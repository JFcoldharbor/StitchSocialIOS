//
//  DiscoveryService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Discovery with Multi-Window Algorithm + TTL Cache
//  Dependencies: RecentUser.swift (RecentUser, LeaderboardVideo models)
//
//  COST OPTIMIZATIONS:
//  1. TTL Cache — category results cached 5 min, tab switches = 0 reads
//  2. Multi-window feed — 4 parallel queries across time periods instead of
//     sequential pagination that always starts from newest
//  3. Reduced over-fetching — old code fetched limit*3 to limit*5 then filtered;
//     now fetches tighter batches with smarter queries
//  4. Collection cache — podcast/film/collection results cached per session
//  5. CachingService.shared integration — all fetched threads cached app-wide
//
//  FIRESTORE INDEX REQUIRED:
//  Collection: videos
//  Fields: conversationDepth (ASC), createdAt (DESC)
//  — This index already exists from the old sequential query.
//  The time-window queries add range filters on createdAt which Firestore
//  handles with the same composite index (conversationDepth + createdAt).
//
//  CACHING STRATEGY:
//  - DiscoveryCacheEntry: holds [ThreadData] + timestamp, keyed by category
//  - TTL default 300s (5 min) — configurable per category
//  - Cache invalidated on: manual refresh, pull-to-refresh, app foreground after 10 min
//  - Collection results: cached until tab re-tap or session end
//  - RecentUsers / Leaderboard: cached 10 min (slow-changing data)
//
//  ADD TO CACHING OPTIMIZATION FILE:
//  - DiscoveryService now uses DiscoveryCacheEntry with TTL
//  - Category tab switches no longer trigger Firestore reads within TTL
//  - Main feed uses weighted scoring instead of sequential scan
//  - Collections cached per-session in ViewModel (already was) + service-level TTL
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// NOTE: RecentUser and LeaderboardVideo are defined in RecentUser.swift

// MARK: - Cache Entry

private struct DiscoveryCacheEntry {
    let threads: [ThreadData]
    let timestamp: Date
    let ttl: TimeInterval
    
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < ttl
    }
}

private struct CollectionCacheEntry {
    let collections: [VideoCollection]
    let timestamp: Date
    let ttl: TimeInterval
    
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < ttl
    }
}

private struct UserCacheEntry {
    let users: [RecentUser]
    let timestamp: Date
    var isValid: Bool { Date().timeIntervalSince(timestamp) < 600 } // 10 min
}

private struct LeaderboardCacheEntry {
    let videos: [LeaderboardVideo]
    let timestamp: Date
    var isValid: Bool { Date().timeIntervalSince(timestamp) < 600 } // 10 min
}

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
    
    // MARK: - TTL Cache
    
    private var categoryCache: [String: DiscoveryCacheEntry] = [:]
    private var collectionCache: [String: CollectionCacheEntry] = [:]
    private var recentUsersCache: UserCacheEntry?
    private var leaderboardCache: LeaderboardCacheEntry?
    
    /// Default TTL for category caches — reads from OptimizationConfig.Discovery
    private let defaultTTL: TimeInterval = OptimizationConfig.Discovery.defaultCategoryTTL
    /// Shorter TTL for fast-changing categories
    private let shortTTL: TimeInterval = OptimizationConfig.Discovery.fastChangingCategoryTTL
    
    // MARK: - Cache Management
    
    /// Clear all caches — call on manual refresh or app foreground after long background
    func invalidateAllCaches() {
        categoryCache.removeAll()
        collectionCache.removeAll()
        recentUsersCache = nil
        leaderboardCache = nil
        print("🗑️ DISCOVERY: All caches invalidated")
    }
    
    /// Clear just video caches (keep collections/users)
    func invalidateVideoCaches() {
        categoryCache.removeAll()
        print("🗑️ DISCOVERY: Video caches invalidated")
    }
    
    private func getCachedThreads(for key: String) -> [ThreadData]? {
        guard let entry = categoryCache[key], entry.isValid else { return nil }
        print("✅ CACHE HIT: \(key) (\(entry.threads.count) threads, \(Int(entry.ttl - Date().timeIntervalSince(entry.timestamp)))s remaining)")
        return entry.threads
    }
    
    private func cacheThreads(_ threads: [ThreadData], for key: String, ttl: TimeInterval? = nil) {
        categoryCache[key] = DiscoveryCacheEntry(
            threads: threads,
            timestamp: Date(),
            ttl: ttl ?? defaultTTL
        )
    }
    
    private func getCachedCollections(for key: String) -> [VideoCollection]? {
        guard let entry = collectionCache[key], entry.isValid else { return nil }
        print("✅ CACHE HIT: \(key) (\(entry.collections.count) collections)")
        return entry.collections
    }
    
    private func cacheCollections(_ collections: [VideoCollection], for key: String, ttl: TimeInterval? = nil) {
        collectionCache[key] = CollectionCacheEntry(
            collections: collections,
            timestamp: Date(),
            ttl: ttl ?? defaultTTL
        )
    }
    
    // MARK: - CachingService Integration
    
    /// Wire fetched threads into the shared CachingService so other views
    /// (HomeFeed, Profile, Thread detail) can read from memory instead of Firestore.
    /// This is the main bridge between Discovery reads and app-wide caching.
    private func cacheThreadsInSharedService(_ threads: [ThreadData]) {
        guard !threads.isEmpty else { return }
        CachingService.shared.cacheThreads(threads, priority: .normal)
    }
    
    // MARK: - Main Discovery Method (Multi-Window Weighted Algorithm)
    
    /// Main feed — pulls from MULTIPLE TIME WINDOWS in parallel so the feed
    /// contains a real mix of recent, mid-range, and older content.
    ///
    /// Strategy:
    ///   Window 1 (40%): Last 3 days   — fresh content
    ///   Window 2 (30%): 3-14 days     — settling content with engagement signals
    ///   Window 3 (20%): 14-60 days    — proven content
    ///   Window 4 (10%): 60+ days      — deep catalog / evergreen
    ///
    /// Each window is a SINGLE Firestore query run in parallel (async let).
    /// Total: 3-4 reads per load instead of 5-10 sequential pages.
    ///
    /// CACHING: TTL cache + allFetchedVideos session cache + CachingService.shared.
    func getDeepRandomizedDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        // Check TTL cache first (0 reads)
        if let cached = getCachedThreads(for: "all_weighted") {
            return Array(cached.prefix(limit))
        }
        
        // If DB exhausted, serve from session cache (0 reads)
        if isDatabaseExhausted && !allFetchedVideos.isEmpty {
            return getFromReshuffledCache(limit: limit)
        }
        
        print("🔍 DISCOVERY: Multi-window fetch for \(limit) videos")
        
        let now = Date()
        let threeDaysAgo   = now.addingTimeInterval(-3 * 24 * 3600)
        let fourteenDaysAgo = now.addingTimeInterval(-14 * 24 * 3600)
        let sixtyDaysAgo   = now.addingTimeInterval(-60 * 24 * 3600)
        
        // How many from each window
        let recentCount   = Int(ceil(Double(limit) * 0.40))  // 40%
        let midCount      = Int(ceil(Double(limit) * 0.30))  // 30%
        let provenCount   = Int(ceil(Double(limit) * 0.20))  // 20%
        let deepCount     = Int(ceil(Double(limit) * 0.10))  // 10%
        
        // Fire all windows in parallel — 4 reads total
        async let recentSnap = fetchTimeWindow(
            after: threeDaysAgo, before: now,
            sortField: FirebaseSchema.VideoDocument.createdAt,
            descending: true, limit: recentCount + 10
        )
        async let midSnap = fetchTimeWindow(
            after: fourteenDaysAgo, before: threeDaysAgo,
            sortField: FirebaseSchema.VideoDocument.createdAt,
            descending: true, limit: midCount + 10
        )
        async let provenSnap = fetchTimeWindow(
            after: sixtyDaysAgo, before: fourteenDaysAgo,
            sortField: FirebaseSchema.VideoDocument.createdAt,
            descending: true, limit: provenCount + 10
        )
        async let deepSnap = fetchTimeWindow(
            after: nil, before: sixtyDaysAgo,
            sortField: FirebaseSchema.VideoDocument.createdAt,
            descending: true, limit: deepCount + 10
        )
        
        // Collect results
        let recentDocs  = (try? await recentSnap) ?? []
        let midDocs     = (try? await midSnap) ?? []
        let provenDocs  = (try? await provenSnap) ?? []
        let deepDocs    = (try? await deepSnap) ?? []
        
        print("🔍 WINDOWS: recent=\(recentDocs.count) mid=\(midDocs.count) proven=\(provenDocs.count) deep=\(deepDocs.count)")
        
        // Parse each window, respecting per-window target counts
        var newThreads: [ThreadData] = []
        
        newThreads.append(contentsOf: parseWindowDocs(recentDocs, target: recentCount))
        newThreads.append(contentsOf: parseWindowDocs(midDocs, target: midCount))
        newThreads.append(contentsOf: parseWindowDocs(provenDocs, target: provenCount))
        newThreads.append(contentsOf: parseWindowDocs(deepDocs, target: deepCount))
        
        // If any window returned 0, backfill from windows that had extras
        if newThreads.count < limit {
            // Just do a fallback sequential fetch for the remainder
            let remaining = limit - newThreads.count
            let fallbackThreads = try await fallbackSequentialFetch(limit: remaining)
            newThreads.append(contentsOf: fallbackThreads)
        }
        
        // Mark DB exhausted if all windows came up short
        if recentDocs.isEmpty && midDocs.isEmpty && provenDocs.isEmpty && deepDocs.isEmpty {
            isDatabaseExhausted = true
            if newThreads.isEmpty {
                return getFromReshuffledCache(limit: limit)
            }
        }
        
        // Score, diversify, cache
        let scored = applyWeightedScoring(threads: newThreads)
        let diversified = ultraShuffleByCreator(threads: scored)
        
        cacheThreads(diversified, for: "all_weighted")
        cacheThreadsInSharedService(diversified)
        
        print("✅ DISCOVERY: Returning \(diversified.count) videos from all time periods (total cached: \(allFetchedVideos.count))")
        return diversified
    }
    
    // MARK: - Time Window Fetch Helper
    
    /// Single Firestore query for a time window. Returns raw DocumentSnapshots.
    /// COST: 1 Firestore read per call.
    private func fetchTimeWindow(
        after: Date?,
        before: Date?,
        sortField: String,
        descending: Bool,
        limit: Int
    ) async throws -> [DocumentSnapshot] {
        
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
        
        if let after = after {
            query = query.whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: after))
        }
        if let before = before {
            query = query.whereField(FirebaseSchema.VideoDocument.createdAt, isLessThanOrEqualTo: Timestamp(date: before))
        }
        
        query = query.order(by: sortField, descending: descending)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents
    }
    
    /// Parse documents from a time window into ThreadData, skipping duplicates.
    private func parseWindowDocs(_ docs: [DocumentSnapshot], target: Int) -> [ThreadData] {
        var threads: [ThreadData] = []
        
        for document in docs {
            guard threads.count < target else { break }
            
            let videoID = document.data()?[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
            guard !loadedVideoIDs.contains(videoID) else { continue }
            
            if document.data()?["isCollectionSegment"] as? Bool == true { continue }
            
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
                loadedVideoIDs.insert(videoID)
                allFetchedVideos.append(thread)
            }
        }
        
        return threads
    }
    
    /// Fallback: sequential pagination for when time windows come up short.
    /// Uses the old cursor-based approach but capped at 2 attempts.
    private func fallbackSequentialFetch(limit: Int) async throws -> [ThreadData] {
        var threads: [ThreadData] = []
        var attempts = 0
        
        while threads.count < limit && attempts < 2 {
            attempts += 1
            
            var query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 40)
            
            if let cursor = lastDocument {
                query = query.start(afterDocument: cursor)
            }
            
            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }
            
            lastDocument = snapshot.documents.last
            
            for document in snapshot.documents {
                let videoID = document.data()[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
                guard !loadedVideoIDs.contains(videoID) else { continue }
                if document.data()["isCollectionSegment"] as? Bool == true { continue }
                
                if let thread = createThreadFromDocument(document) {
                    threads.append(thread)
                    loadedVideoIDs.insert(videoID)
                    allFetchedVideos.append(thread)
                    if threads.count >= limit { break }
                }
            }
        }
        
        return threads
    }
    
    // MARK: - Weighted Scoring Algorithm
    
    /// Scores each video based on multiple signals, then sorts by score.
    /// This replaces pure random shuffle with an intelligent feed.
    ///
    /// Weights:
    ///   discoverabilityScore: 40% — already factors quality, temp, velocity, recording source
    ///   recency:              25% — exponential decay over 7 days
    ///   temperature:          20% — blazing=1.0, hot=0.8, warm=0.5, neutral=0.2, cool=0.1
    ///   engagement:           15% — engagementRatio (hype / total reactions)
    ///
    /// After scoring, adds controlled randomness (±15%) to prevent stale ordering.
    private func applyWeightedScoring(threads: [ThreadData]) -> [ThreadData] {
        guard threads.count > 1 else { return threads }
        
        let now = Date()
        
        let temperatureScores: [String: Double] = [
            "blazing": 1.0,
            "hot": 0.8,
            "warm": 0.5,
            "neutral": 0.2,
            "cool": 0.1,
            "cold": 0.0
        ]
        
        struct ScoredThread {
            let thread: ThreadData
            let score: Double
        }
        
        let scored = threads.map { thread -> ScoredThread in
            let video = thread.parentVideo
            
            // 1. Discoverability (0-1, already computed server-side)
            let discoverability = video.discoverabilityScore
            
            // 2. Recency — softer decay since we intentionally pull from all time periods.
            // 1.0 at 0 days, ~0.65 at 7 days, ~0.42 at 14 days, ~0.14 at 30 days
            let age = now.timeIntervalSince(video.createdAt)
            let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
            let recency = exp(-age / thirtyDays * 2.0)
            
            // 3. Temperature
            let tempScore = temperatureScores[video.temperature.lowercased()] ?? 0.2
            
            // 4. Engagement ratio
            let engagement = video.engagementRatio
            
            // Weighted sum
            let baseScore = (discoverability * 0.40)
                + (recency * 0.25)
                + (tempScore * 0.20)
                + (engagement * 0.15)
            
            // Add controlled randomness (±15%) to prevent stale feed
            let jitter = Double.random(in: -0.15...0.15)
            let finalScore = max(0, baseScore + jitter)
            
            return ScoredThread(thread: thread, score: finalScore)
        }
        
        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }
        return sorted.map { $0.thread }
    }
    
    // MARK: - Cache Reshuffling (0 reads)
    
    private func getFromReshuffledCache(limit: Int) -> [ThreadData] {
        if reshuffleIndex == 0 {
            print("🔄 DISCOVERY: Reshuffling all \(allFetchedVideos.count) videos for fresh loop")
            allFetchedVideos = applyWeightedScoring(threads: allFetchedVideos)
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
    
    // MARK: - Creator Diversity Shuffle
    
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
    
    // MARK: - Category Methods (All TTL Cached)
    
    /// Trending — sorted by discoverabilityScore.
    /// COST: Fetches limit*2 (down from limit*3). Cached 2 min.
    func getTrendingDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        // Cache check
        if let cached = getCachedThreads(for: "trending") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 2)  // Reduced from limit*3
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
        
        let sorted = threads.sorted { $0.parentVideo.discoverabilityScore > $1.parentVideo.discoverabilityScore }
        let result = Array(sorted.prefix(limit))
        
        // Cache with short TTL (trending changes fast)
        cacheThreads(result, for: "trending", ttl: shortTTL)
        cacheThreadsInSharedService(result)
        
        print("🔥 TRENDING: Returning \(result.count) videos sorted by discoverabilityScore")
        return result
    }
    
    func getPopularDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "popular") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        let threads = snapshot.documents.compactMap { createThreadFromDocument($0) }
        
        cacheThreads(threads, for: "popular")
        cacheThreadsInSharedService(threads)
        return threads
    }
    
    /// Recent — last 24h videos.
    /// COST: Fetches limit*1.5 (down from limit*2). Cached 2 min.
    func getRecentDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "recent") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        
        // Tighter fetch — 1.5x instead of 2x
        let fetchLimit = Int(Double(limit) * 1.5)
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: fetchLimit)
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
            
            if threads.count >= limit { break }
        }
        
        let result = threads.shuffled()
        cacheThreads(result, for: "recent", ttl: shortTTL)
        cacheThreadsInSharedService(result)
        
        print("🕐 RECENT: Returning \(result.count) videos from last 24h")
        return result
    }
    
    func getDiscoveryParentThreadsOnly(limit: Int = 40, lastDocument: DocumentSnapshot? = nil) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        let threads = try await getDeepRandomizedDiscovery(limit: limit)
        return (threads: threads, lastDocument: nil, hasMore: !isDatabaseExhausted || !allFetchedVideos.isEmpty)
    }
    
    // MARK: - Recent Users (Cached 10 min)
    
    func getRecentUsers(limit: Int = 20) async throws -> [RecentUser] {
        // Cache check
        if let cached = recentUsersCache, cached.isValid {
            print("✅ CACHE HIT: recentUsers (\(cached.users.count) users)")
            return Array(cached.users.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("🆕 DISCOVERY: Fetching recent users...")
        
        // Fetch limit*2 (down from limit*3)
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
            .limit(to: limit * 2)
            .getDocuments()
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        var recentUsers: [RecentUser] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            guard let username = data[FirebaseSchema.UserDocument.username] as? String,
                  let displayName = data[FirebaseSchema.UserDocument.displayName] as? String,
                  let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() else {
                continue
            }
            
            guard createdAt >= sevenDaysAgo else { continue }
            
            let isPrivate = data[FirebaseSchema.UserDocument.isPrivate] as? Bool ?? false
            guard !isPrivate else { continue }
            
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
            
            if recentUsers.count >= limit { break }
        }
        
        // Cache
        recentUsersCache = UserCacheEntry(users: recentUsers, timestamp: Date())
        
        print("✅ DISCOVERY: Found \(recentUsers.count) recent users (last 7 days, public)")
        return recentUsers
    }
    
    // MARK: - Hype Leaderboard (Cached 10 min)
    
    func getHypeLeaderboard(limit: Int = 10) async throws -> [LeaderboardVideo] {
        // Cache check
        if let cached = leaderboardCache, cached.isValid {
            print("✅ CACHE HIT: leaderboard (\(cached.videos.count) videos)")
            return Array(cached.videos.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔥 DISCOVERY: Fetching hype leaderboard...")
        
        // Fetch limit*2 (down from limit*3)
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit * 2)
            .getDocuments()
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        var leaderboardVideos: [LeaderboardVideo] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            guard let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String,
                  let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String,
                  let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int,
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() else {
                continue
            }
            
            guard createdAt >= sevenDaysAgo else { continue }
            guard hypeCount > 0 else { continue }
            
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
            
            if leaderboardVideos.count >= limit { break }
        }
        
        // Cache
        leaderboardCache = LeaderboardCacheEntry(videos: leaderboardVideos, timestamp: Date())
        
        print("✅ DISCOVERY: Found \(leaderboardVideos.count) leaderboard videos (last 7 days, hyped)")
        return leaderboardVideos
    }
    
    // MARK: - Algorithm Lanes (All Cached)
    
    /// Following feed — videos from users the current user follows.
    /// BATCHING: Uses PrivacyService cached following IDs (0 extra reads if cached).
    /// CACHING: Results cached 5 min. Tab switch = 0 reads.
    func getFollowingFeed(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "following") {
            return Array(cached.prefix(limit))
        }
        
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
        
        // Firestore IN supports max 10 — cap at 3 chunks (30 creators)
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
        let sorted = allThreads.sorted { $0.parentVideo.createdAt > $1.parentVideo.createdAt }
        let seen = NSMutableSet()
        let deduped = sorted.filter { seen.add($0.id) != nil ? false : true }
        let result = Array(deduped.prefix(limit))
        
        cacheThreads(result, for: "following")
        cacheThreadsInSharedService(result)
        
        print("❤️ FOLLOWING: Returning \(result.count) videos from followed creators")
        return result
    }
    
    /// Hot Hashtags — videos from trending hashtags.
    /// CACHING: Cached 5 min. HashtagService trending list reused.
    func getHotHashtagDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "hotHashtags") {
            return Array(cached.prefix(limit))
        }
        
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
        
        let result = Array(allThreads.shuffled().prefix(limit))
        cacheThreads(result, for: "hotHashtags")
        cacheThreadsInSharedService(result)
        
        print("#️⃣ HOT HASHTAGS: Returning \(result.count) videos from trending tags")
        return result
    }
    
    /// Heat Check — only BLAZING and HOT temperature videos.
    /// COST: Fetches limit*2 (down from limit*4). Cached 5 min.
    func getHeatCheckDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "heatCheck") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Reduced from limit*4 to limit*2
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 2)
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
        
        let result = threads.shuffled()
        cacheThreads(result, for: "heatCheck")
        cacheThreadsInSharedService(result)
        
        print("🌡️ HEAT CHECK: Returning \(result.count) blazing/hot videos")
        return result
    }
    
    /// Undiscovered — low view count videos.
    /// COST: Fetches limit*2 (down from limit*3). Cached 5 min.
    func getUndiscoveredDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "undiscovered") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Reduced from limit*3 to limit*2
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.viewCount)
            .limit(to: limit * 2)
            .getDocuments()
        
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let data = doc.data() as? [String: Any] else { continue }
            let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
            
            guard viewCount < 50 else { continue }
            
            if let thread = createThreadFromDocument(doc) {
                threads.append(thread)
                if threads.count >= limit { break }
            }
        }
        
        let result = threads.shuffled()
        cacheThreads(result, for: "undiscovered")
        cacheThreadsInSharedService(result)
        
        print("🔭 UNDISCOVERED: Returning \(result.count) low-view videos")
        return result
    }
    
    /// Longest Threads — threads with the most replies.
    /// COST: Single query, exact limit. Cached 5 min.
    func getLongestThreadsDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "longestThreads") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.replyCount, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let threads = snapshot.documents.compactMap { createThreadFromDocument($0) }
        cacheThreads(threads, for: "longestThreads")
        cacheThreadsInSharedService(threads)
        
        print("💬 LONGEST THREADS: Returning \(threads.count) most-replied threads")
        return threads
    }
    
    /// Spin-Offs — videos that are remixes of other content.
    /// COST: Fetches limit*3 (down from limit*5). Cached 5 min.
    func getSpinOffDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        if let cached = getCachedThreads(for: "spinOffs") {
            return Array(cached.prefix(limit))
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Reduced from limit*5 to limit*3
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit * 3)
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
        
        let result = threads.shuffled()
        cacheThreads(result, for: "spinOffs")
        cacheThreadsInSharedService(result)
        
        print("🔀 SPIN-OFFS: Returning \(result.count) spin-off videos")
        return result
    }
    
    // MARK: - Collection Discovery Lanes (Cached)
    
    /// Fetch published collections by content type.
    /// COST: Fetches limit*1.5 (down from limit*2). Cached 5 min.
    func getCollectionsByType(_ types: [String], limit: Int = 20) async throws -> [VideoCollection] {
        let cacheKey = "collections_\(types.joined(separator: "_"))"
        
        if let cached = getCachedCollections(for: cacheKey) {
            return Array(cached.prefix(limit))
        }
        
        guard !types.isEmpty else { return [] }
        
        let fetchLimit = Int(Double(limit) * 1.5)
        
        let snapshot = try await db.collection("videoCollections")
            .whereField("status", isEqualTo: "published")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "publishedAt", descending: true)
            .limit(to: fetchLimit)
            .getDocuments()
        
        var collections: [VideoCollection] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            let contentType = data["contentType"] as? String ?? "standard"
            
            guard types.contains(contentType) else { continue }
            
            if let collection = parseVideoCollection(from: data, id: doc.documentID) {
                collections.append(collection)
                if collections.count >= limit { break }
            }
        }
        
        cacheCollections(collections, for: cacheKey)
        
        print("🎬 COLLECTIONS: Returning \(collections.count) collections for types: \(types)")
        return collections
    }
    
    /// All collections discovery — all published public collections sorted by recency.
    /// CACHING: Cached 5 min. Tab switches = 0 reads.
    func getAllCollectionsDiscovery(limit: Int = 30) async throws -> [VideoCollection] {
        if let cached = getCachedCollections(for: "all_collections") {
            return Array(cached.prefix(limit))
        }
        
        let snapshot = try await db.collection("videoCollections")
            .whereField("status", isEqualTo: "published")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let collections = snapshot.documents.compactMap { parseVideoCollection(from: $0.data(), id: $0.documentID) }
        cacheCollections(collections, for: "all_collections")
        
        print("📚 DISCOVERY: Loaded \(collections.count) collections for discovery")
        return collections
    }
    
    /// Podcasts discovery
    func getPodcastDiscovery(limit: Int = 20) async throws -> [VideoCollection] {
        return try await getCollectionsByType(["podcast", "interview"], limit: limit)
    }
    
    /// Films discovery
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
