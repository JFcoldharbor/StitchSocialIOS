//
//  GreenScreenProcessor.swift
//  StitchSocial
//
//  Debug version — logs every critical step to console.
//  Search "🟢 GREEN SCREEN" in Xcode console to trace issues.

import Foundation
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import MetalKit

// MARK: - Background Mode

enum GreenScreenBackground: Equatable {
    case blur(radius: Float)
    case solidColor(Color)
    case image(UIImage)
}

// MARK: - Nonisolated atomic flag

private let _gsLock = NSLock()
private var _gsIsActive: Bool = false

// MARK: - Processor

@MainActor
class GreenScreenProcessor: ObservableObject {

    static let shared = GreenScreenProcessor()

    @Published var isActive = false
    @Published var processedFrame: CIImage?
    @Published var background: GreenScreenBackground = .blur(radius: 20)

    // Debug counters
    private var frameReceived = 0
    private var frameProcessed = 0
    private var frameDropped = 0

    nonisolated var isActiveAtomic: Bool {
        _gsLock.lock(); defer { _gsLock.unlock() }
        return _gsIsActive
    }
    private func setActiveAtomic(_ value: Bool) {
        _gsLock.lock(); _gsIsActive = value; _gsLock.unlock()
    }

    private var segmentationRequest: VNGeneratePersonSegmentationRequest?
    private nonisolated let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cachedBackgroundImage: CIImage?
    private var lastBackground: GreenScreenBackground?

    private let processingQueue = DispatchQueue(label: "greenscreen.vision", qos: .userInteractive)

    // MARK: - Activation

    func activate() {
        print("🟢 GREEN SCREEN: activate() called")
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        segmentationRequest = req
        isActive = true
        setActiveAtomic(true)
        frameReceived = 0; frameProcessed = 0; frameDropped = 0
        print("🟢 GREEN SCREEN: Activated — request=\(req), qualityLevel=balanced")
        print("🟢 GREEN SCREEN: isActiveAtomic=\(isActiveAtomic)")
    }

    func deactivate() {
        print("🟢 GREEN SCREEN: deactivate() called — frames: received=\(frameReceived) processed=\(frameProcessed) dropped=\(frameDropped)")
        isActive = false
        setActiveAtomic(false)
        segmentationRequest = nil
        cachedBackgroundImage = nil
        lastBackground = nil
        processedFrame = nil
    }

    func cleanup() {
        deactivate()
        print("🟢 GREEN SCREEN: Cleanup complete")
    }

    // MARK: - Frame Processing

    /// Called from MainActor with a CVPixelBuffer (Sendable — safe across actor boundaries).
    func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        frameReceived += 1
        guard let request = segmentationRequest else {
            if frameReceived == 1 { print("🟢 GREEN SCREEN ❌ No segmentationRequest — was activate() called?") }
            frameDropped += 1; return
        }
        if frameReceived == 1 {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            print("🟢 GREEN SCREEN ✅ First pixel buffer — \(w)x\(h) (will rotate to portrait)")
        }
        // Raw pixel buffer is landscape — rotate to portrait so Vision mask
        // aligns with the preview layer orientation.
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let currentBG = background
        processingQueue.async { [weak self] in
            guard let self else { return }
            let handler = VNImageRequestHandler(ciImage: sourceImage, options: [:])
            do { try handler.perform([request]) } catch {
                if self.frameReceived <= 3 { print("🟢 GREEN SCREEN ❌ Vision failed — \(error)") }
                Task { @MainActor in self.frameDropped += 1 }; return
            }
            guard let result = request.results?.first else { return }
            let maskBuffer = result.pixelBuffer
            if self.frameProcessed == 0 { print("🟢 GREEN SCREEN ✅ First mask — \(CVPixelBufferGetWidth(maskBuffer))x\(CVPixelBufferGetHeight(maskBuffer))") }
            let maskImage  = CIImage(cvPixelBuffer: maskBuffer).resized(to: sourceImage.extent)
            let bg         = self.buildBackground(for: sourceImage.extent, source: sourceImage, bg: currentBG)
            let composited = self.composite(source: sourceImage, mask: maskImage, background: bg)
            Task { @MainActor in
                self.processedFrame = composited
                self.frameProcessed += 1
                if self.frameProcessed == 1 { print("🟢 GREEN SCREEN ✅ First frame composited — \(composited.extent)") }
                if self.frameProcessed % 60 == 0 { print("🟢 GREEN SCREEN: \(self.frameProcessed) frames processed") }
            }
        }
    }

    // Legacy entry point — delegates to processPixelBuffer
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        frameReceived += 1

        guard let request = segmentationRequest else {
            if frameReceived == 1 {
                print("🟢 GREEN SCREEN ❌ processFrame — segmentationRequest is nil (was activate() called?)")
            }
            frameDropped += 1
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if frameReceived == 1 {
                print("🟢 GREEN SCREEN ❌ processFrame — could not get image buffer from sampleBuffer")
            }
            frameDropped += 1
            return
        }

        // Log first frame only to avoid spam
        if frameReceived == 1 {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            print("🟢 GREEN SCREEN ✅ First frame received — size=\(w)x\(h)")
        }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let currentBG = background

        processingQueue.async { [weak self] in
            guard let self else { return }

            let handler = VNImageRequestHandler(ciImage: sourceImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                if self.frameReceived <= 3 {
                    print("🟢 GREEN SCREEN ❌ Vision perform failed — \(error)")
                }
                Task { @MainActor in self.frameDropped += 1 }
                return
            }

            guard let result = request.results?.first else {
                if self.frameReceived <= 3 {
                    print("🟢 GREEN SCREEN ❌ Vision returned no results")
                }
                return
            }

            let maskBuffer = result.pixelBuffer

            if self.frameProcessed == 0 {
                let mw = CVPixelBufferGetWidth(maskBuffer)
                let mh = CVPixelBufferGetHeight(maskBuffer)
                print("🟢 GREEN SCREEN ✅ First mask generated — size=\(mw)x\(mh)")
            }

            let maskImage  = CIImage(cvPixelBuffer: maskBuffer).resized(to: sourceImage.extent)
            let bg         = self.buildBackground(for: sourceImage.extent, source: sourceImage, bg: currentBG)
            let composited = self.composite(source: sourceImage, mask: maskImage, background: bg)

            Task { @MainActor in
                self.processedFrame = composited
                self.frameProcessed += 1
                if self.frameProcessed == 1 {
                    print("🟢 GREEN SCREEN ✅ First composited frame published — extent=\(composited.extent)")
                }
                if self.frameProcessed % 30 == 0 {
                    print("🟢 GREEN SCREEN: \(self.frameProcessed) frames processed (dropped=\(self.frameDropped))")
                }
            }
        }
    }

    // MARK: - Background

    private func buildBackground(for extent: CGRect, source: CIImage, bg: GreenScreenBackground) -> CIImage {
        if let cached = cachedBackgroundImage, bg == lastBackground {
            return cached.resized(to: extent)
        }
        print("🟢 GREEN SCREEN: Rebuilding background — type=\(bg)")
        let image: CIImage
        switch bg {
        case .blur(let radius):
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = source
            filter.radius = radius
            image = filter.outputImage ?? CIImage.black
        case .solidColor(let color):
            let uiColor = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            image = CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: extent)
        case .image(let uiImage):
            image = CIImage(image: uiImage)?.resized(to: extent) ?? CIImage.black
        }
        cachedBackgroundImage = image
        lastBackground = bg
        return image.resized(to: extent)
    }

    private func composite(source: CIImage, mask: CIImage, background: CIImage) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage      = source
        blend.backgroundImage = background
        blend.maskImage       = mask
        return blend.outputImage ?? source
    }
}

private extension CIImage {
    func resized(to extent: CGRect) -> CIImage {
        let sx = extent.width  / self.extent.width
        let sy = extent.height / self.extent.height
        return transformed(by: CGAffineTransform(scaleX: sx, y: sy)).cropped(to: extent)
    }
}

// MARK: - GreenScreenPreviewView

struct GreenScreenPreviewView: UIViewRepresentable {
    @ObservedObject var processor: GreenScreenProcessor

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("🟢 GREEN SCREEN ❌ GreenScreenPreviewView — Metal device unavailable (simulator?)")
            return MTKView()
        }
        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = true
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.backgroundColor = .black
        context.coordinator.ciContext = CIContext(mtlDevice: device)
        context.coordinator.mtkView = view
        view.delegate = context.coordinator
        print("🟢 GREEN SCREEN ✅ MTKView created — device=\(device.name)")
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if let frame = processor.processedFrame {
            if context.coordinator.frameCount == 0 {
                print("🟢 GREEN SCREEN ✅ GreenScreenPreviewView received first frame — extent=\(frame.extent)")
            }
            context.coordinator.currentFrame = frame
            context.coordinator.frameCount += 1
            uiView.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MTKViewDelegate {
        var ciContext: CIContext?
        var currentFrame: CIImage?
        var frameCount = 0
        weak var mtkView: MTKView?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            print("🟢 GREEN SCREEN: MTKView drawable size changed — \(size)")
        }

        func draw(in view: MTKView) {
            guard let frame = currentFrame,
                  let ctx = ciContext,
                  let drawable = view.currentDrawable,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer()
            else {
                if frameCount == 0 {
                    print("🟢 GREEN SCREEN ❌ draw() guard failed — frame=\(currentFrame != nil) ctx=\(ciContext != nil) drawable=\(view.currentDrawable != nil)")
                }
                return
            }

            let bounds = CGRect(origin: .zero, size: view.drawableSize)
            let scaleX = bounds.width  / frame.extent.width
            let scaleY = bounds.height / frame.extent.height
            let scale  = max(scaleX, scaleY)
            let scaled = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let ox = (bounds.width  - scaled.extent.width)  / 2
            let oy = (bounds.height - scaled.extent.height) / 2
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: ox, y: oy))

            ctx.render(positioned,
                       to: drawable.texture,
                       commandBuffer: commandBuffer,
                       bounds: bounds,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
