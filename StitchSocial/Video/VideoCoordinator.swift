//
//  VideoCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - PARALLEL Video Creation Workflow Orchestration
//  Dependencies: VideoService, AIVideoAnalyzer, VideoProcessingService, VideoUploadService, AudioExtractionService
//  Orchestrates: Recording → [Audio Extraction + Compression + AI Analysis] → Upload → Feed Integration
//  OPTIMIZATION: Parallel processing for sub-20 second video creation
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
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoProcessor: VideoProcessingService
    private let uploadService: VideoUploadService
    private let cachingService: CachingService?
    private let audioExtractor: AudioExtractionService // NEW
    
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
    
    private let maxRetries = 1 // Reduced for speed
    private let compressionEnabled = true
    private let aiAnalysisEnabled = true
    private let feedIntegrationEnabled = true
    private let parallelProcessingEnabled = true
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        aiAnalyzer: AIVideoAnalyzer,
        videoProcessor: VideoProcessingService,
        uploadService: VideoUploadService,
        cachingService: CachingService? = nil,
        audioExtractor: AudioExtractionService? = nil
    ) {
        self.videoService = videoService
        self.aiAnalyzer = aiAnalyzer
        self.videoProcessor = videoProcessor
        self.uploadService = uploadService
        self.cachingService = cachingService
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        
        print("🎬 VIDEO COORDINATOR: Initialized with PARALLEL PROCESSING")
    }
    
    // MARK: - PARALLEL VIDEO CREATION WORKFLOW
    
    /// OPTIMIZED: Parallel video creation workflow for sub-20 second processing
    /// Runs audio extraction, compression, and AI analysis simultaneously
    func processVideoCreation(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        userID: String,
        userTier: UserTier
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
                userID: userID
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
    
    // MARK: - PHASE 1: PARALLEL PROCESSING (FIXED RACE CONDITIONS)
    
    /// Run audio extraction, compression, and AI analysis in parallel
    /// FIXED: Proper task collection without ordering assumptions
    private func performParallelProcessing(
        videoURL: URL,
        userID: String,
        userTier: UserTier
    ) async throws -> ParallelProcessingResult {
        
        currentPhase = .parallelProcessing
        currentTask = "Starting parallel processing..."
        await updateProgress(0.0)
        
        print("⚡ PARALLEL: Starting simultaneous audio + compression + AI")
        
        // FIXED: Use dictionary to collect results without ordering assumptions
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
                        await self.updateParallelProgress()
                    }
                }
                
                return .audioExtraction(audioResult)
            }
            
            // Task 2: Video Compression
            group.addTask { [weak self] in
                guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                
                let compressionResult = try await self.performFastCompression(videoURL: videoURL) { progress in
                    Task { @MainActor in
                        self.compressionProgress = progress
                        await self.updateParallelProgress()
                    }
                }
                
                return .compression(compressionResult)
            }
            
            // FIXED: Collect tasks in any order without assumptions
            for try await task in group {
                switch task {
                case .audioExtraction(let result):
                    audioResult = result
                    extractedAudioURL = result.audioURL
                    print("✅ PARALLEL: Audio extraction completed in \(String(format: "%.1f", result.extractionTime))s")
                    
                    // Start AI analysis after audio is ready (but don't block other tasks)
                    if aiResult == nil { // Only start once
                        group.addTask { [weak self] in
                            guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                            
                            let aiResult = await self.performFastAIAnalysis(
                                audioResult: result,
                                userID: userID,
                                userTier: userTier
                            ) { progress in
                                Task { @MainActor in
                                    self.aiAnalysisProgress = progress
                                    await self.updateParallelProgress()
                                }
                            }
                            
                            return .aiAnalysis(aiResult)
                        }
                    }
                    
                case .compression(let result):
                    compressionResult = result
                    compressedVideoURL = result.outputURL
                    print("✅ PARALLEL: Compression completed - \(String(format: "%.1fx", result.compressionRatio)) reduction")
                    
                case .aiAnalysis(let result):
                    aiResult = result
                    aiAnalysisResult = result
                    print("✅ PARALLEL: AI analysis completed")
                }
                
                // Check if we have the minimum required results to proceed
                if let audio = audioResult, let compression = compressionResult {
                    // We have essential results, can proceed even if AI is still running
                    await updateProgress(0.7)
                    currentTask = "Parallel processing complete"
                    
                    // Cancel any remaining tasks and return results
                    group.cancelAll()
                    
                    return ParallelProcessingResult(
                        audioExtraction: audio,
                        compression: compression,
                        aiAnalysis: aiResult // May be nil if still running
                    )
                }
            }
            
            // This should not be reached, but handle the case
            throw VideoCreationError.unknown("Parallel processing incomplete")
        }
    }
    
    // MARK: - FAST COMPRESSION
    
    /// Fast compression optimized for parallel processing
    private func performFastCompression(
        videoURL: URL,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> CompressionResult {
        
        print("🗜️ FAST COMPRESSION: Starting parallel compression")
        
        let originalSize = getFileSize(videoURL)
        let targetSizeMB = 3.0
        let targetSizeBytes = Int64(targetSizeMB * 1024 * 1024)
        
        // Quick size check
        if originalSize <= targetSizeBytes {
            progressCallback(1.0)
            return createSkippedCompressionResult(videoURL: videoURL)
        }
        
        // Fast compression using preset
        let outputURL = createTemporaryVideoURL()
        
        let compressedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let asset = AVAsset(url: videoURL)
            
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetMediumQuality // Balance of speed and quality
            ) else {
                continuation.resume(throwing: VideoCreationError.compressionFailed("Export session failed"))
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            
            // Progress tracking
            let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                progressCallback(Double(exportSession.progress))
            }
            
            exportSession.exportAsynchronously {
                timer.invalidate()
                
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    let error = exportSession.error?.localizedDescription ?? "Unknown error"
                    continuation.resume(throwing: VideoCreationError.compressionFailed(error))
                case .cancelled:
                    continuation.resume(throwing: VideoCreationError.compressionFailed("Cancelled"))
                default:
                    continuation.resume(throwing: VideoCreationError.compressionFailed("Unexpected status"))
                }
            }
        }
        
        let compressedSize = getFileSize(compressedURL)
        let compressionRatio = Double(originalSize) / Double(compressedSize)
        
        let result = CompressionResult(
            originalURL: videoURL,
            outputURL: compressedURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            compressionRatio: compressionRatio,
            qualityScore: 85.0,
            processingTime: 0.0
        )
        
        compressionResult = result
        print("✅ FAST COMPRESSION: \(formatFileSize(originalSize)) → \(formatFileSize(compressedSize))")
        
        return result
    }
    
    // MARK: - FAST AI ANALYSIS (FIXED: No Double Audio Extraction)
    
    /// FIXED: Use original video URL instead of extracted audio URL to prevent double extraction
    private func performFastAIAnalysis(
        audioResult: AudioExtractionResult,
        userID: String,
        userTier: UserTier,
        progressCallback: @escaping (Double) -> Void
    ) async -> VideoAnalysisResult? {
        
        print("🤖 FAST AI: Starting analysis on extracted audio")
        
        guard aiAnalysisEnabled else {
            progressCallback(1.0)
            return nil
        }
        
        progressCallback(0.2)
        
        // FIXED: Use original video URL instead of extracted audio URL
        // This prevents AIVideoAnalyzer from extracting audio again
        let analysisTask = Task {
            return await aiAnalyzer.analyzeVideo(url: audioResult.originalVideoURL, userID: userID)
        }
        
        do {
            progressCallback(0.5)
            
            // Fast timeout - 10 seconds max
            let result = try await withTimeout(seconds: 10) {
                await analysisTask.value
            }
            
            progressCallback(1.0)
            
            if let result = result {
                print("✅ FAST AI: Success - Title: '\(result.title)'")
            } else {
                print("✅ FAST AI: No result - manual mode")
            }
            
            return result
            
        } catch {
            analysisTask.cancel()
            progressCallback(1.0)
            print("⚠️ FAST AI: Timeout (10s) - manual mode")
            return nil
        }
    }
    
    // MARK: - PHASE 2: PARALLEL UPLOAD
    
    /// Upload with parallel thumbnail generation
    private func performParallelUpload(
        compressionResult: CompressionResult,
        aiResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String
    ) async throws -> VideoUploadResult {
        
        currentPhase = .uploading
        currentTask = "Starting upload..."
        await updateProgress(0.7)
        
        print("☁️ PARALLEL UPLOAD: Starting upload with thumbnail generation")
        
        let metadata = VideoUploadMetadata(
            title: aiResult?.title ?? getDefaultTitle(for: recordingContext),
            description: aiResult?.description ?? getDefaultDescription(for: recordingContext),
            hashtags: aiResult?.hashtags ?? getDefaultHashtags(for: recordingContext),
            creatorID: userID,
            creatorName: ""
        )
        
        // Upload with progress tracking
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
    
    // MARK: - PHASE 3: FEED INTEGRATION (UNCHANGED)
    
    /// Feed integration (same as before)
    private func performFeedIntegration(
        uploadResult: VideoUploadResult,
        analysisResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String
    ) async throws -> CoreVideoMetadata {
        
        currentPhase = .integrating
        currentTask = "Creating video document..."
        await updateProgress(0.9)
        
        guard !userID.isEmpty && !uploadResult.videoURL.isEmpty else {
            throw VideoCreationError.feedIntegrationFailed("Invalid data")
        }
        
        let metadata = VideoUploadMetadata(
            title: (analysisResult?.title ?? "New Video"),
            description: (analysisResult?.description ?? ""),
            hashtags: (analysisResult?.hashtags ?? []),
            creatorID: userID,
            creatorName: ""
        )
        
        let createdVideo = try await uploadService.createVideoDocument(
            uploadResult: uploadResult,
            metadata: metadata,
            recordingContext: recordingContext,
            videoService: videoService
        )
        
        await updateProgress(1.0)
        self.createdVideo = createdVideo
        
        print("🔗 FEED INTEGRATION: Success - \(createdVideo.id)")
        return createdVideo
    }
    
    // MARK: - Helper Methods
    
    /// Update combined parallel progress
    private func updateParallelProgress() async {
        let audioWeight = 0.2    // 20%
        let compressionWeight = 0.4  // 40%
        let aiWeight = 0.4       // 40%
        
        let combinedProgress = (
            audioExtractionProgress * audioWeight +
            compressionProgress * compressionWeight +
            aiAnalysisProgress * aiWeight
        )
        
        await updateProgress(combinedProgress * 0.7) // 0-70% of total
        
        let activeTasks = [
            audioExtractionProgress < 1.0 ? "Audio" : nil,
            compressionProgress < 1.0 ? "Compression" : nil,
            aiAnalysisProgress < 1.0 ? "AI" : nil
        ].compactMap { $0 }
        
        if !activeTasks.isEmpty {
            currentTask = "Processing: \(activeTasks.joined(separator: ", "))"
        }
    }
    
    /// Fast timeout implementation
    /// FIXED: Proper task cancellation to prevent timeout after success
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the operation
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VideoCreationError.analysisTimeout
            }
            
            // Return first completed result and cancel others
            guard let result = try await group.next() else {
                throw VideoCreationError.analysisTimeout
            }
            
            group.cancelAll() // Cancel timeout task if operation succeeded
            return result
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
    
    // MARK: - Error Handling & Cleanup (Same as before)
    
    private func handleCreationError(_ error: Error) async {
        currentPhase = .error
        lastError = error as? VideoCreationError ?? .unknown(error.localizedDescription)
        showingError = true
        await performCleanup()
    }
    
    private func performCleanup() async {
        // Cleanup compressed video
        if let compressedURL = compressedVideoURL, compressedURL != recordedVideoURL {
            try? FileManager.default.removeItem(at: compressedURL)
        }
        
        // Cleanup extracted audio
        if let audioURL = extractedAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        audioExtractor.cleanupTemporaryFiles()
        print("🧹 CLEANUP: All temporary files removed")
    }
    
    // MARK: - Utility Methods (Same as before)
    
    private func updateProgress(_ progress: Double) async {
        overallProgress = progress
    }
    
    private func getDefaultTitle(for context: RecordingContext) -> String {
        switch context {
        case .newThread: return "New Thread"
        case .stitchToThread: return "Stitch"
        case .replyToVideo: return "Reply"
        case .continueThread: return "Thread Continuation"
        }
    }
    
    private func getDefaultDescription(for context: RecordingContext) -> String {
        switch context {
        case .newThread: return "Starting a new conversation"
        case .stitchToThread: return "Stitching to continue the thread"
        case .replyToVideo: return "Replying to the video"
        case .continueThread: return "Continuing the thread"
        }
    }
    
    private func getDefaultHashtags(for context: RecordingContext) -> [String] {
        switch context {
        case .newThread: return ["thread", "newthread"]
        case .stitchToThread: return ["stitch", "thread"]
        case .replyToVideo: return ["reply", "response"]
        case .continueThread: return ["thread", "continue"]
        }
    }
    
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
    
    private func createTemporaryVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "compressed_\(UUID().uuidString).mov"
        return tempDir.appendingPathComponent(filename)
    }
    
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return 0
        }
    }
    
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

/// Updated phases for parallel processing
enum VideoCreationPhase: String, CaseIterable {
    case ready = "ready"
    case parallelProcessing = "parallel_processing" // NEW
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

/// Parallel task types
enum ParallelTask {
    case audioExtraction(AudioExtractionResult)
    case compression(CompressionResult)
    case aiAnalysis(VideoAnalysisResult?)
}

/// Result from parallel processing phase
struct ParallelProcessingResult {
    let audioExtraction: AudioExtractionResult
    let compression: CompressionResult
    let aiAnalysis: VideoAnalysisResult?
}

/// Video creation errors (same as before)
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

/// Compression result
struct CompressionResult {
    let originalURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let compressionRatio: Double
    let qualityScore: Double
    let processingTime: TimeInterval
}

/// Analytics
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
    var sub20SecondCount: Int = 0
}

/// Compression configuration
struct CompressionConfig {
    let targetBitrate: Double
    let maxResolution: CGSize
    let quality: Double
    let frameRate: Double
}
