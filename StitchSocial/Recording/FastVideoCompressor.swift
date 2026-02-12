//
//  FastVideoCompressor.swift
//  StitchSocial
//
//  Layer 4: Services - CapCut-Style Fast Video Compression
//  Uses AVAssetWriter with VideoToolbox hardware acceleration
//  Target: 150MB â†’ 30MB in ~5-10 seconds
//
//  Key Differences from AVAssetExportSession:
//  1. Direct hardware encoder access via VideoToolbox
//  2. Real-time bitrate control for target file size
//  3. Single-pass encoding (faster than 2-pass)
//  4. HEVC (H.265) for 40% better compression than H.264
//
//  ðŸ”§ FIXED: Preserves source aspect ratio (no more cropped uploads!)
//

import Foundation
import AVFoundation
import VideoToolbox
import UIKit

/// CapCut-style fast video compression with hardware acceleration
/// Compresses 150MB â†’ 30MB in ~5-10 seconds using HEVC + VideoToolbox
@MainActor
class FastVideoCompressor: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FastVideoCompressor()
    
    // MARK: - Published State
    
    @Published var isCompressing = false
    @Published var progress: Double = 0.0
    @Published var currentPhase: CompressionPhase = .idle
    @Published var lastError: String?
    
    // MARK: - Configuration
    
    /// Target file size in bytes (default 50MB for safe upload margin)
    var targetFileSizeBytes: Int64 = 50 * 1024 * 1024
    
    /// Maximum file size allowed (100MB upload limit)
    static let maxUploadSize: Int64 = 100 * 1024 * 1024
    
    /// Minimum bitrate floor (prevents unwatchable quality)
    private let minBitrate: Int = 800_000  // 800 kbps
    
    /// Maximum bitrate ceiling
    private let maxBitrate: Int = 8_000_000  // 8 Mbps
    
    // MARK: - Compression Phase
    
    enum CompressionPhase: String {
        case idle = "Ready"
        case analyzing = "Analyzing video..."
        case compressing = "Compressing..."
        case finalizing = "Finalizing..."
        case complete = "Complete"
        case failed = "Failed"
    }
    
    // MARK: - Compression Result
    
    struct CompressionResult {
        let outputURL: URL
        let originalSize: Int64
        let compressedSize: Int64
        let compressionRatio: Double
        let duration: TimeInterval
        let processingTime: TimeInterval
        let codec: String
        let resolution: CGSize
        let bitrate: Int
    }
    
    // MARK: - Public Interface
    
    /// Compress video to target size with hardware acceleration
    /// - Parameters:
    ///   - sourceURL: Original video file
    ///   - targetSizeMB: Target size in megabytes (default: 50MB)
    ///   - preserveResolution: If true, keeps original resolution (slower). If false, may downscale for speed.
    ///   - trimRange: Optional time range to trim during compression (saves re-encoding)
    func compress(
        sourceURL: URL,
        targetSizeMB: Double = 50.0,
        preserveResolution: Bool = false,
        trimRange: CMTimeRange? = nil,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws -> CompressionResult {
        
        let startTime = Date()
        
        isCompressing = true
        progress = 0.0
        currentPhase = .analyzing
        lastError = nil
        
        defer {
            isCompressing = false
        }
        
        do {
            // Step 1: Analyze source video
            let sourceInfo = try await analyzeVideo(url: sourceURL)
            let targetBytes = Int64(targetSizeMB * 1024 * 1024)
            
            print("ðŸŽ¬ FAST COMPRESS: Source \(formatBytes(sourceInfo.fileSize)) â†’ Target \(formatBytes(targetBytes))")
            print("ðŸŽ¬ FAST COMPRESS: Duration \(String(format: "%.1f", sourceInfo.duration))s, Resolution \(Int(sourceInfo.resolution.width))x\(Int(sourceInfo.resolution.height))")
            
            // Step 2: Check if compression is needed
            if sourceInfo.fileSize <= targetBytes {
                print("âœ… FAST COMPRESS: Already under target, copying file")
                let outputURL = try copyToOutput(sourceURL)
                
                return CompressionResult(
                    outputURL: outputURL,
                    originalSize: sourceInfo.fileSize,
                    compressedSize: sourceInfo.fileSize,
                    compressionRatio: 1.0,
                    duration: sourceInfo.duration,
                    processingTime: Date().timeIntervalSince(startTime),
                    codec: "passthrough",
                    resolution: sourceInfo.resolution,
                    bitrate: Int(sourceInfo.bitrate)
                )
            }
            
            // Step 3: Calculate optimal settings
            currentPhase = .compressing
            let settings = calculateOptimalSettings(
                sourceInfo: sourceInfo,
                targetBytes: targetBytes,
                preserveResolution: preserveResolution
            )
            
            print("ðŸŽ¬ FAST COMPRESS: Using \(settings.codec) @ \(settings.bitrate / 1000)kbps, \(Int(settings.resolution.width))x\(Int(settings.resolution.height))")
            
            // Step 4: Perform hardware-accelerated compression
            let outputURL = try await performHardwareCompression(
                sourceURL: sourceURL,
                sourceInfo: sourceInfo,
                settings: settings,
                trimRange: trimRange,
                progressCallback: { [weak self] p in
                    Task { @MainActor in
                        self?.progress = p
                        progressCallback?(p)
                    }
                }
            )
            
            // Step 5: Verify output
            currentPhase = .finalizing
            let outputSize = try getFileSize(outputURL)
            let processingTime = Date().timeIntervalSince(startTime)
            
            currentPhase = .complete
            progress = 1.0
            
            let result = CompressionResult(
                outputURL: outputURL,
                originalSize: sourceInfo.fileSize,
                compressedSize: outputSize,
                compressionRatio: Double(sourceInfo.fileSize) / Double(outputSize),
                duration: sourceInfo.duration,
                processingTime: processingTime,
                codec: settings.codec,
                resolution: settings.resolution,
                bitrate: settings.bitrate
            )
            
            print("âœ… FAST COMPRESS: \(formatBytes(sourceInfo.fileSize)) â†’ \(formatBytes(outputSize)) in \(String(format: "%.1f", processingTime))s")
            print("âœ… FAST COMPRESS: \(String(format: "%.1f", result.compressionRatio))x compression ratio")
            
            return result
            
        } catch {
            currentPhase = .failed
            lastError = error.localizedDescription
            print("âŒ FAST COMPRESS: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Quick compress for immediate use (optimized for speed over size)
    func quickCompress(sourceURL: URL) async throws -> URL {
        let result = try await compress(
            sourceURL: sourceURL,
            targetSizeMB: 80.0,  // Higher target = faster
            preserveResolution: false
        )
        return result.outputURL
    }
    
    // MARK: - Video Analysis
    
    private struct VideoInfo {
        let duration: TimeInterval
        let fileSize: Int64
        let resolution: CGSize       // Display size (after transform)
        let naturalResolution: CGSize // Raw buffer size (before transform)
        let bitrate: Double
        let frameRate: Double
        let hasAudio: Bool
    }
    
    private func analyzeVideo(url: URL) async throws -> VideoInfo {
        let asset = AVAsset(url: url)
        
        // Load all properties in parallel
        async let durationLoad = asset.load(.duration)
        async let tracksLoad = asset.loadTracks(withMediaType: .video)
        async let audioTracksLoad = asset.loadTracks(withMediaType: .audio)
        
        let duration = try await durationLoad
        let videoTracks = try await tracksLoad
        let audioTracks = try await audioTracksLoad
        
        guard let videoTrack = videoTracks.first else {
            throw CompressionError.noVideoTrack
        }
        
        // Get video properties
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        
        // Calculate actual display size (accounting for rotation)
        let transformedSize = naturalSize.applying(transform)
        let resolution = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )
        
        // Get file size
        let fileSize = try getFileSize(url)
        
        // Calculate actual bitrate
        let durationSeconds = CMTimeGetSeconds(duration)
        let bitrate = durationSeconds > 0 ? Double(fileSize * 8) / durationSeconds : Double(estimatedDataRate)
        
        return VideoInfo(
            duration: durationSeconds,
            fileSize: fileSize,
            resolution: resolution,
            naturalResolution: naturalSize,
            bitrate: bitrate,
            frameRate: Double(nominalFrameRate),
            hasAudio: !audioTracks.isEmpty
        )
    }
    
    // MARK: - Optimal Settings Calculation
    
    private struct CompressionSettings {
        let resolution: CGSize        // Display resolution (for logging/result)
        let writerResolution: CGSize  // Raw buffer resolution (for AVAssetWriterInput)
        let bitrate: Int
        let frameRate: Int
        let codec: String
        let useHEVC: Bool
        let keyFrameInterval: Int
    }
    
    private func calculateOptimalSettings(
        sourceInfo: VideoInfo,
        targetBytes: Int64,
        preserveResolution: Bool
    ) -> CompressionSettings {
        
        // Calculate target bitrate to achieve file size
        // Formula: bitrate = (targetBytes * 8) / duration - audioBitrate
        let audioBitrate = sourceInfo.hasAudio ? 128_000 : 0  // 128kbps AAC
        let targetTotalBitrate = Int((Double(targetBytes * 8) / sourceInfo.duration))
        var targetVideoBitrate = targetTotalBitrate - audioBitrate
        
        // Clamp bitrate to reasonable bounds
        targetVideoBitrate = max(minBitrate, min(maxBitrate, targetVideoBitrate))
        
        // Determine optimal DISPLAY resolution based on bitrate budget
        let displayResolution: CGSize
        if preserveResolution {
            displayResolution = sourceInfo.resolution
        } else {
            displayResolution = selectResolutionForBitrate(
                targetBitrate: targetVideoBitrate,
                sourceResolution: sourceInfo.resolution
            )
        }
        
        // FIXED: Calculate WRITER resolution from naturalResolution (raw buffer dims)
        // The writer receives raw pixel buffers at naturalSize dimensions,
        // NOT the transformed/display dimensions. The transform is applied separately
        // via videoInput.transform. Using display dimensions here causes
        // dimension mismatch → black bars / pillarboxing.
        let writerResolution: CGSize
        if preserveResolution {
            writerResolution = sourceInfo.naturalResolution
        } else {
            // Scale naturalResolution by the same factor as display resolution
            let displayScale = max(displayResolution.width, displayResolution.height) / max(sourceInfo.resolution.width, sourceInfo.resolution.height)
            let scaledWidth = sourceInfo.naturalResolution.width * displayScale
            let scaledHeight = sourceInfo.naturalResolution.height * displayScale
            // Ensure even dimensions
            writerResolution = CGSize(
                width: CGFloat(Int(scaledWidth) & ~1),
                height: CGFloat(Int(scaledHeight) & ~1)
            )
        }
        
        print("📐 COMPRESSION: Display \(Int(displayResolution.width))x\(Int(displayResolution.height)), Writer \(Int(writerResolution.width))x\(Int(writerResolution.height))")
        
        // Use HEVC for better compression (40% smaller than H.264)
        // Fall back to H.264 if HEVC would be too slow
        let useHEVC = targetVideoBitrate < 4_000_000  // Use HEVC for lower bitrates
        
        // Frame rate: keep original up to 30fps, cap at 30 for compression
        let frameRate = min(30, Int(sourceInfo.frameRate))
        
        // Key frame interval: 2 seconds (good for seeking + compression)
        let keyFrameInterval = frameRate * 2
        
        return CompressionSettings(
            resolution: displayResolution,
            writerResolution: writerResolution,
            bitrate: targetVideoBitrate,
            frameRate: frameRate,
            codec: useHEVC ? "HEVC" : "H.264",
            useHEVC: useHEVC,
            keyFrameInterval: keyFrameInterval
        )
    }
    
    private func selectResolutionForBitrate(targetBitrate: Int, sourceResolution: CGSize) -> CGSize {
        // ðŸ”§ FIXED: Preserve source aspect ratio instead of forcing portrait dimensions
        
        // Calculate source aspect ratio
        let sourceAspectRatio = sourceResolution.width / sourceResolution.height
        
        // Resolution tiers based on the LONGER dimension
        // This works for both portrait and landscape videos
        let maxDimensionTiers: [(CGFloat, Int)] = [
            (1920, 2_000_000),  // 1080p needs 2Mbps+
            (1280, 1_000_000),  // 720p needs 1Mbps+
            (960, 600_000),     // 540p needs 600kbps+
            (854, 400_000),     // 480p minimum
        ]
        
        // Find the max dimension of source
        let sourceMaxDimension = max(sourceResolution.width, sourceResolution.height)
        
        // Find highest resolution tier that fits bitrate budget
        var targetMaxDimension: CGFloat = 854  // Default fallback
        for (maxDim, minBitrate) in maxDimensionTiers {
            if targetBitrate >= minBitrate {
                // Don't upscale
                targetMaxDimension = min(maxDim, sourceMaxDimension)
                break
            }
        }
        
        // Calculate output dimensions preserving aspect ratio
        let scaleFactor = targetMaxDimension / sourceMaxDimension
        let outputWidth = sourceResolution.width * scaleFactor
        let outputHeight = sourceResolution.height * scaleFactor
        
        // Ensure dimensions are even (required for video encoding)
        let evenWidth = CGFloat(Int(outputWidth) & ~1)
        let evenHeight = CGFloat(Int(outputHeight) & ~1)
        
        print("ðŸ“ COMPRESSION: Preserving aspect ratio \(String(format: "%.3f", sourceAspectRatio))")
        print("ðŸ“ COMPRESSION: \(Int(sourceResolution.width))x\(Int(sourceResolution.height)) â†’ \(Int(evenWidth))x\(Int(evenHeight))")
        
        return CGSize(width: evenWidth, height: evenHeight)
    }
    
    // MARK: - Hardware Compression (AVAssetWriter + VideoToolbox)
    
    private func performHardwareCompression(
        sourceURL: URL,
        sourceInfo: VideoInfo,
        settings: CompressionSettings,
        trimRange: CMTimeRange?,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> URL {
        
        let asset = AVAsset(url: sourceURL)
        let outputURL = createOutputURL()
        
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Get source tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressionError.noVideoTrack
        }
        
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        // FIXED: Use AVAssetReaderVideoCompositionOutput to pre-apply the transform
        // This bakes the rotation into the pixel data so the output file has
        // correctly oriented pixels with an identity transform.
        // Previously used AVAssetReaderTrackOutput which reads raw (unrotated) buffers,
        // then set videoInput.transform as metadata — but many apps ignore that metadata.
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Create a composition that applies the transform
        let readerComposition = AVMutableComposition()
        guard let compTrack = readerComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompressionError.noVideoTrack
        }
        
        let fullRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        try compTrack.insertTimeRange(
            trimRange ?? fullRange,
            of: videoTrack,
            at: .zero
        )
        compTrack.preferredTransform = preferredTransform
        
        // Build a video composition that forces the transform into pixels
        let videoComposition = AVMutableVideoComposition()
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )
        videoComposition.renderSize = renderSize
        
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let fps: Int32 = nominalFrameRate > 0 ? Int32(round(nominalFrameRate)) : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: readerComposition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Create composition-based reader (reads pre-rotated frames at display resolution)
        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        
        // We need a new reader for the composition
        let compositionReader = try AVAssetReader(asset: readerComposition)
        if let range = trimRange {
            // Trim already applied via insertTimeRange, but set reader range to full composition
        }
        
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: readerComposition.tracks(withMediaType: .video),
            videoSettings: videoReaderSettings
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        compositionReader.add(videoOutput)
        
        // Configure audio reader output (if present) — use original asset reader
        var audioOutput: AVAssetReaderTrackOutput?
        let audioReader: AVAssetReader? // Separate reader for audio from original asset
        if let audioTrack = audioTracks.first {
            let audioAssetReader = try AVAssetReader(asset: asset)
            if let range = trimRange {
                audioAssetReader.timeRange = range
            }
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2
            ]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
            output.alwaysCopiesSampleData = false
            audioAssetReader.add(output)
            audioOutput = output
            audioReader = audioAssetReader
        } else {
            audioReader = nil
        }
        
        // Create asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Configure video writer input — use DISPLAY dimensions since reader now outputs rotated frames
        // Override writerResolution with display resolution for this flow
        let writerWidth = Int(settings.resolution.width) & ~1
        let writerHeight = Int(settings.resolution.height) & ~1
        
        var videoWriterSettings = createVideoWriterSettings(settings: settings, sourceInfo: sourceInfo)
        // Override with display dimensions since reader outputs pre-rotated frames
        videoWriterSettings[AVVideoWidthKey] = writerWidth
        videoWriterSettings[AVVideoHeightKey] = writerHeight
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoInput.expectsMediaDataInRealTime = false
        // NO transform — pixels are already rotated
        
        print("📐 COMPRESSOR: naturalSize=\(naturalSize), renderSize=\(renderSize), writerDims=\(writerWidth)x\(writerHeight), fps=\(fps)")
        
        writer.add(videoInput)
        
        // Configure audio writer input (if present)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let audioWriterSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }
        
        // Start reading and writing
        guard compositionReader.startReading() else {
            throw CompressionError.readerFailed(compositionReader.error?.localizedDescription ?? "Unknown")
        }
        
        if let audioReader = audioReader {
            guard audioReader.startReading() else {
                throw CompressionError.readerFailed(audioReader.error?.localizedDescription ?? "Unknown")
            }
        }
        
        guard writer.startWriting() else {
            throw CompressionError.writerFailed(writer.error?.localizedDescription ?? "Unknown")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Process frames
        let totalDuration = trimRange?.duration.seconds ?? sourceInfo.duration
        var processedDuration: Double = 0
        
        return try await withCheckedThrowingContinuation { continuation in
            let group = DispatchGroup()
            var encodeError: Error?
            
            // Video encoding
            group.enter()
            videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.encode")) {
                while videoInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                        videoInput.append(sampleBuffer)
                        
                        // Update progress
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        processedDuration = pts.seconds - (trimRange?.start.seconds ?? 0)
                        let progress = min(1.0, processedDuration / totalDuration)
                        progressCallback(progress * 0.95)  // Reserve 5% for finalization
                        
                    } else {
                        videoInput.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
            
            // Audio encoding (if present)
            if let audioOutput = audioOutput, let audioInput = audioInput {
                group.enter()
                audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.encode")) {
                    while audioInput.isReadyForMoreMediaData {
                        if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                            audioInput.append(sampleBuffer)
                        } else {
                            audioInput.markAsFinished()
                            group.leave()
                            break
                        }
                    }
                }
            }
            
            // Wait for completion
            group.notify(queue: .main) {
                if compositionReader.status == .failed {
                    encodeError = CompressionError.readerFailed(compositionReader.error?.localizedDescription ?? "Unknown")
                }
                
                writer.finishWriting {
                    progressCallback(1.0)
                    
                    if let error = encodeError {
                        continuation.resume(throwing: error)
                    } else if writer.status == .failed {
                        continuation.resume(throwing: CompressionError.writerFailed(writer.error?.localizedDescription ?? "Unknown"))
                    } else {
                        continuation.resume(returning: outputURL)
                    }
                }
            }
        }
    }
    
    private func createVideoWriterSettings(settings: CompressionSettings, sourceInfo: VideoInfo) -> [String: Any] {
        // Use hardware-accelerated codec
        let codecKey = settings.useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264
        
        // FIXED: Use writerResolution (raw buffer dimensions, NOT display dimensions)
        // AVAssetReaderTrackOutput produces pixel buffers at naturalSize,
        // so the writer must match. The transform handles orientation separately.
        let width = Int(settings.writerResolution.width) & ~1
        let height = Int(settings.writerResolution.height) & ~1
        
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitrate,
            AVVideoMaxKeyFrameIntervalKey: settings.keyFrameInterval,
            AVVideoAllowFrameReorderingKey: false,  // Faster encoding
        ]
        
        // HEVC-specific settings
        if settings.useHEVC {
            compressionProperties[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        } else {
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        
        // Enable hardware acceleration (VideoToolbox)
        compressionProperties[kVTCompressionPropertyKey_RealTime as String] = false
        compressionProperties[kVTCompressionPropertyKey_AllowTemporalCompression as String] = true
        
        return [
            AVVideoCodecKey: codecKey,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
    }
    
    // MARK: - Helper Methods
    
    private func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func copyToOutput(_ sourceURL: URL) throws -> URL {
        let outputURL = createOutputURL()
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        return outputURL
    }
    
    private func createOutputURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Errors

enum CompressionError: LocalizedError {
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case fileTooLarge(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found"
        case .readerFailed(let msg):
            return "Failed to read video: \(msg)"
        case .writerFailed(let msg):
            return "Failed to write video: \(msg)"
        case .fileTooLarge(let msg):
            return msg
        case .cancelled:
            return "Compression cancelled"
        }
    }
}

// MARK: - Convenience Extensions

extension FastVideoCompressor {
    
    /// Compress with trim in single pass (most efficient)
    func compressWithTrim(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        targetSizeMB: Double = 50.0
    ) async throws -> CompressionResult {
        
        let trimRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
        
        return try await compress(
            sourceURL: sourceURL,
            targetSizeMB: targetSizeMB,
            preserveResolution: false,
            trimRange: trimRange
        )
    }
    
    /// Check if video needs compression
    func needsCompression(_ url: URL, maxSizeMB: Double = 100.0) -> Bool {
        guard let size = try? getFileSize(url) else { return true }
        return size > Int64(maxSizeMB * 1024 * 1024)
    }
}
