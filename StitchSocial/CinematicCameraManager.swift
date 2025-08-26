//
//  CinematicCameraManager.swift
//  StitchSocial
//
//  Created by James Garmon on 8/25/25.
//

//
//  CinematicCameraManager.swift
//  CleanBeta
//
//  Layer 4: Core Services - Professional Cinematic Camera System
//  iPhone Cinematic Mode Quality with Advanced Features
//  Dependencies: AVFoundation
//

import Foundation
import SwiftUI
@preconcurrency import AVFoundation

/// Professional cinematic camera manager with iPhone-level quality
/// Features: Cinematic stabilization, HDR, shallow depth of field, pro controls
@MainActor
class CinematicCameraManager: NSObject, ObservableObject {
    
    // MARK: - Singleton Instance
    
    static let shared = CinematicCameraManager()
    
    // MARK: - Published State
    
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var sessionState: CameraSessionState = .inactive
    
    // MARK: - Cinematic Controls
    
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var cinematicModeEnabled = true
    @Published var hdrEnabled = true
    @Published var stabilizationMode: AVCaptureVideoStabilizationMode = .cinematicExtended
    @Published var exposureMode: AVCaptureDevice.ExposureMode = .autoExpose
    @Published var focusMode: AVCaptureDevice.FocusMode = .autoFocus
    @Published var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .autoWhiteBalance
    
    // MARK: - Recording Quality
    
    @Published var recordingQuality: CinematicQuality = .professional
    @Published var recordingDuration: TimeInterval = 0
    @Published var isLowLightMode = false
    
    // MARK: - Core Components (Professional Setup)
    
    private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private let sessionQueue = DispatchQueue(label: "cinematic.camera.session", qos: .userInitiated)
    
    // MARK: - Recording State
    
    private var recordingCompletion: ((URL?) -> Void)?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    
    // MARK: - Advanced Camera Features
    
    private var currentDevice: AVCaptureDevice?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    // MARK: - Cinematic Quality Settings
    
    enum CinematicQuality: String, CaseIterable {
        case standard = "standard"      // 1080p@30fps
        case professional = "pro"       // 4K@30fps
        case cinematic = "cinematic"    // 4K@24fps
        case ultraHigh = "ultra"        // 4K@60fps
        
        var sessionPreset: AVCaptureSession.Preset {
            switch self {
            case .standard: return .hd1920x1080
            case .professional, .cinematic, .ultraHigh: return .hd4K3840x2160
            }
        }
        
        var frameRate: Int32 {
            switch self {
            case .standard, .professional: return 30
            case .cinematic: return 24
            case .ultraHigh: return 60
            }
        }
        
        var bitrate: Int {
            switch self {
            case .standard: return 8_000_000      // 8 Mbps
            case .professional: return 15_000_000 // 15 Mbps
            case .cinematic: return 12_000_000    // 12 Mbps
            case .ultraHigh: return 25_000_000    // 25 Mbps
            }
        }
    }
    
    // MARK: - Initialization (Singleton)
    
    private override init() {
        super.init()
        setupSessionNotifications()
        setupAudioSession()
        print("🎬 CINEMATIC CAMERA: Professional camera system initialized")
    }
    
    // MARK: - Session Management (Professional Grade)
    
    func startSession() async {
        guard sessionState != .active else {
            print("🎬 CINEMATIC CAMERA: Session already active")
            return
        }
        
        sessionState = .starting
        
        return await withCheckedContinuation { continuation in
            Task {
                // Force cleanup any existing sessions
                await self.forceStopSession()
                
                // Professional session configuration
                await self.configureCinematicSession()
                
                // Get session reference with proper isolation
                let session = await MainActor.run { self.captureSession }
                
                // Start with validation on session queue
                sessionQueue.async {
                    if !session.isRunning {
                        session.startRunning()
                        print("🎬 CINEMATIC CAMERA: Professional session started")
                    }
                    
                    Task { @MainActor in
                        self.isSessionRunning = session.isRunning
                        self.sessionState = session.isRunning ? .active : .error
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func stopSession() async {
        guard sessionState == .active else { return }
        
        sessionState = .stopping
        
        return await withCheckedContinuation { continuation in
            Task {
                // Get references with proper isolation
                let session = await MainActor.run { self.captureSession }
                let movieOutput = await MainActor.run { self.movieOutput }
                let isRecording = await MainActor.run { self.isRecording }
                
                sessionQueue.async {
                    // Stop any recording
                    if isRecording {
                        movieOutput?.stopRecording()
                    }
                    
                    // Stop session
                    if session.isRunning {
                        session.stopRunning()
                        print("🎬 CINEMATIC CAMERA: Session stopped")
                    }
                    
                    Task { @MainActor in
                        self.isSessionRunning = false
                        self.sessionState = .inactive
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // MARK: - Cinematic Session Configuration
    
    private func configureCinematicSession() async {
        return await withCheckedContinuation { continuation in
            Task {
                // Get session and quality with proper isolation
                let session = await MainActor.run { self.captureSession }
                let quality = await MainActor.run { self.recordingQuality }
                
                sessionQueue.async {
                    session.beginConfiguration()
                    
                    // Set professional session preset
                    if session.canSetSessionPreset(quality.sessionPreset) {
                        session.sessionPreset = quality.sessionPreset
                        print("🎬 CINEMATIC CAMERA: Set quality preset - \(quality.rawValue)")
                    }
                    
                    // Clear existing configuration
                    session.inputs.forEach { session.removeInput($0) }
                    session.outputs.forEach { session.removeOutput($0) }
                    
                    Task {
                        // Configure professional camera input
                        await self.configureProfessionalVideoInput(session: session)
                        
                        // Configure professional audio input
                        await self.configureProfessionalAudioInput(session: session)
                        
                        // Configure cinematic outputs
                        await self.configureCinematicOutputs(session: session)
                        
                        session.commitConfiguration()
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func configureProfessionalVideoInput(session: AVCaptureSession) async {
        let position = await MainActor.run { self.currentCameraPosition }
        let quality = await MainActor.run { self.recordingQuality }
        
        guard let camera = await getBestCamera(for: position) else {
            print("❌ CINEMATIC CAMERA: No suitable camera found")
            return
        }
        
        do {
            // Configure camera for cinematic recording
            try camera.lockForConfiguration()
            
            // Set optimal format for quality
            if let format = getBestFormat(for: camera, quality: quality) {
                camera.activeFormat = format
                print("🎬 CINEMATIC CAMERA: Set optimal format - \(format)")
            }
            
            // Set frame rate for quality
            let frameRate = quality.frameRate
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: frameRate)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: frameRate)
            
            // Enable advanced features if available
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
                print("🎬 CINEMATIC CAMERA: Low light boost enabled")
            }
            
            // Configure focus for cinematic feel
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            // Configure exposure for cinematic look
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            // Configure white balance
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            camera.unlockForConfiguration()
            
            // Create and add input
            let videoInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                
                await MainActor.run {
                    self.videoDeviceInput = videoInput
                    self.currentDevice = camera
                    self.updateAdvancedCapabilities(for: camera)
                }
                print("🎬 CINEMATIC CAMERA: Professional video input configured")
            }
            
        } catch {
            print("❌ CINEMATIC CAMERA: Video input configuration failed - \(error)")
        }
    }
    
    private func configureProfessionalAudioInput(session: AVCaptureSession) async {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("❌ CINEMATIC CAMERA: No audio device found")
            return
        }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                
                await MainActor.run {
                    self.audioDeviceInput = audioInput
                }
                print("🎬 CINEMATIC CAMERA: Professional audio input configured")
            }
        } catch {
            print("❌ CINEMATIC CAMERA: Audio input failed - \(error)")
        }
    }
    
    private func configureCinematicOutputs(session: AVCaptureSession) async {
        let quality = await MainActor.run { self.recordingQuality }
        
        // 1. Movie Output (Primary Recording)
        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            
            // Configure for maximum quality
            if let connection = movieOutput.connection(with: .video) {
                
                // CINEMATIC STABILIZATION (iPhone-level)
                if connection.isVideoStabilizationSupported {
                    if #available(iOS 17.0, *) {
                        connection.preferredVideoStabilizationMode = .cinematicExtended
                    } else {
                        connection.preferredVideoStabilizationMode = .cinematicExtendedEnhanced
                    }
                    print("🎬 CINEMATIC CAMERA: Cinematic stabilization enabled")
                }
                
                // Portrait orientation for social media - iOS 17+ compatibility
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                
                // Configure advanced video settings
                configureAdvancedVideoSettings(movieOutput, quality: quality)
            }
            
            await MainActor.run {
                self.movieOutput = movieOutput
            }
        }
        
        // 2. Photo Output (for thumbnails)
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            // Configure for high quality thumbnails - iOS 16+ compatibility
            if #available(iOS 16.0, *) {
                photoOutput.maxPhotoDimensions = CMVideoDimensions(width: 4032, height: 3024)
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
            
            await MainActor.run {
                self.photoOutput = photoOutput
            }
            print("🎬 CINEMATIC CAMERA: High-res photo output configured")
        }
        
        // 3. Depth Data Output (for Portrait/Cinematic effects)
        if #available(iOS 11.0, *) {
            let depthOutput = AVCaptureDepthDataOutput()
            if session.canAddOutput(depthOutput) {
                session.addOutput(depthOutput)
                
                depthOutput.isFilteringEnabled = true
                
                await MainActor.run {
                    self.depthDataOutput = depthOutput
                }
                print("🎬 CINEMATIC CAMERA: Depth data output enabled")
            }
        }
    }
    
    // MARK: - Advanced Camera Selection
    
    private func getBestCamera(for position: AVCaptureDevice.Position) async -> AVCaptureDevice? {
        return await Task.detached {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInTripleCamera,        // iPhone Pro models
                    .builtInDualWideCamera,      // iPhone 13/14/15 models
                    .builtInDualCamera,          // iPhone Plus models
                    .builtInWideAngleCamera,     // Standard cameras
                    .builtInTelephotoCamera,     // Telephoto cameras
                    .builtInUltraWideCamera      // Ultra-wide cameras
                ],
                mediaType: .video,
                position: position
            )
            
            // Prioritize best cameras first
            let cameras = discoverySession.devices.filter { $0.position == position }
            
            // Return best available camera (triple > dual > wide)
            return cameras.first { $0.deviceType == .builtInTripleCamera } ??
                   cameras.first { $0.deviceType == .builtInDualWideCamera } ??
                   cameras.first { $0.deviceType == .builtInDualCamera } ??
                   cameras.first { $0.deviceType == .builtInWideAngleCamera }
        }.value
    }
    
    private func getBestFormat(for device: AVCaptureDevice, quality: CinematicQuality) -> AVCaptureDevice.Format? {
        let formats = device.formats
        let targetResolution = quality.sessionPreset
        let targetFrameRate = Double(quality.frameRate)
        
        // Find best format matching our quality requirements
        return formats.first { format in
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let frameRateRanges = format.videoSupportedFrameRateRanges
            
            // Check resolution match
            let isResolutionMatch: Bool
            switch targetResolution {
            case .hd4K3840x2160:
                isResolutionMatch = dimensions.width >= 3840 && dimensions.height >= 2160
            case .hd1920x1080:
                isResolutionMatch = dimensions.width >= 1920 && dimensions.height >= 1080
            default:
                isResolutionMatch = true
            }
            
            // Check frame rate support
            let supportsFrameRate = frameRateRanges.contains { range in
                range.minFrameRate <= targetFrameRate && range.maxFrameRate >= targetFrameRate
            }
            
            return isResolutionMatch && supportsFrameRate
        }
    }
    
    // MARK: - Advanced Video Configuration
    
    private func configureAdvancedVideoSettings(_ movieOutput: AVCaptureMovieFileOutput, quality: CinematicQuality) {
        // Configure codec settings for maximum quality
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: quality == .standard ? 1080 : 3840,
            AVVideoHeightKey: quality == .standard ? 1920 : 2160,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoExpectedSourceFrameRateKey: quality.frameRate
            ]
        ]
        
        // Audio settings for professional quality
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,  // Professional audio sample rate
            AVNumberOfChannelsKey: 2, // Stereo
            AVEncoderBitRateKey: 128000 // 128 kbps
        ]
        
        movieOutput.movieFragmentInterval = .invalid // Full video file
        movieOutput.setOutputSettings(videoSettings, for: movieOutput.connection(with: .video)!)
        movieOutput.setOutputSettings(audioSettings, for: movieOutput.connection(with: .audio)!)
        
        print("🎬 CINEMATIC CAMERA: Advanced codec settings configured")
    }
    
    // MARK: - Professional Recording Controls
    
    func startRecording(completion: @escaping (URL?) -> Void) {
        guard sessionState == .active,
              let movieOutput = movieOutput,
              !isRecording else {
            print("❌ CINEMATIC CAMERA: Cannot start recording - Session not ready")
            completion(nil)
            return
        }
        
        guard captureSession.isRunning else {
            print("❌ CINEMATIC CAMERA: Session not running")
            completion(nil)
            return
        }
        
        // Generate filename with quality indicator
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "stitch_\(recordingQuality.rawValue)_\(timestamp).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // Clean up existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        recordingCompletion = completion
        recordingStartTime = Date()
        isRecording = true
        
        sessionQueue.async { [weak self] in
            movieOutput.startRecording(to: outputURL, recordingDelegate: self!)
            print("🎬 CINEMATIC CAMERA: Recording started - \(fileName)")
        }
        
        startRecordingTimer()
    }
    
    func stopRecording() {
        guard let movieOutput = movieOutput, isRecording else {
            print("❌ CINEMATIC CAMERA: Not recording")
            return
        }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        sessionQueue.async {
            movieOutput.stopRecording()
            print("🎬 CINEMATIC CAMERA: Recording stop requested")
        }
    }
    
    // MARK: - Professional Camera Controls
    
    func switchCamera() async {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        currentCameraPosition = newPosition
        await configureCinematicSession()
        print("🎬 CINEMATIC CAMERA: Switched to \(newPosition == .back ? "rear" : "front") camera")
    }
    
    func setZoom(_ factor: CGFloat) async {
        guard let device = currentDevice else { return }
        
        let validZoom = min(max(factor, 1.0), device.maxAvailableVideoZoomFactor)
        
        do {
            try device.lockForConfiguration()
            
            // Smooth zoom transition for cinematic feel
            device.ramp(toVideoZoomFactor: validZoom, withRate: 2.0)
            
            await MainActor.run {
                currentZoomFactor = validZoom
            }
            
            device.unlockForConfiguration()
            print("🎬 CINEMATIC CAMERA: Smooth zoom to \(validZoom)x")
        } catch {
            print("❌ CINEMATIC CAMERA: Zoom failed - \(error)")
        }
    }
    
    func setExposure(at point: CGPoint, in view: UIView) async {
        guard let device = currentDevice else { return }
        
        let exposurePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        do {
            try device.lockForConfiguration()
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = exposurePoint
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            print("🎬 CINEMATIC CAMERA: Exposure set to \(exposurePoint)")
        } catch {
            print("❌ CINEMATIC CAMERA: Exposure failed - \(error)")
        }
    }
    
    func setFocus(at point: CGPoint, in view: UIView) async {
        guard let device = currentDevice else { return }
        
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
                
                // Add cinematic focus transition
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
            }
            
            device.unlockForConfiguration()
            print("🎬 CINEMATIC CAMERA: Cinematic focus to \(focusPoint)")
        } catch {
            print("❌ CINEMATIC CAMERA: Focus failed - \(error)")
        }
    }
    
    // Convenience method for RecordingView compatibility
    func focusAt(point: CGPoint, in view: UIView) async {
        await setFocus(at: point, in: view)
    }
    
    // MARK: - Quality Management
    
    func setRecordingQuality(_ quality: CinematicQuality) async {
        guard quality != recordingQuality else { return }
        
        recordingQuality = quality
        
        // Reconfigure session for new quality
        if sessionState == .active {
            await configureCinematicSession()
        }
        
        print("🎬 CINEMATIC CAMERA: Quality changed to \(quality.rawValue)")
    }
    
    func enableHDR(_ enabled: Bool) async {
        hdrEnabled = enabled
        
        guard let device = currentDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Configure HDR if supported
            if device.activeFormat.isVideoHDRSupported {
                device.isVideoHDREnabled = enabled
                print("🎬 CINEMATIC CAMERA: HDR \(enabled ? "enabled" : "disabled")")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ CINEMATIC CAMERA: HDR configuration failed - \(error)")
        }
    }
    
    // MARK: - Audio Session (Professional)
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true)
            print("🎬 CINEMATIC CAMERA: Professional audio session configured")
        } catch {
            print("❌ CINEMATIC CAMERA: Audio session failed - \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateAdvancedCapabilities(for device: AVCaptureDevice) {
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 15.0) // Pro-level zoom
        currentZoomFactor = device.videoZoomFactor
        
        // Update low light detection
        isLowLightMode = device.isLowLightBoostEnabled
        
        print("🎬 CINEMATIC CAMERA: Max zoom: \(maxZoomFactor)x, Low light: \(isLowLightMode)")
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingDuration()
            }
        }
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
        
        // Auto-stop at 30 seconds (social media optimal)
        if recordingDuration >= 30.0 {
            stopRecording()
        }
    }
    
    /// Validate session readiness for recording
    func validateSessionForRecording() -> Bool {
        guard sessionState == .active,
              captureSession.isRunning,
              movieOutput != nil,
              !isRecording else {
            return false
        }
        return true
    }
    
    // MARK: - Session Cleanup
    
    private func forceStopSession() async {
        return await withCheckedContinuation { continuation in
            Task {
                // Get references with proper isolation
                let session = await MainActor.run { self.captureSession }
                let movieOutput = await MainActor.run { self.movieOutput }
                
                sessionQueue.async {
                    // Stop recording if active
                    if let output = movieOutput, output.isRecording {
                        output.stopRecording()
                    }
                    
                    // Stop session
                    if session.isRunning {
                        session.stopRunning()
                    }
                    
                    // Clear configuration
                    session.beginConfiguration()
                    session.inputs.forEach { session.removeInput($0) }
                    session.outputs.forEach { session.removeOutput($0) }
                    session.commitConfiguration()
                    
                    Task { @MainActor in
                        self.videoDeviceInput = nil
                        self.audioDeviceInput = nil
                        self.movieOutput = nil
                        self.photoOutput = nil
                        self.depthDataOutput = nil
                        self.currentDevice = nil
                        self.recordingCompletion = nil
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // MARK: - Session Notifications
    
    private func setupSessionNotifications() {
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSessionRunning = true
                self?.sessionState = .active
                print("🎬 CINEMATIC CAMERA: Session active")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStopRunning,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSessionRunning = false
                self?.sessionState = .inactive
                print("🎬 CINEMATIC CAMERA: Session stopped")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: captureSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.sessionState = .error
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
                    await self?.handleSessionError(error)
                }
            }
        }
        
        // App lifecycle handling
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.stopSession() }
        }
    }
    
    private func handleSessionError(_ error: AVError) async {
        print("❌ CINEMATIC CAMERA: Session error - \(error.localizedDescription)")
        
        switch error.code {
        case .deviceAlreadyUsedByAnotherSession:
            await forceStopSession()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await startSession()
            
        case .mediaServicesWereReset:
            await stopSession()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await startSession()
            
        default:
            sessionState = .error
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        recordingTimer?.invalidate()
    }
}

// MARK: - Recording Delegate (Professional)

extension CinematicCameraManager: AVCaptureFileOutputRecordingDelegate {
    
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("✅ CINEMATIC CAMERA: Recording started - Professional quality")
        
        Task { @MainActor in
            if !self.isRecording {
                self.isRecording = true
            }
        }
    }
    
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingStartTime = nil
            self.isRecording = false
            
            if let error = error {
                print("❌ CINEMATIC CAMERA: Recording failed - \(error)")
                self.recordingCompletion?(nil)
            } else {
                print("✅ CINEMATIC CAMERA: Professional recording completed")
                
                // Validate output file
                if FileManager.default.fileExists(atPath: outputFileURL.path) {
                    // Log file stats
                    self.logVideoStats(outputFileURL)
                    self.recordingCompletion?(outputFileURL)
                } else {
                    print("❌ CINEMATIC CAMERA: Output file missing")
                    self.recordingCompletion?(nil)
                }
            }
            
            self.recordingCompletion = nil
        }
    }
    
    private func logVideoStats(_ url: URL) {
        Task.detached {
            do {
                let asset = AVAsset(url: url)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                
                if let track = tracks.first {
                    let naturalSize = try await track.load(.naturalSize)
                    let estimatedDataRate = try await track.load(.estimatedDataRate)
                    
                    let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                    
                    print("🎬 CINEMATIC CAMERA: Video Stats")
                    print("   Duration: \(String(format: "%.1fs", CMTimeGetSeconds(duration)))")
                    print("   Resolution: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
                    print("   Bitrate: \(String(format: "%.1f Mbps", Double(estimatedDataRate) / 1_000_000))")
                    print("   File Size: \(String(format: "%.1f MB", Double(fileSize) / 1_048_576))")
                }
            } catch {
                print("❌ CINEMATIC CAMERA: Could not analyze video stats")
            }
        }
    }
}

// MARK: - Camera Session State

enum CameraSessionState: String, CaseIterable {
    case inactive = "inactive"
    case starting = "starting"
    case active = "active"
    case stopping = "stopping"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .inactive: return "Inactive"
        case .starting: return "Starting"
        case .active: return "Ready"
        case .stopping: return "Stopping"
        case .error: return "Error"
        }
    }
    
    var canStartRecording: Bool {
        return self == .active
    }
}
