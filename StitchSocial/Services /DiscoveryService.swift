//
//  DiscoveryService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Discovery with Deep Time-Based Randomization
//  Dependencies: RecentUser.swift (RecentUser, LeaderboardVideo models)
//  FIXED: getRecentUsers and getHypeLeaderboard now use simple queries
//         that don't require composite Firestore indexes
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// NOTE: RecentUser and LeaderboardVideo are defined in RecentUser.swift

// MARK: - Discovery Service

@MainActor
class DiscoveryService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Session Tracking
    
    private var loadedVideoIDs: Set<String> = []
    private var allFetchedVideos: [ThreadData] = []
    private var lastDocument: DocumentSnapshot?
    private var isDatabaseExhausted: Bool = false
    private var reshuffleIndex: Int = 0
    
    // MARK: - Main Discovery Method
    
    func getDeepRandomizedDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        if isDatabaseExhausted && !allFetchedVideos.isEmpty {
            return getFromReshuffledCache(limit: limit)
        }
        
        print("🔍 DISCOVERY: Fetching \(limit) videos (loaded so far: \(loadedVideoIDs.count))")
        
        var newThreads: [ThreadData] = []
        var attempts = 0
        let maxAttempts = 10
        
        while newThreads.count < limit && attempts < maxAttempts {
            attempts += 1
            
            var query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 100)
            
            if let cursor = lastDocument {
                query = query.start(afterDocument: cursor)
            }
            
            let snapshot = try await query.getDocuments()
            
            if snapshot.documents.isEmpty {
                print("📭 DISCOVERY: Database exhausted - all \(allFetchedVideos.count) videos loaded")
                isDatabaseExhausted = true
                
                if !newThreads.isEmpty {
                    break
                }
                
                return getFromReshuffledCache(limit: limit)
            }
            
            lastDocument = snapshot.documents.last
            
            for document in snapshot.documents {
                let videoID = document.data()[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
                
                guard !loadedVideoIDs.contains(videoID) else { continue }
                
                // Skip collection segments — they appear in Collections tab only
                if document.data()["isCollectionSegment"] as? Bool == true { continue }
                
                if let thread = createThreadFromDocument(document) {
                    newThreads.append(thread)
                    loadedVideoIDs.insert(videoID)
                    allFetchedVideos.append(thread)
                    
                    if newThreads.count >= limit {
                        break
                    }
                }
            }
            
            print("🔍 Batch \(attempts): found \(newThreads.count)/\(limit) new videos")
        }
        
        let shuffled = ultraShuffleByCreator(threads: newThreads)
        
        print("✅ DISCOVERY: Returning \(shuffled.count) videos (total in DB: \(allFetchedVideos.count))")
        
        return shuffled
    }
    
    private func getFromReshuffledCache(limit: Int) -> [ThreadData] {
        if reshuffleIndex == 0 {
            print("🔄 DISCOVERY: Reshuffling all \(allFetchedVideos.count) videos for fresh loop")
            allFetchedVideos = ultraShuffleByCreator(threads: allFetchedVideos)
        }
        
        let startIndex = reshuffleIndex
        let endIndex = min(reshuffleIndex + limit, allFetchedVideos.count)
        
        let batch = Array(allFetchedVideos[startIndex..<endIndex])
        
        reshuffleIndex = endIndex
        
        if reshuffleIndex >= allFetchedVideos.count {
            print("🔄 DISCOVERY: Completed full loop, will reshuffle on next fetch")
            reshuffleIndex = 0
        }
        
        print("✅ DISCOVERY (cache): Returning \(batch.count) videos (position \(startIndex)-\(endIndex) of \(allFetchedVideos.count))")
        
        return batch
    }
    
    private func ultraShuffleByCreator(threads: [ThreadData]) -> [ThreadData] {
        guard threads.count > 1 else { return threads }
        
        var creatorBuckets: [String: [ThreadData]] = [:]
        for thread in threads {
            creatorBuckets[thread.parentVideo.creatorID, default: []].append(thread)
        }
        
        var shuffledBuckets = creatorBuckets.mapValues { $0.shuffled() }
        var result: [ThreadData] = []
        var recentCreators: [String] = []
        let avoidWindow = min(5, max(1, creatorBuckets.count - 1))
        
        while !shuffledBuckets.isEmpty {
            let available = shuffledBuckets.keys.filter { !recentCreators.suffix(avoidWindow).contains($0) }
            let chosen = available.randomElement() ?? shuffledBuckets.keys.randomElement()!
            
            if var bucket = shuffledBuckets[chosen], !bucket.isEmpty {
                result.append(bucket.removeFirst())
                recentCreators.append(chosen)
                
                if bucket.isEmpty {
                    shuffledBuckets.removeValue(forKey: chosen)
                } else {
                    shuffledBuckets[chosen] = bucket
                }
            }
        }
        
        return result
    }
    
    // MARK: - Thread Creation
    
    private func createThreadFromDocument(_ document: DocumentSnapshot) -> ThreadData? {
        guard let data = document.data() else { return nil }
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        guard !id.isEmpty else { return nil }
        
        // Privacy filter: skip non-public or discovery-excluded videos
        let visibility = data["visibility"] as? String ?? "public"
        let excludeFromDiscovery = data["excludeFromDiscovery"] as? Bool ?? false
        
        if visibility != "public" || excludeFromDiscovery {
            return nil
        }
        
        // Teen safety: teen users only see teenSafe content
        if PrivacyService.shared.cachedAgeGroup == .teen {
            let teenSafe = data["teenSafe"] as? Bool ?? false
            if !teenSafe { return nil }
        }
        
        let parentVideo = createCoreVideoMetadata(from: data, id: id)
        return ThreadData(id: id, parentVideo: parentVideo, childVideos: [])
    }
    
    private func createCoreVideoMetadata(from data: [String: Any], id: String) -> CoreVideoMetadata {
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let engagementRatio = hypeCount + coolCount > 0 ? Double(hypeCount) / Double(hypeCount + coolCount) : 0.5
        
        return CoreVideoMetadata(
            id: id,
            title: data[FirebaseSchema.VideoDocument.title] as? String ?? "",
            description: data[FirebaseSchema.VideoDocument.description] as? String ?? "",
            taggedUserIDs: data[FirebaseSchema.VideoDocument.taggedUserIDs] as? [String] ?? [],
            videoURL: data[FirebaseSchema.VideoDocument.videoURL] as? String ?? "",
            thumbnailURL: data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? "",
            creatorID: data[FirebaseSchema.VideoDocument.creatorID] as? String ?? "",
            creatorName: data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown",
            createdAt: (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date(),
            threadID: data[FirebaseSchema.VideoDocument.threadID] as? String ?? id,
            replyToVideoID: data[FirebaseSchema.VideoDocument.replyToVideoID] as? String,
            conversationDepth: data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0,
            viewCount: data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0,
            shareCount: data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0,
            temperature: data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral",
            qualityScore: data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50,
            engagementRatio: engagementRatio,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0,
            aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0,
            fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
            discoverabilityScore: data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5,
            isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue(),
            collectionID: data["collectionID"] as? String,
            segmentNumber: data["segmentNumber"] as? Int,
            segmentTitle: data["segmentTitle"] as? String,
            isCollectionSegment: data["isCollectionSegment"] as? Bool ?? false,
            replyTimestamp: data["replyTimestamp"] as? TimeInterval
        )
    }
    
    // MARK: - Category Methods
    
    func getTrendingDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        // Simple query - fetch recent videos, sort by discoverabilityScore in memory
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 3)  // Fetch more to filter/sort in memory
            .getDocuments()
        
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any],
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue(),
                  createdAt >= sevenDaysAgo else {
                continue
            }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
            }
        }
        
        // Sort by discoverabilityScore (highest first) - true trending content
        // discoverabilityScore factors in: quality, temperature, recency, velocity, recording source
        let sorted = threads.sorted { $0.parentVideo.discoverabilityScore > $1.parentVideo.discoverabilityScore }
        
        print("🔥 TRENDING: Returning \(min(limit, sorted.count)) videos sorted by discoverabilityScore")
        return Array(sorted.prefix(limit))
    }
    
    func getPopularDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { createThreadFromDocument($0) }
    }
    
    func getRecentDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        
        // Simple query - fetch by createdAt, filter in memory
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 2)
            .getDocuments()
        
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any],
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue(),
                  createdAt >= twentyFourHoursAgo else {
                continue
            }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
            }
            
            if threads.count >= limit {
                break
            }
        }
        
        print("🕐 RECENT: Returning \(threads.count) videos from last 24h")
        return threads.shuffled()
    }
    
    func getDiscoveryParentThreadsOnly(limit: Int = 40, lastDocument: DocumentSnapshot? = nil) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        let threads = try await getDeepRandomizedDiscovery(limit: limit)
        return (threads: threads, lastDocument: nil, hasMore: !isDatabaseExhausted || !allFetchedVideos.isEmpty)
    }
    
    // MARK: - Recent Users (FIXED: Simple query, no composite index needed)
    
    /// Get recently joined users
    /// FIXED: Uses simple createdAt order only, filters isPrivate in memory
    func getRecentUsers(limit: Int = 20) async throws -> [RecentUser] {
        isLoading = true
        defer { isLoading = false }
        
        print("🆕 DISCOVERY: Fetching recent users...")
        
        // Simple query - just order by createdAt, no compound filters
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
            .limit(to: limit * 3)  // Fetch more to filter in memory
            .getDocuments()
        
        print("🆕 DISCOVERY: Got \(snapshot.documents.count) user documents")
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        var recentUsers: [RecentUser] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            // Filter: must have required fields
            guard let username = data[FirebaseSchema.UserDocument.username] as? String,
                  let displayName = data[FirebaseSchema.UserDocument.displayName] as? String,
                  let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() else {
                print("⚠️ DISCOVERY: Skipping user \(doc.documentID) - missing required fields")
                continue
            }
            
            // Filter: must be within 7 days
            guard createdAt >= sevenDaysAgo else {
                continue
            }
            
            // Filter: must not be private (filter in memory)
            let isPrivate = data[FirebaseSchema.UserDocument.isPrivate] as? Bool ?? false
            guard !isPrivate else {
                continue
            }
            
            let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
            let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
            
            recentUsers.append(RecentUser(
                id: doc.documentID,
                username: username,
                displayName: displayName,
                profileImageURL: profileImageURL,
                joinedAt: createdAt,
                isVerified: isVerified
            ))
            
            if recentUsers.count >= limit {
                break
            }
        }
        
        print("✅ DISCOVERY: Found \(recentUsers.count) recent users (last 7 days, public)")
        return recentUsers
    }
    
    // MARK: - Hype Leaderboard (FIXED: Simple query, no composite index needed)
    
    /// Get top videos by hype count
    /// FIXED: Uses simple hypeCount order, filters by date in memory
    func getHypeLeaderboard(limit: Int = 10) async throws -> [LeaderboardVideo] {
        isLoading = true
        defer { isLoading = false }
        
        print("🔥 DISCOVERY: Fetching hype leaderboard...")
        
        // Simple query - just order by hypeCount, no compound filters
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit * 3)  // Fetch more to filter in memory
            .getDocuments()
        
        print("🔥 DISCOVERY: Got \(snapshot.documents.count) video documents")
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        var leaderboardVideos: [LeaderboardVideo] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            // Filter: must have required fields
            guard let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String,
                  let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String,
                  let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int,
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() else {
                print("⚠️ DISCOVERY: Skipping video \(doc.documentID) - missing required fields")
                continue
            }
            
            // Filter: must be within 7 days
            guard createdAt >= sevenDaysAgo else {
                continue
            }
            
            // Filter: must have at least 1 hype
            guard hypeCount > 0 else {
                continue
            }
            
            let title = data[FirebaseSchema.VideoDocument.title] as? String ?? "Untitled"
            let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
            let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
            let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String
            
            leaderboardVideos.append(LeaderboardVideo(
                id: doc.documentID,
                title: title,
                creatorID: creatorID,
                creatorName: creatorName,
                thumbnailURL: thumbnailURL,
                hypeCount: hypeCount,
                coolCount: coolCount,
                temperature: temperature,
                createdAt: createdAt
            ))
            
            if leaderboardVideos.count >= limit {
                break
            }
        }
        
        print("✅ DISCOVERY: Found \(leaderboardVideos.count) leaderboard videos (last 7 days, hyped)")
        return leaderboardVideos
    }
    
    // MARK: - Algorithm Lanes
    
    /// Following feed — videos from users the current user follows.
    /// BATCHING: Uses PrivacyService cached following IDs (0 extra reads if cached).
    /// Firestore IN query limited to 10, so chunked for users following many people.
    func getFollowingFeed(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let followingIDs: [String]
        if !PrivacyService.shared.cachedFollowingIDs.isEmpty {
            followingIDs = Array(PrivacyService.shared.cachedFollowingIDs)
        } else {
            guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return [] }
            followingIDs = try await UserService().getFollowingIDs(userID: uid)
        }
        
        guard !followingIDs.isEmpty else { return [] }
        
        // Firestore IN supports max 10
        var allThreads: [ThreadData] = []
        let chunks = stride(from: 0, to: min(followingIDs.count, 30), by: 10).map {
            Array(followingIDs[$0..<min($0 + 10, followingIDs.count)])
        }
        
        for chunk in chunks {
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, in: chunk)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
                .getDocuments()
            
            for doc in snapshot.documents {
                if let thread = createThreadFromDocument(doc) {
                    allThreads.append(thread)
                }
            }
        }
        
        // Sort by date, deduplicate, take limit
        let sorted = allThreads
            .sorted { $0.parentVideo.createdAt > $1.parentVideo.createdAt }
        let seen = NSMutableSet()
        let deduped = sorted.filter { seen.add($0.id) != nil ? false : true }
        
        print("❤️ FOLLOWING: Returning \(min(limit, deduped.count)) videos from followed creators")
        return Array(deduped.prefix(limit))
    }
    
    /// Hot Hashtags — videos from trending hashtags.
    /// Reuses HashtagService trending list, then fetches videos matching top tags.
    func getHotHashtagDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let hashtagService = HashtagService()
        await hashtagService.loadTrendingHashtags(limit: 5)
        let topTags = hashtagService.trendingHashtags.map { $0.tag }
        
        guard !topTags.isEmpty else {
            return try await getTrendingDiscovery(limit: limit)
        }
        
        var allThreads: [ThreadData] = []
        
        for tag in topTags.prefix(3) {
            let result = try await hashtagService.getVideosForHashtag(tag, limit: 15)
            for video in result.videos {
                let thread = ThreadData(id: video.id, parentVideo: video, childVideos: [])
                allThreads.append(thread)
            }
        }
        
        let shuffled = allThreads.shuffled()
        print("#️⃣ HOT HASHTAGS: Returning \(min(limit, shuffled.count)) videos from trending tags")
        return Array(shuffled.prefix(limit))
    }
    
    /// Heat Check — only BLAZING and HOT temperature videos.
    /// Single query with in-memory temperature filter.
    func getHeatCheckDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 4)
            .getDocuments()
        
        var threads: [ThreadData] = []
        let hotTemps: Set<String> = ["blazing", "hot"]
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any],
                  let temp = data[FirebaseSchema.VideoDocument.temperature] as? String,
                  hotTemps.contains(temp.lowercased()) else { continue }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
                if threads.count >= limit { break }
            }
        }
        
        print("🌡️ HEAT CHECK: Returning \(threads.count) blazing/hot videos")
        return threads.shuffled()
    }
    
    /// Undiscovered — low view count videos from newer/smaller creators.
    /// Surfaces content that hasn't gotten attention yet.
    func getUndiscoveredDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        // Fetch recent videos sorted by oldest first (less likely to be seen)
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.viewCount)
            .limit(to: limit * 3)
            .getDocuments()
        
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any] else { continue }
            let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
            
            // Only include low-view videos (under 50 views)
            guard viewCount < 50 else { continue }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
                if threads.count >= limit { break }
            }
        }
        
        print("🔭 UNDISCOVERED: Returning \(threads.count) low-view videos")
        return threads.shuffled()
    }
    
    /// Longest Threads — threads with the most replies (deep conversations).
    func getLongestThreadsDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.replyCount, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let threads = snapshot.documents.compactMap { createThreadFromDocument($0) }
        
        print("💬 LONGEST THREADS: Returning \(threads.count) most-replied threads")
        return threads
    }
    
    /// Spin-Offs — videos that are remixes/spin-offs of other content.
    /// Filters for non-nil spinOffFromVideoID in memory since Firestore can't query != nil easily.
    func getSpinOffDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 5)
            .getDocuments()
        
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any],
                  let spinOffID = data["spinOffFromVideoID"] as? String,
                  !spinOffID.isEmpty else { continue }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
                if threads.count >= limit { break }
            }
        }
        
        print("🔀 SPIN-OFFS: Returning \(threads.count) spin-off videos")
        return threads.shuffled()
    }
    
    // MARK: - Collection Discovery Lanes
    
    /// Fetch published collections by content type.
    /// CACHING: Results cached in DiscoveryViewModel for session. 1 query per lane.
    func getCollectionsByType(_ types: [String], limit: Int = 20) async throws -> [VideoCollection] {
        guard !types.isEmpty else { return [] }
        
        let snapshot = try await db.collection("videoCollections")
            .whereField("status", isEqualTo: "published")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "publishedAt", descending: true)
            .limit(to: limit * 2)
            .getDocuments()
        
        var collections: [VideoCollection] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            let contentType = data["contentType"] as? String ?? "standard"
            
            // Filter by requested types
            guard types.contains(contentType) else { continue }
            
            if let collection = parseVideoCollection(from: data, id: doc.documentID) {
                collections.append(collection)
                if collections.count >= limit { break }
            }
        }
        
        print("🎬 COLLECTIONS: Returning \(collections.count) collections for types: \(types)")
        return collections
    }
    
    /// Podcast discovery — podcasts + interviews
    /// All collections discovery — all published public collections sorted by recency
    /// CACHING: Results cached in DiscoveryViewModel.discoveryCollections, refreshed on tab tap.
    /// Single Firestore read per tab selection.
    func getAllCollectionsDiscovery(limit: Int = 30) async throws -> [VideoCollection] {
        let snapshot = try await db.collection("videoCollections")
            .whereField("status", isEqualTo: "published")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let collections = snapshot.documents.compactMap { parseVideoCollection(from: $0.data(), id: $0.documentID) }
        print("📚 DISCOVERY: Loaded \(collections.count) collections for discovery")
        return collections
    }
    
    /// Podcasts discovery — interviews + podcasts
    func getPodcastDiscovery(limit: Int = 20) async throws -> [VideoCollection] {
        return try await getCollectionsByType(["podcast", "interview"], limit: limit)
    }
    
    /// Films discovery — short films + documentaries
    func getFilmsDiscovery(limit: Int = 20) async throws -> [VideoCollection] {
        return try await getCollectionsByType(["shortFilm", "documentary"], limit: limit)
    }
    
    // MARK: - Collection Parsing Helper
    
    private func parseVideoCollection(from data: [String: Any], id: String) -> VideoCollection? {
        let title = data["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        
        return VideoCollection(
            id: id,
            title: title,
            description: data["description"] as? String ?? "",
            creatorID: data["creatorID"] as? String ?? "",
            creatorName: data["creatorName"] as? String ?? "",
            coverImageURL: data["thumbnailURL"] as? String ?? data["coverImageURL"] as? String,
            segmentIDs: data["segmentVideoIDs"] as? [String] ?? [],
            segmentCount: data["segmentCount"] as? Int ?? 0,
            totalDuration: data["totalDuration"] as? TimeInterval ?? 0,
            status: CollectionStatus(rawValue: data["status"] as? String ?? "") ?? .published,
            visibility: CollectionVisibility(rawValue: data["visibility"] as? String ?? "") ?? .publicVisible,
            allowReplies: data["allowReplies"] as? Bool ?? true,
            contentType: CollectionContentType(rawValue: data["contentType"] as? String ?? "") ?? .standard,
            allowStitchReplies: data["allowStitchReplies"] as? Bool,
            publishedAt: (data["publishedAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            totalViews: data["totalViews"] as? Int ?? 0,
            totalHypes: data["totalHypes"] as? Int ?? 0,
            totalCools: data["totalCools"] as? Int ?? 0,
            totalReplies: data["totalReplies"] as? Int ?? 0,
            totalShares: data["totalShares"] as? Int ?? 0
        )
    }
}
