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
//  FIRESTORE INDEXES REQUIRED:
//  1. conversationDepth (ASC) + createdAt (DESC)   — fetchChronological + category queries
//  2. conversationDepth (ASC) + feedSeed (ASC)     — fetchSeedBatch (windows 2-7)
//     ⚠️ Index 2 is MISSING — use Firebase Console link from logs to create it.
//     Until created, fetchSeedBatch falls back to createdAt which kills randomness.
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
    
    // MARK: - TTL Cache (category tabs — not main feed)
    
    private var categoryCache: [String: DiscoveryCacheEntry] = [:]
    private var collectionCache: [String: CollectionCacheEntry] = [:]
    private var recentUsersCache: UserCacheEntry?
    private var leaderboardCache: LeaderboardCacheEntry?
    
    private let defaultTTL: TimeInterval = OptimizationConfig.Discovery.defaultCategoryTTL
    private let shortTTL: TimeInterval = OptimizationConfig.Discovery.fastChangingCategoryTTL
    
    // MARK: - Cache Management
    
    func invalidateAllCaches() {
        categoryCache.removeAll()
        collectionCache.removeAll()
        recentUsersCache = nil
        leaderboardCache = nil
    }
    
    func invalidateVideoCaches() {
        categoryCache.removeAll()
    }
    
    func resetSession() {
        invalidateAllCaches()
        DiscoveryFeedQueue.shared.reset()
        print("🔄 DISCOVERY: Session reset")
    }

    /// One-time backfill: assigns random feedSeed to videos missing the field.
    /// Called once on app launch. Batched in groups of 500 (Firestore limit).
    /// CACHING: No cache needed — writes only, no reads returned to caller.
    func backfillFeedSeeds() async {
        do {
            let snap = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .getDocuments()
            let missing = snap.documents.filter { $0.data()["feedSeed"] == nil }
            guard !missing.isEmpty else { return }
            print("🌱 BACKFILL: Assigning feedSeed to \(missing.count) videos")
            let chunks = stride(from: 0, to: missing.count, by: 500).map {
                Array(missing[$0..<min($0 + 500, missing.count)])
            }
            for chunk in chunks {
                let batch = db.batch()
                for doc in chunk {
                    batch.updateData(["feedSeed": Double.random(in: 0.0...1.0)], forDocument: doc.reference)
                }
                try await batch.commit()
            }
            print("✅ BACKFILL: feedSeed assigned to \(missing.count) videos")
        } catch {
            print("⚠️ BACKFILL: feedSeed backfill failed: \(error)")
        }
    }
    
    private func getCachedThreads(for key: String) -> [ThreadData]? {
        guard let entry = categoryCache[key], entry.isValid else { return nil }
        return entry.threads
    }
    
    private func cacheThreads(_ threads: [ThreadData], for key: String, ttl: TimeInterval? = nil) {
        categoryCache[key] = DiscoveryCacheEntry(threads: threads, timestamp: Date(), ttl: ttl ?? defaultTTL)
    }
    
    private func cacheThreadsInSharedService(_ threads: [ThreadData]) {
        guard !threads.isEmpty else { return }
        CachingService.shared.cacheThreads(threads, priority: .normal)
    }
    
    private func getCachedCollections(for key: String) -> [VideoCollection]? {
        guard let entry = collectionCache[key], entry.isValid else { return nil }
        return entry.collections
    }
    
    private func cacheCollections(_ collections: [VideoCollection], for key: String) {
        collectionCache[key] = CollectionCacheEntry(collections: collections, timestamp: Date(), ttl: defaultTTL)
    }
    
    // MARK: - Feed Batch Fetch
    //
    // ARCHITECTURE (new — replaces cursor/reshuffle complexity):
    // - Window 1 (last 24h): strict createdAt DESC — newest first
    // - Windows 2-7 (older): feedSeed >= sessionSeed for random catalog slice
    //   with wrap-around when slice is thin
    // - All results shuffled before light scoring — genuinely different each session
    // - No cursors, no reshuffle pool, no session state
    // - Called by DiscoveryFeedQueue: initial=20, subsequent=40
    //
    // FIRESTORE INDEX REQUIRED:
    // Collection: videos — conversationDepth ASC + feedSeed ASC

    func fetchFeedBatch(seed: Double, limit: Int, exclude: Set<String> = []) async throws -> [ThreadData] {
        let now = Date()
        let h24  = now.addingTimeInterval(-1   * 24 * 3600)
        let h48  = now.addingTimeInterval(-2   * 24 * 3600)
        let h72  = now.addingTimeInterval(-3   * 24 * 3600)
        let d7   = now.addingTimeInterval(-7   * 24 * 3600)
        let d30  = now.addingTimeInterval(-30  * 24 * 3600)
        let d60  = now.addingTimeInterval(-60  * 24 * 3600)
        let d365 = now.addingTimeInterval(-365 * 24 * 3600)

        // Window target counts based on proportions
        let w1 = max(4,  Int(Double(limit) * 0.30))  // 24h    — chronological newest
        let w2 = max(3,  Int(Double(limit) * 0.18))  // 24-48h — random
        let w3 = max(3,  Int(Double(limit) * 0.14))  // 48-72h — random
        let w4 = max(3,  Int(Double(limit) * 0.12))  // 3-7d   — random
        let w5 = max(2,  Int(Double(limit) * 0.10))  // 7-30d  — random
        let w6 = max(2,  Int(Double(limit) * 0.08))  // 30-60d — random
        let w7 = max(1,  Int(Double(limit) * 0.08))  // 60-1yr — random

        let blockedCreators = Set(DiscoveryEngagementTracker.shared.blockedCreatorIDs())

        // Window 1: strict createdAt DESC — last 24h, newest first
        async let r1 = fetchChronological(after: h24, before: now, limit: w1 * 3)
        // Windows 2-7: feedSeed random slice
        async let r2 = fetchSeedBatch(after: h48,  before: h24,  seed: seed, limit: w2 * 3)
        async let r3 = fetchSeedBatch(after: h72,  before: h48,  seed: seed, limit: w3 * 3)
        async let r4 = fetchSeedBatch(after: d7,   before: h72,  seed: seed, limit: w4 * 3)
        async let r5 = fetchSeedBatch(after: d30,  before: d7,   seed: seed, limit: w5 * 3)
        async let r6 = fetchSeedBatch(after: d60,  before: d30,  seed: seed, limit: w6 * 3)
        async let r7 = fetchSeedBatch(after: d365, before: d60,  seed: seed, limit: w7 * 3)

        let docs1 = (try? await r1) ?? []
        let docs2 = (try? await r2) ?? []
        let docs3 = (try? await r3) ?? []
        let docs4 = (try? await r4) ?? []
        let docs5 = (try? await r5) ?? []
        let docs6 = (try? await r6) ?? []
        let docs7 = (try? await r7) ?? []

        print("🔍 WINDOWS: 24h=\(docs1.count) 48h=\(docs2.count) 72h=\(docs3.count) 7d=\(docs4.count) 30d=\(docs5.count) 60d=\(docs6.count) 1yr=\(docs7.count)")

        // Parse each window
        var batchSeen = Set<String>()
        var results: [ThreadData] = []

        func parse(_ docs: [DocumentSnapshot], target: Int) {
            var added = 0
            for doc in docs {
                guard added < target else { break }
                let id = doc.data()?[FirebaseSchema.VideoDocument.id] as? String ?? doc.documentID
                guard !batchSeen.contains(id), !exclude.contains(id) else { continue }
                let temp = (doc.data()?["temperature"] as? String ?? "").lowercased()
                if temp == "cool" || temp == "cold" { continue }
                let creatorID = doc.data()?["creatorID"] as? String ?? ""
                if blockedCreators.contains(creatorID) { continue }
                if let thread = createThreadFromDocument(doc) {
                    results.append(thread)
                    batchSeen.insert(id)
                    added += 1
                }
            }
        }

        // Window 1 kept in chronological order (newest first)
        parse(docs1, target: w1)

        // Windows 2-7 collected then shuffled for randomness
        var olderDocs: [DocumentSnapshot] = []
        olderDocs.append(contentsOf: docs2.prefix(w2))
        olderDocs.append(contentsOf: docs3.prefix(w3))
        olderDocs.append(contentsOf: docs4.prefix(w4))
        olderDocs.append(contentsOf: docs5.prefix(w5))
        olderDocs.append(contentsOf: docs6.prefix(w6))
        olderDocs.append(contentsOf: docs7.prefix(w7))
        olderDocs.shuffle()

        for doc in olderDocs {
            let id = doc.data()?[FirebaseSchema.VideoDocument.id] as? String ?? doc.documentID
            guard !batchSeen.contains(id), !exclude.contains(id) else { continue }
            let temp = (doc.data()?["temperature"] as? String ?? "").lowercased()
            if temp == "cool" || temp == "cold" { continue }
            let creatorID = doc.data()?["creatorID"] as? String ?? ""
            if blockedCreators.contains(creatorID) { continue }
            if let thread = createThreadFromDocument(doc) {
                results.append(thread)
                batchSeen.insert(id)
            }
        }

        // Fallback if windows short
        if results.count < limit / 2 {
            let fallback = try? await fetchSeedBatch(after: nil, before: now, seed: seed, limit: limit * 2)
            for doc in (fallback ?? []) {
                if results.count >= limit { break }
                let id = doc.data()?[FirebaseSchema.VideoDocument.id] as? String ?? doc.documentID
                guard !batchSeen.contains(id), !exclude.contains(id) else { continue }
                if let thread = createThreadFromDocument(doc) {
                    results.append(thread)
                    batchSeen.insert(id)
                }
            }
        }

        cacheThreadsInSharedService(results)
        print("✅ FETCH BATCH: \(results.count) videos (seed: \(String(format: "%.3f", seed)))")
        return results
    }

    // MARK: - Legacy wrapper — keeps DiscoveryViewModel callsites compiling
    // DiscoveryFeedQueue is the new entry point; this bridges old category methods

    func getDeepRandomizedDiscovery(limit: Int = 80) async throws -> [ThreadData] {
        return try await fetchFeedBatch(seed: Double.random(in: 0...1), limit: limit)
    }

    // MARK: - Window Fetch Helpers

    private func fetchChronological(after: Date, before: Date, limit: Int) async throws -> [DocumentSnapshot] {
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: after))
            .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThanOrEqualTo: Timestamp(date: before))
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents
    }

    private func fetchSeedBatch(after: Date?, before: Date, seed: Double, limit: Int) async throws -> [DocumentSnapshot] {
        // feedSeed >= seed gives a random catalog slice
        // No createdAt range in same query — avoids multi-field range conflict
        // Filter createdAt client-side after fetch
        do {
            var query: Query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .whereField("feedSeed", isGreaterThanOrEqualTo: seed)
                .order(by: "feedSeed", descending: false)
                .limit(to: limit)

            var docs = try await query.getDocuments().documents

            // Wrap-around if slice is thin
            if docs.count < limit / 2 {
                let wrapSnap = try await db.collection(FirebaseSchema.Collections.videos)
                    .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                    .whereField("feedSeed", isLessThan: seed)
                    .order(by: "feedSeed", descending: false)
                    .limit(to: limit - docs.count)
                    .getDocuments()
                docs.append(contentsOf: wrapSnap.documents)
            }

            // Client-side createdAt filter
            if let after = after {
                docs = docs.filter { doc in
                    guard let ts = doc.data()[FirebaseSchema.VideoDocument.createdAt] as? Timestamp else { return false }
                    return ts.dateValue() > after && ts.dateValue() <= before
                }
            }

            // feedSeed field missing on old docs — fall back to createdAt range for this window
            if docs.isEmpty, let after = after {
                let rangeFallback = try await db.collection(FirebaseSchema.Collections.videos)
                    .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                    .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: after))
                    .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThanOrEqualTo: Timestamp(date: before))
                    .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                    .limit(to: limit)
                    .getDocuments()
                return rangeFallback.documents
            }

            return docs

        } catch {
            // feedSeed index missing — fall back to createdAt range query
            // IMPORTANT: where clauses must come before order(by:) for inequality fields
            print("⚠️ DISCOVERY: feedSeed index missing — add composite index: conversationDepth ASC + feedSeed ASC")
            var fallback: Query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            if let after = after {
                fallback = fallback
                    .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: after))
                    .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThanOrEqualTo: Timestamp(date: before))
            }
            fallback = fallback
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
            return try await fallback.getDocuments().documents
        }
    }

    // MARK: - Cursor Feed (replaces feedSeed window approach)
    //
    // Simple straight pagination: conversationDepth==0, ordered createdAt DESC.
    // Cursor = last DocumentSnapshot from previous batch (nil = first page).
    // No exclude sets, no feedSeed, no notIn queries.
    // Requires Firestore index: conversationDepth ASC + createdAt DESC
    // (same index as existing chronological queries — already exists).

    func fetchCursorBatch(
        after cursor: DocumentSnapshot?,
        limit: Int = 20
    ) async throws -> (videos: [CoreVideoMetadata], lastDocument: DocumentSnapshot?, hasMore: Bool) {

        // Simplest possible query — just order by createdAt, no where clauses.
        // All filters (isDeleted, isCollectionSegment, conversationDepth, visibility)
        // handled client-side so older docs without these fields are not excluded.
        // Only requires a basic createdAt index which always exists.
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)

        if let cursor = cursor {
            query = query.start(afterDocument: cursor)
        }

        let snapshot = try await query.getDocuments()
        let docs = snapshot.documents
        print("📡 CURSOR FEED: Raw docs from Firestore: \(docs.count)")

        var deleted = 0, segment = 0, reply = 0, priv = 0, threadDropped = 0
        let videos = docs.compactMap { doc -> CoreVideoMetadata? in
            let data = doc.data()
            if data["isDeleted"] as? Bool == true           { deleted += 1; return nil }
            if data["isCollectionSegment"] as? Bool == true  { segment += 1; return nil }
            let depth = data["conversationDepth"] as? Int ?? 0
            if depth > 0                                     { reply += 1; return nil }
            let vis = data["visibility"] as? String ?? "public"
            if vis == "private" || vis == "followersOnly"    { priv += 1; return nil }
            guard let video = createThreadFromDocument(doc)?.parentVideo else {
                threadDropped += 1; return nil
            }
            return video
        }
        print("📡 CURSOR FEED: \(videos.count) shown | deleted:\(deleted) segment:\(segment) reply:\(reply) private:\(priv) threadDropped:\(threadDropped)")
        let hasMore = docs.count >= limit
        return (videos: videos, lastDocument: docs.last, hasMore: hasMore)
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
        // Don't filter on title — episodes may have empty titles during creation
        guard !id.isEmpty else { return nil }
        
        return VideoCollection(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            description: data["description"] as? String ?? "",
            creatorID: data["creatorID"] as? String ?? "",
            creatorName: data["creatorName"] as? String ?? "",
            coverImageURL: data["coverImageURL"] as? String ?? data["thumbnailURL"] as? String,
            segmentIDs: data["segmentIDs"] as? [String] ?? [],
            segmentCount: data["segmentCount"] as? Int ?? 0,
            totalDuration: data["totalDuration"] as? TimeInterval ?? 0,
            status: CollectionStatus(rawValue: data["status"] as? String ?? "") ?? .published,
            visibility: CollectionVisibility(rawValue: data["visibility"] as? String ?? "") ?? .publicVisible,
            allowReplies: data["allowReplies"] as? Bool ?? true,
            contentType: CollectionContentType(rawValue: data["contentType"] as? String ?? "") ?? .standard,
            allowStitchReplies: data["allowStitchReplies"] as? Bool,
            isFree: data["isFree"] as? Bool ?? false,
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
