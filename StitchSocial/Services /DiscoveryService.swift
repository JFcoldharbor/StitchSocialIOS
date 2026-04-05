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
    
    /// IDs seen in current scroll session — cleared on resetSession() or when pool exhausted
    private var sessionSeenIDs: Set<String> = []
    private var allFetchedVideos: [ThreadData] = []
    private var reshuffleIndex: Int = 0
    
    // Per-window cursors — each loadMore starts after previous batch end
    private var cursors: [Int: DocumentSnapshot] = [:] // window index -> last doc
    
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
    
    /// Full session reset — clears caches AND session state.
    /// Call on refresh, account switch, or pull-to-refresh.
    func resetSession() {
        invalidateAllCaches()
        sessionSeenIDs.removeAll()
        allFetchedVideos.removeAll()
        reshuffleIndex = 0
        cursors.removeAll()
        print("🔄 DISCOVERY: Session reset — fresh fetch on next load")
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
    //
    // FEED STRATEGY:
    // 1. Pull from 7 time windows in parallel (each maps to a resurfacing bucket)
    // 2. "Seen" tracking is per-scroll-session only — UserDefaults tracks last seen timestamp
    // 3. Resurfacing rules: never show again in same session, but resurface after:
    //    24h, 48h, 72h, 7d, 30d, 60d, 90d — whichever bucket the video falls into
    // 4. "Cooled" videos excluded permanently (from DiscoveryEngagementTracker)
    // 5. Within each batch, score by algorithm then creator-diversify
    // 6. When all videos exhausted in session, reshuffle full pool (never-ending scroll)
    
    // MARK: - Main Feed
    //
    // ARCHITECTURE:
    // - No TTL cache on main feed — cursor-based pagination drives fresh content
    // - 7 parallel time windows, each with its own cursor for true pagination
    // - Window-aware scoring: recency weight varies by window age
    // - Single shuffle pass at service level (ViewModel does NOT re-shuffle)
    // - cool/cold temperature + blocked creator filtering
    // - Never-ending scroll: when all windows exhausted, cursors reset + reshuffle pool
    
    func getDeepRandomizedDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        let h24  = now.addingTimeInterval(-1   * 24 * 3600)
        let h48  = now.addingTimeInterval(-2   * 24 * 3600)
        let h72  = now.addingTimeInterval(-3   * 24 * 3600)
        let d7   = now.addingTimeInterval(-7   * 24 * 3600)
        let d30  = now.addingTimeInterval(-30  * 24 * 3600)
        let d60  = now.addingTimeInterval(-60  * 24 * 3600)
        let d365 = now.addingTimeInterval(-365 * 24 * 3600)
        
        // Fetch 3x target per window — filters (cool, blocked, collection segments)
        // reduce raw count, so we need buffer to hit targets
        let w1 = max(6,  Int(Double(limit) * 0.30))  // last 24h   (30%)
        let w2 = max(5,  Int(Double(limit) * 0.20))  // 24-48h     (20%)
        let w3 = max(4,  Int(Double(limit) * 0.15))  // 48-72h     (15%)
        let w4 = max(4,  Int(Double(limit) * 0.12))  // 3-7d       (12%)
        let w5 = max(3,  Int(Double(limit) * 0.10))  // 7-30d      (10%)
        let w6 = max(3,  Int(Double(limit) * 0.08))  // 30-60d     ( 8%)
        let w7 = max(2,  Int(Double(limit) * 0.05))  // 60d-1yr    ( 5%)
        
        // All windows fire in parallel — cursors paginate each window independently
        async let snap1 = fetchTimeWindow(after: h24,  before: now,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: true,  limit: w1 * 3, cursor: cursors[1])
        async let snap2 = fetchTimeWindow(after: h48,  before: h24,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: true,  limit: w2 * 3, cursor: cursors[2])
        async let snap3 = fetchTimeWindow(after: h72,  before: h48,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: true,  limit: w3 * 3, cursor: cursors[3])
        async let snap4 = fetchTimeWindow(after: d7,   before: h72,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: false, limit: w4 * 3, cursor: cursors[4])
        async let snap5 = fetchTimeWindow(after: d30,  before: d7,   sortField: FirebaseSchema.VideoDocument.createdAt, descending: false, limit: w5 * 3, cursor: cursors[5])
        async let snap6 = fetchTimeWindow(after: d60,  before: d30,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: false, limit: w6 * 3, cursor: cursors[6])
        async let snap7 = fetchTimeWindow(after: d365, before: d60,  sortField: FirebaseSchema.VideoDocument.createdAt, descending: false, limit: w7 * 4, cursor: cursors[7])
        
        let r1 = (try? await snap1) ?? (docs: [], lastDoc: nil)
        let r2 = (try? await snap2) ?? (docs: [], lastDoc: nil)
        let r3 = (try? await snap3) ?? (docs: [], lastDoc: nil)
        let r4 = (try? await snap4) ?? (docs: [], lastDoc: nil)
        let r5 = (try? await snap5) ?? (docs: [], lastDoc: nil)
        let r6 = (try? await snap6) ?? (docs: [], lastDoc: nil)
        let r7 = (try? await snap7) ?? (docs: [], lastDoc: nil)
        
        // Advance cursors — empty windows reset so they cycle from beginning next fetch
        if let d = r1.lastDoc { cursors[1] = d } else { cursors.removeValue(forKey: 1) }
        if let d = r2.lastDoc { cursors[2] = d } else { cursors.removeValue(forKey: 2) }
        if let d = r3.lastDoc { cursors[3] = d } else { cursors.removeValue(forKey: 3) }
        if let d = r4.lastDoc { cursors[4] = d } else { cursors.removeValue(forKey: 4) }
        if let d = r5.lastDoc { cursors[5] = d } else { cursors.removeValue(forKey: 5) }
        if let d = r6.lastDoc { cursors[6] = d } else { cursors.removeValue(forKey: 6) }
        if let d = r7.lastDoc { cursors[7] = d } else { cursors.removeValue(forKey: 7) }
        
        print("🔍 WINDOWS: 24h=\(r1.docs.count) 48h=\(r2.docs.count) 72h=\(r3.docs.count) 7d=\(r4.docs.count) 30d=\(r5.docs.count) 60d=\(r6.docs.count) 1yr=\(r7.docs.count)")
        
        let blockedCreators = Set(DiscoveryEngagementTracker.shared.blockedCreatorIDs())
        var batchSeen = Set<String>()
        
        // Parse each window with its recency tier — used for window-aware scoring
        var newThreads: [(thread: ThreadData, windowTier: Int)] = []
        newThreads.append(contentsOf: parseDocs(r1.docs, target: w1, tier: 1, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r2.docs, target: w2, tier: 2, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r3.docs, target: w3, tier: 3, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r4.docs, target: w4, tier: 4, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r5.docs, target: w5, tier: 5, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r6.docs, target: w6, tier: 6, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        newThreads.append(contentsOf: parseDocs(r7.docs, target: w7, tier: 7, batchSeen: &batchSeen, blockedCreators: blockedCreators))
        
        // Backfill if all windows came up short (small DB or end of pagination)
        if newThreads.count < limit / 2 {
            let fallback = try await fallbackSequentialFetch(limit: limit - newThreads.count, batchSeen: &batchSeen, blockedCreators: blockedCreators)
            newThreads.append(contentsOf: fallback.map { (thread: $0, windowTier: 4) })
        }
        
        // Pool exhausted — reshuffle everything seen so far
        if newThreads.isEmpty && !allFetchedVideos.isEmpty {
            print("🔄 DISCOVERY: Windows exhausted — resurfacing full pool with reshuffle")
            cursors.removeAll() // reset all cursors so windows start fresh
            sessionSeenIDs.removeAll()
            return getFromReshuffledCache(limit: limit)
        }
        
        // Accumulate session pool for reshuffle fallback
        for item in newThreads {
            sessionSeenIDs.insert(item.thread.parentVideo.id)
            if !allFetchedVideos.contains(where: { $0.parentVideo.id == item.thread.parentVideo.id }) {
                allFetchedVideos.append(item.thread)
            }
        }
        
        // Window-aware score + single creator diversity shuffle
        let scored = applyWindowAwareScoring(threads: newThreads)
        let diversified = ultraShuffleByCreator(threads: scored)
        
        // Cache in shared service for other views (profile, thread detail)
        cacheThreadsInSharedService(diversified)
        
        print("✅ DISCOVERY: \(diversified.count) videos (pool: \(allFetchedVideos.count))")
        return diversified
    }
    
    // MARK: - Time Window Fetch Helper
    
    private func fetchTimeWindow(
        after: Date?,
        before: Date?,
        sortField: String,
        descending: Bool,
        limit: Int,
        cursor: DocumentSnapshot? = nil
    ) async throws -> (docs: [DocumentSnapshot], lastDoc: DocumentSnapshot?) {
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
        
        if let after = after {
            query = query.whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: after))
        }
        if let before = before {
            query = query.whereField(FirebaseSchema.VideoDocument.createdAt, isLessThanOrEqualTo: Timestamp(date: before))
        }
        
        query = query.order(by: sortField, descending: descending).limit(to: limit)
        if let cursor = cursor { query = query.start(afterDocument: cursor) }
        
        let snapshot = try await query.getDocuments()
        return (docs: snapshot.documents, lastDoc: snapshot.documents.last)
    }
    
    /// Parse docs for a window — returns (thread, tier) tuples for window-aware scoring.
    /// Filters: cool/cold temp, blocked creators, collection segments, batch dupes.
    private func parseDocs(_ docs: [DocumentSnapshot], target: Int, tier: Int, batchSeen: inout Set<String>, blockedCreators: Set<String>) -> [(thread: ThreadData, windowTier: Int)] {
        var results: [(thread: ThreadData, windowTier: Int)] = []
        for document in docs {
            guard results.count < target else { break }
            guard let data = document.data() else { continue }
            let videoID = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
            guard !batchSeen.contains(videoID) else { continue }
            let temp = (data["temperature"] as? String ?? "").lowercased()
            if temp == "cool" || temp == "cold" { continue }
            let creatorID = data["creatorID"] as? String ?? ""
            if blockedCreators.contains(creatorID) { continue }
            if let thread = createThreadFromDocument(document) {
                results.append((thread: thread, windowTier: tier))
                batchSeen.insert(videoID)
            }
        }
        return results
    }
    
    /// Fallback when windows come up short — full sequential fetch, no cursor.
    /// Resets session seen so all videos are eligible for recirculation.
    private func fallbackSequentialFetch(limit: Int, batchSeen: inout Set<String>, blockedCreators: Set<String>) async throws -> [ThreadData] {
        sessionSeenIDs.removeAll()
        var threads: [ThreadData] = []
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: max(limit * 3, 60))
        let snapshot = try await query.getDocuments()
        for document in snapshot.documents {
            guard threads.count < limit else { break }
            let data = document.data()
            let videoID = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
            guard !batchSeen.contains(videoID) else { continue }
            let temp = (data["temperature"] as? String ?? "").lowercased()
            if temp == "cool" || temp == "cold" { continue }
            let creatorID = data["creatorID"] as? String ?? ""
            if blockedCreators.contains(creatorID) { continue }
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
                batchSeen.insert(videoID)
            }
        }
        print("🔄 DISCOVERY: Fallback fetch returned \(threads.count) videos")
        return threads
    }
    
    // MARK: - Window-Aware Scoring
    //
    // Each tier gets different recency weight:
    // Tier 1 (last 24h):  recency=1.0 bonus — freshness is the point
    // Tier 2-3 (24-72h):  recency still high, engagement starting to signal
    // Tier 4-5 (3-30d):   balanced — engagement + discoverability matter more
    // Tier 6-7 (30d-1yr): engagement/discoverability carry the weight, recency minimal
    //
    // This means a 6-month-old banger can still surface above a mediocre new video.
    
    private func applyWindowAwareScoring(threads: [(thread: ThreadData, windowTier: Int)]) -> [ThreadData] {
        guard threads.count > 1 else { return threads.map { $0.thread } }
        
        let temperatureScores: [String: Double] = [
            "blazing": 1.0, "hot": 0.8, "warm": 0.5, "neutral": 0.2, "cool": 0.1, "cold": 0.0
        ]
        
        // Recency weight per tier — higher tier = older window = less recency weight
        let recencyWeights: [Int: Double] = [1: 0.35, 2: 0.28, 3: 0.22, 4: 0.15, 5: 0.10, 6: 0.06, 7: 0.04]
        let engageWeights:  [Int: Double] = [1: 0.10, 2: 0.12, 3: 0.15, 4: 0.20, 5: 0.25, 6: 0.28, 7: 0.30]
        let discoverWeights:[Int: Double] = [1: 0.35, 2: 0.38, 3: 0.40, 4: 0.42, 5: 0.42, 6: 0.44, 7: 0.44]
        let tempWeights:    [Int: Double] = [1: 0.20, 2: 0.22, 3: 0.23, 4: 0.23, 5: 0.23, 6: 0.22, 7: 0.22]
        
        struct Scored { let thread: ThreadData; let score: Double }
        
        let scored = threads.map { item -> Scored in
            let video = item.thread.parentVideo
            let tier = item.windowTier
            
            let rw = recencyWeights[tier] ?? 0.15
            let ew = engageWeights[tier]  ?? 0.20
            let dw = discoverWeights[tier] ?? 0.40
            let tw = tempWeights[tier]    ?? 0.25
            
            // Recency decay: 30-day half-life for all windows
            // Older windows naturally have lower raw recency, offset by lower rw weight
            let age = Date().timeIntervalSince(video.createdAt)
            let recency = exp(-age / (30 * 24 * 3600) * 1.5)
            
            let tempScore = temperatureScores[video.temperature.lowercased()] ?? 0.2
            let engagement = min(1.0, video.engagementRatio)
            let discoverability = min(1.0, video.discoverabilityScore)
            
            let base = (discoverability * dw) + (recency * rw) + (tempScore * tw) + (engagement * ew)
            let jitter = Double.random(in: -0.10...0.10) // ±10% randomness
            return Scored(thread: item.thread, score: max(0, base + jitter))
        }
        
        return scored.sorted { $0.score > $1.score }.map { $0.thread }
    }
    
    // MARK: - Reshuffle Pool (never-ending scroll fallback)
    
    private func getFromReshuffledCache(limit: Int) -> [ThreadData] {
        if reshuffleIndex == 0 {
            print("🔄 DISCOVERY: Reshuffling pool of \(allFetchedVideos.count) videos")
            // Re-score with tier 4 (balanced weights) and diversify
            let tiered = allFetchedVideos.map { (thread: $0, windowTier: 4) }
            let scored = applyWindowAwareScoring(threads: tiered)
            allFetchedVideos = ultraShuffleByCreator(threads: scored)
        }
        let start = reshuffleIndex
        let end = min(reshuffleIndex + limit, allFetchedVideos.count)
        let batch = Array(allFetchedVideos[start..<end])
        reshuffleIndex = end >= allFetchedVideos.count ? 0 : end
        print("✅ DISCOVERY (reshuffle): \(batch.count) videos (\(start)-\(end) of \(allFetchedVideos.count))")
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
        return (threads: threads, lastDocument: nil, hasMore: true)
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
            .whereField("visibility", isEqualTo: "public")
            .order(by: "createdAt", descending: true)
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
        
        // Query by visibility only — status may vary ("published", "active", etc.)
        // Order by createdAt (always present) instead of publishedAt (may be null)
        let snapshot = try await db.collection("videoCollections")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "createdAt", descending: true)
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
