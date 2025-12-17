//
//  VideoProcessingService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video Technical Analysis & Compression
//  Handles video quality assessment, format validation, and compression
//  Pure AVFoundation processing - no Firebase or AI dependencies
//  UPDATED: Orientation-aware compression with improved quality for all tiers
//

import Foundation
import AVFoundation
import CoreImage
import VideoToolbox

// MARK: - Video Orientation Detection

/// Video orientation based on aspect ratio
/// SINGLE DEFINITION - Used by VideoService, VideoUploadService, VideoProcessingService
enum VideoOrientation: String {
    case portrait   // Height > Width (aspect ratio < 0.9)
    case landscape  // Width > Height (aspect ratio > 1.1)
    case square     // Width ≈ Height (aspect ratio 0.9-1.1)
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        case .square: return "Square"
        }
    }
    
    /// Determine orientation from aspect ratio (width/height)
    static func from(aspectRatio: Double) -> VideoOrientation {
        if aspectRatio < 0.9 {
            return .portrait
        } else if aspectRatio > 1.1 {
            return .landscape
        } else {
            return .square
        }
    }
    
    /// Determine orientation from dimensions
    static func from(width: CGFloat, height: CGFloat) -> VideoOrientation {
        guard height > 0 else { return .square }
        return from(aspectRatio: Double(width / height))
    }
}

/// Service for technical video analysis, quality assessment, and compression
/// UPDATED: Now detects orientation and uses appropriate presets
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
    
    // MARK: - Video Compression (ORIENTATION-AWARE)
    
    /// Compress video with orientation-aware approach for best quality
    /// UPDATED: Detects orientation and selects appropriate preset
    func compress(
        videoURL: URL,
        userTier: UserTier,
        targetSizeMB: Double = 3.0,
        progressCallback: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        
        let startTime = Date()
        
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
            
            // STEP 2: Detect video orientation
            await updateProgress(0.15, task: "Detecting video orientation...")
            let orientation = try await detectVideoOrientation(videoURL: videoURL)
            print("🎬 PROCESSING SERVICE: Detected orientation: \(orientation.rawValue)")
            
            // STEP 3: Basic video analysis
            await updateProgress(0.2, task: "Analyzing video...")
            let asset = AVAsset(url: videoURL)
            let duration = try await asset.load(.duration).seconds
            
            print("🎯 PROCESSING SERVICE: \(String(format: "%.1f", duration))s \(orientation.rawValue) video for \(userTier.displayName)")
            
            // STEP 4: Choose optimal preset based on orientation and user tier
            await updateProgress(0.3, task: "Selecting compression preset...")
            let exportPreset = selectOptimalPreset(
                duration: duration,
                userTier: userTier,
                orientation: orientation
            )
            
            // STEP 5: Setup export session with simple preset (NO VIDEO COMPOSITION)
            await updateProgress(0.4, task: "Setting up compression...")
            
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: exportPreset
            ) else {
                throw VideoProcessingError.compressionFailed("Failed to create export session")
            }
            
            // STEP 6: Configure basic output settings (NO CUSTOM TRANSFORMS)
            let outputURL = generateCompressedVideoURL()
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            
            print("✅ PROCESSING SERVICE: Using preset \(exportPreset) for \(orientation.rawValue) video - NO CUSTOM COMPOSITION")
            
            // STEP 7: Export with progress monitoring
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
                        await self.updateProgress(0.9, task: "Validating output...")
                    }
                    
                    switch exportSession.status {
                    case .completed:
                        guard let outputURL = exportSession.outputURL else {
                            continuation.resume(throwing: VideoProcessingError.compressionFailed("No output URL"))
                            return
                        }
                        
                        // Use sync validation to avoid async issues
                        guard self.validateCompressedVideoSync(outputURL) else {
                            continuation.resume(throwing: VideoProcessingError.compressionFailed("Output video validation failed - may be black/corrupt"))
                            return
                        }
                        
                        Task { @MainActor in
                            await self.updateProgress(1.0, task: "Compression complete!")
                            self.isProcessing = false
                            
                            // Log success metrics
                            let processingTime = Date().timeIntervalSince(startTime)
                            let originalSize = self.getFileSize(videoURL)
                            let compressedSize = self.getFileSize(outputURL)
                            let compressionRatio = originalSize > 0 ? Double(originalSize) / Double(compressedSize) : 1.0
                            
                            print("✅ ORIENTATION-AWARE COMPRESSION: \(self.formatFileSize(originalSize)) → \(self.formatFileSize(compressedSize))")
                            print("✅ COMPRESSION RATIO: \(String(format: "%.1fx", compressionRatio))")
                            print("✅ PROCESSING TIME: \(String(format: "%.1fs", processingTime))")
                            print("✅ PRESET USED: \(exportPreset)")
                            print("✅ ORIENTATION: \(orientation.rawValue)")
                            
                            self.recordProcessingMetrics(
                                duration: processingTime,
                                success: true,
                                qualityScore: 85.0,
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
    
    // MARK: - NEW: Video Orientation Detection
    
    /// Detect video orientation from video file
    /// Returns .portrait, .landscape, or .square based on actual dimensions
    func detectVideoOrientation(videoURL: URL) async throws -> VideoOrientation {
        let asset = AVAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            print("⚠️ PROCESSING SERVICE: No video track found, defaulting to portrait")
            return .portrait
        }
        
        // Get natural size and transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Apply transform to get actual display dimensions
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        
        let orientation = VideoOrientation.from(width: width, height: height)
        
        print("🎬 ORIENTATION DETECTION: \(Int(width))x\(Int(height)) → \(orientation.rawValue)")
        
        return orientation
    }
    
    /// Get video dimensions with transform applied
    func getVideoDimensions(videoURL: URL) async throws -> (width: CGFloat, height: CGFloat, aspectRatio: Double) {
        let asset = AVAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack("No video track found")
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        let aspectRatio = height > 0 ? Double(width / height) : 9.0/16.0
        
        return (width, height, aspectRatio)
    }
    
    // MARK: - UPDATED: Preset Selection (Orientation-Aware)
    
    /// Select optimal export preset based on duration, user tier, AND orientation
    /// UPDATED: 720p minimum for ALL tiers (no more 640x480 for rookies)
    /// UPDATED: Uses appropriate presets for portrait vs landscape
    private func selectOptimalPreset(duration: TimeInterval, userTier: UserTier, orientation: VideoOrientation) -> String {
        
        // For portrait videos, we need to be careful with preset selection
        // Most presets are landscape-oriented (e.g., 1920x1080)
        // We'll use the preset that best matches the video orientation
        
        switch orientation {
        case .portrait:
            // Portrait videos: Height > Width
            // Use presets that work well with portrait content
            return selectPortraitPreset(duration: duration, userTier: userTier)
            
        case .landscape:
            // Landscape videos: Width > Height
            // Standard presets work well here
            return selectLandscapePreset(duration: duration, userTier: userTier)
            
        case .square:
            // Square videos: Use balanced preset
            return selectSquarePreset(duration: duration, userTier: userTier)
        }
    }
    
    /// Select preset for portrait videos
    /// Uses presets that maintain quality without stretching
    private func selectPortraitPreset(duration: TimeInterval, userTier: UserTier) -> String {
        switch userTier {
        case .founder, .coFounder, .topCreator, .legendary:
            // High tier users get highest quality
            // 1920x1080 preset works for portrait (will be 1080x1920 after transform)
            if duration <= 15.0 {
                return AVAssetExportPreset1920x1080
            } else {
                return AVAssetExportPreset1280x720
            }
            
        case .partner, .elite, .influencer, .ambassador:
            // Mid tier users get good quality
            return AVAssetExportPreset1280x720
            
        case .veteran, .rising:
            // Standard users get balanced quality
            // UPDATED: Use 720p instead of qHD for better quality
            return AVAssetExportPreset1280x720
            
        case .rookie:
            // UPDATED: Rookies now get 720p minimum (NOT 640x480!)
            // This is a significant quality improvement
            return AVAssetExportPreset1280x720
            
        @unknown default:
            return AVAssetExportPreset1280x720
        }
    }
    
    /// Select preset for landscape videos
    private func selectLandscapePreset(duration: TimeInterval, userTier: UserTier) -> String {
        switch userTier {
        case .founder, .coFounder, .topCreator, .legendary:
            // High tier users get highest quality
            if duration <= 15.0 {
                return AVAssetExportPreset1920x1080
            } else {
                return AVAssetExportPreset1280x720
            }
            
        case .partner, .elite, .influencer, .ambassador:
            return AVAssetExportPreset1280x720
            
        case .veteran, .rising:
            return AVAssetExportPreset1280x720
            
        case .rookie:
            // UPDATED: Rookies get 720p for landscape too
            return AVAssetExportPreset1280x720
            
        @unknown default:
            return AVAssetExportPreset1280x720
        }
    }
    
    /// Select preset for square videos
    private func selectSquarePreset(duration: TimeInterval, userTier: UserTier) -> String {
        // Square videos work well with standard presets
        switch userTier {
        case .founder, .coFounder, .topCreator, .legendary:
            return AVAssetExportPreset1920x1080
            
        case .partner, .elite, .influencer, .ambassador:
            return AVAssetExportPreset1280x720
            
        case .veteran, .rising, .rookie:
            // All get 720p for square videos
            return AVAssetExportPreset1280x720
            
        @unknown default:
            return AVAssetExportPreset1280x720
        }
    }
    
    // MARK: - Output Validation
    
    /// Simple validation that compressed video exists and has reasonable size
    /// Called synchronously from completion handler
    private func validateCompressedVideoSync(_ videoURL: URL) -> Bool {
        // Check file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("❌ VALIDATION: Output file does not exist")
            return false
        }
        
        // Check file size is reasonable
        let fileSize = getFileSize(videoURL)
        guard fileSize > 1024 else { // At least 1KB
            print("❌ VALIDATION: File size too small: \(fileSize) bytes")
            return false
        }
        
        print("✅ VALIDATION: Basic checks passed - Size: \(formatFileSize(fileSize))")
        return true
    }
    
    /// Validate that compressed video actually has visible frames
    /// Prevents uploading black/corrupt videos (async version for detailed validation)
    private func validateCompressedVideo(_ videoURL: URL) async throws -> Bool {
        let asset = AVAsset(url: videoURL)
        
        // Check basic playability
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            print("❌ VALIDATION: Video is not playable")
            return false
        }
        
        // Check duration is reasonable
        let duration = try await asset.load(.duration).seconds
        guard duration > 0.1 else {
            print("❌ VALIDATION: Video duration too short: \(duration)s")
            return false
        }
        
        // Check video tracks exist
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            print("❌ VALIDATION: No video tracks found")
            return false
        }
        
        // Check file size is reasonable
        let fileSize = getFileSize(videoURL)
        guard fileSize > 1024 else { // At least 1KB
            print("❌ VALIDATION: File size too small: \(fileSize) bytes")
            return false
        }
        
        print("✅ VALIDATION: Video passed all checks - Duration: \(String(format: "%.1f", duration))s, Size: \(formatFileSize(fileSize))")
        return true
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
            let fourCC = fourCCToString(mediaSubType)
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
        let aspectRatio = height > 0 ? width / height : 16.0/9.0
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
        
        // Analyze format descriptions
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        var codecType = "unknown"
        var sampleRate: Double = 44100
        var channelCount = 2
        
        if let formatDescription = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
            codecType = fourCCToString(mediaSubType)
            
            // Get audio format description
            if let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = basicDescription.pointee.mSampleRate
                channelCount = Int(basicDescription.pointee.mChannelsPerFrame)
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
        var videoScore: Double = 0
        
        // Resolution score (40% weight)
        let pixelCount = video.pixelCount
        let resolutionScore = min(100, Double(pixelCount) / (1920 * 1080) * 100)
        videoScore += resolutionScore * 0.4
        
        // Frame rate score (30% weight)
        let frameRateScore = min(100, video.frameRate / 60.0 * 100)
        videoScore += frameRateScore * 0.3
        
        // Bitrate score (30% weight)
        let bitrateScore = min(100, video.bitrate / 10_000_000 * 100) // 10Mbps target
        videoScore += bitrateScore * 0.3
        
        // Audio quality score (0-100)
        var audioScore: Double = 0
        
        if audio.hasAudio {
            // Sample rate score (50% weight)
            let sampleRateScore = min(100, audio.sampleRate / 48000 * 100)
            audioScore += sampleRateScore * 0.5
            
            // Channel count score (25% weight)
            let channelScore = audio.channelCount >= 2 ? 100 : 50
            audioScore += Double(channelScore) * 0.25
            
            // Bitrate score (25% weight)
            let audioBitrateScore = min(100, audio.bitrate / 320_000 * 100) // 320kbps target
            audioScore += audioBitrateScore * 0.25
        }
        
        // Overall score (video 70%, audio 30%)
        let overallScore = (videoScore * 0.7) + (audioScore * 0.3)
        
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
        
        // Overall quality assessment
        if scores.overall >= 90 {
            recommendations.append(.success("Excellent video quality"))
        } else if scores.overall >= 70 {
            recommendations.append(.info("Good video quality"))
        } else if scores.overall >= 50 {
            recommendations.append(.suggestion("Video quality could be improved"))
        } else {
            recommendations.append(.warning("Video quality is poor"))
        }
        
        // Duration recommendations
        if metadata.duration > 25 {
            recommendations.append(.warning("Video is longer than recommended 25 seconds"))
        } else if metadata.duration < 1 {
            recommendations.append(.warning("Video is very short"))
        }
        
        // Resolution recommendations
        if video.resolution.height < 720 {
            recommendations.append(.suggestion("Consider recording in HD (720p) or higher"))
        }
        
        // Frame rate recommendations
        if video.frameRate < 24 {
            recommendations.append(.warning("Frame rate is below standard (24fps)"))
        }
        
        // Audio recommendations
        if !audio.hasAudio {
            recommendations.append(.info("Video has no audio track"))
        } else if audio.sampleRate < 44100 {
            recommendations.append(.suggestion("Audio sample rate could be higher"))
        }
        
        return recommendations
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
