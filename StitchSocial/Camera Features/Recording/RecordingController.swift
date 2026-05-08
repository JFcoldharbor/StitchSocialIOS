//
//  RecordingController.swift
//  StitchSocial
//
//  Layer 3: Recording Controller
//
//  ARCHITECTURE:
//  - Segment-based recording (TikTok-style tap/hold)
//  - Async timer via Task.sleep (no Timer on main runloop)
//  - Modern segment merge: AVURLAsset + export(to:as:) async
//  - Background compression starts on .complete
//  - Mutable recordingContext for stitch/reply reuse
//  - @ObservedObject-friendly: owned by presentation wrapper, not self
//
//  CACHING: compressionResult cached until trim invalidates
//  CLEANUP: temp segments deleted after merge, compression cancelled on deinit
//  THREADING: All @Published updates on MainActor, heavy work on Task.detached
//

import Foundation
import SwiftUI
import Photos
@preconcurrency import AVFoundation
import FirebaseStorage

// MARK: - Data Models

enum RecordingContext {
    case newThread
    case stitchToThread(threadID: String, threadInfo: ThreadInfo)
    case replyToVideo(videoID: String, videoInfo: CameraVideoInfo)
    case continueThread(threadID: String, threadInfo: ThreadInfo)
    case spinOffFrom(videoID: String, threadID: String, videoInfo: CameraVideoInfo)

    var displayTitle: String {
        switch self {
        case .newThread: return "New Thread"
        case .stitchToThread(_, let i): return "Stitching to \(i.creatorName)"
        case .replyToVideo(_, let i): return "Replying to \(i.creatorName)"
        case .continueThread(_, let i): return "Adding to \(i.creatorName)'s thread"
        case .spinOffFrom(_, _, let i): return "Responding to \(i.creatorName)"
        }
    }

    var contextDescription: String {
        switch self {
        case .newThread: return "Start a new conversation"
        case .stitchToThread(_, let i): return "Stitch to: \(i.title)"
        case .replyToVideo(_, let i): return "Reply to: \(i.title)"
        case .continueThread(_, let i): return "Continue: \(i.title)"
        case .spinOffFrom(_, _, let i): return "Spin-off from: \(i.title)"
        }
    }

    /// The URL of the video the user is responding to, if any. Used by
    /// the reaction camera to auto-fill the content zone with the source
    /// video the user tapped Stitch on.
    var sourceVideoURL: URL? {
        let urlString: String?
        switch self {
        case .newThread:                       urlString = nil
        case .stitchToThread(_, let i):        urlString = i.videoURL
        case .replyToVideo(_, let i):          urlString = i.videoURL
        case .continueThread(_, let i):        urlString = i.videoURL
        case .spinOffFrom(_, _, let i):        urlString = i.videoURL
        }
        guard let s = urlString, !s.isEmpty, let url = URL(string: s) else { return nil }
        return url
    }
}

struct ThreadInfo {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
    let participantCount: Int
    let stitchCount: Int
    /// Firebase Storage URL of the parent video (when known). Threaded
    /// down to the reaction camera so it can auto-fill the source zone.
    var videoURL: String? = nil
}

struct CameraVideoInfo {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
    /// Firebase Storage URL of the video being responded to.
    var videoURL: String? = nil
}

// MARK: - Phase Machine

enum RecordingPhase: Equatable {
    case ready, recording, stopping, aiProcessing, complete, error(String)

    static func == (lhs: RecordingPhase, rhs: RecordingPhase) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready), (.recording, .recording), (.stopping, .stopping),
             (.aiProcessing, .aiProcessing), (.complete, .complete): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var isRecording: Bool { if case .recording = self { return true } else { return false } }
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .recording: return "Recording"
        case .stopping: return "Stopping"
        case .aiProcessing: return "Processing"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }
}

struct VideoMetadata {
    var title = ""
    var description = ""
    var hashtags: [String] = []
}

// MARK: - Segment

struct RecordingSegment: Identifiable {
    let id: UUID
    let videoURL: URL
    let duration: TimeInterval
    let recordedAt: Date
}

// MARK: - Recording Controller

@MainActor
class RecordingController: ObservableObject {

    // MARK: - Published State

    @Published var currentPhase: RecordingPhase = .ready
    @Published var recordingPhase: RecordingPhase = .ready
    @Published var videoMetadata = VideoMetadata()
    @Published var errorMessage: String?
    @Published var aiAnalysisResult: VideoAnalysisResult?
    @Published var recordedVideoURL: URL?
    @Published var isSavingSegment = false

    // MARK: - Timer State (async — no Timer on main runloop)
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStartTime: Date?
    @Published var currentSegmentDuration: TimeInterval = 0
    private var timerTask: Task<Void, Never>?

    // MARK: - Segments
    @Published var segments: [RecordingSegment] = []

    var totalDuration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
    var canDelete: Bool { !segments.isEmpty && currentPhase != .recording }
    var canFinish: Bool { !segments.isEmpty && currentPhase != .recording }

    var userTierLimit: TimeInterval {
        guard let user = authService.currentUser else { return 30 }
        return videoService.getMaxRecordingDuration(for: user.tier)
    }

    // MARK: - Compression State
    @Published var compressedVideoURL: URL?
    @Published var compressionComplete = false
    @Published var compressionProgress = 0.0
    @Published var originalFileSize: Int64 = 0
    @Published var compressedFileSize: Int64 = 0
    private var compressionTask: Task<Void, Never>?

    // MARK: - Dependencies
    private let videoService: VideoService
    private let authService: AuthService
    private let aiAnalyzer: AIVideoAnalyzer
    private let videoCoordinator: VideoCoordinator
    private let fastCompressor = FastVideoCompressor.shared
    let cameraManager: CinematicCameraManager

    // MARK: - Config
    var recordingContext: RecordingContext

    private var maxRecordingDuration: TimeInterval {
        guard let user = authService.currentUser else { return 30 }
        return VideoService().getMaxRecordingDuration(for: user.tier)
    }

    private var isUnlimitedRecording: Bool {
        guard let user = authService.currentUser else { return false }
        return user.tier == .founder || user.tier == .coFounder
    }

    var currentUserTier: UserTier {
        authService.currentUser?.tier ?? .rookie
    }

    // MARK: - Init

    init(recordingContext: RecordingContext) {
        self.recordingContext = recordingContext
        self.videoService = VideoService()
        self.authService = AuthService()
        self.aiAnalyzer = AIVideoAnalyzer.shared
        self.cameraManager = CinematicCameraManager.shared
        self.videoCoordinator = VideoCoordinator(
            videoService: videoService,
            userService: UserService(),
            aiAnalyzer: aiAnalyzer,
            uploadService: VideoUploadService(),
            cachingService: CachingService.shared
        )
        print("🎬 RECORDING CONTROLLER: Initialized")
    }

    deinit {
        timerTask?.cancel()
        compressionTask?.cancel()
        print("🎬 RECORDING CONTROLLER: Deinitialized")
    }

    // MARK: - Camera Session

    func startCameraSession() async {
        await cameraManager.startSession()
        if let user = authService.currentUser {
            let limit = videoService.getMaxRecordingDuration(for: user.tier)
            print("✅ CONTROLLER: Camera started — \(user.tier.displayName) tier, \(Int(limit))s limit")
        } else {
            print("✅ CONTROLLER: Camera started — default 30s limit")
        }
    }

    func stopCameraSession() async {
        stopTimer()
        cancelBackgroundCompression()
        await cameraManager.stopSession()
        print("⏹ CONTROLLER: Camera stopped")
    }

    // MARK: - Segment Recording

    func startSegment() {
        guard currentPhase == .ready else { return }
        guard !isSavingSegment, !cameraManager.isRecording else {
            print("⚠️ SEGMENT: Cannot start — busy")
            return
        }

        guard videoService.canContinueRecording(
            currentDuration: totalDuration,
            userTier: authService.currentUser?.tier ?? .rookie
        ) else {
            print("⚠️ SEGMENT: Tier limit reached")
            return
        }

        currentPhase = .recording
        recordingPhase = .recording
        recordingStartTime = Date()
        currentSegmentDuration = 0

        startTimer()

        cameraManager.startRecording { [weak self] videoURL in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if videoURL == nil && !self.cameraManager.isRecording {
                    self.stopTimer()
                    self.currentPhase = .ready
                    self.recordingPhase = .ready
                    return
                }
                self.handleSegmentRecorded(videoURL)
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        print("🎬 SEGMENT: Started segment \(segments.count + 1)")
    }

    func stopSegment() {
        guard currentPhase == .recording else { return }
        currentPhase = .stopping
        recordingPhase = .stopping
        isSavingSegment = true
        stopTimer()
        cameraManager.stopRecording()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        print("🎬 SEGMENT: Stopped at \(String(format: "%.1f", currentSegmentDuration))s")
    }

    private func handleSegmentRecorded(_ videoURL: URL?) {
        guard let url = videoURL else {
            isSavingSegment = false
            handleRecordingError("Segment recording failed")
            return
        }

        segments.append(RecordingSegment(
            id: UUID(), videoURL: url,
            duration: currentSegmentDuration, recordedAt: Date()
        ))

        currentPhase = .ready
        recordingPhase = .ready
        currentSegmentDuration = 0
        isSavingSegment = false
        print("✅ SEGMENT: Saved #\(segments.count) — total \(String(format: "%.1f", totalDuration))s")
    }

    func deleteNewestSegment() {
        guard canDelete else { return }
        let removed = segments.removeLast()
        try? FileManager.default.removeItem(at: removed.videoURL)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if segments.isEmpty { currentPhase = .ready; recordingPhase = .ready }
    }

    // MARK: - Finish Recording (merge + compress)

    func finishRecording() async {
        guard canFinish else { return }
        currentPhase = .stopping
        recordingPhase = .stopping

        do {
            let mergedURL = try await mergeSegments()
            recordedVideoURL = mergedURL
            startBackgroundCompression(mergedURL)
            currentPhase = .complete
            recordingPhase = .complete
            print("✅ FINISH: Merged \(segments.count) segments")
        } catch {
            handleRecordingError("Merge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Gallery Video

    func processSelectedVideo(_ videoURL: URL) async {
        recordedVideoURL = videoURL
        startBackgroundCompression(videoURL)
        currentPhase = .complete
        recordingPhase = .complete
    }

    // MARK: - Async Timer (no Timer on main runloop)

    private func startTimer() {
        stopTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms tick
                guard let self, let start = self.recordingStartTime else { continue }

                let segDuration = Date().timeIntervalSince(start)
                self.currentSegmentDuration = segDuration
                self.recordingDuration = self.totalDuration + segDuration

                // Auto-stop at tier limit
                if !self.isUnlimitedRecording && self.recordingDuration >= self.maxRecordingDuration {
                    self.stopSegment()
                    return
                }
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // Alias for external callers
    func stopRecordingTimer() { stopTimer() }

    // MARK: - Segment Merge (modern async)

    private func mergeSegments() async throws -> URL {
        guard !segments.isEmpty else { throw MergeError.noSegments }
        if segments.count == 1 { return segments[0].videoURL }

        let composition = AVMutableComposition()
        guard let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MergeError.trackCreationFailed
        }

        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform?
        var firstSize: CGSize?

        for segment in segments {
            let asset = AVURLAsset(url: segment.videoURL)
            let duration = try await asset.load(.duration)

            if let videoAssetTrack = try? await asset.loadTracks(withMediaType: .video).first {
                if firstTransform == nil {
                    firstTransform = try await videoAssetTrack.load(.preferredTransform)
                    firstSize = try await videoAssetTrack.load(.naturalSize)
                }
                try vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoAssetTrack, at: cursor)
            }

            if let audioAssetTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioAssetTrack, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")

        // Build video composition for portrait orientation
        if let transform = firstTransform, let naturalSize = firstSize {
            vTrack.preferredTransform = transform

            let videoComp = AVMutableVideoComposition()
            videoComp.frameDuration = CMTime(value: 1, timescale: 30)
            videoComp.renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            let layerInst = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
            layerInst.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInst]
            videoComp.instructions = [instruction]

            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw MergeError.exportFailed
            }
            session.videoComposition = videoComp
            try await session.export(to: outputURL, as: .mp4)
        } else {
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw MergeError.exportFailed
            }
            try await session.export(to: outputURL, as: .mp4)
        }

        // Cleanup segment files
        for segment in segments {
            try? FileManager.default.removeItem(at: segment.videoURL)
        }

        return outputURL
    }

    // MARK: - Background Compression

    private func startBackgroundCompression(_ videoURL: URL) {
        cancelBackgroundCompression()

        let size = getFileSize(videoURL)
        originalFileSize = size

        compressionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fastCompressor.compress(
                    sourceURL: videoURL,
                    targetSizeMB: 50.0,
                    preserveResolution: false,
                    progressCallback: { [weak self] p in
                        Task { @MainActor [weak self] in self?.compressionProgress = p }
                    }
                )
                guard !Task.isCancelled else { return }

                self.compressedVideoURL = result.outputURL
                self.compressedFileSize = result.compressedSize
                self.compressionComplete = true
                let savings = size > 0 ? 100.0 - (Double(result.compressedSize) / Double(size) * 100.0) : 0
                print("📦 COMPRESSION: \(size / 1024 / 1024)MB → \(result.compressedSize / 1024 / 1024)MB (\(String(format: "%.0f", savings))% saved)")
            } catch {
                print("⚠️ COMPRESSION: Failed — \(error.localizedDescription)")
            }
        }
    }

    func cancelBackgroundCompression() {
        compressionTask?.cancel()
        compressionTask = nil
    }

    func invalidateCompression() {
        cancelBackgroundCompression()
        if let url = compressedVideoURL { try? FileManager.default.removeItem(at: url) }
        compressedVideoURL = nil
        compressionComplete = false
        compressionProgress = 0
        originalFileSize = 0
        compressedFileSize = 0
    }

    var compressionSavingsText: String {
        guard originalFileSize > 0, compressedFileSize > 0 else { return "" }
        return String(format: "%.0f%% smaller", 100.0 - (Double(compressedFileSize) / Double(originalFileSize) * 100.0))
    }

    var bestVideoURLForUpload: URL? {
        compressionComplete ? compressedVideoURL : recordedVideoURL
    }

    // MARK: - Error Handling

    func handleRecordingError(_ message: String) {
        currentPhase = .error(message)
        recordingPhase = .error(message)
        errorMessage = message
        print("❌ RECORDING: \(message)")
    }

    func clearError() {
        currentPhase = .ready
        recordingPhase = .ready
        errorMessage = nil
    }

    // MARK: - Display Helpers

    var formattedRecordingDuration: String {
        let m = Int(recordingDuration) / 60
        let s = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var recordingProgress: Double {
        isUnlimitedRecording ? 0 : min(recordingDuration / maxRecordingDuration, 1.0)
    }

    var recordingLimitText: String {
        guard let user = authService.currentUser else { return "30s limit" }
        switch user.tier {
        case .founder, .coFounder: return "Unlimited"
        case .partner, .legendary, .topCreator: return "2min limit"
        default: return "30s limit"
        }
    }

    var timeRemainingText: String {
        if isUnlimitedRecording { return "∞" }
        let remaining = maxRecordingDuration - recordingDuration
        guard remaining > 0 else { return "00:00" }
        return String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60)
    }

    // MARK: - Gallery Save

    func saveVideoToGallery(_ videoURL: URL) async {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else { continuation.resume(); return }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, _ in
                    if success { print("✅ GALLERY: Saved") }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Zoom (convenience)

    func setZoomFactor(_ factor: CGFloat) {
        Task { await cameraManager.setZoom(factor) }
    }

    // MARK: - Helpers

    private func getFileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - Errors

enum MergeError: LocalizedError {
    case noSegments, trackCreationFailed, exportFailed
    var errorDescription: String? {
        switch self {
        case .noSegments: return "No segments to merge"
        case .trackCreationFailed: return "Failed to create composition track"
        case .exportFailed: return "Export session failed"
        }
    }
}
