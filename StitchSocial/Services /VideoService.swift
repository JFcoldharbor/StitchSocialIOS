//
//  VideoService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Enhanced Video Management
//  Dependencies: Firebase Firestore, CachingService, BatchingService
//  Features: Thread hierarchy, following feed, multidirectional swiping support, engagement updates, video deletion
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Enhanced video management service with HomeFeed multidirectional swiping support
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
            FirebaseSchema.VideoDocument.moderationStatus: "approved"
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(videoData)
        
        // Create engagement document
        try await createEngagementDocument(videoID: videoID, creatorID: creatorID)
        
        print("✅ VIDEO SERVICE: Thread created: \(videoID)")
        
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
        
        // Cache when available
        // cachingService.cacheVideo(video)
        
        return video
    }
    
    /// Create child reply to thread
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
        
        let videoData: [String: Any] = [
            FirebaseSchema.VideoDocument.id: videoID,
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.videoURL: videoURL,
            FirebaseSchema.VideoDocument.thumbnailURL: thumbnailURL,
            FirebaseSchema.VideoDocument.creatorID: creatorID,
            FirebaseSchema.VideoDocument.creatorName: creatorName,
            FirebaseSchema.VideoDocument.createdAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
            
            // Thread hierarchy
            FirebaseSchema.VideoDocument.threadID: threadID,
            FirebaseSchema.VideoDocument.conversationDepth: 1,
            
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
            FirebaseSchema.VideoDocument.moderationStatus: "approved"
        ]
        
        // Update parent thread reply count
        let batch = db.batch()
        
        let videoRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
        batch.setData(videoData, forDocument: videoRef)
        
        let threadRef = db.collection(FirebaseSchema.Collections.videos).document(threadID)
        batch.updateData([
            FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ], forDocument: threadRef)
        
        try await batch.commit()
        
        // Create engagement document
        try await createEngagementDocument(videoID: videoID, creatorID: creatorID)
        
        print("✅ VIDEO SERVICE: Child reply created for thread \(threadID)")
        
        let video = CoreVideoMetadata(
            id: videoID,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: threadID,
            replyToVideoID: nil,
            conversationDepth: 1,
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
        
        // Cache when available
        // cachingService.cacheVideo(video)
        // cachingService.removeCachedThread(threadID)
        
        return video
    }
    
    // MARK: - Delete Operations
    
    /// Delete video and clean up related data
    func deleteVideo(videoID: String, creatorID: String) async throws {
        
        // Validate permissions
        let videoRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
        
        // Get video data first
        let snapshot = try await videoRef.getDocument()
        guard let data = snapshot.data() else {
            throw StitchError.processingError("Video not found")
        }
        
        // Verify creator permissions
        guard data[FirebaseSchema.VideoDocument.creatorID] as? String == creatorID else {
            throw StitchError.authenticationError("Not authorized to delete this video")
        }
        
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        
        // Create batch for atomic deletion
        let batch = db.batch()
        
        // Delete main video document
        batch.deleteDocument(videoRef)
        
        // Delete engagement document
        let engagementRef = db.collection(FirebaseSchema.Collections.engagement).document(videoID)
        batch.deleteDocument(engagementRef)
        
        // Handle thread hierarchy cleanup
        if conversationDepth == 0 && replyCount > 0 {
            // Deleting parent thread - delete all children
            let childVideosQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: videoID)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            
            let childSnapshot = try await childVideosQuery.getDocuments()
            
            for childDoc in childSnapshot.documents {
                batch.deleteDocument(childDoc.reference)
                
                // Delete child engagement documents
                let childEngagementRef = db.collection(FirebaseSchema.Collections.engagement).document(childDoc.documentID)
                batch.deleteDocument(childEngagementRef)
            }
            
        } else if conversationDepth > 0, let threadID = threadID {
            // Deleting child video - update parent reply count
            let parentRef = db.collection(FirebaseSchema.Collections.videos).document(threadID)
            batch.updateData([
                FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(-1)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ], forDocument: parentRef)
        }
        
        // Execute batch deletion
        try await batch.commit()
        
        // Clean up Firebase Storage files
        await deleteVideoFiles(videoID: videoID, videoURL: data[FirebaseSchema.VideoDocument.videoURL] as? String)
        
        print("✅ VIDEO SERVICE: Video \(videoID) deleted successfully")
    }
    
    /// Delete multiple videos in batch (for bulk operations)
    func deleteVideos(videoIDs: [String], creatorID: String) async throws {
        
        guard !videoIDs.isEmpty else { return }
        
        // Process in chunks to avoid Firestore batch limits
        for chunk in videoIDs.chunked(into: 10) {
            try await deleteVideoChunk(videoIDs: chunk, creatorID: creatorID)
        }
        
        print("✅ VIDEO SERVICE: Batch deleted \(videoIDs.count) videos")
    }
    
    /// Delete a chunk of videos atomically
    private func deleteVideoChunk(videoIDs: [String], creatorID: String) async throws {
        
        let batch = db.batch()
        var videosToDeleteFromStorage: [(videoID: String, videoURL: String?)] = []
        
        // Fetch all videos first to validate permissions and gather data
        for videoID in videoIDs {
            let videoRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
            let snapshot = try await videoRef.getDocument()
            
            guard let data = snapshot.data() else { continue }
            
            // Verify creator permissions
            guard data[FirebaseSchema.VideoDocument.creatorID] as? String == creatorID else {
                throw StitchError.authenticationError("Not authorized to delete video \(videoID)")
            }
            
            // Queue for batch deletion
            batch.deleteDocument(videoRef)
            
            // Queue engagement document for deletion
            let engagementRef = db.collection(FirebaseSchema.Collections.engagement).document(videoID)
            batch.deleteDocument(engagementRef)
            
            // Queue storage cleanup
            let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String
            videosToDeleteFromStorage.append((videoID: videoID, videoURL: videoURL))
            
            // Handle thread hierarchy (simplified for batch - only handle child deletions)
            let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String
            let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
            
            if conversationDepth > 0, let threadID = threadID {
                // Update parent reply count for child deletions
                let parentRef = db.collection(FirebaseSchema.Collections.videos).document(threadID)
                batch.updateData([
                    FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(-1)),
                    FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                ], forDocument: parentRef)
            }
        }
        
        // Execute batch deletion
        try await batch.commit()
        
        // Clean up storage files
        await deleteMultipleVideoFiles(videosToDeleteFromStorage)
    }
    
    /// Delete associated video files from Firebase Storage
    private func deleteVideoFiles(videoID: String, videoURL: String?) async {
        guard let videoURL = videoURL, !videoURL.isEmpty else { return }
        
        do {
            // Delete video file
            let videoRef = storage.reference(forURL: videoURL)
            try await videoRef.delete()
            
            // Delete thumbnail if exists
            let thumbnailPath = "thumbnails/\(videoID).jpg"
            let thumbnailRef = storage.reference().child(thumbnailPath)
            try await thumbnailRef.delete()
            
            print("✅ VIDEO SERVICE: Storage files deleted for video \(videoID)")
            
        } catch {
            print("⚠️ VIDEO SERVICE: Failed to delete storage files: \(error)")
            // Don't throw error - video document deletion succeeded
        }
    }
    
    /// Delete multiple video files from storage
    private func deleteMultipleVideoFiles(_ videos: [(videoID: String, videoURL: String?)]) async {
        
        await withTaskGroup(of: Void.self) { group in
            for video in videos {
                group.addTask {
                    await self.deleteVideoFiles(videoID: video.videoID, videoURL: video.videoURL)
                }
            }
        }
    }
    
    // MARK: - Engagement Update Operations
    
    /// Update video engagement metrics in database
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
            
            // Update engagement document
            let engagementUpdateData: [String: Any] = [
                FirebaseSchema.EngagementDocument.hypeCount: hypeCount,
                FirebaseSchema.EngagementDocument.coolCount: coolCount,
                FirebaseSchema.EngagementDocument.viewCount: viewCount,
                FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(date: lastEngagementAt)
            ]
            
            try await db.collection(FirebaseSchema.Collections.engagement)
                .document(videoID)
                .updateData(engagementUpdateData)
            
            print("✅ VIDEO SERVICE: Updated engagement for video \(videoID)")
            print("✅ VIDEO SERVICE: Hype: \(hypeCount), Cool: \(coolCount), Views: \(viewCount)")
            
        } catch {
            lastError = .processingError("Failed to update engagement: \(error.localizedDescription)")
            print("❌ VIDEO SERVICE: Engagement update failed - \(error)")
            throw lastError!
        }
    }
    
    /// Record user's engagement interaction with a video
    func recordUserEngagement(
        userID: String,
        videoID: String,
        interactionType: InteractionType,
        timestamp: Date
    ) async throws {
        
        do {
            // Create user interaction record
            let interactionData: [String: Any] = [
                "userID": userID,
                "videoID": videoID,
                "interactionType": interactionType.rawValue,
                "timestamp": Timestamp(date: timestamp),
                "createdAt": Timestamp()
            ]
            
            // Use a composite document ID to prevent duplicates
            let interactionID = "\(userID)_\(videoID)_\(interactionType.rawValue)"
            
            try await db.collection(FirebaseSchema.Collections.interactions)
                .document(interactionID)
                .setData(interactionData, merge: true)
            
            print("✅ VIDEO SERVICE: Recorded \(interactionType.rawValue) interaction for user \(userID) on video \(videoID)")
            
        } catch {
            print("❌ VIDEO SERVICE: Failed to record user engagement - \(error)")
            // Don't throw error here as this is for analytics and shouldn't break the main flow
        }
    }
    
    /// Check if user has already interacted with video
    func hasUserInteracted(
        userID: String,
        videoID: String,
        interactionType: InteractionType
    ) async throws -> Bool {
        
        do {
            let interactionID = "\(userID)_\(videoID)_\(interactionType.rawValue)"
            let document = try await db.collection(FirebaseSchema.Collections.interactions)
                .document(interactionID)
                .getDocument()
            
            return document.exists
            
        } catch {
            print("⚠️ VIDEO SERVICE: Failed to check user interaction - \(error)")
            return false // Default to false if we can't check
        }
    }
    
    /// Get user's engagement status for a video
    func getUserEngagementStatus(
        userID: String,
        videoID: String
    ) async throws -> UserEngagementStatus {
        
        do {
            // Check all interaction types
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
            print("⚠️ VIDEO SERVICE: Failed to get engagement status - \(error)")
            return UserEngagementStatus(hasHyped: false, hasCooled: false, hasViewed: false, hasShared: false)
        }
    }
    
    /// Batch update engagement for multiple videos (for performance)
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
                
                // Update engagement document
                let engagementRef = db.collection(FirebaseSchema.Collections.engagement).document(update.videoID)
                let engagementUpdateData: [String: Any] = [
                    FirebaseSchema.EngagementDocument.hypeCount: update.hypeCount,
                    FirebaseSchema.EngagementDocument.coolCount: update.coolCount,
                    FirebaseSchema.EngagementDocument.viewCount: update.viewCount,
                    FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(date: update.lastEngagementAt)
                ]
                batch.updateData(engagementUpdateData, forDocument: engagementRef)
            }
            
            try await batch.commit()
            print("✅ VIDEO SERVICE: Batch updated engagement for \(updates.count) videos")
            
        } catch {
            lastError = .processingError("Failed to batch update engagement: \(error.localizedDescription)")
            print("❌ VIDEO SERVICE: Batch engagement update failed - \(error)")
            throw lastError!
        }
    }
    
    // MARK: - Enhanced Read Operations for HomeFeed
    
    /// Get following feed with complete thread data (Horizontal + Vertical swiping)
    func getFollowingThreadsWithChildren(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // Simplified implementation without batching service
        // Step 1: Get following list
        // CORRECT: Query the following collection (not subcollection)
        let followingQuery = db.collection("following")
            .whereField("followerID", isEqualTo: userID)
            .whereField("isActive", isEqualTo: true)

        let followingSnapshot = try await followingQuery.getDocuments()
        let followingUserIDs = followingSnapshot.documents.compactMap { doc in
            doc.data()["followingID"] as? String
        }
        
        if followingUserIDs.isEmpty {
            return (threads: [], lastDocument: nil, hasMore: false)
        }
        
        // Step 2: Get threads from followed users (simplified batching)
        var allThreads: [ThreadData] = []
        
        for batch in followingUserIDs.chunked(into: 10) {
            let threadsQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, in: batch)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
            
            let threadsSnapshot = try await threadsQuery.getDocuments()
            
            for doc in threadsSnapshot.documents {
                if let video = try createVideoFromDocument(doc) {
                    let children = try await getThreadChildren(threadID: video.id)
                    let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: children)
                    allThreads.append(threadData)
                }
            }
        }
        
        // Simple randomization for content variety
        let shuffledThreads = allThreads.shuffled().prefix(limit)
        
        print("✅ VIDEO SERVICE: Following feed loaded - \(shuffledThreads.count) threads with children")
        return (threads: Array(shuffledThreads), lastDocument: nil, hasMore: false)
    }
    
    /// Get thread children for vertical swiping
    func getThreadChildren(
        threadID: String,
        limit: Int = 10
    ) async throws -> [CoreVideoMetadata] {
        
        // Load from Firebase (cache integration when available)
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 1)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        let children = try snapshot.documents.compactMap { doc in
            try createVideoFromDocument(doc)
        }
        
        print("✅ VIDEO SERVICE: Loaded \(children.count) children for thread \(threadID)")
        return children
    }
    
    /// Build complete ThreadData structure
    func buildThreadData(
        parentVideo: CoreVideoMetadata,
        includeChildren: Bool = true
    ) async throws -> ThreadData {
        
        var childVideos: [CoreVideoMetadata] = []
        
        if includeChildren {
            childVideos = try await getThreadChildren(threadID: parentVideo.id)
        }
        
        let threadData = ThreadData(
            id: parentVideo.id,
            parentVideo: parentVideo,
            childVideos: childVideos
        )
        
        return threadData
    }
    
    /// Get all threads (fallback for empty following)
    func getAllThreadsWithChildren(
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // Get all threads (simplified implementation)
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
            if let video = try createVideoFromDocument(doc) {
                let children = try await getThreadChildren(threadID: video.id)
                let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: children)
                threads.append(threadData)
            }
        }
        
        // Simple randomization
        let shuffledThreads = threads.shuffled()
        
        let hasMore = snapshot.documents.count >= limit
        
        print("✅ VIDEO SERVICE: All threads loaded - \(shuffledThreads.count) threads")
        return (threads: shuffledThreads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }
    
    // MARK: - Cache Optimization Helpers (For Future Implementation)
    
    /// Get cached following threads for quick access (when caching available)
    private func getCachedFollowingThreads(userID: String, limit: Int) -> [ThreadData] {
        // Implementation would check cache for user's following feed
        // For now, return empty array to always hit fresh data
        return []
    }
    
    /// Preload threads for smooth swiping
    func preloadThreadsForNavigation(
        threads: [ThreadData],
        currentIndex: Int,
        direction: SwipeDirection = .horizontal
    ) async {
        
        let preloadRange: Range<Int>
        
        switch direction {
        case .horizontal:
            // Preload next 2 threads ahead
            let start = max(0, currentIndex + 1)
            let end = min(threads.count, currentIndex + 3)
            preloadRange = start..<end
            
        case .vertical:
            // Preload children for current thread
            guard currentIndex < threads.count else { return }
            let currentThread = threads[currentIndex]
            
            // Ensure children are loaded and cached
            if currentThread.childVideos.isEmpty {
                _ = try? await getThreadChildren(threadID: currentThread.id)
            }
            return
        }
        
        // Preload horizontal threads
        for index in preloadRange {
            let thread = threads[index]
            
            // Ensure thread has children loaded
            if thread.childVideos.isEmpty {
                _ = try? await getThreadChildren(threadID: thread.id)
            }
        }
        
        print("🎯 VIDEO SERVICE: Preloaded threads for \(direction) navigation")
    }
    
    // MARK: - Basic Read Operations (Legacy Support)
    
    /// Get basic threads for simple views
    func getThreadsForHomeFeed(
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> PaginatedResult<CoreVideoMetadata> {
        
        let query: Query
        if let lastDoc = lastDocument {
            query = db.collection("videos")
                .whereField("conversationDepth", isEqualTo: 0)
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: limit)
        } else {
            query = db.collection("videos")
                .whereField("conversationDepth", isEqualTo: 0)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()
        let videos = try snapshot.documents.compactMap { doc in
            try createVideoFromDocument(doc)
        }
        
        // Cache videos when available
        // cachingService.cacheVideos(videos)
        
        print("✅ VIDEO SERVICE: Loaded \(videos.count) basic threads")
        
        return PaginatedResult(
            items: videos,
            lastDocument: snapshot.documents.last,
            hasMore: snapshot.documents.count >= limit
        )
    }
    
    /// Get video by ID
    func getVideo(id: String) async throws -> CoreVideoMetadata? {
        
        // Cache when available (when CachingService is restored)
        // if let cached = cachingService.getCachedVideo(id) {
        //     return cached
        // }
        
        // Load from Firebase
        let doc = try await db.collection(FirebaseSchema.Collections.videos).document(id).getDocument()
        
        guard doc.exists, let video = try createVideoFromDocument(doc) else {
            return nil
        }
        
        // Cache when available
        // cachingService.cacheVideo(video)
        
        return video
    }
    
    // MARK: - Helper Methods
    
    /// Create video metadata from Firestore document
    private func createVideoFromDocument(_ document: DocumentSnapshot) throws -> CoreVideoMetadata? {
        let data = document.data()
        guard let data = data else { return nil }
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? ""
        let createdAtTimestamp = data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp
        let createdAt = createdAtTimestamp?.dateValue() ?? Date()
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? (9.0/16.0)
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        let discoverabilityScore = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false
        let lastEngagementAtTimestamp = data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp
        let lastEngagementAt = lastEngagementAtTimestamp?.dateValue()
        
        // Calculate derived metrics
        let total = hypeCount + coolCount
        let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
        let totalInteractions = hypeCount + coolCount + replyCount + shareCount
        let ageInHours = Date().timeIntervalSince(createdAt) / 3600.0
        let velocityScore = ageInHours > 0 ? Double(totalInteractions) / ageInHours : 0.0
        
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
            trendingScore: 0.0, // Default trending score
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: lastEngagementAt
        )
    }
    
    /// Create engagement document for new video
    private func createEngagementDocument(videoID: String, creatorID: String) async throws {
        let engagementData: [String: Any] = [
            FirebaseSchema.EngagementDocument.videoID: videoID,
            FirebaseSchema.EngagementDocument.creatorID: creatorID,
            FirebaseSchema.EngagementDocument.hypeCount: 0,
            FirebaseSchema.EngagementDocument.coolCount: 0,
            FirebaseSchema.EngagementDocument.shareCount: 0,
            FirebaseSchema.EngagementDocument.replyCount: 0,
            FirebaseSchema.EngagementDocument.viewCount: 0,
            FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.engagement)
            .document(videoID)
            .setData(engagementData)
    }
}

// MARK: - Supporting Types for Engagement

/// User engagement status for a specific video
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

// MARK: - Existing Supporting Types

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
        } else if index - 1 < childVideos.count {
            return childVideos[index - 1]
        }
        return nil
    }
    
    /// Check if thread has replies
    var hasReplies: Bool {
        return !childVideos.isEmpty
    }
}

/// Paginated result wrapper
struct PaginatedResult<T> {
    let items: [T]
    let lastDocument: DocumentSnapshot?
    let hasMore: Bool
}

// MARK: - Array Extension for Chunking

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
        print("🔹 VIDEO SERVICE: Enhanced Hello World - Ready for multidirectional swiping!")
        print("🔹 VIDEO SERVICE: Features: Thread hierarchy, following feed, engagement updates, video deletion")
        print("🔹 VIDEO SERVICE: Performance: Direct Firebase access with real-time engagement")
    }
}
