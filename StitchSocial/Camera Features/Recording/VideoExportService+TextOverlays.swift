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

        // Skip empty stickers (see buildCombinedAnimationTool for rationale).
        let visibleOverlays = overlays.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for overlay in visibleOverlays {
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

        // Resolve font matching the preview's overlay.font.swiftUIFont(...).
        // .handwritten always uses SnellRoundhand-Bold to match TextStickerView.
        // .typewriter falls back to a monospaced system font if Courier-style
        // fonts aren't available — same behavior as preview's monospaced design.
        let font = resolveFont(for: overlay)

        // Measure at base font size only — scale is applied as a transform on
        // the container so padding scales uniformly (matches preview's
        // .scaleEffect(overlay.scale) behavior).
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (overlay.text as NSString).size(withAttributes: attrs)

        // Per-style padding matching TextStickerView.
        let (hPad, vPad): (CGFloat, CGFloat) = paddingFor(style: overlay.style)
        let layerW = textSize.width  + hPad * 2
        let layerH = textSize.height + vPad * 2

        // Position from normalizedX/Y (0…1 of render size).
        // CoreAnimation isGeometryFlipped = true on the parent so y is in
        // video pixel space (0=top, height=bottom), matching SwiftUI's
        // .position(x:y:) coordinate system in the preview.
        let cx = overlay.normalizedX * renderSize.width
        let cy = overlay.normalizedY * renderSize.height
        let frame = CGRect(
            x: cx - layerW / 2,
            y: cy - layerH / 2,
            width: layerW,
            height: layerH
        )

        // Container layer — applies rotation AND scale so chrome (padding,
        // backgrounds, borders) scales with the text. anchorPoint stays at
        // (0.5, 0.5) so transforms pivot around the center.
        let container = CALayer()
        container.frame = frame
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let rotationRad = overlay.rotation * .pi / 180
        let scaleT = CATransform3DMakeScale(overlay.scale, overlay.scale, 1)
        let rotateT = CATransform3DMakeRotation(rotationRad, 0, 0, 1)
        container.transform = CATransform3DConcat(scaleT, rotateT)

        // Per-style chrome (background, border, drop shadow).
        applyStyleChrome(to: container, overlay: overlay, layerH: layerH)

        // Text layer(s) — gradient and glitch use multiple layers; others
        // use a single CATextLayer.
        addTextLayers(to: container, overlay: overlay, font: font, textSize: textSize, hPad: hPad, vPad: vPad)

        // Visibility timing. If start/end are set the layer stays opacity 0
        // until startTime, then fades to 1, then fades back to 0 at endTime.
        // If no time range set, the layer is always visible (opacity stays
        // at default 1 — no animation needed).
        if let start = overlay.startTime, let end = overlay.endTime {
            installVisibilityAnimation(on: container, start: start, end: end, totalDuration: duration)
        }

        // Phase 3 — entrance animation if the user picked one.
        installEntranceAnimation(on: container, overlay: overlay)

        return container
    }

    // MARK: - Font resolution

    private func resolveFont(for overlay: TextOverlay) -> UIFont {
        // Handwritten style is locked to script font regardless of overlay.font
        // (matches preview which hardcodes SnellRoundhand-Bold).
        if overlay.style == .handwritten {
            return UIFont(name: "SnellRoundhand-Bold", size: overlay.fontSize)
                ?? UIFont.italicSystemFont(ofSize: overlay.fontSize)
        }

        // Default sans / Typewriter use system designs in preview; mirror that
        // by falling back to system fonts with matching weight/design.
        if overlay.font == .defaultSans {
            return UIFont.systemFont(
                ofSize: overlay.fontSize,
                weight: overlay.isBold ? .bold : .semibold
            )
        }
        if overlay.font == .typewriter {
            // .system(...design: .monospaced) in preview → use monospaced system.
            if #available(iOS 13.0, *) {
                let weight: UIFont.Weight = overlay.isBold ? .bold : .regular
                return UIFont.monospacedSystemFont(ofSize: overlay.fontSize, weight: weight)
            }
            return UIFont(name: "Menlo", size: overlay.fontSize)
                ?? UIFont.systemFont(ofSize: overlay.fontSize, weight: overlay.isBold ? .bold : .regular)
        }

        return UIFont(name: overlay.font.postScriptName, size: overlay.fontSize)
            ?? UIFont.systemFont(ofSize: overlay.fontSize, weight: overlay.isBold ? .bold : .semibold)
    }

    private func paddingFor(style: TextOverlayStyle) -> (h: CGFloat, v: CGFloat) {
        switch style {
        case .boldPill:    return (14, 7)
        case .outline:     return (8, 4)
        case .neon:        return (14, 7)
        case .typewriter:  return (12, 6)
        case .gradient:    return (8, 4)
        case .ribbon:      return (18, 8)
        case .shadow:      return (8, 4)
        case .glitch:      return (8, 4)
        case .handwritten: return (8, 4)
        case .sticker:     return (14, 8)
        }
    }

    // MARK: - Style chrome

    private func applyStyleChrome(to container: CALayer, overlay: TextOverlay, layerH: CGFloat) {
        switch overlay.style {
        case .boldPill:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = layerH / 2

        case .typewriter:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = 4

        case .neon:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = 8
            container.shadowColor = overlay.textColor.cgColor
            container.shadowRadius = 12
            container.shadowOpacity = 0.9
            container.shadowOffset = .zero

        case .outline, .gradient, .shadow, .glitch, .handwritten:
            container.backgroundColor = UIColor.clear.cgColor

        case .ribbon:
            // Stroke a notched-banner shape behind the text via CAShapeLayer.
            let shape = CAShapeLayer()
            shape.frame = container.bounds
            shape.path = ribbonPath(in: container.bounds).cgPath
            shape.fillColor = overlay.bgColor.cgColor
            container.addSublayer(shape)

        case .sticker:
            container.backgroundColor = overlay.bgColor.cgColor
            container.cornerRadius = 12
            container.borderColor = UIColor.white.cgColor
            container.borderWidth = 4
        }
    }

    private func ribbonPath(in rect: CGRect) -> UIBezierPath {
        let notch = min(10, rect.height / 2)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - notch, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: notch, y: rect.midY))
        p.close()
        return p
    }

    // MARK: - Text layers

    private func addTextLayers(
        to container: CALayer,
        overlay: TextOverlay,
        font: UIFont,
        textSize: CGSize,
        hPad: CGFloat,
        vPad: CGFloat
    ) {
        let textFrame = CGRect(x: hPad, y: vPad, width: textSize.width, height: textSize.height)

        switch overlay.style {
        case .gradient:
            // CAGradientLayer masked by the text shape.
            let textMask = makeTextLayer(text: overlay.text, font: font, color: .white, frame: textFrame)
            let grad = CAGradientLayer()
            grad.frame = textFrame
            grad.colors = [
                overlay.textColor.cgColor,
                overlay.textColor.withAlphaComponent(0.5).cgColor
            ]
            grad.startPoint = CGPoint(x: 0, y: 0)
            grad.endPoint = CGPoint(x: 1, y: 1)
            grad.mask = textMask
            container.addSublayer(grad)

        case .glitch:
            // RGB-split: cyan offset left, red offset right, white in center.
            let cyan = makeTextLayer(text: overlay.text, font: font, color: .cyan, frame: textFrame.offsetBy(dx: -2, dy: 0))
            let red = makeTextLayer(text: overlay.text, font: font, color: .red, frame: textFrame.offsetBy(dx: 2, dy: 0))
            let main = makeTextLayer(text: overlay.text, font: font, color: overlay.textColor, frame: textFrame)
            container.addSublayer(cyan)
            container.addSublayer(red)
            container.addSublayer(main)

        case .outline:
            // Re-create the preview's three-direction shadow trick with a
            // single text layer — only one shadow direction is supported by
            // CALayer, so we fake the rest by stacking offset copies.
            let dirs: [(CGFloat, CGFloat)] = [(1, 1), (-1, -1), (1, -1), (-1, 1)]
            for (dx, dy) in dirs {
                let stroke = makeTextLayer(text: overlay.text, font: font, color: overlay.textColor, frame: textFrame.offsetBy(dx: dx, dy: dy))
                stroke.opacity = 0.6
                container.addSublayer(stroke)
            }
            let main = makeTextLayer(text: overlay.text, font: font, color: overlay.textColor, frame: textFrame)
            container.addSublayer(main)

        case .shadow:
            let main = makeTextLayer(text: overlay.text, font: font, color: overlay.textColor, frame: textFrame)
            main.shadowColor = UIColor.black.cgColor
            main.shadowOpacity = 0.85
            main.shadowOffset = CGSize(width: 4, height: 4)
            main.shadowRadius = 0
            container.addSublayer(main)

        default:
            // .boldPill, .typewriter, .neon, .ribbon, .handwritten, .sticker
            let main = makeTextLayer(text: overlay.text, font: font, color: overlay.textColor, frame: textFrame)
            container.addSublayer(main)
        }
    }

    private func makeTextLayer(text: String, font: UIFont, color: UIColor, frame: CGRect) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.font = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        layer.fontSize = font.pointSize
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .center
        layer.isWrapped = false
        layer.contentsScale = UIScreen.main.scale
        return layer
    }

    // MARK: - Visibility / entrance animations

    private func installVisibilityAnimation(on layer: CALayer, start: TimeInterval, end: TimeInterval, totalDuration: CMTime) {
        let showAt = CABasicAnimation(keyPath: "opacity")
        showAt.fromValue = 0; showAt.toValue = 1
        showAt.beginTime = start; showAt.duration = 0.01
        showAt.fillMode = .forwards; showAt.isRemovedOnCompletion = false

        let hideAt = CABasicAnimation(keyPath: "opacity")
        hideAt.fromValue = 1; hideAt.toValue = 0
        hideAt.beginTime = end; hideAt.duration = 0.01
        hideAt.fillMode = .forwards; hideAt.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [showAt, hideAt]
        group.duration = CMTimeGetSeconds(totalDuration)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.opacity = 0
        layer.add(group, forKey: "visibility")
    }

    // Phase 3 — entrance animation. Plays once at the overlay's startTime
    // (or t=0 if no time range was set). Each style maps to a CAAnimation
    // pattern that approximates the SwiftUI preview behavior.
    private func installEntranceAnimation(on layer: CALayer, overlay: TextOverlay) {
        guard overlay.animation != .none else { return }

        let beginAt = overlay.startTime ?? 0
        let dur = overlay.animation.duration

        switch overlay.animation {
        case .none:
            return

        case .fadeIn:
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.beginTime = beginAt; fade.duration = dur
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "entrance")

        case .popIn:
            // Scale 0 → 1.1 → 1 with opacity 0 → 1.
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.0, 1.15, 0.95, 1.0]
            scale.keyTimes = [0, 0.55, 0.8, 1.0]
            scale.beginTime = beginAt; scale.duration = dur
            scale.fillMode = .forwards; scale.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.beginTime = beginAt; fade.duration = dur * 0.4
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false

            layer.add(scale, forKey: "entranceScale")
            layer.add(fade, forKey: "entranceFade")

        case .slideUp:
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = 60; slide.toValue = 0
            slide.beginTime = beginAt; slide.duration = dur
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slide.fillMode = .forwards; slide.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.beginTime = beginAt; fade.duration = dur * 0.6
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false

            layer.add(slide, forKey: "entranceSlide")
            layer.add(fade, forKey: "entranceFade")

        case .bounce:
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [0.0, 1.3, 0.85, 1.1, 0.97, 1.0]
            bounce.keyTimes = [0, 0.4, 0.6, 0.75, 0.9, 1.0]
            bounce.beginTime = beginAt; bounce.duration = dur
            bounce.fillMode = .forwards; bounce.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.beginTime = beginAt; fade.duration = dur * 0.3
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false

            layer.add(bounce, forKey: "entranceBounce")
            layer.add(fade, forKey: "entranceFade")

        case .typewriter:
            // A coarse approximation: reveal in 5 steps via opacity stair-step.
            // True per-character reveal would require splitting the text into
            // per-glyph CATextLayers; this is the cheap version that still
            // reads as a "typing" fade in for short overlays.
            let steps = CAKeyframeAnimation(keyPath: "opacity")
            steps.values = [0.0, 0.0, 0.4, 0.7, 1.0]
            steps.keyTimes = [0, 0.05, 0.4, 0.7, 1.0]
            steps.beginTime = beginAt; steps.duration = dur
            steps.calculationMode = .discrete
            steps.fillMode = .forwards; steps.isRemovedOnCompletion = false
            layer.add(steps, forKey: "entranceType")
        }
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

        // Skip overlays whose text is empty or whitespace-only — these are
        // ghost stickers from a tap-to-create that the user never typed
        // into, and would render as a tiny invisible chrome rectangle.
        let visibleOverlays = overlays.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let droppedCount = overlays.count - visibleOverlays.count
        if droppedCount > 0 {
            #if DEBUG
            print("📝 EXPORT: dropped \(droppedCount) empty text overlay(s)")
            #endif
        }
        #if DEBUG
        print("📝 EXPORT: rendering \(visibleOverlays.count) text overlay(s), \(captions.count) caption(s) at renderSize=\(renderSize)")
        #endif

        // Text overlay stickers
        for overlay in visibleOverlays {
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

        // Standard caption: white text, black pill background, bold 22pt.
        // Matches StandardCaptionText in the preview 1:1.
        let fontSize: CGFloat = 22
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textColor = UIColor.white
        let bgColor = UIColor.black.withAlphaComponent(0.6)

        let cx = renderSize.width / 2
        let cy = renderSize.height * caption.position.safeOffset

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth = renderSize.width * 0.85
        let textSize = (caption.text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        ).size

        let hPad: CGFloat = 16
        let vPad: CGFloat = 8
        let layerW = min(textSize.width + hPad * 2, renderSize.width * 0.92)
        let layerH = textSize.height + vPad * 2

        let frame = CGRect(
            x: cx - layerW / 2,
            y: cy - layerH / 2,
            width: layerW, height: layerH
        )

        let container = CALayer()
        container.frame = frame
        container.backgroundColor = bgColor.cgColor
        container.cornerRadius = layerH / 2  // pill

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

        animateVisibility(layer: container, startTime: caption.startTime,
                          endTime: caption.endTime, totalDuration: duration)
        return container
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
}
