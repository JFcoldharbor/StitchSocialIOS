//
//  VideoService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Complete Video Management with Enhanced Deletion
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema
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
        
        print("✅ VIDEO SERVICE: Thread created - \(videoID)")
        
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
            FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
            FirebaseSchema.VideoDocument.isPromoted: false
        ]
        
        // Use batch for atomic operations
        let batch = db.batch()
        
        // Create child video document
        let videoRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
        batch.setData(videoData, forDocument: videoRef)
        
        // Update parent thread reply count
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
        
        return video
    }
    
    // MARK: - Delete Operations - ROBUST IMPLEMENTATION
    
    /// Delete video with complete cleanup - SIMPLIFIED for permission stability
    func deleteVideo(videoID: String, creatorID: String) async throws {
        
        print("🗑️ VIDEO SERVICE: Starting deletion for video: \(videoID)")
        
        // Step 1: Verify video exists and ownership
        let videoDoc = try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .getDocument()
        
        guard videoDoc.exists,
              let videoData = videoDoc.data(),
              let docCreatorID = videoData[FirebaseSchema.VideoDocument.creatorID] as? String,
              docCreatorID == creatorID else {
            throw StitchError.validationError("Video not found or unauthorized")
        }
        
        // Step 2: Get video data for cleanup
        let videoURL = videoData[FirebaseSchema.VideoDocument.videoURL] as? String
        let thumbnailURL = videoData[FirebaseSchema.VideoDocument.thumbnailURL] as? String
        let isThread = videoData[FirebaseSchema.VideoDocument.threadID] as? String == videoID
        let conversationDepth = videoData[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        let threadID = videoData[FirebaseSchema.VideoDocument.threadID] as? String
        let replyCount = videoData[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        
        // Step 3: Delete documents individually with better error handling
        do {
            // Delete video document first
            try await db.collection(FirebaseSchema.Collections.videos).document(videoID).delete()
            print("✅ VIDEO SERVICE: Video document deleted")
            
            // Delete engagement document (may not exist)
            do {
                try await db.collection(FirebaseSchema.Collections.engagement).document(videoID).delete()
                print("✅ VIDEO SERVICE: Engagement document deleted")
            } catch {
                print("⚠️ VIDEO SERVICE: Engagement document deletion failed (may not exist): \(error)")
            }
            
            // Delete thread document if this is a thread starter
            if isThread {
                do {
                    try await db.collection(FirebaseSchema.Collections.threads).document(videoID).delete()
                    print("✅ VIDEO SERVICE: Thread document deleted")
                } catch {
                    print("⚠️ VIDEO SERVICE: Thread document deletion failed (may not exist): \(error)")
                }
            }
            
            // Handle child videos if this is a parent thread
            if conversationDepth == 0 && replyCount > 0 {
                await deleteChildVideos(threadID: videoID)
            }
            
            // Update parent reply count if this is a child video
            if conversationDepth > 0, let threadID = threadID {
                do {
                    try await db.collection(FirebaseSchema.Collections.videos).document(threadID).updateData([
                        FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(-1)),
                        FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                    ])
                    print("✅ VIDEO SERVICE: Parent reply count updated")
                } catch {
                    print("⚠️ VIDEO SERVICE: Failed to update parent reply count: \(error)")
                }
            }
            
            // Update user's video count
            do {
                try await db.collection(FirebaseSchema.Collections.users).document(creatorID).updateData([
                    FirebaseSchema.UserDocument.videoCount: FieldValue.increment(Int64(-1)),
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
                print("✅ VIDEO SERVICE: User video count updated")
            } catch {
                print("⚠️ VIDEO SERVICE: Failed to update user video count: \(error)")
            }
            
        } catch {
            print("❌ VIDEO SERVICE: Core deletion failed: \(error)")
            throw StitchError.processingError("Failed to delete video: \(error.localizedDescription)")
        }
        
        // Step 4: Clean up storage files (non-blocking)
        await deleteStorageFiles(videoURL: videoURL, thumbnailURL: thumbnailURL)
        
        // Step 5: Clean up related data (non-blocking)
        await cleanupRelatedData(videoID: videoID)
        
        print("✅ VIDEO SERVICE: Video deletion complete: \(videoID)")
    }
    
    /// Delete child videos when parent thread is deleted
    private func deleteChildVideos(threadID: String) async {
        do {
            let childVideosQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            
            let childSnapshot = try await childVideosQuery.getDocuments()
            
            for childDoc in childSnapshot.documents {
                do {
                    // Delete child video document
                    try await childDoc.reference.delete()
                    
                    // Delete child engagement document
                    try await db.collection(FirebaseSchema.Collections.engagement).document(childDoc.documentID).delete()
                    
                    print("✅ VIDEO SERVICE: Deleted child video: \(childDoc.documentID)")
                } catch {
                    print("⚠️ VIDEO SERVICE: Failed to delete child video \(childDoc.documentID): \(error)")
                }
            }
            
        } catch {
            print("⚠️ VIDEO SERVICE: Failed to query child videos: \(error)")
        }
    }
    
    /// Delete multiple videos in batch (for bulk operations)
    func deleteVideos(videoIDs: [String], creatorID: String) async throws {
        
        print("🗑️ VIDEO SERVICE: Starting batch deletion for \(videoIDs.count) videos")
        
        for videoID in videoIDs {
            do {
                try await deleteVideo(videoID: videoID, creatorID: creatorID)
                print("✅ VIDEO SERVICE: Deleted video \(videoID)")
            } catch {
                print("❌ VIDEO SERVICE: Failed to delete video \(videoID): \(error)")
                // Continue with other deletions even if one fails
            }
        }
        
        print("✅ VIDEO SERVICE: Batch deletion complete")
    }
    
    // MARK: - Private Deletion Helpers
    
    /// Delete video and thumbnail files from Firebase Storage
    private func deleteStorageFiles(videoURL: String?, thumbnailURL: String?) async {
        
        // Delete video file
        if let videoURL = videoURL, let videoRef = extractStorageRef(from: videoURL) {
            do {
                try await videoRef.delete()
                print("✅ VIDEO SERVICE: Video file deleted from storage")
            } catch {
                print("⚠️ VIDEO SERVICE: Failed to delete video file: \(error)")
            }
        }
        
        // Delete thumbnail file
        if let thumbnailURL = thumbnailURL, let thumbnailRef = extractStorageRef(from: thumbnailURL) {
            do {
                try await thumbnailRef.delete()
                print("✅ VIDEO SERVICE: Thumbnail deleted from storage")
            } catch {
                print("⚠️ VIDEO SERVICE: Failed to delete thumbnail: \(error)")
            }
        }
    }
    
    /// Extract Firebase Storage reference from download URL
    private func extractStorageRef(from downloadURL: String) -> StorageReference? {
        guard let url = URL(string: downloadURL),
              let pathComponent = url.path.split(separator: "/").last else {
            return nil
        }
        
        let fileName = String(pathComponent).removingPercentEncoding ?? String(pathComponent)
        
        if downloadURL.contains("videos/") {
            return Storage.storage().reference().child("videos/\(fileName)")
        } else if downloadURL.contains("thumbnails/") {
            return Storage.storage().reference().child("thumbnails/\(fileName)")
        } else if downloadURL.contains("profile_images/") {
            return Storage.storage().reference().child("profile_images/\(fileName)")
        }
        
        return nil
    }
    
    /// Clean up related engagement and interaction data
    private func cleanupRelatedData(videoID: String) async {
        
        do {
            // Delete user interactions for this video
            let interactionsQuery = db.collection(FirebaseSchema.Collections.interactions)
                .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            
            let interactionDocs = try await interactionsQuery.getDocuments()
            
            for doc in interactionDocs.documents {
                try await doc.reference.delete()
            }
            
            print("✅ VIDEO SERVICE: Deleted \(interactionDocs.documents.count) interaction records")
            
            // Delete view records (using interactions collection instead)
            let viewsQuery = db.collection(FirebaseSchema.Collections.interactions)
                .whereField("videoID", isEqualTo: videoID)
            
            let viewDocs = try await viewsQuery.getDocuments()
            
            for doc in viewDocs.documents {
                try await doc.reference.delete()
            }
            
            print("✅ VIDEO SERVICE: Deleted \(viewDocs.documents.count) view records")
            
        } catch {
            print("⚠️ VIDEO SERVICE: Failed to clean up related data: \(error)")
        }
    }
    
    // MARK: - Engagement Operations
    
    /// Update video engagement metrics in database (for EngagementCoordinator)
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
                FirebaseSchema.EngagementDocument.lastEngagementAt: Timestamp(date: lastEngagementAt),
                FirebaseSchema.EngagementDocument.updatedAt: Timestamp()
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
    
    /// Record user's engagement interaction with a video (for EngagementCoordinator)
    func recordUserEngagement(
        userID: String,
        videoID: String,
        interactionType: InteractionType,
        timestamp: Date
    ) async throws {
        
        do {
            // Create user interaction record
            let interactionData: [String: Any] = [
                FirebaseSchema.InteractionDocument.userID: userID,
                FirebaseSchema.InteractionDocument.videoID: videoID,
                FirebaseSchema.InteractionDocument.engagementType: interactionType.rawValue,
                FirebaseSchema.InteractionDocument.timestamp: Timestamp(date: timestamp),
                FirebaseSchema.InteractionDocument.currentTaps: 1,
                FirebaseSchema.InteractionDocument.requiredTaps: 2,
                FirebaseSchema.InteractionDocument.isCompleted: true,
                FirebaseSchema.InteractionDocument.impactValue: 1
            ]
            
            // Use document ID pattern from FirebaseSchema
            let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
                videoID: videoID,
                userID: userID,
                type: interactionType.rawValue
            )
            
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
    
    /// Batch update engagement metrics for multiple videos
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
    
    /// Get following feed with complete thread data - PERFORMANCE OPTIMIZED
    func getFollowingThreadsWithChildren(
        userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // Get following list efficiently
        let followingQuery = db.collection("following")
            .whereField("followerID", isEqualTo: userID)
            .whereField("isActive", isEqualTo: true)
            .limit(to: 100) // Limit following queries

        let followingSnapshot = try await followingQuery.getDocuments()
        let followingUserIDs = followingSnapshot.documents.compactMap { doc in
            doc.data()["followingID"] as? String
        }
        
        guard !followingUserIDs.isEmpty else {
            print("📭 VIDEO SERVICE: No following users found")
            return (threads: [], lastDocument: nil, hasMore: false)
        }
        
        // Get threads from following users - BATCH OPTIMIZED
        var allThreads: [ThreadData] = []
        
        // Process following users in smaller batches to avoid heavy queries
        for batch in followingUserIDs.chunked(into: 5) { // Reduced from 10 to 5 for better performance
            var threadsQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, in: batch)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 8) // Reduced limit per batch
            
            if let lastDoc = lastDocument {
                threadsQuery = threadsQuery.start(afterDocument: lastDoc)
            }
            
            let threadsSnapshot = try await threadsQuery.getDocuments()
            
            // Create ThreadData with EMPTY children initially (load on-demand)
            for doc in threadsSnapshot.documents {
                if let video = try createVideoFromDocument(doc) {
                    let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: [])
                    allThreads.append(threadData)
                }
            }
            
            // Break early if we have enough threads
            if allThreads.count >= limit {
                break
            }
        }
        
        // Limit final results and randomize
        let limitedThreads = Array(allThreads.shuffled().prefix(limit))
        
        print("✅ VIDEO SERVICE: Following feed loaded - \(limitedThreads.count) threads (optimized)")
        return (threads: limitedThreads, lastDocument: nil, hasMore: allThreads.count >= limit)
    }
    
    /// Get all threads with children for discovery feed - PERFORMANCE OPTIMIZED
    func getAllThreadsWithChildren(
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        // Get parent threads ONLY (don't load children yet for performance)
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        // Create ThreadData with EMPTY children for performance (load children on-demand)
        for doc in snapshot.documents {
            if let video = try createVideoFromDocument(doc) {
                let threadData = ThreadData(id: video.id, parentVideo: video, childVideos: [])
                threads.append(threadData)
            }
        }
        
        // Simple randomization
        let shuffledThreads = threads.shuffled()
        
        let hasMore = snapshot.documents.count >= limit
        
        print("✅ VIDEO SERVICE: All threads loaded - \(shuffledThreads.count) threads (children will load on-demand)")
        return (threads: shuffledThreads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }
    
    /// Get child videos for a thread - LAZY LOADING OPTIMIZED
    func getThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        
        // Simple query - load only when specifically requested
        let childQuery = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .limit(to: 10) // Limit children for performance
        
        let snapshot = try await childQuery.getDocuments()
        
        let children = try snapshot.documents.compactMap { doc in
            try createVideoFromDocument(doc)
        }
        
        print("✅ VIDEO SERVICE: Loaded \(children.count) children for thread \(threadID)")
        return children
    }
    
    /// Preload threads for smooth swiping - PERFORMANCE OPTIMIZED
    func preloadThreadsForNavigation(
        threads: [ThreadData],
        currentIndex: Int,
        direction: SwipeDirection = .horizontal
    ) async {
        
        let preloadRange: Range<Int>
        
        switch direction {
        case .horizontal:
            // Preload only next 1-2 threads ahead (reduced from 3)
            let start = max(0, currentIndex + 1)
            let end = min(threads.count, currentIndex + 2) // Reduced preload count
            preloadRange = start..<end
            
        case .vertical:
            // Preload children only for current thread
            guard currentIndex < threads.count else { return }
            let currentThread = threads[currentIndex]
            
            // Load children only if not already loaded
            if currentThread.childVideos.isEmpty {
                _ = try? await getThreadChildren(threadID: currentThread.id)
            }
            return
        }
        
        // Preload horizontal threads (children loaded on-demand)
        for index in preloadRange {
            _ = threads[index] // Mark thread for preloading (structure already in memory)
            
            // Don't automatically load children - wait for user to swipe vertically
            print("🎯 VIDEO SERVICE: Preloaded thread \(index) structure")
        }
        
        print("🎯 VIDEO SERVICE: Optimized preload for \(direction) navigation")
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
        
        print("✅ VIDEO SERVICE: Loaded \(videos.count) basic threads")
        
        return PaginatedResult(
            items: videos,
            lastDocument: snapshot.documents.last,
            hasMore: snapshot.documents.count >= limit
        )
    }
    
    /// Get video by ID
    func getVideo(id: String) async throws -> CoreVideoMetadata? {
        
        // Load from Firebase
        let doc = try await db.collection(FirebaseSchema.Collections.videos).document(id).getDocument()
        
        guard doc.exists, let video = try createVideoFromDocument(doc) else {
            return nil
        }
        
        return video
    }
    
    /// Get videos by creator ID
    func getVideosByCreator(creatorID: String, limit: Int = 20) async throws -> [CoreVideoMetadata] {
        
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: creatorID)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        
        let videos = try snapshot.documents.compactMap { doc in
            try createVideoFromDocument(doc)
        }
        
        print("✅ VIDEO SERVICE: Loaded \(videos.count) videos for creator \(creatorID)")
        return videos
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
        
        // Performance metrics (calculated, not stored in FirebaseSchema)
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

// MARK: - Array Extension for Chunking (Remove duplicate)

// This extension is already defined elsewhere, removing duplicate
// extension Array {
//     func chunked(into size: Int) -> [[Element]] {
//         return stride(from: 0, to: count, by: size).map {
//             Array(self[$0..<Swift.min($0 + size, count)])
//         }
//     }
// }

// MARK: - Hello World Test Extension

extension VideoService {
    
    /// Test video service functionality
    func helloWorldTest() {
        print("📹 VIDEO SERVICE: Enhanced Hello World - Ready for complete video management!")
        print("📹 VIDEO SERVICE: Features: Thread hierarchy, following feed, engagement updates, secure video deletion")
        print("📹 VIDEO SERVICE: Performance: Direct Firebase access with real-time engagement and storage cleanup")
    }
}
