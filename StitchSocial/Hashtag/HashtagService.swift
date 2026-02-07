//
//  HashtagService.swift
//  StitchSocial
//
//  Created by James Garmon on 2/5/26.
//


//
//  HashtagService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Hashtag Query & Aggregation
//  Dependencies: FirebaseSchema, HashtagModels, CoreVideoMetadata
//  Features: Trending hashtags, filter videos by tag, velocity calculation
//

import Foundation
import FirebaseFirestore

@MainActor
class HashtagService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var isLoading = false
    
    // Cache to avoid redundant queries (tag -> videos)
    private var tagVideoCache: [String: [CoreVideoMetadata]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 120 // 2 min
    
    // MARK: - Trending Hashtags
    
    /// Fetch trending hashtags by scanning recent videos
    /// Aggregates hashtag usage + hype velocity from last 24h
    func loadTrendingHashtags(limit: Int = 20) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            
            // Query recent videos that have hashtags
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: cutoff))
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 200)
                .getDocuments()
            
            // Aggregate by hashtag
            var tagStats: [String: TagAccumulator] = [:]
            
            for doc in snapshot.documents {
                let data = doc.data()
                guard let tags = data[FirebaseSchema.VideoDocument.hashtags] as? [String] else { continue }
                let hypes = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
                let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
                
                for tag in tags {
                    let key = tag.lowercased()
                    if tagStats[key] == nil {
                        tagStats[key] = TagAccumulator(tag: key)
                    }
                    tagStats[key]?.addVideo(hypes: hypes, createdAt: createdAt)
                }
            }
            
            // Also count total videos per tag (not just recent) for popular tags
            let topTags = tagStats.sorted { $0.value.totalHypes > $1.value.totalHypes }.prefix(limit)
            
            var trending: [TrendingHashtag] = []
            for (_, acc) in topTags {
                let ageHours = max(1.0, Date().timeIntervalSince(acc.earliestVideo) / 3600.0)
                let velocity = Double(acc.totalHypes) / ageHours
                
                // Get total video count for this tag (all time)
                let totalCount = try await getVideoCountForTag(acc.tag)
                
                trending.append(TrendingHashtag(
                    tag: acc.tag,
                    videoCount: totalCount,
                    recentVideoCount: acc.videoCount,
                    totalHypes: acc.totalHypes,
                    velocity: velocity,
                    lastUsedAt: acc.latestVideo
                ))
            }
            
            // Sort by velocity (fastest growing first)
            trendingHashtags = trending.sorted { $0.velocity > $1.velocity }
            
            print("ðŸ·ï¸ HASHTAG SERVICE: Loaded \(trendingHashtags.count) trending hashtags")
            
        } catch {
            print("âŒ HASHTAG SERVICE: Failed to load trending: \(error)")
        }
    }
    
    // MARK: - Videos by Hashtag
    
    /// Get videos for a specific hashtag, sorted by discoverabilityScore
    func getVideosForHashtag(
        _ tag: String,
        limit: Int = 30,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (videos: [CoreVideoMetadata], lastDoc: DocumentSnapshot?, hasMore: Bool) {
        
        let key = tag.lowercased()
        
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.hashtags, arrayContains: key)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        let videoService = VideoService()
        
        let videos = snapshot.documents.map { doc in
            videoService.createCoreVideoMetadata(from: doc.data(), id: doc.documentID)
        }
        
        // Sort client-side by discoverabilityScore (inApp content ranks higher)
        let sorted = videos.sorted { $0.discoverabilityScore > $1.discoverabilityScore }
        
        return (sorted, snapshot.documents.last, snapshot.documents.count >= limit)
    }
    
    // MARK: - Video Count for Tag
    
    /// Get total number of videos with a given hashtag
    func getVideoCountForTag(_ tag: String) async throws -> Int {
        let key = tag.lowercased()
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.hashtags, arrayContains: key)
            .count
            .getAggregation(source: .server)
        
        return Int(truncating: snapshot.count)
    }
    
    // MARK: - Search Hashtags
    
    /// Filter hashtags by prefix (for search bar autocomplete)
    func searchHashtags(prefix: String) -> [TrendingHashtag] {
        let query = prefix.lowercased().replacingOccurrences(of: "#", with: "")
        guard !query.isEmpty else { return trendingHashtags }
        return trendingHashtags.filter { $0.tag.hasPrefix(query) }
    }
    
    // MARK: - Extract Hashtags from Text
    
    /// Parse #hashtags from a title or description string
    /// Returns array of tags without the # prefix, lowercased
    static func extractHashtags(from text: String) -> [String] {
        let pattern = "#([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[tagRange]).lowercased()
        }
    }
    
    // MARK: - Cache Helpers
    
    func clearCache() {
        tagVideoCache.removeAll()
        cacheTimestamps.removeAll()
    }
    
    // MARK: - Backfill Hashtags
    
    /// One-time backfill: Extract hashtags from all existing video descriptions
    /// Call this once to populate hashtags field for legacy content
    func backfillAllHashtags(batchSize: Int = 100) async -> (updated: Int, failed: Int) {
        var updated = 0
        var failed = 0
        var lastDoc: DocumentSnapshot? = nil
        
        print("🏷️ BACKFILL: Starting hashtag backfill...")
        
        repeat {
            do {
                var query: Query = db.collection(FirebaseSchema.Collections.videos)
                    .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                    .limit(to: batchSize)
                
                if let lastDoc = lastDoc {
                    query = query.start(afterDocument: lastDoc)
                }
                
                let snapshot = try await query.getDocuments()
                
                if snapshot.documents.isEmpty {
                    break
                }
                
                lastDoc = snapshot.documents.last
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    let description = data[FirebaseSchema.VideoDocument.description] as? String ?? ""
                    let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
                    let existingHashtags = data[FirebaseSchema.VideoDocument.hashtags] as? [String] ?? []
                    
                    // Skip if already has hashtags
                    if !existingHashtags.isEmpty {
                        continue
                    }
                    
                    // Extract from description and title
                    let combined = "\(title) \(description)"
                    let hashtags = HashtagService.extractHashtags(from: combined)
                    
                    if !hashtags.isEmpty {
                        do {
                            try await db.collection(FirebaseSchema.Collections.videos)
                                .document(doc.documentID)
                                .updateData([
                                    FirebaseSchema.VideoDocument.hashtags: hashtags
                                ])
                            updated += 1
                            print("✅ BACKFILL: \(doc.documentID) -> \(hashtags)")
                        } catch {
                            failed += 1
                            print("❌ BACKFILL: Failed \(doc.documentID) - \(error)")
                        }
                    }
                }
                
                print("🏷️ BACKFILL: Processed batch, updated: \(updated), failed: \(failed)")
                
            } catch {
                print("❌ BACKFILL: Batch failed - \(error)")
                break
            }
        } while lastDoc != nil
        
        print("🏷️ BACKFILL: Complete! Updated: \(updated), Failed: \(failed)")
        return (updated, failed)
    }
    
    // MARK: - Batch Score Recalculation
    
    /// Recalculate qualityScore and discoverabilityScore for all videos
    /// Should be run periodically or after significant engagement changes
    func recalculateAllScores(batchSize: Int = 50) async -> (updated: Int, failed: Int) {
        var updated = 0
        var failed = 0
        var lastDoc: DocumentSnapshot? = nil
        
        print("📊 SCORE RECALC: Starting batch recalculation...")
        
        repeat {
            do {
                var query: Query = db.collection(FirebaseSchema.Collections.videos)
                    .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                    .limit(to: batchSize)
                
                if let lastDoc = lastDoc {
                    query = query.start(afterDocument: lastDoc)
                }
                
                let snapshot = try await query.getDocuments()
                
                if snapshot.documents.isEmpty {
                    break
                }
                
                lastDoc = snapshot.documents.last
                
                let videoService = VideoService()
                
                for doc in snapshot.documents {
                    let video = videoService.createCoreVideoMetadata(from: doc.data(), id: doc.documentID)
                    let (newQuality, newDiscoverability) = ContentScoreCalculator.recalculateScores(for: video)
                    
                    // Only update if scores changed significantly
                    let qualityDiff = abs(newQuality - video.qualityScore)
                    let discoverabilityDiff = abs(newDiscoverability - video.discoverabilityScore)
                    
                    if qualityDiff >= 2 || discoverabilityDiff >= 0.02 {
                        do {
                            try await db.collection(FirebaseSchema.Collections.videos)
                                .document(doc.documentID)
                                .updateData([
                                    FirebaseSchema.VideoDocument.qualityScore: newQuality,
                                    FirebaseSchema.VideoDocument.discoverabilityScore: newDiscoverability
                                ])
                            updated += 1
                            print("📊 RECALC: \(doc.documentID) quality: \(video.qualityScore)→\(newQuality), disc: \(String(format: "%.2f", video.discoverabilityScore))→\(String(format: "%.2f", newDiscoverability))")
                        } catch {
                            failed += 1
                        }
                    }
                }
                
                print("📊 SCORE RECALC: Batch done, updated: \(updated)")
                
            } catch {
                print("❌ SCORE RECALC: Batch failed - \(error)")
                break
            }
        } while lastDoc != nil
        
        print("📊 SCORE RECALC: Complete! Updated: \(updated), Failed: \(failed)")
        return (updated, failed)
    }
}

// MARK: - Internal Accumulator

private struct TagAccumulator {
    let tag: String
    var videoCount: Int = 0
    var totalHypes: Int = 0
    var earliestVideo: Date = Date()
    var latestVideo: Date = Date.distantPast
    
    mutating func addVideo(hypes: Int, createdAt: Date) {
        videoCount += 1
        totalHypes += hypes
        if createdAt < earliestVideo { earliestVideo = createdAt }
        if createdAt > latestVideo { latestVideo = createdAt }
    }
}
