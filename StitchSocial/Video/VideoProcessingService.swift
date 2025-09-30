//
//  VideoProcessingService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Video Technical Analysis & Compression
//  Handles video quality assessment, format validation, and compression
//  Pure AVFoundation processing - no Firebase or AI dependencies
//  UPDATED: Duration-based tiered compression with user tier privileges
//

import Foundation
import AVFoundation
import CoreImage
import VideoToolbox

/// Service for technical video analysis, quality assessment, and compression
/// Provides detailed metadata about video quality, format, and compression capabilities
@MainActor
class VideoProcessingService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var lastProcessingError: VideoProcessingError?
    
    // MARK: - Configuration
    
    private let qualityThresholds = QualityThresholds()
    private let supportedFormats: Set<String> = ["mp4", "mov", "m4v"]
    private let preferredCodecs: Set<String> = ["avc1", "hvc1"] // H.264, H.265
    
    // MARK: - Analytics
    
    @Published var totalProcessed: Int = 0
    private var processingMetrics: [ProcessingMetrics] = []
    
    // MARK: - Public Interface
    
    /// Analyzes video technical quality and extracts comprehensive metadata
    /// Returns detailed analysis including quality scores and recommendations
    func analyzeVideoQuality(videoURL: URL) async throws -> VideoQualityAnalysis {
        let startTime = Date()
        
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
            self.currentTask = "Starting video analysis..."
            self.lastProcessingError = nil
        }
        
        do {
            // Step 1: Basic validation
            await updateProgress(0.1, task: "Validating video file...")
            try await validateVideoFile(videoURL)
            
            // Step 2: Extract basic metadata
            await updateProgress(0.2, task: "Extracting video metadata...")
            let basicMetadata = try await extractBasicMetadata(videoURL)
            
            // Step 3: Analyze video tracks
            await updateProgress(0.4, task: "Analyzing video quality...")
            let videoAnalysis = try await analyzeVideoTracks(videoURL)
            
            // Step 4: Analyze audio tracks
            await updateProgress(0.6, task: "Analyzing audio quality...")
            let audioAnalysis = try await analyzeAudioTracks(videoURL)
            
            // Step 5: Calculate quality scores
            await updateProgress(0.8, task: "Calculating quality scores...")
            let qualityScores = calculateQualityScores(
                basic: basicMetadata,
                video: videoAnalysis,
                audio: audioAnalysis
            )
            
            // Step 6: Generate recommendations
            await updateProgress(0.9, task: "Generating recommendations...")
            let recommendations = generateRecommendations(
                metadata: basicMetadata,
                video: videoAnalysis,
                audio: audioAnalysis,
                scores: qualityScores
            )
            
            await updateProgress(1.0, task: "Analysis complete!")
            
            let result = VideoQualityAnalysis(
                basicMetadata: basicMetadata,
                videoAnalysis: videoAnalysis,
                audioAnalysis: audioAnalysis,
                qualityScores: qualityScores,
                recommendations: recommendations,
                processingTime: Date().timeIntervalSince(startTime)
            )
            
            await MainActor.run {
                self.isProcessing = false
                self.totalProcessed += 1
            }
            
            recordProcessingMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: true,
                qualityScore: qualityScores.overall,
                error: nil
            )
            
            return result
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.lastProcessingError = error as? VideoProcessingError
            }
            
            recordProcessingMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: false,
                qualityScore: 0.0,
                error: error
            )
            
            throw error
        }
    }
    
    // MARK: - Video Compression (UPDATED WITH DURATION-BASED TIERED STRATEGY)
    
    /// Compress video to target file size with H.264/AAC encoding and duration-based tiered strategy
    /// Achieves 90% size reduction (28MB → 3MB) while maintaining quality based on user tier
    /// UPDATED: Now includes userTier parameter for duration-based tiered compression
    func compress(
        videoURL: URL,
        userTier: UserTier,
        targetSizeMB: Double = 3.0,
        progressCallback: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        
        let startTime = Date()
        
        print("🗜️ PROCESSING SERVICE: Starting tiered compression for \(userTier.displayName)")
        
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
            self.currentTask = "Preparing video compression..."
            self.lastProcessingError = nil
        }
        
        do {
            // STEP 1: Validate input video
            await updateProgress(0.1, task: "Validating video file...")
            try await validateVideoFile(videoURL)
            
            // STEP 2: Extract video duration for tiered strategy
            await updateProgress(0.15, task: "Extracting video duration...")
            let asset = AVAsset(url: videoURL)
            let duration = try await asset.load(.duration).seconds
            
            // NEW: Calculate optimal resolution based on duration and user tier
            let optimalResolution = VideoQualityAnalyzer.calculateOptimalResolution(
                duration: duration,
                userTier: userTier
            )
            
            print("🎯 PROCESSING SERVICE: \(String(format: "%.1f", duration))s video → \(Int(optimalResolution.width))x\(Int(optimalResolution.height)) for \(userTier.displayName)")
            
            // STEP 3: Analyze video for optimal settings
            await updateProgress(0.2, task: "Analyzing video quality...")
            let qualityAnalysis = try await analyzeVideoQuality(videoURL: videoURL)
            
            // STEP 4: Calculate compression settings with user tier
            await updateProgress(0.3, task: "Calculating compression settings...")
            let compressionSettings = calculateCompressionSettings(
                analysis: qualityAnalysis,
                userTier: userTier,
                targetSizeMB: targetSizeMB
            )
            
            // STEP 5: Setup export session
            await updateProgress(0.4, task: "Setting up compression...")
            
            // FIXED: Use HighestQuality preset for true 1440p quality
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw VideoProcessingError.compressionFailed("Failed to create export session")
            }
            
            // STEP 6: Configure output settings with advanced H.264/AAC encoding
            let outputURL = generateCompressedVideoURL()
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            
            // Configure video composition for better compression
            let videoComposition = try await createVideoComposition(
                asset: asset,
                settings: compressionSettings
            )
            exportSession.videoComposition = videoComposition
            
            // STEP 7: Start compression with progress tracking
            await updateProgress(0.5, task: "Compressing video...")
            
            return try await withCheckedThrowingContinuation { continuation in
                
                // Setup progress monitoring
                let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    let progress = Double(exportSession.progress)
                    let adjustedProgress = 0.5 + (progress * 0.4) // 50-90%
                    
                    Task { @MainActor in
                        self.processingProgress = adjustedProgress
                        self.currentTask = "Compressing video... \(Int(progress * 100))%"
                    }
                    
                    // Report to callback
                    progressCallback(progress)
                }
                
                // Start export
                exportSession.exportAsynchronously {
                    progressTimer.invalidate()
                    
                    Task { @MainActor in
                        await self.updateProgress(0.9, task: "Finalizing compression...")
                    }
                    
                    switch exportSession.status {
                    case .completed:
                        guard let outputURL = exportSession.outputURL else {
                            continuation.resume(throwing: VideoProcessingError.compressionFailed("No output URL"))
                            return
                        }
                        
                        Task { @MainActor in
                            await self.updateProgress(1.0, task: "Compression complete!")
                            self.isProcessing = false
                            
                            // Log success metrics with tiered compression info
                            let processingTime = Date().timeIntervalSince(startTime)
                            let originalSize = self.getFileSize(videoURL)
                            let compressedSize = self.getFileSize(outputURL)
                            let compressionRatio = Double(originalSize) / Double(compressedSize)
                            
                            print("✅ TIERED COMPRESSION: \(self.formatFileSize(originalSize)) → \(self.formatFileSize(compressedSize))")
                            print("✅ COMPRESSION RATIO: \(String(format: "%.1fx", compressionRatio))")
                            print("✅ PROCESSING TIME: \(String(format: "%.1fs", processingTime))")
                            print("✅ STRATEGY: \(VideoQualityAnalyzer.getCompressionStrategyDescription(duration: duration, userTier: userTier))")
                            
                            self.recordProcessingMetrics(
                                duration: processingTime,
                                success: true,
                                qualityScore: qualityAnalysis.qualityScores.overall,
                                error: nil
                            )
                        }
                        
                        continuation.resume(returning: outputURL)
                        
                    case .failed:
                        let error = exportSession.error ?? VideoProcessingError.compressionFailed("Export failed")
                        
                        Task { @MainActor in
                            self.isProcessing = false
                            self.lastProcessingError = error as? VideoProcessingError
                            
                            self.recordProcessingMetrics(
                                duration: Date().timeIntervalSince(startTime),
                                success: false,
                                qualityScore: 0.0,
                                error: error
                            )
                        }
                        
                        // Clean up failed output
                        if let outputURL = exportSession.outputURL {
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        
                        continuation.resume(throwing: error)
                        
                    case .cancelled:
                        Task { @MainActor in
                            self.isProcessing = false
                        }
                        
                        if let outputURL = exportSession.outputURL {
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        
                        continuation.resume(throwing: VideoProcessingError.compressionFailed("Compression cancelled"))
                        
                    default:
                        Task { @MainActor in
                            self.isProcessing = false
                        }
                        
                        continuation.resume(throwing: VideoProcessingError.compressionFailed("Unknown export status"))
                    }
                }
                
                // Set timeout for compression
                DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                    if exportSession.status == .exporting {
                        exportSession.cancelExport()
                        progressTimer.invalidate()
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.lastProcessingError = error as? VideoProcessingError
                
                self.recordProcessingMetrics(
                    duration: Date().timeIntervalSince(startTime),
                    success: false,
                    qualityScore: 0.0,
                    error: error
                )
            }
            
            throw error
        }
    }
    
    /// Check if video format is compatible with iOS
    func checkCompatibility(videoURL: URL) async throws -> CompatibilityResult {
        let asset = AVAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack("No video track found")
        }
        
        // Check codec compatibility
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let isCompatible = formatDescriptions.allSatisfy { description in
            let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
            let fourCC = String(describing: mediaSubType)
            return preferredCodecs.contains(fourCC)
        }
        
        // Check duration
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        let isDurationValid = seconds > 0.5 && seconds <= 30.0
        
        // Check resolution
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let size = naturalSize.applying(transform)
        let width = abs(size.width)
        let height = abs(size.height)
        let isResolutionValid = height >= 720 && width >= 480
        
        return CompatibilityResult(
            isCompatible: isCompatible && isDurationValid && isResolutionValid,
            formatSupported: isCompatible,
            durationValid: isDurationValid,
            resolutionValid: isResolutionValid,
            duration: seconds,
            resolution: CGSize(width: width, height: height)
        )
    }
    
    // MARK: - Private Analysis Methods
    
    /// Validates basic video file requirements
    private func validateVideoFile(_ videoURL: URL) async throws {
        // Check file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw VideoProcessingError.fileNotFound("Video file not found")
        }
        
        // Check file extension
        let fileExtension = videoURL.pathExtension.lowercased()
        guard supportedFormats.contains(fileExtension) else {
            throw VideoProcessingError.unsupportedFormat("Unsupported format: \(fileExtension)")
        }
        
        // Check file size
        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = resourceValues.fileSize ?? 0
        
        guard fileSize > 1024 else { // At least 1KB
            throw VideoProcessingError.invalidFile("File too small")
        }
        
        guard fileSize <= 100 * 1024 * 1024 else { // Max 100MB
            throw VideoProcessingError.fileTooLarge("File exceeds 100MB limit")
        }
    }
    
    /// Extracts basic video metadata
    private func extractBasicMetadata(_ videoURL: URL) async throws -> BasicVideoMetadata {
        let asset = AVAsset(url: videoURL)
        
        // Get duration
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        
        // Get file size
        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        
        // Get creation date
        let creationDate = try await asset.load(.creationDate)
        let date: Date
        if let creationDate = creationDate {
            if let dateValue = try? await creationDate.load(.dateValue) {
                date = dateValue
            } else {
                date = Date()
            }
        } else {
            date = Date()
        }
        
        // Check if file is playable
        let isPlayable = try await asset.load(.isPlayable)
        
        return BasicVideoMetadata(
            duration: seconds,
            fileSize: fileSize,
            creationDate: date,
            isPlayable: isPlayable,
            url: videoURL
        )
    }
    
    /// Analyzes video track quality
    private func analyzeVideoTracks(_ videoURL: URL) async throws -> VideoTrackAnalysis {
        let asset = AVAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack("No video track found")
        }
        
        // Get basic track info
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        
        // Calculate actual display size considering transform
        let displaySize = naturalSize.applying(preferredTransform)
        let width = abs(displaySize.width)
        let height = abs(displaySize.height)
        
        // Analyze format descriptions
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        var codecType = "unknown"
        var bitDepth = 8
        
        if let formatDescription = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
            codecType = fourCCToString(mediaSubType)
            
            // Try to get bit depth from extensions
            if let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any] {
                bitDepth = extensions["BitsPerComponent"] as? Int ?? 8
            }
        }
        
        // Calculate quality metrics
        let aspectRatio = height > 0 ? Double(width) / Double(height) : 1.0
        let pixelCount = Int(width * height)
        
        return VideoTrackAnalysis(
            resolution: CGSize(width: width, height: height),
            aspectRatio: aspectRatio,
            frameRate: Double(nominalFrameRate),
            bitrate: Double(estimatedDataRate),
            codecType: codecType,
            bitDepth: bitDepth,
            pixelCount: pixelCount
        )
    }
    
    /// Analyzes audio track quality
    private func analyzeAudioTracks(_ videoURL: URL) async throws -> AudioTrackAnalysis {
        let asset = AVAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        guard let audioTrack = audioTracks.first else {
            return AudioTrackAnalysis(
                hasAudio: false,
                sampleRate: 0,
                channelCount: 0,
                bitrate: 0,
                codecType: "none"
            )
        }
        
        // Get audio track info
        let estimatedDataRate = try await audioTrack.load(.estimatedDataRate)
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        
        var codecType = "unknown"
        var sampleRate: Double = 0
        var channelCount = 0
        
        if let formatDescription = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
            codecType = fourCCToString(mediaSubType)
            
            // Get audio stream basic description
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = audioStreamBasicDescription.pointee.mSampleRate
                channelCount = Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
            }
        }
        
        return AudioTrackAnalysis(
            hasAudio: true,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitrate: Double(estimatedDataRate),
            codecType: codecType
        )
    }
    
    /// Calculate overall quality scores
    private func calculateQualityScores(
        basic: BasicVideoMetadata,
        video: VideoTrackAnalysis,
        audio: AudioTrackAnalysis
    ) -> QualityScores {
        
        // Video quality score (0-100)
        let videoScore = VideoQualityAnalyzer.calculateQualityScore(
            resolution: video.resolution,
            bitrate: video.bitrate,
            frameRate: video.frameRate
        )
        
        // Audio quality score (0-100)
        let audioScore: Double
        if audio.hasAudio {
            let bitrateScore = min(100.0, (audio.bitrate / 128_000) * 100) // 128kbps = 100%
            let sampleRateScore = min(100.0, (audio.sampleRate / 44100) * 100) // 44.1kHz = 100%
            audioScore = (bitrateScore * 0.7) + (sampleRateScore * 0.3)
        } else {
            audioScore = 0.0
        }
        
        // Overall score (weighted average)
        let overallScore = (videoScore * 0.8) + (audioScore * 0.2)
        
        return QualityScores(
            overall: overallScore,
            video: videoScore,
            audio: audioScore
        )
    }
    
    /// Generate processing recommendations
    private func generateRecommendations(
        metadata: BasicVideoMetadata,
        video: VideoTrackAnalysis,
        audio: AudioTrackAnalysis,
        scores: QualityScores
    ) -> [ProcessingRecommendation] {
        
        var recommendations: [ProcessingRecommendation] = []
        
        // Resolution recommendations
        if video.pixelCount < 921600 { // Less than 720p
            recommendations.append(.warning("Low resolution may affect video quality"))
        } else if video.pixelCount >= 2073600 { // 1080p or higher
            recommendations.append(.success("High resolution video detected"))
        }
        
        // Frame rate recommendations
        if video.frameRate < 24 {
            recommendations.append(.warning("Frame rate too low for smooth playback"))
        } else if video.frameRate > 60 {
            recommendations.append(.info("High frame rate detected - may increase file size"))
        }
        
        // Audio recommendations
        if !audio.hasAudio {
            recommendations.append(.warning("No audio track detected"))
        } else if audio.bitrate < 64000 {
            recommendations.append(.suggestion("Audio quality could be improved"))
        }
        
        // File size recommendations
        let mbSize = Double(metadata.fileSize) / (1024 * 1024)
        if mbSize > 50 {
            recommendations.append(.warning("Large file size may affect upload time"))
        }
        
        // Overall quality
        if scores.overall >= 80 {
            recommendations.append(.success("Excellent video quality detected"))
        } else if scores.overall >= 60 {
            recommendations.append(.info("Good video quality"))
        } else {
            recommendations.append(.warning("Video quality could be improved"))
        }
        
        return recommendations
    }
    
    // MARK: - Advanced Compression Methods (UPDATED WITH USER TIER)
    
    /// Calculate optimal compression settings for target file size with user tier considerations
    /// UPDATED: Now includes userTier parameter for duration-based compression strategy
    private func calculateCompressionSettings(
        analysis: VideoQualityAnalysis,
        userTier: UserTier,
        targetSizeMB: Double
    ) -> VideoCompressionSettings {
        
        let inputVideo = VideoQualityInput(
            duration: analysis.basicMetadata.duration,
            fileSize: analysis.basicMetadata.fileSize,
            resolution: analysis.videoAnalysis.resolution,
            bitrate: analysis.videoAnalysis.bitrate,
            frameRate: analysis.videoAnalysis.frameRate,
            aspectRatio: analysis.videoAnalysis.aspectRatio
        )
        
        return VideoQualityAnalyzer.calculateCompressionSettings(
            input: inputVideo,
            targetSizeMB: targetSizeMB,
            userTier: userTier
        )
    }
    
    /// Create video composition for compression settings
    private func createVideoComposition(
        asset: AVAsset,
        settings: VideoCompressionSettings
    ) async throws -> AVMutableVideoComposition {
        
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack("No video track found")
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        
        // Apply transform to get correct orientation
        let videoSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(videoSize.width),
            height: abs(videoSize.height)
        )
        
        // Scale down if needed to meet target file size
        let scaledSize = calculateScaledSize(
            originalSize: renderSize,
            maxSize: settings.maxResolution
        )
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = scaledSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(nominalFrameRate))
        
        // Create instruction for video track
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Apply scaling and transform
        let scaleX = scaledSize.width / renderSize.width
        let scaleY = scaledSize.height / renderSize.height
        let scale = min(scaleX, scaleY)
        
        var transform = preferredTransform
        transform = transform.scaledBy(x: scale, y: scale)
        
        // Center the video
        let tx = (scaledSize.width - renderSize.width * scale) / 2
        let ty = (scaledSize.height - renderSize.height * scale) / 2
        transform = transform.translatedBy(x: tx, y: ty)
        
        transformer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        return videoComposition
    }
    
    /// Calculate scaled size maintaining aspect ratio
    private func calculateScaledSize(originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = min(widthRatio, heightRatio, 1.0) // Don't upscale
        
        return CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
    }
    
    /// Generate unique output URL for compressed video
    private func generateCompressedVideoURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "compressed_video_\(timestamp).mp4"
        return documentsPath.appendingPathComponent(filename)
    }
    
    // MARK: - Helper Methods
    
    private func updateProgress(_ progress: Double, task: String) async {
        await MainActor.run {
            self.processingProgress = progress
            self.currentTask = task
        }
    }
    
    private func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "unknown"
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
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func recordProcessingMetrics(
        duration: TimeInterval,
        success: Bool,
        qualityScore: Double,
        error: Error?
    ) {
        let metrics = ProcessingMetrics(
            timestamp: Date(),
            duration: duration,
            success: success,
            qualityScore: qualityScore,
            error: error?.localizedDescription
        )
        
        processingMetrics.append(metrics)
        
        // Keep only last 100 analyses
        if processingMetrics.count > 100 {
            processingMetrics.removeFirst()
        }
        
        print("📊 PROCESSING SERVICE: Metrics - Duration: \(String(format: "%.2f", duration))s, Quality: \(String(format: "%.1f", qualityScore))%")
    }
    
    func clearError() {
        lastProcessingError = nil
    }
}

// MARK: - Data Models (Unique to VideoProcessingService)

struct VideoQualityAnalysis {
    let basicMetadata: BasicVideoMetadata
    let videoAnalysis: VideoTrackAnalysis
    let audioAnalysis: AudioTrackAnalysis
    let qualityScores: QualityScores
    let recommendations: [ProcessingRecommendation]
    let processingTime: TimeInterval
}

struct BasicVideoMetadata {
    let duration: TimeInterval
    let fileSize: Int64
    let creationDate: Date
    let isPlayable: Bool
    let url: URL
}

struct VideoTrackAnalysis {
    let resolution: CGSize
    let aspectRatio: Double
    let frameRate: Double
    let bitrate: Double
    let codecType: String
    let bitDepth: Int
    let pixelCount: Int
}

struct AudioTrackAnalysis {
    let hasAudio: Bool
    let sampleRate: Double
    let channelCount: Int
    let bitrate: Double
    let codecType: String
}

struct QualityScores {
    let overall: Double
    let video: Double
    let audio: Double
}

struct CompatibilityResult {
    let isCompatible: Bool
    let formatSupported: Bool
    let durationValid: Bool
    let resolutionValid: Bool
    let duration: TimeInterval
    let resolution: CGSize
}

enum ProcessingRecommendation {
    case success(String)
    case info(String)
    case suggestion(String)
    case warning(String)
    
    var message: String {
        switch self {
        case .success(let msg), .info(let msg), .suggestion(let msg), .warning(let msg):
            return msg
        }
    }
    
    var type: String {
        switch self {
        case .success: return "success"
        case .info: return "info"
        case .suggestion: return "suggestion"
        case .warning: return "warning"
        }
    }
}

struct QualityThresholds {
    let minResolution = CGSize(width: 480, height: 720)
    let maxFileSize: Int64 = 100 * 1024 * 1024 // 100MB
    let minFrameRate: Double = 15.0
    let maxDuration: TimeInterval = 30.0
    let minDuration: TimeInterval = 0.5
}

enum VideoProcessingError: Error, LocalizedError {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case invalidFile(String)
    case fileTooLarge(String)
    case noVideoTrack(String)
    case analysisFailure(String)
    case compressionFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let msg): return "File Not Found: \(msg)"
        case .unsupportedFormat(let msg): return "Unsupported Format: \(msg)"
        case .invalidFile(let msg): return "Invalid File: \(msg)"
        case .fileTooLarge(let msg): return "File Too Large: \(msg)"
        case .noVideoTrack(let msg): return "No Video Track: \(msg)"
        case .analysisFailure(let msg): return "Analysis Failed: \(msg)"
        case .compressionFailed(let msg): return "Compression Failed: \(msg)"
        case .unknown(let msg): return "Unknown Error: \(msg)"
        }
    }
}

struct ProcessingMetrics {
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let qualityScore: Double
    let error: String?
}
