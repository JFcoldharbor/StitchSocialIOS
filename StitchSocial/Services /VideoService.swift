//
//  VideoService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Video Management with Progressive Tapping System
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema
//  Features: Thread hierarchy, progressive tapping, engagement tracking, temperature calculation
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

// MARK: - Progressive Tapping Support Structures

/// Tap progress state for progressive tapping
struct TapProgressState {
    let currentTaps: Int
    let requiredTaps: Int
    let isComplete: Bool
    let progress: Double
    let milestone: TapMilestone?
    
    init(currentTaps: Int, requiredTaps: Int) {
        self.currentTaps = currentTaps
        self.requiredTaps = requiredTaps
        self.isComplete = currentTaps >= requiredTaps
        self.progress = requiredTaps > 0 ? min(1.0, Double(currentTaps) / Double(requiredTaps)) : 0.0
        
        // Detect milestone
        if progress >= 1.0 {
            self.milestone = .complete
        } else if progress >= 0.75 {
            self.milestone = .threeQuarters
        } else if progress >= 0.5 {
            self.milestone = .half
        } else if progress >= 0.25 {
            self.milestone = .quarter
        } else {
            self.milestone = nil
        }
    }
}

/// Progressive tapping result
struct ProgressiveTapResult {
    let isComplete: Bool
    let progress: Double
    let milestone: TapMilestone?
    let message: String
    let newVideoHypeCount: Int?
    let newVideoCoolCount: Int?
    let cloutAwarded: Int?
}

// MARK: - Supporting Data Structures (Global Scope)

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

/// Engagement update data for batch operations
struct EngagementUpdate {
    let videoID: String
    let hypeCount: Int
    let coolCount: Int
    let viewCount: Int
    let temperature: String
    let lastEngagementAt: Date
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

/// Complete video management service with progressive tapping system
@MainActor
class VideoService: ObservableObject {
    
    // MARK: - Properties
    
    internal let db = Firestore.firestore(database: Config.Firebase.databaseName)
    internal let storage = Storage.storage()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Progressive Tapping System (NEW)
    
    /// Process progressive tap (main entry point for engagement)
    func processProgressiveTap(
        videoID: String,
        userID: String,
        engagementType: InteractionType,
        userTier: UserTier
    ) async throws -> ProgressiveTapResult {
        
        print("🎯 VIDEO SERVICE: Processing \(engagementType.rawValue) tap for video \(videoID)")
        
        // Get current tap progress
        let currentProgress = try await getTapProgress(videoID: videoID, userID: userID, type: engagementType)
        
        // Calculate required taps based on user's total engagements with this video
        let totalEngagements = try await getTotalEngagements(videoID: videoID, userID: userID)
        let requiredTaps = calculateProgressiveTaps(engagementNumber: totalEngagements + 1)
        
        // Update tap count
        let newTapCount = currentProgress.currentTaps + 1
        let newProgress = TapProgressState(currentTaps: newTapCount, requiredTaps: requiredTaps)
        
        // Save updated progress
        try await updateTapProgress(
            videoID: videoID,
            userID: userID,
            type: engagementType,
            currentTaps: newTapCount,
            requiredTaps: requiredTaps
        )
        
        if newProgress.isComplete {
            // Complete engagement!
            let result = try await completeEngagement(
                videoID: videoID,
                userID: userID,
                type: engagementType,
                userTier: userTier
            )
            
            // Reset tap progress for next engagement
            try await resetTapProgress(videoID: videoID, userID: userID, type: engagementType)
            
            print("✅ VIDEO SERVICE: \(engagementType.rawValue) engagement completed!")
            
            return ProgressiveTapResult(
                isComplete: true,
                progress: 1.0,
                milestone: .complete,
                message: "\(engagementType.rawValue.capitalized) added!",
                newVideoHypeCount: result.newHypeCount,
                newVideoCoolCount: result.newCoolCount,
                cloutAwarded: result.cloutAwarded
            )
            
        } else {
            // Still tapping...
            print("🔄 VIDEO SERVICE: \(engagementType.rawValue) progress: \(newTapCount)/\(requiredTaps)")
            
            return ProgressiveTapResult(
                isComplete: false,
                progress: newProgress.progress,
                milestone: newProgress.milestone,
                message: "Keep tapping... (\(newTapCount)/\(requiredTaps))",
                newVideoHypeCount: nil,
                newVideoCoolCount: nil,
                cloutAwarded: nil
            )
        }
    }
    
    /// Get current tap progress from tap_progress collection
    private func getTapProgress(videoID: String, userID: String, type: InteractionType) async throws -> TapProgressState {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        let document = try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).getDocument()
        
        if document.exists, let data = document.data() {
            let currentTaps = data[FirebaseSchema.TapProgressDocument.currentTaps] as? Int ?? 0
            let requiredTaps = data[FirebaseSchema.TapProgressDocument.requiredTaps] as? Int ?? 1
            return TapProgressState(currentTaps: currentTaps, requiredTaps: requiredTaps)
        } else {
            // No progress yet - determine required taps
            let totalEngagements = try await getTotalEngagements(videoID: videoID, userID: userID)
            let requiredTaps = calculateProgressiveTaps(engagementNumber: totalEngagements + 1)
            return TapProgressState(currentTaps: 0, requiredTaps: requiredTaps)
        }
    }
    
    /// Update tap count in tap_progress collection
    private func updateTapProgress(
        videoID: String,
        userID: String,
        type: InteractionType,
        currentTaps: Int,
        requiredTaps: Int
    ) async throws {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        
        let progressData: [String: Any] = [
            FirebaseSchema.TapProgressDocument.videoID: videoID,
            FirebaseSchema.TapProgressDocument.userID: userID,
            FirebaseSchema.TapProgressDocument.engagementType: type.rawValue,
            FirebaseSchema.TapProgressDocument.currentTaps: currentTaps,
            FirebaseSchema.TapProgressDocument.requiredTaps: requiredTaps,
            FirebaseSchema.TapProgressDocument.lastTapTime: Timestamp(),
            FirebaseSchema.TapProgressDocument.isCompleted: currentTaps >= requiredTaps,
            FirebaseSchema.TapProgressDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).setData(progressData, merge: true)
    }
    
    /// Complete engagement - award clout, update video counts, create final interaction record
    private func completeEngagement(
        videoID: String,
        userID: String,
        type: InteractionType,
        userTier: UserTier
    ) async throws -> (newHypeCount: Int, newCoolCount: Int, cloutAwarded: Int) {
        
        // Get current video
        let video = try await getVideo(id: videoID)
        
        // Calculate clout reward
        let cloutAwarded = calculateCloutReward(giverTier: userTier)
        
        // Update video counts
        let newHypeCount = type == .hype ? video.hypeCount + 1 : video.hypeCount
        let newCoolCount = type == .cool ? video.coolCount + 1 : video.coolCount
        
        // Perform updates in transaction
        try await db.runTransaction { transaction, errorPointer in
            // Update video engagement counts
            let videoRef = self.db.collection(FirebaseSchema.Collections.videos).document(videoID)
            transaction.updateData([
                FirebaseSchema.VideoDocument.hypeCount: newHypeCount,
                FirebaseSchema.VideoDocument.coolCount: newCoolCount,
                FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp(),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ], forDocument: videoRef)
            
            // Create final interaction record (only completed engagements)
            let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
                videoID: videoID, userID: userID, type: type.rawValue
            )
            let interactionRef = self.db.collection(FirebaseSchema.Collections.interactions).document(interactionID)
            transaction.setData([
                FirebaseSchema.InteractionDocument.userID: userID,
                FirebaseSchema.InteractionDocument.videoID: videoID,
                FirebaseSchema.InteractionDocument.engagementType: type.rawValue,
                FirebaseSchema.InteractionDocument.timestamp: Timestamp(),
                FirebaseSchema.InteractionDocument.isCompleted: true
            ], forDocument: interactionRef)
            
            return nil
        }
        
        // Award clout to video creator (separate operation to avoid transaction complexity)
        try await awardCloutToCreator(creatorID: video.creatorID, amount: cloutAwarded)
        
        return (newHypeCount: newHypeCount, newCoolCount: newCoolCount, cloutAwarded: cloutAwarded)
    }
    
    /// Reset tap progress after successful engagement
    private func resetTapProgress(videoID: String, userID: String, type: InteractionType) async throws {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).delete()
    }
    
    /// Award clout to video creator
    private func awardCloutToCreator(creatorID: String, amount: Int) async throws {
        let userRef = db.collection(FirebaseSchema.Collections.users).document(creatorID)
        try await userRef.updateData([
            FirebaseSchema.UserDocument.clout: FieldValue.increment(Int64(amount)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ])
        print("💰 VIDEO SERVICE: Awarded \(amount) clout to creator \(creatorID)")
    }
    
    /// Get total engagements for a user with a specific video
    private func getTotalEngagements(videoID: String, userID: String) async throws -> Int {
        let snapshot = try await db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .whereField(FirebaseSchema.InteractionDocument.userID, isEqualTo: userID)
            .whereField(FirebaseSchema.InteractionDocument.isCompleted, isEqualTo: true)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    /// Calculate progressive tap requirement
    private func calculateProgressiveTaps(engagementNumber: Int) -> Int {
        if engagementNumber <= 4 {
            return 1  // First 4 engagements are instant
        }
        
        // Progressive: 5th = 2, 6th = 4, 7th = 8, 8th = 16, etc.
        let progressiveIndex = engagementNumber - 4 - 1  // 0-based index for progression
        let requirement = 2 * Int(pow(2.0, Double(progressiveIndex)))
        return min(requirement, 256)  // Cap at 256
    }
    
    /// Calculate clout reward based on user tier
    private func calculateCloutReward(giverTier: UserTier) -> Int {
        switch giverTier {
        case .rookie: return 1
        case .rising: return 3
        case .veteran: return 10
        case .influencer: return 25
        case .elite: return 50
        case .partner: return 100
        case .legendary: return 250
        case .topCreator: return 500
        case .founder: return 1000
        case .coFounder: return 1000
        }
    }
    
    // MARK: - Create Operations
    
    /// Create new thread (parent video) with Firebase Auth validation
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
        
        let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,  // Use validated Firebase UID
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
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        let video = createCoreVideoMetadata(from: videoData, id: videoID)
        print("VIDEO SERVICE: Created thread \(videoID) with Firebase UID \(validatedCreatorID)")
        return video
    }
    
    /// Create child reply in thread with Firebase Auth validation
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
        
        // Ensure we're using the actual Firebase UID, not any other ID
        let validatedCreatorID = currentFirebaseUID
        
        if creatorID != validatedCreatorID {
            print("⚠️ VIDEO SERVICE: Correcting creatorID from '\(creatorID)' to Firebase UID '\(validatedCreatorID)'")
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
            FirebaseSchema.VideoDocument.creatorID: validatedCreatorID,  // Use validated Firebase UID
            FirebaseSchema.VideoDocument.creatorName: creatorName,
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
        print("VIDEO SERVICE: Created reply \(videoID) to \(parentID) with Firebase UID \(validatedCreatorID)")
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
        
        // Get all threads for discovery feed
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
            
            // Load child videos for this thread
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
        
        // Get interaction data
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
    
    /// Update video engagement counts
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
    
    /// Record user interaction (LEGACY - use processProgressiveTap instead)
    func recordUserInteraction(
        videoID: String,
        userID: String,
        interactionType: InteractionType,
        watchTime: TimeInterval = 0
    ) async throws {
        
        // For views, require minimum 5 seconds watch time
        if interactionType == .view {
            guard watchTime >= 5.0 else {
                print("VIDEO SERVICE: View not counted - insufficient watch time (\(String(format: "%.1f", watchTime))s, need 5.0s)")
                return
            }
            
            // Generate unique ID with timestamp for multiple views
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
            
            // Update video view count
            try await incrementVideoViewCount(videoID: videoID)
            
            print("VIDEO SERVICE: Recorded view interaction for \(videoID) (watch time: \(String(format: "%.1f", watchTime))s)")
            
        } else if interactionType == .share {
            // For shares, use standard duplicate prevention
            let hasShared = try await hasUserInteracted(userID: userID, videoID: videoID, interactionType: .share)
            guard !hasShared else {
                print("VIDEO SERVICE: User \(userID) already shared video \(videoID)")
                return
            }
            
            let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
                videoID: videoID, userID: userID, type: interactionType.rawValue
            )
            
            let interactionData: [String: Any] = [
                FirebaseSchema.InteractionDocument.userID: userID,
                FirebaseSchema.InteractionDocument.videoID: videoID,
                FirebaseSchema.InteractionDocument.engagementType: interactionType.rawValue,
                "watchTime": watchTime,
                FirebaseSchema.InteractionDocument.timestamp: Timestamp(),
                FirebaseSchema.InteractionDocument.isCompleted: true
            ]
            
            try await db.collection(FirebaseSchema.Collections.interactions).document(interactionID).setData(interactionData)
            print("VIDEO SERVICE: Recorded share interaction for \(videoID)")
            
        } else {
            print("WARNING VIDEO SERVICE: Use processProgressiveTap for \(interactionType.rawValue) engagements")
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
    
    /// Convenience method for tracking views with watch time validation
    func trackVideoView(videoID: String, userID: String, watchTime: TimeInterval) async throws {
        try await recordUserInteraction(
            videoID: videoID,
            userID: userID,
            interactionType: .view,
            watchTime: watchTime
        )
    }
    
    /// Check if user has already interacted with video
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
    
    /// Save engagement state to Firebase (for EngagementCoordinator)
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
        print("VIDEO SERVICE: Saved engagement state for key \(key)")
    }
    
    /// Load engagement state from Firebase (for EngagementCoordinator)
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
        
        // Create VideoEngagementState with basic parameters and then update it
        var state = VideoEngagementState(
            videoID: videoID,
            userID: userID,
            createdAt: lastEngagementTimestamp.dateValue()
        )
        
        // Update the state with loaded values
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
        
        guard document.exists, let videoData = document.data() else {
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
        
        // Calculate temperature using local method
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
        
        print("VIDEO SERVICE: Temperature updated to \(temperature.rawValue) for video \(videoID)")
    }
    
    // MARK: - Delete Operations
    
    /// Delete video and all related data
    func deleteVideo(videoID: String) async throws {
        print("VIDEO SERVICE: Starting deletion of video \(videoID)")
        
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos).document(videoID).getDocument()
        
        guard videoDoc.exists, let videoData = videoDoc.data() else {
            throw StitchError.validationError("Video not found")
        }
        
        // Check if this is a parent video (thread)
        let conversationDepth = videoData[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        if conversationDepth == 0 {
            // This is a parent video - delete entire thread
            try await deleteEntireThread(threadID: videoID)
        } else {
            // This is a child video - delete only this video
            try await deleteSingleVideo(videoID: videoID, videoData: videoData)
        }
        
        print("VIDEO SERVICE: Completed deletion of video \(videoID)")
    }
    
    /// Delete entire thread (parent + all children)
    private func deleteEntireThread(threadID: String) async throws {
        do {
            // Get all videos in thread
            let threadSnapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
                .getDocuments()
            
            print("VIDEO SERVICE: Deleting thread with \(threadSnapshot.documents.count) videos")
            
            // Delete each video and its storage files
            for document in threadSnapshot.documents {
                let videoData = document.data()
                
                // Delete storage files
                if let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String {
                    try? await deleteFromStorage(url: videoURL)
                }
                
                if let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String {
                    try? await deleteFromStorage(url: thumbnailURL)
                }
                
                // Delete video document
                try await document.reference.delete()
            }
            
            // Clean up related data
            await cleanupRelatedData(videoID: threadID)
            
            print("VIDEO SERVICE: Deleted thread \(threadID)")
            
        } catch {
            print("VIDEO SERVICE: Failed to delete thread: \(error)")
            throw StitchError.processingError("Failed to delete thread: \(error.localizedDescription)")
        }
    }
    
    /// Delete single video
    private func deleteSingleVideo(videoID: String, videoData: [String: Any]) async throws {
        do {
            // Delete storage files
            if let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String {
                try? await deleteFromStorage(url: videoURL)
            }
            
            if let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String {
                try? await deleteFromStorage(url: thumbnailURL)
            }
            
            // Update parent reply count if this is a child video
            if let parentID = videoData[FirebaseSchema.VideoDocument.replyToVideoID] as? String {
                try? await db.collection(FirebaseSchema.Collections.videos)
                    .document(parentID)
                    .updateData([
                        FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(-1)),
                        FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                    ])
            }
            
            // Delete video document
            try await db.collection(FirebaseSchema.Collections.videos).document(videoID).delete()
            
            // Clean up related data
            await cleanupRelatedData(videoID: videoID)
            
            print("VIDEO SERVICE: Deleted video \(videoID)")
            
        } catch {
            print("VIDEO SERVICE: Failed to delete video: \(error)")
            throw StitchError.processingError("Failed to delete video: \(error.localizedDescription)")
        }
    }
    
    /// Clean up interactions and engagement states
    private func cleanupRelatedData(videoID: String) async {
        do {
            // Delete interactions
            let interactionDocs = try await db.collection(FirebaseSchema.Collections.interactions)
                .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
                .getDocuments()
            
            for doc in interactionDocs.documents {
                try await doc.reference.delete()
            }
            
            // Delete tap progress records
            let tapProgressDocs = try await db.collection(FirebaseSchema.Collections.tapProgress)
                .whereField(FirebaseSchema.TapProgressDocument.videoID, isEqualTo: videoID)
                .getDocuments()
            
            for doc in tapProgressDocs.documents {
                try await doc.reference.delete()
            }
            
            print("VIDEO SERVICE: Deleted \(interactionDocs.documents.count) interaction records and \(tapProgressDocs.documents.count) tap progress records")
            
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
    
    // MARK: - Private Helper Methods
    
    /// Create CoreVideoMetadata from Firestore data
    internal func createCoreVideoMetadata(from data: [String: Any], id: String) -> CoreVideoMetadata {
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let engagementRatio = hypeCount + coolCount > 0 ? Double(hypeCount) / Double(hypeCount + coolCount) : 0.5
        
        return CoreVideoMetadata(
            id: id,
            title: data[FirebaseSchema.VideoDocument.title] as? String ?? "",
            description: data[FirebaseSchema.VideoDocument.description] as? String ?? "",
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
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0,
            aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0,
            fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
            discoverabilityScore: data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5,
            isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        )
    }
    
    /// Calculate video temperature locally (no dependencies)
    private func calculateVideoTemperature(
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        ageInMinutes: Double,
        creatorTier: UserTier
    ) -> Temperature {
        
        // Calculate engagement ratio
        let totalEngagement = hypeCount + coolCount
        let engagementRate = viewCount > 0 ? Double(totalEngagement) / Double(viewCount) : 0.0
        
        // Calculate velocity (engagements per hour)
        let ageInHours = ageInMinutes / 60.0
        let velocity = ageInHours > 0 ? Double(totalEngagement) / ageInHours : 0.0
        
        // Calculate positivity ratio
        let positivityRatio = totalEngagement > 0 ? Double(hypeCount) / Double(totalEngagement) : 0.5
        
        // Creator tier multiplier
        let tierMultiplier: Double
        switch creatorTier {
        case .rookie: tierMultiplier = 1.0
        case .rising: tierMultiplier = 1.2
        case .veteran: tierMultiplier = 1.5
        case .influencer: tierMultiplier = 2.0
        case .elite: tierMultiplier = 2.5
        case .partner: tierMultiplier = 3.0
        case .legendary: tierMultiplier = 4.0
        case .topCreator: tierMultiplier = 5.0
        case .founder, .coFounder: tierMultiplier = 6.0
        }
        
        // Time decay factor (newer content gets boost)
        let timeFactor = ageInHours < 24 ? 1.0 : max(0.5, 1.0 - (ageInHours - 24) / 168) // Week decay
        
        // Calculate score
        let score = (engagementRate * 40 + velocity * 30 + positivityRatio * 20) * tierMultiplier * timeFactor
        
        // Map to temperature
        if score >= 60 { return .blazing }
        if score >= 40 { return .hot }
        if score >= 20 { return .warm }
        if score >= 10 { return .cool }
        return .cold
    }
    
    /// Get user tier for temperature calculations
    private func getUserTier(userID: String) async throws -> UserTier {
        do {
            let userDoc = try await db.collection(FirebaseSchema.Collections.users).document(userID).getDocument()
            guard let userData = userDoc.data() else { return .rookie }
            
            let tierString = userData[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
            return UserTier(rawValue: tierString) ?? .rookie
        } catch {
            print("VIDEO SERVICE: Failed to get user tier for \(userID): \(error)")
            return .rookie
        }
    }
    
    /// Calculate video temperature based on engagement (simple version)
    private func calculateTemperature(hypeCount: Int, coolCount: Int, viewCount: Int) -> String {
        guard viewCount > 0 else { return "cold" }
        
        let engagementRate = Double(hypeCount + coolCount) / Double(viewCount)
        
        if engagementRate >= 0.7 { return "hot" }
        if engagementRate >= 0.4 { return "warm" }
        if engagementRate >= 0.2 { return "cool" }
        return "cold"
    }
}

// MARK: - Extensions for Array Chunking
extension Array {
    func Mychunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Hello World Test Extension
extension VideoService {
    
    /// Test video service functionality
    func helloWorldTest() {
        print("🎯 VIDEO SERVICE: Progressive tapping system ready!")
        print("🎯 VIDEO SERVICE: Features: Tap progress tracking, separate collections, no duplicates")
        print("🎯 VIDEO SERVICE: Collections: tap_progress, interactions, videos")
    }
}
