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
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: sevenDaysAgo))
            .order(by: FirebaseSchema.VideoDocument.createdAt)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { createThreadFromDocument($0) }
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
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: twentyFourHoursAgo))
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { createThreadFromDocument($0) }.shuffled()
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
}
