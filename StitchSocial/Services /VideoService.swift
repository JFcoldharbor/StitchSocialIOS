//
//  VideoService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video CRUD and Thread Management
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema
//  Features: Thread hierarchy, video data operations, temperature calculation, user tagging, viewer tracking
//  UPDATED: Dynamic aspect ratio support - no more hardcoded 9:16
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

// MARK: - Supporting Data Structures

// NOTE: VideoOrientation is defined in VideoProcessingService.swift
// Do not duplicate here to avoid "Invalid redeclaration" errors

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
    /// UPDATED: Now accepts aspectRatio parameter instead of hardcoding 9:16
    func createThread(
        title: String,
        description: String = "",
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64,
        aspectRatio: Double = 9.0/16.0,
        recordingSource: String = "unknown",
        hashtags: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        // CRITICAL: Validate creatorID is Firebase Auth UID
        guard let currentFirebaseUID = Auth.auth().currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user found")
        }
        
        // Ensure we're using the actual Firebase UID, not any other ID
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
        }
        
        // CRITICAL: Server-side duration enforcement — fetch user tier from Firestore
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(validatedCreatorID)
            .getDocument()
        let userTierRaw = userDoc.data()?["tier"] as? String ?? "rookie"
        let userTier = UserTier(rawValue: userTierRaw) ?? .rookie
        let maxDuration = getMaxRecordingDuration(for: userTier)
        
        if duration > maxDuration + 1.0 {
            let maxFormatted = maxDuration >= 60
                ? String(format: "%d:%02d", Int(maxDuration) / 60, Int(maxDuration) % 60)
                : "\(Int(maxDuration))s"
            throw StitchError.validationError("Video duration \(Int(duration))s exceeds your tier limit of \(maxFormatted)")
        }
        
        // FIX: If creatorName is empty, fetch username from Firestore
        var finalCreatorName = creatorName
        if finalCreatorName.isEmpty {
            print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: creatorName empty, fetching username from Firestore...")
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(validatedCreatorID)
                .getDocument()
            
            if let userData = userDoc.data(),
               let username = userData[FirebaseSchema.UserDocument.username] as? String {
                finalCreatorName = username
                print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ VIDEO SERVICE: Auto-fetched username: @\(finalCreatorName)")
            } else {
                finalCreatorName = "unknown_user"
                print("ÃƒÂ¢Ã‚ÂÃ…â€™ VIDEO SERVICE: Could not fetch username, using fallback")
            }
        }
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        // Determine video orientation for logging
        let orientation = VideoOrientation.from(aspectRatio: aspectRatio)
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â VIDEO SERVICE: Creating \(orientation.displayName) video with aspect ratio \(String(format: "%.3f", aspectRatio))")
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,
            FirebaseSchema.VideoDocument.creatorName: finalCreatorName,
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
            
            // Content metadata - FIXED: Use actual aspect ratio
            FirebaseSchema.VideoDocument.duration: duration,
            FirebaseSchema.VideoDocument.aspectRatio: aspectRatio,  // ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ NOW DYNAMIC
            FirebaseSchema.VideoDocument.fileSize: fileSize,
            FirebaseSchema.VideoDocument.qualityScore: 50,
            
            // Temperature system
            FirebaseSchema.VideoDocument.temperature: "neutral",
            
            // Status
            FirebaseSchema.VideoDocument.isDeleted: false,
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false,
            
            // Content authenticity
            FirebaseSchema.VideoDocument.recordingSource: recordingSource,
            
            // Hashtags
            FirebaseSchema.VideoDocument.hashtags: hashtags
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("✅ VIDEO SERVICE: Created thread \(videoID) by @\(finalCreatorName) with Firebase UID \(validatedCreatorID)")
        return video
    }
    
    /// Create spin-off thread - a new thread that references an original video
    /// Spin-offs are new threads (depth 0) but with attribution to the original video
    func createSpinOffThread(
        originalVideoID: String,
        originalThreadID: String,
        title: String,
        description: String = "",
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64,
        aspectRatio: Double = 9.0/16.0,
        recordingSource: String = "unknown",
        hashtags: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        // CRITICAL: Validate creatorID is Firebase Auth UID
        guard let currentFirebaseUID = Auth.auth().currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user found")
        }
        
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("Ã¢Å¡Â Ã¯Â¸Â VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
        }
        
        // FIX: If creatorName is empty, fetch username
        var finalCreatorName = creatorName
        if finalCreatorName.isEmpty {
            print("Ã¢Å¡Â Ã¯Â¸Â VIDEO SERVICE: creatorName empty, fetching username from Firestore...")
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(validatedCreatorID)
                .getDocument()
            
            if let userData = userDoc.data(),
               let username = userData[FirebaseSchema.UserDocument.username] as? String {
                finalCreatorName = username
                print("Ã¢Å“â€¦ VIDEO SERVICE: Auto-fetched username: @\(finalCreatorName)")
            } else {
                finalCreatorName = "unknown_user"
                print("Ã¢ÂÅ’ VIDEO SERVICE: Could not fetch username, using fallback")
            }
        }
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        let orientation = VideoOrientation.from(aspectRatio: aspectRatio)
        print("Ã°Å¸â€œÂ¹ VIDEO SERVICE: Creating spin-off \(orientation.displayName) video referencing \(originalVideoID)")
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,
            FirebaseSchema.VideoDocument.creatorName: finalCreatorName,
            FirebaseSchema.VideoDocument.createdAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
            
            // Thread hierarchy - NEW thread (depth 0) with spin-off attribution
            FirebaseSchema.VideoDocument.threadID: videoID,  // Its own thread
            FirebaseSchema.VideoDocument.conversationDepth: 0,
            FirebaseSchema.VideoDocument.spinOffFromVideoID: originalVideoID,  // Reference to original video
            FirebaseSchema.VideoDocument.spinOffFromThreadID: originalThreadID,  // Reference to original thread
            
            // Basic engagement
            FirebaseSchema.VideoDocument.viewCount: 0,
            FirebaseSchema.VideoDocument.hypeCount: 0,
            FirebaseSchema.VideoDocument.coolCount: 0,
            FirebaseSchema.VideoDocument.replyCount: 0,
            FirebaseSchema.VideoDocument.shareCount: 0,
            FirebaseSchema.VideoDocument.spinOffCount: 0,  // Track spin-offs from this video
            
            // Milestone tracking
            FirebaseSchema.VideoDocument.firstHypeReceived: false,
            FirebaseSchema.VideoDocument.firstCoolReceived: false,
            FirebaseSchema.VideoDocument.milestone10Reached: false,
            FirebaseSchema.VideoDocument.milestone400Reached: false,
            FirebaseSchema.VideoDocument.milestone1000Reached: false,
            FirebaseSchema.VideoDocument.milestone15000Reached: false,
            
            // Content metadata
            FirebaseSchema.VideoDocument.duration: duration,
            FirebaseSchema.VideoDocument.aspectRatio: aspectRatio,
            FirebaseSchema.VideoDocument.fileSize: fileSize,
            FirebaseSchema.VideoDocument.qualityScore: 50,
            
            // Temperature system
            FirebaseSchema.VideoDocument.temperature: "neutral",
            
            // Status
            FirebaseSchema.VideoDocument.isDeleted: false,
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false,
            
            // Content authenticity
            FirebaseSchema.VideoDocument.recordingSource: recordingSource,
            
            // Hashtags
            FirebaseSchema.VideoDocument.hashtags: hashtags
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        // Increment spinOffCount on the original video
        let originalVideoRef = db.collection(FirebaseSchema.Collections.videos).document(originalVideoID)
        try await originalVideoRef.updateData([
            FirebaseSchema.VideoDocument.spinOffCount: FieldValue.increment(Int64(1))
        ])
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("Ã¢Å“â€¦ VIDEO SERVICE: Created spin-off thread \(videoID) by @\(finalCreatorName) from original \(originalVideoID)")
        return video
    }
    
    /// Create child reply in thread with Firebase Auth validation and auto-username fetch
    /// UPDATED: Now accepts aspectRatio parameter instead of hardcoding 9:16
    func createChildReply(
        parentID: String,
        title: String,
        description: String = "",
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64,
        aspectRatio: Double = 9.0/16.0,
        recordingSource: String = "unknown",
        hashtags: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        // CRITICAL: Validate creatorID is Firebase Auth UID
        guard let currentFirebaseUID = Auth.auth().currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user found")
        }
        
        // Ensure we're using the actual Firebase UID
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
        }
        
        // CRITICAL: Server-side duration enforcement
        let tierDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(validatedCreatorID)
            .getDocument()
        let replyTierRaw = tierDoc.data()?["tier"] as? String ?? "rookie"
        let replyUserTier = UserTier(rawValue: replyTierRaw) ?? .rookie
        let replyMaxDuration = getMaxRecordingDuration(for: replyUserTier)
        
        if duration > replyMaxDuration + 1.0 {
            let maxFormatted = replyMaxDuration >= 60
                ? String(format: "%d:%02d", Int(replyMaxDuration) / 60, Int(replyMaxDuration) % 60)
                : "\(Int(replyMaxDuration))s"
            throw StitchError.validationError("Video duration \(Int(duration))s exceeds your tier limit of \(maxFormatted)")
        }
        
        // FIX: If creatorName is empty, fetch username from Firestore
        var finalCreatorName = creatorName
        if finalCreatorName.isEmpty {
            print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: creatorName empty, fetching username from Firestore...")
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(validatedCreatorID)
                .getDocument()
            
            if let userData = userDoc.data(),
               let username = userData[FirebaseSchema.UserDocument.username] as? String {
                finalCreatorName = username
                print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ VIDEO SERVICE: Auto-fetched username: @\(finalCreatorName)")
            } else {
                finalCreatorName = "unknown_user"
                print("ÃƒÂ¢Ã‚ÂÃ…â€™ VIDEO SERVICE: Could not fetch username, using fallback")
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
        
        // Determine video orientation for logging
        let orientation = VideoOrientation.from(aspectRatio: aspectRatio)
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â VIDEO SERVICE: Creating \(orientation.displayName) reply with aspect ratio \(String(format: "%.3f", aspectRatio))")
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,
            FirebaseSchema.VideoDocument.creatorName: finalCreatorName,
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
            
            // Content metadata - FIXED: Use actual aspect ratio
            FirebaseSchema.VideoDocument.duration: duration,
            FirebaseSchema.VideoDocument.aspectRatio: aspectRatio,  // ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ NOW DYNAMIC
            FirebaseSchema.VideoDocument.fileSize: fileSize,
            FirebaseSchema.VideoDocument.qualityScore: 50,
            
            // Temperature system
            FirebaseSchema.VideoDocument.temperature: "neutral",
            
            // Status
            FirebaseSchema.VideoDocument.isDeleted: false,
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false,
            
            // Content authenticity
            FirebaseSchema.VideoDocument.recordingSource: recordingSource,
            
            // Hashtags
            FirebaseSchema.VideoDocument.hashtags: hashtags
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
        
        // Propagate reply count to parent collection if segment
        await propagateToCollection(videoID: parentID, field: "totalReplies", delta: 1)
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ VIDEO SERVICE: Created reply \(videoID) by @\(finalCreatorName) to \(parentID)")
        
        // Ã°Å¸â€â€ NOTIFY PARENT CREATOR OF NEW REPLY
        let parentCreatorID = parentData[FirebaseSchema.VideoDocument.creatorID] as? String
        if let parentCreatorID = parentCreatorID, parentCreatorID != validatedCreatorID {
            Task {
                do {
                    let notificationService = NotificationService()
                    try await notificationService.sendReplyNotification(
                        to: parentCreatorID,
                        videoID: videoID,
                        videoTitle: title
                    )
                    print("Ã¢Å“â€¦ REPLY NOTIFICATION: Sent to parent creator \(parentCreatorID)")
                } catch {
                    print("Ã¢Å¡Â Ã¯Â¸Â REPLY NOTIFICATION: Failed - \(error)")
                }
            }
        }
        
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
    
    /// Get user videos with pagination (EXCLUDES collection segments)
    func getUserVideos(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> PaginatedResult<CoreVideoMetadata> {
        
        // Fetch more to account for filtered collection segments
        let fetchLimit = limit + 10
        
        var query: Query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: userID)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: fetchLimit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let allVideos = snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
        
        // Client-side filter: exclude collection segments
        let filteredVideos = allVideos.filter { video in
            // Exclude videos that are collection segments
            return video.collectionID == nil || video.collectionID?.isEmpty == true
        }
        
        // Take only the requested limit
        let limitedVideos = Array(filteredVideos.prefix(limit))
        
        return PaginatedResult(
            items: limitedVideos,
            lastDocument: snapshot.documents.last,
            hasMore: snapshot.documents.count >= fetchLimit
        )
    }
    
    // MARK: - Collection Support
    
    /// Get all videos belonging to a collection, sorted by segment number
    func getVideosByCollection(collectionID: String) async throws -> [CoreVideoMetadata] {
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â¡ VIDEO SERVICE: Fetching videos for collection \(collectionID)")
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField("collectionID", isEqualTo: collectionID)
            .order(by: "segmentNumber", descending: false)
            .getDocuments()
        
        let videos = snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
        
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â¡ VIDEO SERVICE: Loaded \(videos.count) segments for collection \(collectionID)")
        return videos
    }
    
    /// Get timestamped replies for a video segment (replies that reference specific timestamps)
    /// - Parameter videoID: The video ID (also accepts segmentID)
    func getTimestampedReplies(videoID: String? = nil, segmentID: String? = nil) async throws -> [CoreVideoMetadata] {
        let targetID = videoID ?? segmentID ?? ""
        guard !targetID.isEmpty else {
            print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: No videoID or segmentID provided for timestamped replies")
            return []
        }
        
        // Query for replies to this video that have timestamp markers
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.replyToVideoID, isEqualTo: targetID)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .getDocuments()
        
        let replies = snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
        
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â¡ VIDEO SERVICE: Loaded \(replies.count) timestamped replies for \(targetID)")
        return replies
    }
    
    /// Get all threads with children for discovery feed (EXCLUDES collection segments)
    func getAllThreadsWithChildren(
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // Fetch more to account for filtered collection segments
        let fetchLimit = limit + 20
        
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: fetchLimit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        for doc in snapshot.documents {
            let video = createCoreVideoMetadata(from: doc.data(), id: doc.documentID)
            
            // Skip collection segments - they should only appear in collection player
            if let collID = video.collectionID, !collID.isEmpty {
                continue
            }
            
            let childVideos = try await getThreadChildren(threadID: video.id)
            
            let threadData = ThreadData(
                id: video.id,
                parentVideo: video,
                childVideos: childVideos
            )
            threads.append(threadData)
            
            // Stop once we have enough threads
            if threads.count >= limit {
                break
            }
        }
        
        let hasMore = snapshot.documents.count >= fetchLimit
        
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
    
    // MARK: - Distributed Counter Sharding (Scalable Writes)
    
    /// Increment hype shard for a video (random shard selection)
    /// Writes to: videos/{videoID}/hype_shards/{shardIndex}
    func incrementHypeShard(videoID: String, amount: Int = 1) async throws {
        let shardIndex = Int.random(in: 0..<FirebaseSchema.Collections.shardCount)
        let shardRef = db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.hypeShards)
            .document("\(shardIndex)")
        
        try await shardRef.setData([
            "count": FieldValue.increment(Int64(amount)),
            "updatedAt": Timestamp()
        ], merge: true)
        
        // Dual-write: also update video doc for instant UI feedback
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData([
                FirebaseSchema.VideoDocument.hypeCount: FieldValue.increment(Int64(amount)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ])
        
        try await markVideoShardActive(videoID: videoID)
        await propagateToCollection(videoID: videoID, field: "totalHypes", delta: Int64(amount))
        
        print("ðŸ”¥ SHARD: +\(amount) hype â†’ shard \(shardIndex) + video doc for \(videoID)")
    }
    
    /// Increment cool shard for a video (random shard selection)
    /// Writes to: videos/{videoID}/cool_shards/{shardIndex}
    func incrementCoolShard(videoID: String, amount: Int = 1) async throws {
        let shardIndex = Int.random(in: 0..<FirebaseSchema.Collections.shardCount)
        let shardRef = db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.coolShards)
            .document("\(shardIndex)")
        
        try await shardRef.setData([
            "count": FieldValue.increment(Int64(amount)),
            "updatedAt": Timestamp()
        ], merge: true)
        
        // Dual-write: also update video doc for instant UI feedback
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData([
                FirebaseSchema.VideoDocument.coolCount: FieldValue.increment(Int64(amount)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ])
        
        try await markVideoShardActive(videoID: videoID)
        await propagateToCollection(videoID: videoID, field: "totalCools", delta: Int64(amount))
        
        print("â„ï¸ SHARD: +\(amount) cool â†’ shard \(shardIndex) + video doc for \(videoID)")
    }
    
    /// Decrement hype shard (for grace period switches/removal)
    /// SAFE: Reads current totals first to prevent negative counts
    func decrementHypeShard(videoID: String, amount: Int) async throws {
        // Read current totals to cap decrement
        let currentShardTotal = try await getShardedHypeCount(videoID: videoID)
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        let currentVideoCount = videoDoc.data()?[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        
        // Cap at the minimum of both sources - never go below 0
        let safeAmount = min(amount, max(0, min(currentShardTotal, currentVideoCount)))
        
        guard safeAmount > 0 else {
            print("ðŸ”¥ SHARD: Skip hype decrement - totals: shard=\(currentShardTotal), doc=\(currentVideoCount), requested=-\(amount)")
            return
        }
        
        let shardRef = db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.hypeShards)
            .document("0")
        
        try await shardRef.setData([
            "count": FieldValue.increment(Int64(-safeAmount)),
            "updatedAt": Timestamp()
        ], merge: true)
        
        // Dual-write: also update video doc for instant UI feedback (SAFE)
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData([
                FirebaseSchema.VideoDocument.hypeCount: FieldValue.increment(Int64(-safeAmount)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ])
        
        try await markVideoShardActive(videoID: videoID)
        await propagateToCollection(videoID: videoID, field: "totalHypes", delta: Int64(-safeAmount))
        
        if safeAmount < amount {
            print("ðŸ”¥ SHARD: -\(safeAmount) hype â†’ shard 0 + video doc for \(videoID) (CAPPED from -\(amount), shard=\(currentShardTotal), doc=\(currentVideoCount))")
        } else {
            print("ðŸ”¥ SHARD: -\(safeAmount) hype â†’ shard 0 + video doc for \(videoID)")
        }
    }
    
    /// Decrement cool shard (for grace period switches/removal)
    /// SAFE: Reads current totals first to prevent negative counts
    func decrementCoolShard(videoID: String, amount: Int) async throws {
        // Read current totals to cap decrement
        let currentShardTotal = try await getShardedCoolCount(videoID: videoID)
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        let currentVideoCount = videoDoc.data()?[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        
        // Cap at the minimum of both sources - never go below 0
        let safeAmount = min(amount, max(0, min(currentShardTotal, currentVideoCount)))
        
        guard safeAmount > 0 else {
            print("â„ï¸ SHARD: Skip cool decrement - totals: shard=\(currentShardTotal), doc=\(currentVideoCount), requested=-\(amount)")
            return
        }
        
        let shardRef = db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.coolShards)
            .document("0")
        
        try await shardRef.setData([
            "count": FieldValue.increment(Int64(-safeAmount)),
            "updatedAt": Timestamp()
        ], merge: true)
        
        // Dual-write: also update video doc for instant UI feedback (SAFE)
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData([
                FirebaseSchema.VideoDocument.coolCount: FieldValue.increment(Int64(-safeAmount)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ])
        
        try await markVideoShardActive(videoID: videoID)
        await propagateToCollection(videoID: videoID, field: "totalCools", delta: Int64(-safeAmount))
        
        if safeAmount < amount {
            print("â„ï¸ SHARD: -\(safeAmount) cool â†’ shard 0 + video doc for \(videoID) (CAPPED from -\(amount), shard=\(currentShardTotal), doc=\(currentVideoCount))")
        } else {
            print("â„ï¸ SHARD: -\(safeAmount) cool â†’ shard 0 + video doc for \(videoID)")
        }
    }
    
    /// Read total hype count by summing all shards (for real-time display)
    func getShardedHypeCount(videoID: String) async throws -> Int {
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.hypeShards)
            .getDocuments()
        
        let total = snapshot.documents.reduce(0) { sum, doc in
            sum + (doc.data()["count"] as? Int ?? 0)
        }
        
        return max(0, total)
    }
    
    // MARK: - Collection Engagement Propagation
    //
    // When a segment gets hyped/cooled/viewed, propagate to parent collection.
    // Uses FieldValue.increment — NO extra reads. One write per engagement.
    // CACHING: collectionID lookup cached per-video for session to avoid re-reads.
    
    /// In-memory cache: videoID -> collectionID (nil = not a segment)
    private var collectionIDCache: [String: String?] = [:]
    
    /// Propagate engagement delta to parent collection document.
    /// Reads collectionID from video doc ONCE, caches for session.
    /// field: "totalHypes", "totalCools", "totalViews", "totalReplies", "totalShares"
    private func propagateToCollection(videoID: String, field: String, delta: Int64) async {
        // Check cache first — avoids repeated Firestore reads
        if let cached = collectionIDCache[videoID] {
            guard let collectionID = cached else { return } // nil = not a segment
            await incrementCollectionField(collectionID: collectionID, field: field, delta: delta)
            return
        }
        
        // Cache miss — read video doc once
        do {
            let doc = try await db.collection(FirebaseSchema.Collections.videos)
                .document(videoID).getDocument()
            let data = doc.data() ?? [:]
            let isSegment = data["isCollectionSegment"] as? Bool ?? false
            let collectionID = data["collectionID"] as? String
            
            if isSegment, let cID = collectionID {
                collectionIDCache[videoID] = cID
                await incrementCollectionField(collectionID: cID, field: field, delta: delta)
            } else {
                collectionIDCache[videoID] = nil // cache negative result
            }
        } catch {
            print("⚠️ COLLECTION PROPAGATE: Failed to read video \(videoID): \(error)")
        }
    }
    
    /// Atomic increment on collection document — no read needed
    private func incrementCollectionField(collectionID: String, field: String, delta: Int64) async {
        do {
            try await db.collection("videoCollections")
                .document(collectionID)
                .updateData([
                    field: FieldValue.increment(delta),
                    "updatedAt": Timestamp()
                ])
            print("📊 COLLECTION PROPAGATE: \(field) \(delta > 0 ? "+" : "")\(delta) → collection \(collectionID)")
        } catch {
            print("⚠️ COLLECTION PROPAGATE: Failed to update \(field) on \(collectionID): \(error)")
        }
    }
    
    /// Read total cool count by summing all shards (for real-time display)
    func getShardedCoolCount(videoID: String) async throws -> Int {
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .collection(FirebaseSchema.Collections.coolShards)
            .getDocuments()
        
        let total = snapshot.documents.reduce(0) { sum, doc in
            sum + (doc.data()["count"] as? Int ?? 0)
        }
        
        return max(0, total)
    }
    
    /// Mark a video as having recent shard activity (for Cloud Function aggregation)
    private func markVideoShardActive(videoID: String) async throws {
        try await db.collection("active_shards").document(videoID).setData([
            "videoID": videoID,
            "lastShardWrite": Timestamp(),
            "needsAggregation": true
        ], merge: true)
    }
    
    /// Update only non-count fields on video doc (temperature, timestamps)
    func updateVideoMetadata(
        videoID: String,
        temperature: String? = nil,
        lastEngagementAt: Date? = nil
    ) async throws {
        var updateData: [String: Any] = [
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ]
        
        if let temperature = temperature {
            updateData[FirebaseSchema.VideoDocument.temperature] = temperature
        }
        
        if let lastEngagement = lastEngagementAt {
            updateData[FirebaseSchema.VideoDocument.lastEngagementAt] = Timestamp(date: lastEngagement)
        }
        
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData(updateData)
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
        
        print("ÃƒÂ°Ã…Â¸Ã‚ÂÃ‚Â·ÃƒÂ¯Ã‚Â¸Ã‚Â VIDEO SERVICE: Updated tags for video \(videoID) with \(taggedUserIDs.count) users")
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
        await propagateToCollection(videoID: videoID, field: "totalViews", delta: 1)
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
            "totalCloutGiven": state.totalCloutGiven,
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
              let lastEngagementTimestamp = data["lastEngagementAt"] as? Timestamp else {
            return nil
        }
        
        // Get optional fields
        let totalCloutGiven = data["totalCloutGiven"] as? Int ?? 0
        
        var state = VideoEngagementState(
            videoID: videoID,
            userID: userID,
            createdAt: lastEngagementTimestamp.dateValue()
        )
        
        state.totalEngagements = totalEngagements
        state.hypeEngagements = hypeEngagements
        state.coolEngagements = coolEngagements
        state.totalCloutGiven = totalCloutGiven
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
        let recordingSource = data[FirebaseSchema.VideoDocument.recordingSource] as? String ?? "unknown"
        let hashtags = data[FirebaseSchema.VideoDocument.hashtags] as? [String] ?? []
        
        // Collection fields
        let collectionID = data["collectionID"] as? String
        let segmentNumber = data["segmentNumber"] as? Int
        let segmentTitle = data["segmentTitle"] as? String
        let isCollectionSegment = data["isCollectionSegment"] as? Bool ?? false
        let replyTimestamp = data["replyTimestamp"] as? TimeInterval
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            description: description,
            taggedUserIDs: taggedUserIDs,
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
            lastEngagementAt: lastEngagementAt,
            collectionID: collectionID,
            segmentNumber: segmentNumber,
            segmentTitle: segmentTitle,
            isCollectionSegment: isCollectionSegment,
            replyTimestamp: replyTimestamp,
            recordingSource: recordingSource,
            hashtags: hashtags
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
    
    // MARK: - Recording Limits (Tier-Based)
    
    /// Get maximum recording duration for a user tier (in seconds)
    func getMaxRecordingDuration(for tier: UserTier) -> TimeInterval {
        switch tier {
        case .rookie: return 30          // 30 seconds
        case .rising: return 45          // 45 seconds
        case .veteran: return 60         // 1 minute
        case .influencer: return 90      // 1.5 minutes
        case .ambassador: return 120     // 2 minutes
        case .elite: return 180          // 3 minutes
        case .partner: return 300        // 5 minutes
        case .legendary: return 480      // 8 minutes
        case .topCreator: return 600     // 10 minutes
        case .founder, .coFounder: return 900  // 15 minutes (technical limit)
        }
    }
    
    /// Check if user can continue recording based on current duration
    func canContinueRecording(currentDuration: TimeInterval, userTier: UserTier) -> Bool {
        let maxDuration = getMaxRecordingDuration(for: userTier)
        return currentDuration < maxDuration
    }
    
    /// Get remaining recording time for user's tier
    func getRemainingTime(currentDuration: TimeInterval, userTier: UserTier) -> TimeInterval {
        let maxDuration = getMaxRecordingDuration(for: userTier)
        return max(0, maxDuration - currentDuration)
    }
}
