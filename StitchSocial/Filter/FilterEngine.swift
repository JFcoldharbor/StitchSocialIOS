//
//  FilterEngine.swift
//  StitchSocial
//
//  Singleton filter engine — all filter rendering goes through here.
//  CinematicCameraManager calls FilterEngine.shared.apply(...)
//  FilterPickerView reads FilterEngine.shared.availableFilters
//
//  CACHING (add to optimization file):
//  - manifests: fetched ONCE on launch, cached 30min TTL
//  - ciFilterCache: CIFilter instances keyed by filterID — never recreated
//  - ciContext: Metal-backed, single instance, app lifetime
//  - assetCache: downloaded LUT/texture data keyed by URL
//
//  BATCHING:
//  - All filter docs fetched in ONE Firestore query (not per-filter)
//  - Asset downloads batched on first need, then cached to disk
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class FilterEngine: ObservableObject {

    static let shared = FilterEngine()

    // MARK: - Published
    @Published var availableFilters: [FilterManifest] = []
    @Published var isLoaded = false

    // MARK: - Nonisolated render state (safe from capture delegate)
    let renderer = FilterRenderer()

    // MARK: - Firestore
    private let db = Firestore.firestore(database: "stitchfin")
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 1800 // 30 min

    private init() {}

    // MARK: - Load (call once on app launch)

    func load() async {
        // TTL check — don't re-fetch within 30min
        if let ts = cacheTimestamp, Date().timeIntervalSince(ts) < cacheTTL, isLoaded { return }

        do {
            // BATCH: single query — all active filters, ordered
            let snap = try await db.collection("filters")
                .whereField("isActive", isEqualTo: true)
                .order(by: "sortOrder")
                .getDocuments()

            let filters = snap.documents.compactMap { FilterManifest.from($0) }
                .filter { $0.platforms.contains(.ios) }

            availableFilters = filters
            cacheTimestamp   = Date()
            isLoaded         = true

            // Pre-warm CIFilter instances for color filters
            renderer.prewarm(filters.filter { $0.type == .ciFilter })
            print("✅ FILTER ENGINE: Loaded \(filters.count) filters")
        } catch {
            // Fallback to built-in defaults if Firestore fails
            availableFilters = FilterSeed.defaultFilters.filter { $0.platforms.contains(.ios) }
            isLoaded = true
            print("⚠️ FILTER ENGINE: Firestore failed, using defaults")
        }
    }

    // MARK: - Apply (called from CinematicCameraManager — nonisolated context)

    nonisolated func apply(filterID: String, to image: CIImage, intensity: Float) -> CIImage {
        renderer.apply(filterID: filterID, to: image, intensity: intensity)
    }

    // MARK: - Filters by category

    func filters(for category: FilterCategory) -> [FilterManifest] {
        availableFilters.filter { $0.category == category }
    }

    func canUse(_ filter: FilterManifest, userTier: String) -> Bool {
        switch filter.tier {
        case .free:       return true
        case .subscriber: return ["subscriber", "influencer", "elite", "partner",
                                  "legendary", "top_creator", "founder", "co_founder"].contains(userTier)
        case .premium:    return ["elite", "partner", "legendary",
                                  "top_creator", "founder", "co_founder"].contains(userTier)
        }
    }
}

// MARK: - FilterRenderer (nonisolated — used from capture queue)

final class FilterRenderer {

    // CACHE: single Metal CIContext — NEVER create per frame
    private let ciContext: CIContext
    private let device:    MTLDevice?

    // CACHE: CIFilter instances keyed by filterID
    private var filterCache: [String: CIFilter] = [:]

    // CACHE: downloaded LUT data keyed by URL string
    private var assetCache: [String: Data] = [:]

    init() {
        let dev  = MTLCreateSystemDefaultDevice()
        device   = dev
        ciContext = dev.map {
            CIContext(mtlDevice: $0, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .outputColorSpace:  CGColorSpace(name: CGColorSpace.sRGB) as Any
            ])
        } ?? CIContext()
    }

    // Pre-warm filter instances so first frame has no stutter
    func prewarm(_ manifests: [FilterManifest]) {
        for m in manifests {
            guard filterCache[m.id] == nil else { continue }
            if let f = ciFilterName(for: m.id).flatMap({ CIFilter(name: $0) }) {
                filterCache[m.id] = f
            }
        }
        print("🔥 FILTER RENDERER: Pre-warmed \(filterCache.count) filters")
    }

    // MARK: - Apply

    func apply(filterID: String, to image: CIImage, intensity: Float) -> CIImage {
        switch filterID {
        case "color_vivid":      return applyVivid(image, intensity: intensity)
        case "color_warm":       return applyWarm(image, intensity: intensity)
        case "color_cool":       return applyCool(image, intensity: intensity)
        case "color_dramatic":   return applyDramatic(image, intensity: intensity)
        case "color_cinematic":  return applyCinematic(image, intensity: intensity)
        case "color_vintage":    return applyVintage(image, intensity: intensity)
        case "color_monochrome": return applyMonochrome(image, intensity: intensity)
        case "color_sunset":     return applySunset(image, intensity: intensity)
        case "face_beauty",
             "beauty":           return applyBeauty(image, intensity: intensity)
        default:                 return image
        }
    }

    // MARK: - Render to texture (for MTKView)

    func render(_ image: CIImage, to texture: MTLTexture,
                commandBuffer: MTLCommandBuffer?, bounds: CGRect) {
        ciContext.render(image, to: texture, commandBuffer: commandBuffer,
                         bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer) {
        ciContext.render(image, to: pixelBuffer)
    }

    // MARK: - Filter Implementations

    private func applyVivid(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_vivid", name: "CIVibrance")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(intensity * 1.5, forKey: "inputAmount")
        return f.outputImage ?? image
    }

    private func applyWarm(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_warm", name: "CITemperatureAndTint")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: CGFloat(6500 - 2500 * intensity), y: 0), forKey: "inputNeutral")
        f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        return f.outputImage ?? image
    }

    private func applyCool(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_cool", name: "CITemperatureAndTint")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: CGFloat(6500 + 2500 * intensity), y: 0), forKey: "inputNeutral")
        f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        return f.outputImage ?? image
    }

    private func applyDramatic(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_dramatic", name: "CIColorControls")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CGFloat(1.0 + intensity * 0.8), forKey: kCIInputContrastKey)
        f.setValue(CGFloat(-intensity * 0.05), forKey: kCIInputBrightnessKey)
        f.setValue(CGFloat(1.0 - intensity * 0.3), forKey: kCIInputSaturationKey)
        return f.outputImage ?? image
    }

    private func applyCinematic(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_cinematic", name: "CIColorControls")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CGFloat(1.0 + intensity * 0.3), forKey: kCIInputContrastKey)
        f.setValue(CGFloat(1.0 - intensity * 0.25), forKey: kCIInputSaturationKey)
        let v = CIFilter(name: "CIVignette")!
        v.setValue(f.outputImage ?? image, forKey: kCIInputImageKey)
        v.setValue(CGFloat(intensity * 1.5), forKey: kCIInputIntensityKey)
        v.setValue(CGFloat(intensity * 2.0), forKey: kCIInputRadiusKey)
        return v.outputImage ?? image
    }

    private func applyVintage(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_vintage", name: "CIPhotoEffectProcess")
        f.setValue(image, forKey: kCIInputImageKey)
        return f.outputImage?.applyingFilter("CISepiaTone",
            parameters: [kCIInputIntensityKey: intensity * 0.4]) ?? image
    }

    private func applyMonochrome(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_monochrome", name: "CIColorMonochrome")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIColor.gray, forKey: kCIInputColorKey)
        f.setValue(CGFloat(intensity), forKey: kCIInputIntensityKey)
        return f.outputImage ?? image
    }

    private func applySunset(_ image: CIImage, intensity: Float) -> CIImage {
        let f = cachedFilter("color_sunset", name: "CITemperatureAndTint")
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: 4000, y: 0), forKey: "inputNeutral")
        f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        let warmed = f.outputImage ?? image
        let sat = CIFilter(name: "CIColorControls")!
        sat.setValue(warmed, forKey: kCIInputImageKey)
        sat.setValue(CGFloat(1.0 + intensity * 0.6), forKey: kCIInputSaturationKey)
        return sat.outputImage ?? image
    }

    private func applyBeauty(_ image: CIImage, intensity: Float) -> CIImage {
        var result = image
        let amount = CGFloat(intensity)

        // 1. Skin smoothing — frequency separation
        let blur = cachedFilter("beauty_blur", name: "CIGaussianBlur")
        blur.setValue(result, forKey: kCIInputImageKey)
        blur.setValue(Double(intensity * 5.0), forKey: kCIInputRadiusKey)
        if let blurred = blur.outputImage?.cropped(to: image.extent) {
            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(blurred, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: amount * 0.45), forKey: "inputAVector")
            if let tinted = matrix.outputImage {
                let comp = CIFilter(name: "CISourceOverCompositing")!
                comp.setValue(tinted,  forKey: kCIInputImageKey)
                comp.setValue(result,  forKey: kCIInputBackgroundImageKey)
                result = comp.outputImage?.cropped(to: image.extent) ?? result
            }
        }

        // 2. Tone brightening — midtone lift
        let tone = cachedFilter("beauty_tone", name: "CIToneCurve")
        let lift = amount * 0.07
        tone.setValue(result, forKey: kCIInputImageKey)
        tone.setValue(CIVector(x: 0,    y: 0),          forKey: "inputPoint0")
        tone.setValue(CIVector(x: 0.25, y: 0.25 + lift * 0.3), forKey: "inputPoint1")
        tone.setValue(CIVector(x: 0.5,  y: 0.5  + lift), forKey: "inputPoint2")
        tone.setValue(CIVector(x: 0.75, y: 0.75 + lift * 0.6), forKey: "inputPoint3")
        tone.setValue(CIVector(x: 1.0,  y: 1.0),        forKey: "inputPoint4")
        result = tone.outputImage?.cropped(to: image.extent) ?? result

        // 3. Eye sharpening
        let sharp = cachedFilter("beauty_sharp", name: "CISharpenLuminance")
        sharp.setValue(result, forKey: kCIInputImageKey)
        sharp.setValue(amount * 0.5, forKey: kCIInputSharpnessKey)
        sharp.setValue(0.025,        forKey: "inputRadius")
        result = sharp.outputImage?.cropped(to: image.extent) ?? result

        // 4. Subtle face slimming
        let bump = cachedFilter("beauty_bump", name: "CIBumpDistortion")
        let center = CIVector(x: image.extent.midX, y: image.extent.midY)
        let radius = min(image.extent.width, image.extent.height) * 0.5
        bump.setValue(result,  forKey: kCIInputImageKey)
        bump.setValue(center,  forKey: kCIInputCenterKey)
        bump.setValue(radius,  forKey: kCIInputRadiusKey)
        bump.setValue(-amount * 0.12, forKey: kCIInputScaleKey)
        result = bump.outputImage?.cropped(to: image.extent) ?? result

        return result
    }

    // MARK: - Cache helper

    private func cachedFilter(_ id: String, name: String) -> CIFilter {
        if let f = filterCache[id] { return f }
        let f = CIFilter(name: name) ?? CIFilter(name: "CIColorControls")!
        filterCache[id] = f
        return f
    }

    private func ciFilterName(for id: String) -> String? {
        switch id {
        case "color_vivid":      return "CIVibrance"
        case "color_warm",
             "color_cool",
             "color_sunset":     return "CITemperatureAndTint"
        case "color_dramatic",
             "color_cinematic":  return "CIColorControls"
        case "color_vintage":    return "CIPhotoEffectProcess"
        case "color_monochrome": return "CIColorMonochrome"
        default:                 return nil
        }
    }
}
