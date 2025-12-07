//
//  VideoService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video CRUD and Thread Management
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema
//  Features: Thread hierarchy, video data operations, temperature calculation, user tagging, viewer tracking
//  FIXED: Auto-fetch username when creatorName is empty
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

// MARK: - Supporting Data Structures

/// Swipe direction for preloading optimization
enum SwipeDirection {
    case horizontal // Thread to thread navigation
    case vertical   // Parent to child navigation
}

/// Thread data structure for multidirectional navigation
struct ThreadData: Identifiable, Codable {
    let id: String
    let parentVideo: CoreVideoMetadata
    let childVideos: [CoreVideoMetadata]
    
    /// Total videos in this thread (parent + children)
    var totalVideos: Int {
        return 1 + childVideos.count
    }
    
    /// Get video at specific index (0 = parent, 1+ = children)
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

// MARK: - VideoService Class

/// Video CRUD and thread management service
@MainActor
class VideoService: ObservableObject {
    
    // MARK: - Properties
    
    internal let db = Firestore.firestore(database: Config.Firebase.databaseName)
    internal let storage = Storage.storage()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Create Operations
    
    /// Create new thread (parent video) with Firebase Auth validation and auto-username fetch
    func createThread(
        title: String,
        description: String = "",
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) async throws -> CoreVideoMetadata {
        
        // CRITICAL: Validate creatorID is Firebase Auth UID
        guard let currentFirebaseUID = Auth.auth().currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user found")
        }
        
        // Ensure we're using the actual Firebase UID, not any other ID
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("⚠️ VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
        }
        
        // 🔥 FIX: If creatorName is empty, fetch username from Firestore
        var finalCreatorName = creatorName
        if finalCreatorName.isEmpty {
            print("⚠️ VIDEO SERVICE: creatorName empty, fetching username from Firestore...")
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(validatedCreatorID)
                .getDocument()
            
            if let userData = userDoc.data(),
               let username = userData[FirebaseSchema.UserDocument.username] as? String {
                finalCreatorName = username
                print("✅ VIDEO SERVICE: Auto-fetched username: @\(finalCreatorName)")
            } else {
                finalCreatorName = "unknown_user"
                print("❌ VIDEO SERVICE: Could not fetch username, using fallback")
            }
        }
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,
            FirebaseSchema.VideoDocument.creatorName: finalCreatorName,  // ✅ USE FETCHED VALUE
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
            
            // Milestone tracking
            FirebaseSchema.VideoDocument.firstHypeReceived: false,
            FirebaseSchema.VideoDocument.firstCoolReceived: false,
            FirebaseSchema.VideoDocument.milestone10Reached: false,
            FirebaseSchema.VideoDocument.milestone400Reached: false,
            FirebaseSchema.VideoDocument.milestone1000Reached: false,
            FirebaseSchema.VideoDocument.milestone15000Reached: false,
            
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
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("✅ VIDEO SERVICE: Created thread \(videoID) by @\(finalCreatorName) with Firebase UID \(validatedCreatorID)")
        return video
    }
    
    /// Create child reply in thread with Firebase Auth validation and auto-username fetch
    func createChildReply(
        parentID: String,
        title: String,
        description: String = "",
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) async throws -> CoreVideoMetadata {
        
        // CRITICAL: Validate creatorID is Firebase Auth UID
        guard let currentFirebaseUID = Auth.auth().currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user found")
        }
        
        // Ensure we're using the actual Firebase UID
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("⚠️ VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
        }
        
        // 🔥 FIX: If creatorName is empty, fetch username from Firestore
        var finalCreatorName = creatorName
        if finalCreatorName.isEmpty {
            print("⚠️ VIDEO SERVICE: creatorName empty, fetching username from Firestore...")
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(validatedCreatorID)
                .getDocument()
            
            if let userData = userDoc.data(),
               let username = userData[FirebaseSchema.UserDocument.username] as? String {
                finalCreatorName = username
                print("✅ VIDEO SERVICE: Auto-fetched username: @\(finalCreatorName)")
            } else {
                finalCreatorName = "unknown_user"
                print("❌ VIDEO SERVICE: Could not fetch username, using fallback")
            }
        }
        
        // Get parent video to determine thread details
        let parentDoc = try await db.collection(FirebaseSchema.Collections.videos).document(parentID).getDocument()
        
        guard parentDoc.exists, let parentData = parentDoc.data() else {
            throw StitchError.validationError("Parent video not found")
        }
        
        let threadID = parentData[FirebaseSchema.VideoDocument.threadID] as? String ?? parentID
        let parentDepth = parentData[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,
            FirebaseSchema.VideoDocument.creatorName: finalCreatorName,  // ✅ USE FETCHED VALUE
            FirebaseSchema.VideoDocument.createdAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
            
            // Thread hierarchy - child video
            FirebaseSchema.VideoDocument.threadID: threadID,
            FirebaseSchema.VideoDocument.replyToVideoID: parentID,
            FirebaseSchema.VideoDocument.conversationDepth: parentDepth + 1,
            
            // Basic engagement
            FirebaseSchema.VideoDocument.viewCount: 0,
            FirebaseSchema.VideoDocument.hypeCount: 0,
            FirebaseSchema.VideoDocument.coolCount: 0,
            FirebaseSchema.VideoDocument.replyCount: 0,
            FirebaseSchema.VideoDocument.shareCount: 0,
            
            // Milestone tracking
            FirebaseSchema.VideoDocument.firstHypeReceived: false,
            FirebaseSchema.VideoDocument.firstCoolReceived: false,
            FirebaseSchema.VideoDocument.milestone10Reached: false,
            FirebaseSchema.VideoDocument.milestone400Reached: false,
            FirebaseSchema.VideoDocument.milestone1000Reached: false,
            FirebaseSchema.VideoDocument.milestone15000Reached: false,
            
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
        
        // Create child video and update parent reply count
        try await db.runTransaction { transaction, errorPointer in
            let videoRef = self.db.collection(FirebaseSchema.Collections.videos).document(videoID)
            let parentRef = self.db.collection(FirebaseSchema.Collections.videos).document(parentID)
            
            transaction.setData(videoData, forDocument: videoRef)
            transaction.updateData([
                FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(1)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ], forDocument: parentRef)
            
            return nil
        }
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("✅ VIDEO SERVICE: Created reply \(videoID) by @\(finalCreatorName) to \(parentID)")
        return video
    }
    
    // MARK: - Read Operations
    
    /// Get single video by ID
    func getVideo(id: String) async throws -> CoreVideoMetadata {
        let document = try await db.collection(FirebaseSchema.Collections.videos).document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        return createCoreVideoMetadata(from: data, id: id)
    }
    
    /// Get thread videos (for VideoCoordinator stitch notifications)
    func getThreadVideos(threadID: String) async throws -> [CoreVideoMetadata] {
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .order(by: FirebaseSchema.VideoDocument.conversationDepth)
            .getDocuments()
        
        return snapshot.documents.map { doc in
            createCoreVideoMetadata(from: doc.data(), id: doc.documentID)
        }
    }
    
    /// Get following feed with pagination
    func getFollowingFeed(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> PaginatedResult<ThreadData> {
        
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        var threads: [ThreadData] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let parentVideo = createCoreVideoMetadata(from: data, id: document.documentID)
            
            // Load child videos for this thread
            let childVideos = try await getThreadChildren(threadID: parentVideo.id)
            
            let thread = ThreadData(
                id: parentVideo.id,
                parentVideo: parentVideo,
                childVideos: childVideos
            )
            
            threads.append(thread)
        }
        
        return PaginatedResult(
            items: threads,
            lastDocument: snapshot.documents.last,
            hasMore: snapshot.documents.count >= limit
        )
    }
    
    /// Get thread children (replies)
    func getThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt)
            .getDocuments()
        
        return snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
    }
    
    /// Get complete thread data
    func getCompleteThread(threadID: String) async throws -> ThreadData {
        // Get parent video
        let parentDoc = try await db.collection(FirebaseSchema.Collections.videos)
            .document(threadID)
            .getDocument()
        
        guard parentDoc.exists, let parentData = parentDoc.data() else {
            throw StitchError.validationError("Thread not found")
        }
        
        let parentVideo = createCoreVideoMetadata(from: parentData, id: threadID)
        
        // Get child videos
        let childVideos = try await getThreadChildren(threadID: threadID)
        
        return ThreadData(
            id: threadID,
            parentVideo: parentVideo,
            childVideos: childVideos
        )
    }
    
    /// Get user videos with pagination
    func getUserVideos(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> PaginatedResult<CoreVideoMetadata> {
        
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: userID)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let videos = snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
        
        return PaginatedResult(
            items: videos,
            lastDocument: snapshot.documents.last,
            hasMore: snapshot.documents.count >= limit
        )
    }
    
    /// Get all threads with children for discovery feed
    func getAllThreadsWithChildren(
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
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
            guard let video = try? createCoreVideoMetadata(from: doc.data(), id: doc.documentID) else { continue }
            
            let childVideos = try await getThreadChildren(threadID: video.id)
            
            let threadData = ThreadData(
                id: video.id,
                parentVideo: video,
                childVideos: childVideos
            )
            threads.append(threadData)
        }
        
        let hasMore = snapshot.documents.count >= limit
        
        print("VIDEO SERVICE: Discovery feed loaded - \(threads.count) threads")
        return (threads: threads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }
    
    /// Get video analytics
    func getVideoAnalytics(videoID: String) async throws -> VideoAnalytics {
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        
        guard videoDoc.exists, let videoData = videoDoc.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        let interactionSnapshot = try await db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .getDocuments()
        
        let totalViews = videoData[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let totalHypes = videoData[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let totalCools = videoData[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let totalShares = videoData[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        let uniqueViewers = Set(interactionSnapshot.documents.compactMap { doc in
            doc.data()[FirebaseSchema.InteractionDocument.userID] as? String
        }).count
        
        let watchTimes = interactionSnapshot.documents.compactMap { doc in
            doc.data()["watchTime"] as? TimeInterval
        }
        
        let totalWatchTime = watchTimes.reduce(0, +)
        let averageWatchTime = watchTimes.isEmpty ? 0 : totalWatchTime / Double(watchTimes.count)
        
        let totalEngagements = totalHypes + totalCools + totalShares
        let engagementRate = totalViews > 0 ? Double(totalEngagements) / Double(totalViews) : 0.0
        
        return VideoAnalytics(
            videoID: videoID,
            totalViews: totalViews,
            uniqueViewers: uniqueViewers,
            totalHypes: totalHypes,
            totalCools: totalCools,
            totalShares: totalShares,
            averageWatchTime: averageWatchTime,
            totalWatchTime: totalWatchTime,
            engagementRate: engagementRate,
            temperature: videoData[FirebaseSchema.VideoDocument.temperature] as? String ?? "cold"
        )
    }
    
    // MARK: - Update Operations
    
    /// Update video engagement counts (simple update only, no logic)
    func updateVideoEngagement(
        videoID: String,
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        temperature: String,
        lastEngagementAt: Date
    ) async throws {
        
        let updateData: [String: Any] = [
            FirebaseSchema.VideoDocument.hypeCount: hypeCount,
            FirebaseSchema.VideoDocument.coolCount: coolCount,
            FirebaseSchema.VideoDocument.viewCount: viewCount,
            FirebaseSchema.VideoDocument.temperature: temperature,
            FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp(date: lastEngagementAt),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData(updateData)
        
        print("VIDEO SERVICE: Updated engagement for \(videoID)")
    }
    
    /// Update video tags
    func updateVideoTags(videoID: String, taggedUserIDs: [String]) async throws {
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData([
                FirebaseSchema.VideoDocument.taggedUserIDs: taggedUserIDs,
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ])
        
        print("🏷️ VIDEO SERVICE: Updated tags for video \(videoID) with \(taggedUserIDs.count) users")
    }
    
    /// Record user interaction (views and shares only)
    func recordUserInteraction(
        videoID: String,
        userID: String,
        interactionType: InteractionType,
        watchTime: TimeInterval = 0
    ) async throws {
        
        if interactionType == .view {
            guard watchTime >= 5.0 else {
                print("VIDEO SERVICE: View not counted - insufficient watch time")
                return
            }
            
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let interactionID = "\(videoID)_\(userID)_view_\(timestamp)"
            
            let interactionData: [String: Any] = [
                FirebaseSchema.InteractionDocument.userID: userID,
                FirebaseSchema.InteractionDocument.videoID: videoID,
                FirebaseSchema.InteractionDocument.engagementType: interactionType.rawValue,
                "watchTime": watchTime,
                FirebaseSchema.InteractionDocument.timestamp: Timestamp(),
                FirebaseSchema.InteractionDocument.isCompleted: true
            ]
            
            try await db.collection(FirebaseSchema.Collections.interactions).document(interactionID).setData(interactionData)
            try await incrementVideoViewCount(videoID: videoID)
            
            print("VIDEO SERVICE: Recorded view interaction")
            
        } else if interactionType == .share {
            let hasShared = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .share)
            guard !hasShared else { return }
            
            let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
                videoID: videoID, userID: userID, type: interactionType.rawValue
            )
            
            let interactionData: [String: Any] = [
                FirebaseSchema.InteractionDocument.userID: userID,
                FirebaseSchema.InteractionDocument.videoID: videoID,
                FirebaseSchema.InteractionDocument.engagementType: interactionType.rawValue,
                FirebaseSchema.InteractionDocument.timestamp: Timestamp(),
                FirebaseSchema.InteractionDocument.isCompleted: true
            ]
            
            try await db.collection(FirebaseSchema.Collections.interactions).document(interactionID).setData(interactionData)
            print("VIDEO SERVICE: Recorded share interaction")
        }
    }
    
    /// Increment video view count
    private func incrementVideoViewCount(videoID: String) async throws {
        let videoRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
        try await videoRef.updateData([
            FirebaseSchema.VideoDocument.viewCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ])
    }
    
    /// Convenience method for tracking views
    func trackVideoView(videoID: String, userID: String, watchTime: TimeInterval) async throws {
        try await recordUserInteraction(
            videoID: videoID,
            userID: userID,
            interactionType: .view,
            watchTime: watchTime
        )
    }
    
    /// Check if user has interacted with video
    func hasUserInteracted(
        userID: String,
        videoID: String,
        interactionType: InteractionType
    ) async throws -> Bool {
        
        let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
            videoID: videoID,
            userID: userID,
            type: interactionType.rawValue
        )
        let document = try await db.collection(FirebaseSchema.Collections.interactions)
            .document(interactionID)
            .getDocument()
        
        return document.exists
    }
    
    // MARK: - Legacy Support (for EngagementManager compatibility)
    
    /// Save engagement state to Firebase
    func saveEngagementState(key: String, state: VideoEngagementState) async throws {
        let data: [String: Any] = [
            "videoID": state.videoID,
            "userID": state.userID,
            "totalEngagements": state.totalEngagements,
            "hypeEngagements": state.hypeEngagements,
            "coolEngagements": state.coolEngagements,
            "hypeCurrentTaps": state.hypeCurrentTaps,
            "hypeRequiredTaps": state.hypeRequiredTaps,
            "coolCurrentTaps": state.coolCurrentTaps,
            "coolRequiredTaps": state.coolRequiredTaps,
            "lastEngagementAt": Timestamp(date: state.lastEngagementAt)
        ]
        
        try await db.collection("engagement_states").document(key).setData(data)
    }
    
    /// Load engagement state from Firebase
    func loadEngagementState(key: String) async throws -> VideoEngagementState? {
        let document = try await db.collection("engagement_states").document(key).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        guard let videoID = data["videoID"] as? String,
              let userID = data["userID"] as? String,
              let totalEngagements = data["totalEngagements"] as? Int,
              let hypeEngagements = data["hypeEngagements"] as? Int,
              let coolEngagements = data["coolEngagements"] as? Int,
              let hypeCurrentTaps = data["hypeCurrentTaps"] as? Int,
              let hypeRequiredTaps = data["hypeRequiredTaps"] as? Int,
              let coolCurrentTaps = data["coolCurrentTaps"] as? Int,
              let coolRequiredTaps = data["coolRequiredTaps"] as? Int,
              let lastEngagementTimestamp = data["lastEngagementAt"] as? Timestamp else {
            return nil
        }
        
        var state = VideoEngagementState(
            videoID: videoID,
            userID: userID,
            createdAt: lastEngagementTimestamp.dateValue()
        )
        
        state.totalEngagements = totalEngagements
        state.hypeEngagements = hypeEngagements
        state.coolEngagements = coolEngagements
        state.hypeCurrentTaps = hypeCurrentTaps
        state.hypeRequiredTaps = hypeRequiredTaps
        state.coolCurrentTaps = coolCurrentTaps
        state.coolRequiredTaps = coolRequiredTaps
        state.lastEngagementAt = lastEngagementTimestamp.dateValue()
        
        return state
    }
    
    /// Update video temperature
    func updateVideoTemperature(videoID: String) async throws {
        let document = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        
        guard document.exists, let videoData = document.data() else { return }
        
        let hypeCount = videoData[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = videoData[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let viewCount = videoData[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let createdAt = (videoData[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        let ageInMinutes = Date().timeIntervalSince(createdAt) / 60.0
        let creatorID = videoData[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorTier = try await getUserTier(userID: creatorID)
        
        let temperature = calculateVideoTemperature(
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
    }
    
    // MARK: - Delete Operations
    
    /// Delete video and all related data
    func deleteVideo(videoID: String) async throws {
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        
        guard videoDoc.exists, let videoData = videoDoc.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        let conversationDepth = videoData[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        if conversationDepth == 0 {
            try await deleteEntireThread(threadID: videoID)
        } else {
            try await deleteSingleVideo(videoID: videoID, videoData: videoData)
        }
    }
    
    /// Delete entire thread
    private func deleteEntireThread(threadID: String) async throws {
        let threadSnapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .getDocuments()
        
        for document in threadSnapshot.documents {
            let videoData = document.data()
            
            if let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String {
                try? await deleteFromStorage(url: videoURL)
            }
            
            if let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String {
                try? await deleteFromStorage(url: thumbnailURL)
            }
            
            try await document.reference.delete()
        }
        
        await cleanupRelatedData(videoID: threadID)
    }
    
    /// Delete single video
    private func deleteSingleVideo(videoID: String, videoData: [String: Any]) async throws {
        if let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String {
            try? await deleteFromStorage(url: videoURL)
        }
        
        if let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String {
            try? await deleteFromStorage(url: thumbnailURL)
        }
        
        if let parentID = videoData[FirebaseSchema.VideoDocument.replyToVideoID] as? String {
            try? await db.collection(FirebaseSchema.Collections.videos)
                .document(parentID)
                .updateData([
                    FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(-1)),
                    FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                ])
        }
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).delete()
        await cleanupRelatedData(videoID: videoID)
    }
    
    /// Clean up interactions and engagement states
    private func cleanupRelatedData(videoID: String) async {
        do {
            let interactionDocs = try await db.collection(FirebaseSchema.Collections.interactions)
                .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
                .getDocuments()
            
            for doc in interactionDocs.documents {
                try await doc.reference.delete()
            }
            
            let tapProgressDocs = try await db.collection(FirebaseSchema.Collections.tapProgress)
                .whereField(FirebaseSchema.TapProgressDocument.videoID, isEqualTo: videoID)
                .getDocuments()
            
            for doc in tapProgressDocs.documents {
                try await doc.reference.delete()
            }
        } catch {
            print("VIDEO SERVICE: Failed to clean up related data: \(error)")
        }
    }
    
    /// Delete file from Firebase Storage
    private func deleteFromStorage(url: String) async throws {
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
    
    // MARK: - Preloading
    
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
        }
    }
    
    // MARK: - Private Helper Methods

    /// Create CoreVideoMetadata from Firestore data
    internal func createCoreVideoMetadata(from data: [String: Any], id: String) -> CoreVideoMetadata {
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let engagementRatio = hypeCount + coolCount > 0 ? Double(hypeCount) / Double(hypeCount + coolCount) : 0.5
        
        // Break into sub-expressions to help compiler
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let description = data[FirebaseSchema.VideoDocument.description] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? ""
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String ?? id
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        let discoverabilityScore = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false
        let lastEngagementAt = (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        let taggedUserIDs = data[FirebaseSchema.VideoDocument.taggedUserIDs] as? [String] ?? []
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            description: description,
            taggedUserIDs: taggedUserIDs,  // ← MOVE HERE (after description)
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
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: lastEngagementAt
        )
    }
    /// Calculate video temperature
    private func calculateVideoTemperature(
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        ageInMinutes: Double,
        creatorTier: UserTier
    ) -> Temperature {
        
        let totalEngagement = hypeCount + coolCount
        let engagementRate = viewCount > 0 ? Double(totalEngagement) / Double(viewCount) : 0.0
        
        let ageInHours = ageInMinutes / 60.0
        let velocity = ageInHours > 0 ? Double(totalEngagement) / ageInHours : 0.0
        
        let positivityRatio = totalEngagement > 0 ? Double(hypeCount) / Double(totalEngagement) : 0.5
        
        let tierMultiplier: Double
        switch creatorTier {
        case .rookie: tierMultiplier = 1.0
        case .rising: tierMultiplier = 1.2
        case .veteran: tierMultiplier = 1.5
        case .influencer: tierMultiplier = 2.0
        case .ambassador: tierMultiplier = 2.2
        case .elite: tierMultiplier = 2.5
        case .partner: tierMultiplier = 3.0
        case .legendary: tierMultiplier = 4.0
        case .topCreator: tierMultiplier = 5.0
        case .founder, .coFounder: tierMultiplier = 6.0
        }
        
        let timeFactor = ageInHours < 24 ? 1.0 : max(0.5, 1.0 - (ageInHours - 24) / 168)
        let score = (engagementRate * 40 + velocity * 30 + positivityRatio * 20) * tierMultiplier * timeFactor
        
        if score >= 60 { return .blazing }
        if score >= 40 { return .hot }
        if score >= 20 { return .warm }
        if score >= 10 { return .cool }
        return .cold
    }
    
    /// Get user tier
    private func getUserTier(userID: String) async throws -> UserTier {
        do {
            let userDoc = try await db.collection(FirebaseSchema.Collections.users).document(userID).getDocument()
            guard let userData = userDoc.data() else { return .rookie }
            
            let tierString = userData[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
            return UserTier(rawValue: tierString) ?? .rookie
        } catch {
            return .rookie
        }
    }
}
