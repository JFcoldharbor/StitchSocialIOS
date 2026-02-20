//
//  ThreadCollageService.swift
//  StitchSocial
//
//  Layer 4: Services - Thread Collage Composition & Export
//  Dependencies: CollageConfiguration (Layer 3), VideoExportService (Layer 4), AVFoundation
//  Features: Select main video + 3-5 thread responses → compose 60s collage → watermark → export
//
//  CACHING STRATEGY:
//  - AVAsset instances are cached per-clip after first load (avoids re-opening remote URLs)
//  - Thumbnail images for selection UI should come from existing ThumbnailCacheManager
//  - All temp files cleaned up on completion, cancellation, or dealloc
//  → ADD TO CACHING OPTIMIZATION FILE: CollageClip.asset caching + temp file cleanup
//
//  BATCHING STRATEGY:
//  - All clip AVAssets loaded concurrently via async let / TaskGroup (not sequential)
//  - All track insertions go into ONE AVMutableComposition (no per-clip export sessions)
//  - Track metadata (duration, transform, naturalSize) loaded in batch per asset
//  → This avoids N separate AVAssetReader sessions and cuts memory spikes
//

import Foundation
import AVFoundation
import UIKit
import CoreImage

// MARK: - ThreadCollageService

@MainActor
class ThreadCollageService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var state: CollageState = .idle
    @Published var progress: Double = 0.0
    @Published var selectedClips: [CollageClip] = []
    @Published var configuration = CollageConfiguration()
    
    // MARK: - Constraints
    
    static let minResponseClips = 3
    static let maxResponseClips = 5
    static let maxTotalDuration: TimeInterval = 60.0
    
    // MARK: - Private
    
    /// Cached AVAssets keyed by video ID — prevents re-downloading from Firebase Storage
    /// CACHING: Strong refs held only during composition lifecycle, cleared on cleanup
    private var assetCache: [String: AVAsset] = [:]
    
    /// Temp file URLs to clean up
    private var tempFileURLs: [URL] = []
    
    /// Current export task for cancellation
    private var exportTask: Task<URL, Error>?
    
    // MARK: - Selection Phase
    
    /// Set the main (parent) video for the collage
    /// Caches AVAsset immediately so composition doesn't re-fetch
    func setMainVideo(_ video: CoreVideoMetadata) {
        let clip = CollageClip(
            id: video.id,
            videoMetadata: video,
            asset: nil,
            originalDuration: video.duration,
            isMainClip: true
        )
        
        selectedClips.removeAll { $0.isMainClip }
        selectedClips.insert(clip, at: 0)
        configuration.creatorUsername = "@\(video.creatorName)"
        state = .selectingClips
        recalculateAllocations()
    }
    
    /// Toggle a response video selection (add/remove)
    /// Returns false if at max capacity and trying to add
    @discardableResult
    func toggleResponseVideo(_ video: CoreVideoMetadata) -> Bool {
        if let index = selectedClips.firstIndex(where: { $0.id == video.id && !$0.isMainClip }) {
            selectedClips.remove(at: index)
            recalculateAllocations()
            return true
        } else {
            let responseCount = selectedClips.filter { !$0.isMainClip }.count
            guard responseCount < Self.maxResponseClips else { return false }
            
            let clip = CollageClip(
                id: video.id,
                videoMetadata: video,
                asset: nil,
                originalDuration: video.duration,
                isMainClip: false
            )
            selectedClips.append(clip)
            recalculateAllocations()
            return true
        }
    }
    
    /// Check if a video is currently selected
    func isSelected(_ videoID: String) -> Bool {
        return selectedClips.contains { $0.id == videoID }
    }
    
    /// Current response clip count
    var responseClipCount: Int {
        return selectedClips.filter { !$0.isMainClip }.count
    }
    
    /// Whether we have enough clips to build the collage
    var canBuildCollage: Bool {
        let hasMain = selectedClips.contains { $0.isMainClip }
        return hasMain && responseClipCount >= Self.minResponseClips
    }
    
    // MARK: - Build Collage (Full Pipeline)
    
    /// Main entry point: loads assets → composes → watermarks → exports
    /// Single pipeline, all batched into one composition
    func buildCollage() async throws -> URL {
        guard canBuildCollage else {
            throw CollageError.insufficientClips(
                have: responseClipCount,
                need: Self.minResponseClips
            )
        }
        
        // Store as task for cancellation support
        let task = Task<URL, Error> {
            
            // Phase 1: Batch load all AVAssets concurrently
            state = .loadingAssets
            progress = 0.1
            try await batchLoadAssets()
            
            // Phase 2: Calculate time allocations
            calculateAllocations()
            progress = 0.2
            
            // Phase 3: Build single AVMutableComposition with all clips
            state = .composing
            let (composition, videoComposition) = try await buildComposition()
            progress = 0.5
            
            // Phase 4: Export (no watermark yet — added after via VideoWatermarkService)
            state = .exporting(progress: 0.0)
            let rawURL = try await exportCollage(
                composition: composition,
                videoComposition: videoComposition
            )
            progress = 0.8
            
            // Phase 5: Apply watermark via existing proven VideoWatermarkService
            state = .addingWatermark
            let outputURL = try await applyWatermarkViaService(
                sourceURL: rawURL,
                creatorUsername: configuration.creatorUsername
            )
            
            progress = 1.0
            state = .completed(url: outputURL)
            
            return outputURL
        }
        
        exportTask = task
        
        do {
            let url = try await task.value
            return url
        } catch {
            if !Task.isCancelled {
                state = .failed(error: error.localizedDescription)
            }
            throw error
        }
    }
    
    /// Cancel in-progress collage build
    func cancel() {
        exportTask?.cancel()
        exportTask = nil
        cleanup()
        state = .idle
        progress = 0.0
    }
    
    // MARK: - Phase 1: Batch Asset Loading
    
    /// BATCHING: Load all clip AVAssets concurrently via TaskGroup
    /// CACHING: Results stored in assetCache so composition reads from cache
    private func batchLoadAssets() async throws {
        try await withThrowingTaskGroup(of: (String, AVAsset, TimeInterval).self) { group in
            for clip in selectedClips {
                let videoID = clip.id
                let videoURLString = clip.videoMetadata.videoURL
                
                group.addTask { [weak self] in
                    // Check cache first — skip network if already loaded
                    if let cached = await self?.assetCache[videoID] {
                        let duration = try await cached.load(.duration).seconds
                        return (videoID, cached, duration)
                    }
                    
                    guard let url = URL(string: videoURLString) else {
                        throw CollageError.invalidVideoURL(videoID)
                    }
                    
                    let asset = AVAsset(url: url)
                    // Batch-load all needed properties in one call
                    let (duration, _) = try await asset.load(.duration, .tracks)
                    
                    return (videoID, asset, duration.seconds)
                }
            }
            
            // Collect results and update clips + cache
            for try await (videoID, asset, duration) in group {
                assetCache[videoID] = asset
                
                if let index = selectedClips.firstIndex(where: { $0.id == videoID }) {
                    selectedClips[index].asset = asset
                    selectedClips[index].originalDuration = duration
                }
            }
        }
    }
    
    // MARK: - Phase 2: Time Allocation
    
    /// Recalculate allocations whenever clips change — keeps trim UI in sync
    func recalculateAllocations() {
        guard let mainClip = selectedClips.first(where: { $0.isMainClip }) else { return }
        guard !selectedClips.filter({ !$0.isMainClip }).isEmpty else {
            // Only main clip — give it the full budget
            if let idx = selectedClips.firstIndex(where: { $0.isMainClip }) {
                selectedClips[idx].allocatedDuration = min(
                    configuration.contentDuration,
                    selectedClips[idx].originalDuration
                )
            }
            return
        }
        
        let responseDurations = selectedClips.filter { !$0.isMainClip }.map { $0.originalDuration }
        
        let allocations = configuration.calculateTimeAllocations(
            mainClipDuration: mainClip.originalDuration,
            responseClipDurations: responseDurations
        )
        
        var allocationIndex = 0
        for i in selectedClips.indices {
            guard allocationIndex < allocations.count else { break }
            selectedClips[i].allocatedDuration = min(
                allocations[allocationIndex],
                selectedClips[i].originalDuration
            )
            // Reset trimStart if it would overflow with new allocation
            let maxStart = selectedClips[i].originalDuration - selectedClips[i].allocatedDuration
            if selectedClips[i].trimStart > maxStart {
                selectedClips[i].trimStart = max(0, maxStart)
            }
            allocationIndex += 1
        }
    }
    
    /// Called during build — same logic but after asset durations are confirmed
    private func calculateAllocations() {
        recalculateAllocations()
    }
    
    // MARK: - Phase 3: Composition Build (Single AVMutableComposition)
    
    /// BATCHING: All clips inserted into ONE composition — no per-clip exports
    /// Returns composition + video composition for orientation/sizing
    private func buildComposition() async throws -> (AVMutableComposition, AVMutableVideoComposition?) {
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CollageError.compositionFailed("Could not create video track")
        }
        
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        var insertionTime = CMTime.zero
        let renderSize = configuration.outputResolution.size
        
        // Track segment times and transforms for per-segment instructions
        struct SegmentInfo {
            let startTime: CMTime
            let duration: CMTime
            let transform: CGAffineTransform
        }
        var segments: [SegmentInfo] = []
        
        for clip in selectedClips {
            guard let asset = clip.asset ?? assetCache[clip.id] else {
                print("⚠️ COLLAGE: Skipping clip \(clip.id) — no cached asset")
                continue
            }
            
            let timeRange = clip.compositionTimeRange
            
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                try compositionVideoTrack.insertTimeRange(
                    timeRange,
                    of: videoTrack,
                    at: insertionTime
                )
                
                // Calculate the transform to force this clip into portrait renderSize
                let transform = try await calculatePortraitTransform(
                    track: videoTrack,
                    renderSize: renderSize
                )
                
                segments.append(SegmentInfo(
                    startTime: insertionTime,
                    duration: timeRange.duration,
                    transform: transform
                ))
            }
            
            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let compAudio = compositionAudioTrack {
                try? compAudio.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertionTime
                )
            }
            
            insertionTime = CMTimeAdd(insertionTime, timeRange.duration)
        }
        
        // No watermark end card needed — watermark applied post-export by VideoWatermarkService
        
        // Build video composition with ONE instruction per segment
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: configuration.frameRate)
        
        var instructions: [AVMutableVideoCompositionInstruction] = []
        
        for segment in segments {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: segment.startTime, duration: segment.duration)
            instruction.backgroundColor = UIColor.black.cgColor
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )
            layerInstruction.setTransform(segment.transform, at: segment.startTime)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)
        }
        
        videoComposition.instructions = instructions
        
        return (composition, videoComposition)
    }
    
    // MARK: - Portrait Transform Calculator
    
    /// Calculate transform to force any video orientation into portrait renderSize
    /// Uses aspect FILL (covers entire frame, crops overflow) so no black bars
    private func calculatePortraitTransform(
        track: AVAssetTrack,
        renderSize: CGSize
    ) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        
        // Get the actual displayed size after the track's built-in rotation
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayWidth = abs(transformedRect.width)
        let displayHeight = abs(transformedRect.height)
        
        // Aspect FILL — scale to cover entire renderSize
        let scaleX = renderSize.width / max(displayWidth, 1)
        let scaleY = renderSize.height / max(displayHeight, 1)
        let scale = max(scaleX, scaleY)
        
        let scaledWidth = displayWidth * scale
        let scaledHeight = displayHeight * scale
        
        // Center offset (crops the overflow equally on both sides)
        let offsetX = (renderSize.width - scaledWidth) / 2
        let offsetY = (renderSize.height - scaledHeight) / 2
        
        // Chain: preferredTransform → normalize to origin → scale → center in render
        // Step 1: Apply the track's rotation/flip
        // Step 2: Normalize — the transformed rect may have negative origin
        let normX = -transformedRect.origin.x
        let normY = -transformedRect.origin.y
        
        var finalTransform = preferredTransform
        finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: normX, y: normY))
        finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
        return finalTransform
    }
    
    // MARK: - Phase 4: Watermark + End Screen via Existing Service
    
    /// Uses same VideoWatermarkService as regular share — includes watermark overlay + end screen card
    private func applyWatermarkViaService(
        sourceURL: URL,
        creatorUsername: String
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            // Default options include watermark + end screen — same as regular share
            let options = VideoWatermarkService.ExportOptions.default
            
            VideoWatermarkService.shared.exportWithWatermark(
                sourceURL: sourceURL,
                creatorUsername: creatorUsername,
                options: options
            ) { result in
                switch result {
                case .success(let watermarkedURL):
                    print("✅ COLLAGE: Watermark + end screen applied via VideoWatermarkService")
                    continuation.resume(returning: watermarkedURL)
                case .failure(let error):
                    print("⚠️ COLLAGE: Watermark failed, using raw video — \(error.localizedDescription)")
                    continuation.resume(returning: sourceURL)
                }
            }
        }
    }
    
    // MARK: - Phase 5: Export
    
    /// Export the final composition to a shareable MP4
    private func exportCollage(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?
    ) async throws -> URL {
        let outputURL = createTempURL(extension: "mp4")
        tempFileURLs.append(outputURL)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        // Use specific resolution preset — HighestQuality can fail with animationTool
        let presetName: String
        if configuration.outputResolution == .hd1080p {
            presetName = AVAssetExportPreset1920x1080
        } else {
            presetName = AVAssetExportPreset1280x720
        }
        
        // Check preset compatibility
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let finalPreset = compatiblePresets.contains(presetName) ? presetName : AVAssetExportPresetMediumQuality
        
        print("🎬 COLLAGE EXPORT: Using preset \(finalPreset)")
        print("🎬 COLLAGE EXPORT: Composition duration: \(composition.duration.seconds)s")
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: finalPreset
        ) else {
            throw CollageError.exportFailed("Could not create export session with preset \(finalPreset)")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        if let videoComp = videoComposition {
            exportSession.videoComposition = videoComp
        }
        
        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                let p = Double(exportSession.progress)
                await MainActor.run {
                    self.progress = 0.6 + (p * 0.4) // 60-100% of total progress
                    self.state = .exporting(progress: p)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            // Remove from temp tracking — this is the final output, don't auto-delete
            tempFileURLs.removeAll { $0 == outputURL }
            return outputURL
            
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            print("❌ COLLAGE EXPORT FAILED: \(errorMsg)")
            print("❌ COLLAGE EXPORT: Underlying error: \(String(describing: exportSession.error))")
            throw CollageError.exportFailed(errorMsg)
            
        case .cancelled:
            throw CollageError.cancelled
            
        default:
            throw CollageError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - Cleanup
    
    /// CACHING CLEANUP: Clear cached assets and delete temp files
    /// Called on cancel, dealloc, or after successful save-to-photos
    func cleanup() {
        // Clear AVAsset cache — releases network-backed asset handles
        assetCache.removeAll()
        
        // Clear clip references
        for i in selectedClips.indices {
            selectedClips[i].asset = nil
        }
        
        // Delete temp files
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs.removeAll()
        
        print("🧹 COLLAGE: Cleaned up \(assetCache.count) cached assets and \(tempFileURLs.count) temp files")
    }
    
    /// Full reset — clears selection and all state
    func reset() {
        cancel()
        selectedClips.removeAll()
        configuration = CollageConfiguration()
        state = .idle
        progress = 0.0
    }
    
    deinit {
        // Ensure temp files are cleaned even if caller forgets
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Helpers
    
    private func createTempURL(extension ext: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("collage_\(UUID().uuidString).\(ext)")
    }
}

// MARK: - Errors

enum CollageError: LocalizedError {
    case insufficientClips(have: Int, need: Int)
    case invalidVideoURL(String)
    case compositionFailed(String)
    case exportFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .insufficientClips(let have, let need):
            return "Need at least \(need) response clips, currently have \(have)"
        case .invalidVideoURL(let id):
            return "Invalid video URL for clip \(id)"
        case .compositionFailed(let msg):
            return "Composition failed: \(msg)"
        case .exportFailed(let msg):
            return "Export failed: \(msg)"
        case .cancelled:
            return "Collage build was cancelled"
        }
    }
}
