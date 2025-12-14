//
//  HomeFeedService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Following Feed with Deep Discovery
//  Dependencies: VideoService, UserService, Config
//  Features: Deep time-based discovery, varied content, lazy loading
//  UPDATED: Integrated deep discovery for diverse content mix
//

import Foundation
import FirebaseFirestore

/// Following-only feed service with deep discovery for varied content
@MainActor
class HomeFeedService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let userService: UserService
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var lastError: StitchError?
    @Published var feedStats = FeedStats()
    
    // MARK: - Feed State
    
    private var currentFeed: [ThreadData] = []
    private var lastDocument: DocumentSnapshot?
    private var hasMoreContent: Bool = true
    
    // MARK: - Configuration
    
    private let defaultFeedSize = 40
    private let triggerLoadThreshold = 10
    private let maxCachedThreads = 300
    
    // MARK: - Caching for Performance
    
    private var cachedFollowingIDs: [String] = []
    private var followingIDsCacheTime: Date?
    private let followingCacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService
    ) {
        self.videoService = videoService
        self.userService = userService
        
        print("🏠 HOME FEED: Initialized with deep discovery strategy")
    }
    
    // MARK: - DEEP DISCOVERY - Primary Feed Loading
    
    /// Load feed with deep discovery - mix of recent, older, and varied content
    func loadFeedWithDeepDiscovery(userID: String, limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔍 DEEP DISCOVERY: Loading diverse feed for user \(userID)")
        
        // Step 1: Get following IDs
        let followingIDs = try await getCachedFollowingIDs(userID: userID)
        guard !followingIDs.isEmpty else {
            print("🔍 DEEP DISCOVERY: No following found")
            return []
        }
        
        print("🔍 DEEP DISCOVERY: Found \(followingIDs.count) following users")
        
        // Step 2: Get diverse content mix
        var allThreads: [ThreadData] = []
        
        // 40% Recent content (last 7 days)
        let recentThreads = try await getRecentContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.4)
        )
        allThreads.append(contentsOf: recentThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(recentThreads.count) recent threads")
        
        // 30% Medium-old content (7-30 days)
        let mediumOldThreads = try await getMediumOldContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.3)
        )
        allThreads.append(contentsOf: mediumOldThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(mediumOldThreads.count) medium-old threads")
        
        // 20% Older content (30-90 days)
        let olderThreads = try await getOlderContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.2)
        )
        allThreads.append(contentsOf: olderThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(olderThreads.count) older threads")
        
        // 10% Random deep cuts (90+ days)
        let deepCutThreads = try await getDeepCutContent(
            followingIDs: followingIDs,
            limit: Int(Double(limit) * 0.1)
        )
        allThreads.append(contentsOf: deepCutThreads)
        print("🔍 DEEP DISCOVERY: Loaded \(deepCutThreads.count) deep cut threads")
        
        // Step 3: Shuffle for variety
        let shuffledThreads = allThreads.shuffled()
        
        // Step 4: Update state
        currentFeed = shuffledThreads
        feedStats.totalThreadsLoaded = shuffledThreads.count
        feedStats.lastRefreshTime = Date()
        feedStats.refreshCount += 1
        
        print("✅ DEEP DISCOVERY: Loaded \(shuffledThreads.count) total threads with diverse time range")
        return shuffledThreads
    }
    
    // MARK: - Time-Based Content Loading
    
    /// Get recent content (last 7 days)
    private func getRecentContent(followingIDs: [String], limit: Int) async throws -> [ThreadData] {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: sevenDaysAgo,
            endDate: Date(),
            limit: limit
        )
    }
    
    /// Get medium-old content (7-30 days)
    private func getMediumOldContent(followingIDs: [String], limit: Int) async throws -> [ThreadData] {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: thirtyDaysAgo,
            endDate: sevenDaysAgo,
            limit: limit
        )
    }
    
    /// Get older content (30-90 days)
    private func getOlderContent(followingIDs: [String], limit: Int) async throws -> [ThreadData] {
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: ninetyDaysAgo,
            endDate: thirtyDaysAgo,
            limit: limit
        )
    }
    
    /// Get deep cut content (90+ days old)
    private func getDeepCutContent(followingIDs: [String], limit: Int) async throws -> [ThreadData] {
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let veryOld = Date().addingTimeInterval(-365 * 24 * 60 * 60) // Up to 1 year old
        return try await getContentInTimeRange(
            followingIDs: followingIDs,
            startDate: veryOld,
            endDate: ninetyDaysAgo,
            limit: limit
        )
    }
    
    /// Core method to get content in a specific time range
    private func getContentInTimeRange(
        followingIDs: [String],
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [ThreadData] {
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        // Sample different followers each time for variety
        let sampledFollowers = getSampledFollowers(from: followingIDs, count: 30)
        
        guard !sampledFollowers.isEmpty else { return [] }
        
        // Query with time range
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, in: sampledFollowers)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThan: Timestamp(date: endDate))
            .limit(to: limit * 2) // Get more to account for filtering
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        for document in snapshot.documents {
            if let thread = try await createParentThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        // Shuffle and limit
        return Array(threads.shuffled().prefix(limit))
    }
    
    /// Sample random followers for variety
    private func getSampledFollowers(from followingIDs: [String], count: Int) -> [String] {
        if followingIDs.count <= count {
            return followingIDs.shuffled()
        }
        
        // Random sample - different each time
        return Array(followingIDs.shuffled().prefix(count))
    }
    
    // MARK: - Legacy Methods (Keep for compatibility)
    
    /// Load initial following feed - NOW USES DEEP DISCOVERY
    func loadFeed(userID: String, limit: Int = 40) async throws -> [ThreadData] {
        // Redirect to deep discovery
        return try await loadFeedWithDeepDiscovery(userID: userID, limit: limit)
    }
    
    /// Refresh feed - NOW USES DEEP DISCOVERY
    func refreshFeed(userID: String) async throws -> [ThreadData] {
        isRefreshing = true
        defer { isRefreshing = false }
        
        print("🔄 HOME FEED: Refreshing with deep discovery")
        
        // Clear cache for fresh data
        cachedFollowingIDs = []
        followingIDsCacheTime = nil
        
        return try await loadFeedWithDeepDiscovery(userID: userID, limit: defaultFeedSize)
    }
    
    /// Load more content - NOW USES DEEP DISCOVERY
    func loadMoreContent(userID: String) async throws -> [ThreadData] {
        
        guard hasMoreContent && !isLoading else {
            print("🔍 DEEP DISCOVERY: No more content or already loading")
            return currentFeed
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔍 DEEP DISCOVERY: Loading more diverse content")
        
        // Load another diverse batch
        let nextBatch = try await loadFeedWithDeepDiscovery(userID: userID, limit: defaultFeedSize)
        
        if !nextBatch.isEmpty {
            currentFeed.append(contentsOf: nextBatch)
            feedStats.totalThreadsLoaded = currentFeed.count
            
            // Memory management
            if currentFeed.count > maxCachedThreads {
                let threadsToRemove = currentFeed.count - maxCachedThreads
                currentFeed.removeFirst(threadsToRemove)
                print("🧹 DEEP DISCOVERY: Cleaned \(threadsToRemove) old threads")
            }
            
            print("✅ DEEP DISCOVERY: Added \(nextBatch.count) diverse threads, total: \(currentFeed.count)")
        } else {
            hasMoreContent = false
            print("🏁 DEEP DISCOVERY: No more content available")
        }
        
        return currentFeed
    }
    
    // MARK: - Thread Creation Helper
    
    /// Create ThreadData with PARENT ONLY (no children loading) - FIXED FOR SPEED
    private func createParentThreadFromDocument(_ document: DocumentSnapshot) async throws -> ThreadData? {
        
        let data = document.data()
        guard let data = data else { return nil }
        
        // Extract parent video data
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String ?? id
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        // Engagement metrics
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        // Video metadata
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int ?? 0
        
        let total = hypeCount + coolCount
        let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
        
        // Create parent video
        let parentVideo = CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: nil,
            conversationDepth: conversationDepth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: engagementRatio,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: Int64(fileSize),
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
        
        // Create thread with empty children (loaded lazily)
        return ThreadData(
            id: threadID,
            parentVideo: parentVideo,
            childVideos: [] // Empty - loaded on demand
        )
    }
    
    // MARK: - Following IDs with Caching
    
    /// Get following IDs with 5-minute cache
    func getCachedFollowingIDs(userID: String) async throws -> [String] {
        
        // Check cache first
        if let cacheTime = followingIDsCacheTime,
           Date().timeIntervalSince(cacheTime) < followingCacheExpiration,
           !cachedFollowingIDs.isEmpty {
            print("🏠 HOME FEED: Using cached following IDs (\(cachedFollowingIDs.count))")
            return cachedFollowingIDs
        }
        
        // Fetch fresh
        print("🏠 HOME FEED: Fetching fresh following IDs...")
        let followingIDs = try await userService.getFollowingIDs(userID: userID)
        
        // Update cache
        cachedFollowingIDs = followingIDs
        followingIDsCacheTime = Date()
        
        print("✅ HOME FEED: Cached \(followingIDs.count) following IDs")
        return followingIDs
    }
    
    /// Clear following cache (call when user follows/unfollows)
    func clearFollowingCache() {
        cachedFollowingIDs = []
        followingIDsCacheTime = nil
        print("🧹 HOME FEED: Cleared following cache")
    }
    
    // MARK: - Feed State Management
    
    /// Get current feed
    func getCurrentFeed() -> [ThreadData] {
        return currentFeed
    }
    
    /// Check if should trigger load
    func shouldLoadMore(currentIndex: Int) -> Bool {
        let remainingThreads = currentFeed.count - currentIndex
        return remainingThreads <= triggerLoadThreshold && hasMoreContent && !isLoading
    }
    
    /// Clear all state
    func clearFeed() {
        currentFeed = []
        lastDocument = nil
        hasMoreContent = true
        feedStats = FeedStats()
        print("🧹 HOME FEED: Cleared all state")
    }
    
    // MARK: - Additional Feed Operations
    
    /// Reshuffle current feed for variety
    func getReshuffledFeed(userID: String) async throws -> [ThreadData] {
        print("🔀 HOME FEED: Reshuffling feed with new deep discovery mix")
        
        // Clear cache to get fresh followers
        clearFollowingCache()
        
        // Load new diverse batch
        return try await loadFeedWithDeepDiscovery(userID: userID, limit: defaultFeedSize)
    }
    
    /// Load children for a thread (lazy loading)
    func loadThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        print("👶 HOME FEED: Loading children for thread \(threadID)")
        
        // Query for child videos
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.conversationDepth, descending: false)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .limit(to: 50) // Reasonable limit for thread children
        
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
            
            // Engagement metrics
            let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
            let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
            let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
            let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
            let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
            
            // Video metadata
            let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
            let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
            let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int ?? 0
            
            let total = hypeCount + coolCount
            let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
            
            let childVideo = CoreVideoMetadata(
                id: id,
                title: title,
                videoURL: videoURL,
                thumbnailURL: thumbnailURL,
                creatorID: creatorID,
                creatorName: creatorName,
                createdAt: createdAt,
                threadID: threadID,
                replyToVideoID: replyToVideoID,
                conversationDepth: conversationDepth,
                viewCount: viewCount,
                hypeCount: hypeCount,
                coolCount: coolCount,
                replyCount: replyCount,
                shareCount: shareCount,
                temperature: "neutral",
                qualityScore: 50,
                engagementRatio: engagementRatio,
                velocityScore: 0.0,
                trendingScore: 0.0,
                duration: duration,
                aspectRatio: aspectRatio,
                fileSize: Int64(fileSize),
                discoverabilityScore: 0.5,
                isPromoted: false,
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
