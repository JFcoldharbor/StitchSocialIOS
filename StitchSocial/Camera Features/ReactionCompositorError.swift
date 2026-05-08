//
//  ReactionCompositorError.swift
//  StitchSocial
//
//  Composites camera recording + content zone into a single video.
//
//  FIXES:
//  - All request.finish() calls nil-guarded (prevents NSInvalidArgumentException)
//  - AVURLAsset instead of deprecated AVAsset(url:)
//  - export(to:as:) instead of deprecated export()
//  - Modern videoComposition async init where possible
//
//  CACHING: contentCIImage, solidColorCIImage (static-background path only)
//  CLEANUP: call cleanup() after export
//

import AVFoundation
import CoreImage
import UIKit

// MARK: - Errors

enum ReactionCompositorError: LocalizedError {
    case noCameraTrack
    case noContentVideo
    case exportFailed(String)
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noCameraTrack:    return "No video track in camera recording"
        case .noContentVideo:   return "Content video could not be loaded"
        case .exportFailed(let m): return "Reaction composite failed: \(m)"
        case .exportCancelled:  return "Reaction composite cancelled"
        }
    }
}

// MARK: - ReactionCompositor

class ReactionCompositor {

    private let cameraURL: URL
    private let contentZone: ZoneContent
    private let layout: ReactionLayout
    private let cameraIsTop: Bool
    private let sourceStartOffset: TimeInterval
    private let pauseEvents: [PauseEvent]

    // CACHING (used only by static-background path)
    private var contentCIImage: CIImage?
    private var solidColorCIImage: CIImage?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let renderSize = CGSize(width: 1080, height: 1920)

    init(
        cameraURL: URL,
        contentZone: ZoneContent,
        layout: ReactionLayout,
        cameraIsTop: Bool,
        sourceStartOffset: TimeInterval = 0,
        pauseEvents: [PauseEvent] = []
    ) {
        self.cameraURL = cameraURL
        self.contentZone = contentZone
        self.layout = layout
        self.cameraIsTop = cameraIsTop
        self.sourceStartOffset = sourceStartOffset
        self.pauseEvents = pauseEvents
    }

    // MARK: - Public

    func composite() async throws -> URL {
        cacheContentAssets()
        switch contentZone {
        case .solidColor, .importedImage:
            return try await compositeWithStaticBackground()
        case .importedVideo(let url):
            return try await compositeWithVideo(contentURL: url)
        case .camera:
            return cameraURL
        }
    }

    func cleanup() {
        contentCIImage = nil
        solidColorCIImage = nil
    }

    // MARK: - Content Caching

    private func cacheContentAssets() {
        switch contentZone {
        case .importedImage(let img):
            // CIImage(image:) handles HEIC and other formats UIImage.cgImage may
            // return nil for (e.g. images straight from PhotosPicker on iOS 17+).
            contentCIImage = CIImage(image: img)
            if contentCIImage == nil {
                print("🎬 COMPOSITOR: ⚠️ Failed to load CIImage from UIImage \(img.size)")
            } else {
                print("🎬 COMPOSITOR: Cached CIImage \(img.size)")
            }
        case .solidColor(let color):
            let c = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            solidColorCIImage = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: a))
                .cropped(to: CGRect(origin: .zero, size: renderSize))
        default: break
        }
    }

    // MARK: - Zone Geometry

    private func zoneRects() -> (camera: CGRect, content: CGRect) {
        let w = renderSize.width, h = renderSize.height

        switch layout {
        case .pip:
            let full = CGRect(origin: .zero, size: renderSize)
            let pipRect = CGRect(x: w - 310, y: 120, width: 270, height: 370)
            return cameraIsTop ? (pipRect, full) : (full, pipRect)
        default:
            let (topFrac, _) = layout.split
            let topH = h * topFrac
            let top = CGRect(x: 0, y: 0, width: w, height: topH)
            let bot = CGRect(x: 0, y: topH, width: w, height: h - topH)
            return cameraIsTop ? (top, bot) : (bot, top)
        }
    }

    // MARK: - Static Background Composite

    private func compositeWithStaticBackground() async throws -> URL {
        let cameraAsset = AVURLAsset(url: cameraURL)

        async let videoLoad = cameraAsset.loadTracks(withMediaType: .video)
        async let audioLoad = cameraAsset.loadTracks(withMediaType: .audio)
        async let durLoad = cameraAsset.load(.duration)

        let videoTracks = try await videoLoad
        let audioTracks = try await audioLoad
        let duration = try await durLoad

        guard let camTrack = videoTracks.first else { throw ReactionCompositorError.noCameraTrack }
        let camTransform = try await camTrack.load(.preferredTransform)

        let composition = AVMutableComposition()
        let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: camTrack, at: .zero)
        compVideo.preferredTransform = camTransform

        if let camAudio = audioTracks.first {
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: camAudio, at: .zero)
        }

        let (cameraRect, contentRect) = zoneRects()

        let videoComposition = try await AVMutableVideoComposition.videoComposition(with: composition) { [weak self] request in
            guard let self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            let cameraImage = request.sourceImage.clampedToExtent()

            let contentImage: CIImage
            if let solid = self.solidColorCIImage {
                contentImage = solid
            } else if let ci = self.contentCIImage {
                contentImage = ci
            } else {
                contentImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: self.renderSize))
            }

            let composited = self.renderFrame(
                cameraImage: cameraImage, contentImage: contentImage,
                cameraRect: cameraRect, contentRect: contentRect,
                cameraTransform: camTransform
            )
            // CRITICAL: nil guard prevents finishWithImage crash
            let safe = composited ?? request.sourceImage
            request.finish(with: safe, context: nil)
        }

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        print("🎬 COMPOSITOR: Exporting \(layout.rawValue) layout…")
        return try await exportComposition(composition, videoComposition: videoComposition)
    }

    // MARK: - Video + Video Composite (Mode A)
    //
    // Standard AVFoundation pattern: each source video is a track in the
    // composition; per-track AVMutableVideoCompositionLayerInstruction places
    // it in its zone rect via setTransform. No render closure, no per-frame
    // image generator. Source audio is mixed in at reduced volume so the
    // creator's voice stays intelligible.

    private func compositeWithVideo(contentURL: URL) async throws -> URL {
        let camAsset = AVURLAsset(url: cameraURL)
        let conAsset = AVURLAsset(url: contentURL)

        async let camV = camAsset.loadTracks(withMediaType: .video)
        async let camA = camAsset.loadTracks(withMediaType: .audio)
        async let camD = camAsset.load(.duration)
        async let conV = conAsset.loadTracks(withMediaType: .video)
        async let conA = conAsset.loadTracks(withMediaType: .audio)
        async let conD = conAsset.load(.duration)

        let camVideoTracks = try await camV
        let camAudioTracks = try await camA
        let camDuration = try await camD
        let conVideoTracks = try await conV
        let conAudioTracks = try await conA
        let contentDuration = try await conD

        guard let camTrack = camVideoTracks.first else { throw ReactionCompositorError.noCameraTrack }
        guard let conTrack = conVideoTracks.first else { throw ReactionCompositorError.noContentVideo }

        let camTransform = try await camTrack.load(.preferredTransform)
        let camNaturalSize = try await camTrack.load(.naturalSize)
        let conTransform = try await conTrack.load(.preferredTransform)
        let conNaturalSize = try await conTrack.load(.naturalSize)

        let composition = AVMutableComposition()

        // Camera video track — output is sized to camDuration (master)
        let compCamera = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        try compCamera.insertTimeRange(
            CMTimeRange(start: .zero, duration: camDuration),
            of: camTrack,
            at: .zero
        )

        // Content video track — built from the user's pause/scrub timeline.
        // During play windows the source plays at 1x; during pause windows
        // we insert a single source frame and stretch it via scaleTimeRange
        // so the source visually freezes while the camera keeps rolling.
        let compContent = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!

        // Camera audio (creator's voice — full volume)
        if let camAudio = camAudioTracks.first {
            let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )!
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: camDuration),
                of: camAudio,
                at: .zero
            )
        }

        // Source audio track — same play/pause structure as the content
        // video: audio plays during play windows, silent during pauses.
        var contentAudioCompTrack: AVMutableCompositionTrack?
        if conAudioTracks.first != nil {
            contentAudioCompTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        // Build both tracks segment by segment.
        try buildSourceTracks(
            videoSource: conTrack,
            audioSource: conAudioTracks.first,
            contentDuration: contentDuration,
            cameraDuration: camDuration,
            videoTrack: compContent,
            audioTrack: contentAudioCompTrack
        )

        let (cameraRect, contentRect) = zoneRects()

        let camPlacement = placementForTrack(
            naturalSize: camNaturalSize,
            preferredTransform: camTransform,
            into: cameraRect
        )
        let cameraLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compCamera)
        cameraLayer.setCropRectangle(camPlacement.cropRect, at: .zero)
        cameraLayer.setTransform(camPlacement.transform, at: .zero)

        let conPlacement = placementForTrack(
            naturalSize: conNaturalSize,
            preferredTransform: conTransform,
            into: contentRect
        )
        let contentLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compContent)
        contentLayer.setCropRectangle(conPlacement.cropRect, at: .zero)
        contentLayer.setTransform(conPlacement.transform, at: .zero)

        // Layer order: first element is topmost. In PiP we want the small
        // overlay drawn over the full-screen background; in split layouts the
        // rects don't overlap so order doesn't matter visually.
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: camDuration)
        if layout == .pip {
            instruction.layerInstructions = cameraIsTop
                ? [cameraLayer, contentLayer]   // camera = small PiP, content = background
                : [contentLayer, cameraLayer]   // content = small PiP, camera = background
        } else {
            instruction.layerInstructions = [cameraLayer, contentLayer]
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        var audioMix: AVMutableAudioMix?
        if let contentAudioCompTrack {
            let mix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: contentAudioCompTrack)
            params.setVolume(0.6, at: .zero)
            mix.inputParameters = [params]
            audioMix = mix
        }

        print("🎬 COMPOSITOR: Exporting \(layout.rawValue) layout (Mode A)…")
        return try await exportComposition(composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    // MARK: - Track Placement

    /// Aspect-fill placement for a source video into `targetRect`.
    /// Returns both the affine transform (rotation + scale + translate) and
    /// the source-space crop rectangle that limits the visible region to
    /// exactly `targetRect`'s aspect ratio. Both are required: the transform
    /// scales for fill, and the crop prevents overflow into adjacent zones.
    private func placementForTrack(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        into targetRect: CGRect
    ) -> (transform: CGAffineTransform, cropRect: CGRect) {
        let displayedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayedSize = CGSize(width: abs(displayedBounds.width), height: abs(displayedBounds.height))

        guard displayedSize.width > 0, displayedSize.height > 0,
              targetRect.width > 0, targetRect.height > 0 else {
            return (preferredTransform, CGRect(origin: .zero, size: naturalSize))
        }

        // Aspect-fill scale: pick the larger ratio so source covers the rect.
        let scale = max(targetRect.width / displayedSize.width, targetRect.height / displayedSize.height)
        let scaledW = displayedSize.width * scale
        let scaledH = displayedSize.height * scale

        // Visible region of source in DISPLAYED coords (centered crop).
        // overflowX/Y are how much the scaled source exceeds the target rect.
        let overflowX = max(0, scaledW - targetRect.width)
        let overflowY = max(0, scaledH - targetRect.height)
        let visibleDisplayed = CGRect(
            x: overflowX / (2 * scale),
            y: overflowY / (2 * scale),
            width: targetRect.width / scale,
            height: targetRect.height / scale
        )

        // Convert visible region to source-natural coords for setCropRectangle.
        // visibleDisplayed is anchored at displayedBounds.origin in transformed
        // space, so we re-add that origin before inverting the transform.
        let cropTransformed = CGRect(
            x: visibleDisplayed.origin.x + displayedBounds.origin.x,
            y: visibleDisplayed.origin.y + displayedBounds.origin.y,
            width: visibleDisplayed.width,
            height: visibleDisplayed.height
        ).applying(preferredTransform.inverted())

        // Normalize to positive width/height and clamp to natural bounds.
        let cropX = max(0, min(cropTransformed.minX, cropTransformed.maxX))
        let cropY = max(0, min(cropTransformed.minY, cropTransformed.maxY))
        let cropW = min(naturalSize.width - cropX, abs(cropTransformed.width))
        let cropH = min(naturalSize.height - cropY, abs(cropTransformed.height))
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        // Build setTransform: preferredTransform → scale → translate so that
        // the visible region's top-left lands exactly at targetRect.origin.
        let tx = targetRect.origin.x - (visibleDisplayed.origin.x + displayedBounds.origin.x) * scale
        let ty = targetRect.origin.y - (visibleDisplayed.origin.y + displayedBounds.origin.y) * scale

        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))

        return (transform, cropRect)
    }

    // MARK: - Frame Rendering

    private func renderFrame(
        cameraImage: CIImage, contentImage: CIImage,
        cameraRect: CGRect, contentRect: CGRect,
        cameraTransform: CGAffineTransform
    ) -> CIImage? {
        // Return optional — caller nil-guards before finish()
        var canvas = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))

        let scaledContent = scaleToFill(contentImage, into: contentRect)
        canvas = scaledContent.composited(over: canvas)

        let oriented = cameraImage.transformed(by: cameraTransform)
        let scaledCamera = scaleToFill(oriented, into: cameraRect)
        canvas = scaledCamera.composited(over: canvas)

        let result = canvas.cropped(to: CGRect(origin: .zero, size: renderSize))
        // Validate extent is non-empty
        return result.extent.isEmpty ? nil : result
    }

    private func scaleToFill(_ source: CIImage, into target: CGRect) -> CIImage {
        let ext = source.extent
        guard ext.width > 0, ext.height > 0, target.width > 0, target.height > 0 else {
            return CIImage(color: .black).cropped(to: target)
        }

        let scale = max(target.width / ext.width, target.height / ext.height)
        let scaled = source
            .transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let sw = ext.width * scale, sh = ext.height * scale
        let cx = (sw - target.width) / 2, cy = (sh - target.height) / 2

        return scaled
            .cropped(to: CGRect(x: cx, y: cy, width: target.width, height: target.height))
            .transformed(by: CGAffineTransform(translationX: target.origin.x - cx, y: target.origin.y - cy))
    }

    // MARK: - Looped Track Insert

    private func insertLoopedTrack(sourceTrack: AVAssetTrack, sourceDuration: CMTime, into dest: AVMutableCompositionTrack, masterDuration: CMTime) throws {
        var cursor = CMTime.zero
        while cursor < masterDuration {
            let remaining = masterDuration - cursor
            let dur = min(sourceDuration, remaining)
            try dest.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: sourceTrack, at: cursor)
            cursor = cursor + dur
        }
    }

    // MARK: - Pause-Timeline Track Builder
    //
    // Walks the pause events in order and emits two kinds of segments:
    //
    //   • PLAY segments — source plays at 1x from sourceCursor for the
    //     gap until the next pause (or until camera end). Both video and
    //     audio are inserted normally.
    //
    //   • FREEZE segments — at each pause, we insert a single source
    //     frame at the freeze time and stretch it via scaleTimeRange to
    //     match the pause's camera-time duration. AVFoundation repeats
    //     the frame for the entire stretched range, giving us a clean
    //     freeze. Audio is intentionally NOT inserted during freeze
    //     windows — the source goes silent so the creator's voice can
    //     carry the moment.
    //
    // The video track is required; the audio track is optional (nil if
    // the source has no audio stream).
    private func buildSourceTracks(
        videoSource: AVAssetTrack,
        audioSource: AVAssetTrack?,
        contentDuration: CMTime,
        cameraDuration: CMTime,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?
    ) throws {
        let cameraSec = CMTimeGetSeconds(cameraDuration)
        let contentSec = CMTimeGetSeconds(contentDuration)
        let timescale: CMTimeScale = 600
        let frameDuration = CMTime(value: 1, timescale: 30)

        // Sort + sanitize the pause events so we never go backwards in
        // camera time. Open events (cameraEnd nil) get clamped to
        // cameraSec; out-of-range events are dropped.
        let sanitized: [PauseEvent] = pauseEvents
            .filter { $0.cameraStart >= 0 && $0.cameraStart < cameraSec }
            .map { ev in
                var copy = ev
                copy.cameraEnd = min(copy.cameraEnd ?? cameraSec, cameraSec)
                return copy
            }
            .sorted { $0.cameraStart < $1.cameraStart }

        var cameraCursor: TimeInterval = 0
        var sourceCursor: TimeInterval = max(0, min(sourceStartOffset, max(0, contentSec - 0.05)))

        // If there are no pauses, this still works — just one big play
        // segment from 0 to cameraSec.
        for pause in sanitized {
            // Play segment from cameraCursor up to pause.cameraStart.
            let playDur = max(0, pause.cameraStart - cameraCursor)
            if playDur > 0 {
                try insertPlaySegment(
                    videoSource: videoSource,
                    audioSource: audioSource,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    sourceStart: sourceCursor,
                    duration: playDur,
                    cameraStart: cameraCursor,
                    contentSec: contentSec,
                    timescale: timescale
                )
                sourceCursor += playDur
                cameraCursor = pause.cameraStart
            }

            // Freeze segment for the pause window.
            let pauseEnd = pause.cameraEnd ?? cameraSec
            let pauseDur = max(0, pauseEnd - pause.cameraStart)
            if pauseDur > 0 {
                let freezeAt = max(0, min(pause.sourceFreezeTime, max(0, contentSec - 0.05)))
                try insertFreezeSegment(
                    videoSource: videoSource,
                    videoTrack: videoTrack,
                    sourceTime: freezeAt,
                    cameraStart: cameraCursor,
                    cameraDuration: pauseDur,
                    frameDuration: frameDuration,
                    timescale: timescale
                )
                // Audio stays silent during a freeze (no insert) — that
                // gap shows up as silence in the exported audio track.
                cameraCursor += pauseDur
                // sourceCursor stays put — the source clock is paused.
            }
        }

        // Trailing play segment from the last cursor to camera end.
        let trailingDur = max(0, cameraSec - cameraCursor)
        if trailingDur > 0 {
            try insertPlaySegment(
                videoSource: videoSource,
                audioSource: audioSource,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                sourceStart: sourceCursor,
                duration: trailingDur,
                cameraStart: cameraCursor,
                contentSec: contentSec,
                timescale: timescale
            )
        }
    }

    private func insertPlaySegment(
        videoSource: AVAssetTrack,
        audioSource: AVAssetTrack?,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        sourceStart: TimeInterval,
        duration: TimeInterval,
        cameraStart: TimeInterval,
        contentSec: TimeInterval,
        timescale: CMTimeScale
    ) throws {
        // Clamp duration so we don't read past the end of the source.
        // If the source is shorter than the requested play duration, the
        // remainder of the camera segment will be a freeze of the last
        // frame (we accomplish that by chaining a zero-frame freeze).
        let availableSourceSec = max(0, contentSec - sourceStart)
        let actualDur = min(duration, availableSourceSec)

        if actualDur > 0 {
            let range = CMTimeRange(
                start: CMTime(seconds: sourceStart, preferredTimescale: timescale),
                duration: CMTime(seconds: actualDur, preferredTimescale: timescale)
            )
            try videoTrack.insertTimeRange(
                range, of: videoSource,
                at: CMTime(seconds: cameraStart, preferredTimescale: timescale)
            )
            if let audioTrack, let audioSource {
                try audioTrack.insertTimeRange(
                    range, of: audioSource,
                    at: CMTime(seconds: cameraStart, preferredTimescale: timescale)
                )
            }
        }

        // If the source ran out, freeze the last frame for the remainder.
        let remaining = duration - actualDur
        if remaining > 0 {
            let freezeAt = max(0, contentSec - 0.05)
            try insertFreezeSegment(
                videoSource: videoSource,
                videoTrack: videoTrack,
                sourceTime: freezeAt,
                cameraStart: cameraStart + actualDur,
                cameraDuration: remaining,
                frameDuration: CMTime(value: 1, timescale: 30),
                timescale: timescale
            )
        }
    }

    private func insertFreezeSegment(
        videoSource: AVAssetTrack,
        videoTrack: AVMutableCompositionTrack,
        sourceTime: TimeInterval,
        cameraStart: TimeInterval,
        cameraDuration: TimeInterval,
        frameDuration: CMTime,
        timescale: CMTimeScale
    ) throws {
        // Insert a single source frame, then stretch it to the pause's
        // camera-time duration. AVFoundation repeats the frame across
        // the stretched range, producing a true visual freeze.
        let frameStart = CMTime(seconds: sourceTime, preferredTimescale: timescale)
        let frameRange = CMTimeRange(start: frameStart, duration: frameDuration)
        let cameraStartTime = CMTime(seconds: cameraStart, preferredTimescale: timescale)
        try videoTrack.insertTimeRange(frameRange, of: videoSource, at: cameraStartTime)

        let stretchedDur = CMTime(seconds: cameraDuration, preferredTimescale: timescale)
        videoTrack.scaleTimeRange(
            CMTimeRange(start: cameraStartTime, duration: frameDuration),
            toDuration: stretchedDur
        )
    }

    // MARK: - Export

    private func exportComposition(
        _ composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix? = nil
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction_composite_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ReactionCompositorError.exportFailed("Could not create export session")
        }

        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        session.shouldOptimizeForNetworkUse = true

        try await session.export(to: outputURL, as: .mp4)

        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        print("🎬 COMPOSITOR: Done — \(size / 1024)KB")
        return outputURL
    }
}
