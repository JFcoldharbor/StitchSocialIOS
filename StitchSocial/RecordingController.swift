//
//  RecordingController.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Recording Flow Controller
//  Complete fix with VideoCoordinator integration and background thread handling
//

import Foundation
import SwiftUI
@preconcurrency import AVFoundation
import FirebaseStorage

// MARK: - Streamlined Camera Manager (Fixed)

@MainActor
class StreamlinedCameraManager: NSObject, ObservableObject, @unchecked Sendable {
    
    // MARK: - Essential State Only
    
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Core Components
    
    private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    
    // Recording completion
    private var recordingCompletion: ((URL?) -> Void)?
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: captureSession)
    }
    
    // MARK: - Session Management (FIXED - Background Thread)

    @MainActor
    func startSession() async {
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Task {
                    await self.configureSessionOnBackground()
                    
                    // FIXED: Move session.startRunning() to background thread
                    self.sessionQueue.async {
                        let session = self.captureSession
                        if !session.isRunning {
                            session.startRunning()
                        }
                        
                        Task { @MainActor in
                            self.isSessionRunning = session.isRunning
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func stopSession() async {
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // FIXED: Move session.stopRunning() to background thread
                let session = self.captureSession
                if session.isRunning {
                    session.stopRunning()
                }
                
                Task { @MainActor in
                    self.isSessionRunning = false
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Recording Controls
    
    @MainActor
    func startRecording(completion: @escaping (URL?) -> Void) {
        guard let movieOutput = movieOutput else {
            print("❌ CAMERA: Movie output not available")
            completion(nil)
            return
        }
        
        // Generate unique filename
        let fileName = "recorded_video_\(Date().timeIntervalSince1970).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        recordingCompletion = completion
        isRecording = true
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    @MainActor
    func stopRecording() {
        guard let movieOutput = movieOutput, movieOutput.isRecording else {
            print("❌ CAMERA: Not currently recording")
            return
        }
        
        isRecording = false
        movieOutput.stopRecording()
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() async {
        await configureSessionOnBackground()
    }
    
    func setZoom(_ factor: CGFloat) async {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(factor, 1.0), device.maxAvailableVideoZoomFactor)
            await MainActor.run {
                currentZoomFactor = device.videoZoomFactor
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ CAMERA: Zoom failed - \(error)")
        }
    }
    
    func focusAt(point: CGPoint, in view: UIView) async {
        guard let device = videoDeviceInput?.device else { return }
        
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ CAMERA: Focus failed - \(error)")
        }
    }
    
    // MARK: - Private Configuration
    
    private func configureSessionOnBackground() async {
        captureSession.beginConfiguration()
        
        // Set session preset
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // Remove existing inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        // Add video input
        if let backCamera = await getCamera(for: .back),
           let videoInput = try? AVCaptureDeviceInput(device: backCamera) {
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                
                await MainActor.run { [weak self] in
                    self?.videoDeviceInput = videoInput
                    self?.updateZoomCapabilities(for: backCamera)
                }
            }
        }
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
                
                await MainActor.run { [weak self] in
                    self?.audioDeviceInput = audioInput
                }
            }
        }
        
        // Add movie output
        let movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            
            await MainActor.run { [weak self] in
                self?.movieOutput = movieOutput
            }
            
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    private func getCamera(for position: AVCaptureDevice.Position) async -> AVCaptureDevice? {
        return await Task.detached {
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                mediaType: .video,
                position: position
            ).devices.first { $0.position == position }
        }.value
    }
    
    private func updateZoomCapabilities(for device: AVCaptureDevice) {
        maxZoomFactor = device.maxAvailableVideoZoomFactor
        currentZoomFactor = device.videoZoomFactor
    }
}

// MARK: - Recording Delegate

extension StreamlinedCameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("✅ CAMERA: Started recording")
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ CAMERA: Recording failed - \(error)")
                self.recordingCompletion?(nil)
            } else {
                print("✅ CAMERA: Recording completed - \(outputFileURL)")
                self.recordingCompletion?(outputFileURL)
            }
            self.recordingCompletion = nil
        }
    }
}

// MARK: - Recording Controller (FIXED with VideoCoordinator Integration)

@MainActor
class RecordingController: ObservableObject {
    
    // MARK: - Published State
    
    @Published var recordingPhase: RecordingPhase = .ready
    @Published var currentPhase: RecordingPhase = .ready
    @Published var videoMetadata = VideoMetadata()
    @Published var errorMessage: String?
    @Published var uploadProgress: Double = 0.0
    @Published var aiAnalysisResult: VideoAnalysisResult?
    @Published var recordedVideoURL: URL?
    
    // MARK: - Dependencies (FIXED - Added VideoCoordinator)
    
    private let videoService: VideoService
    private let authService: AuthService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoCoordinator: VideoCoordinator // NEW: Post-processing coordinator
    let cameraManager: StreamlinedCameraManager
    
    // MARK: - Configuration
    
    let recordingContext: RecordingContext
    
    // MARK: - Initialization (FIXED - Initialize VideoCoordinator)
    
    init(recordingContext: RecordingContext) {
        self.recordingContext = recordingContext
        self.videoService = VideoService()
        self.authService = AuthService()
        self.aiAnalyzer = AIVideoAnalyzer()
        self.cameraManager = StreamlinedCameraManager()
        
        // NEW: Initialize VideoCoordinator with all dependencies
        self.videoCoordinator = VideoCoordinator(
            videoService: videoService,
            aiAnalyzer: aiAnalyzer,
            videoProcessor: VideoProcessingService(),
            uploadService: VideoUploadService(),
            cachingService: nil // Optional caching service
        )
        
        print("🎬 RECORDING CONTROLLER: Initialized with VideoCoordinator integration")
    }
    
    // MARK: - Camera Management
    
    func startCameraSession() async {
        do {
            await cameraManager.startSession()
            print("✅ CONTROLLER: Camera session started")
        } catch {
            print("❌ CONTROLLER: Camera session failed - \(error)")
            currentPhase = .error("Camera startup failed")
        }
    }
    
    func stopCameraSession() async {
        await cameraManager.stopSession()
        print("✅ CONTROLLER: Camera session stopped")
    }
    
    // MARK: - Recording Workflow (FIXED with VideoCoordinator)
    
    func startRecording() {
        guard currentPhase == .ready else { return }
        
        currentPhase = .recording
        recordingPhase = .recording
        
        // Start recording with VideoCoordinator integration
        cameraManager.startRecording { [weak self] videoURL in
            Task { @MainActor in
                await self?.handleRecordingCompleted(videoURL)
            }
        }
        
        print("🎬 RECORDING: Started with VideoCoordinator integration")
    }
    
    func stopRecording() {
        guard currentPhase == .recording else { return }
        
        currentPhase = .stopping
        recordingPhase = .stopping
        cameraManager.stopRecording()
        
        print("🎬 RECORDING: Stopping...")
    }
    
    // MARK: - Post-Recording Processing (FIXED - Use VideoCoordinator)
    
    private func handleRecordingCompleted(_ videoURL: URL?) async {
        guard let videoURL = videoURL else {
            handleRecordingError("Recording failed")
            return
        }
        
        recordedVideoURL = videoURL
        currentPhase = .aiProcessing
        recordingPhase = .aiProcessing
        
        print("🎬 POST-PROCESSING: Starting VideoCoordinator workflow")
        
        // NEW: Use VideoCoordinator for complete post-processing
        await processVideoWithCoordinator(videoURL: videoURL)
    }
    
    private func processVideoWithCoordinator(videoURL: URL) async {
        guard let currentUser = authService.currentUser else {
            handleRecordingError("No authenticated user")
            return
        }
        
        do {
            print("🎬 VIDEO COORDINATOR: Starting complete post-processing workflow")
            
            // Call VideoCoordinator for complete workflow:
            // Recording → AI Analysis → Compression → Upload → Feed Integration
            let createdVideo = try await videoCoordinator.processVideoCreation(
                recordedVideoURL: videoURL,
                recordingContext: recordingContext,
                userID: currentUser.id,
                userTier: currentUser.tier
            )
            
            print("✅ VIDEO COORDINATOR: Post-processing completed successfully")
            print("✅ CREATED VIDEO: \(createdVideo.title) (ID: \(createdVideo.id))")
            
            // Update UI state
            currentPhase = .complete
            recordingPhase = .complete
            
            // Store the AI result if available
            aiAnalysisResult = videoCoordinator.aiAnalysisResult
            
            // Apply AI results to metadata if available
            if let aiResult = aiAnalysisResult {
                videoMetadata.title = aiResult.title
                videoMetadata.description = aiResult.description
                videoMetadata.hashtags = aiResult.hashtags
                videoMetadata.aiAnalysisComplete = true
                
                print("✅ AI RESULTS: Applied to metadata")
                print("✅ TITLE: '\(aiResult.title)'")
                print("✅ HASHTAGS: \(aiResult.hashtags)")
            }
            
        } catch {
            print("❌ VIDEO COORDINATOR: Post-processing failed - \(error.localizedDescription)")
            handleRecordingError("Post-processing failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Legacy Handlers (Updated)
    
    func handleVideoRecorded(_ url: URL) {
        // This is now handled by handleRecordingCompleted
        recordedVideoURL = url
        currentPhase = .aiProcessing
    }
    
    func handleRecordingStateChanged(_ phase: RecordingPhase) {
        recordingPhase = phase
        
        // Update current phase to match
        switch phase {
        case .ready:
            currentPhase = .ready
        case .recording:
            currentPhase = .recording
        case .stopping:
            currentPhase = .stopping
        case .aiProcessing:
            currentPhase = .aiProcessing
        case .complete:
            currentPhase = .complete
        case .error(let message):
            currentPhase = .error(message)
        }
    }
    
    func handleAIAnalysisComplete(_ result: VideoAnalysisResult?) {
        print("🧠 DEBUG: AI analysis completed")
        print("🧠 DEBUG: Result exists: \(result != nil)")
        
        if let result = result {
            print("🧠 DEBUG: AI title: '\(result.title)'")
            print("🧠 DEBUG: AI description: '\(result.description)'")
            print("🧠 DEBUG: AI hashtags: \(result.hashtags)")
            
            // Apply AI results to metadata
            videoMetadata.title = result.title
            videoMetadata.description = result.description
            videoMetadata.hashtags = Array(Set(result.hashtags))
            videoMetadata.aiSuggestedTitles = [
                result.title,
                "\(result.title) 🔥",
                "\(result.title) - What do you think?"
            ]
            videoMetadata.aiSuggestedHashtags = result.hashtags
        } else {
            print("🧠 DEBUG: AI analysis returned nil - user will create content manually")
        }
        
        // Store AI result and transition to metadata input
        aiAnalysisResult = result
        videoMetadata.aiAnalysisComplete = true
        currentPhase = .complete
    }
    
    func handleAIAnalysisCancel() {
        currentPhase = .ready
        recordedVideoURL = nil
        aiAnalysisResult = nil
    }
    
    func handleBackToRecording() {
        currentPhase = .ready
        recordedVideoURL = nil
        aiAnalysisResult = nil
        resetMetadata()
    }
    
    // MARK: - Error Handling
    
    private func handleRecordingError(_ message: String) {
        errorMessage = message
        currentPhase = .error(message)
        recordingPhase = .error(message)
        
        print("❌ RECORDING ERROR: \(message)")
    }
    
    func clearError() {
        errorMessage = nil
        currentPhase = .ready
        recordingPhase = .ready
    }
    
    // MARK: - Helper Methods
    
    private func resetMetadata() {
        videoMetadata = VideoMetadata()
    }
    
    // MARK: - VideoCoordinator State Access
    
    var coordinatorCurrentPhase: VideoCreationPhase {
        videoCoordinator.currentPhase
    }
    
    var coordinatorProgress: Double {
        videoCoordinator.overallProgress
    }
    
    var coordinatorCurrentTask: String {
        videoCoordinator.currentTask
    }
    
    var coordinatorIsProcessing: Bool {
        videoCoordinator.isProcessing
    }
}

// MARK: - Data Models

enum RecordingPhase: Equatable {
    case ready
    case recording
    case stopping
    case aiProcessing
    case complete
    case error(String)
    
    static func == (lhs: RecordingPhase, rhs: RecordingPhase) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.recording, .recording), (.stopping, .stopping),
             (.aiProcessing, .aiProcessing), (.complete, .complete):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
    
    var isRecording: Bool {
        switch self {
        case .recording: return true
        default: return false
        }
    }
    
    var canStartRecording: Bool {
        switch self {
        case .ready: return true
        default: return false
        }
    }
    
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .recording: return "Recording"
        case .stopping: return "Stopping"
        case .aiProcessing: return "Processing"
        case .complete: return "Complete"
        case .error(_): return "Error"
        }
    }
}

struct VideoMetadata {
    var title: String = ""
    var description: String = ""
    var hashtags: [String] = []
    var isPrivate: Bool = false
    
    // AI Analysis results
    var aiSuggestedTitles: [String] = []
    var aiSuggestedHashtags: [String] = []
    var aiAnalysisComplete: Bool = false
}

// MARK: - Recording Context

enum RecordingContext {
    case newThread
    case stitchToThread(threadID: String, threadInfo: ThreadInfo)
    case replyToVideo(videoID: String, videoInfo: CameraVideoInfo)
    case continueThread(threadID: String, threadInfo: ThreadInfo)
    
    var displayTitle: String {
        switch self {
        case .newThread: return "New Thread"
        case .stitchToThread(_, let info): return "Stitching to \(info.creatorName)"
        case .replyToVideo(_, let info): return "Replying to \(info.creatorName)"
        case .continueThread(_, let info): return "Adding to \(info.creatorName)'s thread"
        }
    }
    
    var contextDescription: String {
        switch self {
        case .newThread: return "Start a new conversation"
        case .stitchToThread(_, let info): return "Stitch to: \(info.title)"
        case .replyToVideo(_, let info): return "Reply to: \(info.title)"
        case .continueThread(_, let info): return "Continue: \(info.title)"
        }
    }
}

struct ThreadInfo {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
    let participantCount: Int
    let stitchCount: Int
}

struct CameraVideoInfo {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
}
