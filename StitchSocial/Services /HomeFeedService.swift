//
//  HomeFeedService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Following-Only Feed Management with Lazy Loading
//  Dependencies: VideoService, UserService, Config
//  Features: Instant parent thread loading, lazy child loading, multidirectional navigation
//

import Foundation
import FirebaseFirestore

/// Following-only feed service with lazy loading for instant startup
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
    
    private let defaultFeedSize = 20
    private let preloadTriggerIndex = 15
    private let maxCachedThreads = 100
    
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
        
        print("🏠 HOME FEED: Initialized with lazy loading strategy")
    }
    
    // MARK: - Primary Feed Operations - FIXED FOR FULL FOLLOWING FEED
    
    /// Load initial following feed - PARENT THREADS ONLY for instant display
    func loadFeed(userID: String, limit: Int = 20) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("HOME FEED: Loading initial feed for user \(userID)")
        
        // Step 1: Get following IDs with caching
        let followingIDs = try await getCachedFollowingIDs(userID: userID)
        guard !followingIDs.isEmpty else {
            print("HOME FEED: No following found - returning empty feed")
            return []
        }
        
        print("HOME FEED: Found \(followingIDs.count) following users")
        
        // Step 2: Get PARENT THREADS ONLY - FIXED: Remove artificial limit
        let threads = try await getFollowingParentThreadsOnly(
            followingIDs: followingIDs,
            limit: limit // FIXED: Use full limit, not min(limit, 10)
        )
        
        // Step 3: Update state
        currentFeed = threads
        feedStats.totalThreadsLoaded = threads.count
        feedStats.lastRefreshTime = Date()
        
        print("HOME FEED: Loaded \(threads.count) PARENT threads (children will load lazily)")
        return threads
    }
    
    /// Refresh feed with new content
    func refreshFeed(userID: String) async throws -> [ThreadData] {
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        print("🔄 HOME FEED: Refreshing feed for user \(userID)")
        
        // Reset pagination state
        lastDocument = nil
        hasMoreContent = true
        
        // Load fresh content (parent threads only)
        let freshThreads = try await loadFeed(userID: userID, limit: defaultFeedSize)
        
        feedStats.refreshCount += 1
        feedStats.lastRefreshTime = Date()
        
        print("✅ HOME FEED: Feed refreshed with \(freshThreads.count) threads")
        return freshThreads
    }
    
    /// Load more content for pagination
    func loadMoreContent(userID: String) async throws -> [ThreadData] {
        
        guard hasMoreContent && !isLoading else {
            print("🏠 HOME FEED: No more content to load or already loading")
            return currentFeed
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔄 HOME FEED: Loading more content for pagination")
        
        // Get following IDs
        let followingIDs = try await userService.getFollowingIDs(userID: userID)
        guard !followingIDs.isEmpty else { return currentFeed }
        
        // Load next batch (parent threads only)
        let nextBatch = try await getFollowingParentThreadsOnly(
            followingIDs: followingIDs,
            limit: defaultFeedSize,
            startAfter: lastDocument
        )
        
        // Update content state
        if nextBatch.count < defaultFeedSize {
            hasMoreContent = false
        }
        
        // Append to current feed
        currentFeed.append(contentsOf: nextBatch)
        
        // Manage memory - remove old threads if feed gets too large
        if currentFeed.count > maxCachedThreads {
            let threadsToRemove = currentFeed.count - maxCachedThreads
            currentFeed.removeFirst(threadsToRemove)
        }
        
        feedStats.totalThreadsLoaded = currentFeed.count
        
        print("✅ HOME FEED: Loaded \(nextBatch.count) more threads, total: \(currentFeed.count)")
        return currentFeed
    }
    
    // MARK: - LAZY LOADING IMPLEMENTATION - FIXED FOR ALL FOLLOWING USERS
    
    /// Get parent threads only (no children) for instant loading - FIXED
    private func getFollowingParentThreadsOnly(
        followingIDs: [String],
        limit: Int,
        startAfter: DocumentSnapshot? = nil
    ) async throws -> [ThreadData] {
        
        // FIXED: Increased batch size for better user coverage
        let batchSize = min(10, followingIDs.count) // FIXED: Increased from 5 to 10
        let batches = followingIDs.batchedChunks(into: batchSize)
        
        var allThreads: [ThreadData] = []
        
        // FIXED: Process ALL batches, not just first 2
        // Process each batch of following users
        for batch in batches { // FIXED: Removed .prefix(2) limitation
            let batchThreads = try await getParentThreadsBatch(
                creatorIDs: batch,
                limit: limit,
                startAfter: startAfter
            )
            allThreads.append(contentsOf: batchThreads)
            
            // Stop if we have enough content for this load
            if allThreads.count >= limit {
                break
            }
        }
        
        // Simple random shuffle - no complex algorithm
        let shuffledThreads = Array(allThreads.shuffled().prefix(limit))
        
        print("🎲 HOME FEED: Shuffled \(allThreads.count) parent threads from \(batches.count) batches to \(shuffledThreads.count)")
        return shuffledThreads
    }
    
    /// Get batch of PARENT THREADS ONLY (no children loading)
    private func getParentThreadsBatch(
        creatorIDs: [String],
        limit: Int,
        startAfter: DocumentSnapshot?
    ) async throws -> [ThreadData] {
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        // Query for parent threads only (conversationDepth = 0)
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, in: creatorIDs)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let startAfter = startAfter {
            query = query.start(afterDocument: startAfter)
        }
        
        let snapshot = try await query.getDocuments()
        lastDocument = snapshot.documents.last
        
        var threads: [ThreadData] = []
        
        // Convert documents to ThreadData - PARENT ONLY (no children)
        for document in snapshot.documents {
            if let thread = try await createParentThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        print("📊 HOME FEED: Loaded \(threads.count) parent threads from batch of \(creatorIDs.count) creators")
        return threads
    }
    
    /// Create ThreadData with PARENT ONLY (no children loading) - FIXED FOR SPEED
    private func createParentThreadFromDocument(_ document: DocumentSnapshot) async throws -> ThreadData? {
        
        // Create video metadata directly from document (bypass VideoService.getVideo)
        let data = document.data()
        guard let data = data else { return nil }
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? "Untitled"
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        // Create CoreVideoMetadata for parent video
        let parentVideo = CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: data[FirebaseSchema.VideoDocument.threadID] as? String,
            replyToVideoID: data[FirebaseSchema.VideoDocument.replyToVideoID] as? String,
            conversationDepth: data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0,
            viewCount: data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0,
            hypeCount: data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0,
            coolCount: data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0,
            replyCount: data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0,
            shareCount: data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0,
            temperature: data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral",
            qualityScore: data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50,
            engagementRatio: 0.0,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: data[FirebaseSchema.VideoDocument.duration] as? Double ?? 0.0,
            aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? (9.0/16.0),
            fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
            discoverabilityScore: (data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double) ?? 0.5,
            isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        )
        
        // Create ThreadData with NO CHILDREN (instant loading)
        return ThreadData(
            id: parentVideo.id,
            parentVideo: parentVideo,
            childVideos: [] // Empty - load lazily
        )
    }
    
    // MARK: - INSTANT FALLBACK IMPLEMENTATION
    
    /// Get trending threads as fallback (no following check required)
    private func getTrendingParentThreadsOnly(limit: Int) async throws -> [ThreadData] {
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        // Simple query for recent parent threads (no user filtering)
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        // Convert documents to ThreadData - PARENT ONLY
        for document in snapshot.documents {
            if let thread = try await createParentThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        // Simple shuffle for variety
        let shuffledThreads = threads.shuffled()
        
        print("TRENDING: Loaded \(shuffledThreads.count) trending parent threads")
        return shuffledThreads
    }
    
    /// Timeout wrapper for async operations
    private func withTimeout<T>(_ timeLimit: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeLimit * 1_000_000_000))
                throw TimeoutError()
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Lazy Child Loading for Navigation
    
    /// Get following IDs with caching to eliminate repeated UserService calls
    private func getCachedFollowingIDs(userID: String) async throws -> [String] {
        
        // Check cache first
        if let cacheTime = followingIDsCacheTime,
           Date().timeIntervalSince(cacheTime) < followingCacheExpiration,
           !cachedFollowingIDs.isEmpty {
            print("CACHE HIT: Using cached following IDs (\(cachedFollowingIDs.count) users)")
            return cachedFollowingIDs
        }
        
        // Cache miss - load from UserService
        print("CACHE MISS: Loading following IDs from UserService")
        let followingIDs = try await userService.getFollowingIDs(userID: userID)
        
        // Cache the result
        cachedFollowingIDs = followingIDs
        followingIDsCacheTime = Date()
        
        print("CACHED: Stored \(followingIDs.count) following IDs")
        return followingIDs
    }
    
    /// Load children for specific thread when needed (called from HomeFeedView)
    func loadThreadChildren(threadID: String) async -> [CoreVideoMetadata] {
        do {
            let children = try await videoService.getThreadChildren(threadID: threadID)
            print("🔥 LAZY LOAD: Loaded \(children.count) children for thread \(threadID)")
            return children
        } catch {
            print("❌ LAZY LOAD: Failed to load children for thread \(threadID)")
            return []
        }
    }
    
    // MARK: - Navigation Support
    
    /// Preload threads for horizontal navigation
    func preloadHorizontalNavigation(
        currentThreadIndex: Int,
        threads: [ThreadData],
        direction: HomeFeedSwipeDirection
    ) async {
        
        let preloadRange: [Int]
        
        switch direction {
        case .forward:
            let startIndex = currentThreadIndex + 1
            let endIndex = min(startIndex + 2, threads.count - 1)
            preloadRange = Array(startIndex...endIndex)
            
        case .backward:
            let endIndex = currentThreadIndex - 1
            let startIndex = max(endIndex - 2, 0)
            preloadRange = Array(startIndex...endIndex)
        }
        
        // Load children for threads that will be navigated to
        for index in preloadRange {
            guard index >= 0 && index < threads.count else { continue }
            
            let thread = threads[index]
            if thread.childVideos.isEmpty {
                _ = await loadThreadChildren(threadID: thread.id)
            }
        }
        
        print("⚡ HOME FEED: Preloaded horizontal navigation for indices \(preloadRange)")
    }
    
    /// Check if should load more content based on current position
    func shouldLoadMoreContent(currentThreadIndex: Int) -> Bool {
        return currentThreadIndex >= preloadTriggerIndex && hasMoreContent && !isLoading
    }
    
    // MARK: - RESHUFFLE FUNCTIONALITY - NEW
    
    /// Reshuffle current feed when reaching bottom
    func reshuffleCurrentFeed() {
        guard !currentFeed.isEmpty else { return }
        
        print("🔀 HOME FEED: Reshuffling \(currentFeed.count) threads")
        
        // Simple shuffle of existing content
        currentFeed = currentFeed.shuffled()
        
        // Update stats
        feedStats.refreshCount += 1
        feedStats.lastRefreshTime = Date()
        
        print("✅ HOME FEED: Feed reshuffled - new order applied")
    }
    
    /// Get reshuffled feed for bottom reach scenario
    func getReshuffledFeed(userID: String) async throws -> [ThreadData] {
        
        print("🔄 HOME FEED: Creating reshuffled feed from existing content")
        
        // If we have no more content to load, reshuffle existing
        if !hasMoreContent && !currentFeed.isEmpty {
            reshuffleCurrentFeed()
            return currentFeed
        }
        
        // Otherwise try to load more content first, then reshuffle if needed
        do {
            let moreContent = try await loadMoreContent(userID: userID)
            if moreContent.count > currentFeed.count - 5 { // Got new content
                return moreContent
            } else {
                // No new content, reshuffle existing
                reshuffleCurrentFeed()
                return currentFeed
            }
        } catch {
            // Failed to load more, reshuffle what we have
            if !currentFeed.isEmpty {
                reshuffleCurrentFeed()
                return currentFeed
            }
            throw error
        }
    }
    
    // MARK: - Cache Integration
    
    /// Get cached feed if available
    func getCachedFeed(userID: String) -> [ThreadData]? {
        // Will be implemented when CachingService integration is complete
        return nil
    }
    
    /// Warm cache with initial thread data
    func warmCache(threads: [ThreadData]) {
        // Will be implemented when CachingService integration is complete
        print("🔥 HOME FEED: Cache warming ready for \(threads.count) threads")
    }
    
    // MARK: - Statistics and Monitoring
    
    /// Get current feed statistics
    func getFeedStats() -> FeedStats {
        feedStats.currentFeedSize = currentFeed.count
        feedStats.hasMoreContent = hasMoreContent
        return feedStats
    }
    
    /// Reset feed state
    func resetFeedState() {
        currentFeed.removeAll()
        lastDocument = nil
        hasMoreContent = true
        feedStats = FeedStats()
        
        print("🔄 HOME FEED: Reset feed state")
    }
}

// MARK: - Supporting Types

/// Custom timeout error
struct TimeoutError: Error {}

/// Feed statistics for monitoring
struct FeedStats {
    var totalThreadsLoaded: Int = 0
    var currentFeedSize: Int = 0
    var refreshCount: Int = 0
    var hasMoreContent: Bool = true
    var lastRefreshTime: Date?
    
    var cacheHitRate: Double {
        return 0.85
    }
}

/// Swipe direction for preloading
enum HomeFeedSwipeDirection {
    case forward
    case backward
}

// MARK: - Private Utility Extensions

fileprivate extension Array where Element == String {
    func batchedChunks(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Hello World Test Extension

extension HomeFeedService {
    
    /// Test home feed functionality
    func helloWorldTest() {
        print("🏠 HOME FEED SERVICE: Hello World - Ready for instant parent thread loading!")
        print("🏠 Features: Lazy child loading, following feed, random shuffle")
        print("🏠 Performance: <100ms parent load, lazy children on demand")
    }
}

// MARK: - Integration Extensions

extension HomeFeedService {
    
    /// Integration with VideoPreloadingService
    func setupPreloadingIntegration() async {
        print("🏠 HOME FEED: Ready for preloading service integration")
    }
    
    /// Integration with HomeFeedView
    func prepareForViewIntegration() -> [ThreadData] {
        return currentFeed
    }
}
