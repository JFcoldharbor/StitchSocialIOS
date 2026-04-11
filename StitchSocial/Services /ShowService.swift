//
//  ShowService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Show Hierarchy Management (CORRECTED)
//
//  ARCHITECTURE:
//  - shows/{showId} → metadata only (title, genre, format, tags, cover)
//  - shows/{showId}/seasons/{seasonId} → lightweight season metadata
//  - videoCollections/{collectionId} → episodes live HERE with showId + seasonId fields
//  - videos/{videoId} → segments with collectionID linking to episode
//
//  All existing reads (ProfileView, DiscoveryView, CollectionPlayerView) pick up
//  show episodes automatically with zero changes.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ShowService: ObservableObject {
    
    static let shared = ShowService()
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // Cache
    private var showCache: [String: (show: Show, cachedAt: Date)] = [:]
    private var seasonsCache: [String: (seasons: [Season], cachedAt: Date)] = [:]
    private let showTTL: TimeInterval = 1800
    private let seasonTTL: TimeInterval = 1800
    
    init() { print("🎬 SHOW SERVICE: Initialized") }
    
    private func isFresh<T>(_ entry: (T, cachedAt: Date)?, ttl: TimeInterval) -> Bool {
        guard let entry = entry else { return false }
        return Date().timeIntervalSince(entry.cachedAt) < ttl
    }
    
    func clearAllCaches() {
        showCache.removeAll()
        seasonsCache.removeAll()
    }
    
    // ═══════════════════════════════════════
    // MARK: - Show CRUD
    // ═══════════════════════════════════════
    
    func getShow(_ showId: String) async throws -> Show? {
        if let cached = showCache[showId], isFresh(cached, ttl: showTTL) { return cached.show }
        let doc = try await db.collection("shows").document(showId).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        let show = decodeShow(from: data, id: showId)
        if let show = show { showCache[showId] = (show, Date()) }
        return show
    }
    
    func getCreatorShows(creatorID: String) async throws -> [Show] {
        do {
            let snapshot = try await db.collection("shows")
                .whereField("creatorID", isEqualTo: creatorID)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            let all = snapshot.documents.compactMap { decodeShow(from: $0.data(), id: $0.documentID) }
            let shows = all.filter { $0.status != .removed }
            print("📚 SHOW SERVICE: Loaded \(shows.count) shows for \(creatorID)")
            for show in shows { showCache[show.id] = (show, Date()) }
            return shows
        } catch {
            // Index may be missing — fall back to unordered query
            print("⚠️ SHOW SERVICE: Ordered query failed (\(error.localizedDescription)) — retrying without order")
            let snapshot = try await db.collection("shows")
                .whereField("creatorID", isEqualTo: creatorID)
                .getDocuments()
            let all = snapshot.documents.compactMap { decodeShow(from: $0.data(), id: $0.documentID) }
            let shows = all.filter { $0.status != .removed }
                .sorted { $0.updatedAt > $1.updatedAt }
            print("📚 SHOW SERVICE: Fallback loaded \(shows.count) shows for \(creatorID)")
            for show in shows { showCache[show.id] = (show, Date()) }
            return shows
        }
    }
    
    func saveShow(_ show: Show) async throws {
        var mutable = show
        mutable.updatedAt = Date()
        try await db.collection("shows").document(show.id).setData(encodeShow(mutable), merge: true)
        showCache[show.id] = (mutable, Date())
    }
    
    func deleteShow(_ showId: String) async throws {
        try await db.collection("shows").document(showId).updateData([
            "status": ShowStatus.removed.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        showCache.removeValue(forKey: showId)
    }
    
    // ═══════════════════════════════════════
    // MARK: - Season CRUD
    // ═══════════════════════════════════════
    
    func getSeasons(showId: String) async throws -> [Season] {
        if let cached = seasonsCache[showId], isFresh(cached, ttl: seasonTTL) { return cached.seasons }
        let snapshot = try await db.collection("shows").document(showId)
            .collection("seasons").order(by: "number").getDocuments()
        let seasons = snapshot.documents.compactMap { decodeSeason(from: $0.data(), id: $0.documentID, showId: showId) }
        seasonsCache[showId] = (seasons, Date())
        return seasons
    }
    
    func saveSeason(showId: String, season: Season) async throws {
        var mutable = season
        mutable.updatedAt = Date()
        try await db.collection("shows").document(showId)
            .collection("seasons").document(season.id)
            .setData(encodeSeason(mutable), merge: true)
        seasonsCache.removeValue(forKey: showId)
    }
    
    func deleteSeason(showId: String, seasonId: String) async throws {
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId).delete()
        seasonsCache.removeValue(forKey: showId)
        try await db.collection("shows").document(showId).setData([
            "seasonCount": FieldValue.increment(Int64(-1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        showCache.removeValue(forKey: showId)
    }
    
    // ═══════════════════════════════════════
    // MARK: - Episode CRUD (videoCollections)
    // ═══════════════════════════════════════
    
    /// Query videoCollections by showId + seasonId
    func getEpisodes(showId: String, seasonId: String) async throws -> [VideoCollection] {
        let snapshot = try await db.collection("videoCollections")
            .whereField("showId", isEqualTo: showId)
            .whereField("seasonId", isEqualTo: seasonId)
            .order(by: "episodeNumber")
            .getDocuments()
        return snapshot.documents.compactMap { decodeEpisode(from: $0.data(), id: $0.documentID) }
    }
    
    /// All episodes for a show across all seasons
    func getAllEpisodes(showId: String) async throws -> [VideoCollection] {
        let snapshot = try await db.collection("videoCollections")
            .whereField("showId", isEqualTo: showId)
            .order(by: "episodeNumber")
            .getDocuments()
        return snapshot.documents.compactMap { decodeEpisode(from: $0.data(), id: $0.documentID) }
    }
    
    /// Save episode to videoCollections
    func saveEpisode(showId: String, seasonId: String, episode: VideoCollection) async throws {
        try await db.collection("videoCollections").document(episode.id)
            .setData(encodeEpisode(episode), merge: true)
    }
    
    /// Soft-delete episode
    func deleteEpisode(showId: String, seasonId: String, episodeId: String) async throws {
        try await db.collection("videoCollections").document(episodeId).updateData([
            "status": "deleted",
            "updatedAt": FieldValue.serverTimestamp()
        ])
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .setData(["episodeCount": FieldValue.increment(Int64(-1)),
                       "updatedAt": FieldValue.serverTimestamp()], merge: true)
        seasonsCache.removeValue(forKey: showId)
    }
    
    // ═══════════════════════════════════════
    // MARK: - Batch Loading
    // ═══════════════════════════════════════
    
    func loadShowWithSeasons(_ showId: String) async throws -> (Show?, [Season]) {
        async let s = getShow(showId)
        async let ss = getSeasons(showId: showId)
        return (try await s, try await ss)
    }
    
    func loadFullShow(_ showId: String) async throws -> (Show?, [Season], [String: [VideoCollection]]) {
        let (show, seasons) = try await loadShowWithSeasons(showId)
        var episodeMap: [String: [VideoCollection]] = [:]
        try await withThrowingTaskGroup(of: (String, [VideoCollection]).self) { group in
            for season in seasons {
                group.addTask {
                    let eps = try await self.getEpisodes(showId: showId, seasonId: season.id)
                    return (season.id, eps)
                }
            }
            for try await (sid, eps) in group { episodeMap[sid] = eps }
        }
        return (show, seasons, episodeMap)
    }
    
    // ═══════════════════════════════════════
    // MARK: - Convenience: Add Season / Episode
    // ═══════════════════════════════════════
    
    func addSeason(to showId: String) async throws -> Season {
        // Ensure show doc exists
        try await saveShow(Show(id: showId, creatorID: Auth.auth().currentUser?.uid ?? ""))
        let existing = try await getSeasons(showId: showId)
        let num = existing.count + 1
        let season = Season.newSeason(showId: showId, number: num)
        try await saveSeason(showId: showId, season: season)
        try await db.collection("shows").document(showId).setData([
            "seasonCount": num, "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        showCache.removeValue(forKey: showId)
        return season
    }
    
    func addEpisode(showId: String, seasonId: String, creatorID: String, creatorName: String, format: ShowFormat) async throws -> VideoCollection {
        let existing = try await getEpisodes(showId: showId, seasonId: seasonId)
        let num = existing.count + 1
        let episode = VideoCollection(
            id: UUID().uuidString,
            title: "",
            description: "",
            creatorID: creatorID,
            creatorName: creatorName,
            contentType: .series,
            showId: showId,
            seasonId: seasonId,
            episodeNumber: num,
            format: format
        )
        try await saveEpisode(showId: showId, seasonId: seasonId, episode: episode)
        try await db.collection("shows").document(showId)
            .collection("seasons").document(seasonId)
            .setData(["episodeCount": num, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        seasonsCache.removeValue(forKey: showId)
        return episode
    }
    
    // ═══════════════════════════════════════
    // MARK: - Encode / Decode
    // ═══════════════════════════════════════
    
    // ═══════════════════════════════════════
    // MARK: - Schedule
    // ═══════════════════════════════════════

    /// Returns the next open premiere slot for a show.
    /// Zero Firestore reads — uses already-loaded episodes.
    /// CACHING: Pass in your in-memory episodesBySeasonId values.
    func nextAvailableSlot(for show: Show, existingEpisodes: [VideoCollection]) -> Date? {
        guard let config = show.scheduleConfig else { return nil }
        let scheduled = existingEpisodes.filter {
            $0.status == .published || $0.status.rawValue == "scheduled"
        }
        return ScheduleService.nextAvailableSlot(config: config, scheduledEpisodes: scheduled)
    }

    /// Batch-updates publishedAt for reordered episodes to preserve cadence spacing.
    /// BATCHING: All writes in a single Firestore batch — 1 round trip.
    func applyReorderedSchedule(
        episodes: [VideoCollection],
        show: Show
    ) async throws {
        guard let config = show.scheduleConfig, config.cadence != .custom else { return }
        let pairs = ScheduleService.recomputeDates(for: episodes, config: config)
        let batch = db.batch()
        for (id, date) in pairs {
            let ref = db.collection("videoCollections").document(id)
            batch.updateData(["publishedAt": Timestamp(date: date),
                              "status": "scheduled",
                              "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
        }
        try await batch.commit()
        print("📅 SHOW SERVICE: Reordered schedule — \(pairs.count) episodes updated")
    }

    private func encodeShow(_ show: Show) -> [String: Any] {
        var data: [String: Any] = [
            "id": show.id, "title": show.title, "description": show.description,
            "creatorID": show.creatorID, "creatorName": show.creatorName,
            "format": show.format.rawValue, "genre": show.genre.rawValue,
            "contentType": show.contentType.rawValue,
            "tags": show.tags.map { $0.rawValue },
            "coverImageURL": show.coverImageURL ?? "", "thumbnailURL": show.thumbnailURL ?? "",
            "status": show.status.rawValue, "isFeatured": show.isFeatured, "isFree": show.isFree,
            "seasonCount": show.seasonCount, "totalEpisodes": show.totalEpisodes,
            "totalViews": show.totalViews, "totalHypes": show.totalHypes, "totalCools": show.totalCools,
            "createdAt": Timestamp(date: show.createdAt), "updatedAt": FieldValue.serverTimestamp()
        ]
        if let config = show.scheduleConfig {
            data["releaseCadence"] = config.cadence.rawValue
            data["releaseWeekday"] = config.releaseWeekday
            data["releaseHour"]    = config.releaseHour
            data["releaseMinute"]  = config.releaseMinute
        }
        return data
    }

    private func decodeShow(from data: [String: Any], id: String) -> Show? {
        let title         = data["title"] as? String ?? ""
        let description   = data["description"] as? String ?? ""
        let creatorID     = data["creatorID"] as? String ?? ""
        let creatorName   = data["creatorName"] as? String ?? ""
        let format        = ShowFormat(rawValue: data["format"] as? String ?? "vertical") ?? .vertical
        let genre         = ShowGenre(rawValue: data["genre"] as? String ?? "other") ?? .other
        let contentType   = CollectionContentType(rawValue: data["contentType"] as? String ?? "series") ?? .series
        let tags          = (data["tags"] as? [String])?.compactMap { ShowTag(rawValue: $0) } ?? []
        let coverImageURL = data["coverImageURL"] as? String
        let thumbnailURL  = data["thumbnailURL"] as? String
        let status        = ShowStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft
        let isFeatured    = data["isFeatured"] as? Bool ?? false
        let isFree        = data["isFree"] as? Bool ?? false
        let seasonCount   = data["seasonCount"] as? Int ?? 0
        let totalEpisodes = data["totalEpisodes"] as? Int ?? 0
        let totalViews    = data["totalViews"] as? Int ?? 0
        let totalHypes    = data["totalHypes"] as? Int ?? 0
        let totalCools    = data["totalCools"] as? Int ?? 0
        let createdAt     = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt     = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let cadence       = data["releaseCadence"] as? String
        let weekday       = data["releaseWeekday"] as? Int
        let hour          = data["releaseHour"] as? Int
        let minute        = data["releaseMinute"] as? Int

        return Show(id: id, title: title, description: description,
                    creatorID: creatorID, creatorName: creatorName,
                    format: format, genre: genre, contentType: contentType, tags: tags,
                    coverImageURL: coverImageURL, thumbnailURL: thumbnailURL,
                    status: status, isFeatured: isFeatured, isFree: isFree,
                    seasonCount: seasonCount, totalEpisodes: totalEpisodes,
                    totalViews: totalViews, totalHypes: totalHypes, totalCools: totalCools,
                    createdAt: createdAt, updatedAt: updatedAt)
    }
    
    private func encodeSeason(_ season: Season) -> [String: Any] {
        ["id": season.id, "showId": season.showId, "number": season.number,
         "title": season.title, "description": season.description,
         "coverImageURL": season.coverImageURL ?? "", "status": season.status.rawValue,
         "episodeCount": season.episodeCount,
         "totalViews": season.totalViews, "totalHypes": season.totalHypes, "totalCools": season.totalCools,
         "createdAt": Timestamp(date: season.createdAt), "updatedAt": FieldValue.serverTimestamp()]
    }
    
    private func decodeSeason(from data: [String: Any], id: String, showId: String) -> Season? {
        Season(id: id, showId: showId,
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
               updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date())
    }
    
    private func encodeEpisode(_ ep: VideoCollection) -> [String: Any] {
        var data: [String: Any] = [
            "id": ep.id, "title": ep.title, "description": ep.description,
            "creatorID": ep.creatorID, "creatorName": ep.creatorName,
            "coverImageURL": ep.coverImageURL ?? "",
            "segmentIDs": ep.segmentIDs, "segmentCount": ep.segmentCount,
            "totalDuration": ep.totalDuration,
            "status": ep.status.rawValue, "visibility": ep.visibility.rawValue,
            "allowReplies": ep.allowReplies, "contentType": ep.contentType.rawValue,
            "allowStitchReplies": ep.allowStitchReplies, "isFree": ep.isFree,
            "createdAt": Timestamp(date: ep.createdAt), "updatedAt": FieldValue.serverTimestamp(),
            "totalViews": ep.totalViews, "totalHypes": ep.totalHypes,
            "totalCools": ep.totalCools, "totalReplies": ep.totalReplies, "totalShares": ep.totalShares,
            "showId": ep.showId ?? "", "seasonId": ep.seasonId ?? "",
            "episodeNumber": ep.episodeNumber ?? 0, "format": ep.format?.rawValue ?? "vertical",
            "compressed": ep.compressed, "splitIntoFiles": ep.splitIntoFiles,
            "originalFileSizeMB": ep.originalFileSizeMB ?? 0,
            "compressedFileSizeMB": ep.compressedFileSizeMB ?? 0,
        ]
        if let pub = ep.publishedAt { data["publishedAt"] = Timestamp(date: pub) }
        if let ads = ep.adSlots {
            data["adSlots"] = ads.map { ["afterSegmentIndex": $0.afterSegmentIndex,
                                          "insertAfterTime": $0.insertAfterTime,
                                          "type": $0.type,
                                          "durationSeconds": $0.durationSeconds] as [String: Any] }
        }
        return data
    }
    
    private func decodeEpisode(from data: [String: Any], id: String) -> VideoCollection? {
        let title = data["title"] as? String ?? ""
        let desc = data["description"] as? String ?? ""
        let cid = data["creatorID"] as? String ?? ""
        let cname = data["creatorName"] as? String ?? ""
        let cover = data["coverImageURL"] as? String
        let segIDs = data["segmentIDs"] as? [String] ?? []
        let segCount = data["segmentCount"] as? Int ?? 0
        let dur = data["totalDuration"] as? TimeInterval ?? 0
        let status = CollectionStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft
        let vis = CollectionVisibility(rawValue: data["visibility"] as? String ?? "public") ?? .publicVisible
        let replies = data["allowReplies"] as? Bool ?? true
        let cType = CollectionContentType(rawValue: data["contentType"] as? String ?? "series") ?? .series
        let stitch = data["allowStitchReplies"] as? Bool
        let isFree = data["isFree"] as? Bool ?? false
        let pub = (data["publishedAt"] as? Timestamp)?.dateValue()
        let created = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updated = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let views = data["totalViews"] as? Int ?? 0
        let hypes = data["totalHypes"] as? Int ?? 0
        let cools = data["totalCools"] as? Int ?? 0
        let tReplies = data["totalReplies"] as? Int ?? 0
        let shares = data["totalShares"] as? Int ?? 0
        let showId = data["showId"] as? String
        let seasonId = data["seasonId"] as? String
        let epNum = data["episodeNumber"] as? Int
        let fmt = ShowFormat(rawValue: data["format"] as? String ?? "vertical")
        let comp = data["compressed"] as? Bool ?? false
        let split = data["splitIntoFiles"] as? Bool ?? false
        let origSize = data["originalFileSizeMB"] as? Double
        let compSize = data["compressedFileSizeMB"] as? Double
        let adsRaw = data["adSlots"] as? [[String: Any]]
        let ads = adsRaw?.map {
            AdSlot(afterSegmentIndex: $0["afterSegmentIndex"] as? Int ?? 0,
                   insertAfterTime: $0["insertAfterTime"] as? TimeInterval ?? 0,
                   type: $0["type"] as? String ?? "standard",
                   durationSeconds: $0["durationSeconds"] as? TimeInterval ?? 30)
        }
        
        return VideoCollection(
            id: id, title: title, description: desc,
            creatorID: cid, creatorName: cname, coverImageURL: cover,
            segmentIDs: segIDs, segmentCount: segCount, totalDuration: dur,
            status: status, visibility: vis, allowReplies: replies,
            contentType: cType, allowStitchReplies: stitch, isFree: isFree,
            showId: showId, seasonId: seasonId, episodeNumber: epNum, format: fmt,
            compressed: comp, splitIntoFiles: split,
            originalFileSizeMB: origSize, compressedFileSizeMB: compSize, adSlots: ads,
            publishedAt: pub, createdAt: created, updatedAt: updated,
            totalViews: views, totalHypes: hypes, totalCools: cools,
            totalReplies: tReplies, totalShares: shares)
    }
}
