//
//  RecordingController.swift
//  StitchSocial
//
//  FIXED: Upload timing - now only uploads after user confirms "Post" in ThreadComposer
//  FIXED: Retain cycle issues causing crashes on exit + tier-based recording durations
//  ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ UPDATED: Background compression starts when recording completes (CapCut-style)
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
    case spinOffFrom(videoID: String, threadID: String, videoInfo: CameraVideoInfo)
    
    var displayTitle: String {
        switch self {
        case .newThread: return "New Thread"
        case .stitchToThread(_, let info): return "Stitching to \(info.creatorName)"
        case .replyToVideo(_, let info): return "Replying to \(info.creatorName)"
        case .continueThread(_, let info): return "Adding to \(info.creatorName)'s thread"
        case .spinOffFrom(_, _, let info): return "Responding to \(info.creatorName)"
        }
    }
    
    var contextDescription: String {
        switch self {
        case .newThread: return "Start a new conversation"
        case .stitchToThread(_, let info): return "Stitch to: \(info.title)"
        case .replyToVideo(_, let info): return "Reply to: \(info.title)"
        case .continueThread(_, let info): return "Continue: \(info.title)"
        case .spinOffFrom(_, _, let info): return "Spin-off from: \(info.title)"
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

// MARK: - Recording Controller (FIXED RETAIN CYCLES + TIER-BASED + BACKGROUND COMPRESSION)

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
    @Published var isSavingSegment: Bool = false  // Prevents starting new recording while saving
    
    // MARK: - Recording Timer State (FIXED)
    
    private var recordingTimer: Timer?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStartTime: Date?
    
    // MARK: - Segment Management (NEW - TikTok-style)
    
    /// Individual recording segment
    struct RecordingSegment: Identifiable {
        let id: UUID
        let videoURL: URL
        let duration: TimeInterval
        let recordedAt: Date
    }
    
    @Published var segments: [RecordingSegment] = []
    @Published var currentSegmentDuration: TimeInterval = 0
    
    /// User's tier-based recording limit (computed from current user)
    var userTierLimit: TimeInterval {
        guard let currentUser = authService.currentUser else { return 30.0 }
        return videoService.getMaxRecordingDuration(for: currentUser.tier)
    }
    
    /// Total duration across all segments
    var totalDuration: TimeInterval {
        return segments.reduce(0) { $0 + $1.duration }
    }
    
    /// Can delete segments (not while recording)
    var canDelete: Bool {
        return segments.count > 0 && currentPhase != .recording
    }
    
    /// Can finish recording (has segments and not recording)
    var canFinish: Bool {
        return segments.count > 0 && currentPhase != .recording
    }
    
    // MARK: - ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ NEW: Background Compression State
    
    @Published var compressedVideoURL: URL?
    @Published var compressionComplete: Bool = false
    @Published var compressionProgress: Double = 0.0
    @Published var originalFileSize: Int64 = 0
    @Published var compressedFileSize: Int64 = 0
    
    private var compressionTask: Task<Void, Never>?
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let authService: AuthService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoCoordinator: VideoCoordinator
    private let fastCompressor = FastVideoCompressor.shared  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ NEW
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
            uploadService: VideoUploadService(),
            cachingService: nil
        )
        
        print("ðŸŽ¬ RECORDING CONTROLLER: Initialized with tier-based recording + background compression")
    }
    
    // MARK: - Camera Management
    
    func startCameraSession() async {
        do {
            await cameraManager.startSession()
            
            // Log tier information
            if let currentUser = authService.currentUser {
                let limit = videoService.getMaxRecordingDuration(for: currentUser.tier)
                print("âœ… CONTROLLER: Camera session started")
                print("ðŸ‘¤ USER: \(currentUser.tier.displayName) tier - Recording limit: \(Int(limit))s")
            } else {
                print("âœ… CONTROLLER: Camera session started")
                print("âš ï¸ USER: Not logged in - using default 30s limit")
            }
        } catch {
            print("âŒ CONTROLLER: Camera session failed - \(error)")
            currentPhase = .error("Camera startup failed")
        }
    }
    
    func stopCameraSession() async {
        stopRecordingTimer()
        cancelBackgroundCompression()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Cancel any running compression
        await cameraManager.stopSession()
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ CONTROLLER: Camera session stopped")
    }
    
    // MARK: - Zoom Control
    
    func setZoomFactor(_ factor: CGFloat) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else { return }
        do {
            try device.lockForConfiguration()
            let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("⚠️ ZOOM: Failed to set zoom - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recording Workflow (TIER-BASED)
    
    func startRecording() {
        guard currentPhase == .ready else { return }
        
        currentPhase = .recording
        recordingPhase = .recording
        recordingStartTime = Date()
        recordingDuration = 0
        
        // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Reset compression state for new recording
        resetCompressionState()
        
        if !isUnlimitedRecording {
            startRecordingTimer()
        }
        
        cameraManager.startRecording { [weak self] videoURL in
            Task { @MainActor [weak self] in
                await self?.handleRecordingCompleted(videoURL)
            }
        }
       
        print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¬ RECORDING: Started - Tier: \(authService.currentUser?.tier.rawValue ?? "unknown"), Duration: \(isUnlimitedRecording ? "Unlimited" : "\(maxRecordingDuration)s")")
    }
    
    func stopRecording() {
        guard currentPhase == .recording else { return }
        
        currentPhase = .stopping
        recordingPhase = .stopping
        
        stopRecordingTimer()
        cameraManager.stopRecording()
        
        print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¬ RECORDING: Stopped at \(String(format: "%.1f", recordingDuration))s")
    }
    
    // MARK: - Recording Timer Management (FIXED)
    
    private func startRecordingTimer() {
        stopRecordingTimer()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: recordingTickInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateRecordingDuration()
            }
        }
        
        print("ÃƒÂ¢Ã‚ÂÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â TIMER: Recording timer started")
    }
    
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        print("ÃƒÂ¢Ã‚ÂÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â TIMER: Recording timer stopped")
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        
        currentSegmentDuration = Date().timeIntervalSince(startTime)
        recordingDuration = totalDuration + currentSegmentDuration  // For display purposes
        
        // Check tier limit against total duration (all segments + current)
        let combinedDuration = totalDuration + currentSegmentDuration
        if !isUnlimitedRecording && combinedDuration >= maxRecordingDuration {
            print("â±ï¸ AUTO-STOP: Tier limit reached (\(maxRecordingDuration)s)")
            handleAutoStop()
        }
    }
    
    private func handleAutoStop() {
        guard currentPhase == .recording else { return }
        print("ðŸ›‘ AUTO-STOP: Automatically stopping segment at tier limit")
        stopSegment()  // Use stopSegment instead of stopRecording
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
        if isUnlimitedRecording { return "ÃƒÂ¢Ã‹â€ Ã…Â¾" }
        
        let remaining = maxRecordingDuration - recordingDuration
        if remaining <= 0 { return "00:00" }
        
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Gallery Video Processing
    
    func processSelectedVideo(_ videoURL: URL) async {
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â± RECORDING CONTROLLER: Processing gallery-selected video")
        recordedVideoURL = videoURL
        currentPhase = .aiProcessing
        recordingPhase = .aiProcessing
        await handleRecordingCompleted(videoURL)
    }
    
    // MARK: - Segment Management (NEW - TikTok-style tap-and-hold)
    
    /// Start recording a new segment (called when finger goes down)
    func startSegment() {
        guard currentPhase != .recording else { return }
        
        // CRITICAL: Don't start if previous segment is still being saved
        guard !isSavingSegment else {
            print("âš ï¸ SEGMENT: Cannot start - previous segment still saving")
            return
        }
        
        // Check if we can continue recording (tier limit check)
        guard videoService.canContinueRecording(currentDuration: totalDuration, userTier: authService.currentUser?.tier ?? .rookie) else {
            print("âš ï¸ SEGMENT: Tier limit reached, cannot start new segment")
            return
        }
        
        currentPhase = .recording
        recordingPhase = .recording
        recordingStartTime = Date()
        currentSegmentDuration = 0
        
        // Start timer for current segment
        startRecordingTimer()
        
        // Start camera recording
        cameraManager.startRecording { [weak self] videoURL in
            Task { @MainActor [weak self] in
                self?.handleSegmentRecorded(videoURL)
            }
        }
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        print("ðŸŽ¬ SEGMENT: Started segment \(segments.count + 1)")
    }
    
    /// Stop recording current segment (called when finger releases)
    func stopSegment() {
        guard currentPhase == .recording else { return }
        
        currentPhase = .stopping
        recordingPhase = .stopping
        isSavingSegment = true  // Mark as saving to prevent new recording
        
        stopRecordingTimer()
        cameraManager.stopRecording()
        
        // Haptic feedback
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        
        print("ðŸŽ¬ SEGMENT: Stopped segment at \(String(format: "%.1f", currentSegmentDuration))s")
    }
    
    /// Handle when segment video is recorded
    private func handleSegmentRecorded(_ videoURL: URL?) {
        guard let videoURL = videoURL else {
            isSavingSegment = false  // Clear flag on error
            handleRecordingError("Segment recording failed")
            return
        }
        
        // Create segment
        let segment = RecordingSegment(
            id: UUID(),
            videoURL: videoURL,
            duration: currentSegmentDuration,
            recordedAt: Date()
        )
        
        segments.append(segment)
        
        // Update state to paused (can continue or finish)
        currentPhase = .ready  // Back to ready so user can tap again
        recordingPhase = .ready
        currentSegmentDuration = 0
        isSavingSegment = false  // Clear flag - ready for next segment
        
        print("âœ… SEGMENT: Saved segment \(segments.count) - Total duration: \(String(format: "%.1f", totalDuration))s")
    }
    
    /// Delete the most recent segment (LIFO - Last In First Out)
    func deleteNewestSegment() {
        guard canDelete else { return }
        
        let removedSegment = segments.removeLast()
        
        // Delete video file
        try? FileManager.default.removeItem(at: removedSegment.videoURL)
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        print("ðŸ—‘ï¸ SEGMENT: Deleted segment \(segments.count + 1) - New total: \(String(format: "%.1f", totalDuration))s")
        
        // If no segments left, reset to ready state
        if segments.isEmpty {
            currentPhase = .ready
            recordingPhase = .ready
        }
    }
    
    /// Finish recording - merge all segments and navigate to review
    func finishRecording() async {
        guard canFinish else { return }
        
        print("ðŸŽ¬ FINISH: Merging \(segments.count) segments...")
        
        currentPhase = .stopping
        recordingPhase = .stopping
        
        // Merge all segments into single video
        do {
            let mergedURL = try await mergeSegments()
            recordedVideoURL = mergedURL
            
            // Start background compression
            startBackgroundCompression(mergedURL)
            
            currentPhase = .complete
            recordingPhase = .complete
            
            print("âœ… FINISH: Successfully merged \(segments.count) segments")
        } catch {
            handleRecordingError("Failed to merge segments: \(error.localizedDescription)")
        }
    }
    
    /// Merge all recorded segments into a single video
    private func mergeSegments() async throws -> URL {
        guard !segments.isEmpty else {
            throw StitchError.processingError("No segments to merge")
        }
        
        // If only one segment, just return it
        if segments.count == 1 {
            return segments[0].videoURL
        }
        
        // Create composition
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw StitchError.processingError("Failed to create video track")
        }
        
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw StitchError.processingError("Failed to create audio track")
        }
        
        var currentTime = CMTime.zero
        var firstVideoTransform: CGAffineTransform?
        var firstVideoNaturalSize: CGSize?
        
        // Add each segment to the composition
        for segment in segments {
            let asset = AVAsset(url: segment.videoURL)
            
            // Add video track
            if let assetVideoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                // Capture transform from first segment
                if firstVideoTransform == nil {
                    firstVideoTransform = assetVideoTrack.preferredTransform
                    firstVideoNaturalSize = assetVideoTrack.naturalSize
                    print("ðŸ“ MERGE: First segment transform: \(assetVideoTrack.preferredTransform)")
                    print("ðŸ“ MERGE: First segment size: \(assetVideoTrack.naturalSize)")
                }
                
                let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
                try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
            }
            
            // Add audio track
            if let assetAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
                try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
            }
            
            currentTime = CMTimeAdd(currentTime, CMTime(seconds: segment.duration, preferredTimescale: 600))
        }
        
        // Apply the transform from first segment to maintain orientation
        if let transform = firstVideoTransform, let naturalSize = firstVideoNaturalSize {
            videoTrack.preferredTransform = transform
            
            // Create video composition to handle the transform properly
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            // Calculate the correct render size based on transform
            let renderSize = CGSize(
                width: naturalSize.height,  // Swap for portrait
                height: naturalSize.width
            )
            videoComposition.renderSize = renderSize
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(transform, at: .zero)
            
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            
            print("ðŸ“ MERGE: Applied portrait transform - render size: \(renderSize)")
            
            // Export with video composition
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw StitchError.processingError("Failed to create export session")
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.videoComposition = videoComposition  // Apply the composition
            
            await exportSession.export()
            
            guard exportSession.status == .completed else {
                throw StitchError.processingError("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            }
            
            print("âœ… MERGE: Exported portrait video")
            return outputURL
        } else {
            // Fallback: export without composition (shouldn't happen)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw StitchError.processingError("Failed to create export session")
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            
            await exportSession.export()
            
            guard exportSession.status == .completed else {
                throw StitchError.processingError("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            }
            
            return outputURL
        }
    }
    
    // MARK: - ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ NEW: Background Compression
    
    /// Start background compression immediately after recording (CapCut-style)
    private func startBackgroundCompression(_ videoURL: URL) {
        // Cancel any existing compression
        cancelBackgroundCompression()
        
        print("ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ BACKGROUND COMPRESSION: Starting while user reviews...")
        
        compressionTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Get original file size
                let originalSize = self.getFileSize(videoURL)
                await MainActor.run {
                    self.originalFileSize = originalSize
                }
                
                print("ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ BACKGROUND COMPRESSION: Original size \(originalSize / 1024 / 1024)MB")
                
                let result = try await self.fastCompressor.compress(
                    sourceURL: videoURL,
                    targetSizeMB: 50.0,  // Target 50MB for safe margin under 100MB limit
                    preserveResolution: false,
                    progressCallback: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.compressionProgress = progress
                        }
                    }
                )
                
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â BACKGROUND COMPRESSION: Cancelled")
                    return
                }
                
                await MainActor.run {
                    self.compressedVideoURL = result.outputURL
                    self.compressedFileSize = result.compressedSize
                    self.compressionComplete = true
                    self.compressionProgress = 1.0
                }
                
                let savings = 100.0 - (Double(result.compressedSize) / Double(result.originalSize) * 100.0)
                print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ BACKGROUND COMPRESSION: Complete!")
                print("   ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¦ \(result.originalSize / 1024 / 1024)MB ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ \(result.compressedSize / 1024 / 1024)MB")
                print("   ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã¢â‚¬Â° \(String(format: "%.0f", savings))% smaller")
                print("   ÃƒÂ¢Ã‚ÂÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â \(String(format: "%.1f", result.processingTime))s")
                
            } catch {
                print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â BACKGROUND COMPRESSION: Failed - \(error.localizedDescription)")
                // Not fatal - we'll compress on-demand during upload if needed
            }
        }
    }
    
    /// Cancel background compression (e.g., when user goes back to re-record)
    func cancelBackgroundCompression() {
        compressionTask?.cancel()
        compressionTask = nil
    }
    
    /// Invalidate compression (call when trim changes significantly)
    func invalidateCompression() {
        cancelBackgroundCompression()
        
        // Clean up old compressed file
        if let url = compressedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        resetCompressionState()
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ COMPRESSION: Invalidated (trim changed)")
    }
    
    private func resetCompressionState() {
        compressedVideoURL = nil
        compressionComplete = false
        compressionProgress = 0.0
        originalFileSize = 0
        compressedFileSize = 0
    }
    
    private func getFileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
    
    // MARK: - ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ NEW: Compression Status Helpers
    
    /// Formatted compression savings (e.g., "45% smaller")
    var compressionSavingsText: String {
        guard originalFileSize > 0, compressedFileSize > 0 else { return "" }
        let savings = 100.0 - (Double(compressedFileSize) / Double(originalFileSize) * 100.0)
        return String(format: "%.0f%% smaller", savings)
    }
    
    /// The best video URL to use for upload (compressed if available)
    var bestVideoURLForUpload: URL? {
        if compressionComplete, let compressed = compressedVideoURL {
            return compressed
        }
        return recordedVideoURL
    }
    
    // MARK: - Post-Recording Processing (ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED WITH BACKGROUND COMPRESSION)
    
    private func handleRecordingCompleted(_ videoURL: URL?) async {
        guard let videoURL = videoURL else {
            handleRecordingError("Recording failed")
            return
        }
        
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¹ RECORDING: Video recorded successfully")
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¹ SAVING: Saving to photo gallery as backup")
        
        // Save to gallery immediately (backup in case of crash)
        await saveVideoToGallery(videoURL)
        
        recordedVideoURL = videoURL
        
        // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ START BACKGROUND COMPRESSION IMMEDIATELY
        // This runs while user reviews the video, so by the time they tap "Post"
        // the video is already compressed (CapCut-style instant posting)
        startBackgroundCompression(videoURL)
        
        currentPhase = .complete
        recordingPhase = .complete
        
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ RECORDING: Ready for ThreadComposer")
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Background compression started")
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Upload will occur when user confirms 'Post'")
    }
    
    private func saveVideoToGallery(_ videoURL: URL) async {
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬â„¢Ã‚Â¾ GALLERY: Saving video to user's photo library")
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â GALLERY: Permission denied")
                    continuation.resume()
                    return
                }
                
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, error in
                    if success {
                        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ GALLERY: Video saved successfully")
                    } else if let error = error {
                        print("ÃƒÂ¢Ã‚ÂÃ…â€™ GALLERY: Failed to save - \(error.localizedDescription)")
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
        print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: AI analysis completed")
        print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: Result exists: \(result != nil)")
        
        if let result = result {
            print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: AI title: '\(result.title)'")
            print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: AI description: '\(result.description)'")
            print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: AI hashtags: \(result.hashtags)")
            
            videoMetadata.title = result.title
            videoMetadata.description = result.description
            videoMetadata.hashtags = Array(Set(result.hashtags))
            videoMetadata.aiSuggestedTitles = [
                result.title,
                "\(result.title) ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¥",
                "\(result.title) - What do you think?"
            ]
            videoMetadata.aiSuggestedHashtags = result.hashtags
        } else {
            print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â  DEBUG: AI analysis returned nil - user will create content manually")
        }
        
        aiAnalysisResult = result
        videoMetadata.aiAnalysisComplete = true
        currentPhase = .complete
    }
    
    func handleAIAnalysisCancel() {
        currentPhase = .ready
        recordedVideoURL = nil
        aiAnalysisResult = nil
        cancelBackgroundCompression()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Cancel compression too
    }
    
    func handleBackToRecording() {
        currentPhase = .ready
        recordedVideoURL = nil
        aiAnalysisResult = nil
        resetMetadata()
        cancelBackgroundCompression()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Cancel compression
        resetCompressionState()        // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Reset compression state
    }
    
    // MARK: - Error Handling (FIXED)
    
    private func handleRecordingError(_ message: String) {
        stopRecordingTimer()
        isSavingSegment = false  // Clear flag on error
        cancelBackgroundCompression()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Cancel compression on error
        errorMessage = message
        currentPhase = .error(message)
        recordingPhase = .error(message)
        
        print("ÃƒÂ¢Ã‚ÂÃ…â€™ RECORDING ERROR: \(message)")
    }
    
    func clearError() {
        errorMessage = nil
        currentPhase = .ready
        recordingPhase = .ready
        recordingDuration = 0
        recordingStartTime = nil
        resetCompressionState()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Reset compression state
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
        recordingTimer?.invalidate()
        recordingTimer = nil
        compressionTask?.cancel()  // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Cancel compression task
        print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¬ RECORDING CONTROLLER: Deinitialized")
    }
}
