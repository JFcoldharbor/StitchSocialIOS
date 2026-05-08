//
//  VideoExportService.swift
//  StitchSocial
//
//  Layer 4: Video Export & Processing
//
//  ARCHITECTURE:
//  - Three export modes: passthrough (copy), trimOnly (no re-encode), fullProcess (filters/captions)
//  - All exports use export(to:as:) async throws (not deprecated export() or exportAsynchronously)
//  - AVURLAsset everywhere (not deprecated AVAsset(url:))
//  - Progress via async polling loop (not Timer)
//  - Filter composition via AVVideoComposition async init (iOS 18+)
//
//  CACHING: None persistent — export is one-shot
//  CLEANUP: Temp files use UUID naming, cleaned by caller
//

import Foundation
import AVFoundation
import UIKit
import CoreImage

@MainActor
class VideoExportService: ObservableObject {

    static let shared = VideoExportService()

    // MARK: - Published State
    @Published var isExporting = false
    @Published var exportProgress = 0.0
    @Published var exportError: String?
    @Published var exportMode: ExportMode = .unknown

    // MARK: - Private
    private var currentExportSession: AVAssetExportSession?
    private let ciContext = CIContext()

    enum ExportMode: String {
        case unknown, passthrough, trimOnly = "trim_only", fullProcess = "full_process"
    }

    // MARK: - Public Export

    func exportVideo(editState: VideoEditState) async throws -> (videoURL: URL, thumbnailURL: URL) {
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportMode = .unknown

        defer {
            isExporting = false
            currentExportSession = nil
        }

        do {
            let asset = AVURLAsset(url: editState.videoURL)
            let mode = determineExportMode(editState: editState)
            exportMode = mode
            #if DEBUG
            print("🎬 EXPORT: Mode = \(mode.rawValue)")
            #endif

            let outputURL: URL
            switch mode {
            case .passthrough:
                outputURL = try await passthroughExport(from: editState.videoURL)
            case .trimOnly:
                outputURL = try await trimOnlyExport(asset: asset, trimStart: editState.trimStartTime, trimEnd: editState.trimEndTime)
            case .fullProcess, .unknown:
                outputURL = try await fullProcessExport(asset: asset, editState: editState)
            }

            let thumbnailURL = try await generateThumbnail(from: outputURL)
            await logQualityComparison(original: editState.videoURL, exported: outputURL)
            #if DEBUG
            print("✅ EXPORT: Complete — \(outputURL.lastPathComponent)")
            #endif
            return (outputURL, thumbnailURL)
        } catch {
            exportError = error.localizedDescription
            throw error
        }
    }

    func cancelExport() {
        currentExportSession?.cancelExport()
        currentExportSession = nil
        isExporting = false
    }

    // MARK: - Mode Detection

    private func determineExportMode(editState: VideoEditState) -> ExportMode {
        let hasFilter = editState.selectedFilter != nil
        let hasCaptions = editState.captionsEnabled && !editState.captions.isEmpty
        let hasOverlays = !editState.textOverlays.isEmpty

        if hasFilter || hasCaptions || hasOverlays { return .fullProcess }
        if editState.hasTrim { return .trimOnly }
        return .passthrough
    }

    // MARK: - Passthrough (zero quality loss)

    private func passthroughExport(from sourceURL: URL) async throws -> URL {
        exportProgress = 0.2
        let outputURL = tempVideoURL()
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        exportProgress = 1.0
        return outputURL
    }

    // MARK: - Trim Only (passthrough preset)

    private func trimOnlyExport(asset: AVAsset, trimStart: TimeInterval, trimEnd: TimeInterval) async throws -> URL {
        let outputURL = tempVideoURL()
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoExportError.exportSessionCreationFailed
        }

        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        currentExportSession = session
        let progressTask = monitorProgress()

        try await session.export(to: outputURL, as: .mp4)
        progressTask.cancel()
        exportProgress = 1.0
        return outputURL
    }

    // MARK: - Full Process (re-encode with edits)

    private func fullProcessExport(asset: AVAsset, editState: VideoEditState) async throws -> URL {
        let composition = try await createComposition(from: asset, trimStart: editState.trimStartTime, trimEnd: editState.trimEndTime)

        let hasFilter = editState.selectedFilter != nil
        let hasOverlays = !editState.textOverlays.isEmpty
        let hasCaptions = editState.captionsEnabled && !editState.captions.isEmpty
        let needsAnimTool = hasOverlays || hasCaptions

        var videoComposition: AVVideoComposition?

        if needsAnimTool {
            let renderSize = try await getRenderSize(from: composition)
            let mvc = try await buildBaseVideoComposition(from: composition, renderSize: renderSize)
            mvc.animationTool = buildCombinedAnimationTool(
                overlays: editState.textOverlays,
                // Override per-caption position with the user-chosen global so
                // every caption ends up at the same spot in the export.
                captions: editState.captionsEnabled ? editState.captions.map { c in
                    var copy = c
                    copy.position = editState.globalCaptionPosition
                    return copy
                } : [],
                renderSize: renderSize,
                duration: composition.duration
            )
            videoComposition = mvc
        } else if hasFilter, let filter = editState.selectedFilter {
            videoComposition = try await createFilterVideoComposition(filter: filter, intensity: editState.filterIntensity, composition: composition)
        }

        let outputURL = try await exportComposition(composition: composition, videoComposition: videoComposition)

        // Second pass for filter + overlays combo
        if hasFilter && needsAnimTool, let filter = editState.selectedFilter {
            return try await applyFilterPostProcess(videoURL: outputURL, filter: filter, intensity: editState.filterIntensity)
        }

        return outputURL
    }

    // MARK: - Composition Creation

    private func createComposition(from asset: AVAsset, trimStart: TimeInterval, trimEnd: TimeInterval) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compVideo?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compVideo?.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compAudio?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        return composition
    }

    // MARK: - Filter Composition (modern API)

    private func createFilterVideoComposition(
        filter: VideoFilter,
        intensity: Double,
        composition: AVMutableComposition
    ) async throws -> AVVideoComposition? {
        guard let videoTrack = try await composition.loadTracks(withMediaType: .video).first else { return nil }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))

        // Modern iOS 18+ async init
        let videoComposition = try await AVMutableVideoComposition.videoComposition(
            with: composition
        ) { request in
            let source = request.sourceImage.clampedToExtent()
            let output = self.applyCIFilter(filter, to: source, intensity: intensity)
            request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
        }

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        return videoComposition
    }

    // MARK: - Filter Application

    private func applyCIFilter(_ filter: VideoFilter, to image: CIImage, intensity: Double) -> CIImage {
        guard let ciFilterName = filter.ciFilterName,
              let ciFilter = CIFilter(name: ciFilterName) else { return image }

        ciFilter.setValue(image, forKey: kCIInputImageKey)
        if ciFilter.inputKeys.contains(kCIInputIntensityKey) {
            ciFilter.setValue(intensity, forKey: kCIInputIntensityKey)
        }
        return ciFilter.outputImage ?? image
    }

    // MARK: - Filter Post-Process (filter + overlays combo)

    private func applyFilterPostProcess(videoURL: URL, filter: VideoFilter, intensity: Double) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let comp = AVMutableComposition()

        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { return videoURL }
        let dur = try await asset.load(.duration)

        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vTrack, at: .zero)
        cv?.preferredTransform = try await vTrack.load(.preferredTransform)

        if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try ca?.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: aTrack, at: .zero)
        }

        let vc = try await createFilterVideoComposition(filter: filter, intensity: intensity, composition: comp)
        return try await exportComposition(composition: comp, videoComposition: vc)
    }

    // MARK: - Export Composition

    private func exportComposition(composition: AVMutableComposition, videoComposition: AVVideoComposition?) async throws -> URL {
        let outputURL = tempVideoURL()
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.exportSessionCreationFailed
        }

        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let vc = videoComposition { session.videoComposition = vc }

        currentExportSession = session
        let progressTask = monitorProgress()

        try await session.export(to: outputURL, as: .mp4)
        progressTask.cancel()
        exportProgress = 1.0
        return outputURL
    }

    // MARK: - Thumbnail

    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let duration = try await asset.load(.duration).seconds
        let time = CMTime(seconds: min(0.5, duration * 0.1), preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        let uiImage = UIImage(cgImage: cgImage)

        let thumbURL = tempImageURL()
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            throw VideoExportError.thumbnailGenerationFailed
        }
        try data.write(to: thumbURL)
        return thumbURL
    }

    // MARK: - Progress Monitor (async loop)

    private func monitorProgress() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.currentExportSession else { return }
                self.exportProgress = Double(session.progress)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    // MARK: - Quality Logging

    private func logQualityComparison(original: URL, exported: URL) async {
        let origSize = (try? FileManager.default.attributesOfItem(atPath: original.path)[.size] as? Int64) ?? 0
        let expSize = (try? FileManager.default.attributesOfItem(atPath: exported.path)[.size] as? Int64) ?? 0
        let ratio = origSize > 0 ? Double(expSize) / Double(origSize) * 100 : 100
        #if DEBUG
        print("📊 EXPORT: \(ByteCountFormatter.string(fromByteCount: origSize, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: expSize, countStyle: .file)) (\(String(format: "%.0f%%", ratio)), \(exportMode.rawValue))")
        #endif
    }

    // MARK: - Helpers

    // These are internal but called from the TextOverlays extension
    func getRenderSize(from composition: AVMutableComposition) async throws -> CGSize {
        guard let track = try await composition.loadTracks(withMediaType: .video).first else {
            return CGSize(width: 1080, height: 1920)
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = natural.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    func buildBaseVideoComposition(from composition: AVMutableComposition, renderSize: CGSize) async throws -> AVMutableVideoComposition {
        guard let videoTrack = try await composition.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let mvc = AVMutableVideoComposition()
        mvc.renderSize = renderSize
        mvc.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        let transform = try await videoTrack.load(.preferredTransform)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        mvc.instructions = [instruction]

        return mvc
    }

    private func tempVideoURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("processed_\(UUID().uuidString).mp4")
    }

    private func tempImageURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail_\(UUID().uuidString).jpg")
    }
}

// MARK: - Errors

enum VideoExportError: LocalizedError {
    case noVideoTrack, exportSessionCreationFailed, exportFailed(String), exportCancelled, thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found"
        case .exportSessionCreationFailed: return "Failed to create export session"
        case .exportFailed(let m): return "Export failed: \(m)"
        case .exportCancelled: return "Export cancelled"
        case .thumbnailGenerationFailed: return "Thumbnail generation failed"
        }
    }
}
