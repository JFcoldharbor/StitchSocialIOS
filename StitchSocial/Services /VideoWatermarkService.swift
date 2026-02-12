//
//  VideoWatermarkService.swift
//  StitchSocial
//
//  Layer 4: Services - Video Watermarking for Sharing
//  Features: Jumping watermark, end screen, sound effect
//  UPDATED: Increased watermark size by 50% for better visibility
//

import Foundation
import AVFoundation
import UIKit
import CoreImage

/// Service to add watermarks to videos for sharing
class VideoWatermarkService {
    
    static let shared = VideoWatermarkService()
    
    private init() {}
    
    // MARK: - Watermark Configuration
    
    /// Positions the watermark can jump to (3 zones only)
    enum WatermarkPosition: CaseIterable {
        case topLeft
        case rightMiddle
        case bottomLeft
        
        func point(for videoSize: CGSize, watermarkSize: CGSize, padding: CGFloat) -> CGPoint {
            switch self {
            case .topLeft:
                return CGPoint(x: padding, y: videoSize.height - watermarkSize.height - padding)
            case .rightMiddle:
                return CGPoint(x: videoSize.width - watermarkSize.width - padding, y: (videoSize.height - watermarkSize.height) / 2)
            case .bottomLeft:
                return CGPoint(x: padding, y: padding)
            }
        }
    }
    
    // Jump interval in seconds
    private let jumpInterval: Double = 2.0
    private let watermarkPadding: CGFloat = 30.0  // Increased from 20 to match larger watermark
    private let watermarkOpacity: Float = 1.0
    
    // End screen duration
    private let endScreenDuration: Double = 2.0
    
    // Custom end screen video properties (set during processing)
    private var customEndScreenTransform: CGAffineTransform = .identity
    private var customEndScreenNaturalSize: CGSize = .zero
    
    // MARK: - Export Options
    
    // MARK: - Stats for Promo Share
    
    struct VideoStats {
        let viewCount: Int
        let hypeCount: Int
        let coolCount: Int
        let temperature: String  // "hot", "warm", "cold", "neutral"
    }
    
    // MARK: - Export Options
    
    struct ExportOptions {
        var addWatermark: Bool = true
        var addEndScreen: Bool = true
        var addSound: Bool = true
        var showUsernameOnCustomEndScreen: Bool = true
        
        /// Promo mode: slam-in cycling stats overlay (views, hype, cool, temperature)
        var showStats: Bool = false
        var stats: VideoStats? = nil
        
        static let `default` = ExportOptions()
    }
    
    // Custom end screen video file name (add to your project bundle)
    // Supported: StitchEndScreen.mp4, StitchEndScreen.mov
    private let customEndScreenNames = ["StitchEndScreen", "stitch_end_screen", "EndScreen"]
    private let videoExtensions = ["mp4", "mov", "m4v"]
    
    /// Check if custom end screen video exists in bundle
    private func getCustomEndScreenURL() -> URL? {
        for name in customEndScreenNames {
            for ext in videoExtensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    print("✅ ENDSCREEN: Found custom video: \(name).\(ext)")
                    return url
                }
            }
        }
        print("ℹ️ ENDSCREEN: No custom video found, using generated overlay")
        return nil
    }  // Full opacity for maximum visibility
    
    // MARK: - Export Video with Watermark
    
    /// Exports a video with jumping watermark, end screen, and sound
    /// - Parameters:
    ///   - sourceURL: Original video URL
    ///   - creatorUsername: Username to display on watermark
    ///   - options: Export options (watermark, end screen, sound)
    ///   - completion: Returns URL of processed video or error
    func exportWithWatermark(
        sourceURL: URL,
        creatorUsername: String,
        options: ExportOptions = .default,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        
        // Get video track
        asset.loadTracks(withMediaType: .video) { [weak self] tracks, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let videoTrack = tracks?.first else {
                completion(.failure(WatermarkError.noVideoTrack))
                return
            }
            
            self.processVideo(
                asset: asset,
                videoTrack: videoTrack,
                creatorUsername: creatorUsername,
                options: options,
                completion: completion
            )
        }
    }
    
    // Convenience method without options (backwards compatible)
    func exportWithWatermark(
        sourceURL: URL,
        creatorUsername: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        exportWithWatermark(sourceURL: sourceURL, creatorUsername: creatorUsername, options: .default, completion: completion)
    }
    
    private func processVideo(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        creatorUsername: String,
        options: ExportOptions,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Create composition
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            completion(.failure(WatermarkError.compositionFailed))
            return
        }
        
        // Get duration
        let videoDuration = asset.duration
        let timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        
        // Track if we're using custom end screen
        var usingCustomEndScreen = false
        var customEndScreenDuration: CMTime = .zero
        var customEndScreenTrack: AVMutableCompositionTrack? = nil
        
        do {
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            
            // If end screen is enabled, check for custom video first
            if options.addEndScreen {
                if let customURL = getCustomEndScreenURL() {
                    // Use custom end screen video
                    let customAsset = AVURLAsset(url: customURL)
                    
                    // Load custom video track synchronously
                    let semaphore = DispatchSemaphore(value: 0)
                    var customVideoTrack: AVAssetTrack?
                    var customAudioTrack: AVAssetTrack?
                    
                    customAsset.loadTracks(withMediaType: .video) { tracks, _ in
                        customVideoTrack = tracks?.first
                        semaphore.signal()
                    }
                    semaphore.wait()
                    
                    customAsset.loadTracks(withMediaType: .audio) { tracks, _ in
                        customAudioTrack = tracks?.first
                        semaphore.signal()
                    }
                    semaphore.wait()
                    
                    if let customTrack = customVideoTrack {
                        // Get the custom video's size and transform
                        let customSemaphore = DispatchSemaphore(value: 0)
                        
                        Task {
                            do {
                                self.customEndScreenNaturalSize = try await customTrack.load(.naturalSize)
                                self.customEndScreenTransform = try await customTrack.load(.preferredTransform)
                            } catch {
                                print("⚠️ ENDSCREEN: Could not load custom video properties")
                            }
                            customSemaphore.signal()
                        }
                        customSemaphore.wait()
                        
                        customEndScreenDuration = customAsset.duration
                        let customRange = CMTimeRange(start: .zero, duration: customEndScreenDuration)
                        
                        // Create a SEPARATE track for the custom end screen
                        if let endScreenTrack = composition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        ) {
                            // Insert custom video at the end of the main video
                            try endScreenTrack.insertTimeRange(customRange, of: customTrack, at: videoDuration)
                            customEndScreenTrack = endScreenTrack
                            usingCustomEndScreen = true
                            
                            print("✅ ENDSCREEN: Added custom video on separate track (\(CMTimeGetSeconds(customEndScreenDuration))s)")
                            print("✅ ENDSCREEN: Custom size: \(customEndScreenNaturalSize), transform: \(customEndScreenTransform)")
                        }
                        
                        // Add custom end screen audio if available
                        if let customAudio = customAudioTrack,
                           let audioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                           ) {
                            try? audioTrack.insertTimeRange(customRange, of: customAudio, at: videoDuration)
                        }
                    }
                }
                
                // Fallback: if no custom video, extend with last frame on same track
                if !usingCustomEndScreen {
                    let lastFrameTime = CMTime(seconds: 0.1, preferredTimescale: 600)
                    let lastFrameRange = CMTimeRange(
                        start: CMTimeSubtract(videoDuration, lastFrameTime),
                        duration: lastFrameTime
                    )
                    let repeatCount = Int(ceil(endScreenDuration / 0.1))
                    for _ in 0..<repeatCount {
                        try compositionVideoTrack.insertTimeRange(lastFrameRange, of: videoTrack, at: composition.duration)
                    }
                    print("ℹ️ ENDSCREEN: Using generated overlay (\(endScreenDuration)s)")
                }
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        // Add original audio if available
        asset.loadTracks(withMediaType: .audio) { [weak self] audioTracks, _ in
            guard let self = self else { return }
            
            if let audioTrack = audioTracks?.first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }
            
            // Add sound effect if enabled
            if options.addSound {
                self.addSoundEffect(to: composition, at: .zero)
            }
            
            // Get video size and transform using async/await
            Task {
                do {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    
                    // Calculate actual video size accounting for rotation
                    let videoSize = self.calculateVideoSize(naturalSize: naturalSize, transform: transform)
                    
                    // Total duration is now the composition duration
                    let totalDuration = composition.duration
                    
                    // Create video composition with watermark and end screen
                    self.createVideoComposition(
                        composition: composition,
                        mainVideoTrack: compositionVideoTrack,
                        customEndScreenTrack: customEndScreenTrack,
                        videoSize: videoSize,
                        naturalSize: naturalSize,
                        mainTransform: transform,
                        videoDuration: videoDuration,
                        totalDuration: totalDuration,
                        creatorUsername: creatorUsername,
                        options: options,
                        usingCustomEndScreen: usingCustomEndScreen,
                        completion: completion
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Sound Effect
    
    private func addSoundEffect(to composition: AVMutableComposition, at time: CMTime) {
        // Try to load sound from bundle
        // Add a file named "StitchSound.mp3" or "StitchSound.wav" to your project
        let soundNames = ["StitchSound", "stitch_sound", "share_sound"]
        let extensions = ["mp3", "wav", "m4a", "aiff"]
        
        var soundURL: URL?
        
        for name in soundNames {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    soundURL = url
                    break
                }
            }
            if soundURL != nil { break }
        }
        
        guard let url = soundURL else {
            print("⚠️ WATERMARK: No sound file found. Add StitchSound.mp3 to your project.")
            return
        }
        
        let soundAsset = AVURLAsset(url: url)
        
        soundAsset.loadTracks(withMediaType: .audio) { [weak self] tracks, error in
            guard let soundTrack = tracks?.first else {
                print("⚠️ WATERMARK: Could not load sound track")
                return
            }
            
            guard let soundCompositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return }
            
            let soundDuration = soundAsset.duration
            let soundRange = CMTimeRange(start: .zero, duration: soundDuration)
            
            do {
                try soundCompositionTrack.insertTimeRange(soundRange, of: soundTrack, at: time)
                print("✅ WATERMARK: Added sound effect")
            } catch {
                print("⚠️ WATERMARK: Failed to add sound - \(error)")
            }
        }
    }
    
    private func calculateVideoSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        // Apply transform to get the actual visible rect
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
    
    /// Build a transform that centers and scales the source video to fill renderSize
    /// Handles portrait iPhone videos (rotated 90°), landscape, and non-standard transforms
    private func buildNormalizedTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        // Apply the preferred transform to get actual visible rect
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let visibleWidth = abs(transformedRect.width)
        let visibleHeight = abs(transformedRect.height)
        
        // Scale to fill renderSize (aspect fill)
        let scaleX = renderSize.width / visibleWidth
        let scaleY = renderSize.height / visibleHeight
        let scale = max(scaleX, scaleY)
        
        // Center the scaled result
        let scaledWidth = visibleWidth * scale
        let scaledHeight = visibleHeight * scale
        let translateX = (renderSize.width - scaledWidth) / 2
        let translateY = (renderSize.height - scaledHeight) / 2
        
        // Fix origin: preferredTransform can leave rect with negative origin
        let originFixX = -transformedRect.origin.x
        let originFixY = -transformedRect.origin.y
        
        let fixedOrigin = CGAffineTransform(translationX: originFixX, y: originFixY)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let centerTransform = CGAffineTransform(translationX: translateX, y: translateY)
        
        return preferredTransform
            .concatenating(fixedOrigin)
            .concatenating(scaleTransform)
            .concatenating(centerTransform)
    }
    
    private func createVideoComposition(
        composition: AVMutableComposition,
        mainVideoTrack: AVMutableCompositionTrack,
        customEndScreenTrack: AVMutableCompositionTrack?,
        videoSize: CGSize,
        naturalSize: CGSize,
        mainTransform: CGAffineTransform,
        videoDuration: CMTime,
        totalDuration: CMTime,
        creatorUsername: String,
        options: ExportOptions,
        usingCustomEndScreen: Bool,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Build normalized transform that centers+fills regardless of source orientation
        let normalizedTransform = buildNormalizedTransform(
            naturalSize: naturalSize,
            preferredTransform: mainTransform,
            renderSize: videoSize
        )
        
        var instructions: [AVMutableVideoCompositionInstruction] = []
        
        // Instruction 1: Main video portion
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        
        let mainLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mainVideoTrack)
        mainLayerInstruction.setTransform(normalizedTransform, at: .zero)
        
        var mainLayerInstructions: [AVMutableVideoCompositionLayerInstruction] = [mainLayerInstruction]
        
        // If we have a custom end screen track, add it to main instruction (hidden)
        if let endScreenTrack = customEndScreenTrack {
            let hiddenEndScreenInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: endScreenTrack)
            hiddenEndScreenInstruction.setOpacity(0, at: .zero)
            mainLayerInstructions.append(hiddenEndScreenInstruction)
        }
        
        mainInstruction.layerInstructions = mainLayerInstructions
        instructions.append(mainInstruction)
        
        // Instruction 2: End screen portion
        if options.addEndScreen {
            let endScreenDur = CMTimeSubtract(totalDuration, videoDuration)
            let endInstruction = AVMutableVideoCompositionInstruction()
            endInstruction.timeRange = CMTimeRange(start: videoDuration, duration: endScreenDur)
            
            var endLayerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
            
            if usingCustomEndScreen, let endScreenTrack = customEndScreenTrack {
                // Hide the main video track during end screen
                let hiddenMainInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mainVideoTrack)
                hiddenMainInstruction.setOpacity(0, at: .zero)
                endLayerInstructions.append(hiddenMainInstruction)
                
                // Show the custom end screen track
                let endLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: endScreenTrack)
                
                print("🎬 ENDSCREEN: customNaturalSize=\(customEndScreenNaturalSize)")
                print("🎬 ENDSCREEN: renderSize=\(videoSize)")
                
                // Check if custom video needs rotation
                let customIsRotated = customEndScreenTransform.b == 1.0 || customEndScreenTransform.b == -1.0
                
                // Calculate scale
                let scaleX = videoSize.width / customEndScreenNaturalSize.width
                let scaleY = videoSize.height / customEndScreenNaturalSize.height
                let scale = min(scaleX, scaleY)
                
                var finalTransform: CGAffineTransform
                if customIsRotated {
                    finalTransform = customEndScreenTransform
                    print("✅ ENDSCREEN: Using rotated transform")
                } else {
                    finalTransform = CGAffineTransform(scaleX: scale, y: scale)
                    print("✅ ENDSCREEN: Using scale=\(scale)")
                }
                
                endLayerInstruction.setTransform(finalTransform, at: .zero)
                endLayerInstruction.setOpacity(1.0, at: .zero)
                endLayerInstructions.append(endLayerInstruction)
                
            } else {
                // Generated end screen - dim the main video
                let endLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mainVideoTrack)
                endLayerInstruction.setTransform(normalizedTransform, at: .zero)
                endLayerInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.3, timeRange: CMTimeRange(
                    start: videoDuration,
                    duration: CMTime(seconds: 0.3, preferredTimescale: 600)
                ))
                endLayerInstructions.append(endLayerInstruction)
            }
            
            endInstruction.layerInstructions = endLayerInstructions
            instructions.append(endInstruction)
        }
        
        videoComposition.instructions = instructions
        
        // Create watermark and end screen layers
        let (parentLayer, videoLayer) = createOverlayLayers(
            videoSize: videoSize,
            videoDuration: videoDuration,
            totalDuration: totalDuration,
            creatorUsername: creatorUsername,
            options: options,
            usingCustomEndScreen: usingCustomEndScreen
        )
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        // Export
        exportComposition(composition: composition, videoComposition: videoComposition, completion: completion)
    }
    
    // MARK: - Overlay Layer Creation
    
    private func createOverlayLayers(
        videoSize: CGSize,
        videoDuration: CMTime,
        totalDuration: CMTime,
        creatorUsername: String,
        options: ExportOptions,
        usingCustomEndScreen: Bool
    ) -> (CALayer, CALayer) {
        
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.isGeometryFlipped = true
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        
        parentLayer.addSublayer(videoLayer)
        
        // Watermark (main video only)
        if options.addWatermark {
            let watermarkLayer = createAnimatedWatermarkLayer(
                videoSize: videoSize,
                duration: videoDuration,
                creatorUsername: creatorUsername
            )
            parentLayer.addSublayer(watermarkLayer)
        }
        
        // Promo stats overlay — cycling slam-in blocks
        if options.showStats, let stats = options.stats {
            let statsLayer = createPromoStatsOverlay(
                videoSize: videoSize,
                videoDuration: videoDuration,
                stats: stats
            )
            parentLayer.addSublayer(statsLayer)
        }
        
        // Generated end screen (only if no custom video)
        if options.addEndScreen && !usingCustomEndScreen {
            let endScreenLayer = createEndScreenLayer(
                videoSize: videoSize,
                videoDuration: videoDuration,
                creatorUsername: creatorUsername
            )
            parentLayer.addSublayer(endScreenLayer)
        }
        
        // Username overlay for custom end screen
        if options.addEndScreen && usingCustomEndScreen && options.showUsernameOnCustomEndScreen {
            let usernameOverlay = createCustomEndScreenUsernameOverlay(
                videoSize: videoSize,
                videoDuration: videoDuration,
                creatorUsername: creatorUsername
            )
            parentLayer.addSublayer(usernameOverlay)
        }
        
        return (parentLayer, videoLayer)
    }
    
    // MARK: - Promo Stats Overlay (Slam-In Cycling)
    
    /// Creates cycling stat blocks that slam into center of video
    /// Order: VIEWS → HYPE → COOL → TEMPERATURE → repeat
    /// Each stat: scale(0.3) → scale(1.08) → scale(1) hold → scale(0.8) out
    private func createPromoStatsOverlay(
        videoSize: CGSize,
        videoDuration: CMTime,
        stats: VideoStats
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: videoSize)
        
        // Dark tint over video so stats pop — video still visible underneath
        let dimLayer = CALayer()
        dimLayer.frame = CGRect(origin: .zero, size: videoSize)
        dimLayer.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        
        // Dim only shows during main video
        dimLayer.opacity = 0
        let dimOn = CABasicAnimation(keyPath: "opacity")
        dimOn.fromValue = 0
        dimOn.toValue = 1
        dimOn.beginTime = AVCoreAnimationBeginTimeAtZero + 0.1
        dimOn.duration = 0.3
        dimOn.fillMode = .forwards
        dimOn.isRemovedOnCompletion = false
        dimLayer.add(dimOn, forKey: nil)
        
        // Hide dim during end screen
        let dimOff = CABasicAnimation(keyPath: "opacity")
        dimOff.fromValue = 1
        dimOff.toValue = 0
        dimOff.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) - 0.3
        dimOff.duration = 0.3
        dimOff.fillMode = .forwards
        dimOff.isRemovedOnCompletion = false
        dimLayer.add(dimOff, forKey: nil)
        
        container.addSublayer(dimLayer)
        
        let duration = CMTimeGetSeconds(videoDuration)
        let scale = min(videoSize.width, videoSize.height) / 1080.0
        
        // Build stat entries
        struct StatEntry {
            let number: String
            let label: String
            let color: UIColor
        }
        
        var entries: [StatEntry] = []
        entries.append(StatEntry(
            number: formatStatNumber(stats.viewCount),
            label: "VIEWS",
            color: .white
        ))
        entries.append(StatEntry(
            number: formatStatNumber(stats.hypeCount),
            label: "HYPE",
            color: UIColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1.0)
        ))
        entries.append(StatEntry(
            number: formatStatNumber(stats.coolCount),
            label: "COOL",
            color: UIColor(red: 0.27, green: 0.73, blue: 1.0, alpha: 1.0)
        ))
        
        let tempDisplay = temperatureDisplay(stats.temperature)
        entries.append(StatEntry(
            number: tempDisplay.emoji + " " + tempDisplay.text,
            label: "TEMPERATURE",
            color: tempDisplay.color
        ))
        
        // Cycle time: divide video duration evenly among stats
        // Stop 1s before end screen so stats don't overlap
        let usableDuration = max(duration - 1.0, Double(entries.count) * 1.5)
        let cycleDuration = min(2.5, usableDuration / Double(entries.count))
        
        // How many full cycles fit before end screen
        let totalCycle = cycleDuration * Double(entries.count)
        let repeatCount = max(1, Int(floor(usableDuration / totalCycle)))
        
        // Create each stat block with timed slam-in/out animations
        for (index, entry) in entries.enumerated() {
            let statLayer = createSingleStatBlock(
                number: entry.number,
                label: entry.label,
                color: entry.color,
                videoSize: videoSize,
                scale: scale
            )
            
            // Opacity animation — slam in, hold, slam out
            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
            
            // Opacity: slam in, hold, slam out, CLEAR GAP before next
            // 0.00 - 0.06: slam in
            // 0.06 - 0.60: hold visible
            // 0.60 - 0.70: slam out
            // 0.70 - 1.00: fully hidden (gap before next stat)
            opacityAnim.values = [0, 1, 1, 0, 0] as [NSNumber]
            opacityAnim.keyTimes = [0, 0.06, 0.60, 0.70, 1.0] as [NSNumber]
            
            // Scale: punch in big, settle, shrink out
            scaleAnim.values = [0.3, 1.12, 1.0, 0.7, 0.3] as [NSNumber]
            scaleAnim.keyTimes = [0, 0.06, 0.14, 0.70, 1.0] as [NSNumber]
            
            let slamIn = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            let hold = CAMediaTimingFunction(name: .linear)
            let slamOut = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
            
            opacityAnim.timingFunctions = [slamIn, hold, slamOut, hold]
            scaleAnim.timingFunctions = [slamIn, slamIn, slamOut, hold]
            
            let offset = Double(index) * cycleDuration
            
            opacityAnim.beginTime = AVCoreAnimationBeginTimeAtZero + offset
            opacityAnim.duration = totalCycle
            opacityAnim.repeatCount = Float(repeatCount)
            opacityAnim.fillMode = .both
            opacityAnim.isRemovedOnCompletion = false
            
            scaleAnim.beginTime = AVCoreAnimationBeginTimeAtZero + offset
            scaleAnim.duration = totalCycle
            scaleAnim.repeatCount = Float(repeatCount)
            scaleAnim.fillMode = .both
            scaleAnim.isRemovedOnCompletion = false
            
            statLayer.opacity = 0
            statLayer.add(opacityAnim, forKey: "statOpacity")
            statLayer.add(scaleAnim, forKey: "statScale")
            
            container.addSublayer(statLayer)
        }
        
        // Bottom branding text
        let brandLayer = CATextLayer()
        brandLayer.string = "STITCHSOCIAL"
        brandLayer.font = UIFont.systemFont(ofSize: 14, weight: .bold) as CTFont
        brandLayer.fontSize = 14 * scale
        brandLayer.foregroundColor = UIColor.white.withAlphaComponent(0.35).cgColor
        brandLayer.alignmentMode = .center
        brandLayer.contentsScale = UIScreen.main.scale
        let brandHeight: CGFloat = 24 * scale
        brandLayer.frame = CGRect(
            x: 0,
            y: videoSize.height - brandHeight - 20 * scale,
            width: videoSize.width,
            height: brandHeight
        )
        
        // Fade brand out before end screen
        let brandOff = CABasicAnimation(keyPath: "opacity")
        brandOff.fromValue = 0.35
        brandOff.toValue = 0
        brandOff.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) - 0.3
        brandOff.duration = 0.3
        brandOff.fillMode = .forwards
        brandOff.isRemovedOnCompletion = false
        brandLayer.add(brandOff, forKey: nil)
        
        container.addSublayer(brandLayer)
        
        return container
    }
    
    /// Single stat block: big number + label + accent line, centered in video
    private func createSingleStatBlock(
        number: String,
        label: String,
        color: UIColor,
        videoSize: CGSize,
        scale: CGFloat
    ) -> CALayer {
        let block = CALayer()
        let blockWidth = videoSize.width * 0.9
        let blockHeight: CGFloat = 220 * scale
        
        block.frame = CGRect(
            x: (videoSize.width - blockWidth) / 2,
            y: (videoSize.height - blockHeight) / 2 - 20 * scale,
            width: blockWidth,
            height: blockHeight
        )
        
        // Big number — massive, fills the screen
        let numberLayer = CATextLayer()
        numberLayer.string = number
        numberLayer.font = UIFont.systemFont(ofSize: 140, weight: .black) as CTFont
        numberLayer.fontSize = 140 * scale
        numberLayer.foregroundColor = color.cgColor
        numberLayer.alignmentMode = .center
        numberLayer.contentsScale = UIScreen.main.scale
        numberLayer.shadowColor = UIColor.black.cgColor
        numberLayer.shadowOffset = CGSize(width: 0, height: 6)
        numberLayer.shadowRadius = 30
        numberLayer.shadowOpacity = 0.6
        numberLayer.frame = CGRect(x: 0, y: 0, width: blockWidth, height: 155 * scale)
        block.addSublayer(numberLayer)
        
        // Label — big and bold
        let labelLayer = CATextLayer()
        labelLayer.string = label
        labelLayer.font = UIFont.systemFont(ofSize: 36, weight: .bold) as CTFont
        labelLayer.fontSize = 36 * scale
        labelLayer.foregroundColor = color.withAlphaComponent(0.7).cgColor
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = UIScreen.main.scale
        labelLayer.frame = CGRect(x: 0, y: 155 * scale, width: blockWidth, height: 44 * scale)
        block.addSublayer(labelLayer)
        
        // Accent line — wider
        let lineLayer = CALayer()
        let lineWidth: CGFloat = 90 * scale
        lineLayer.frame = CGRect(
            x: (blockWidth - lineWidth) / 2,
            y: 205 * scale,
            width: lineWidth,
            height: 4 * scale
        )
        lineLayer.backgroundColor = color.withAlphaComponent(0.5).cgColor
        lineLayer.cornerRadius = 2 * scale
        block.addSublayer(lineLayer)
        
        return block
    }
    
    // MARK: - Stat Formatting Helpers
    
    private func formatStatNumber(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    private func temperatureDisplay(_ temp: String) -> (emoji: String, text: String, color: UIColor) {
        switch temp.lowercased() {
        case "hot":
            return ("🔥", "HOT", UIColor(red: 1.0, green: 0.67, blue: 0, alpha: 1.0))
        case "warm":
            return ("☀️", "WARM", UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0))
        case "cold":
            return ("❄️", "COLD", UIColor(red: 0.5, green: 0.78, blue: 1.0, alpha: 1.0))
        default:
            return ("🌡️", temp.uppercased(), UIColor.white)
        }
    }
    
    // MARK: - Custom End Screen Username Overlay
    
    /// Creates a username overlay that appears on top of custom end screen video
    /// Username is centered below where the logo would be
    private func createCustomEndScreenUsernameOverlay(
        videoSize: CGSize,
        videoDuration: CMTime,
        creatorUsername: String
    ) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.frame = CGRect(origin: .zero, size: videoSize)
        
        // Username text layer - centered, below logo
        let usernameLayer = CATextLayer()
        usernameLayer.string = "@\(creatorUsername)"
        usernameLayer.font = UIFont.systemFont(ofSize: 28, weight: .bold) as CTFont
        usernameLayer.fontSize = min(videoSize.width * 0.06, 32)
        usernameLayer.foregroundColor = UIColor.white.cgColor
        usernameLayer.alignmentMode = .center
        usernameLayer.contentsScale = UIScreen.main.scale
        usernameLayer.shadowColor = UIColor.black.cgColor
        usernameLayer.shadowOffset = CGSize(width: 2, height: 2)
        usernameLayer.shadowRadius = 4
        usernameLayer.shadowOpacity = 0.8
        
        let textHeight: CGFloat = 44
        
        // Center of screen + offset to be below logo
        // Assumes logo is centered, username goes ~10% below center
        let centerY = videoSize.height / 2
        let belowLogoOffset = videoSize.height * 0.10  // 10% below center
        
        usernameLayer.frame = CGRect(
            x: 0,
            y: centerY + belowLogoOffset,
            width: videoSize.width,
            height: textHeight
        )
        
        // Start hidden, fade in when end screen starts
        usernameLayer.opacity = 0
        
        // Fade in animation
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) + 0.3
        fadeIn.duration = 0.4
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        usernameLayer.add(fadeIn, forKey: "fadeIn")
        
        containerLayer.addSublayer(usernameLayer)
        
        return containerLayer
    }
    
    // MARK: - End Screen Layer
    
    private func createEndScreenLayer(
        videoSize: CGSize,
        videoDuration: CMTime,
        creatorUsername: String
    ) -> CALayer {
        let endScreenLayer = CALayer()
        endScreenLayer.frame = CGRect(origin: .zero, size: videoSize)
        endScreenLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        
        // Start hidden, fade in at end
        endScreenLayer.opacity = 0
        
        // Fade in animation
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration)
        fadeIn.duration = 0.3
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        endScreenLayer.add(fadeIn, forKey: "fadeIn")
        
        // Add logo to end screen
        let logoLayer = CALayer()
        let logoSize: CGFloat = min(videoSize.width, videoSize.height) * 0.25
        logoLayer.frame = CGRect(
            x: (videoSize.width - logoSize) / 2,
            y: (videoSize.height - logoSize) / 2 + 30,
            width: logoSize,
            height: logoSize
        )
        
        if let logo = UIImage(named: "StitchSocialLogo") {
            logoLayer.contents = logo.cgImage
            print("✅ ENDSCREEN: Using custom logo")
        } else {
            // Fallback - create text-based logo
            let fallbackImage = createEndScreenLogo(size: CGSize(width: logoSize, height: logoSize))
            logoLayer.contents = fallbackImage.cgImage
            print("⚠️ ENDSCREEN: Using fallback logo")
        }
        
        logoLayer.contentsGravity = .resizeAspect
        logoLayer.opacity = 0
        
        // Logo fade in (slightly delayed)
        let logoFadeIn = CABasicAnimation(keyPath: "opacity")
        logoFadeIn.fromValue = 0
        logoFadeIn.toValue = 1
        logoFadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) + 0.2
        logoFadeIn.duration = 0.4
        logoFadeIn.fillMode = .forwards
        logoFadeIn.isRemovedOnCompletion = false
        logoLayer.add(logoFadeIn, forKey: "fadeIn")
        
        // Logo scale animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.5
        scaleAnimation.toValue = 1.0
        scaleAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) + 0.2
        scaleAnimation.duration = 0.4
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false
        logoLayer.add(scaleAnimation, forKey: "scale")
        
        endScreenLayer.addSublayer(logoLayer)
        
        // Add "StitchSocial" text below logo
        let textLayer = CATextLayer()
        textLayer.string = "StitchSocial"
        textLayer.font = UIFont.systemFont(ofSize: 32, weight: .bold) as CTFont
        textLayer.fontSize = min(videoSize.width * 0.08, 48)
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        
        let textHeight: CGFloat = 50
        textLayer.frame = CGRect(
            x: 0,
            y: (videoSize.height - logoSize) / 2 - textHeight - 20,
            width: videoSize.width,
            height: textHeight
        )
        
        textLayer.opacity = 0
        
        // Text fade in
        let textFadeIn = CABasicAnimation(keyPath: "opacity")
        textFadeIn.fromValue = 0
        textFadeIn.toValue = 1
        textFadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) + 0.4
        textFadeIn.duration = 0.3
        textFadeIn.fillMode = .forwards
        textFadeIn.isRemovedOnCompletion = false
        textLayer.add(textFadeIn, forKey: "fadeIn")
        
        endScreenLayer.addSublayer(textLayer)
        
        // Add username text
        let usernameLayer = CATextLayer()
        usernameLayer.string = "Video by @\(creatorUsername)"
        usernameLayer.font = UIFont.systemFont(ofSize: 18, weight: .medium) as CTFont
        usernameLayer.fontSize = min(videoSize.width * 0.045, 24)
        usernameLayer.foregroundColor = UIColor.white.withAlphaComponent(0.8).cgColor
        usernameLayer.alignmentMode = .center
        usernameLayer.contentsScale = UIScreen.main.scale
        
        let usernameHeight: CGFloat = 30
        usernameLayer.frame = CGRect(
            x: 0,
            y: (videoSize.height - logoSize) / 2 - textHeight - usernameHeight - 40,
            width: videoSize.width,
            height: usernameHeight
        )
        
        usernameLayer.opacity = 0
        
        // Username fade in
        let usernameFadeIn = CABasicAnimation(keyPath: "opacity")
        usernameFadeIn.fromValue = 0
        usernameFadeIn.toValue = 1
        usernameFadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + CMTimeGetSeconds(videoDuration) + 0.5
        usernameFadeIn.duration = 0.3
        usernameFadeIn.fillMode = .forwards
        usernameFadeIn.isRemovedOnCompletion = false
        usernameLayer.add(usernameFadeIn, forKey: "fadeIn")
        
        endScreenLayer.addSublayer(usernameLayer)
        
        return endScreenLayer
    }
    
    private func createEndScreenLogo(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 2.0)
        
        // Draw a simple "S" as fallback
        let iconConfig = UIImage.SymbolConfiguration(pointSize: size.width * 0.6, weight: .bold)
        if let icon = UIImage(systemName: "s.circle.fill", withConfiguration: iconConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            let iconRect = CGRect(
                x: (size.width - icon.size.width) / 2,
                y: (size.height - icon.size.height) / 2,
                width: icon.size.width,
                height: icon.size.height
            )
            icon.draw(in: iconRect)
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
    
    private func createAnimatedWatermarkLayer(
        videoSize: CGSize,
        duration: CMTime,
        creatorUsername: String
    ) -> CALayer {
        
        // Create watermark image
        let watermarkImage = createWatermarkImage(creatorUsername: creatorUsername, forVideoSize: videoSize)
        let watermarkSize = watermarkImage.size
        
        // Create layer - use default anchorPoint (0.5, 0.5) so position is center
        let watermarkLayer = CALayer()
        watermarkLayer.contents = watermarkImage.cgImage
        watermarkLayer.opacity = watermarkOpacity
        watermarkLayer.bounds = CGRect(origin: .zero, size: watermarkSize)
        watermarkLayer.masksToBounds = false
        
        // Calculate positions for jumping
        let positions = WatermarkPosition.allCases.map { position in
            position.point(for: videoSize, watermarkSize: watermarkSize, padding: watermarkPadding)
        }
        
        // Create jumping animation
        let positionAnimation = createJumpingAnimation(
            positions: positions,
            duration: duration,
            watermarkSize: watermarkSize
        )
        
        watermarkLayer.add(positionAnimation, forKey: "position")
        
        // Set initial position
        let initialPosition = positions[0]
        watermarkLayer.position = CGPoint(
            x: initialPosition.x + watermarkSize.width / 2,
            y: initialPosition.y + watermarkSize.height / 2
        )
        
        return watermarkLayer
    }
    
    private func createJumpingAnimation(
        positions: [CGPoint],
        duration: CMTime,
        watermarkSize: CGSize
    ) -> CAKeyframeAnimation {
        
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = CMTimeGetSeconds(duration)
        animation.isRemovedOnCompletion = false
        
        // Calculate number of jumps
        let totalSeconds = CMTimeGetSeconds(duration)
        let numberOfJumps = Int(totalSeconds / jumpInterval) + 1
        
        // Create keyframe values and times
        var values: [CGPoint] = []
        var keyTimes: [NSNumber] = []
        
        for i in 0..<numberOfJumps {
            let positionIndex = i % positions.count
            let position = positions[positionIndex]
            
            // Convert from origin to center for CALayer position
            let centerPosition = CGPoint(
                x: position.x + watermarkSize.width / 2,
                y: position.y + watermarkSize.height / 2
            )
            
            values.append(centerPosition)
            
            let time = Double(i) * jumpInterval / totalSeconds
            keyTimes.append(NSNumber(value: min(time, 1.0)))
        }
        
        // Ensure we end at time 1.0
        if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
            values.append(values.last!)
            keyTimes.append(NSNumber(value: 1.0))
        }
        
        animation.values = values
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete // Instant jump, no interpolation
        
        return animation
    }
    
    // MARK: - Watermark Image Creation
    
    private func createWatermarkImage(creatorUsername: String, forVideoSize videoSize: CGSize) -> UIImage {
        // Scale watermark based on video size
        let rawScale = min(videoSize.width, videoSize.height) / 1080.0
        let scale = max(rawScale, 0.8)
        
        // INCREASED SIZES - 50% bigger for better visibility
        let logoSize: CGFloat = 54 * scale       // Was 36
        let textWidth: CGFloat = 200 * scale     // Was 140
        let width = logoSize + 12 * scale + textWidth
        let height = logoSize + 10 * scale
        let scaledSize = CGSize(width: width, height: height)
        
        // Create context with transparency (no background)
        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 2.0)
        guard UIGraphicsGetCurrentContext() != nil else {
            UIGraphicsEndImageContext()
            return UIImage()
        }
        
        // Logo on the left
        let logoRect = CGRect(
            x: 0,
            y: (scaledSize.height - logoSize) / 2,
            width: logoSize,
            height: logoSize
        )
        
        if let logo = UIImage(named: "StitchSocialLogo") {
            logo.draw(in: logoRect)
            print("✅ WATERMARK: Using custom StitchSocialLogo")
        } else {
            print("⚠️ WATERMARK: StitchSocialLogo not found, using fallback")
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 42 * scale, weight: .semibold)  // Was 28
            if let icon = UIImage(systemName: "film.stack", withConfiguration: iconConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                icon.draw(in: logoRect)
            }
        }
        
        // Text to the right of logo
        let textX = logoRect.maxX + 12 * scale
        
        // Shadow for visibility on any background
        let shadowStyle = NSShadow()
        shadowStyle.shadowColor = UIColor.black.withAlphaComponent(0.8)
        shadowStyle.shadowOffset = CGSize(width: 1.5, height: 1.5)
        shadowStyle.shadowBlurRadius = 4
        
        // Username - INCREASED from 16pt to 24pt
        let usernameFont = UIFont.systemFont(ofSize: 24 * scale, weight: .bold)
        let usernameAttributes: [NSAttributedString.Key: Any] = [
            .font: usernameFont,
            .foregroundColor: UIColor.white,
            .shadow: shadowStyle
        ]
        let usernameText = "@\(creatorUsername)" as NSString
        let usernameRect = CGRect(
            x: textX,
            y: 4 * scale,
            width: textWidth,
            height: 32 * scale  // Was 22
        )
        usernameText.draw(in: usernameRect, withAttributes: usernameAttributes)
        
        // StitchSocial - INCREASED from 13pt to 19pt
        let appFont = UIFont.systemFont(ofSize: 19 * scale, weight: .medium)
        let appAttributes: [NSAttributedString.Key: Any] = [
            .font: appFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            .shadow: shadowStyle
        ]
        let appText = "StitchSocial" as NSString
        let appRect = CGRect(
            x: textX,
            y: 36 * scale,  // Was 26
            width: textWidth,
            height: 26 * scale  // Was 18
        )
        appText.draw(in: appRect, withAttributes: appAttributes)
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - Export
    
    private func exportComposition(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StitchSocial_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create exporter
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(WatermarkError.exporterCreationFailed))
            return
        }
        
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        
        print("🎬 WATERMARK: Starting export...")
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    print("✅ WATERMARK: Export completed")
                    completion(.success(outputURL))
                case .failed:
                    print("❌ WATERMARK: Export failed - \(exporter.error?.localizedDescription ?? "Unknown")")
                    completion(.failure(exporter.error ?? WatermarkError.exportFailed))
                case .cancelled:
                    print("⚠️ WATERMARK: Export cancelled")
                    completion(.failure(WatermarkError.exportCancelled))
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in files where file.lastPathComponent.hasPrefix("StitchSocial_") {
                try? FileManager.default.removeItem(at: file)
            }
            print("🧹 WATERMARK: Cleaned up temp files")
        } catch {
            print("⚠️ WATERMARK: Cleanup error - \(error)")
        }
    }
}

// MARK: - Errors

enum WatermarkError: LocalizedError {
    case noVideoTrack
    case compositionFailed
    case invalidVideoSize
    case exporterCreationFailed
    case exportFailed
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found"
        case .compositionFailed: return "Failed to create composition"
        case .invalidVideoSize: return "Invalid video size"
        case .exporterCreationFailed: return "Failed to create exporter"
        case .exportFailed: return "Export failed"
        case .exportCancelled: return "Export was cancelled"
        }
    }
}
