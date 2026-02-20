//
//  VideoCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - PARALLEL Video Creation Workflow Orchestration
//
//  🔧 UPDATED: Integrated FastVideoCompressor for CapCut-style speed
//  🔧 UPDATED: Added trim support (trimStartTime, trimEndTime)
//  🔧 UPDATED: Added pre-compression support (use already-compressed video)
//  🔧 UPDATED: Background compression starts when recording ends
//  🔧 OPTIMIZED: Uses AIVideoAnalyzer.shared singleton — no duplicate connection tests
//  🔧 OPTIMIZED: CachingService.shared passed by default — was nil before
//

import Foundation
import SwiftUI
import AVFoundation
import FirebaseFirestore

/// Orchestrates parallel video creation workflow for maximum speed
/// Now uses FastVideoCompressor for CapCut-style 5-10 second compression
@MainActor
class VideoCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let userService: UserService
    private let aiAnalyzer: AIVideoAnalyzer
    private let fastCompressor: FastVideoCompressor  // 🆕 NEW: Fast hardware compression
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
    
    // MARK: - 🆕 NEW: Pre-compression State (Background compression)
    
    @Published var preCompressedVideoURL: URL?
    @Published var preCompressionComplete: Bool = false
    @Published var preCompressionProgress: Double = 0.0
    
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
    
    /// Target file size for compression (50MB for safe margin under 100MB limit)
    private let targetFileSizeMB: Double = 50.0
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService,
        aiAnalyzer: AIVideoAnalyzer = .shared,
        uploadService: VideoUploadService,
        cachingService: CachingService? = CachingService.shared,
        audioExtractor: AudioExtractionService? = nil,
        notificationService: NotificationService? = nil
    ) {
        self.videoService = videoService
        self.userService = userService
        self.aiAnalyzer = aiAnalyzer
        self.fastCompressor = FastVideoCompressor.shared  // 🆕 Use singleton
        self.uploadService = uploadService
        self.cachingService = cachingService
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        self.notificationService = notificationService ?? NotificationService()
        
        print("🎬 VIDEO COORDINATOR: Initialized with FAST COMPRESSION + TRIM SUPPORT")
    }
    
    // MARK: - 🆕 NEW: Background Pre-Compression
    
    /// Start compression immediately when recording ends (CapCut-style)
    /// Call this as soon as recording stops, before user enters review screen
    func startBackgroundCompression(videoURL: URL) {
        guard preCompressedVideoURL == nil else {
            print("⚠️ BACKGROUND COMPRESS: Already have pre-compressed video")
            return
        }
        
        preCompressionComplete = false
        preCompressionProgress = 0.0
        
        print("🚀 BACKGROUND COMPRESS: Starting while user reviews...")
        
        Task {
            do {
                let result = try await fastCompressor.compress(
                    sourceURL: videoURL,
                    targetSizeMB: targetFileSizeMB,
                    preserveResolution: false,
                    progressCallback: { [weak self] progress in
                        Task { @MainActor in
                            self?.preCompressionProgress = progress
                        }
                    }
                )
                
                await MainActor.run {
                    self.preCompressedVideoURL = result.outputURL
                    self.preCompressionComplete = true
                    print("✅ BACKGROUND COMPRESS: Complete - \(result.compressedSize / 1024 / 1024)MB in \(String(format: "%.1f", result.processingTime))s")
                }
                
            } catch {
                print("⚠️ BACKGROUND COMPRESS: Failed - \(error.localizedDescription)")
                // Not fatal - we'll compress on-demand during post
            }
        }
    }
    
    /// Invalidate pre-compression (call when user changes trim)
    func invalidatePreCompression() {
        if let url = preCompressedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        preCompressedVideoURL = nil
        preCompressionComplete = false
        preCompressionProgress = 0.0
        print("🔄 BACKGROUND COMPRESS: Invalidated (trim changed)")
    }
    
    // MARK: - 🔧 UPDATED: Main Video Creation (with trim support)
    
    /// Process video creation with optional trim parameters
    /// - Parameters:
    ///   - recordedVideoURL: Original recorded video
    ///   - trimStartTime: Optional trim start (nil = no trim)
    ///   - trimEndTime: Optional trim end (nil = no trim)
    ///   - preCompressedURL: Optional pre-compressed video (from background compression)
    func processVideoCreation(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        userID: String,
        userTier: UserTier,
        trimStartTime: TimeInterval? = nil,
        trimEndTime: TimeInterval? = nil,
        preCompressedURL: URL? = nil,
        manualTitle: String? = nil,
        manualDescription: String? = nil,
        taggedUserIDs: [String] = [],
        recordingSource: String = "unknown",
        hashtags: [String] = [],
        customThumbnailTime: TimeInterval? = nil
    ) async throws -> CoreVideoMetadata {
        
        guard !isProcessing else {
            throw VideoCreationError.unknown("Video creation already in progress")
        }
        
        let workflowStartTime = Date()
        isProcessing = true
        self.recordedVideoURL = recordedVideoURL
        
        // Reset all progress for fresh run
        overallProgress = 0.0
        audioExtractionProgress = 0.0
        compressionProgress = 0.0
        aiAnalysisProgress = 0.0
        uploadProgress = 0.0
        
        print("🚀 FAST WORKFLOW: Starting optimized processing")
        print("🎬 VIDEO: \(recordedVideoURL.lastPathComponent)")
        
        // Log trim info
        if let start = trimStartTime, let end = trimEndTime {
            print("✂️ TRIM: \(String(format: "%.1f", start))s - \(String(format: "%.1f", end))s")
        }
        
        // Log pre-compression status
        if let preURL = preCompressedURL ?? preCompressedVideoURL, preCompressionComplete {
            print("⚡ PRE-COMPRESSED: Using background-compressed video")
        }
        
        defer {
            isProcessing = false
            // Clear pre-compression state after use
            preCompressedVideoURL = nil
            preCompressionComplete = false
        }
        
        do {
            // PHASE 1: PARALLEL PROCESSING (0-70%)
            let parallelResults = try await performParallelProcessing(
                videoURL: recordedVideoURL,
                userID: userID,
                userTier: userTier,
                trimStartTime: trimStartTime,
                trimEndTime: trimEndTime,
                preCompressedURL: preCompressedURL ?? preCompressedVideoURL
            )
            
            // PHASE 2: UPLOAD (70-90%)
            let uploadResult = try await performParallelUpload(
                compressionResult: parallelResults.compression,
                aiResult: parallelResults.aiAnalysis,
                recordingContext: recordingContext,
                userID: userID,
                customThumbnailTime: customThumbnailTime
            )
            
            // PHASE 3: FEED INTEGRATION (90-100%)
            let createdVideo = try await performFeedIntegration(
                uploadResult: uploadResult,
                analysisResult: parallelResults.aiAnalysis,
                recordingContext: recordingContext,
                userID: userID,
                manualTitle: manualTitle,
                manualDescription: manualDescription,
                taggedUserIDs: taggedUserIDs,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // PHASE 4: NOTIFICATIONS
            if !taggedUserIDs.isEmpty {
                await sendMentionNotifications(
                    videoID: createdVideo.id,
                    videoTitle: createdVideo.title,
                    taggerUserID: userID,
                    taggedUserIDs: taggedUserIDs
                )
            }
            
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
    
    // MARK: - 🔧 UPDATED: Parallel Processing with FastVideoCompressor
    
    private func performParallelProcessing(
        videoURL: URL,
        userID: String,
        userTier: UserTier,
        trimStartTime: TimeInterval?,
        trimEndTime: TimeInterval?,
        preCompressedURL: URL?
    ) async throws -> ParallelProcessingResult {
        
        currentPhase = .parallelProcessing
        currentTask = "Processing video..."
        await updateProgress(0.0)
        
        print("⚡ PARALLEL: Starting audio + compression + AI")
        
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
            
            // Task 2: Fast Video Compression (🆕 UPDATED)
            group.addTask { [weak self] in
                guard let self = self else { throw VideoCreationError.unknown("Coordinator deallocated") }
                
                let startTime = Date()
                var compressedURL: URL
                var originalSize: Int64
                var compressedSize: Int64
                
                // Check if we have pre-compressed video (no trim change)
                if let preURL = preCompressedURL, trimStartTime == nil {
                    print("⚡ COMPRESSION: Using pre-compressed video!")
                    compressedURL = preURL
                    originalSize = await self.getFileSize(videoURL)
                    compressedSize = await self.getFileSize(preURL)
                    
                    await MainActor.run {
                        self.compressionProgress = 1.0
                    }
                    
                } else if let start = trimStartTime, let end = trimEndTime {
                    // Compress WITH trim (single pass - most efficient)
                    print("🗜️ COMPRESSION: Fast compress + trim in single pass")
                    
                    let result = try await self.fastCompressor.compressWithTrim(
                        sourceURL: videoURL,
                        startTime: start,
                        endTime: end,
                        targetSizeMB: self.targetFileSizeMB
                    )
                    
                    compressedURL = result.outputURL
                    originalSize = result.originalSize
                    compressedSize = result.compressedSize
                    
                    await MainActor.run {
                        self.compressionProgress = 1.0
                    }
                    
                } else {
                    // Standard fast compression (no trim)
                    print("🗜️ COMPRESSION: Fast compress (no trim)")
                    
                    let result = try await self.fastCompressor.compress(
                        sourceURL: videoURL,
                        targetSizeMB: self.targetFileSizeMB,
                        progressCallback: { progress in
                            Task { @MainActor in
                                self.compressionProgress = progress
                                await self.updateParallelProgress()
                            }
                        }
                    )
                    
                    compressedURL = result.outputURL
                    originalSize = result.originalSize
                    compressedSize = result.compressedSize
                }
                
                let processingTime = Date().timeIntervalSince(startTime)
                let ratio = originalSize > 0 ? Double(compressedSize) / Double(originalSize) : 1.0
                
                let result = CompressionResult(
                    originalURL: videoURL,
                    outputURL: compressedURL,
                    originalSize: originalSize,
                    compressedSize: compressedSize,
                    compressionRatio: ratio,
                    qualityScore: 0.85,
                    processingTime: processingTime
                )
                
                print("✅ COMPRESSION: \(originalSize / 1024 / 1024)MB → \(compressedSize / 1024 / 1024)MB in \(String(format: "%.1f", processingTime))s")
                
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
                    Task { await self.updateParallelProgress() }
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
                    print("🗜️ PARALLEL: Compression complete - \(String(format: "%.0f", result.compressionRatio * 100))% of original")
                case .aiAnalysis(let result):
                    aiResult = result
                    self.aiAnalysisResult = result
                    if let title = result?.title {
                        print("🧠 PARALLEL: AI analysis complete - '\(title)'")
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
    
    // MARK: - PHASE 2: Upload
    
    private func performParallelUpload(
        compressionResult: CompressionResult,
        aiResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String,
        customThumbnailTime: TimeInterval? = nil
    ) async throws -> VideoUploadResult {
        
        currentPhase = .uploading
        currentTask = "Uploading video..."
        await updateProgress(0.7)
        
        print("☁️ UPLOAD: Starting with compressed video (\(compressionResult.compressedSize / 1024 / 1024)MB)")
        
        let metadata = VideoUploadMetadata(
            title: aiResult?.title ?? getDefaultTitle(for: recordingContext),
            description: aiResult?.description ?? getDefaultDescription(for: recordingContext),
            hashtags: aiResult?.hashtags ?? getDefaultHashtags(for: recordingContext),
            creatorID: userID,
            creatorName: ""
        )
        
        // Monitor uploadService.uploadProgress and map 0.0-1.0 → coordinator 0.7-0.9
        let progressTask = Task { @MainActor in
            var lastMapped = 0.7
            while !Task.isCancelled {
                let uploadFrac = self.uploadService.uploadProgress
                let mapped = 0.7 + (uploadFrac * 0.2) // 0.7 → 0.9
                if mapped > lastMapped {
                    lastMapped = mapped
                    self.overallProgress = max(self.overallProgress, mapped)
                    
                    // Update task text based on upload phase
                    if uploadFrac < 0.2 {
                        self.currentTask = "Preparing upload..."
                    } else if uploadFrac < 0.7 {
                        self.currentTask = "Uploading video..."
                    } else if uploadFrac < 0.9 {
                        self.currentTask = "Uploading thumbnail..."
                    } else {
                        self.currentTask = "Finalizing..."
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 10fps poll
            }
        }
        
        let result = try await uploadService.uploadVideo(
            videoURL: compressionResult.outputURL,
            metadata: metadata,
            recordingContext: recordingContext,
            customThumbnailTime: customThumbnailTime
        )
        
        progressTask.cancel()
        await updateProgress(0.9)
        uploadResult = result
        
        print("☁️ UPLOAD: Complete - \(result.videoURL)")
        return result
    }
    
    // MARK: - PHASE 3: Feed Integration
    
    private func performFeedIntegration(
        uploadResult: VideoUploadResult,
        analysisResult: VideoAnalysisResult?,
        recordingContext: RecordingContext,
        userID: String,
        manualTitle: String?,
        manualDescription: String?,
        taggedUserIDs: [String],
        recordingSource: String,
        hashtags: [String]
    ) async throws -> CoreVideoMetadata {
        
        currentPhase = .integrating
        currentTask = "Creating video document..."
        await updateProgress(0.9)
        
        let finalTitle = manualTitle ?? analysisResult?.title ?? getDefaultTitle(for: recordingContext)
        let finalDescription = manualDescription ?? analysisResult?.description ?? getDefaultDescription(for: recordingContext)
        
        let smartHashtags = generateSmartHashtags(
            aiHashtags: analysisResult?.hashtags,
            recordingContext: recordingContext
        )
        
        let metadata = VideoUploadMetadata(
            title: finalTitle,
            description: finalDescription,
            hashtags: smartHashtags,
            creatorID: userID,
            creatorName: ""
        )
        
        print("📝 FEED INTEGRATION: Title = '\(finalTitle)'")
        
        let createdVideo = try await uploadService.createVideoDocument(
            uploadResult: uploadResult,
            metadata: metadata,
            recordingContext: recordingContext,
            videoService: videoService,
            userService: userService,
            notificationService: notificationService,
            taggedUserIDs: taggedUserIDs,
            recordingSource: recordingSource,
            hashtags: hashtags
        )
        
        await updateProgress(1.0)
        self.createdVideo = createdVideo
        
        // OPTIMIZED: Cache created video for instant feed display
        cachingService?.cacheVideo(createdVideo, priority: .high)
        
        return createdVideo
    }
    
    // MARK: - Notifications
    
    private func sendMentionNotifications(
        videoID: String,
        videoTitle: String,
        taggerUserID: String,
        taggedUserIDs: [String]
    ) async {
        for taggedUserID in taggedUserIDs {
            guard taggedUserID != taggerUserID else { continue }
            
            do {
                try await notificationService.sendMentionNotification(
                    to: taggedUserID,
                    videoID: videoID,
                    videoTitle: videoTitle,
                    mentionContext: "tagged in video"
                )
                print("✅ MENTION: Sent to \(taggedUserID)")
            } catch {
                print("⚠️ MENTION: Failed for \(taggedUserID) - \(error)")
            }
        }
    }
    
    private func sendStitchNotifications(
        createdVideo: CoreVideoMetadata,
        recordingContext: RecordingContext,
        creatorUserID: String
    ) async {
        guard case .stitchToThread(let parentVideoID, _) = recordingContext else { return }
        
        do {
            let parentVideo = try await videoService.getVideo(id: parentVideoID)
            
            try await notificationService.sendStitchNotification(
                videoID: createdVideo.id,
                videoTitle: createdVideo.title,
                originalCreatorID: parentVideo.creatorID,
                parentCreatorID: parentVideo.creatorID,
                threadUserIDs: []
            )
            print("✅ STITCH: Notification sent")
        } catch {
            print("⚠️ STITCH: Notification failed - \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateParallelProgress() async {
        let weights = (audio: 0.2, compression: 0.5, ai: 0.3)
        
        let combined = (
            audioExtractionProgress * weights.audio +
            compressionProgress * weights.compression +
            aiAnalysisProgress * weights.ai
        )
        
        // Maps to 0.0-0.7 range, updateProgress enforces monotonic increase
        await updateProgress(combined * 0.7)
        
        let activeTasks = [
            audioExtractionProgress < 1.0 ? "Audio" : nil,
            compressionProgress < 1.0 ? "Compressing" : nil,
            aiAnalysisProgress < 1.0 ? "AI" : nil
        ].compactMap { $0 }
        
        if !activeTasks.isEmpty {
            currentTask = activeTasks.joined(separator: " + ")
        }
    }
    
    private func completeVideoCreation(createdVideo: CoreVideoMetadata, totalTime: TimeInterval) async {
        currentPhase = .complete
        currentTask = "Video created!"
        
        creationMetrics.totalVideosCreated += 1
        creationMetrics.lastCreatedVideoID = createdVideo.id
        performanceStats.averageCreationTime = totalTime
        
        if totalTime < 20 {
            performanceStats.sub20SecondCount += 1
        }
        
        print("🎉 WORKFLOW COMPLETE!")
        print("⏱️ TOTAL TIME: \(String(format: "%.1f", totalTime))s")
        print("🎯 SUB-20s: \(totalTime < 20 ? "YES ✓" : "NO")")
    }
    
    private func handleCreationError(_ error: Error) async {
        currentPhase = .error
        lastError = error as? VideoCreationError ?? .unknown(error.localizedDescription)
        showingError = true
        await performCleanup()
    }
    
    private func performCleanup() async {
        if let url = compressedVideoURL, url != recordedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = extractedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func updateProgress(_ progress: Double) async {
        // Never go backwards — prevents flickering between phases
        if progress > overallProgress {
            overallProgress = progress
        }
    }
    
    private func getFileSize(_ url: URL) async -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
    
    private func generateSmartHashtags(aiHashtags: [String]?, recordingContext: RecordingContext) -> [String] {
        var tags: [String] = aiHashtags?.prefix(3).map { $0 } ?? []
        
        switch recordingContext {
        case .newThread: tags.append("original")
        case .stitchToThread: tags.append("stitch")
        case .replyToVideo: tags.append("reply")
        case .continueThread: tags.append("continuation")
        case .spinOffFrom: tags.append("spinoff")
        }
        
        return Array(Set(tags)).prefix(5).map { $0 }
    }
    
    private func getDefaultTitle(for context: RecordingContext) -> String {
        switch context {
        case .newThread: return "New Thread"
        case .stitchToThread(_, let info): return "Stitch to \(info.creatorName)"
        case .replyToVideo(_, let info): return "Reply to \(info.creatorName)"
        case .continueThread(_, let info): return "Continuing: \(info.title)"
        case .spinOffFrom(_, _, let info): return "Responding to \(info.creatorName)"
        }
    }
    
    private func getDefaultDescription(for context: RecordingContext) -> String {
        switch context {
        case .newThread: return "Check out my new thread!"
        case .stitchToThread(_, let info): return "Stitching to thread by \(info.creatorName)"
        case .replyToVideo(_, let info): return "Replying to video by \(info.creatorName)"
        case .continueThread(_, let info): return "Continuing thread: \(info.title)"
        case .spinOffFrom(_, _, let info): return "Spin-off responding to \(info.creatorName)"
        }
    }
    
    private func getDefaultHashtags(for context: RecordingContext) -> [String] {
        switch context {
        case .newThread: return ["newthread", "original"]
        case .stitchToThread: return ["stitch"]
        case .replyToVideo: return ["reply"]
        case .continueThread: return ["continuation"]
        case .spinOffFrom: return ["spinoff", "response"]
        }
    }
}

// MARK: - Supporting Types

enum VideoCreationPhase: String, CaseIterable {
    case ready, parallelProcessing, uploading, integrating, complete, error
    
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .parallelProcessing: return "Processing"
        case .uploading: return "Uploading"
        case .integrating: return "Finishing"
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
        case .invalidVideo(let msg): return "Invalid Video: \(msg)"
        case .analysisTimeout: return "Analysis timed out"
        case .compressionFailed(let msg): return "Compression Failed: \(msg)"
        case .uploadFailed(let msg): return "Upload Failed: \(msg)"
        case .feedIntegrationFailed(let msg): return "Integration Failed: \(msg)"
        case .networkError(let msg): return "Network Error: \(msg)"
        case .userNotFound: return "User not found"
        case .permissionDenied: return "Permission denied"
        case .unknown(let msg): return msg
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
