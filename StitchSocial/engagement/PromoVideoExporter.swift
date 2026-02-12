//
//  PromoVideoExporter.swift
//  StitchSocial
//
//  Layer 4: Services - Promo Video Export
//  Creates a 30-second promo clip from any video with cycling stat overlays
//  Structure: First 22s of source video + stats cycling full duration + 3s end card
//  Stats: VIEWS → gap → HYPE → gap → COOL → gap → TEMPERATURE → gap (repeats)
//
//  CACHING: Uses VideoDiskCache to avoid re-downloading source video
//  Output written to temp dir, cleaned up after share sheet dismisses
//

import Foundation
import AVFoundation
import UIKit

class PromoVideoExporter {
    
    static let shared = PromoVideoExporter()
    private init() {}
    
    // MARK: - Configuration
    
    /// Total promo video duration
    private let promoDuration: Double = 30.0
    
    /// How long the source video clip plays (remainder is end card)
    private let clipDuration: Double = 27.0
    
    /// End card duration
    private let endCardDuration: Double = 3.0
    
    /// Stat display config — 4 stats, each gets ~6.75s of the 27s clip
    /// With 30% hidden gap: visible ~4.7s, hidden ~2s per stat
    private let statCount = 4
    
    // MARK: - Stats
    
    struct PromoStats {
        let viewCount: Int
        let hypeCount: Int
        let coolCount: Int
        let temperature: String
    }
    
    // MARK: - Export
    
    /// Export a 30s promo video with cycling stats
    /// - Parameters:
    ///   - sourceURL: Local video file URL
    ///   - creatorUsername: Creator's username for watermark
    ///   - stats: Video engagement stats
    ///   - completion: Returns exported promo URL or error
    func exportPromo(
        sourceURL: URL,
        creatorUsername: String,
        stats: PromoStats,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let asset = AVURLAsset(url: sourceURL)
        
        asset.loadTracks(withMediaType: .video) { [weak self] tracks, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let videoTrack = tracks?.first else {
                completion(.failure(PromoExportError.noVideoTrack))
                return
            }
            
            Task {
                do {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    
                    self.buildPromo(
                        asset: asset,
                        videoTrack: videoTrack,
                        naturalSize: naturalSize,
                        transform: transform,
                        creatorUsername: creatorUsername,
                        stats: stats,
                        completion: completion
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Build Composition
    
    private func buildPromo(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        naturalSize: CGSize,
        transform: CGAffineTransform,
        creatorUsername: String,
        stats: PromoStats,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let composition = AVMutableComposition()
        
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            completion(.failure(PromoExportError.compositionFailed))
            return
        }
        
        // Calculate render size from transform
        let renderSize = calculateRenderSize(naturalSize: naturalSize, transform: transform)
        
        // Source video duration
        let sourceDuration = CMTimeGetSeconds(asset.duration)
        
        // Total promo = 30s. Use first 27s of source (or all if shorter) + 3s end card
        let actualClipSeconds = min(clipDuration, sourceDuration)
        let clipTime = CMTime(seconds: actualClipSeconds, preferredTimescale: 600)
        
        do {
            // Insert the main clip (first 27s or full source)
            let clipRange = CMTimeRange(start: .zero, duration: clipTime)
            try compVideoTrack.insertTimeRange(clipRange, of: videoTrack, at: .zero)
            
            // For end card: grab last 1 second of source, insert it, then time-stretch to 3s
            // This creates a near-freeze (slow motion of last second) without glitchy micro-inserts
            let grabDuration = min(1.0, actualClipSeconds)
            let grabStart = CMTime(seconds: actualClipSeconds - grabDuration, preferredTimescale: 600)
            let grabRange = CMTimeRange(start: grabStart, duration: CMTime(seconds: grabDuration, preferredTimescale: 600))
            
            try compVideoTrack.insertTimeRange(grabRange, of: videoTrack, at: composition.duration)
            
            // Stretch that 1s segment to fill 3s (end card overlay covers it anyway)
            let insertedEnd = CMTimeRange(
                start: clipTime,
                duration: CMTime(seconds: grabDuration, preferredTimescale: 600)
            )
            compVideoTrack.scaleTimeRange(
                insertedEnd,
                toDuration: CMTime(seconds: endCardDuration, preferredTimescale: 600)
            )
            
            // If source was shorter than 27s, stretch the main clip to fill 27s
            if sourceDuration < clipDuration {
                let mainRange = CMTimeRange(start: .zero, duration: clipTime)
                compVideoTrack.scaleTimeRange(
                    mainRange,
                    toDuration: CMTime(seconds: clipDuration, preferredTimescale: 600)
                )
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        // Add audio (clipped to actual clip duration, no audio during end card)
        asset.loadTracks(withMediaType: .audio) { [weak self] audioTracks, _ in
            guard let self = self else { return }
            
            if let audioTrack = audioTracks?.first,
               let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let audioClipDuration = min(self.clipDuration, sourceDuration)
                let audioRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: audioClipDuration, preferredTimescale: 600)
                )
                try? compAudioTrack.insertTimeRange(audioRange, of: audioTrack, at: .zero)
            }
            
            // Build video composition
            let videoComp = AVMutableVideoComposition()
            videoComp.renderSize = renderSize
            videoComp.frameDuration = CMTime(value: 1, timescale: 30)
            
            // Normalized transform for the video layer
            let normalizedTransform = self.buildNormalizedTransform(
                naturalSize: naturalSize,
                preferredTransform: transform,
                renderSize: renderSize
            )
            
            // Single instruction spanning full composition
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
            layerInstruction.setTransform(normalizedTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComp.instructions = [instruction]
            
            // Build overlay layers
            let totalDuration = composition.duration
            let (parentLayer, videoLayer) = self.buildOverlayLayers(
                videoSize: renderSize,
                clipDuration: self.clipDuration,
                totalDuration: CMTimeGetSeconds(totalDuration),
                creatorUsername: creatorUsername,
                stats: stats
            )
            
            videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
            
            // Export
            self.export(composition: composition, videoComposition: videoComp, completion: completion)
        }
    }
    
    // MARK: - Overlay Layers
    
    private func buildOverlayLayers(
        videoSize: CGSize,
        clipDuration: Double,
        totalDuration: Double,
        creatorUsername: String,
        stats: PromoStats
    ) -> (CALayer, CALayer) {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.isGeometryFlipped = true
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)
        
        let scale = min(videoSize.width, videoSize.height) / 1080.0
        let slotDuration = clipDuration / 4.0
        
        // Base dark tint
        let dimLayer = CALayer()
        dimLayer.frame = CGRect(origin: .zero, size: videoSize)
        dimLayer.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        parentLayer.addSublayer(dimLayer)
        
        // Heat glow — bottom gradient shifts color per stat phase
        let heatGlow = buildHeatGlowLayer(
            videoSize: videoSize,
            slotDuration: slotDuration,
            clipDuration: clipDuration,
            temperature: stats.temperature
        )
        parentLayer.addSublayer(heatGlow)
        
        // Ember particles — float up during HYPE and TEMPERATURE
        let embers = buildEmberLayer(
            videoSize: videoSize,
            scale: scale,
            slotDuration: slotDuration,
            clipDuration: clipDuration
        )
        parentLayer.addSublayer(embers)
        
        // Watermark
        let watermarkLayer = buildWatermarkLayer(
            videoSize: videoSize,
            creatorUsername: creatorUsername,
            scale: scale
        )
        parentLayer.addSublayer(watermarkLayer)
        
        // Stats cycling
        let statsContainer = buildStatsOverlay(
            videoSize: videoSize,
            clipDuration: clipDuration,
            scale: scale,
            stats: stats
        )
        parentLayer.addSublayer(statsContainer)
        
        // End card
        let endCard = buildEndCard(
            videoSize: videoSize,
            clipDuration: clipDuration,
            totalDuration: totalDuration,
            creatorUsername: creatorUsername,
            scale: scale
        )
        parentLayer.addSublayer(endCard)
        
        // Bottom branding
        let brandLayer = CATextLayer()
        brandLayer.string = "STITCHSOCIAL"
        brandLayer.font = UIFont.systemFont(ofSize: 16, weight: .bold) as CTFont
        brandLayer.fontSize = 16 * scale
        brandLayer.foregroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
        brandLayer.alignmentMode = .center
        brandLayer.contentsScale = UIScreen.main.scale
        brandLayer.frame = CGRect(x: 0, y: videoSize.height - 36 * scale, width: videoSize.width, height: 28 * scale)
        
        let brandOff = CABasicAnimation(keyPath: "opacity")
        brandOff.fromValue = 0.3
        brandOff.toValue = 0
        brandOff.beginTime = AVCoreAnimationBeginTimeAtZero + clipDuration - 0.5
        brandOff.duration = 0.5
        brandOff.fillMode = .forwards
        brandOff.isRemovedOnCompletion = false
        brandLayer.add(brandOff, forKey: nil)
        parentLayer.addSublayer(brandLayer)
        
        return (parentLayer, videoLayer)
    }
    
    // MARK: - Heat Glow (bottom gradient shifts per stat phase)
    
    private func buildHeatGlowLayer(
        videoSize: CGSize,
        slotDuration: Double,
        clipDuration: Double,
        temperature: String
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: videoSize)
        
        let glowHeight = videoSize.height * 0.45
        let glowLayer = CAGradientLayer()
        glowLayer.frame = CGRect(x: 0, y: videoSize.height - glowHeight, width: videoSize.width, height: glowHeight)
        glowLayer.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        glowLayer.locations = [0, 1]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 1)
        
        // Phase 1 VIEWS: subtle cyan
        let p1 = CABasicAnimation(keyPath: "colors")
        p1.fromValue = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        p1.toValue = [UIColor.clear.cgColor, UIColor.cyan.withAlphaComponent(0.08).cgColor]
        p1.beginTime = AVCoreAnimationBeginTimeAtZero + 0.3
        p1.duration = 0.5
        p1.fillMode = .forwards
        p1.isRemovedOnCompletion = false
        glowLayer.add(p1, forKey: nil)
        
        // Phase 2 HYPE: warm orange
        let p2 = CABasicAnimation(keyPath: "colors")
        p2.fromValue = [UIColor.clear.cgColor, UIColor.cyan.withAlphaComponent(0.08).cgColor]
        p2.toValue = [UIColor.clear.cgColor, UIColor.orange.withAlphaComponent(0.18).cgColor]
        p2.beginTime = AVCoreAnimationBeginTimeAtZero + slotDuration
        p2.duration = 0.5
        p2.fillMode = .forwards
        p2.isRemovedOnCompletion = false
        glowLayer.add(p2, forKey: nil)
        
        // Phase 3 COOL: blue
        let p3 = CABasicAnimation(keyPath: "colors")
        p3.fromValue = [UIColor.clear.cgColor, UIColor.orange.withAlphaComponent(0.18).cgColor]
        p3.toValue = [UIColor.clear.cgColor, UIColor(red: 0.27, green: 0.73, blue: 1.0, alpha: 0.12).cgColor]
        p3.beginTime = AVCoreAnimationBeginTimeAtZero + slotDuration * 2
        p3.duration = 0.5
        p3.fillMode = .forwards
        p3.isRemovedOnCompletion = false
        glowLayer.add(p3, forKey: nil)
        
        // Phase 4 TEMPERATURE: matches actual temp
        let tempColor: UIColor = {
            switch temperature.lowercased() {
            case "hot": return UIColor(red: 1.0, green: 0.27, blue: 0, alpha: 0.25)
            case "warm": return UIColor(red: 1.0, green: 0.6, blue: 0, alpha: 0.18)
            case "cold": return UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.15)
            default: return UIColor.white.withAlphaComponent(0.1)
            }
        }()
        
        let p4 = CABasicAnimation(keyPath: "colors")
        p4.fromValue = [UIColor.clear.cgColor, UIColor(red: 0.27, green: 0.73, blue: 1.0, alpha: 0.12).cgColor]
        p4.toValue = [UIColor.clear.cgColor, tempColor.cgColor]
        p4.beginTime = AVCoreAnimationBeginTimeAtZero + slotDuration * 3
        p4.duration = 0.5
        p4.fillMode = .forwards
        p4.isRemovedOnCompletion = false
        glowLayer.add(p4, forKey: nil)
        
        // Pulse during HYPE and TEMP
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.7
        pulse.toValue = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.duration = 1.2
        pulse.beginTime = AVCoreAnimationBeginTimeAtZero + slotDuration
        glowLayer.add(pulse, forKey: nil)
        
        // Fade before end card
        let off = CABasicAnimation(keyPath: "opacity")
        off.fromValue = 1.0
        off.toValue = 0
        off.beginTime = AVCoreAnimationBeginTimeAtZero + clipDuration - 0.5
        off.duration = 0.5
        off.fillMode = .forwards
        off.isRemovedOnCompletion = false
        glowLayer.add(off, forKey: nil)
        
        container.addSublayer(glowLayer)
        return container
    }
    
    // MARK: - Ember Particles (rise during HYPE + TEMPERATURE)
    
    private func buildEmberLayer(
        videoSize: CGSize,
        scale: CGFloat,
        slotDuration: Double,
        clipDuration: Double
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: videoSize)
        
        let hypeStart = slotDuration
        let tempStart = slotDuration * 3
        let colors: [UIColor] = [
            UIColor(red: 1.0, green: 0.4, blue: 0, alpha: 1),
            UIColor(red: 1.0, green: 0.53, blue: 0, alpha: 1),
            UIColor(red: 1.0, green: 0.67, blue: 0, alpha: 1),
            UIColor(red: 1.0, green: 0.27, blue: 0, alpha: 1),
            UIColor(red: 1.0, green: 0.8, blue: 0, alpha: 1)
        ]
        
        for i in 0..<12 {
            let ember = CALayer()
            let sz = CGFloat.random(in: 3...7) * scale
            let xPos = CGFloat.random(in: 0.05...0.95) * videoSize.width
            ember.frame = CGRect(x: xPos, y: videoSize.height + 20, width: sz, height: sz)
            ember.cornerRadius = sz / 2
            ember.backgroundColor = colors[i % colors.count].cgColor
            ember.opacity = 0
            
            let riseDur = Double.random(in: 2.5...4.0)
            let delay1 = Double.random(in: 0...2.0)
            let drift = CGFloat.random(in: -30...30) * scale
            
            // HYPE wave
            let rise1 = CABasicAnimation(keyPath: "position.y")
            rise1.fromValue = videoSize.height + 20
            rise1.toValue = videoSize.height * 0.1
            rise1.beginTime = AVCoreAnimationBeginTimeAtZero + hypeStart + delay1
            rise1.duration = riseDur
            rise1.fillMode = .both
            rise1.isRemovedOnCompletion = false
            ember.add(rise1, forKey: nil)
            
            let op1 = CAKeyframeAnimation(keyPath: "opacity")
            op1.values = [0, 0.8, 0.5, 0] as [NSNumber]
            op1.keyTimes = [0, 0.1, 0.7, 1.0] as [NSNumber]
            op1.beginTime = AVCoreAnimationBeginTimeAtZero + hypeStart + delay1
            op1.duration = riseDur
            op1.fillMode = .both
            op1.isRemovedOnCompletion = false
            ember.add(op1, forKey: nil)
            
            // TEMPERATURE wave
            let delay2 = Double.random(in: 0...2.0)
            let rise2 = CABasicAnimation(keyPath: "position.y")
            rise2.fromValue = videoSize.height + 20
            rise2.toValue = videoSize.height * 0.05
            rise2.beginTime = AVCoreAnimationBeginTimeAtZero + tempStart + delay2
            rise2.duration = riseDur * 0.85
            rise2.fillMode = .both
            rise2.isRemovedOnCompletion = false
            ember.add(rise2, forKey: nil)
            
            let op2 = CAKeyframeAnimation(keyPath: "opacity")
            op2.values = [0, 0.9, 0.6, 0] as [NSNumber]
            op2.keyTimes = [0, 0.1, 0.7, 1.0] as [NSNumber]
            op2.beginTime = AVCoreAnimationBeginTimeAtZero + tempStart + delay2
            op2.duration = riseDur * 0.85
            op2.fillMode = .both
            op2.isRemovedOnCompletion = false
            ember.add(op2, forKey: nil)
            
            container.addSublayer(ember)
        }
        
        return container
    }

    // MARK: - Stats Overlay (Counter Accumulation)
    
    private func buildStatsOverlay(
        videoSize: CGSize,
        clipDuration: Double,
        scale: CGFloat,
        stats: PromoStats
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: videoSize)
        
        struct StatEntry {
            let targetValue: Int
            let label: String
            let color: UIColor
            let isTemperature: Bool
            let tempEmoji: String
            let tempText: String
        }
        
        let temp = tempDisplay(stats.temperature)
        
        let entries: [StatEntry] = [
            StatEntry(targetValue: stats.viewCount, label: "VIEWS", color: .white, isTemperature: false, tempEmoji: "", tempText: ""),
            StatEntry(targetValue: stats.hypeCount, label: "\u{1F525} HYPE",
                color: UIColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1.0), isTemperature: false, tempEmoji: "", tempText: ""),
            StatEntry(targetValue: stats.coolCount, label: "\u{2744}\u{FE0F} COOL",
                color: UIColor(red: 0.27, green: 0.73, blue: 1.0, alpha: 1.0), isTemperature: false, tempEmoji: "", tempText: ""),
            StatEntry(targetValue: 0, label: "TEMPERATURE", color: temp.color, isTemperature: true, tempEmoji: temp.emoji, tempText: temp.text)
        ]
        
        // Each stat: ~6.75s slot
        // Timing: 0.4s slam in → 3.0s counter → 1.5s hold final → 0.5s slam out → 1.35s gap
        let slotDuration = clipDuration / Double(entries.count)
        
        for (index, entry) in entries.enumerated() {
            let slotStart = Double(index) * slotDuration
            
            let statLayer: CALayer
            if entry.isTemperature {
                statLayer = buildTemperatureBlock(
                    emoji: entry.tempEmoji,
                    text: entry.tempText,
                    color: entry.color,
                    videoSize: videoSize,
                    scale: scale,
                    slotStart: slotStart
                )
            } else {
                statLayer = buildCounterStatBlock(
                    targetValue: entry.targetValue,
                    label: entry.label,
                    color: entry.color,
                    videoSize: videoSize,
                    scale: scale,
                    slotStart: slotStart,
                    counterDuration: 3.0
                )
            }
            
            // Slam in
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart
            fadeIn.duration = 0.3
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false
            
            let scaleIn = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleIn.values = [0.3, 1.12, 1.0] as [NSNumber]
            scaleIn.keyTimes = [0, 0.6, 1.0] as [NSNumber]
            scaleIn.timingFunctions = [
                CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1),
                CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            ]
            scaleIn.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart
            scaleIn.duration = 0.4
            scaleIn.fillMode = .forwards
            scaleIn.isRemovedOnCompletion = false
            
            // Slam out
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart + slotDuration - 1.75
            fadeOut.duration = 0.4
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            
            let scaleOut = CABasicAnimation(keyPath: "transform.scale")
            scaleOut.fromValue = 1.0
            scaleOut.toValue = 0.7
            scaleOut.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart + slotDuration - 1.75
            scaleOut.duration = 0.4
            scaleOut.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
            scaleOut.fillMode = .forwards
            scaleOut.isRemovedOnCompletion = false
            
            statLayer.opacity = 0
            statLayer.add(fadeIn, forKey: nil)
            statLayer.add(scaleIn, forKey: nil)
            statLayer.add(fadeOut, forKey: nil)
            statLayer.add(scaleOut, forKey: nil)
            
            container.addSublayer(statLayer)
        }
        
        return container
    }
    
    // MARK: - Counter Stat Block (number counts up from 0)
    
    /// Creates a stat block where the number counts from 0 to targetValue over counterDuration.
    /// Uses ~20 text layers with staggered opacity to simulate the counter rolling up.
    private func buildCounterStatBlock(
        targetValue: Int,
        label: String,
        color: UIColor,
        videoSize: CGSize,
        scale: CGFloat,
        slotStart: Double,
        counterDuration: Double
    ) -> CALayer {
        let block = CALayer()
        let blockWidth = videoSize.width * 0.9
        let blockHeight: CGFloat = 264 * scale
        
        block.frame = CGRect(
            x: (videoSize.width - blockWidth) / 2,
            y: (videoSize.height - blockHeight) / 2 - 20 * scale,
            width: blockWidth,
            height: blockHeight
        )
        
        // Generate counter steps — 20 frames using easeOutExpo curve
        let stepCount = 20
        let counterStart = slotStart + 0.4  // after slam-in
        let stepDuration = counterDuration / Double(stepCount)
        
        for step in 0...stepCount {
            let progress = Double(step) / Double(stepCount)
            // easeOutExpo: fast start, slow finish
            let eased = progress == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * progress)
            let currentValue = Int(eased * Double(targetValue))
            let displayText = formatNumber(currentValue)
            
            let numberLayer = CATextLayer()
            numberLayer.string = displayText
            numberLayer.font = UIFont.systemFont(ofSize: 168, weight: .black) as CTFont
            numberLayer.fontSize = 168 * scale
            numberLayer.foregroundColor = color.cgColor
            numberLayer.alignmentMode = .center
            numberLayer.contentsScale = UIScreen.main.scale
            numberLayer.shadowColor = UIColor.black.cgColor
            numberLayer.shadowOffset = CGSize(width: 0, height: 6)
            numberLayer.shadowRadius = 30
            numberLayer.shadowOpacity = 0.6
            numberLayer.frame = CGRect(x: 0, y: 0, width: blockWidth, height: 186 * scale)
            numberLayer.opacity = 0
            
            // Each step: visible for its duration, then hidden
            if step < stepCount {
                // Show at step start, hide at next step
                let showTime = counterStart + Double(step) * stepDuration
                
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0
                show.toValue = 1
                show.beginTime = AVCoreAnimationBeginTimeAtZero + showTime
                show.duration = 0.01
                show.fillMode = .forwards
                show.isRemovedOnCompletion = false
                numberLayer.add(show, forKey: nil)
                
                let hide = CABasicAnimation(keyPath: "opacity")
                hide.fromValue = 1
                hide.toValue = 0
                hide.beginTime = AVCoreAnimationBeginTimeAtZero + showTime + stepDuration
                hide.duration = 0.01
                hide.fillMode = .forwards
                hide.isRemovedOnCompletion = false
                numberLayer.add(hide, forKey: nil)
            } else {
                // Final value — stays visible until slam out
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0
                show.toValue = 1
                show.beginTime = AVCoreAnimationBeginTimeAtZero + counterStart + counterDuration
                show.duration = 0.01
                show.fillMode = .forwards
                show.isRemovedOnCompletion = false
                numberLayer.add(show, forKey: nil)
            }
            
            block.addSublayer(numberLayer)
        }
        
        // Label — always visible once block appears
        let labelLayer = CATextLayer()
        labelLayer.string = label
        labelLayer.font = UIFont.systemFont(ofSize: 43, weight: .bold) as CTFont
        labelLayer.fontSize = 43 * scale
        labelLayer.foregroundColor = color.withAlphaComponent(0.7).cgColor
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = UIScreen.main.scale
        labelLayer.frame = CGRect(x: 0, y: 186 * scale, width: blockWidth, height: 53 * scale)
        block.addSublayer(labelLayer)
        
        // Accent line
        let lineLayer = CALayer()
        let lineWidth: CGFloat = 90 * scale
        lineLayer.frame = CGRect(
            x: (blockWidth - lineWidth) / 2,
            y: 245 * scale,
            width: lineWidth,
            height: 4 * scale
        )
        lineLayer.backgroundColor = color.withAlphaComponent(0.5).cgColor
        lineLayer.cornerRadius = 2 * scale
        block.addSublayer(lineLayer)
        
        return block
    }
    
    // MARK: - Temperature Block (emoji slam + text type-in)
    
    /// Temperature doesn't count — emoji slams in big, then label types in letter by letter
    private func buildTemperatureBlock(
        emoji: String,
        text: String,
        color: UIColor,
        videoSize: CGSize,
        scale: CGFloat,
        slotStart: Double
    ) -> CALayer {
        let block = CALayer()
        let blockWidth = videoSize.width * 0.9
        let blockHeight: CGFloat = 312 * scale
        
        block.frame = CGRect(
            x: (videoSize.width - blockWidth) / 2,
            y: (videoSize.height - blockHeight) / 2 - 20 * scale,
            width: blockWidth,
            height: blockHeight
        )
        
        // Big emoji — slams in with overshoot
        let emojiLayer = CATextLayer()
        emojiLayer.string = emoji
        emojiLayer.fontSize = 120 * scale
        emojiLayer.alignmentMode = .center
        emojiLayer.contentsScale = UIScreen.main.scale
        emojiLayer.frame = CGRect(x: 0, y: 10 * scale, width: blockWidth, height: 120 * scale)
        emojiLayer.opacity = 0
        
        let emojiShow = CABasicAnimation(keyPath: "opacity")
        emojiShow.fromValue = 0
        emojiShow.toValue = 1
        emojiShow.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart + 0.3
        emojiShow.duration = 0.15
        emojiShow.fillMode = .forwards
        emojiShow.isRemovedOnCompletion = false
        emojiLayer.add(emojiShow, forKey: nil)
        
        let emojiScale = CAKeyframeAnimation(keyPath: "transform.scale")
        emojiScale.values = [0.2, 1.3, 1.0] as [NSNumber]
        emojiScale.keyTimes = [0, 0.5, 1.0] as [NSNumber]
        emojiScale.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1),
            CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        ]
        emojiScale.beginTime = AVCoreAnimationBeginTimeAtZero + slotStart + 0.3
        emojiScale.duration = 0.5
        emojiScale.fillMode = .forwards
        emojiScale.isRemovedOnCompletion = false
        emojiLayer.add(emojiScale, forKey: nil)
        
        block.addSublayer(emojiLayer)
        
        // Text types in letter by letter: "HOT" → "H" → "HO" → "HOT"
        let typeStartTime = slotStart + 1.0
        let letterDuration = 0.2
        
        for i in 0..<text.count {
            let partialText = String(text.prefix(i + 1))
            let letterLayer = CATextLayer()
            letterLayer.string = partialText
            letterLayer.font = UIFont.systemFont(ofSize: 72, weight: .black) as CTFont
            letterLayer.fontSize = 72 * scale
            letterLayer.foregroundColor = color.cgColor
            letterLayer.alignmentMode = .center
            letterLayer.contentsScale = UIScreen.main.scale
            letterLayer.shadowColor = UIColor.black.cgColor
            letterLayer.shadowOffset = CGSize(width: 0, height: 4)
            letterLayer.shadowRadius = 20
            letterLayer.shadowOpacity = 0.5
            letterLayer.frame = CGRect(x: 0, y: 162 * scale, width: blockWidth, height: 84 * scale)
            letterLayer.opacity = 0
            
            let showTime = typeStartTime + Double(i) * letterDuration
            
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 0
            show.toValue = 1
            show.beginTime = AVCoreAnimationBeginTimeAtZero + showTime
            show.duration = 0.01
            show.fillMode = .forwards
            show.isRemovedOnCompletion = false
            letterLayer.add(show, forKey: nil)
            
            // Hide when next letter appears (except last)
            if i < text.count - 1 {
                let hide = CABasicAnimation(keyPath: "opacity")
                hide.fromValue = 1
                hide.toValue = 0
                hide.beginTime = AVCoreAnimationBeginTimeAtZero + showTime + letterDuration
                hide.duration = 0.01
                hide.fillMode = .forwards
                hide.isRemovedOnCompletion = false
                letterLayer.add(hide, forKey: nil)
            }
            
            block.addSublayer(letterLayer)
        }
        
        // "TEMPERATURE" label
        let labelLayer = CATextLayer()
        labelLayer.string = "TEMPERATURE"
        labelLayer.font = UIFont.systemFont(ofSize: 34, weight: .bold) as CTFont
        labelLayer.fontSize = 34 * scale
        labelLayer.foregroundColor = color.withAlphaComponent(0.5).cgColor
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = UIScreen.main.scale
        labelLayer.frame = CGRect(x: 0, y: 252 * scale, width: blockWidth, height: 48 * scale)
        block.addSublayer(labelLayer)
        
        // Accent line
        let lineLayer = CALayer()
        let lineWidth: CGFloat = 90 * scale
        lineLayer.frame = CGRect(
            x: (blockWidth - lineWidth) / 2,
            y: 298 * scale,
            width: lineWidth,
            height: 4 * scale
        )
        lineLayer.backgroundColor = color.withAlphaComponent(0.5).cgColor
        lineLayer.cornerRadius = 2 * scale
        block.addSublayer(lineLayer)
        
        return block
    }
    
    // MARK: - Watermark
    
    private func buildWatermarkLayer(
        videoSize: CGSize,
        creatorUsername: String,
        scale: CGFloat
    ) -> CALayer {
        let container = CALayer()
        let padding: CGFloat = 24 * scale
        
        // Logo — larger for promo
        let logoSize: CGFloat = 48 * scale
        let logoLayer = CALayer()
        logoLayer.frame = CGRect(x: padding, y: padding, width: logoSize, height: logoSize)
        logoLayer.cornerRadius = 12 * scale
        
        if let logo = UIImage(named: "StitchSocialLogo") {
            logoLayer.contents = logo.cgImage
            logoLayer.contentsGravity = .resizeAspectFill
        } else {
            logoLayer.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
        }
        container.addSublayer(logoLayer)
        
        // Username text
        let textLayer = CATextLayer()
        textLayer.string = "@\(creatorUsername) · StitchSocial"
        textLayer.font = UIFont.systemFont(ofSize: 20, weight: .bold) as CTFont
        textLayer.fontSize = 20 * scale
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOffset = CGSize(width: 1, height: 1)
        textLayer.shadowRadius = 3
        textLayer.shadowOpacity = 0.8
        textLayer.frame = CGRect(
            x: padding + logoSize + 12 * scale,
            y: padding + 10 * scale,
            width: videoSize.width - padding * 2 - logoSize - 12 * scale,
            height: 28 * scale
        )
        container.addSublayer(textLayer)
        
        return container
    }
    
    // MARK: - End Card
    
    private func buildEndCard(
        videoSize: CGSize,
        clipDuration: Double,
        totalDuration: Double,
        creatorUsername: String,
        scale: CGFloat
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: videoSize)
        container.opacity = 0
        
        // Darken more for end card
        let darkBg = CALayer()
        darkBg.frame = CGRect(origin: .zero, size: videoSize)
        darkBg.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        container.addSublayer(darkBg)
        
        // App name — big centered
        let appName = CATextLayer()
        appName.string = "STITCHSOCIAL"
        appName.font = UIFont.systemFont(ofSize: 48, weight: .black) as CTFont
        appName.fontSize = 48 * scale
        appName.foregroundColor = UIColor.white.cgColor
        appName.alignmentMode = .center
        appName.contentsScale = UIScreen.main.scale
        appName.frame = CGRect(
            x: 0,
            y: videoSize.height / 2 - 50 * scale,
            width: videoSize.width,
            height: 60 * scale
        )
        container.addSublayer(appName)
        
        // Username below
        let userLayer = CATextLayer()
        userLayer.string = "@\(creatorUsername)"
        userLayer.font = UIFont.systemFont(ofSize: 24, weight: .semibold) as CTFont
        userLayer.fontSize = 24 * scale
        userLayer.foregroundColor = UIColor.white.withAlphaComponent(0.6).cgColor
        userLayer.alignmentMode = .center
        userLayer.contentsScale = UIScreen.main.scale
        userLayer.frame = CGRect(
            x: 0,
            y: videoSize.height / 2 + 16 * scale,
            width: videoSize.width,
            height: 36 * scale
        )
        container.addSublayer(userLayer)
        
        // Fade in at clip end
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + clipDuration
        fadeIn.duration = 0.5
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        container.add(fadeIn, forKey: nil)
        
        return container
    }
    
    // MARK: - Transform Helpers
    
    private func calculateRenderSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
    
    private func buildNormalizedTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let visibleWidth = abs(transformedRect.width)
        let visibleHeight = abs(transformedRect.height)
        
        let scaleX = renderSize.width / visibleWidth
        let scaleY = renderSize.height / visibleHeight
        let scale = max(scaleX, scaleY)
        
        let scaledWidth = visibleWidth * scale
        let scaledHeight = visibleHeight * scale
        let translateX = (renderSize.width - scaledWidth) / 2
        let translateY = (renderSize.height - scaledHeight) / 2
        
        let originFixX = -transformedRect.origin.x
        let originFixY = -transformedRect.origin.y
        
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: originFixX, y: originFixY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: translateX, y: translateY))
    }
    
    // MARK: - Formatting
    
    private func formatNumber(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
    
    private func tempDisplay(_ temp: String) -> (emoji: String, text: String, color: UIColor) {
        switch temp.lowercased() {
        case "hot": return ("🔥", "HOT", UIColor(red: 1.0, green: 0.67, blue: 0, alpha: 1.0))
        case "warm": return ("☀️", "WARM", UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0))
        case "cold": return ("❄️", "COLD", UIColor(red: 0.5, green: 0.78, blue: 1.0, alpha: 1.0))
        default: return ("🌡️", temp.uppercased(), .white)
        }
    }
    
    // MARK: - Export
    
    private func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StitchPromo_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(.failure(PromoExportError.exporterFailed))
            return
        }
        
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    print("✅ PROMO: Export completed — \(outputURL.lastPathComponent)")
                    completion(.success(outputURL))
                case .failed:
                    print("❌ PROMO: Export failed — \(exporter.error?.localizedDescription ?? "")")
                    completion(.failure(exporter.error ?? PromoExportError.exporterFailed))
                default:
                    completion(.failure(PromoExportError.exporterFailed))
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("StitchPromo_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

// MARK: - Errors

enum PromoExportError: LocalizedError {
    case noVideoTrack
    case compositionFailed
    case exporterFailed
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found"
        case .compositionFailed: return "Failed to create composition"
        case .exporterFailed: return "Export failed"
        }
    }
}
