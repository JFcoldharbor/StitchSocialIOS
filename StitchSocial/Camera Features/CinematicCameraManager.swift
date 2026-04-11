//
//  CinematicCameraManager.swift
//  StitchSocial
//
//  Camera manager - recording, preview, zoom, multi-lens, torch
//
//  CACHING: availableLenses discovered once at session start and cached
//  in-memory. No re-discovery on lens switch — avoids repeated
//  DiscoverySession allocations. Cleared on stopSession().

import Foundation
import SwiftUI
import AVFoundation

// MARK: - Lens Type

enum CameraLens: String, CaseIterable {
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

@MainActor
class CinematicCameraManager: NSObject, ObservableObject {

    static let shared = CinematicCameraManager()

    // MARK: - Published State
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var isTorchOn = false

    // MARK: - Multi-Lens State
    // CACHING: discovered once, reused for session lifetime
    @Published var availableLenses: [CameraLens] = []
    @Published var activeLens: CameraLens = .wide

    // MARK: - Core Components
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?   // green screen frames
    private var currentDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    // Dedicated serial queue for frame delivery — keeps sessionQueue free
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)

    // MARK: - Recording
    private var recordingCompletion: ((URL?) -> Void)?

    // MARK: - Preview Layer
    // NOTE: Returns same session — no new allocation on repeated access
    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    override init() {
        super.init()
        print("📱 CAMERA: Initialized")
    }

    // MARK: - Session Management

    func startSession() async {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // All AVFoundation work stays on sessionQueue — never touch main thread
            self.setupSession()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            let isRunning = self.captureSession.isRunning
            // Only @Published state update needs MainActor
            Task { @MainActor in
                self.isSessionRunning = isRunning
                self.discoverAvailableLenses()
                print("📱 CAMERA: Session \(isRunning ? "started" : "failed")")
            }
        }
    }

    func stopSession() async {
        // Cleanup: turn off torch before stopping
        if isTorchOn { setTorch(false) }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            Task { @MainActor in
                self.isSessionRunning = false
                self.availableLenses = [] // clear cache on session end
                print("📱 CAMERA: Session stopped")
            }
        }
    }

    // MARK: - Lens Discovery (cached)

    private func discoverAvailableLenses() {
        let position: AVCaptureDevice.Position = currentDevice?.position ?? .back
        var found: [CameraLens] = []

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: position
        )

        let deviceTypes = session.devices.map { $0.deviceType }

        if deviceTypes.contains(.builtInUltraWideCamera) { found.append(.ultraWide) }
        found.append(.wide) // always available
        if deviceTypes.contains(.builtInTelephotoCamera) {
            found.append(.tele2x)
            // 3x only on Pro models (zoom factor >= 3)
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
        guard let newCamera = AVCaptureDevice.default(lens.deviceType, for: .video, position: position) else {
            print("❌ CAMERA: Lens \(lens.rawValue) not available")
            return
        }

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
                print("❌ CAMERA: Lens switch failed - \(error)")
            }
            self.captureSession.commitConfiguration()
            Task { @MainActor in self.setPortraitOrientation() }
            print("📱 CAMERA: Switched to \(lens.rawValue) lens")
        }
    }

    // MARK: - Torch

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    func setTorch(_ on: Bool) {
        guard let device = currentDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
            print("📱 CAMERA: Torch \(on ? "ON" : "OFF")")
        } catch {
            print("❌ CAMERA: Torch failed - \(error)")
        }
    }

    // MARK: - Session Setup

    private func setupSession() {
        captureSession.beginConfiguration()
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }
        setupVideoInput()
        setupAudioInput()
        setupMovieOutput()
        setupVideoDataOutput()   // green screen frame tap
        captureSession.commitConfiguration()
        setPortraitOrientation()
    }

    private func setPortraitOrientation() {
        guard let movieOutput else { return }
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
            print("📱 CAMERA: Orientation set to portrait")
        }
    }

    private func setupVideoInput() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ CAMERA: No camera found")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
                currentDevice = camera
                let maxZoom = min(camera.maxAvailableVideoZoomFactor, 10.0)
                // @Published update deferred to MainActor — called after startRunning
                Task { @MainActor in
                    self.maxZoomFactor = maxZoom
                    self.activeLens = .wide
                }
                print("📱 CAMERA: Video input added")
            }
        } catch {
            print("❌ CAMERA: Video input failed - \(error)")
        }
    }

    private func setupAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("❌ CAMERA: No audio device")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                audioInput = input
                print("📱 CAMERA: Audio input added")
            }
        } catch {
            print("❌ CAMERA: Audio input failed - \(error)")
        }
    }

    private func setupMovieOutput() {
        let output = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            movieOutput = output
            print("📱 CAMERA: Movie output added")
        }
    }

    private func setupVideoDataOutput() {
        let output = AVCaptureVideoDataOutput()
        // kCVPixelFormatType_32BGRA — required by CIImage + Vision
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Drop frames if processor is busy — never block the session queue
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoDataOutput = output
            // Mirror orientation so Vision mask aligns with preview
            if let connection = output.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            print("📱 CAMERA: Video data output added")
        }
    }

    // MARK: - Recording

    func startRecording(completion: @escaping (URL?) -> Void) {
        guard let movieOutput else {
            print("❌ CAMERA: No movie output")
            completion(nil)
            return
        }

        print("🔍 START CHECK: movieOutput.isRecording=\(movieOutput.isRecording) isRecording=\(isRecording) session.isRunning=\(captureSession.isRunning)")

        guard !movieOutput.isRecording else {
            print("⚠️ CAMERA: Already recording — skipping")
            completion(nil)
            return
        }
        guard captureSession.isRunning else {
            print("⚠️ CAMERA: Session not running")
            completion(nil)
            return
        }
        guard !isRecording else {
            print("⚠️ CAMERA: isRecording flag true — skipping")
            completion(nil)
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: outputURL)

        if let connection = movieOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        recordingCompletion = completion
        sessionQueue.async { movieOutput.startRecording(to: outputURL, recordingDelegate: self) }
        print("📱 CAMERA: startRecording dispatched")
    }

    func stopRecording() {
        guard let movieOutput, movieOutput.isRecording else {
            print("⚠️ CAMERA: stopRecording called but not recording")
            return
        }
        sessionQueue.async { movieOutput.stopRecording() }
        print("📱 CAMERA: stopRecording dispatched")
    }

    // MARK: - Camera Controls

    func switchCamera() async {
        let currentPosition = currentDevice?.position ?? .back
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            print("❌ CAMERA: No camera for position \(newPosition)")
            return
        }

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
                        self.activeLens = .wide
                        // Re-discover lenses for new position
                        self.discoverAvailableLenses()
                        // Turn off torch on camera flip (front has no torch)
                        if newPosition == .front { self.isTorchOn = false }
                    }
                }
            } catch {
                print("❌ CAMERA: Camera switch failed - \(error)")
            }
            self.captureSession.commitConfiguration()
            Task { @MainActor in self.setPortraitOrientation() }
            print("📱 CAMERA: Switched to \(newPosition == .back ? "back" : "front")")
        }
    }

    func setZoom(_ factor: CGFloat) async {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, 1.0), maxZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            currentZoomFactor = clamped
        } catch {
            print("❌ CAMERA: Zoom failed - \(error)")
        }
    }

    func handleZoomDrag(translation: CGSize, in view: UIView) async {
        let delta = (-translation.height * 0.01)
        await setZoom(currentZoomFactor + delta)
    }

    func startZoomGesture() { print("📱 CAMERA: Zoom gesture started at \(currentZoomFactor)x") }
    func endZoomGesture()   { print("📱 CAMERA: Zoom gesture ended at \(currentZoomFactor)x") }

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
            print("📱 CAMERA: Focus + exposure set")
        } catch {
            print("❌ CAMERA: Focus failed - \(error)")
        }
    }
}

// MARK: - Video Data Delegate (Green Screen frames)

extension CinematicCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard GreenScreenProcessor.shared.isActiveAtomic else { return }
        // Extract pixel buffer on frameQueue — CVPixelBuffer is Sendable,
        // CMSampleBuffer is not. ARC retains pixelBuffer automatically.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in
            GreenScreenProcessor.shared.processPixelBuffer(pixelBuffer)
        }
    }
}


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
                print("❌ CAMERA: Recording failed - \(error)")
                self.recordingCompletion?(nil)
            } else {
                let asset = AVAsset(url: outputFileURL)
                if let track = asset.tracks(withMediaType: .video).first {
                    let size = track.naturalSize
                    print("✅ CAMERA: Done — \(size.width)x\(size.height)")
                }
                self.recordingCompletion?(outputFileURL)
            }
            self.recordingCompletion = nil
        }
    }
}
