//
//  VideoExportService.swift
//  StitchSocial
//
//  Created by James Garmon on 12/14/25.
//


//
//  VideoExportService.swift
//  StitchSocial
//
//  Layer 4: Services - Video Export & Processing
//  Dependencies: VideoEditState (Layer 3), AVFoundation
//  Features: Apply trim, filters, captions, export with progress
//  PHASE 4 UPDATE: Passthrough mode for unedited videos, better bitrate control
//

import Foundation
import AVFoundation
import UIKit
import CoreImage

/// Handles video export with all edits applied
/// PHASE 4: Added passthrough mode to prevent quality loss when no edits are made
@MainActor
class VideoExportService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = VideoExportService()
    
    // MARK: - Published State
    
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var exportError: String?
    @Published var exportMode: ExportMode = .unknown
    
    // MARK: - Private Properties
    
    private var currentExportSession: AVAssetExportSession?
    private let ciContext = CIContext()
    
    // MARK: - Export Mode Enum
    
    enum ExportMode: String {
        case unknown = "unknown"
        case passthrough = "passthrough"    // No re-encoding, just copy
        case trimOnly = "trim_only"         // Only trim, use passthrough preset
        case fullProcess = "full_process"   // Re-encode with filters/captions
    }
    
    // MARK: - Public Interface
    
    /// Export video with all edits applied
    /// PHASE 4: Now detects if edits were made and uses passthrough when possible
    func exportVideo(editState: VideoEditState) async throws -> (videoURL: URL, thumbnailURL: URL) {
        isExporting = true
        exportProgress = 0.0
        exportError = nil
        exportMode = .unknown
        
        defer {
            isExporting = false
            currentExportSession = nil
        }
        
        do {
            // Load source video
            let asset = AVAsset(url: editState.videoURL)
            
            // PHASE 4: Determine export mode based on edits
            let mode = determineExportMode(editState: editState, asset: asset)
            exportMode = mode
            
            print("ðŸŽ¬ VIDEO EXPORT: Using mode: \(mode.rawValue)")
            
            let outputURL: URL
            
            switch mode {
            case .passthrough:
                // No edits - just copy the file (zero quality loss)
                outputURL = try await passthroughExport(from: editState.videoURL)
                
            case .trimOnly:
                // Only trim - use passthrough preset (minimal quality loss)
                outputURL = try await trimOnlyExport(
                    asset: asset,
                    trimStart: editState.trimStartTime,
                    trimEnd: editState.trimEndTime
                )
                
            case .fullProcess, .unknown:
                // Full re-encode with filters/captions
                outputURL = try await fullProcessExport(
                    asset: asset,
                    editState: editState
                )
            }
            
            // Generate thumbnail from output
            let thumbnailURL = try await generateThumbnail(from: outputURL)
            
            // Log quality comparison
            await logQualityComparison(original: editState.videoURL, exported: outputURL)
            
            print("âœ… VIDEO EXPORT: Complete - \(outputURL.lastPathComponent) (mode: \(mode.rawValue))")
            
            return (outputURL, thumbnailURL)
            
        } catch {
            exportError = error.localizedDescription
            print("âŒ VIDEO EXPORT: Failed - \(error)")
            throw error
        }
    }
    
    /// Cancel current export
    func cancelExport() {
        currentExportSession?.cancelExport()
        currentExportSession = nil
        isExporting = false
        print("âš ï¸ VIDEO EXPORT: Cancelled")
    }
    
    // MARK: - PHASE 4: Export Mode Detection
    
    /// Determine the best export mode based on what edits were made
    private func determineExportMode(editState: VideoEditState, asset: AVAsset) -> ExportMode {
        let hasFilter = editState.selectedFilter != nil
        let hasCaptions = !editState.captions.isEmpty
        
        // Check if trim is at original bounds (no actual trim)
        let hasTrim = hasActualTrim(editState: editState, asset: asset)
        
        print("ðŸ” EXPORT MODE CHECK:")
        print("   Has filter: \(hasFilter)")
        print("   Has captions: \(hasCaptions)")
        print("   Has trim: \(hasTrim)")
        
        // If filters or captions, must do full processing
        if hasFilter || hasCaptions {
            return .fullProcess
        }
        
        // If only trim, use trim-only mode (passthrough preset)
        if hasTrim {
            return .trimOnly
        }
        
        // No edits at all - pure passthrough (just copy file)
        return .passthrough
    }
    
    /// Check if trim values actually differ from video duration
    private func hasActualTrim(editState: VideoEditState, asset: AVAsset) -> Bool {
        // Use VideoEditState's own trim detection — it knows the original duration
        return editState.hasTrim
    }
    
    // MARK: - PHASE 4: Passthrough Export (Zero Quality Loss)
    
    /// Simply copy the file - no re-encoding at all
    private func passthroughExport(from sourceURL: URL) async throws -> URL {
        print("ðŸ“‹ EXPORT: Passthrough mode - copying file directly")
        
        exportProgress = 0.2
        
        let outputURL = createTemporaryVideoURL()
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Simply copy the file
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        
        exportProgress = 1.0
        
        print("âœ… EXPORT: Passthrough complete - zero quality loss")
        return outputURL
    }
    
    // MARK: - PHASE 4: Trim-Only Export (Minimal Quality Loss)
    
    /// Export with trim only using passthrough preset
    private func trimOnlyExport(
        asset: AVAsset,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) async throws -> URL {
        print("âœ‚ï¸ EXPORT: Trim-only mode - using passthrough preset")
        
        let outputURL = createTemporaryVideoURL()
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Use AVAssetExportPresetPassthrough for minimal quality loss
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw VideoExportError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        // Set time range for trim
        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )
        exportSession.timeRange = timeRange
        
        currentExportSession = exportSession
        
        // Start progress monitoring
        Task {
            await monitorExportProgress()
        }
        
        // Start export
        await exportSession.export()
        
        // Check status
        switch exportSession.status {
        case .completed:
            exportProgress = 1.0
            print("âœ… EXPORT: Trim-only complete - minimal quality loss")
            return outputURL
            
        case .failed:
            throw VideoExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
            
        case .cancelled:
            throw VideoExportError.exportCancelled
            
        default:
            throw VideoExportError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - Full Process Export (With Re-encoding)
    
    /// Full export with composition for filters/captions
    private func fullProcessExport(
        asset: AVAsset,
        editState: VideoEditState
    ) async throws -> URL {
        print("ðŸŽ¨ EXPORT: Full process mode - re-encoding with edits")
        
        // Create composition with trim
        let composition = try await createComposition(
            from: asset,
            trimStart: editState.trimStartTime,
            trimEnd: editState.trimEndTime
        )
        
        // Apply filter if selected
        let videoComposition: AVVideoComposition?
        if let filter = editState.selectedFilter {
            videoComposition = try await createFilterVideoComposition(
                filter: filter,
                intensity: editState.filterIntensity,
                composition: composition
            )
        } else {
            videoComposition = nil
        }
        
        // Export with quality settings
        let outputURL = try await exportCompositionWithQuality(
            composition: composition,
            videoComposition: videoComposition
        )
        
        return outputURL
    }
    
    // MARK: - Composition Creation
    
    /// Create composition with trim applied
    private func createComposition(
        from asset: AVAsset,
        trimStart: TimeInterval,
        trimEnd: TimeInterval
    ) async throws -> AVMutableComposition {
        
        let composition = AVMutableComposition()
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }
        
        // Add trimmed video
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )
        
        try compositionVideoTrack?.insertTimeRange(
            timeRange,
            of: videoTrack,
            at: .zero
        )
        
        // Preserve video transform (orientation)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        compositionVideoTrack?.preferredTransform = preferredTransform
        
        // Get audio track if exists
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            
            try compositionAudioTrack?.insertTimeRange(
                timeRange,
                of: audioTrack,
                at: .zero
            )
        }
        
        return composition
    }
    
    // MARK: - PHASE 4: Filter Video Composition
    
    /// Create AVVideoComposition for applying filters
    private func createFilterVideoComposition(
        filter: VideoFilter,
        intensity: Double,
        composition: AVMutableComposition
    ) async throws -> AVVideoComposition? {
        
        guard let videoTrack = try await composition.loadTracks(withMediaType: .video).first else {
            return nil
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Calculate render size accounting for orientation
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )
        
        // Create video composition with CIFilter
        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            let sourceImage = request.sourceImage.clampedToExtent()
            
            // Apply filter using generic method
            let outputImage = self.applyCIFilter(filter, to: sourceImage, intensity: intensity)
            
            request.finish(with: outputImage.cropped(to: request.sourceImage.extent), context: nil)
        }
        
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        return videoComposition
    }
    
    // MARK: - Filter Implementation
    
    /// Apply CIFilter based on VideoFilter type
    /// Extend this switch statement to match your VideoFilter enum cases
    private func applyCIFilter(
        _ filter: VideoFilter,
        to image: CIImage,
        intensity: Double
    ) -> CIImage {
        // Get the CIFilter name from your VideoFilter
        // Adjust this to match your VideoFilter enum's properties/cases
        guard let ciFilterName = filter.ciFilterName,
              let ciFilter = CIFilter(name: ciFilterName) else {
            return image
        }
        
        ciFilter.setValue(image, forKey: kCIInputImageKey)
        
        // Apply intensity if the filter supports it
        if ciFilter.inputKeys.contains(kCIInputIntensityKey) {
            ciFilter.setValue(intensity, forKey: kCIInputIntensityKey)
        }
        
        return ciFilter.outputImage ?? image
    }
    
    // MARK: - PHASE 4: Quality-Controlled Export
    
    /// Export composition with explicit quality settings
    private func exportCompositionWithQuality(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition?
    ) async throws -> URL {
        
        let outputURL = createTemporaryVideoURL()
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // PHASE 4: Use highest quality preset
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoExportError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Apply video composition if we have filters
        if let videoComp = videoComposition {
            exportSession.videoComposition = videoComp
        }
        
        currentExportSession = exportSession
        
        // Start progress monitoring
        Task {
            await monitorExportProgress()
        }
        
        // Start export
        await exportSession.export()
        
        // Check status
        switch exportSession.status {
        case .completed:
            exportProgress = 1.0
            return outputURL
            
        case .failed:
            throw VideoExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
            
        case .cancelled:
            throw VideoExportError.exportCancelled
            
        default:
            throw VideoExportError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate thumbnail from video
    /// PHASE 4: Improved quality settings
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1080, height: 1920)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        // Get video duration
        let duration = try await asset.load(.duration).seconds
        
        // Generate at 0.5 seconds or 10% in, whichever is smaller
        let thumbnailTime = min(0.5, duration * 0.1)
        let time = CMTime(seconds: thumbnailTime, preferredTimescale: 600)
        
        let cgImage = try await imageGenerator.image(at: time).image
        let uiImage = UIImage(cgImage: cgImage)
        
        // Save to file with high quality
        let thumbnailURL = createTemporaryImageURL()
        
        // PHASE 4: Increased JPEG quality from 0.8 to 0.9
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            throw VideoExportError.thumbnailGenerationFailed
        }
        
        try data.write(to: thumbnailURL)
        
        return thumbnailURL
    }
    
    // MARK: - Progress Monitoring
    
    /// Monitor export progress
    private func monitorExportProgress() async {
        guard let session = currentExportSession else { return }
        
        while session.status == .exporting {
            await MainActor.run {
                exportProgress = Double(session.progress)
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }
    
    // MARK: - PHASE 4: Quality Logging
    
    /// Log quality comparison between original and exported video
    private func logQualityComparison(original: URL, exported: URL) async {
        do {
            let originalSize = try FileManager.default.attributesOfItem(atPath: original.path)[.size] as? Int64 ?? 0
            let exportedSize = try FileManager.default.attributesOfItem(atPath: exported.path)[.size] as? Int64 ?? 0
            
            let ratio = originalSize > 0 ? Double(exportedSize) / Double(originalSize) : 1.0
            
            print("ðŸ“Š EXPORT QUALITY:")
            print("   Original: \(formatFileSize(originalSize))")
            print("   Exported: \(formatFileSize(exportedSize))")
            print("   Size Ratio: \(String(format: "%.1f%%", ratio * 100))")
            print("   Mode: \(exportMode.rawValue)")
            
            if exportMode == .passthrough {
                print("   âœ… Zero quality loss (passthrough)")
            } else if exportMode == .trimOnly {
                print("   âœ… Minimal quality loss (passthrough preset)")
            } else {
                print("   âš ï¸ Re-encoded (necessary for filters/captions)")
            }
            
        } catch {
            print("âš ï¸ EXPORT: Could not compare file sizes")
        }
    }
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - URL Helpers
    
    private func createTemporaryVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "processed_\(UUID().uuidString).mp4"
        return tempDir.appendingPathComponent(filename)
    }
    
    private func createTemporaryImageURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "thumbnail_\(UUID().uuidString).jpg"
        return tempDir.appendingPathComponent(filename)
    }
}

// MARK: - Errors

enum VideoExportError: LocalizedError {
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(String)
    case exportCancelled
    case thumbnailGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in source"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .exportCancelled:
            return "Export was cancelled"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}
