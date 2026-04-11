//
//  VideoExportService+TextOverlays.swift
//  StitchSocial
//
//  Burns TextOverlay stickers into the exported video using
//  CATextLayer + AVVideoCompositionCoreAnimationTool.
//
//  HOW IT WIRES IN — two changes to VideoExportService.swift:
//
//  1. In fullProcessExport(), after building videoComposition, add:
//
//     if !editState.textOverlays.isEmpty {
//         let renderSize = try await getRenderSize(from: composition)
//         let duration   = CMTime(seconds: editState.trimmedDuration, preferredTimescale: 600)
//         let animTool   = buildTextOverlayAnimationTool(
//             overlays: editState.textOverlays,
//             renderSize: renderSize,
//             duration: duration
//         )
//         // Attach to existing or new AVMutableVideoComposition
//         if var mvc = videoComposition as? AVMutableVideoComposition {
//             mvc.animationTool = animTool
//             videoComposition = mvc
//         } else {
//             let mvc = try await buildBaseVideoComposition(from: composition, renderSize: renderSize)
//             mvc.animationTool = animTool
//             videoComposition = mvc
//         }
//     }
//
//  2. In determineExportMode(), make sure hasTextOverlays returns .fullProcess:
//     (Already handled — hasEdits now includes hasTextOverlays from VideoEditState update.)
//
//  CACHING: CALayers are created once per export call, released after export.
//  No persistent caches needed — export is a one-shot operation.

import AVFoundation
import UIKit
import QuartzCore

extension VideoExportService {

    // MARK: - Build CALayer Animation Tool

    /// Creates an AVVideoCompositionCoreAnimationTool that burns text overlays
    /// into the video frame using CATextLayer/CALayer compositing.
    func buildTextOverlayAnimationTool(
        overlays: [TextOverlay],
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoCompositionCoreAnimationTool {

        // Parent layer — same size as video
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true  // CoreAnimation uses flipped coords vs AVFoundation

        // Video layer — AVFoundation composites into this
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Build a CALayer for each overlay
        for overlay in overlays {
            let layer = buildTextLayer(overlay: overlay, renderSize: renderSize, duration: duration)
            parentLayer.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    // MARK: - Single Text Layer

    private func buildTextLayer(
        overlay: TextOverlay,
        renderSize: CGSize,
        duration: CMTime
    ) -> CALayer {

        let font = UIFont(name: overlay.font.postScriptName, size: overlay.fontSize * overlay.scale)
            ?? UIFont.systemFont(ofSize: overlay.fontSize * overlay.scale,
                                 weight: overlay.isBold ? .bold : .semibold)

        // Measure text to size background layer
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (overlay.text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 16
        let layerW = textSize.width  + padding * 2
        let layerH = textSize.height + padding

        // Position from normalizedX/Y (0…1 of render size)
        // CoreAnimation isGeometryFlipped = true so y is already in video space
        let cx = overlay.normalizedX * renderSize.width
        let cy = overlay.normalizedY * renderSize.height
        let frame = CGRect(
            x: cx - layerW / 2,
            y: cy - layerH / 2,
            width: layerW,
            height: layerH
        )

        // Container layer (handles bg + rotation)
        let container = CALayer()
        container.frame = frame
        container.transform = CATransform3DMakeRotation(
            overlay.rotation * .pi / 180, 0, 0, 1
        )

        // Background
        switch overlay.style {
        case .boldPill, .typewriter:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = overlay.style == .boldPill ? layerH / 2 : 4
        case .neon:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = 8
            container.shadowColor = overlay.textColor.cgColor
            container.shadowRadius = 12
            container.shadowOpacity = 0.9
            container.shadowOffset = .zero
        case .outline, .gradient:
            container.backgroundColor = UIColor.clear.cgColor
        }

        // Text layer
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(
            x: padding,
            y: padding / 2,
            width: textSize.width,
            height: textSize.height
        )
        textLayer.string = overlay.text
        textLayer.font = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = overlay.textColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.isWrapped = false
        textLayer.contentsScale = UIScreen.main.scale

        // Gradient text — apply gradient mask
        if overlay.style == .gradient {
            let gradLayer = CAGradientLayer()
            gradLayer.frame = textLayer.bounds
            gradLayer.colors = [
                overlay.textColor.cgColor,
                overlay.textColor.withAlphaComponent(0.5).cgColor
            ]
            gradLayer.startPoint = CGPoint(x: 0, y: 0)
            gradLayer.endPoint   = CGPoint(x: 1, y: 1)
            gradLayer.mask = textLayer
            container.addSublayer(gradLayer)
        } else {
            container.addSublayer(textLayer)
        }

        // Outline style — shadow trick for stroke
        if overlay.style == .outline {
            textLayer.shadowColor  = overlay.textColor.cgColor
            textLayer.shadowRadius = 0
            textLayer.shadowOpacity = 1
            textLayer.shadowOffset = CGSize(width: 1.5, height: 1.5)
        }

        // Time visibility — hide outside startTime…endTime if set
        if let start = overlay.startTime, let end = overlay.endTime {
            let showAt  = CABasicAnimation(keyPath: "opacity")
            showAt.fromValue = 0; showAt.toValue = 1
            showAt.beginTime = start; showAt.duration = 0.01
            showAt.fillMode = .forwards; showAt.isRemovedOnCompletion = false

            let hideAt  = CABasicAnimation(keyPath: "opacity")
            hideAt.fromValue = 1; hideAt.toValue = 0
            hideAt.beginTime = end; hideAt.duration = 0.01
            hideAt.fillMode = .forwards; hideAt.isRemovedOnCompletion = false

            let group = CAAnimationGroup()
            group.animations = [showAt, hideAt]
            group.duration = CMTimeGetSeconds(duration)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            container.opacity = 0
            container.add(group, forKey: "visibility")
        }

        return container
    }

    // MARK: - Combined: Text Overlays + Captions in one animationTool

    /// Builds a single AVVideoCompositionCoreAnimationTool containing both
    /// text overlay stickers AND time-synced caption layers.
    func buildCombinedAnimationTool(
        overlays: [TextOverlay],
        captions: [VideoCaption],
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoCompositionCoreAnimationTool {

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Text overlay stickers
        for overlay in overlays {
            let layer = buildTextLayer(overlay: overlay, renderSize: renderSize, duration: duration)
            parentLayer.addSublayer(layer)
        }

        // Caption layers
        for caption in captions {
            let layer = buildCaptionLayer(caption: caption, renderSize: renderSize, duration: duration)
            parentLayer.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    // MARK: - Caption CALayer

    private func buildCaptionLayer(
        caption: VideoCaption,
        renderSize: CGSize,
        duration: CMTime
    ) -> CALayer {

        // Resolve font and colors from preset or legacy style
        let preset = caption.preset
        let fontSize: CGFloat = preset?.fontSize ?? caption.style.fontSize
        let font: UIFont = preset?.uiFont ??
            UIFont.systemFont(ofSize: fontSize,
                              weight: caption.style.fontWeight == "bold" ? .bold : .semibold)
        let textColor: UIColor = preset?.textUIColor ?? .white
        let bgColor:   UIColor = preset?.bgUIColor   ?? UIColor.black.withAlphaComponent(0.55)
        let bgType:    CaptionBgType = preset?.bgType ?? .pill

        // Use safe Y offset to avoid ContextualVideoOverlay metadata
        let cy = renderSize.height * caption.position.safeOffset

        // Measure text
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth = renderSize.width * 0.85
        let textSize = (caption.text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).size

        // Build container based on bgType
        let hPad: CGFloat = bgType == .none ? 0 : 20
        let vPad: CGFloat = bgType == .none ? 0 : 10
        let layerW = bgType == .fullBar
            ? renderSize.width
            : min(textSize.width + hPad * 2, renderSize.width * 0.92)
        let layerH = textSize.height + vPad * 2

        let frame = CGRect(
            x: (renderSize.width - layerW) / 2,
            y: cy - layerH / 2,
            width: layerW, height: layerH
        )

        let container = CALayer()
        container.frame = frame

        switch bgType {
        case .pill:
            container.backgroundColor = bgColor.cgColor
            container.cornerRadius = layerH / 2
        case .fullBar:
            container.backgroundColor = bgColor.cgColor
            container.cornerRadius = 0
        case .highlightWord:
            // Build stacked word-highlight layers
            return buildWordHighlightLayer(caption: caption, preset: preset!,
                                           font: font, renderSize: renderSize,
                                           cy: cy, duration: duration)
        case .blur, .outline:
            container.backgroundColor = bgColor.cgColor
            container.cornerRadius = 10
        case .none:
            container.backgroundColor = UIColor.clear.cgColor
        }

        // Text layer
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: hPad, y: vPad,
                                 width: layerW - hPad * 2, height: textSize.height)
        textLayer.string = caption.text
        textLayer.font = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = textColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.contentsScale = UIScreen.main.scale
        container.addSublayer(textLayer)

        // Stroke layer (if preset has stroke)
        if let preset = preset, preset.strokeWidth > 0 {
            let strokeLayer = CATextLayer()
            strokeLayer.frame = textLayer.frame
            strokeLayer.string = caption.text
            strokeLayer.font = textLayer.font
            strokeLayer.fontSize = textLayer.fontSize
            strokeLayer.foregroundColor = preset.strokeUIColor.cgColor
            strokeLayer.alignmentMode = .center
            strokeLayer.isWrapped = true
            strokeLayer.contentsScale = UIScreen.main.scale
            // Insert behind text
            container.insertSublayer(strokeLayer, at: 0)
        }

        animateVisibility(layer: container, startTime: caption.startTime,
                          endTime: caption.endTime, totalDuration: duration)
        return container
    }

    // Word-highlight layer for Insta Bold / Karaoke presets
    private func buildWordHighlightLayer(
        caption: VideoCaption,
        preset: CaptionStylePreset,
        font: UIFont,
        renderSize: CGSize,
        cy: CGFloat,
        duration: CMTime
    ) -> CALayer {
        let words = caption.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let maxPerLine = 3
        var lines: [[String]] = []
        var current: [String] = []
        for word in words {
            current.append(word)
            if current.count >= maxPerLine { lines.append(current); current = [] }
        }
        if !current.isEmpty { lines.append(current) }

        let lineH: CGFloat = font.lineHeight + 14
        let totalH = CGFloat(lines.count) * lineH + CGFloat(max(lines.count - 1, 0)) * 4
        let stackFrame = CGRect(x: 0, y: cy - totalH / 2,
                                width: renderSize.width, height: totalH)

        let stack = CALayer()
        stack.frame = stackFrame

        for (li, line) in lines.enumerated() {
            let lineY = CGFloat(li) * (lineH + 4)
            // Measure total line width
            var lineWidth: CGFloat = 0
            let wordWidths: [CGFloat] = line.map { word in
                let w = (word as NSString).size(withAttributes: [.font: font]).width + 18
                lineWidth += w + 6
                return w
            }
            lineWidth -= 6

            var xCursor = (renderSize.width - lineWidth) / 2
            for (wi, word) in line.enumerated() {
                let wW = wordWidths[wi]
                let pill = CALayer()
                pill.frame = CGRect(x: xCursor, y: lineY, width: wW, height: lineH)
                pill.backgroundColor = preset.bgUIColor.cgColor
                pill.cornerRadius = lineH / 2

                let tl = CATextLayer()
                tl.frame = CGRect(x: 6, y: (lineH - font.lineHeight) / 2,
                                  width: wW - 12, height: font.lineHeight + 4)
                tl.string = word
                tl.font = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
                tl.fontSize = font.pointSize
                tl.foregroundColor = preset.textUIColor.cgColor
                tl.alignmentMode = .center
                tl.contentsScale = UIScreen.main.scale
                pill.addSublayer(tl)
                stack.addSublayer(pill)
                xCursor += wW + 6
            }
        }

        animateVisibility(layer: stack, startTime: caption.startTime,
                          endTime: caption.endTime, totalDuration: duration)
        return stack
    }

    // Shared visibility animation helper
    private func animateVisibility(layer: CALayer, startTime: TimeInterval,
                                   endTime: TimeInterval, totalDuration: CMTime) {
        let showAnim = CABasicAnimation(keyPath: "opacity")
        showAnim.fromValue = 0; showAnim.toValue = 1
        showAnim.beginTime = startTime; showAnim.duration = 0.01
        showAnim.fillMode = .forwards; showAnim.isRemovedOnCompletion = false

        let hideAnim = CABasicAnimation(keyPath: "opacity")
        hideAnim.fromValue = 1; hideAnim.toValue = 0
        hideAnim.beginTime = endTime; hideAnim.duration = 0.01
        hideAnim.fillMode = .forwards; hideAnim.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [showAnim, hideAnim]
        group.duration = CMTimeGetSeconds(totalDuration)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.opacity = 0
        layer.add(group, forKey: "visibility")
    }

    // MARK: - Render Size Helper

    func getRenderSize(from composition: AVMutableComposition) async throws -> CGSize {
        guard let videoTrack = try await composition.loadTracks(withMediaType: .video).first else {
            return CGSize(width: 1080, height: 1920)
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform   = try await videoTrack.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    // MARK: - Base VideoComposition (orientation only)

    func buildBaseVideoComposition(
        from composition: AVMutableComposition,
        renderSize: CGSize
    ) async throws -> AVMutableVideoComposition {
        let vc = AVMutableVideoComposition()
        vc.renderSize    = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

        if let track = try await composition.loadTracks(withMediaType: .video).first {
            let transform = try await track.load(.preferredTransform)
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            li.setTransform(transform, at: .zero)
            instruction.layerInstructions = [li]
        }
        vc.instructions = [instruction]
        return vc
    }
}
