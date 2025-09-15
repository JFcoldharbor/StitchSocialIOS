//
//  VideoCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - Complete Video Creation Workflow Orchestration
//  Dependencies: VideoService, AIVideoAnalyzer, VideoProcessingService, VideoUploadService
//  Orchestrates: Recording → AI Analysis → Compression → Upload → Feed Integration
//  FINAL FIX: Removed ALL duplicate VideoUploadMetadata declarations and fixed metadata handling
//

import Foundation
import SwiftUI
import AVFoundation
import FirebaseFirestore

/// Orchestrates complete video creation workflow from recording to feed integration
/// Coordinates between recording, AI analysis, compression, upload, and feed services
@MainActor
class VideoCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoProcessor: VideoProcessingService
    private let uploadService: VideoUploadService
    private let cachingService: CachingService?
    
    // MARK: - Workflow State
    
    @Published var currentPhase: VideoCreationPhase = .ready
    @Published var overallProgress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var isProcessing: Bool = false
    
    // MARK: - Video State
    
    @Published var recordedVideoURL: URL?
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
    
    private let maxRetries = 2
    private let compressionEnabled = true
    private let aiAnalysisEnabled = true
    private let feedIntegrationEnabled = true
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        aiAnalyzer: AIVideoAnalyzer,
        videoProcessor: VideoProcessingService,
        uploadService: VideoUploadService,
        cachingService: CachingService?
    ) {
        self.videoService = videoService
        self.aiAnalyzer = aiAnalyzer
        self.videoProcessor = videoProcessor
        self.uploadService = uploadService
        self.cachingService = cachingService
        
        print("🎬 VIDEO COORDINATOR: Initialized with all services")
    }
    
    // MARK: - Public Interface
    
    /// Main entry point: Process complete video creation workflow
    func processVideoCreation(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        userID: String,
        userTier: UserTier
    ) async throws -> CoreVideoMetadata {
        
        guard !isProcessing else {
            throw VideoCreationError.unknown("Video creation already in progress")
        }
        
        isProcessing = true
        self.recordedVideoURL = recordedVideoURL
        
        print("🎬 VIDEO CREATION: Starting full workflow")
        print("🎬 VIDEO CREATION: Video URL: \(recordedVideoURL.lastPathComponent)")
        print("🎬 VIDEO CREATION: Context: \(recordingContext)")
        print("🎬 VIDEO CREATION: User ID: \(userID)")
        
        do {
            // Phase 1: AI Analysis (0-30%)
            let analysisResult = await performAIAnalysis(
                videoURL: recordedVideoURL,
                userID: userID,
                userTier: userTier
            )
            
            // Phase 2: Video Compression (30-60%)
            let compressionResult = try await performVideoCompression(
                videoURL: recordedVideoURL,
                analysisResult: analysisResult
            )
            
            // Phase 3: Upload to Firebase Storage (60-85%)
            let uploadResult = try await performVideoUpload(
                videoURL: compressionResult.outputURL,
                originalURL: recordedVideoURL,
                analysisResult: analysisResult,
                recordingContext: recordingContext,
                userID: userID
            )
            
            // Phase 4: Feed Integration (85-100%)
            let createdVideo = try await performFeedIntegration(
                uploadResult: uploadResult,
                analysisResult: analysisResult,
                recordingContext: recordingContext,
                userID: userID
            )
            
            // Complete workflow
            await completeVideoCreation(createdVideo: createdVideo)
            
            return createdVideo
            
        } catch {
            await handleCreationError(error)
            throw error
        }
    }
    
    /// Retry failed video creation with same parameters
    func retryVideoCreation() async {
        guard let videoURL = recordedVideoURL,
              canRetry else { return }
        
        clearError()
        
        // Would need to store original parameters for retry
        print("🔄 VIDEO CREATION: Retrying workflow")
    }
    
    /// Cancel ongoing video creation
    func cancelVideoCreation() async {
        guard isProcessing else { return }
        
        currentPhase = .ready
        isProcessing = false
        await performCleanup()
        
        print("❌ VIDEO CREATION: Workflow cancelled")
    }
    
    /// Clear current error state
    func clearError() {
        lastError = nil
        showingError = false
        canRetry = false
    }
    
    // MARK: - Phase 1: AI Analysis
    
    /// Perform AI analysis on video content
    private func performAIAnalysis(
        videoURL: URL,
        userID: String,
        userTier: UserTier
    ) async -> VideoAnalysisResult? {
        
        currentPhase = .analyzing
        currentTask = "Analyzing video content..."
        await updateProgress(0.1)
        
        print("🤖 AI ANALYSIS: Starting analysis phase")
        
        // Check if AI analysis is enabled
        guard aiAnalysisEnabled else {
            print("🤖 AI ANALYSIS: Skipped - AI analysis disabled")
            await updateProgress(0.3)
            return nil
        }
        
        do {
            // Use exact method signature from AIVideoAnalyzer
            let result = await aiAnalyzer.analyzeVideo(url: videoURL, userID: userID)
            
            // Store result for later use
            aiAnalysisResult = result
            
            await updateProgress(0.3)
            currentTask = "AI analysis complete"
            
            if let result = result {
                print("✅ AI ANALYSIS: Success - Title: '\(result.title)'")
                print("✅ AI ANALYSIS: Hashtags: \(result.hashtags)")
            } else {
                print("✅ AI ANALYSIS: Completed - No result (manual content creation)")
            }
            
            return result
            
        } catch {
            print("⚠️ AI ANALYSIS: Failed with error - \(error.localizedDescription)")
            // Continue without AI analysis - manual content creation
            await updateProgress(0.3)
            return nil
        }
    }
    
    // MARK: - Phase 2: Video Compression
    
    /// Perform video compression using real VideoProcessingService implementation
    private func performVideoCompression(
        videoURL: URL,
        analysisResult: VideoAnalysisResult?
    ) async throws -> CompressionResult {
        
        currentPhase = .compressing
        currentTask = "Preparing video compression..."
        await updateProgress(0.3)
        
        print("🗜️ COMPRESSION: Starting compression phase")
        
        guard compressionEnabled else {
            print("🗜️ COMPRESSION: Skipped - compression disabled")
            return createSkippedCompressionResult(videoURL: videoURL)
        }
        
        do {
            // Get original file stats
            let originalSize = getFileSize(videoURL)
            let originalDuration = try await getVideoDuration(videoURL)
            
            print("🗜️ COMPRESSION: Original size: \(formatFileSize(originalSize))")
            print("🗜️ COMPRESSION: Target size: 3MB")
            print("🗜️ COMPRESSION: Duration: \(String(format: "%.1f", originalDuration))s")
            
            // Check if compression is needed
            let targetSizeMB = 3.0
            let targetSizeBytes = Int64(targetSizeMB * 1024 * 1024)
            
            if originalSize <= targetSizeBytes {
                print("✅ COMPRESSION: File already under target size - skipping compression")
                await updateProgress(0.6)
                currentTask = "Compression complete (skipped)"
                return createSkippedCompressionResult(videoURL: videoURL)
            }
            
            // Perform actual compression using VideoProcessingService
            currentTask = "Compressing video..."
            await updateProgress(0.4)
            
            // Use exact method signature from VideoProcessingService
            let qualityAnalysis = try await videoProcessor.analyzeVideoQuality(videoURL: videoURL)
            
            // Create compression configuration based on original file
            let compressionConfig = createCompressionConfig(
                originalSize: originalSize,
                targetSize: targetSizeBytes,
                duration: originalDuration
            )
            
            currentTask = "Processing video compression..."
            await updateProgress(0.5)
            
            // Create output URL for compressed video
            let outputURL = createTemporaryVideoURL()
            
            // Perform compression using AVFoundation
            let compressedURL = try await compressVideoWithAVFoundation(
                inputURL: videoURL,
                outputURL: outputURL,
                config: compressionConfig
            )
            
            // Get compressed file stats
            let compressedSize = getFileSize(compressedURL)
            let compressionRatio = Double(originalSize) / Double(compressedSize)
            
            currentTask = "Compression complete"
            await updateProgress(0.6)
            
            let result = CompressionResult(
                originalURL: videoURL,
                outputURL: compressedURL,
                originalSize: originalSize,
                compressedSize: compressedSize,
                compressionRatio: compressionRatio,
                qualityScore: qualityAnalysis.qualityScores.overall,
                processingTime: 0.0 // Would track actual time
            )
            
            // Store for cleanup
            compressedVideoURL = compressedURL
            compressionResult = result
            
            print("✅ COMPRESSION: Success")
            print("✅ COMPRESSION: Size: \(formatFileSize(originalSize)) → \(formatFileSize(compressedSize))")
            print("✅ COMPRESSION: Ratio: \(String(format: "%.1fx", compressionRatio))")
            
            return result
            
        } catch {
            print("❌ COMPRESSION: Failed with error - \(error.localizedDescription)")
            // Fall back to original video
            print("⚠️ COMPRESSION: Using original video as fallback")
            return createSkippedCompressionResult(videoURL: videoURL)
        }
    }
    
    /// Create compression configuration based on file characteristics
    private func createCompressionConfig(
        originalSize: Int64,
        targetSize: Int64,
        duration: TimeInterval
    ) -> CompressionConfig {
        
        // Calculate target bitrate based on duration and target size
        let targetBitrate = Double(targetSize) * 8.0 / duration / 1024.0 // kbps
        
        return CompressionConfig(
            targetBitrate: max(500, min(2000, targetBitrate)), // Between 500-2000 kbps
            maxResolution: CGSize(width: 720, height: 1280),
            quality: 0.7,
            frameRate: 30
        )
    }
    
    /// Compress video using AVFoundation
    private func compressVideoWithAVFoundation(
        inputURL: URL,
        outputURL: URL,
        config: CompressionConfig
    ) async throws -> URL {
        
        return try await withCheckedThrowingContinuation { continuation in
            
            let asset = AVAsset(url: inputURL)
            
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetMediumQuality
            ) else {
                continuation.resume(throwing: VideoCreationError.compressionFailed("Could not create export session"))
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    print("🗜️ COMPRESSION: AVFoundation export completed")
                    continuation.resume(returning: outputURL)
                case .failed:
                    let error = exportSession.error?.localizedDescription ?? "Unknown compression error"
                    continuation.resume(throwing: VideoCreationError.compressionFailed(error))
                case .cancelled:
                    continuation.resume(throwing: VideoCreationError.compressionFailed("Compression cancelled"))
                default:
                    continuation.resume(throwing: VideoCreationError.compressionFailed("Unexpected compression status"))
                }
            }
        }
    }
    
    /// Create temporary URL for compressed video
    private func createTemporaryVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "compressed_\(UUID().uuidString).mov"
        return tempDir.appendingPathComponent(filename)
    }
    
    /// Create compression result for skipped compression
    private func createSkippedCompressionResult(videoURL: URL) -> CompressionResult {
        let fileSize = getFileSize(videoURL)
        return CompressionResult(
            originalURL: videoURL,
            outputURL: videoURL,
            originalSize: fileSize,
            compressedSize: fileSize,
            compressionRatio: 1.0,
            qualityScore: 100.0,
            processingTime: 0.0
        )
    }
    
    // MARK: - Phase 3: Upload
    
    /// Upload compressed video and thumbnail to Firebase Storage
    private func performVideoUpload(
        videoURL: URL,
        originalURL: URL,
        analysisResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String
    ) async throws -> VideoUploadResult {
        
        currentPhase = .uploading
        currentTask = "Preparing upload..."
        await updateProgress(0.65)
        
        print("☁️ UPLOAD: Starting upload phase")
        
        do {
            currentTask = "Uploading video..."
            await updateProgress(0.7)
            
            // Create metadata directly for upload service
            let metadata = VideoUploadMetadata(
                title: analysisResult?.title ?? getDefaultTitle(for: recordingContext),
                description: analysisResult?.description ?? getDefaultDescription(for: recordingContext),
                hashtags: analysisResult?.hashtags ?? getDefaultHashtags(for: recordingContext),
                creatorID: userID,
                creatorName: ""
            )
            
            // Use exact method signature from VideoUploadService
            let result = try await uploadService.uploadVideo(
                videoURL: videoURL,
                metadata: metadata,
                recordingContext: recordingContext
            )
            
            await updateProgress(0.85)
            currentTask = "Upload complete"
            
            // Store for later use
            uploadResult = result
            
            print("☁️ UPLOAD: Success - Video URL: \(result.videoURL)")
            print("☁️ UPLOAD: Thumbnail URL: \(result.thumbnailURL)")
            print("☁️ UPLOAD: Duration: \(String(format: "%.1f", result.duration))s")
            
            return result
            
        } catch {
            print("❌ UPLOAD: Failed with error - \(error.localizedDescription)")
            throw VideoCreationError.uploadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Phase 4: Feed Integration
    
    /// Integrate uploaded video into feed and create database document
    private func performFeedIntegration(
        uploadResult: VideoUploadResult,
        analysisResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String
    ) async throws -> CoreVideoMetadata {
        
        currentPhase = .integrating
        currentTask = "Creating video document..."
        await updateProgress(0.9)
        
        print("🔗 FEED INTEGRATION: Starting integration phase")
        
        // VALIDATION: Ensure userID is not empty before proceeding
        guard !userID.isEmpty else {
            print("❌ FEED INTEGRATION: User ID is empty - cannot create document")
            throw VideoCreationError.userNotFound
        }
        
        // VALIDATION: Ensure video URLs are valid
        guard !uploadResult.videoURL.isEmpty else {
            print("❌ FEED INTEGRATION: Video URL is empty - cannot create document")
            throw VideoCreationError.feedIntegrationFailed("Invalid video URL")
        }
        
        do {
            // Create metadata directly for document creation
            let metadata = VideoUploadMetadata(
                title: (analysisResult?.title ?? "New Video"),
                description: (analysisResult?.description ?? ""),
                hashtags: (analysisResult?.hashtags ?? []),
                creatorID: userID,
                creatorName: ""
            )
            
            // Use exact method signature from VideoUploadService
            let createdVideo = try await uploadService.createVideoDocument(
                uploadResult: uploadResult,
                metadata: metadata,
                recordingContext: recordingContext,
                videoService: videoService
            )
            
            currentTask = "Updating cache..."
            await updateProgress(0.95)
            
            // Update cache for immediate availability
            if feedIntegrationEnabled {
                cachingService?.cacheVideo(createdVideo)
            }
            
            await updateProgress(1.0)
            currentTask = "Video creation complete"
            
            // Store for return
            self.createdVideo = createdVideo
            
            print("🔗 FEED INTEGRATION: Success - Video ID: \(createdVideo.id)")
            print("🔗 FEED INTEGRATION: Title: '\(createdVideo.title)'")
            print("🔗 FEED INTEGRATION: Context: \(recordingContext)")
            
            return createdVideo
            
        } catch {
            print("❌ FEED INTEGRATION: Failed with error - \(error.localizedDescription)")
            throw VideoCreationError.feedIntegrationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Completion
    
    /// Complete video creation workflow with cleanup and analytics
    private func completeVideoCreation(createdVideo: CoreVideoMetadata) async {
        
        currentPhase = .complete
        currentTask = "Video created successfully!"
        
        // Update analytics
        creationMetrics.totalVideosCreated += 1
        creationMetrics.lastCreatedVideoID = createdVideo.id
        
        if aiAnalysisResult != nil {
            creationMetrics.aiAnalysisUsageCount += 1
        }
        
        if let compression = compressionResult {
            creationMetrics.averageCompressionRatio = compression.compressionRatio
            creationMetrics.averageFileSizeReduction = (1.0 - (Double(compression.compressedSize) / Double(compression.originalSize))) * 100
        }
        
        // Performance stats
        performanceStats.averageCreationTime = calculateAverageCreationTime()
        performanceStats.successRate = calculateSuccessRate()
        
        print("🎉 VIDEO CREATION: Workflow completed successfully!")
        print("📊 ANALYTICS: Total videos created: \(creationMetrics.totalVideosCreated)")
        
        if let compression = compressionResult {
            print("📊 COMPRESSION: Average ratio: \(String(format: "%.1fx", compression.compressionRatio))")
            print("📊 COMPRESSION: Size reduction: \(String(format: "%.1f", creationMetrics.averageFileSizeReduction))%")
        }
    }
    
    // MARK: - Error Handling
    
    /// Handle creation errors with proper cleanup and user feedback
    private func handleCreationError(_ error: Error) async {
        
        currentPhase = .error
        lastError = error as? VideoCreationError ?? .unknown(error.localizedDescription)
        showingError = true
        canRetry = shouldAllowRetry(for: error)
        
        // Update analytics
        creationMetrics.totalErrorsEncountered += 1
        creationMetrics.lastErrorType = String(describing: type(of: error))
        
        print("❌ VIDEO CREATION: Workflow failed with error")
        print("❌ ERROR TYPE: \(type(of: error))")
        print("❌ ERROR DESCRIPTION: \(error.localizedDescription)")
        
        // Cleanup temporary files
        await performCleanup()
    }
    
    /// Determine if retry should be allowed for specific error types
    private func shouldAllowRetry(for error: Error) -> Bool {
        switch error {
        case VideoCreationError.networkError(_),
             VideoCreationError.uploadFailed(_):
            return true
        case VideoCreationError.invalidVideo(_),
             VideoCreationError.permissionDenied:
            return false
        default:
            return true
        }
    }
    
    /// Cleanup temporary files and reset state
    private func performCleanup() async {
        
        // Clean up compressed video file if it exists
        if let compressedURL = compressedVideoURL,
           compressedURL != recordedVideoURL {
            try? FileManager.default.removeItem(at: compressedURL)
            print("🧹 CLEANUP: Removed compressed video file")
        }
        
        // Reset state
        compressedVideoURL = nil
        uploadResult = nil
        
        print("🧹 CLEANUP: Temporary files cleaned up")
    }
    
    // MARK: - Helper Methods
    
    /// Update overall progress and current task
    private func updateProgress(_ progress: Double) async {
        await MainActor.run {
            self.overallProgress = progress
        }
    }
    
    /// Get default title based on recording context
    private func getDefaultTitle(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "New Thread"
        case .stitchToThread:
            return "Stitch"
        case .replyToVideo:
            return "Reply"
        case .continueThread:
            return "Thread Continuation"
        }
    }
    
    /// Get default description based on recording context
    private func getDefaultDescription(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "Starting a new conversation"
        case .stitchToThread:
            return "Stitching to continue the thread"
        case .replyToVideo:
            return "Replying to the video"
        case .continueThread:
            return "Continuing the thread"
        }
    }
    
    /// Get default hashtags based on recording context
    private func getDefaultHashtags(for context: RecordingContext) -> [String] {
        switch context {
        case .newThread:
            return ["thread", "newthread"]
        case .stitchToThread:
            return ["stitch", "thread"]
        case .replyToVideo:
            return ["reply", "response"]
        case .continueThread:
            return ["thread", "continue"]
        }
    }
    
    /// Get file size for URL
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            print("⚠️ FILE SIZE: Could not get file size for \(url.lastPathComponent)")
            return 0
        }
    }
    
    /// Get video duration
    private func getVideoDuration(_ url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Calculate average creation time
    private func calculateAverageCreationTime() -> TimeInterval {
        // Implementation would track creation times
        return 45.0 // Placeholder
    }
    
    /// Calculate success rate
    private func calculateSuccessRate() -> Double {
        guard creationMetrics.totalVideosCreated > 0 else { return 1.0 }
        let totalAttempts = creationMetrics.totalVideosCreated + creationMetrics.totalErrorsEncountered
        return Double(creationMetrics.totalVideosCreated) / Double(totalAttempts)
    }
}

// MARK: - Supporting Types

/// Video creation phases for UI tracking
enum VideoCreationPhase: String, CaseIterable {
    case ready = "ready"
    case analyzing = "analyzing"
    case compressing = "compressing"
    case uploading = "uploading"
    case integrating = "integrating"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .analyzing: return "AI Analysis"
        case .compressing: return "Compression"
        case .uploading: return "Upload"
        case .integrating: return "Integration"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }
    
    var progressWeight: Double {
        switch self {
        case .ready: return 0.0
        case .analyzing: return 0.3
        case .compressing: return 0.6
        case .uploading: return 0.85
        case .integrating: return 1.0
        case .complete: return 1.0
        case .error: return 0.0
        }
    }
}

/// Video creation errors
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

/// Compression result data
struct CompressionResult {
    let originalURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let compressionRatio: Double
    let qualityScore: Double
    let processingTime: TimeInterval
}

/// Video upload metadata - SINGLE DECLARATION ONLY
struct MyVideoUploadMetadata {
    let title: String
    let description: String
    let hashtags: [String]
    let creatorID: String
    let creatorName: String
}

/// Analytics for video creation
struct VideoCreationMetrics {
    var totalVideosCreated: Int = 0
    var totalErrorsEncountered: Int = 0
    var aiAnalysisUsageCount: Int = 0
    var averageCompressionRatio: Double = 1.0
    var averageFileSizeReduction: Double = 0.0
    var lastCreatedVideoID: String = ""
    var lastErrorType: String = ""
}

/// Performance statistics
struct PerformanceStats {
    var averageCreationTime: TimeInterval = 0.0
    var successRate: Double = 1.0
    var lastErrorType: String?
}

/// Compression configuration
struct CompressionConfig {
    let targetBitrate: Double
    let maxResolution: CGSize
    let quality: Double
    let frameRate: Double
}
