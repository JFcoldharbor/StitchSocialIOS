//
//  ShowService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Show Hierarchy Management
//  Dependencies: Firebase Firestore, Show, Season, VideoCollection, CollectionService
//  Handles Show → Season → Episode CRUD matching web dashboard ShowEditor.jsx + EpisodeEditor.jsx
//
//  CACHING STRATEGY:
//  - Shows list: TTL 30 min in CachingService. Creator rarely has >10 shows.
//  - Seasons per show: TTL 30 min, keyed "seasons_{showId}". Typically 1-5 seasons.
//  - Episodes per season: TTL 15 min, keyed "episodes_{seasonId}". Invalidated on add/delete.
//  - All reads go through cache-first pattern: check cache → return if fresh → else fetch + cache.
//  - Writes always invalidate relevant cache keys immediately.
//
//  BATCHING:
//  - loadShow() fetches show + seasons in parallel (like web's Promise.all)
//  - loadSeason() fetches season + all episodes in one parallel call
//  - Episode publish batches: episode doc + segment count update + season rollup in one Firestore batch write
//  - Engagement rollups (totalViews/Hypes/Cools on show/season) updated via Cloud Function, not per-view on client
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ShowService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // MARK: - In-Memory Cache (TTL-based)
    // Lightweight local cache to avoid redundant reads.
    // For production scale, migrate these into CachingService with shared eviction.
    
    private var showCache: [String: (show: Show, cachedAt: Date)] = [:]
    private var seasonsCache: [String: (seasons: [Season], cachedAt: Date)] = [:]  // keyed by showId
    private var episodesCache: [String: (episodes: [VideoCollection], cachedAt: Date)] = [:]  // keyed by seasonId
    
    private let showTTL: TimeInterval = 1800        // 30 min
    private let seasonTTL: TimeInterval = 1800       // 30 min
    private let episodeTTL: TimeInterval = 900       // 15 min
    
    init() {
        print("🎬 SHOW SERVICE: Initialized")
    }
    
    // MARK: - Cache Helpers
    
    private func isFresh<T>(_ entry: (T, cachedAt: Date)?, ttl: TimeInterval) -> Bool {
        guard let entry = entry else { return false }
        return Date().timeIntervalSince(entry.cachedAt) < ttl
    }
    
    private func invalidateShowCache(_ showId: String) {
        showCache.removeValue(forKey: showId)
    }
    
    private func invalidateSeasonsCache(_ showId: String) {
        seasonsCache.removeValue(forKey: showId)
    }
    
    private func invalidateEpisodesCache(_ seasonId: String) {
        episodesCache.removeValue(forKey: seasonId)
    }
    
    /// Clear all caches — call on logout or major data changes
    func clearAllCaches() {
        showCache.removeAll()
        seasonsCache.removeAll()
        episodesCache.removeAll()
        print("🎬 SHOW SERVICE: All caches cleared")
    }
    
    // ═══════════════════════════════════════
    // MARK: - Show CRUD
    // ═══════════════════════════════════════
    
    /// Get a single show by ID (cache-first)
    func getShow(_ showId: String) async throws -> Show? {
        // Cache check
        if let cached = showCache[showId], isFresh(cached, ttl: showTTL) {
            print("🎬 SHOW SERVICE: Cache hit for show \(showId)")
            return cached.show
        }
        
        let doc = try await db.collection("shows").document(showId).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        let show = decodeShow(from: data, id: showId)
        
        if let show = show {
            showCache[showId] = (show, Date())
        }
        return show
    }
    
    /// Get all shows for a creator (cache-first per creator)
    func getCreatorShows(creatorID: String) async throws -> [Show] {
        let snapshot = try await db.collection("shows")
            .whereField("creatorID", isEqualTo: creatorID)
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        let shows = snapshot.documents.compactMap { doc in
            decodeShow(from: doc.data(), id: doc.documentID)
        }
        
        // Populate cache for each show
        for show in shows {
            showCache[show.id] = (show, Date())
        }
        
        print("🎬 SHOW SERVICE: Loaded \(shows.count) shows for creator")
        return shows
    }
    
    /// Save (create or update) a show
    func saveShow(_ show: Show) async throws {
        var mutable = show
        mutable.updatedAt = Date()
        
        let data = encodeShow(mutable)
        try await db.collection("shows").document(show.id).setData(data, merge: true)
        
        // Update cache
        showCache[show.id] = (mutable, Date())
        print("🎬 SHOW SERVICE: Saved show \(show.id)")
    }
    
    /// Delete a show (soft delete — sets status to removed)
    func deleteShow(_ showId: String) async throws {
        try await db.collection("shows").document(showId).updateData([
            "status": ShowStatus.removed.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        invalidateShowCache(showId)
        print("🎬 SHOW SERVICE: Deleted show \(showId)")
    }
    
    // ═══════════════════════════════════════
    // MARK: - Season CRUD
    // ═══════════════════════════════════════
    
    /// Get all seasons for a show (cache-first)
    func getSeasons(showId: String) async throws -> [Season] {
        if let cached = seasonsCache[showId], isFresh(cached, ttl: seasonTTL) {
            print("🎬 SHOW SERVICE: Cache hit for seasons of \(showId)")
            return cached.seasons
        }
        
        let snapshot = try await db.collection("shows").document(showId)
            .collection("seasons")
            .order(by: "number")
            .getDocuments()
        
        let seasons = snapshot.documents.compactMap { doc in
            decodeSeason(from: doc.data(), id: doc.documentID, showId: showId)
        }
        
        seasonsCache[showId] = (seasons, Date())
        print("🎬 SHOW SERVICE: Loaded \(seasons.count) seasons for show \(showId)")
        return seasons
    }
    
    /// Save a season
    func saveSeason(showId: String, season: Season) async throws {
        var mutable = season
        mutable.updatedAt = Date()
        
        let data = encodeSeason(mutable)
        try await db.collection("shows").document(showId)
            .collection("seasons").document(season.id)
            .setData(data, merge: true)
        
        invalidateSeasonsCache(showId)
        print("🎬 SHOW SERVICE: Saved season \(season.id) in show \(showId)")
    }
    
    /// Delete a season and all its episodes
    func deleteSeason(showId: String, seasonId: String) async throws {
        // Get all episodes first to delete them
        let episodes = try await getEpisodes(showId: showId, seasonId: seasonId)
        
        // Batch delete: season doc + all episode docs
        let batch = db.batch()
        
        let seasonRef = db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
        batch.deleteDocument(seasonRef)
        
        for ep in episodes {
            let epRef = db.collection("shows").document(showId)
                .collection("seasons").document(seasonId)
                .collection("episodes").document(ep.id)
            batch.deleteDocument(epRef)
        }
        
        try await batch.commit()
        
        // Invalidate caches
        invalidateSeasonsCache(showId)
        invalidateEpisodesCache(seasonId)
        
        // Update show season count
        try await db.collection("shows").document(showId).updateData([
            "seasonCount": FieldValue.increment(Int64(-1)),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        invalidateShowCache(showId)
        
        print("🎬 SHOW SERVICE: Deleted season \(seasonId) with \(episodes.count) episodes")
    }
    
    // ═══════════════════════════════════════
    // MARK: - Episode CRUD (Episode = VideoCollection)
    // ═══════════════════════════════════════
    
    /// Get all episodes for a season (cache-first)
    func getEpisodes(showId: String, seasonId: String) async throws -> [VideoCollection] {
        if let cached = episodesCache[seasonId], isFresh(cached, ttl: episodeTTL) {
            print("🎬 SHOW SERVICE: Cache hit for episodes of season \(seasonId)")
            return cached.episodes
        }
        
        let snapshot = try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .collection("episodes")
            .order(by: "episodeNumber")
            .getDocuments()
        
        let episodes = snapshot.documents.compactMap { doc in
            decodeEpisode(from: doc.data(), id: doc.documentID)
        }
        
        episodesCache[seasonId] = (episodes, Date())
        print("🎬 SHOW SERVICE: Loaded \(episodes.count) episodes for season \(seasonId)")
        return episodes
    }
    
    /// Save an episode (create or update)
    func saveEpisode(showId: String, seasonId: String, episode: VideoCollection) async throws {
        let data = encodeEpisode(episode)
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .collection("episodes").document(episode.id)
            .setData(data, merge: true)
        
        invalidateEpisodesCache(seasonId)
        print("🎬 SHOW SERVICE: Saved episode \(episode.id)")
    }
    
    /// Delete an episode
    func deleteEpisode(showId: String, seasonId: String, episodeId: String) async throws {
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .collection("episodes").document(episodeId)
            .delete()
        
        invalidateEpisodesCache(seasonId)
        
        // Update season episode count
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .updateData([
                "episodeCount": FieldValue.increment(Int64(-1)),
                "updatedAt": FieldValue.serverTimestamp()
            ])
        invalidateSeasonsCache(showId)
        
        print("🎬 SHOW SERVICE: Deleted episode \(episodeId)")
    }
    
    // ═══════════════════════════════════════
    // MARK: - Batch Loading (Parallel Fetches)
    // ═══════════════════════════════════════
    
    /// Load show + all seasons in parallel (mirrors web Promise.all)
    /// Cost: 1 show read + 1 seasons query = 2 Firestore reads (or 0 if cached)
    func loadShowWithSeasons(_ showId: String) async throws -> (Show?, [Season]) {
        async let showTask = getShow(showId)
        async let seasonsTask = getSeasons(showId: showId)
        
        let show = try await showTask
        let seasons = try await seasonsTask
        
        return (show, seasons)
    }
    
    /// Load a season + all its episodes in parallel
    /// Cost: 1 season doc read + 1 episodes query = 2 reads (or 0 if cached)
    func loadSeasonWithEpisodes(showId: String, seasonId: String) async throws -> (Season?, [VideoCollection]) {
        async let seasonsTask = getSeasons(showId: showId)
        async let episodesTask = getEpisodes(showId: showId, seasonId: seasonId)
        
        let seasons = try await seasonsTask
        let season = seasons.first { $0.id == seasonId }
        let episodes = try await episodesTask
        
        return (season, episodes)
    }
    
    /// Full load: show + all seasons + all episodes per season
    /// Optimized: parallel season fetch, then parallel episode fetches per season
    /// Cost: 1 + 1 + N season queries (N = number of seasons, typically 1-5)
    func loadFullShow(_ showId: String) async throws -> (Show?, [Season], [String: [VideoCollection]]) {
        let (show, seasons) = try await loadShowWithSeasons(showId)
        
        // Parallel fetch all episodes for all seasons
        var episodeMap: [String: [VideoCollection]] = [:]
        
        try await withThrowingTaskGroup(of: (String, [VideoCollection]).self) { group in
            for season in seasons {
                group.addTask {
                    let eps = try await self.getEpisodes(showId: showId, seasonId: season.id)
                    return (season.id, eps)
                }
            }
            
            for try await (seasonId, episodes) in group {
                episodeMap[seasonId] = episodes
            }
        }
        
        print("🎬 SHOW SERVICE: Full load complete — \(seasons.count) seasons, \(episodeMap.values.flatMap { $0 }.count) episodes")
        return (show, seasons, episodeMap)
    }
    
    // ═══════════════════════════════════════
    // MARK: - Convenience: Add Season / Episode
    // ═══════════════════════════════════════
    
    /// Add a new season to a show (mirrors web addSeason)
    func addSeason(to showId: String) async throws -> Season {
        let existingSeasons = try await getSeasons(showId: showId)
        let newNumber = existingSeasons.count + 1
        
        let season = Season.newSeason(showId: showId, number: newNumber)
        try await saveSeason(showId: showId, season: season)
        
        // Update show season count — use setData merge so it works even if show doc
        // was created in memory but not yet persisted to Firestore
        try await db.collection("shows").document(showId).setData([
            "seasonCount": newNumber,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        invalidateShowCache(showId)
        
        return season
    }
    
    /// Add a new episode to a season (mirrors web addEpisode)
    func addEpisode(showId: String, seasonId: String, creatorID: String, creatorName: String, format: ShowFormat) async throws -> VideoCollection {
        let existingEpisodes = try await getEpisodes(showId: showId, seasonId: seasonId)
        let newNumber = existingEpisodes.count + 1
        
        let episode = VideoCollection(
            id: UUID().uuidString,
            title: "",
            description: "",
            creatorID: creatorID,
            creatorName: creatorName,
            contentType: .series,
            showId: showId,
            seasonId: seasonId,
            episodeNumber: newNumber,
            format: format
        )
        
        try await saveEpisode(showId: showId, seasonId: seasonId, episode: episode)
        
        // Update season episode count
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .setData([
                "episodeCount": newNumber,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        invalidateSeasonsCache(showId)
        
        return episode
    }
    
    // ═══════════════════════════════════════
    // MARK: - Encode / Decode
    // ═══════════════════════════════════════
    
    private func encodeShow(_ show: Show) -> [String: Any] {
        return [
            "id": show.id,
            "title": show.title,
            "description": show.description,
            "creatorID": show.creatorID,
            "creatorName": show.creatorName,
            "format": show.format.rawValue,
            "genre": show.genre.rawValue,
            "contentType": show.contentType.rawValue,
            "tags": show.tags.map { $0.rawValue },
            "coverImageURL": show.coverImageURL ?? "",
            "thumbnailURL": show.thumbnailURL ?? "",
            "status": show.status.rawValue,
            "isFeatured": show.isFeatured,
            "seasonCount": show.seasonCount,
            "totalEpisodes": show.totalEpisodes,
            "totalViews": show.totalViews,
            "totalHypes": show.totalHypes,
            "totalCools": show.totalCools,
            "createdAt": Timestamp(date: show.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }
    
    private func decodeShow(from data: [String: Any], id: String) -> Show? {
        return Show(
            id: id,
            title: data["title"] as? String ?? "",
            description: data["description"] as? String ?? "",
            creatorID: data["creatorID"] as? String ?? "",
            creatorName: data["creatorName"] as? String ?? "",
            format: ShowFormat(rawValue: data["format"] as? String ?? "vertical") ?? .vertical,
            genre: ShowGenre(rawValue: data["genre"] as? String ?? "drama") ?? .drama,
            contentType: CollectionContentType(rawValue: data["contentType"] as? String ?? "series") ?? .series,
            tags: (data["tags"] as? [String])?.compactMap { ShowTag(rawValue: $0) } ?? [],
            coverImageURL: data["coverImageURL"] as? String,
            thumbnailURL: data["thumbnailURL"] as? String,
            status: ShowStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft,
            isFeatured: data["isFeatured"] as? Bool ?? false,
            seasonCount: data["seasonCount"] as? Int ?? 0,
            totalEpisodes: data["totalEpisodes"] as? Int ?? 0,
            totalViews: data["totalViews"] as? Int ?? 0,
            totalHypes: data["totalHypes"] as? Int ?? 0,
            totalCools: data["totalCools"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func encodeSeason(_ season: Season) -> [String: Any] {
        return [
            "id": season.id,
            "showId": season.showId,
            "number": season.number,
            "title": season.title,
            "description": season.description,
            "coverImageURL": season.coverImageURL ?? "",
            "status": season.status.rawValue,
            "episodeCount": season.episodeCount,
            "totalViews": season.totalViews,
            "totalHypes": season.totalHypes,
            "totalCools": season.totalCools,
            "createdAt": Timestamp(date: season.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }
    
    private func decodeSeason(from data: [String: Any], id: String, showId: String) -> Season? {
        return Season(
            id: id,
            showId: showId,
            number: data["number"] as? Int ?? 1,
            title: data["title"] as? String ?? "",
            description: data["description"] as? String ?? "",
            coverImageURL: data["coverImageURL"] as? String,
            status: SeasonStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft,
            episodeCount: data["episodeCount"] as? Int ?? 0,
            totalViews: data["totalViews"] as? Int ?? 0,
            totalHypes: data["totalHypes"] as? Int ?? 0,
            totalCools: data["totalCools"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func encodeEpisode(_ ep: VideoCollection) -> [String: Any] {
        var data: [String: Any] = [
            "id": ep.id,
            "title": ep.title,
            "description": ep.description,
            "creatorID": ep.creatorID,
            "creatorName": ep.creatorName,
            "coverImageURL": ep.coverImageURL ?? "",
            "segmentIDs": ep.segmentIDs,
            "segmentCount": ep.segmentCount,
            "totalDuration": ep.totalDuration,
            "status": ep.status.rawValue,
            "visibility": ep.visibility.rawValue,
            "allowReplies": ep.allowReplies,
            "contentType": ep.contentType.rawValue,
            "allowStitchReplies": ep.allowStitchReplies,
            "publishedAt": ep.publishedAt != nil ? Timestamp(date: ep.publishedAt!) : NSNull(),
            "createdAt": Timestamp(date: ep.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "totalViews": ep.totalViews,
            "totalHypes": ep.totalHypes,
            "totalCools": ep.totalCools,
            "totalReplies": ep.totalReplies,
            "totalShares": ep.totalShares,
            // Show hierarchy fields
            "showId": ep.showId ?? "",
            "seasonId": ep.seasonId ?? "",
            "episodeNumber": ep.episodeNumber ?? 0,
            "format": ep.format?.rawValue ?? "vertical",
            // Upload pipeline metadata
            "compressed": ep.compressed,
            "splitIntoFiles": ep.splitIntoFiles,
            "originalFileSizeMB": ep.originalFileSizeMB ?? 0,
            "compressedFileSizeMB": ep.compressedFileSizeMB ?? 0,
        ]
        
        // Ad slots
        if let adSlots = ep.adSlots {
            data["adSlots"] = adSlots.map { slot in
                [
                    "afterSegmentIndex": slot.afterSegmentIndex,
                    "insertAfterTime": slot.insertAfterTime,
                    "type": slot.type,
                    "durationSeconds": slot.durationSeconds,
                ] as [String: Any]
            }
        }
        
        return data
    }
    
    private func decodeEpisode(from data: [String: Any], id: String) -> VideoCollection? {
        // Break into sub-expressions to help Swift compiler type-check
        let adSlotsRaw = data["adSlots"] as? [[String: Any]]
        let adSlots = adSlotsRaw?.map { slot in
            AdSlot(
                afterSegmentIndex: slot["afterSegmentIndex"] as? Int ?? 0,
                insertAfterTime: slot["insertAfterTime"] as? TimeInterval ?? 0,
                type: slot["type"] as? String ?? "standard",
                durationSeconds: slot["durationSeconds"] as? TimeInterval ?? 30
            )
        }
        
        // Core fields
        let epTitle = data["title"] as? String ?? ""
        let epDescription = data["description"] as? String ?? ""
        let epCreatorID = data["creatorID"] as? String ?? ""
        let epCreatorName = data["creatorName"] as? String ?? ""
        let epCoverImageURL = data["coverImageURL"] as? String
        let epSegmentIDs = data["segmentIDs"] as? [String] ?? []
        let epSegmentCount = data["segmentCount"] as? Int ?? 0
        let epTotalDuration = data["totalDuration"] as? TimeInterval ?? 0
        
        // Status fields
        let epStatus = CollectionStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft
        let epVisibility = CollectionVisibility(rawValue: data["visibility"] as? String ?? "public") ?? .publicVisible
        let epAllowReplies = data["allowReplies"] as? Bool ?? true
        let epContentType = CollectionContentType(rawValue: data["contentType"] as? String ?? "series") ?? .series
        let epAllowStitchReplies = data["allowStitchReplies"] as? Bool
        
        // Timestamps
        let epPublishedAt = (data["publishedAt"] as? Timestamp)?.dateValue()
        let epCreatedAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let epUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        // Engagement
        let epTotalViews = data["totalViews"] as? Int ?? 0
        let epTotalHypes = data["totalHypes"] as? Int ?? 0
        let epTotalCools = data["totalCools"] as? Int ?? 0
        let epTotalReplies = data["totalReplies"] as? Int ?? 0
        let epTotalShares = data["totalShares"] as? Int ?? 0
        
        // Show hierarchy
        let epShowId = data["showId"] as? String
        let epSeasonId = data["seasonId"] as? String
        let epEpisodeNumber = data["episodeNumber"] as? Int
        let epFormat = ShowFormat(rawValue: data["format"] as? String ?? "vertical")
        
        // Upload pipeline
        let epCompressed = data["compressed"] as? Bool ?? false
        let epSplitIntoFiles = data["splitIntoFiles"] as? Bool ?? false
        let epOriginalFileSizeMB = data["originalFileSizeMB"] as? Double
        let epCompressedFileSizeMB = data["compressedFileSizeMB"] as? Double
        
        return VideoCollection(
            id: id,
            title: epTitle,
            description: epDescription,
            creatorID: epCreatorID,
            creatorName: epCreatorName,
            coverImageURL: epCoverImageURL,
            segmentIDs: epSegmentIDs,
            segmentCount: epSegmentCount,
            totalDuration: epTotalDuration,
            status: epStatus,
            visibility: epVisibility,
            allowReplies: epAllowReplies,
            contentType: epContentType,
            allowStitchReplies: epAllowStitchReplies,
            showId: epShowId,
            seasonId: epSeasonId,
            episodeNumber: epEpisodeNumber,
            format: epFormat,
            compressed: epCompressed,
            splitIntoFiles: epSplitIntoFiles,
            originalFileSizeMB: epOriginalFileSizeMB,
            compressedFileSizeMB: epCompressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: epPublishedAt,
            createdAt: epCreatedAt,
            updatedAt: epUpdatedAt,
            totalViews: epTotalViews,
            totalHypes: epTotalHypes,
            totalCools: epTotalCools,
            totalReplies: epTotalReplies,
            totalShares: epTotalShares
        )
    }
}
