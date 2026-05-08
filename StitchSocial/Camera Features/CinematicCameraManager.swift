//
//  CinematicCameraManager.swift
//  StitchSocial
//
//  Layer 1: Camera Session Manager
//
//  ARCHITECTURE:
//  - All AVFoundation work runs on dedicated sessionQueue (never main thread)
//  - @Published state updates dispatch to MainActor
//  - Session configured once via isConfigured flag (prevents FigXPC -17281)
//  - start/stop are truly awaitable via CheckedContinuation
//  - Lens discovery cached for session lifetime
//  - Preview layer is lazy singleton shared across UIViewRepresentable instances
//
//  CACHING: isConfigured flag, availableLenses array
//  CLEANUP: isConfigured + lenses reset on stop, torch off
//  THREADING: sessionQueue for AVFoundation, frameQueue for green screen
//

import Foundation
import SwiftUI
@preconcurrency import AVFoundation

// MARK: - Lens Type

enum CameraLens: String, CaseIterable, Sendable {
    case ultraWide = "0.5x"
    case wide      = "1x"
    case tele2x    = "2x"
    case tele3x    = "3x"

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide:      return .builtInWideAngleCamera
        case .tele2x:    return .builtInTelephotoCamera
        case .tele3x:    return .builtInTelephotoCamera
        }
    }

    var displayLabel: String { rawValue }
}

// MARK: - Camera Manager

@MainActor
class CinematicCameraManager: NSObject, ObservableObject {

    static let shared = CinematicCameraManager()

    // MARK: - Published State
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var isTorchOn = false

    // MARK: - Multi-Lens State (cached for session lifetime)
    @Published var availableLenses: [CameraLens] = []
    @Published var activeLens: CameraLens = .wide

    // MARK: - Core Components
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?

    // MARK: - Queues (off main thread)
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)

    // MARK: - Session Cache Flag
    private var isConfigured = false

    // MARK: - Recording
    private var recordingCompletion: ((URL?) -> Void)?

    // MARK: - Preview Layer (lazy singleton)
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    override init() {
        super.init()
    }

    // MARK: - Session Start (awaitable)

    func startSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }

                self.configureSessionIfNeeded()

                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                let running = self.captureSession.isRunning
                Task { @MainActor in
                    self.isSessionRunning = running
                    self.discoverLenses()
                    print("📱 CAMERA: Session \(running ? "started" : "failed")")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Session Stop (awaitable)

    func stopSession() async {
        if isTorchOn { setTorch(false) }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }

                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                self.isConfigured = false

                Task { @MainActor in
                    self.isSessionRunning = false
                    self.availableLenses = []
                    print("📱 CAMERA: Session stopped")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Session Configuration (cached — runs once)

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        captureSession.beginConfiguration()

        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        // Clear stale inputs/outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        addVideoInput()
        addAudioInput()
        addMovieOutput()
        addVideoDataOutput()

        captureSession.commitConfiguration()
        applyPortraitRotation()

        isConfigured = true
    }

    // MARK: - Input/Output Setup

    private func addVideoInput() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ CAMERA: No camera found"); return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                Task { @MainActor in
                    self.videoInput = input
                    self.currentDevice = camera
                    self.maxZoomFactor = min(camera.maxAvailableVideoZoomFactor, 10.0)
                    self.activeLens = .wide
                }
                print("📱 CAMERA: Video input added")
            }
        } catch {
            print("❌ CAMERA: Video input failed — \(error)")
        }
    }

    private func addAudioInput() {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            print("❌ CAMERA: No audio device"); return
        }
        do {
            let input = try AVCaptureDeviceInput(device: mic)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                Task { @MainActor in self.audioInput = input }
                print("📱 CAMERA: Audio input added")
            }
        } catch {
            print("❌ CAMERA: Audio input failed — \(error)")
        }
    }

    private func addMovieOutput() {
        let output = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            Task { @MainActor in self.movieOutput = output }
            print("📱 CAMERA: Movie output added")
        }
    }

    private func addVideoDataOutput() {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            if let conn = output.connection(with: .video) {
                applyRotation(to: conn)
            }
            Task { @MainActor in self.videoDataOutput = output }
            print("📱 CAMERA: Video data output added")
        }
    }

    // MARK: - Orientation (iOS 17+ rotation angle)

    private func applyPortraitRotation() {
        guard let movieOutput else { return }
        if let conn = movieOutput.connection(with: .video) {
            applyRotation(to: conn)
        }
        print("📱 CAMERA: Orientation set to portrait")
    }

    private func applyRotation(to connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    // MARK: - Lens Discovery (cached)

    private func discoverLenses() {
        let position: AVCaptureDevice.Position = currentDevice?.position ?? .back
        var found: [CameraLens] = []

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: position
        )

        let types = session.devices.map { $0.deviceType }

        if types.contains(.builtInUltraWideCamera) { found.append(.ultraWide) }
        found.append(.wide)
        if types.contains(.builtInTelephotoCamera) {
            found.append(.tele2x)
            if let tele = session.devices.first(where: { $0.deviceType == .builtInTelephotoCamera }),
               tele.maxAvailableVideoZoomFactor >= 3 {
                found.append(.tele3x)
            }
        }

        availableLenses = found
        print("📱 CAMERA: Available lenses: \(found.map { $0.rawValue })")
    }

    // MARK: - Switch Lens

    func switchToLens(_ lens: CameraLens) async {
        guard availableLenses.contains(lens), lens != activeLens else { return }
        let position: AVCaptureDevice.Position = currentDevice?.position ?? .back
        guard let newCamera = AVCaptureDevice.default(lens.deviceType, for: .video, position: position) else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if let old = self.videoInput { self.captureSession.removeInput(old) }
            do {
                let input = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    Task { @MainActor in
                        self.videoInput = input
                        self.currentDevice = newCamera
                        self.maxZoomFactor = min(newCamera.maxAvailableVideoZoomFactor, 10.0)
                        self.currentZoomFactor = 1.0
                        self.activeLens = lens
                    }
                }
            } catch {
                print("❌ CAMERA: Lens switch failed — \(error)")
            }
            self.captureSession.commitConfiguration()
            self.applyPortraitRotation()
        }
    }

    // MARK: - Recording

    func startRecording(completion: @escaping (URL?) -> Void) {
        guard let movieOutput, !movieOutput.isRecording, captureSession.isRunning, !isRecording else {
            completion(nil); return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: outputURL)

        if let conn = movieOutput.connection(with: .video) {
            applyRotation(to: conn)
        }

        recordingCompletion = completion
        sessionQueue.async { movieOutput.startRecording(to: outputURL, recordingDelegate: self) }
    }

    func stopRecording() {
        guard let movieOutput, movieOutput.isRecording else { return }
        sessionQueue.async { movieOutput.stopRecording() }
    }

    // MARK: - Camera Switch

    func switchCamera() async {
        let current = currentDevice?.position ?? .back
        let next: AVCaptureDevice.Position = current == .back ? .front : .back
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next) else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if let old = self.videoInput { self.captureSession.removeInput(old) }

            var newInput: AVCaptureDeviceInput?
            do {
                let input = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    newInput = input
                }
            } catch {
                print("❌ CAMERA: Switch failed — \(error)")
            }
            self.captureSession.commitConfiguration()

            // Re-apply rotation on all connections
            if let conn = self.movieOutput?.connection(with: .video) { self.applyRotation(to: conn) }
            if let conn = self.videoDataOutput?.connection(with: .video) { self.applyRotation(to: conn) }

            guard let input = newInput else { return }
            Task { @MainActor in
                self.videoInput = input
                self.currentDevice = newCamera
                self.maxZoomFactor = min(newCamera.maxAvailableVideoZoomFactor, 10.0)
                self.currentZoomFactor = 1.0
                self.activeLens = .wide
                self.availableLenses = next == .front ? [.wide] : self.availableLenses
                if next == .front { self.isTorchOn = false }
            }
        }
    }

    // MARK: - Torch

    func toggleTorch() { setTorch(!isTorchOn) }

    func setTorch(_ on: Bool) {
        guard let device = currentDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
        } catch {
            print("❌ CAMERA: Torch failed — \(error)")
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) async {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, 1.0), maxZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            currentZoomFactor = clamped
        } catch {
            print("❌ CAMERA: Zoom failed — \(error)")
        }
    }

    // MARK: - Focus & Exposure

    func focusAt(point: CGPoint, in view: UIView) async {
        guard let device = currentDevice else { return }
        let devicePoint = CGPoint(
            x: point.y / view.bounds.height,
            y: 1.0 - (point.x / view.bounds.width)
        )
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ CAMERA: Focus failed — \(error)")
        }
    }
}

// MARK: - Video Data Delegate (Green Screen)

extension CinematicCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard GreenScreenProcessor.shared.isActiveAtomic else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in
            GreenScreenProcessor.shared.processPixelBuffer(pixelBuffer)
        }
    }
}

// MARK: - Recording Delegate

extension CinematicCameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.isRecording = true
            print("✅ CAMERA: Recording started")
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            if let error {
                print("❌ CAMERA: Recording failed — \(error)")
                self.recordingCompletion?(nil)
            } else {
                // Log dimensions using modern async API
                let asset = AVURLAsset(url: outputFileURL)
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try? await track.load(.naturalSize)
                    if let size { print("✅ CAMERA: Done — \(size.width)x\(size.height)") }
                }
                self.recordingCompletion?(outputFileURL)
            }
            self.recordingCompletion = nil
        }
    }
}
