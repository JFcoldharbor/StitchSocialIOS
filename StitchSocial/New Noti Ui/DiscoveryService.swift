//
//  DiscoveryService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Discovery with Deep Time-Based Randomization
//  Dependencies: VideoService, Firebase Firestore
//  Features: Deep randomized discovery, varied content across all time periods
//  STRATEGY: Show 30% recent + 70% older content for true discovery experience
//
//  NOTE: RecentUser and LeaderboardVideo types should be defined in RecentUser.swift
//        (see document index 17 in project files)
//

import Foundation
import FirebaseFirestore

/// Discovery service with deep time-based randomization
@MainActor
class DiscoveryService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Configuration
    
    private let defaultBatchSize = 40
    
    // MARK: - DEEP RANDOMIZED DISCOVERY
    
    /// Get discovery videos with deep time randomization (not just newest)
    /// Returns mix of: 30% very recent, 25% recent, 20% medium, 15% older, 10% deep cuts
    func getDeepRandomizedDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔍 DISCOVERY DEEP: Loading randomized content across all time periods")
        
        var allThreads: [ThreadData] = []
        
        // STRATEGY: Mix content from different time periods for variety
        
        // 30% Very Recent (last 24 hours) - Keep it fresh
        let veryRecentLimit = Int(Double(limit) * 0.3)
        let veryRecent = try await getDiscoveryInTimeRange(
            startDate: Date().addingTimeInterval(-24 * 60 * 60),
            endDate: Date(),
            limit: veryRecentLimit
        )
        allThreads.append(contentsOf: veryRecent)
        print("🔍 Loaded \(veryRecent.count) very recent (24hrs)")
        
        // 25% Recent (1-7 days)
        let recentLimit = Int(Double(limit) * 0.25)
        let recent = try await getDiscoveryInTimeRange(
            startDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            endDate: Date().addingTimeInterval(-24 * 60 * 60),
            limit: recentLimit
        )
        allThreads.append(contentsOf: recent)
        print("🔍 Loaded \(recent.count) recent (1-7 days)")
        
        // 20% Medium (7-30 days)
        let mediumLimit = Int(Double(limit) * 0.2)
        let medium = try await getDiscoveryInTimeRange(
            startDate: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            endDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            limit: mediumLimit
        )
        allThreads.append(contentsOf: medium)
        print("🔍 Loaded \(medium.count) medium (7-30 days)")
        
        // 15% Older (30-90 days)
        let olderLimit = Int(Double(limit) * 0.15)
        let older = try await getDiscoveryInTimeRange(
            startDate: Date().addingTimeInterval(-90 * 24 * 60 * 60),
            endDate: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            limit: olderLimit
        )
        allThreads.append(contentsOf: older)
        print("🔍 Loaded \(older.count) older (30-90 days)")
        
        // 10% Deep Cuts (90-365 days) - Hidden gems
        let deepLimit = limit - allThreads.count // Fill remaining
        let deepCuts = try await getDiscoveryInTimeRange(
            startDate: Date().addingTimeInterval(-365 * 24 * 60 * 60),
            endDate: Date().addingTimeInterval(-90 * 24 * 60 * 60),
            limit: deepLimit
        )
        allThreads.append(contentsOf: deepCuts)
        print("🔍 Loaded \(deepCuts.count) deep cuts (90-365 days)")
        
        // CRITICAL: Ultra-shuffle for maximum randomization
        let ultraShuffled = ultraShuffleByCreator(threads: allThreads)
        
        print("✅ DISCOVERY DEEP: Loaded \(ultraShuffled.count) ultra-randomized threads")
        
        return ultraShuffled
    }
    
    // MARK: - Time Range Query Helper
    
    /// Query threads within specific time range
    private func getDiscoveryInTimeRange(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [ThreadData] {
        
        guard limit > 0 else { return [] }
        
        // Query parent threads in time range
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField(FirebaseSchema.VideoDocument.createdAt, isLessThan: Timestamp(date: endDate))
            .limit(to: limit * 3) // Get extra for filtering/shuffling
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        
        for document in snapshot.documents {
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        // Shuffle within time range and limit
        return Array(threads.shuffled().prefix(limit))
    }
    
    // MARK: - Thread Creation from Document
    
    /// Create ThreadData from Firestore document
    private func createThreadFromDocument(_ document: DocumentSnapshot) -> ThreadData? {
        
        let data = document.data()
        guard let data = data else { return nil }
        
        // Extract video data
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        
        // Skip videos with empty IDs
        guard !id.isEmpty else {
            print("⚠️ DISCOVERY: Skipping video with empty ID")
            return nil
        }
        
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
        
        // Create thread with empty children
        return ThreadData(
            id: threadID,
            parentVideo: parentVideo,
            childVideos: []
        )
    }
    
    // MARK: - Ultra Shuffle for Maximum Variety
    
    /// Shuffle threads to ensure maximum creator variety
    /// Never shows same creator back-to-back
    private func ultraShuffleByCreator(threads: [ThreadData]) -> [ThreadData] {
        guard threads.count > 1 else { return threads }
        
        // Group by creator
        var creatorBuckets: [String: [ThreadData]] = [:]
        for thread in threads {
            let creatorID = thread.parentVideo.creatorID
            creatorBuckets[creatorID, default: []].append(thread)
        }
        
        // Shuffle each creator's videos
        var shuffledBuckets = creatorBuckets.mapValues { $0.shuffled() }
        
        // Interleave to avoid same creator back-to-back
        var result: [ThreadData] = []
        var recentCreators: [String] = [] // Track last 5 creators
        let maxRecentTracking = 5
        
        while !shuffledBuckets.isEmpty {
            // Find creators NOT in recent list
            let availableCreators = shuffledBuckets.keys.filter { !recentCreators.contains($0) }
            
            let chosenCreatorID: String
            if !availableCreators.isEmpty {
                // Pick random from available creators
                chosenCreatorID = availableCreators.randomElement()!
            } else {
                // All creators used recently - pick random from any
                chosenCreatorID = shuffledBuckets.keys.randomElement()!
                recentCreators.removeAll() // Reset tracking
            }
            
            // Take one video from chosen creator
            if var creatorVideos = shuffledBuckets[chosenCreatorID], !creatorVideos.isEmpty {
                let video = creatorVideos.removeFirst()
                result.append(video)
                
                // Update recent creators tracking
                recentCreators.append(chosenCreatorID)
                if recentCreators.count > maxRecentTracking {
                    recentCreators.removeFirst()
                }
                
                // Update or remove bucket
                if creatorVideos.isEmpty {
                    shuffledBuckets.removeValue(forKey: chosenCreatorID)
                } else {
                    shuffledBuckets[chosenCreatorID] = creatorVideos
                }
            }
        }
        
        print("🎲 DISCOVERY: Ultra-shuffled \(result.count) videos with max variety")
        return result
    }
    
    // MARK: - Category-Based Discovery
    
    /// Get trending content (high engagement)
    func getTrendingDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔥 DISCOVERY: Loading trending content")
        
        // Get recent high-engagement content
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: sevenDaysAgo))
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        for document in snapshot.documents {
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        print("✅ DISCOVERY: Loaded \(threads.count) trending threads")
        return threads
    }
    
    /// Get popular content (all-time high engagement)
    func getPopularDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("⭐ DISCOVERY: Loading popular content")
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        for document in snapshot.documents {
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        print("✅ DISCOVERY: Loaded \(threads.count) popular threads")
        return threads
    }
    
    /// Get only very recent content (last 24 hours)
    func getRecentDiscovery(limit: Int = 40) async throws -> [ThreadData] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🕐 DISCOVERY: Loading recent content (24hrs)")
        
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: twentyFourHoursAgo))
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        for document in snapshot.documents {
            if let thread = createThreadFromDocument(document) {
                threads.append(thread)
            }
        }
        
        // Shuffle for variety
        let shuffled = threads.shuffled()
        
        print("✅ DISCOVERY: Loaded \(shuffled.count) recent threads")
        return shuffled
    }
    
    // MARK: - Legacy Support (for backward compatibility)
    
    /// Original discovery method - now uses deep randomization
    func getDiscoveryParentThreadsOnly(limit: Int = 40, lastDocument: DocumentSnapshot? = nil) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        // Redirect to deep randomized discovery
        let threads = try await getDeepRandomizedDiscovery(limit: limit)
        
        return (threads: threads, lastDocument: nil, hasMore: true)
    }
    
    // MARK: - Recent Users (for suggestions)
    
    /// Get recently joined users (last 7 days, excluding private accounts)
    func getRecentUsers(limit: Int = 20) async throws -> [RecentUser] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🆕 DISCOVERY: Fetching recent users (last 7 days, limit: \(limit))")
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: sevenDaysAgo))
            .whereField(FirebaseSchema.UserDocument.isPrivate, isEqualTo: false)
            .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let recentUsers = snapshot.documents.compactMap { doc -> RecentUser? in
            let data = doc.data()
            
            guard let username = data[FirebaseSchema.UserDocument.username] as? String,
                  let displayName = data[FirebaseSchema.UserDocument.displayName] as? String,
                  let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
            let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
            
            return RecentUser(
                id: doc.documentID,
                username: username,
                displayName: displayName,
                profileImageURL: profileImageURL,
                joinedAt: createdAt,
                isVerified: isVerified
            )
        }
        
        print("✅ DISCOVERY: Found \(recentUsers.count) recent users")
        return recentUsers
    }
    
    /// Get hype leaderboard (last 7 days)
    func getHypeLeaderboard(limit: Int = 10) async throws -> [LeaderboardVideo] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔥 DISCOVERY: Fetching hype leaderboard (last 7 days, limit: \(limit))")
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: sevenDaysAgo))
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let leaderboardVideos = snapshot.documents.compactMap { doc -> LeaderboardVideo? in
            let data = doc.data()
            
            guard let title = data[FirebaseSchema.VideoDocument.title] as? String,
                  let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String,
                  let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String,
                  let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int,
                  let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int,
                  let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String,
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String
            
            return LeaderboardVideo(
                id: doc.documentID,
                title: title,
                creatorID: creatorID,
                creatorName: creatorName,
                thumbnailURL: thumbnailURL,
                hypeCount: hypeCount,
                coolCount: coolCount,
                temperature: temperature,
                createdAt: createdAt
            )
        }
        
        print("✅ DISCOVERY: Found \(leaderboardVideos.count) leaderboard videos")
        return leaderboardVideos
    }
}
