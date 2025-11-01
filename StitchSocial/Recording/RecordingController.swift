//
//  RecordingController.swift
//  StitchSocial
//
//  FIXED: Upload timing - now only uploads after user confirms "Post" in ThreadComposer
//  FIXED: Retain cycle issues causing crashes on exit + tier-based recording durations
//

import Foundation
import SwiftUI
import Photos
@preconcurrency import AVFoundation
import FirebaseStorage

// MARK: - Data Models and Types

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
    var aiAnalysisComplete: Bool = false
    var aiSuggestedTitles: [String] = []
    var aiSuggestedHashtags: [String] = []
}

// MARK: - Recording Controller (FIXED RETAIN CYCLES + TIER-BASED)

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
    
    // MARK: - Recording Timer State (FIXED)
    
    private var recordingTimer: Timer?  // FIXED: Not @Published to avoid main actor issues in deinit
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStartTime: Date?
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let authService: AuthService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoCoordinator: VideoCoordinator
    let cameraManager: CinematicCameraManager
    
    // MARK: - Configuration - TIER-BASED RECORDING DURATIONS
    
    let recordingContext: RecordingContext
    private let recordingTickInterval: TimeInterval = 0.1
    
    // Tier-based recording durations
    private var maxRecordingDuration: TimeInterval {
        guard let currentUser = authService.currentUser else { return 30.0 }
        
        switch currentUser.tier {
        case .founder, .coFounder:
            return 0  // Unlimited recording
        case .partner, .legendary, .topCreator:
            return 120.0  // 2 minutes
        default:
            return 30.0   // 30 seconds
        }
    }
    
    private var isUnlimitedRecording: Bool {
        guard let currentUser = authService.currentUser else { return false }
        return currentUser.tier == .founder || currentUser.tier == .coFounder
    }
    
    // MARK: - Initialization
    
    init(recordingContext: RecordingContext) {
        self.recordingContext = recordingContext
        self.videoService = VideoService()
        self.authService = AuthService()
        self.aiAnalyzer = AIVideoAnalyzer()
        self.cameraManager = CinematicCameraManager.shared
        
        self.videoCoordinator = VideoCoordinator(
            videoService: videoService,
            userService: UserService(),
            aiAnalyzer: aiAnalyzer,
            videoProcessor: VideoProcessingService(),
            uploadService: VideoUploadService(),
            cachingService: nil
        )
        
        print("🎬 RECORDING CONTROLLER: Initialized with tier-based recording")
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
        // FIXED: Direct timer cleanup to prevent retain cycles
        stopRecordingTimer()
        await cameraManager.stopSession()
        print("✅ CONTROLLER: Camera session stopped")
    }
    
    // MARK: - Recording Workflow (TIER-BASED)
    
    func startRecording() {
        guard currentPhase == .ready else { return }
        
        currentPhase = .recording
        recordingPhase = .recording
        recordingStartTime = Date()
        recordingDuration = 0
        
        if !isUnlimitedRecording {
            startRecordingTimer()
        }
        
        // FIXED: Use weak self in camera callback to prevent retain cycle
        cameraManager.startRecording { [weak self] videoURL in
            Task { @MainActor [weak self] in
                await self?.handleRecordingCompleted(videoURL)
            }
        }
       
        print("🎬 RECORDING: Started - Tier: \(authService.currentUser?.tier.rawValue ?? "unknown"), Duration: \(isUnlimitedRecording ? "Unlimited" : "\(maxRecordingDuration)s")")
    }
    
    func stopRecording() {
        guard currentPhase == .recording else { return }
        
        currentPhase = .stopping
        recordingPhase = .stopping
        
        stopRecordingTimer()
        cameraManager.stopRecording()
        
        print("🎬 RECORDING: Stopped at \(String(format: "%.1f", recordingDuration))s")
    }
    
    // MARK: - Recording Timer Management (FIXED)
    
    private func startRecordingTimer() {
        stopRecordingTimer()
        
        // FIXED: Proper weak self handling to prevent retain cycles
        recordingTimer = Timer.scheduledTimer(withTimeInterval: recordingTickInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateRecordingDuration()
            }
        }
        
        print("⏱️ TIMER: Recording timer started")
    }
    
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        print("⏱️ TIMER: Recording timer stopped")
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        
        recordingDuration = Date().timeIntervalSince(startTime)
        
        if !isUnlimitedRecording && recordingDuration >= maxRecordingDuration {
            print("⏱️ AUTO-STOP: Maximum duration reached (\(maxRecordingDuration)s)")
            handleAutoStop()
        }
    }
    
    private func handleAutoStop() {
        guard currentPhase == .recording else { return }
        print("🛑 AUTO-STOP: Automatically stopping recording")
        stopRecording()
    }
    
    // MARK: - Duration Helper Properties (TIER-BASED)
    
    var formattedRecordingDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var recordingProgress: Double {
        if isUnlimitedRecording { return 0.0 }
        return min(recordingDuration / maxRecordingDuration, 1.0)
    }
    
    var recordingLimitText: String {
        guard let currentUser = authService.currentUser else { return "30s limit" }
        
        switch currentUser.tier {
        case .founder, .coFounder:
            return "Unlimited"
        case .partner, .legendary, .topCreator:
            return "2min limit"
        default:
            return "30s limit"
        }
    }
    
    var timeRemainingText: String {
        if isUnlimitedRecording { return "∞" }
        
        let remaining = maxRecordingDuration - recordingDuration
        if remaining <= 0 { return "00:00" }
        
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Gallery Video Processing
    
    func processSelectedVideo(_ videoURL: URL) async {
        print("📱 RECORDING CONTROLLER: Processing gallery-selected video")
        recordedVideoURL = videoURL
        currentPhase = .aiProcessing
        recordingPhase = .aiProcessing
        await handleRecordingCompleted(videoURL)
    }
    
    // MARK: - Post-Recording Processing (FIXED - NO PREMATURE UPLOAD)
    
    private func handleRecordingCompleted(_ videoURL: URL?) async {
        guard let videoURL = videoURL else {
            handleRecordingError("Recording failed")
            return
        }
        
        print("📹 RECORDING: Video recorded successfully")
        print("📹 SAVING: Saving to photo gallery as backup")
        
        // Save to gallery immediately (backup in case of crash)
        await saveVideoToGallery(videoURL)
        
        recordedVideoURL = videoURL
        currentPhase = .complete
        recordingPhase = .complete
        
        print("✅ RECORDING: Ready for ThreadComposer")
        print("✅ Upload will occur when user confirms 'Post'")
    }
    
    private func saveVideoToGallery(_ videoURL: URL) async {
        print("💾 GALLERY: Saving video to user's photo library")
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    print("⚠️ GALLERY: Permission denied")
                    continuation.resume()
                    return
                }
                
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, error in
                    if success {
                        print("✅ GALLERY: Video saved successfully")
                    } else if let error = error {
                        print("❌ GALLERY: Failed to save - \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Legacy Handlers (Updated)
    
    func handleVideoRecorded(_ url: URL) {
        recordedVideoURL = url
        currentPhase = .aiProcessing
    }
    
    func handleRecordingStateChanged(_ phase: RecordingPhase) {
        recordingPhase = phase
        
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
    
    // MARK: - Error Handling (FIXED)
    
    private func handleRecordingError(_ message: String) {
        stopRecordingTimer()
        errorMessage = message
        currentPhase = .error(message)
        recordingPhase = .error(message)
        
        print("❌ RECORDING ERROR: \(message)")
    }
    
    func clearError() {
        errorMessage = nil
        currentPhase = .ready
        recordingPhase = .ready
        recordingDuration = 0
        recordingStartTime = nil
    }
    
    // MARK: - Helper Methods
    
    private func resetMetadata() {
        videoMetadata = VideoMetadata()
    }
    
    // MARK: - VideoCoordinator Public Access
    
    var currentTask: String {
        videoCoordinator.currentTask
    }
    
    var coordinatorProgress: Double {
        videoCoordinator.overallProgress
    }
    
    var coordinatorIsProcessing: Bool {
        videoCoordinator.isProcessing
    }
    
    var coordinatorCurrentPhase: VideoCreationPhase {
        videoCoordinator.currentPhase
    }
    
    // MARK: - Cleanup (FIXED)
    
    deinit {
        // FIXED: Don't create Task in deinit - direct timer cleanup only
        recordingTimer?.invalidate()
        recordingTimer = nil
        print("🎬 RECORDING CONTROLLER: Deinitialized")
    }
}
