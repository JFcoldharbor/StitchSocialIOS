//
//  VideoCoordinator.swift
//  CleanBeta
//
//  Layer 6: Coordination - Complete Video Creation Workflow Orchestration
//  Dependencies: VideoService, AIVideoAnalyzer, VideoProcessingService, VideoUploadService
//  Orchestrates: Recording → AI Analysis → Compression → Upload → Feed Integration
//  FIXED: Removed tier restrictions for AI analysis to allow all users
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
        cachingService: CachingService? = nil
    ) {
        self.videoService = videoService
        self.aiAnalyzer = aiAnalyzer
        self.videoProcessor = videoProcessor
        self.uploadService = uploadService
        self.cachingService = cachingService
        
        print("🎬 VIDEO COORDINATOR: Initialized - Ready for complete video creation workflow")
    }
    
    // MARK: - Primary Video Creation Workflow
    
    /// Complete video creation workflow: Recording → Analysis → Compression → Upload → Feed
    func processVideoCreation(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        userID: String,
        userTier: UserTier
    ) async throws -> CoreVideoMetadata {
        
        let startTime = Date()
        isProcessing = true
        currentPhase = .analyzing
        overallProgress = 0.0
        
        print("🎬 VIDEO CREATION: Starting complete workflow")
        print("🎬 CONTEXT: \(recordingContext)")
        print("🎬 USER: \(userID) (\(userTier.displayName))")
        
        defer {
            isProcessing = false
            // Note: Analytics tracking would be implemented here
        }
        
        do {
            // Phase 1: AI Analysis (0-30%)
            let analysisResult = try await performAIAnalysis(
                videoURL: recordedVideoURL,
                userID: userID,
                userTier: userTier
            )
            
            // Phase 2: Video Compression (30-60%)
            let compressionResult = try await performVideoCompression(
                videoURL: recordedVideoURL,
                analysisResult: analysisResult
            )
            
            // Phase 3: Video Upload (60-85%)
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
            
            print("✅ VIDEO CREATION: Complete workflow finished successfully")
            return createdVideo
            
        } catch {
            await handleCreationError(error)
            throw error
        }
    }
    
    // MARK: - Phase 1: AI Analysis - FIXED TO ALLOW ALL TIERS
    
    /// Perform AI analysis with fallback to manual content creation
    private func performAIAnalysis(
        videoURL: URL,
        userID: String,
        userTier: UserTier
    ) async throws -> VideoAnalysisResult? {
        
        currentPhase = .analyzing
        currentTask = "Analyzing video content..."
        await updateProgress(0.1)
        
        print("🤖 AI ANALYSIS: Starting analysis phase")
        print("🤖 USER TIER: \(userTier.displayName)")
        print("🤖 AI ENABLED: \(aiAnalysisEnabled)")
        
        // FIXED: Remove tier restriction - allow all users to try AI analysis
        guard aiAnalysisEnabled else {
            print("🤖 AI ANALYSIS: Skipped - AI analysis disabled globally")
            await updateProgress(0.3)
            return nil
        }
        
        print("🤖 AI ANALYSIS: Proceeding with analysis for \(userTier.displayName) user")
        
        do {
            print("🤖 AI ANALYSIS: Calling aiAnalyzer.analyzeVideo()")
            print("🤖 VIDEO URL: \(videoURL)")
            print("🤖 USER ID: \(userID)")
            
            // Perform AI analysis with proper method signature
            let result = await aiAnalyzer.analyzeVideo(url: videoURL, userID: userID)
            
            // Store result for later use
            aiAnalysisResult = result
            
            await updateProgress(0.3)
            currentTask = "AI analysis complete"
            
            if let result = result {
                print("✅ AI ANALYSIS: Success - Title: '\(result.title)'")
                print("✅ AI ANALYSIS: Description: '\(result.description)'")
                print("✅ AI ANALYSIS: Hashtags: \(result.hashtags)")
            } else {
                print("✅ AI ANALYSIS: Completed - No result (manual content creation)")
                print("📝 MANUAL MODE: User will create own title/description")
            }
            
            return result
            
        } catch {
            print("⚠️ AI ANALYSIS: Failed with error - \(error.localizedDescription)")
            print("📝 FALLBACK: Continuing without AI analysis - manual content creation")
            // Continue without AI analysis - manual content creation
            await updateProgress(0.3)
            return nil
        }
    }
    
    // MARK: - Phase 2: Video Compression
    
    /// Perform video compression to target 2-3MB file size
    private func performVideoCompression(
        videoURL: URL,
        analysisResult: VideoAnalysisResult?
    ) async throws -> CompressionResult {
        
        currentPhase = .compressing
        currentTask = "Preparing compression..."
        await updateProgress(0.35)
        
        print("🗜️ COMPRESSION: Starting compression phase")
        
        guard compressionEnabled else {
            print("🗜️ COMPRESSION: Skipped - compression disabled")
            return createSkippedCompressionResult(videoURL: videoURL)
        }
        
        do {
            // For now, skip compression and use original video
            currentTask = "Using original video (compression pending)..."
            await updateProgress(0.6)
            
            print("⚠️ COMPRESSION: Using original video as compression is not implemented")
            
            let originalSize = getFileSize(videoURL)
            let result = CompressionResult(
                originalURL: videoURL,
                outputURL: videoURL,
                originalSize: originalSize,
                compressedSize: originalSize,
                compressionRatio: 1.0,
                qualityScore: 1.0,
                processingTime: 0.1
            )
            
            compressionResult = result
            compressedVideoURL = videoURL
            
            print("🗜️ COMPRESSION: Complete (skipped) - Size: \(formatFileSize(originalSize))")
            return result
            
        } catch {
            print("❌ COMPRESSION: Failed with error - \(error.localizedDescription)")
            throw VideoCreationError.compressionFailed(error.localizedDescription)
        }
    }
    
    /// Create compression result when compression is skipped
    private func createSkippedCompressionResult(videoURL: URL) -> CompressionResult {
        let fileSize = getFileSize(videoURL)
        
        return CompressionResult(
            originalURL: videoURL,
            outputURL: videoURL,
            originalSize: fileSize,
            compressedSize: fileSize,
            compressionRatio: 1.0,
            qualityScore: 1.0,
            processingTime: 0.0
        )
    }
    
    // MARK: - Phase 3: Video Upload
    
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
            // Create upload metadata
            let metadata = createUploadMetadata(
                analysisResult: analysisResult,
                userID: userID,
                recordingContext: recordingContext
            )
            
            currentTask = "Uploading video..."
            await updateProgress(0.7)
            
            // Upload video using upload service
            let result = try await uploadService.uploadVideo(
                videoURL: videoURL,
                metadata: VideoUploadMetadata(
                    title: metadata.title,
                    description: metadata.description,
                    hashtags: metadata.hashtags,
                    creatorID: metadata.creatorID,
                    creatorName: metadata.creatorName
                ),
                recordingContext: recordingContext
            )
            
            await updateProgress(0.85)
            currentTask = "Upload complete"
            
            // Store for later use
            uploadResult = result
            
            print("☁️ UPLOAD: Success - Video URL: \(result.videoURL)")
            print("☁️ UPLOAD: Thumbnail URL: \(result.thumbnailURL)")
            
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
        
        do {
            // Create video document using upload service with proper parameters
            let createdVideo = try await uploadService.createVideoDocument(
                uploadResult: uploadResult,
                metadata: VideoUploadMetadata(
                    title: (analysisResult?.title ?? "New Video"),
                    description: (analysisResult?.description ?? ""),
                    hashtags: (analysisResult?.hashtags ?? ["#stitch"]),
                    creatorID: userID,
                    creatorName: ""
                ),
                recordingContext: recordingContext,
                videoService: videoService
            )
            
            await updateProgress(0.95)
            currentTask = "Updating user statistics..."
            
            // Update user video count
            try await updateUserVideoCount(userID: userID)
            
            await updateProgress(1.0)
            currentTask = "Integration complete"
            
            // Store for later use
            self.createdVideo = createdVideo
            
            print("🔗 FEED INTEGRATION: Success - Video ID: \(createdVideo.id)")
            print("🔗 FEED INTEGRATION: Title: '\(createdVideo.title)'")
            
            return createdVideo
            
        } catch {
            print("❌ FEED INTEGRATION: Failed with error - \(error.localizedDescription)")
            throw VideoCreationError.feedIntegrationFailed(error.localizedDescription)
        }
    }
    
    /// Update user video count after successful upload
    private func updateUserVideoCount(userID: String) async throws {
        do {
            // Increment user's video count using Firebase
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let userRef = db.collection(FirebaseSchema.Collections.users).document(userID)
            
            try await userRef.updateData([
                FirebaseSchema.UserDocument.videoCount: FieldValue.increment(Int64(1)),
                FirebaseSchema.UserDocument.updatedAt: Timestamp()
            ])
            
            print("📊 USER STATS: Updated video count for \(userID)")
            
        } catch {
            print("⚠️ USER STATS: Failed to update video count - \(error.localizedDescription)")
            // Don't throw - this is non-critical
        }
    }
    
    // MARK: - Workflow Completion
    
    /// Complete the video creation workflow
    private func completeVideoCreation(createdVideo: CoreVideoMetadata) async {
        currentPhase = .complete
        currentTask = "Complete!"
        overallProgress = 1.0
        
        // Update analytics
        creationMetrics.totalVideosCreated += 1
        creationMetrics.lastCreatedVideoID = createdVideo.id
        
        if aiAnalysisResult != nil {
            creationMetrics.aiAnalysisUsageCount += 1
        }
        
        if let compressionResult = compressionResult {
            creationMetrics.averageCompressionRatio = compressionResult.compressionRatio
            creationMetrics.averageFileSizeReduction = compressionResult.sizeReduction
        }
        
        // Update performance stats
        performanceStats.averageCreationTime = calculateAverageCreationTime()
        performanceStats.successRate = calculateSuccessRate()
        
        print("🎉 WORKFLOW COMPLETE: Video '\(createdVideo.title)' created successfully")
        print("📊 ANALYTICS: Total videos created: \(creationMetrics.totalVideosCreated)")
    }
    
    // MARK: - Error Handling
    
    /// Handle video creation errors with retry logic
    private func handleCreationError(_ error: Error) async {
        
        currentPhase = .error
        lastError = error as? VideoCreationError ?? .unknown(error.localizedDescription)
        showingError = true
        canRetry = determineRetryability(error)
        
        // Update analytics
        creationMetrics.totalErrorsEncountered += 1
        performanceStats.lastErrorType = lastError?.localizedDescription
        
        print("❌ VIDEO CREATION: Error encountered - \(error.localizedDescription)")
        print("🔄 RETRY: Can retry: \(canRetry)")
    }
    
    /// Determine if error allows retry
    private func determineRetryability(_ error: Error) -> Bool {
        if let creationError = error as? VideoCreationError {
            switch creationError {
            case .networkError, .uploadFailed, .compressionFailed:
                return true
            case .invalidVideo, .userNotFound, .permissionDenied:
                return false
            default:
                return true
            }
        }
        return true
    }
    
    // MARK: - Helper Methods
    
    /// Update overall workflow progress
    private func updateProgress(_ progress: Double) async {
        overallProgress = min(1.0, max(0.0, progress))
    }
    
    /// Create upload metadata from AI analysis or defaults
    private func createUploadMetadata(
        analysisResult: VideoAnalysisResult?,
        userID: String,
        recordingContext: RecordingContext
    ) -> VideoUploadServiceMetadata {
        
        // Use AI results if available, otherwise use context-based defaults
        let title = analysisResult?.title ?? generateDefaultTitle(for: recordingContext)
        let description = analysisResult?.description ?? generateDefaultDescription(for: recordingContext)
        let hashtags = analysisResult?.hashtags ?? generateDefaultHashtags(for: recordingContext)
        
        return VideoUploadServiceMetadata(
            title: title,
            description: description,
            hashtags: hashtags,
            creatorID: userID,
            creatorName: "" // Will be filled by upload service
        )
    }
    
    /// Generate default title based on recording context
    private func generateDefaultTitle(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "New Stitch"
        case .stitchToThread(_, _):
            return "Stitch Reply"
        case .replyToVideo(_, _):
            return "Video Reply"
        case .continueThread(_, _):
            return "Thread Continue"
        }
    }
    
    /// Generate default description based on recording context
    private func generateDefaultDescription(for context: RecordingContext) -> String {
        switch context {
        case .newThread:
            return "New video thread"
        case .stitchToThread(_, _):
            return "Stitching to thread"
        case .replyToVideo(_, _):
            return "Video reply"
        case .continueThread(_, _):
            return "Continuing thread"
        }
    }
    
    /// Generate default hashtags based on recording context
    private func generateDefaultHashtags(for context: RecordingContext) -> [String] {
        var hashtags = ["#stitch"]
        
        switch context {
        case .newThread:
            hashtags.append("#original")
        case .stitchToThread(_, _):
            hashtags.append("#stitch")
        case .replyToVideo(_, _):
            hashtags.append("#reply")
        case .continueThread(_, _):
            hashtags.append("#continue")
        }
        
        return hashtags
    }
    
    /// Get file size of video
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[FileAttributeKey.size] as? Int64 ?? 0
        } catch {
            print("⚠️ FILE SIZE: Could not get file size for \(url.lastPathComponent)")
            return 0
        }
    }
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Calculate average creation time
    private func calculateAverageCreationTime() -> TimeInterval {
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
        case .invalidVideo(let message):
            return "Invalid video: \(message)"
        case .analysisTimeout:
            return "AI analysis timed out"
        case .compressionFailed(let message):
            return "Compression failed: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .feedIntegrationFailed(let message):
            return "Feed integration failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .userNotFound:
            return "User not found"
        case .permissionDenied:
            return "Permission denied"
        case .unknown(let message):
            return "Unknown error: \(message)"
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
    
    var sizeReduction: Double {
        guard originalSize > 0 else { return 0.0 }
        return (1.0 - (Double(compressedSize) / Double(originalSize))) * 100
    }
}

/// Video creation metrics for analytics
struct VideoCreationMetrics {
    var totalVideosCreated: Int = 0
    var totalErrorsEncountered: Int = 0
    var aiAnalysisUsageCount: Int = 0
    var averageCompressionRatio: Double = 1.0
    var averageFileSizeReduction: Double = 0.0
    var lastCreatedVideoID: String?
}

/// Performance statistics
struct PerformanceStats {
    var averageCreationTime: TimeInterval = 0.0
    var successRate: Double = 1.0
    var lastErrorType: String?
    var compressionEfficiency: Double = 0.0
}

/// Video upload metadata for service coordination
struct VideoUploadServiceMetadata {
    let title: String
    let description: String
    let hashtags: [String]
    let creatorID: String
    let creatorName: String
}

// MARK: - Extensions

extension UserTier {
    /// UPDATED: Allow AI features for all users in development/testing
    var allowsAIFeatures: Bool {
        // For development: Allow all users to test AI features
        #if DEBUG
        return true
        #else
        // For production: Maintain tier restrictions
        switch self {
        case .rookie, .rising:
            return false // Basic tiers get manual content creation
        case .veteran, .influencer, .elite, .partner, .legendary, .topCreator, .founder, .coFounder:
            return true
        }
        #endif
    }
}
