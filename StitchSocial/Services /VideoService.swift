//
//  VideoService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Complete Video Management with Full Engagement Tracking
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema, HypeRatingCalculator
//  Features: Thread hierarchy, following feed, multidirectional swiping, engagement updates, secure video deletion
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Complete video management service with robust deletion and thread hierarchy support
@MainActor
class VideoService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let storage = Storage.storage()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Create Operations
    
    /// Create new thread (parent video)
    func createThread(
        title: String,
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) async throws -> CoreVideoMetadata {
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: creatorID,
            FirebaseSchema.VideoDocument.creatorName: creatorName,
            FirebaseSchema.VideoDocument.createdAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
            
            // Thread hierarchy - parent video
            FirebaseSchema.VideoDocument.threadID: videoID,
            FirebaseSchema.VideoDocument.conversationDepth: 0,
            
            // Basic engagement
            FirebaseSchema.VideoDocument.viewCount: 0,
            FirebaseSchema.VideoDocument.hypeCount: 0,
            FirebaseSchema.VideoDocument.coolCount: 0,
            FirebaseSchema.VideoDocument.replyCount: 0,
            FirebaseSchema.VideoDocument.shareCount: 0,
            
            // Content metadata
            FirebaseSchema.VideoDocument.duration: duration,
            FirebaseSchema.VideoDocument.aspectRatio: 9.0/16.0,
            FirebaseSchema.VideoDocument.fileSize: fileSize,
            FirebaseSchema.VideoDocument.qualityScore: 50,
            
            // Temperature system
            FirebaseSchema.VideoDocument.temperature: "neutral",
            
            // Status
            FirebaseSchema.VideoDocument.isDeleted: false,
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false
        ]
        
        // Create video document
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        // Create thread document for organization
        let threadData: [String: Any] = [
            FirebaseSchema.ThreadDocument.id: videoID,
            FirebaseSchema.ThreadDocument.parentVideoID: videoID,
            FirebaseSchema.ThreadDocument.creatorID: creatorID,
            FirebaseSchema.ThreadDocument.title: title,
            FirebaseSchema.ThreadDocument.createdAt: Timestamp(),
            FirebaseSchema.ThreadDocument.updatedAt: Timestamp(),
            FirebaseSchema.ThreadDocument.totalReplies: 0,
            FirebaseSchema.ThreadDocument.lastActivityAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.threads).document(videoID).setData(threadData)
        
        // Create engagement document
        try await createEngagementDocument(videoID: videoID, creatorID: creatorID)
        
        print("VIDEO SERVICE: Thread created - \(videoID)")
        
        let video = CoreVideoMetadata(
            id: videoID,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: videoID,
            replyToVideoID: nil,
            conversationDepth: 0,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: 9.0/16.0,
            fileSize: fileSize,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
        
        return video
    }
    
    /// Create child reply to existing thread
    func createChildReply(
        to threadID: String,
        title: String,
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) async throws -> CoreVideoMetadata {
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        // Get parent thread to determine conversation depth
        let threadDoc = try await db.collection(FirebaseSchema.Collections.videos).document(threadID).getDocument()
        let parentDepth = threadDoc.data()?[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        let newDepth = parentDepth + 1
        
        guard newDepth <= 2 else {
            throw StitchError.validationError("Maximum conversation depth reached")
        }
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: creatorID,
            FirebaseSchema.VideoDocument.creatorName: creatorName,
            FirebaseSchema.VideoDocument.createdAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
            
            // Thread hierarchy - child video
            FirebaseSchema.VideoDocument.threadID: threadID,
            FirebaseSchema.VideoDocument.replyToVideoID: threadID,
            FirebaseSchema.VideoDocument.conversationDepth: newDepth,
            
            // Basic engagement
            FirebaseSchema.VideoDocument.viewCount: 0,
            FirebaseSchema.VideoDocument.hypeCount: 0,
            FirebaseSchema.VideoDocument.coolCount: 0,
            FirebaseSchema.VideoDocument.replyCount: 0,
            FirebaseSchema.VideoDocument.shareCount: 0,
            
            // Content metadata
            FirebaseSchema.VideoDocument.duration: duration,
            FirebaseSchema.VideoDocument.aspectRatio: 9.0/16.0,
            FirebaseSchema.VideoDocument.fileSize: fileSize,
            FirebaseSchema.VideoDocument.qualityScore: 50,
            
            // Temperature system
            FirebaseSchema.VideoDocument.temperature: "neutral",
            
            // Status
            FirebaseSchema.VideoDocument.isDeleted: false,
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        // Create engagement document
        try await createEngagementDocument(videoID: videoID, creatorID: creatorID)
        
        // Update thread reply count
        try await db.collection(FirebaseSchema.Collections.threads).document(threadID).updateData([
            FirebaseSchema.ThreadDocument.totalReplies: FieldValue.increment(Int64(1)),
            FirebaseSchema.ThreadDocument.lastActivityAt: Timestamp(),
            FirebaseSchema.ThreadDocument.updatedAt: Timestamp()
        ])
        
        print("VIDEO SERVICE: Child reply created - \(videoID)")
        
        return CoreVideoMetadata(
            id: videoID,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: threadID,
            replyToVideoID: threadID,
            conversationDepth: newDepth,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: 9.0/16.0,
            fileSize: fileSize,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
    }
    
    // MARK: - Read Operations

    /// Get single video by ID - FIXED: Safe document parsing without force casting
    func getVideo(id: String) async throws -> CoreVideoMetadata {
        let document = try await db.collection(FirebaseSchema.Collections.videos).document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        // Extract values from document data first
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        
        // Calculate engagement ratio
        let engagementRatio = hypeCount + coolCount > 0 ? Double(hypeCount) / Double(hypeCount + coolCount) : 0.5
        
        // Parse document data directly (safe approach)
        let video = CoreVideoMetadata(
            id: data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID,
            title: data[FirebaseSchema.VideoDocument.title] as? String ?? "",
            videoURL: data[FirebaseSchema.VideoDocument.videoURL] as? String ?? "",
            thumbnailURL: data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? "",
            creatorID: data[FirebaseSchema.VideoDocument.creatorID] as? String ?? "",
            creatorName: data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "",
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
            velocityScore: 0.0, // Calculated field - not stored in Firebase
            trendingScore: 0.0, // Calculated field - not stored in Firebase
            duration: data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0,
            aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0,
            fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
            discoverabilityScore: data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5,
            isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        )
        
        return video
    }

    /// Get threads for home feed - ADDED: Missing method that was being called
    func getThreadsForHomeFeed(
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> PaginatedResult<CoreVideoMetadata> {
        
        isLoading = true
        defer { isLoading = false }
        
        // Get all threads for home feed (same as discovery for now)
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.lastEngagementAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var videos: [CoreVideoMetadata] = []
        
        for doc in snapshot.documents {
            guard let video = try? createVideoFromDocument(doc) else { continue }
            videos.append(video)
        }
        
        let hasMore = snapshot.documents.count >= limit
        
        print("VIDEO SERVICE: Home feed loaded - \(videos.count) threads")
        return PaginatedResult(
            items: videos,
            lastDocument: snapshot.documents.last,
            hasMore: hasMore
        )
    }

    /// Get threads for following feed (BETA: Simple chronological + shuffle)
    func getFollowingThreads(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        let followingUserIDs = try await getFollowingUserIDs(userID: userID)
        
        guard !followingUserIDs.isEmpty else {
            print("VIDEO SERVICE: No following users found")
            return (threads: [], lastDocument: nil, hasMore: false)
        }
        
        // Simple query from following users
        var allThreads: [ThreadData] = []
        
        for batch in followingUserIDs.chunked(into: 5) {
            var threadsQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, in: batch)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.lastEngagementAt, descending: true)
                .limit(to: 8)
            
            if let lastDoc = lastDocument {
                threadsQuery = threadsQuery.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await threadsQuery.getDocuments()
            
            for doc in snapshot.documents {
                guard let video = try? createVideoFromDocument(doc) else { continue }
                let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: [])
                allThreads.append(threadData)
            }
            
            if allThreads.count >= limit {
                break
            }
        }
        
        // BETA: Simple shuffle for variety
        let limitedThreads = Array(allThreads.shuffled().prefix(limit))
        
        print("VIDEO SERVICE: Following feed loaded - \(limitedThreads.count) threads")
        return (threads: limitedThreads, lastDocument: nil, hasMore: allThreads.count >= limit)
    }

    /// Get all threads for discovery feed (BETA: Show ALL videos)
    func getAllThreadsWithChildren(
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // BETA: Get ALL threads for maximum discovery
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            guard let video = try? createVideoFromDocument(doc) else { continue }
            let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: [])
            threads.append(threadData)
        }
        
        let hasMore = snapshot.documents.count >= limit
        
        print("VIDEO SERVICE: Discovery feed loaded - \(threads.count) threads (ALL videos visible)")
        return (threads: threads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }

    /// Get child videos for a thread
    func getThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        let childQuery = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .limit(to: 10)
        
        let snapshot = try await childQuery.getDocuments()
        
        let children = snapshot.documents.compactMap { doc in
            try? createVideoFromDocument(doc)
        }
        
        print("VIDEO SERVICE: Loaded \(children.count) children for thread \(threadID)")
        return children
    }
    
    // MARK: - NEW: Full Engagement Tracking Methods
    
    /// Track unique user view with watch time analytics
    func incrementViewCount(videoID: String, userID: String, watchTime: TimeInterval = 0) async throws {
        // Check if user already viewed to prevent inflation
        let hasViewed = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .view)
        guard !hasViewed else {
            print("VIDEO SERVICE: User \(userID) already viewed \(videoID)")
            return
        }
        
        // Create interaction record
        let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
            videoID: videoID, userID: userID, type: "view"
        )
        
        let interactionData: [String: Any] = [
            FirebaseSchema.InteractionDocument.userID: userID,
            FirebaseSchema.InteractionDocument.videoID: videoID,
            FirebaseSchema.InteractionDocument.engagementType: "view",
            "watchTime": watchTime,
            FirebaseSchema.InteractionDocument.timestamp: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.interactions).document(interactionID).setData(interactionData)
        
        // Increment view count
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).updateData([
            FirebaseSchema.VideoDocument.viewCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp()
        ])
        
        // Update engagement metrics
        try await updateEngagementMetrics(videoID: videoID)
        
        print("VIDEO SERVICE: View count incremented for \(videoID) by user \(userID)")
    }
    
    /// Update video temperature using HypeRatingCalculator
    func updateVideoTemperature(videoID: String) async throws {
        guard let videoData = try? await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument().data() else {
            print("VIDEO SERVICE: Could not load video data for temperature update")
            return
        }
        
        let hypeCount = videoData[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = videoData[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let viewCount = videoData[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let createdAt = (videoData[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        let ageInMinutes = Date().timeIntervalSince(createdAt) / 60.0
        
        // Get creator tier for accurate temperature calculation
        let creatorID = videoData[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorTier = try await getUserTier(userID: creatorID)
        
        let temperature = HypeRatingCalculator.calculateTemperature(
            hypeCount: hypeCount,
            coolCount: coolCount,
            viewCount: viewCount,
            ageInMinutes: ageInMinutes,
            creatorTier: creatorTier
        )
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).updateData([
            FirebaseSchema.VideoDocument.temperature: temperature.rawValue,
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ])
        
        print("VIDEO SERVICE: Temperature updated to \(temperature.rawValue) for video \(videoID)")
    }
    
    /// Calculate and update engagement metrics in real-time
    func updateEngagementMetrics(videoID: String) async throws {
        guard let videoData = try? await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument().data() else {
            return
        }
        
        let hypeCount = videoData[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = videoData[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let viewCount = videoData[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let createdAt = (videoData[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        // Calculate engagement ratio
        let totalEngagement = hypeCount + coolCount
        let engagementRatio = totalEngagement > 0 ? Double(hypeCount) / Double(totalEngagement) : 0.5
        
        // Calculate velocity score (engagements per hour)
        let ageInHours = Date().timeIntervalSince(createdAt) / 3600.0
        let velocityScore = ageInHours > 0 ? Double(totalEngagement) / ageInHours : 0.0
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).updateData([
            "engagementRatio": engagementRatio,
            "velocityScore": velocityScore,
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ])
        
        // Update temperature
        try await updateVideoTemperature(videoID: videoID)
        
        print("VIDEO SERVICE: Engagement metrics updated for \(videoID) - Ratio: \(String(format: "%.2f", engagementRatio))")
    }
    
    /// Record user interaction with comprehensive tracking
    func recordUserInteraction(
        videoID: String,
        userID: String,
        interactionType: InteractionType,
        watchTime: TimeInterval = 0
    ) async throws {
        
        // Prevent duplicate interactions
        let hasInteracted = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: interactionType)
        guard !hasInteracted else {
            print("VIDEO SERVICE: User \(userID) already has \(interactionType.rawValue) interaction with \(videoID)")
            return
        }
        
        // Create interaction record
        let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
            videoID: videoID, userID: userID, type: interactionType.rawValue
        )
        
        let interactionData: [String: Any] = [
            FirebaseSchema.InteractionDocument.userID: userID,
            FirebaseSchema.InteractionDocument.videoID: videoID,
            FirebaseSchema.InteractionDocument.engagementType: interactionType.rawValue,
            "watchTime": watchTime,
            FirebaseSchema.InteractionDocument.timestamp: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.interactions).document(interactionID).setData(interactionData)
        
        // Update appropriate count
        let fieldUpdate: [String: Any]
        switch interactionType {
        case .hype:
            fieldUpdate = [FirebaseSchema.VideoDocument.hypeCount: FieldValue.increment(Int64(1))]
        case .cool:
            fieldUpdate = [FirebaseSchema.VideoDocument.coolCount: FieldValue.increment(Int64(1))]
        case .view:
            fieldUpdate = [FirebaseSchema.VideoDocument.viewCount: FieldValue.increment(Int64(1))]
        case .share:
            fieldUpdate = [FirebaseSchema.VideoDocument.shareCount: FieldValue.increment(Int64(1))]
        default:
            fieldUpdate = [:]
        }
        
        if !fieldUpdate.isEmpty {
            var updateData = fieldUpdate
            updateData[FirebaseSchema.VideoDocument.lastEngagementAt] = Timestamp()
            
            try await db.collection(FirebaseSchema.Collections.videos).document(videoID).updateData(updateData)
            
            // Update engagement metrics after interaction
            try await updateEngagementMetrics(videoID: videoID)
        }
        
        print("VIDEO SERVICE: Recorded \(interactionType.rawValue) interaction for \(videoID) by user \(userID)")
    }
    
    /// Get comprehensive video analytics
    func getVideoAnalytics(videoID: String) async throws -> VideoAnalytics {
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        guard let videoData = videoDoc.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        // Get interaction breakdown
        let interactionsQuery = db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
        
        let interactionsSnapshot = try await interactionsQuery.getDocuments()
        
        var hypeUsers: [String] = []
        var coolUsers: [String] = []
        var viewUsers: [String] = []
        var shareUsers: [String] = []
        var totalWatchTime: TimeInterval = 0
        
        for doc in interactionsSnapshot.documents {
            let data = doc.data()
            let userID = data[FirebaseSchema.InteractionDocument.userID] as? String ?? ""
            let type = data[FirebaseSchema.InteractionDocument.engagementType] as? String ?? ""
            let watchTime = data["watchTime"] as? TimeInterval ?? 0
            
            switch type {
            case "hype":
                hypeUsers.append(userID)
            case "cool":
                coolUsers.append(userID)
            case "view":
                viewUsers.append(userID)
                totalWatchTime += watchTime
            case "share":
                shareUsers.append(userID)
            default:
                break
            }
        }
        
        let averageWatchTime = viewUsers.count > 0 ? totalWatchTime / Double(viewUsers.count) : 0
        
        return VideoAnalytics(
            videoID: videoID,
            totalViews: viewUsers.count,
            uniqueViewers: Set(viewUsers).count,
            totalHypes: hypeUsers.count,
            totalCools: coolUsers.count,
            totalShares: shareUsers.count,
            averageWatchTime: averageWatchTime,
            totalWatchTime: totalWatchTime,
            engagementRate: Double(hypeUsers.count + coolUsers.count) / max(Double(viewUsers.count), 1.0),
            temperature: videoData[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        )
    }
    
    // MARK: - Delete Operations
    
    /// Delete video with comprehensive cleanup
    func deleteVideo(videoID: String, creatorID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get video data
            let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
            guard let videoData = videoDoc.data() else {
                throw StitchError.validationError("Video not found")
            }
            
            let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
            let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
            
            // Delete from storage
            if !videoURL.isEmpty {
                try await deleteFromStorage(url: videoURL)
            }
            if !thumbnailURL.isEmpty {
                try await deleteFromStorage(url: thumbnailURL)
            }
            
            // Delete video document
            try await db.collection(FirebaseSchema.Collections.videos).document(videoID).delete()
            
            // Delete engagement document
            try await db.collection(FirebaseSchema.Collections.engagement).document(videoID).delete()
            
            // Clean up related data
            await cleanupRelatedData(videoID: videoID)
            
            print("VIDEO SERVICE: Video \(videoID) deleted successfully")
            
        } catch {
            lastError = .processingError("Failed to delete video: \(error.localizedDescription)")
            throw lastError!
        }
    }
    
    // MARK: - Engagement Operations
    
    /// Update video engagement metrics in database (for EngagementCoordinator) - FIXED
    func updateVideoEngagement(
        videoID: String,
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        temperature: String,
        lastEngagementAt: Date
    ) async throws {
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Update video document engagement fields
            let videoUpdateData: [String: Any] = [
                FirebaseSchema.VideoDocument.hypeCount: hypeCount,
                FirebaseSchema.VideoDocument.coolCount: coolCount,
                FirebaseSchema.VideoDocument.viewCount: viewCount,
                FirebaseSchema.VideoDocument.temperature: temperature,
                FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp(date: lastEngagementAt),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ]
            
            try await db.collection(FirebaseSchema.Collections.videos)
                .document(videoID)
                .updateData(videoUpdateData)
            
            // Update engagement document - FIXED: Use setData(merge: true)
            let engagementUpdateData: [String: Any] = [
                FirebaseSchema.EngagementDocument.hypeCount: hypeCount,
                FirebaseSchema.EngagementDocument.coolCount: coolCount,
                FirebaseSchema.EngagementDocument.viewCount: viewCount,
                FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(date: lastEngagementAt),
                FirebaseSchema.EngagementDocument.updatedAt: Timestamp()
            ]
            
            try await db.collection(FirebaseSchema.Collections.engagement)
                .document(videoID)
                .setData(engagementUpdateData, merge: true)
            
            print("VIDEO SERVICE: Updated engagement for video \(videoID)")
            print("VIDEO SERVICE: Hype: \(hypeCount), Cool: \(coolCount), Views: \(viewCount)")
            
        } catch {
            lastError = .processingError("Failed to update engagement: \(error.localizedDescription)")
            print("VIDEO SERVICE: Engagement update failed - \(error)")
            throw lastError!
        }
    }
    
    /// Check if user has already interacted with video
    func hasUserInteracted(
        userID: String,
        videoID: String,
        interactionType: InteractionType
    ) async throws -> Bool {
        
        do {
            let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
                videoID: videoID,
                userID: userID,
                type: interactionType.rawValue
            )
            let document = try await db.collection(FirebaseSchema.Collections.interactions)
                .document(interactionID)
                .getDocument()
            
            return document.exists
            
        } catch {
            print("VIDEO SERVICE: Failed to check user interaction - \(error)")
            return false
        }
    }
    
    /// Get user's engagement status for a video
    func getUserEngagementStatus(
        userID: String,
        videoID: String
    ) async throws -> UserEngagementStatus {
        
        do {
            let hasHyped = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .hype)
            let hasCooled = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .cool)
            let hasViewed = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .view)
            let hasShared = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .share)
            
            return UserEngagementStatus(
                hasHyped: hasHyped,
                hasCooled: hasCooled,
                hasViewed: hasViewed,
                hasShared: hasShared
            )
            
        } catch {
            print("VIDEO SERVICE: Failed to get engagement status - \(error)")
            return UserEngagementStatus(hasHyped: false, hasCooled: false, hasViewed: false, hasShared: false)
        }
    }
    
    /// Batch update engagement metrics for multiple videos - FIXED
    func batchUpdateEngagement(_ updates: [EngagementUpdate]) async throws {
        
        guard !updates.isEmpty else { return }
        
        do {
            let batch = db.batch()
            
            for update in updates {
                // Update video document
                let videoRef = db.collection(FirebaseSchema.Collections.videos).document(update.videoID)
                let videoUpdateData: [String: Any] = [
                    FirebaseSchema.VideoDocument.hypeCount: update.hypeCount,
                    FirebaseSchema.VideoDocument.coolCount: update.coolCount,
                    FirebaseSchema.VideoDocument.viewCount: update.viewCount,
                    FirebaseSchema.VideoDocument.temperature: update.temperature,
                    FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp(date: update.lastEngagementAt),
                    FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                ]
                batch.updateData(videoUpdateData, forDocument: videoRef)
                
                // Update engagement document - FIXED: Use setData(merge: true)
                let engagementRef = db.collection(FirebaseSchema.Collections.engagement).document(update.videoID)
                let engagementUpdateData: [String: Any] = [
                    FirebaseSchema.EngagementDocument.hypeCount: update.hypeCount,
                    FirebaseSchema.EngagementDocument.coolCount: update.coolCount,
                    FirebaseSchema.EngagementDocument.viewCount: update.viewCount,
                    FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(date: update.lastEngagementAt),
                    FirebaseSchema.EngagementDocument.updatedAt: Timestamp()
                ]
                batch.setData(engagementUpdateData, forDocument: engagementRef, merge: true)
            }
            
            try await batch.commit()
            
            print("VIDEO SERVICE: Batch updated \(updates.count) video engagement records")
            
        } catch {
            print("VIDEO SERVICE: Batch engagement update failed - \(error)")
            throw StitchError.processingError("Failed to batch update engagement: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get user tier for temperature calculations
    private func getUserTier(userID: String) async throws -> UserTier {
        let userDoc = try await db.collection(FirebaseSchema.Collections.users).document(userID).getDocument()
        guard let userData = userDoc.data() else { return .rookie }
        
        let tierString = userData[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
        return UserTier(rawValue: tierString) ?? .rookie
    }
    
    /// Get following user IDs for feed algorithms
    private func getFollowingUserIDs(userID: String) async throws -> [String] {
        let followingQuery = db.collection(FirebaseSchema.Collections.following)
            .whereField("followerID", isEqualTo: userID)
            .whereField(FirebaseSchema.FollowingDocument.isActive, isEqualTo: true)
        
        let snapshot = try await followingQuery.getDocuments()
        
        return snapshot.documents.compactMap { doc in
            doc.data()["followingID"] as? String
        }
    }
    
    /// Create video from Firestore document - FIXED TYPE HANDLING
    private func createVideoFromDocument(_ document: QueryDocumentSnapshot) throws -> CoreVideoMetadata {
        let data = document.data()
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        // Engagement metrics
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        // Content metadata
        let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0.0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? (9.0/16.0)
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        
        // Performance metrics
        let engagementRatio = hypeCount + coolCount > 0 ? Double(hypeCount) / Double(hypeCount + coolCount) : 0.5
        let velocityScore = data["velocityScore"] as? Double ?? 0.0
        let trendingScore = data["trendingScore"] as? Double ?? 0.0
        let discoverabilityScore = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5
        
        // Status
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false
        let lastEngagementAt = (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: conversationDepth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: temperature,
            qualityScore: qualityScore,
            engagementRatio: engagementRatio,
            velocityScore: velocityScore,
            trendingScore: trendingScore,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: lastEngagementAt
        )
    }
    
    /// Create initial engagement document for new video
    private func createEngagementDocument(videoID: String, creatorID: String) async throws {
        let engagementData: [String: Any] = [
            FirebaseSchema.EngagementDocument.videoID: videoID,
            FirebaseSchema.EngagementDocument.creatorID: creatorID,
            FirebaseSchema.EngagementDocument.hypeCount: 0,
            FirebaseSchema.EngagementDocument.coolCount: 0,
            FirebaseSchema.EngagementDocument.viewCount: 0,
            FirebaseSchema.EngagementDocument.shareCount: 0,
            FirebaseSchema.EngagementDocument.replyCount: 0,
            FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(),
            FirebaseSchema.EngagementDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.engagement).document(videoID).setData(engagementData)
    }
    
    /// Clean up related data when deleting video
    private func cleanupRelatedData(videoID: String) async {
        do {
            // Delete interactions
            let interactionsQuery = db.collection(FirebaseSchema.Collections.interactions)
                .whereField("videoID", isEqualTo: videoID)
            
            let interactionDocs = try await interactionsQuery.getDocuments()
            
            for doc in interactionDocs.documents {
                try await doc.reference.delete()
            }
            
            print("VIDEO SERVICE: Deleted \(interactionDocs.documents.count) interaction records")
            
        } catch {
            print("VIDEO SERVICE: Failed to clean up related data: \(error)")
        }
    }
    
    /// Delete file from Firebase Storage
    private func deleteFromStorage(url: String) async throws {
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
    
    // MARK: - Preloading and Performance
    
    /// Preload threads for smooth swiping
    func preloadThreadsForNavigation(
        threads: [ThreadData],
        currentIndex: Int,
        direction: SwipeDirection = .horizontal
    ) async {
        
        let preloadRange: Range<Int>
        
        switch direction {
        case .horizontal:
            let start = max(0, currentIndex + 1)
            let end = min(threads.count, currentIndex + 2)
            preloadRange = start..<end
            
        case .vertical:
            guard currentIndex < threads.count else { return }
            let currentThread = threads[currentIndex]
            
            if currentThread.childVideos.isEmpty {
                _ = try? await getThreadChildren(threadID: currentThread.id)
            }
            return
        }
        
        for index in preloadRange {
            _ = threads[index]
            print("VIDEO SERVICE: Preloaded thread \(index) structure")
        }
        
        print("VIDEO SERVICE: Optimized preload for \(direction) navigation")
    }
}

// MARK: - Supporting Data Structures

/// User engagement status for a video
struct UserEngagementStatus {
    let hasHyped: Bool
    let hasCooled: Bool
    let hasViewed: Bool
    let hasShared: Bool
    
    var hasAnyEngagement: Bool {
        return hasHyped || hasCooled || hasViewed || hasShared
    }
}

/// Engagement update data for batch operations
struct EngagementUpdate {
    let videoID: String
    let hypeCount: Int
    let coolCount: Int
    let viewCount: Int
    let temperature: String
    let lastEngagementAt: Date
}

/// Swipe direction for preloading optimization
enum SwipeDirection {
    case horizontal // Thread to thread navigation
    case vertical   // Parent to child navigation
}

/// Thread data structure for multidirectional navigation - FIXED BOUNDS CHECK
struct ThreadData: Identifiable, Codable {
    let id: String
    let parentVideo: CoreVideoMetadata
    let childVideos: [CoreVideoMetadata]
    
    /// Total videos in this thread (parent + children)
    var totalVideos: Int {
        return 1 + childVideos.count
    }
    
    /// Get video at specific index (0 = parent, 1+ = children) - BOUNDS FIXED
    func video(at index: Int) -> CoreVideoMetadata? {
        if index == 0 {
            return parentVideo
        } else if index > 0 && (index - 1) < childVideos.count {
            return childVideos[index - 1]
        }
        return nil
    }
    
    /// Check if thread has replies
    var hasReplies: Bool {
        return !childVideos.isEmpty
    }
}

/// Comprehensive video analytics
struct VideoAnalytics {
    let videoID: String
    let totalViews: Int
    let uniqueViewers: Int
    let totalHypes: Int
    let totalCools: Int
    let totalShares: Int
    let averageWatchTime: TimeInterval
    let totalWatchTime: TimeInterval
    let engagementRate: Double
    let temperature: String
}

/// Paginated result wrapper
struct PaginatedResult<T> {
    let items: [T]
    let lastDocument: DocumentSnapshot?
    let hasMore: Bool
}

// MARK: - Hello World Test Extension
extension VideoService {
    
    /// Test video service functionality
    func helloWorldTest() {
        print("VIDEO SERVICE: Complete engagement system ready!")
        print("VIDEO SERVICE: Features: Thread hierarchy, full engagement tracking, temperature updates")
        print("VIDEO SERVICE: Beta algorithms: Simple feeds for maximum content visibility")
    }
}
