//
//  HomeFeedService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Following Feed with Deep Discovery
//  Dependencies: VideoService, UserService, Config, FeedViewHistory
//  Features: Deep time-based discovery, seen-video exclusion, session resume
//  UPDATED: Added view history tracking, deduplication, follower rotation
//
//  NOTE: HomeFeedService shows content from FOLLOWED creators only.
//  Following a creator overrides ALL discovery cool-down signals.
//  Discovery suppression/blocking (via DiscoveryEngagementTracker) does NOT
//  affect the home feed — if you follow someone, their content always shows here.
//

import Foundation
import FirebaseFirestore

/// Following-only feed service with deep discovery and view history
@MainActor
class HomeFeedService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let userService: UserService
    private var viewHistory: FeedViewHistory { FeedViewHistory.shared }
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var lastError: StitchError?
    @Published var feedStats = FeedStats()
    @Published var canResumeSession: Bool = false
    
    // MARK: - Feed State
    
    private var currentFeed: [ThreadData] = []
    private var currentFeedVideoIDs: Set<String> = []  // Fast lookup for deduplication
    private var lastDocument: DocumentSnapshot?
    private var hasMoreContent: Bool = true
    
    // MARK: - Follower Rotation (ensures all followers get coverage)
    
    private var followerRotationIndex: Int = 0
    private var allFollowerIDs: [String] = []
    
    // MARK: - Configuration
    
    private let defaultFeedSize = 40
    private let triggerLoadThreshold = 10
    private let maxCachedThreads = 300
    private let followersPerBatch = 15
    
    // MARK: - Caching for Performance
    
    private var cachedFollowingIDs: [String] = []
    private var followingIDsCacheTime: Date?
    private let followingCacheExpiration: TimeInterval = 300
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService
    ) {
        self.videoService = videoService
        self.userService = userService
        self.canResumeSession = viewHistory.canResumeSession()
        
        print("🏠 HOME FEED: Initialized with view history tracking")
        print(viewHistory.debugStatus())
    }
    
    // MARK: - Session Resume
    
    func checkSessionResume() -> (canResume: Bool, position: FeedPosition?) {
        let canResume = viewHistory.canResumeSession()
        let position = viewHistory.getSavedPosition()
        self.canResumeSession = canResume
        return (canResume, position)
    }
    
    func getLastSessionThreadIDs() -> [String]? {
        return viewHistory.getLastSessionThreadIDs()
    }
    
    func loadThreadsByIDs(_ threadIDs: [String]) async throws -> [ThreadData] {
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        var threads: [ThreadData] = []
        
        for chunk in threadIDs.chunked(into: 10) {
            let query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, in: chunk)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            
            let snapshot = try await query.getDocuments()
            
            for document in snapshot.documents {
                if let thread = try await createParentThreadFromDocument(document) {
                    threads.append(thread)
                }
            }
        }
        
        let threadIDOrder = Dictionary(uniqueKeysWithValues: threadIDs.enumerated().map { ($1, $0) })
        threads.sort { (threadIDOrder[$0.id] ?? Int.max) < (threadIDOrder[$1.id] ?? Int.max) }
        
        return threads
    }
    
    // MARK: - Position Tracking
    
    func saveCurrentPosition(itemIndex: Int, stitchIndex: Int, threadID: String?) {
        viewHistory.saveFeedPosition(itemIndex: itemIndex, stitchIndex: stitchIndex, threadID: threadID)
    }
    
    func saveCurrentFeed(_ threads: [ThreadData]) {
        viewHistory.saveLastSessionFeed(threads)
    }
    
    func clearSessionData() {
        viewHistory.clearFeedPosition()
        viewHistory.clearLastSession()
    }
    
    // MARK: - Video View Tracking
    
    func markVideoSeen(_ videoID: String) {
        viewHistory.markVideoSeen(videoID)
    }
    
    func markVideosSeen(_ videoIDs: [String]) {
        viewHistory.markVideosSeen(videoIDs)
    }
    
    // MARK: - Legacy loadFeed
    
    func loadFeed(userID: String, limit: Int = 40) async throws -> [ThreadData] {
        return try await loadFeedWithDeepDiscovery(userID: userID, limit: limit)
    }
    
    // MARK: - DEEP DISCOVERY - Primary Feed Loading
    
    func loadFeedWithDeepDiscovery(userID: String, limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔍 DEEP DISCOVERY: Loading diverse feed for user \(userID)")
        
        let followingIDs = try await getCachedFollowingIDs(userID: userID)
        guard !followingIDs.isEmpty else {
            print("🔍 DEEP DISCOVERY: No following found")
            return []
        }
        
        allFollowerIDs = followingIDs
        print("🔍 DEEP DISCOVERY: Found \(followingIDs.count) following users")
        
        let recentlySeenIDs = viewHistory.getRecentlySeenVideoIDs()
        print("🔍 DEEP DISCOVERY: Excluding \(recentlySeenIDs.count) recently seen videos")
        
        var allThreads: [ThreadData] = []
        
        let recentThreads = try await getRecentContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.4),
            excludeVideoIDs: recentlySeenIDs
        )
        allThreads.append(contentsOf: recentThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(recentThreads.count) recent threads")
        
        let mediumOldThreads = try await getMediumOldContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.3),
            excludeVideoIDs: recentlySeenIDs
        )
        allThreads.append(contentsOf: mediumOldThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(mediumOldThreads.count) medium-old threads")
        
        let olderThreads = try await getOlderContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.2),
            excludeVideoIDs: recentlySeenIDs
        )
        allThreads.append(contentsOf: olderThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(olderThreads.count) older threads")
        
        let deepCutThreads = try await getDeepCutContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.1),
            excludeVideoIDs: recentlySeenIDs
        )
        allThreads.append(contentsOf: deepCutThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(deepCutThreads.count) deep cut threads")
        
        let dedupedThreads = deduplicateThreads(allThreads)
        let shuffledThreads = dedupedThreads.shuffled()
        
        currentFeed = shuffledThreads
        currentFeedVideoIDs = Set(shuffledThreads.map { $0.parentVideo.id })
        feedStats.totalThreadsLoaded = shuffledThreads.count
        feedStats.lastRefreshTime = Date()
        feedStats.refreshCount += 1
        
        print("✅ DEEP DISCOVERY: Loaded \(shuffledThreads.count) total threads with diverse time range")
        return shuffledThreads
    }
    
    // MARK: - Time-Based Content Loading
    
    private func getRecentContent(followingIDs: [String], limit: Int, excludeVideoIDs: Set<String> = []) async throws -> [ThreadData] {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: sevenDaysAgo,
            endDate: Date(),
            limit: limit,
            excludeVideoIDs: excludeVideoIDs
        )
    }
    
    private func getMediumOldContent(followingIDs: [String], limit: Int, excludeVideoIDs: Set<String> = []) async throws -> [ThreadData] {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: thirtyDaysAgo,
            endDate: sevenDaysAgo,
            limit: limit,
            excludeVideoIDs: excludeVideoIDs
        )
    }
    
    private func getOlderContent(followingIDs: [String], limit: Int, excludeVideoIDs: Set<String> = []) async throws -> [ThreadData] {
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: ninetyDaysAgo,
            endDate: thirtyDaysAgo,
            limit: limit,
            excludeVideoIDs: excludeVideoIDs
        )
    }
    
    private func getDeepCutContent(followingIDs: [String], limit: Int, excludeVideoIDs: Set<String> = []) async throws -> [ThreadData] {
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let veryOld = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: veryOld,
            endDate: ninetyDaysAgo,
            limit: limit,
            excludeVideoIDs: excludeVideoIDs
        )
    }
    
    private func getContentInTimeRange(
        followingIDs: [String],
        startDate: Date,
        endDate: Date,
        limit: Int,
        excludeVideoIDs: Set<String> = []
    ) async throws -> [ThreadData] {
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        let sampledFollowers = getRotatingFollowerBatch(from: followingIDs)
        
        guard !sampledFollowers.isEmpty else { return [] }
        
        let fetchLimit = max(limit * 3, 30)
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, in: sampledFollowers)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThan: Timestamp(date: endDate))
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: fetchLimit)
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        for document in snapshot.documents {
            let videoID = document.data()[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
            if excludeVideoIDs.contains(videoID) { continue }
            if currentFeedVideoIDs.contains(videoID) { continue }
            
            if let thread = try await createParentThreadFromDocument(document) {
                threads.append(thread)
                if threads.count >= limit { break }
            }
        }
        
        return threads
    }
    
    // MARK: - Follower Rotation
    
    private func getRotatingFollowerBatch(from followingIDs: [String]) -> [String] {
        guard !followingIDs.isEmpty else { return [] }
        
        if followingIDs.count <= followersPerBatch {
            return followingIDs
        }
        
        let shuffledFollowers = followingIDs.shuffled()
        let startIndex = followerRotationIndex % shuffledFollowers.count
        
        var batch: [String] = []
        for i in 0..<followersPerBatch {
            let index = (startIndex + i) % shuffledFollowers.count
            batch.append(shuffledFollowers[index])
        }
        
        followerRotationIndex += followersPerBatch
        print("🔄 FOLLOWER ROTATION: Using batch starting at \(startIndex)")
        return batch
    }
    
    private func getSampledFollowers(from followingIDs: [String], count: Int) -> [String] {
        if followingIDs.count <= count { return followingIDs.shuffled() }
        return Array(followingIDs.shuffled().prefix(count))
    }
    
    // MARK: - Deduplication
    
    private func deduplicateThreads(_ threads: [ThreadData]) -> [ThreadData] {
        var seen = Set<String>()
        var result: [ThreadData] = []
        
        for thread in threads {
            if !seen.contains(thread.parentVideo.id) {
                seen.insert(thread.parentVideo.id)
                result.append(thread)
            }
        }
        return result
    }
    
    // MARK: - Load More Content
    
    func loadMoreContent(userID: String) async throws -> [ThreadData] {
        guard hasMoreContent && !isLoading else { return currentFeed }
        
        isLoading = true
        defer { isLoading = false }
        
        let recentlySeenIDs = viewHistory.getRecentlySeenVideoIDs()
        var exclusionSet = recentlySeenIDs
        exclusionSet.formUnion(currentFeedVideoIDs)
        
        let followingIDs = try await getCachedFollowingIDs(userID: userID)
        var newThreads: [ThreadData] = []
        
        let recentBatch = try await getRecentContent(followingIDs: followingIDs, limit: 15, excludeVideoIDs: exclusionSet)
        newThreads.append(contentsOf: recentBatch)
        
        let mediumBatch = try await getMediumOldContent(followingIDs: followingIDs, limit: 10, excludeVideoIDs: exclusionSet)
        newThreads.append(contentsOf: mediumBatch)
        
        let olderBatch = try await getOlderContent(followingIDs: followingIDs, limit: 10, excludeVideoIDs: exclusionSet)
        newThreads.append(contentsOf: olderBatch)
        
        let deepBatch = try await getDeepCutContent(followingIDs: followingIDs, limit: 5, excludeVideoIDs: exclusionSet)
        newThreads.append(contentsOf: deepBatch)
        
        // Single pass: deduplicate while building shuffled result
        var seenIDs = Set<String>()
        var shuffledNew: [ThreadData] = []
        
        for thread in newThreads.shuffled() {
            if !seenIDs.contains(thread.id) {
                seenIDs.insert(thread.id)
                shuffledNew.append(thread)
            }
        }
        
        if !shuffledNew.isEmpty {
            currentFeed.append(contentsOf: shuffledNew)
            currentFeedVideoIDs.formUnion(shuffledNew.map { $0.parentVideo.id })
            feedStats.totalThreadsLoaded = currentFeed.count
            
            if currentFeed.count > maxCachedThreads {
                let threadsToRemove = currentFeed.count - maxCachedThreads
                let removedThreads = currentFeed.prefix(threadsToRemove)
                currentFeed.removeFirst(threadsToRemove)
                for thread in removedThreads {
                    currentFeedVideoIDs.remove(thread.parentVideo.id)
                }
            }
            print("✅ DEEP DISCOVERY: Added \(shuffledNew.count) diverse threads")
        } else {
            hasMoreContent = false
        }
        
        return currentFeed
    }
    
    // MARK: - Thread Creation Helper
    
    private func createParentThreadFromDocument(_ document: DocumentSnapshot) async throws -> ThreadData? {
        guard let data = document.data() else { return nil }
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String ?? id
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int ?? 0
        
        let total = hypeCount + coolCount
        let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
        
        let parentVideo = CoreVideoMetadata(
            id: id, title: title, videoURL: videoURL, thumbnailURL: thumbnailURL,
            creatorID: creatorID, creatorName: creatorName, createdAt: createdAt,
            threadID: threadID, replyToVideoID: nil, conversationDepth: conversationDepth,
            viewCount: viewCount, hypeCount: hypeCount, coolCount: coolCount,
            replyCount: replyCount, shareCount: shareCount, temperature: "neutral",
            qualityScore: 50, engagementRatio: engagementRatio, velocityScore: 0.0,
            trendingScore: 0.0, duration: duration, aspectRatio: aspectRatio,
            fileSize: Int64(fileSize), discoverabilityScore: 0.5, isPromoted: false,
            lastEngagementAt: nil
        )
        
        return ThreadData(id: threadID, parentVideo: parentVideo, childVideos: [])
    }
    
    // MARK: - Following IDs with Caching
    
    func getCachedFollowingIDs(userID: String) async throws -> [String] {
        if let cacheTime = followingIDsCacheTime,
           Date().timeIntervalSince(cacheTime) < followingCacheExpiration,
           !cachedFollowingIDs.isEmpty {
            return cachedFollowingIDs
        }
        
        let followingIDs = try await userService.getFollowingIDs(userID: userID)
        cachedFollowingIDs = followingIDs
        followingIDsCacheTime = Date()
        return followingIDs
    }
    
    func clearFollowingCache() {
        cachedFollowingIDs = []
        followingIDsCacheTime = nil
    }
    
    // MARK: - Feed State Management
    
    func getCurrentFeed() -> [ThreadData] { return currentFeed }
    
    func shouldLoadMore(currentIndex: Int) -> Bool {
        let remainingThreads = currentFeed.count - currentIndex
        return remainingThreads <= triggerLoadThreshold && hasMoreContent && !isLoading
    }
    
    func clearFeed() {
        currentFeed = []
        currentFeedVideoIDs.removeAll()
        lastDocument = nil
        hasMoreContent = true
        followerRotationIndex = 0
        feedStats = FeedStats()
    }
    
    func getReshuffledFeed(userID: String) async throws -> [ThreadData] {
        clearFollowingCache()
        followerRotationIndex = 0
        currentFeedVideoIDs.removeAll()
        return try await loadFeedWithDeepDiscovery(userID: userID, limit: defaultFeedSize)
    }
    
    // MARK: - Load Thread Children
    
    func loadThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.conversationDepth, descending: false)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        var children: [CoreVideoMetadata] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
            let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
            let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
            let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
            let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
            let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
            let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
            let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
            let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
            
            let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
            let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
            let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
            let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
            let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
            
            let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
            let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
            let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int ?? 0
            
            let total = hypeCount + coolCount
            let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
            
            let childVideo = CoreVideoMetadata(
                id: id, title: title, videoURL: videoURL, thumbnailURL: thumbnailURL,
                creatorID: creatorID, creatorName: creatorName, createdAt: createdAt,
                threadID: threadID, replyToVideoID: replyToVideoID, conversationDepth: conversationDepth,
                viewCount: viewCount, hypeCount: hypeCount, coolCount: coolCount,
                replyCount: replyCount, shareCount: shareCount, temperature: "neutral",
                qualityScore: 50, engagementRatio: engagementRatio, velocityScore: 0.0,
                trendingScore: 0.0, duration: duration, aspectRatio: aspectRatio,
                fileSize: Int64(fileSize), discoverabilityScore: 0.5, isPromoted: false,
                lastEngagementAt: nil
            )
            children.append(childVideo)
        }
        
        print("✅ HOME FEED: Loaded \(children.count) children for thread \(threadID)")
        return children
    }
}

// MARK: - Feed Statistics

struct FeedStats: Codable {
    var totalThreadsLoaded: Int = 0
    var lastRefreshTime: Date?
    var refreshCount: Int = 0
    
    var timesSinceRefresh: TimeInterval? {
        guard let lastRefresh = lastRefreshTime else { return nil }
        return Date().timeIntervalSince(lastRefresh)
    }
}
