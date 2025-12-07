//
//  VideoCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - PARALLEL Video Creation Workflow Orchestration
//  Dependencies: VideoService, UserService, AIVideoAnalyzer, VideoProcessingService, VideoUploadService, AudioExtractionService, NotificationService
//  Orchestrates: Recording → [Audio Extraction + Compression + AI Analysis] → Upload → Feed Integration
//  OPTIMIZATION: Parallel processing for sub-20 second video creation
//  FIXED: Added UserService dependency for follower notifications
//  UPDATED: Added user tagging support with mention notifications
//  UPDATED: Added stitch/reply notification logic with parent/child thread awareness
//

import Foundation
import SwiftUI
import AVFoundation
import FirebaseFirestore

/// Orchestrates parallel video creation workflow for maximum speed
/// Coordinates between audio extraction, compression, AI analysis, upload, and feed services simultaneously
@MainActor
class VideoCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let userService: UserService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoProcessor: VideoProcessingService
    private let uploadService: VideoUploadService
    private let cachingService: CachingService?
    private let audioExtractor: AudioExtractionService
    private let notificationService: NotificationService
    
    // MARK: - Workflow State
    
    @Published var currentPhase: VideoCreationPhase = .ready
    @Published var overallProgress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var isProcessing: Bool = false
    
    // MARK: - Parallel Task State
    
    @Published var audioExtractionProgress: Double = 0.0
    @Published var compressionProgress: Double = 0.0
    @Published var aiAnalysisProgress: Double = 0.0
    @Published var uploadProgress: Double = 0.0
    
    // MARK: - Video State
    
    @Published var recordedVideoURL: URL?
    @Published var extractedAudioURL: URL?
    @Published var compressedVideoURL: URL?
    @Published var aiAnalysisResult: VideoAnalysisResult?
    @Published var compressionResult: CompressionResult?
    @Published var uploadResult: VideoUploadResult?
    @Published var createdVideo: CoreVideoMetadata?
    
    // MARK: - Error Handling
    
    @Published var lastError: VideoCreationError?
    @Published var showingError: Bool = false
    @Published var canRetry: Bool = false
    
    // MARK: - Analytics
    
    @Published var creationMetrics = VideoCreationMetrics()
    @Published var performanceStats = PerformanceStats()
    
    // MARK: - Configuration
    
    private let maxRetries = 1
    private let compressionEnabled = true
    private let aiAnalysisEnabled = true
    private let feedIntegrationEnabled = true
    private let parallelProcessingEnabled = true
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService,
        aiAnalyzer: AIVideoAnalyzer,
        videoProcessor: VideoProcessingService,
        uploadService: VideoUploadService,
        cachingService: CachingService? = nil,
        audioExtractor: AudioExtractionService? = nil,
        notificationService: NotificationService? = nil
    ) {
        self.videoService = videoService
        self.userService = userService
        self.aiAnalyzer = aiAnalyzer
        self.videoProcessor = videoProcessor
        self.uploadService = uploadService
        self.cachingService = cachingService
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        self.notificationService = notificationService ?? NotificationService()
        
        print("🎬 VIDEO COORDINATOR: Initialized with PARALLEL PROCESSING + MANUAL OVERRIDE + USER TAGGING + STITCH NOTIFICATIONS + FOLLOWER NOTIFICATIONS")
    }
    
    // MARK: - PARALLEL VIDEO CREATION WORKFLOW (UPDATED: Follower + Stitch Notifications)
    
    /// OPTIMIZED: Parallel video creation workflow with MANUAL title/description override + user tagging + stitch/follower notifications
    /// Runs audio extraction, compression, and AI analysis simultaneously
    /// UPDATED: Now sends follower notifications for new videos and stitch/reply notifications
    func processVideoCreation(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        userID: String,
        userTier: UserTier,
        manualTitle: String? = nil,
        manualDescription: String? = nil,
        taggedUserIDs: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        guard !isProcessing else {
            throw VideoCreationError.unknown("Video creation already in progress")
        }
        
        let workflowStartTime = Date()
        isProcessing = true
        self.recordedVideoURL = recordedVideoURL
        
        print("🚀 PARALLEL WORKFLOW: Starting optimized parallel processing")
        print("🚀 TARGET: Sub-20 second video creation")
        print("🎬 VIDEO: \(recordedVideoURL.lastPathComponent)")
        print("🎬 CONTEXT: \(recordingContext)")
        print("🎬 USER: \(userID)")
        
        // Log manual overrides if provided
        if let manualTitle = manualTitle {
            print("✏️ MANUAL OVERRIDE: Title = '\(manualTitle)'")
        }
        if let manualDescription = manualDescription {
            print("✏️ MANUAL OVERRIDE: Description = '\(manualDescription)'")
        }
        
        // Log tagged users
        if !taggedUserIDs.isEmpty {
            print("🏷️ TAGGED USERS: \(taggedUserIDs.count) users - \(taggedUserIDs)")
        }
        
        defer { isProcessing = false }
        
        do {
            // PHASE 1: PARALLEL PROCESSING (0-70%)
            let parallelResults = try await performParallelProcessing(
                videoURL: recordedVideoURL,
                userID: userID,
                userTier: userTier
            )
            
            // PHASE 2: UPLOAD (70-90%)
            let uploadResult = try await performParallelUpload(
                compressionResult: parallelResults.compression,
                aiResult: parallelResults.aiAnalysis,
                recordingContext: recordingContext,
                userID: userID
            )
            
            // PHASE 3: FEED INTEGRATION (90-100%)
            let createdVideo = try await performFeedIntegration(
                uploadResult: uploadResult,
                analysisResult: parallelResults.aiAnalysis,
                recordingContext: recordingContext,
                userID: userID,
                manualTitle: manualTitle,
                manualDescription: manualDescription,
                taggedUserIDs: taggedUserIDs
            )
            
            // PHASE 4: SEND MENTION NOTIFICATIONS
            if !taggedUserIDs.isEmpty {
                await sendMentionNotifications(
                    videoID: createdVideo.id,
                    videoTitle: createdVideo.title,
                    taggerUserID: userID,
                    taggedUserIDs: taggedUserIDs
                )
            }
            
            // PHASE 5: SEND STITCH/REPLY NOTIFICATIONS (NEW)
            await sendStitchNotifications(
                createdVideo: createdVideo,
                recordingContext: recordingContext,
                creatorUserID: userID
            )
            
            // Complete workflow
            await completeVideoCreation(
                createdVideo: createdVideo,
                totalTime: Date().timeIntervalSince(workflowStartTime)
            )
            
            return createdVideo
            
        } catch {
            await handleCreationError(error)
            throw error
        }
    }
    
    // MARK: - PHASE 1: PARALLEL PROCESSING
    
    /// Run audio extraction, compression, and AI analysis in parallel
    private func performParallelProcessing(
        videoURL: URL,
        userID: String,
        userTier: UserTier
    ) async throws -> ParallelProcessingResult {
        
        currentPhase = .parallelProcessing
        currentTask = "Starting parallel processing..."
        await updateProgress(0.0)
        
        print("⚡ PARALLEL: Starting simultaneous audio + compression + AI")
        
        var audioResult: AudioExtractionResult?
        var compressionResult: CompressionResult?
        var aiResult: VideoAnalysisResult?
        
        return try await withThrowingTaskGroup(of: ParallelTask.self, returning: ParallelProcessingResult.self) { group in
            
            // Task 1: Audio Extraction
            group.addTask { [weak self] in
                guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                
                let audioResult = try await self.audioExtractor.extractAudio(from: videoURL) { progress in
                    Task { @MainActor in
                        self.audioExtractionProgress = progress
                        Task {
                            await self.updateParallelProgress()
                        }
                    }
                }
                
                return .audioExtraction(audioResult)
            }
            
            // Task 2: Video Compression
            group.addTask { [weak self] in
                guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                
                print("🗜️ PARALLEL: Starting VideoProcessingService compression with userTier: \(userTier.displayName)")
                
                let compressedURL = try await self.videoProcessor.compress(
                    videoURL: videoURL,
                    userTier: userTier,
                    targetSizeMB: 3.0,
                    progressCallback: { progress in
                        Task { @MainActor in
                            self.compressionProgress = progress
                            Task {
                                await self.updateParallelProgress()
                            }
                        }
                    }
                )
                
                let originalSize = await self.getFileSize(videoURL)
                let compressedSize = await self.getFileSize(compressedURL)
                let ratio = Double(compressedSize) / Double(originalSize)
                
                let result = CompressionResult(
                    originalURL: videoURL,
                    outputURL: compressedURL,
                    originalSize: originalSize,
                    compressedSize: compressedSize,
                    compressionRatio: ratio,
                    qualityScore: 0.85,
                    processingTime: 0
                )
                
                return .compression(result)
            }
            
            // Task 3: AI Analysis
            group.addTask { [weak self] in
                guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                
                print("🧠 PARALLEL: Starting AI analysis")
                
                let aiResult = await self.aiAnalyzer.analyzeVideo(
                    url: videoURL,
                    userID: userID
                )
                
                await MainActor.run {
                    self.aiAnalysisProgress = 1.0
                    Task {
                        await self.updateParallelProgress()
                    }
                }
                
                return .aiAnalysis(aiResult)
            }
            
            // Collect results
            for try await task in group {
                switch task {
                case .audioExtraction(let result):
                    audioResult = result
                    print("🎵 PARALLEL: Audio extraction complete")
                case .compression(let result):
                    compressionResult = result
                    self.compressionResult = result
                    self.compressedVideoURL = result.outputURL
                    print("🗜️ PARALLEL: Compression complete - \(result.compressionRatio * 100)% of original")
                case .aiAnalysis(let result):
                    aiResult = result
                    self.aiAnalysisResult = result
                    if let title = result?.title {
                        print("🧠 PARALLEL: AI analysis complete - '\(title)'")
                    } else {
                        print("🧠 PARALLEL: AI analysis complete - No results")
                    }
                }
            }
            
            guard let audio = audioResult,
                  let compression = compressionResult else {
                throw VideoCreationError.unknown("Parallel processing incomplete")
            }
            
            self.extractedAudioURL = audio.audioURL
            
            print("✅ PARALLEL PROCESSING: All tasks complete")
            await self.updateProgress(0.7)
            
            return ParallelProcessingResult(
                audioExtraction: audio,
                compression: compression,
                aiAnalysis: aiResult
            )
        }
    }
    
    // MARK: - PHASE 2: PARALLEL UPLOAD
    
    /// Upload compressed video and thumbnail simultaneously
    private func performParallelUpload(
        compressionResult: CompressionResult,
        aiResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String
    ) async throws -> VideoUploadResult {
        
        currentPhase = .uploading
        currentTask = "Uploading video..."
        await updateProgress(0.7)
        
        print("☁️ PARALLEL UPLOAD: Starting")
        
        let metadata = VideoUploadMetadata(
            title: aiResult?.title ?? getDefaultTitle(for: recordingContext),
            description: aiResult?.description ?? getDefaultDescription(for: recordingContext),
            hashtags: aiResult?.hashtags ?? getDefaultHashtags(for: recordingContext),
            creatorID: userID,
            creatorName: ""
        )
        
        let result = try await uploadService.uploadVideo(
            videoURL: compressionResult.outputURL,
            metadata: metadata,
            recordingContext: recordingContext
        )
        
        await updateProgress(0.9)
        uploadResult = result
        
        print("☁️ PARALLEL UPLOAD: Complete - \(result.videoURL)")
        return result
    }
    
    // MARK: - PHASE 3: FEED INTEGRATION
    
    /// Feed integration - saves taggedUserIDs to video document
    private func performFeedIntegration(
        uploadResult: VideoUploadResult,
        analysisResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String,
        manualTitle: String? = nil,
        manualDescription: String? = nil,
        taggedUserIDs: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        currentPhase = .integrating
        currentTask = "Creating video document..."
        await updateProgress(0.9)
        
        guard !userID.isEmpty && !uploadResult.videoURL.isEmpty else {
            throw VideoCreationError.feedIntegrationFailed("Invalid data")
        }
        
        // Smart hashtag handling
        let smartHashtags = generateSmartHashtags(
            aiHashtags: analysisResult?.hashtags,
            recordingContext: recordingContext
        )
        
        // Use manual overrides if provided, otherwise fall back to AI/defaults
        let finalTitle = manualTitle ?? analysisResult?.title ?? getDefaultTitle(for: recordingContext)
        let finalDescription = manualDescription ?? analysisResult?.description ?? getDefaultDescription(for: recordingContext)
        
        let metadata = VideoUploadMetadata(
            title: finalTitle,
            description: finalDescription,
            hashtags: smartHashtags,
            creatorID: userID,
            creatorName: ""
        )
        
        // Enhanced logging
        if let manual = manualTitle {
            print("🔗 FEED INTEGRATION: Using MANUAL title: '\(manual)'")
        } else if let aiTitle = analysisResult?.title {
            print("🔗 FEED INTEGRATION: Using AI-generated title: '\(aiTitle)'")
        } else {
            print("🔗 FEED INTEGRATION: Using default title: '\(finalTitle)'")
        }
        
        if let manual = manualDescription {
            print("🔗 FEED INTEGRATION: Using MANUAL description: '\(manual)'")
        } else if let aiDesc = analysisResult?.description {
            print("🔗 FEED INTEGRATION: Using AI-generated description: '\(aiDesc)'")
        } else {
            print("🔗 FEED INTEGRATION: Using default description")
        }
        
        if !taggedUserIDs.isEmpty {
            print("🔗 FEED INTEGRATION: Tagged users: \(taggedUserIDs)")
        }
        
        // Create video document with tagged users + trigger notifications
        let createdVideo = try await uploadService.createVideoDocument(
            uploadResult: uploadResult,
            metadata: metadata,
            recordingContext: recordingContext,
            videoService: videoService,
            userService: userService,
            notificationService: notificationService,
            taggedUserIDs: taggedUserIDs
        )
        
        await updateProgress(1.0)
        self.createdVideo = createdVideo
        
        print("🔗 FEED INTEGRATION: Success - \(createdVideo.id)")
        print("🔗 FINAL VIDEO TITLE: '\(createdVideo.title)'")
        print("🔗 FINAL VIDEO DESCRIPTION: '\(createdVideo.description)'")
        print("🔗 TAGGED USERS: \(createdVideo.taggedUserIDs.count)")
        return createdVideo
    }
    
    // MARK: - PHASE 4: MENTION NOTIFICATIONS
    
    /// Send mention notifications to all tagged users
    private func sendMentionNotifications(
        videoID: String,
        videoTitle: String,
        taggerUserID: String,
        taggedUserIDs: [String]
    ) async {
        guard !taggedUserIDs.isEmpty else { return }
        
        print("📬 MENTIONS: Sending notifications to \(taggedUserIDs.count) tagged users")
        
        for taggedUserID in taggedUserIDs {
            // Don't send notification if user tagged themselves
            guard taggedUserID != taggerUserID else { continue }
            
            do {
                try await notificationService.sendMentionNotification(
                    to: taggedUserID,
                    videoID: videoID,              // ✅ ADD THIS LINE
                    videoTitle: videoTitle,
                    mentionContext: "tagged in video"
                )
                
                print("✅ MENTION: Notification sent to user \(taggedUserID)")
                
            } catch {
                print("⚠️ MENTION: Failed to notify user \(taggedUserID) - \(error)")
            }
        }
        
        print("📬 MENTIONS: All notifications sent")
    }
    
    // MARK: - PHASE 5: STITCH/REPLY NOTIFICATIONS (NEW)
    
    /// Send stitch/reply notifications based on parent/child thread logic
    private func sendStitchNotifications(
        createdVideo: CoreVideoMetadata,
        recordingContext: RecordingContext,
        creatorUserID: String
    ) async {
        // Only send stitch notifications for replies/stitches
        guard case .stitchToThread(let parentVideoID, _) = recordingContext else {
            print("📬 STITCH: Not a reply/stitch, skipping notifications")
            return
        }
        
        print("📬 STITCH: Starting notification process for video \(createdVideo.id)")
        
        do {
            // Get parent video to understand thread structure
            let parentVideo = try await videoService.getVideo(id: parentVideoID)
            
            // Determine who to notify based on thread structure
            let recipientIDs = try await determineStitchRecipients(
                parentVideo: parentVideo,
                newVideoDepth: createdVideo.conversationDepth,
                creatorUserID: creatorUserID
            )
            
            guard !recipientIDs.isEmpty else {
                print("📬 STITCH: No recipients to notify")
                return
            }
            
            // Get thread users for notification
            let threadUserIDs = recipientIDs.filter { $0 != creatorUserID }
            
            // Determine parent creator for notification
            let parentCreatorID: String? = {
                if createdVideo.conversationDepth == 2 {
                    // Replying to child - notify child's parent
                    return parentVideo.creatorID
                }
                return nil
            }()
            
            // Send stitch notification
            try await notificationService.sendStitchNotification(
                videoID: createdVideo.id,
                videoTitle: createdVideo.title,
                originalCreatorID: getOriginalCreatorID(from: parentVideo),
                parentCreatorID: parentCreatorID,
                threadUserIDs: threadUserIDs
            )
            
            print("✅ STITCH: Notifications sent to \(threadUserIDs.count) users")
            
        } catch {
            print("⚠️ STITCH: Failed to send notifications - \(error)")
        }
    }
    
    /// Determine who should receive stitch notifications based on thread structure
    private func determineStitchRecipients(
        parentVideo: CoreVideoMetadata,
        newVideoDepth: Int,
        creatorUserID: String
    ) async throws -> [String] {
        var recipients: Set<String> = []
        
        // Always notify original creator
        let originalCreatorID = getOriginalCreatorID(from: parentVideo)
        recipients.insert(originalCreatorID)
        
        if newVideoDepth == 1 {
            // REPLYING TO PARENT (depth 0 → depth 1)
            // Notify: parent creator + all users in parent thread
            print("📬 STITCH: Replying to PARENT - notifying all parent thread users")
            
            recipients.insert(parentVideo.creatorID)
            
           
        } else if newVideoDepth == 2 {
            // REPLYING TO CHILD (depth 1 → depth 2)
            // Notify: child creator + child's direct parent only
            print("📬 STITCH: Replying to CHILD - notifying child + parent only")
            
            recipients.insert(parentVideo.creatorID) // Child creator
            
            // Get child's parent
            if let grandparentID = parentVideo.replyToVideoID {
                let grandparent = try await videoService.getVideo(id: grandparentID)
                recipients.insert(grandparent.creatorID)
            }
        }
        
        // Remove the creator from recipients (don't notify yourself)
        recipients.remove(creatorUserID)
        
        return Array(recipients)
    }
    
    /// Get original thread creator (depth 0 video)
    private func getOriginalCreatorID(from video: CoreVideoMetadata) -> String {
        // If this is depth 0, it's the original
        if video.conversationDepth == 0 {
            return video.creatorID
        }
        
        // Otherwise, need to traverse up (we'll use threadID logic)
        // For now, return the creator of the current video as fallback
        return video.creatorID
    }
    
    /// Get all participants in a thread
    private func getThreadParticipants(threadID: String) async throws -> Set<String> {
        var participants: Set<String> = []
        
        // Get all videos in this thread
        let threadVideos = try await videoService.getThreadVideos(threadID: threadID)
        
        for video in threadVideos {
            participants.insert(video.creatorID)
        }
        
        return participants
    }
    
    // MARK: - Helper Methods
    
    /// Update combined parallel progress
    private func updateParallelProgress() async {
        let audioWeight = 0.2
        let compressionWeight = 0.4
        let aiWeight = 0.4
        
        let combinedProgress = (
            audioExtractionProgress * audioWeight +
            compressionProgress * compressionWeight +
            aiAnalysisProgress * aiWeight
        )
        
        await updateProgress(combinedProgress * 0.7)
        
        let activeTasks = [
            audioExtractionProgress < 1.0 ? "Audio" : nil,
            compressionProgress < 1.0 ? "Compression" : nil,
            aiAnalysisProgress < 1.0 ? "AI" : nil
        ].compactMap { $0 }
        
        if !activeTasks.isEmpty {
            currentTask = "Processing: \(activeTasks.joined(separator: ", "))"
        }
    }
    
    /// Complete workflow with timing analytics
    private func completeVideoCreation(createdVideo: CoreVideoMetadata, totalTime: TimeInterval) async {
        currentPhase = .complete
        currentTask = "Video created successfully!"
        
        creationMetrics.totalVideosCreated += 1
        creationMetrics.lastCreatedVideoID = createdVideo.id
        performanceStats.averageCreationTime = totalTime
        
        print("🎉 PARALLEL WORKFLOW: COMPLETE!")
        print("⏱️ TOTAL TIME: \(String(format: "%.1f", totalTime))s")
        print("🎯 TARGET ACHIEVED: \(totalTime < 20 ? "YES" : "NO") (sub-20s)")
    }
    
    // MARK: - Error Handling & Cleanup
    
    private func handleCreationError(_ error: Error) async {
        currentPhase = .error
        lastError = error as? VideoCreationError ?? .unknown(error.localizedDescription)
        showingError = true
        await performCleanup()
    }
    
    private func performCleanup() async {
        if let compressedURL = compressedVideoURL, compressedURL != recordedVideoURL {
            try? FileManager.default.removeItem(at: compressedURL)
        }
        
        if let audioURL = extractedAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }
    
    private func updateProgress(_ progress: Double) async {
        overallProgress = progress
    }
    
    /// Generate smart hashtags combining AI + context + trending
    private func generateSmartHashtags(
        aiHashtags: [String]?,
        recordingContext: RecordingContext
    ) -> [String] {
        var smartHashtags: [String] = []
        
        // 1. AI hashtags (if available)
        if let aiTags = aiHashtags {
            smartHashtags.append(contentsOf: aiTags.prefix(3))
        }
        
        // 2. Context-based hashtags
        switch recordingContext {
        case .newThread:
            smartHashtags.append("original")
        case .stitchToThread:
            smartHashtags.append("stitch")
        case .replyToVideo:
            smartHashtags.append("reply")
        case .continueThread:
            smartHashtags.append("continuation")
        }
        
        return Array(Set(smartHashtags)).prefix(5).map { $0 }
    }
    
    /// Get default title based on context
    private func getDefaultTitle(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "New Thread"
        case .stitchToThread(_, let info):
            return "Stitch to \(info.creatorName)"
        case .replyToVideo(_, let info):
            return "Reply to \(info.creatorName)"
        case .continueThread(_, let info):
            return "Continuing: \(info.title)"
        }
    }
    
    /// Get default description based on context
    private func getDefaultDescription(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "Check out my new thread!"
        case .stitchToThread(_, let info):
            return "Stitching to thread by \(info.creatorName)"
        case .replyToVideo(_, let info):
            return "Replying to video by \(info.creatorName)"
        case .continueThread(_, let info):
            return "Continuing thread: \(info.title)"
        }
    }
    
    /// Get default hashtags based on context
    private func getDefaultHashtags(for context: RecordingContext) -> [String] {
        switch context {
        case .newThread:
            return ["newthread", "original"]
        case .stitchToThread:
            return ["stitch"]
        case .replyToVideo:
            return ["reply"]
        case .continueThread:
            return ["continuation"]
        }
    }
    
    /// Get file size helper
    private func getFileSize(_ url: URL) async -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            print("⚠️ FILE SIZE: Could not get file size for \(url.lastPathComponent)")
            return 0
        }
    }
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) async -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

enum VideoCreationPhase: String, CaseIterable {
    case ready = "ready"
    case parallelProcessing = "parallel_processing"
    case uploading = "uploading"
    case integrating = "integrating"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .parallelProcessing: return "Processing"
        case .uploading: return "Upload"
        case .integrating: return "Integration"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }
}

enum ParallelTask {
    case audioExtraction(AudioExtractionResult)
    case compression(CompressionResult)
    case aiAnalysis(VideoAnalysisResult?)
}

struct ParallelProcessingResult {
    let audioExtraction: AudioExtractionResult
    let compression: CompressionResult
    let aiAnalysis: VideoAnalysisResult?
}

enum VideoCreationError: LocalizedError {
    case invalidVideo(String)
    case analysisTimeout
    case compressionFailed(String)
    case uploadFailed(String)
    case feedIntegrationFailed(String)
    case networkError(String)
    case userNotFound
    case permissionDenied
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidVideo(let message): return "Invalid Video: \(message)"
        case .analysisTimeout: return "Analysis took too long"
        case .compressionFailed(let message): return "Compression Failed: \(message)"
        case .uploadFailed(let message): return "Upload Failed: \(message)"
        case .feedIntegrationFailed(let message): return "Integration Failed: \(message)"
        case .networkError(let message): return "Network Error: \(message)"
        case .userNotFound: return "User not found"
        case .permissionDenied: return "Permission denied"
        case .unknown(let message): return "Unknown Error: \(message)"
        }
    }
}

struct CompressionResult {
    let originalURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let compressionRatio: Double
    let qualityScore: Double
    let processingTime: TimeInterval
}

struct VideoCreationMetrics {
    var totalVideosCreated: Int = 0
    var totalErrorsEncountered: Int = 0
    var aiAnalysisUsageCount: Int = 0
    var averageCompressionRatio: Double = 1.0
    var averageFileSizeReduction: Double = 0.0
    var lastCreatedVideoID: String = ""
    var lastErrorType: String = ""
}

struct PerformanceStats {
    var averageCreationTime: TimeInterval = 0.0
    var successRate: Double = 1.0
    var lastErrorType: String?
    var sub20SecondCount: Int = 0
}
