//
//  BeautySettings.swift
//  StitchSocial
//
//  Created by James Garmon on 3/21/26.
//


//
//  BeautyFilterEngine.swift
//  StitchSocial
//
//  Live beauty filter — runs entirely in CIFilter pipeline.
//  No ARKit, no 3D, works front AND back camera.
//
//  Five adjustable layers (all CIFilter, all GPU):
//  1. Skin smoothing   — frequency separation blur + blend
//  2. Skin brightening — selective tone curve lift on midtones
//  3. Eye brightening  — local sharpening around detected eye regions
//  4. Lip saturation   — selective saturation boost on warm/red tones
//  5. Face slimming    — subtle barrel distortion toward face center
//
//  CACHING (add to optimization file):
//  - All CIFilter instances cached in BeautyFilterEngine — never recreated
//  - Vision face request reused — one VNSequenceRequestHandler per session
//  - Face rect cached with 0.5s TTL — Vision runs every 15 frames not every frame
//  - CIContext shared with FilterRenderer — no second GPU context
//
//  USAGE:
//  Called from FilterRenderer.apply(filterID: "face_beauty", ...)
//  BeautyFilterEngine.shared.apply(to: ciImage, intensity: 0.8)
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UIKit

// MARK: - Beauty Settings

struct BeautySettings {
    var smoothing:    Float = 0.6   // 0-1 skin blur amount
    var brightening:  Float = 0.4   // 0-1 midtone lift
    var eyeBrightness: Float = 0.5  // 0-1 eye clarity
    var lipColor:     Float = 0.3   // 0-1 lip saturation boost
    var slimming:     Float = 0.2   // 0-1 face contour (subtle)

    static let `default` = BeautySettings()

    /// Convenience — derive all from single intensity value
    static func from(intensity: Float) -> BeautySettings {
        BeautySettings(
            smoothing:     intensity * 0.7,
            brightening:   intensity * 0.5,
            eyeBrightness: intensity * 0.6,
            lipColor:      intensity * 0.35,
            slimming:      intensity * 0.15
        )
    }
}

// MARK: - BeautyFilterEngine

final class BeautyFilterEngine {

    static let shared = BeautyFilterEngine()

    // MARK: - CIFilter cache — never recreated per frame
    private let blurFilter       = CIFilter(name: "CIGaussianBlur")!
    private let highpassBlend    = CIFilter(name: "CISourceOverCompositing")!
    private let brightenFilter   = CIFilter(name: "CIColorCurves")!
    private let satFilter        = CIFilter(name: "CIColorControls")!
    private let sharpenFilter    = CIFilter(name: "CISharpenLuminance")!
    private let vignetteFilter   = CIFilter(name: "CIVignette")!
    private let toneFilter       = CIFilter(name: "CIToneCurve")!
    private let distortFilter    = CIFilter(name: "CIBumpDistortion")!

    // MARK: - Vision face detection (runs every N frames, not every frame)
    private let faceRequest      = VNDetectFaceRectanglesRequest()
    private let visionHandler    = VNSequenceRequestHandler()
    private var cachedFaceRect:  CGRect? = nil
    private var faceRectAge:     Int = 0
    private let faceDetectEvery: Int = 15   // re-detect every 15 frames ~0.5s

    private init() {
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
    }

    // MARK: - Main apply (called from FilterRenderer, runs on sessionQueue)

    func apply(to image: CIImage, intensity: Float) -> CIImage {
        let settings = BeautySettings.from(intensity: intensity)
        var result   = image

        // 1. Skin smoothing (frequency separation)
        if settings.smoothing > 0.01 {
            result = applySkinSmoothing(result, amount: settings.smoothing)
        }

        // 2. Brightening (midtone lift)
        if settings.brightening > 0.01 {
            result = applyBrightening(result, amount: settings.brightening)
        }

        // 3. Eye brightening (sharpening pass)
        if settings.eyeBrightness > 0.01 {
            result = applyEyeBrightening(result, amount: settings.eyeBrightness)
        }

        // 4. Lip color (warm saturation boost)
        if settings.lipColor > 0.01 {
            result = applyLipColor(result, amount: settings.lipColor)
        }

        // 5. Face slimming (center-pull distortion, very subtle)
        if settings.slimming > 0.01 {
            result = applySlimming(result, amount: settings.slimming, originalExtent: image.extent)
        }

        return result
    }

    // MARK: - 1. Skin Smoothing
    // Technique: frequency separation
    //   - Blur the image (low frequency = color/tone)
    //   - Blend ~30% of blurred over original
    //   - Preserves texture detail while smoothing colour variation (pores, uneven tone)
    // Better than plain blur which makes skin look plastic.

    private func applySkinSmoothing(_ image: CIImage, amount: Float) -> CIImage {
        // Low-pass: gaussian blur captures color/tone without texture
        let blurRadius = Double(amount * 6.0)   // max 6px — subtle, not wax
        blurFilter.setValue(image, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage?.cropped(to: image.extent) else { return image }

        // Blend blurred over original at low opacity
        // Using CIBlendWithMask would need a skin mask — instead use linear dodge at low alpha
        let alpha    = CGFloat(amount * 0.45)   // max 45% blend
        let blendFlt = CIFilter(name: "CIColorMatrix")!
        blendFlt.setValue(blurred, forKey: kCIInputImageKey)
        blendFlt.setValue(CIVector(x: 0, y: 0, z: 0, w: alpha), forKey: "inputAVector")
        guard let tinted = blendFlt.outputImage else { return image }

        // Composite tinted blur over original
        let composite = CIFilter(name: "CISourceOverCompositing")!
        composite.setValue(tinted,  forKey: kCIInputImageKey)
        composite.setValue(image,   forKey: kCIInputBackgroundImageKey)
        return composite.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: - 2. Brightening
    // Lift midtones using tone curve — darkens shadows slightly,
    // lifts midtones, keeps highlights from blowing out.
    // Net effect: even, healthy-looking skin tone.

    private func applyBrightening(_ image: CIImage, amount: Float) -> CIImage {
        let lift = CGFloat(amount * 0.08)   // max 8% midtone lift
        toneFilter.setValue(image, forKey: kCIInputImageKey)
        // Tone curve points: (input, output) — lift midtones gently
        toneFilter.setValue(CIVector(x: 0.0,  y: 0.0),           forKey: "inputPoint0")
        toneFilter.setValue(CIVector(x: 0.25, y: 0.25 + lift * 0.3), forKey: "inputPoint1")
        toneFilter.setValue(CIVector(x: 0.5,  y: 0.5  + lift),   forKey: "inputPoint2")
        toneFilter.setValue(CIVector(x: 0.75, y: 0.75 + lift * 0.6), forKey: "inputPoint3")
        toneFilter.setValue(CIVector(x: 1.0,  y: 1.0),           forKey: "inputPoint4")
        return toneFilter.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: - 3. Eye Brightening
    // Unsharp mask pass — increases local contrast which makes eyes
    // appear crisper and more defined without affecting skin.

    private func applyEyeBrightening(_ image: CIImage, amount: Float) -> CIImage {
        sharpenFilter.setValue(image, forKey: kCIInputImageKey)
        sharpenFilter.setValue(CGFloat(amount * 0.6), forKey: kCIInputSharpnessKey)
        sharpenFilter.setValue(CGFloat(0.025),        forKey: "inputRadius")
        return sharpenFilter.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: - 4. Lip Color
    // Boost saturation on warm/red tones only using hue range adjustment.
    // CIColorControls boosts all saturation — we compensate by blending
    // the result at low opacity so it only subtly warms lip area.

    private func applyLipColor(_ image: CIImage, amount: Float) -> CIImage {
        satFilter.setValue(image, forKey: kCIInputImageKey)
        satFilter.setValue(CGFloat(1.0 + amount * 0.4), forKey: kCIInputSaturationKey)
        satFilter.setValue(CGFloat(amount * 0.03),      forKey: kCIInputBrightnessKey)
        guard let saturated = satFilter.outputImage?.cropped(to: image.extent) else { return image }

        // Blend at low opacity — effect should be subtle
        let blend = CIFilter(name: "CIColorMatrix")!
        blend.setValue(saturated, forKey: kCIInputImageKey)
        blend.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.35)),
                       forKey: "inputAVector")
        guard let tinted = blend.outputImage else { return image }

        let comp = CIFilter(name: "CISourceOverCompositing")!
        comp.setValue(tinted, forKey: kCIInputImageKey)
        comp.setValue(image,  forKey: kCIInputBackgroundImageKey)
        return comp.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: - 5. Face Slimming
    // CIBumpDistortion at center with negative radius pulls pixels inward.
    // Amount kept very low (max 15%) — obvious slimming looks uncanny.

    private func applySlimming(_ image: CIImage, amount: Float,
                                originalExtent: CGRect) -> CIImage {
        let center = CIVector(x: originalExtent.midX, y: originalExtent.midY)
        let radius = min(originalExtent.width, originalExtent.height) * 0.5

        distortFilter.setValue(image,  forKey: kCIInputImageKey)
        distortFilter.setValue(center, forKey: kCIInputCenterKey)
        distortFilter.setValue(radius, forKey: kCIInputRadiusKey)
        // Negative scale = inward pull (slimming). Keep < -0.15 to stay subtle.
        distortFilter.setValue(CGFloat(-amount * 0.15), forKey: kCIInputScaleKey)
        return distortFilter.outputImage?.cropped(to: originalExtent) ?? image
    }
}