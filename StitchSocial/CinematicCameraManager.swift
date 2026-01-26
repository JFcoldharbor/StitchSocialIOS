//
//  CinematicCameraManager.swift
//  StitchSocial
//
//  Simple camera manager - just recording, preview, and zoom
//

import Foundation
import SwiftUI
import AVFoundation

@MainActor
class CinematicCameraManager: NSObject, ObservableObject {
    
    static let shared = CinematicCameraManager()
    
    // MARK: - Published State
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    
    // MARK: - Core Components
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    
    // MARK: - Recording
    private var recordingCompletion: ((URL?) -> Void)?
    
    // MARK: - Preview Layer
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
            guard let self = self else { return }
            
            Task { @MainActor in
                self.setupSession()
                
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                
                self.isSessionRunning = self.captureSession.isRunning
                print("📱 CAMERA: Session \(self.isSessionRunning ? "started" : "failed")")
            }
        }
    }
    
    func stopSession() async {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            
            Task { @MainActor in
                self.isSessionRunning = false
                print("📱 CAMERA: Session stopped")
            }
        }
    }
    
    // MARK: - Simple Session Setup
    
    private func setupSession() {
        captureSession.beginConfiguration()
        
        // Set quality
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }
        
        // Clear existing inputs/outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        
        // Add video input
        setupVideoInput()
        
        // Add audio input
        setupAudioInput()
        
        // Add movie output
        setupMovieOutput()
        
        captureSession.commitConfiguration()
        
        // CRITICAL: Set orientation AFTER commit
        setPortraitOrientation()
    }
    
    private func setPortraitOrientation() {
        guard let movieOutput = movieOutput else { return }
        
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                print("📱 CAMERA: Video orientation set to portrait (1080x1920)")
            } else {
                print("⚠️ CAMERA: Video orientation not supported")
            }
        } else {
            print("⚠️ CAMERA: No video connection found")
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
                self.videoInput = input
                self.currentDevice = camera
                self.maxZoomFactor = min(camera.maxAvailableVideoZoomFactor, 10.0)
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
                self.audioInput = input
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
            self.movieOutput = output
            print("📱 CAMERA: Movie output added")
        }
    }
    
    // MARK: - Recording
    
    func startRecording(completion: @escaping (URL?) -> Void) {
        guard let movieOutput = movieOutput, !isRecording else {
            completion(nil)
            return
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "video_\(timestamp).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // Clean up existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Verify and enforce portrait orientation before recording
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                print("📱 CAMERA: Recording with orientation: \(connection.videoOrientation.rawValue) (1=portrait)")
            }
        }
        
        recordingCompletion = completion
        isRecording = true
        
        sessionQueue.async {
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            print("📱 CAMERA: Recording started")
        }
    }
    
    func stopRecording() {
        guard let movieOutput = movieOutput, isRecording else { return }
        
        isRecording = false
        
        sessionQueue.async {
            movieOutput.stopRecording()
            print("📱 CAMERA: Recording stopped")
        }
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() async {
        // Simple front/back switch - get current position
        let currentPosition = currentDevice?.position ?? .back
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            print("❌ CAMERA: No camera for position \(newPosition)")
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // Remove old input
            if let oldInput = self.videoInput {
                self.captureSession.removeInput(oldInput)
            }
            
            // Add new input
            do {
                let newInput = try AVCaptureDeviceInput(device: newCamera)
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    
                    Task { @MainActor in
                        self.videoInput = newInput
                        self.currentDevice = newCamera
                        self.maxZoomFactor = min(newCamera.maxAvailableVideoZoomFactor, 10.0)
                        self.currentZoomFactor = 1.0
                    }
                }
            } catch {
                print("❌ CAMERA: Camera switch failed - \(error)")
            }
            
            self.captureSession.commitConfiguration()
            
            // Re-apply portrait orientation after camera switch
            Task { @MainActor in
                self.setPortraitOrientation()
            }
            
            print("📱 CAMERA: Switched to \(newPosition == .back ? "back" : "front")")
        }
    }
    
    func setZoom(_ factor: CGFloat) async {
        guard let device = currentDevice else { return }
        
        let clampedZoom = min(max(factor, 1.0), maxZoomFactor)
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            
            self.currentZoomFactor = clampedZoom
            print("📱 CAMERA: Zoom set to \(clampedZoom)x")
        } catch {
            print("❌ CAMERA: Zoom failed - \(error)")
        }
    }
    
    // MARK: - Single Hand Drag Zoom
    
    func handleZoomDrag(translation: CGSize, in view: UIView) async {
        let sensitivity: CGFloat = 0.01
        let dragDistance = -translation.height // Drag up to zoom in, down to zoom out
        let zoomDelta = dragDistance * sensitivity
        let newZoom = currentZoomFactor + zoomDelta
        
        await setZoom(newZoom)
    }
    
    func startZoomGesture() {
        // Store initial zoom when gesture begins
        print("📱 CAMERA: Zoom gesture started at \(currentZoomFactor)x")
    }
    
    func endZoomGesture() {
        print("📱 CAMERA: Zoom gesture ended at \(currentZoomFactor)x")
    }
    
    func focusAt(point: CGPoint, in view: UIView) async {
        guard let device = currentDevice else { return }
        
        // Convert view coordinates to device coordinates
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
            
            device.unlockForConfiguration()
            print("📱 CAMERA: Focus set")
        } catch {
            print("❌ CAMERA: Focus failed - \(error)")
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
            
            if let error = error {
                print("❌ CAMERA: Recording failed - \(error)")
                self.recordingCompletion?(nil)
            } else {
                // Check actual video dimensions
                let asset = AVAsset(url: outputFileURL)
                if let track = asset.tracks(withMediaType: .video).first {
                    let size = track.naturalSize
                    let transform = track.preferredTransform
                    print("✅ CAMERA: Recording completed")
                    print("📐 CAMERA: Video size: \(size.width)x\(size.height)")
                    print("📐 CAMERA: Transform: \(transform)")
                    
                    // Check if it's actually portrait
                    let isPortrait = size.height > size.width
                    print("📐 CAMERA: Is portrait: \(isPortrait) (expected: true)")
                }
                
                self.recordingCompletion?(outputFileURL)
            }
            
            self.recordingCompletion = nil
        }
    }
}
