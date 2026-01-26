//
//  CollectionPlayerViewModel.swift
//  StitchSocial
//
//  Layer 3: ViewModels - Collection Playback Controller
//  Dependencies: CollectionService, VideoService, VideoCollection, CollectionProgress, CoreVideoMetadata
//  Features: Segment playback, progress tracking, resume functionality, timestamped replies
//  CREATED: Phase 3 - Collections feature ViewModels
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

/// ViewModel for playing a collection with progress tracking
/// Handles segment navigation, watch progress persistence, and timestamped reply display
@MainActor
class CollectionPlayerViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let collectionService: CollectionService
    private let videoService: VideoService
    private let userID: String
    
    // MARK: - Published State - Collection Data
    
    /// The collection being played
    @Published private(set) var collection: VideoCollection
    
    /// All segments loaded for playback
    @Published private(set) var segments: [CoreVideoMetadata] = []
    
    /// Current segment being played
    @Published private(set) var currentSegment: CoreVideoMetadata?
    
    /// Current segment index (0-based)
    @Published private(set) var currentSegmentIndex: Int = 0
    
    // MARK: - Published State - Playback
    
    /// Current playback time within segment (seconds)
    @Published var currentTime: TimeInterval = 0
    
    /// Duration of current segment
    @Published private(set) var currentDuration: TimeInterval = 0
    
    /// Whether video is currently playing
    @Published var isPlaying: Bool = false
    
    /// Whether video is buffering
    @Published private(set) var isBuffering: Bool = false
    
    /// Playback rate (1.0 = normal)
    @Published var playbackRate: Float = 1.0
    
    // MARK: - Published State - Progress
    
    /// User's watch progress
    @Published private(set) var progress: CollectionProgress?
    
    /// Overall completion percentage (0.0 to 1.0)
    @Published private(set) var overallProgress: Double = 0.0
    
    /// Segments that have been completed
    @Published private(set) var completedSegmentIDs: Set<String> = []
    
    // MARK: - Published State - UI
    
    /// Loading state
    @Published private(set) var isLoading: Bool = false
    
    /// Error message
    @Published var errorMessage: String?
    
    /// Whether to show segment list overlay
    @Published var showSegmentList: Bool = false
    
    /// Whether to show playback controls
    @Published var showControls: Bool = true
    
    /// Whether to show resume prompt
    @Published var showResumePrompt: Bool = false
    
    /// Resume info for prompt
    @Published private(set) var resumeInfo: ResumePromptInfo?
    
    /// Timestamped replies for current segment
    @Published private(set) var timestampedReplies: [TimestampedReplyMarker] = []
    
    /// Whether replies overlay is showing
    @Published var showRepliesAtTimestamp: Bool = false
    
    /// Current timestamp for reply display
    @Published private(set) var activeReplyTimestamp: TimeInterval?
    
    // MARK: - Published State - Engagement
    
    /// Whether current user has hyped this collection
    @Published var hasHyped: Bool = false
    
    /// Whether current user has cooled this collection
    @Published var hasCooled: Bool = false
    
    // MARK: - Configuration
    
    /// Auto-advance to next segment when current finishes
    let autoAdvance: Bool = true
    
    /// Time before end to preload next segment (seconds)
    let preloadThreshold: TimeInterval = 5.0
    
    /// Minimum watch time to count as view (seconds)
    let minimumWatchTime: TimeInterval = 5.0
    
    /// Progress save interval (seconds)
    let progressSaveInterval: TimeInterval = 10.0
    
    // MARK: - Private State
    
    private var progressSaveTask: Task<Void, Never>?
    private var segmentWatchStartTime: Date?
    private var segmentWatchDuration: TimeInterval = 0
    private var hasCountedView: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        collection: VideoCollection,
        userID: String,
        collectionService: CollectionService,
        videoService: VideoService
    ) {
        self.collection = collection
        self.userID = userID
        self.collectionService = collectionService
        self.videoService = videoService
        
        setupProgressTracking()
        
        print("▶️ PLAYER VM: Initialized for collection \(collection.id)")
    }
    
    /// Convenience initializer with default services
    convenience init(
        collection: VideoCollection,
        userID: String
    ) {
        // Services are created here in MainActor context
        let collectionService = CollectionService()
        let videoService = VideoService()
        
        self.init(
            collection: collection,
            userID: userID,
            collectionService: collectionService,
            videoService: videoService
        )
    }
    
    deinit {
        progressSaveTask?.cancel()
    }
    
    // MARK: - Computed Properties - Navigation
    
    /// Whether there's a previous segment
    var hasPreviousSegment: Bool {
        currentSegmentIndex > 0
    }
    
    /// Whether there's a next segment
    var hasNextSegment: Bool {
        currentSegmentIndex < segments.count - 1
    }
    
    /// Current segment number (1-based for display)
    var currentSegmentNumber: Int {
        currentSegmentIndex + 1
    }
    
    /// Total segment count
    var totalSegments: Int {
        segments.count
    }
    
    /// Progress text (e.g., "Part 2 of 5")
    var segmentProgressText: String {
        "Part \(currentSegmentNumber) of \(totalSegments)"
    }
    
    /// Current segment title
    var currentSegmentTitle: String {
        currentSegment?.segmentDisplayTitle ?? "Part \(currentSegmentNumber)"
    }
    
    // MARK: - Computed Properties - Time Display
    
    /// Current time formatted (e.g., "2:34")
    var currentTimeFormatted: String {
        formatTime(currentTime)
    }
    
    /// Duration formatted
    var durationFormatted: String {
        formatTime(currentDuration)
    }
    
    /// Time remaining in current segment
    var timeRemaining: TimeInterval {
        max(0, currentDuration - currentTime)
    }
    
    /// Time remaining formatted
    var timeRemainingFormatted: String {
        "-\(formatTime(timeRemaining))"
    }
    
    /// Progress within current segment (0.0 to 1.0)
    var segmentProgress: Double {
        guard currentDuration > 0 else { return 0 }
        return min(1.0, currentTime / currentDuration)
    }
    
    /// Total time remaining in collection
    var totalTimeRemaining: TimeInterval {
        var remaining = timeRemaining
        
        for i in (currentSegmentIndex + 1)..<segments.count {
            remaining += segments[i].duration
        }
        
        return remaining
    }
    
    /// Total time remaining formatted
    var totalTimeRemainingFormatted: String {
        let hours = Int(totalTimeRemaining) / 3600
        let minutes = (Int(totalTimeRemaining) % 3600) / 60
        let seconds = Int(totalTimeRemaining) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d remaining", minutes, seconds)
        }
    }
    
    // MARK: - Computed Properties - Progress
    
    /// Whether collection is completed
    var isCompleted: Bool {
        overallProgress >= 1.0
    }
    
    /// Completion percentage for display
    var completionPercentage: String {
        String(format: "%.0f%% complete", overallProgress * 100)
    }
    
    /// Number of segments completed
    var completedSegmentCount: Int {
        completedSegmentIDs.count
    }
    
    // MARK: - Loading
    
    /// Load collection data and segments
    func load() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load segments
            segments = try await videoService.getVideosByCollection(collectionID: collection.id)
            
            guard !segments.isEmpty else {
                errorMessage = "No segments found"
                isLoading = false
                return
            }
            
            // Load user's progress
            progress = try await collectionService.getWatchProgress(
                userID: userID,
                collectionID: collection.id
            )
            
            // Check for resume point
            if let existingProgress = progress, existingProgress.isInProgress {
                // Show resume prompt
                resumeInfo = ResumePromptInfo(
                    segmentIndex: existingProgress.currentSegmentIndex,
                    segmentTitle: segments[safe: existingProgress.currentSegmentIndex]?.segmentDisplayTitle ?? "Part \(existingProgress.currentSegmentIndex + 1)",
                    timestamp: existingProgress.currentTimestamp,
                    percentComplete: existingProgress.percentComplete
                )
                showResumePrompt = true
                
                // Load completed segments
                completedSegmentIDs = Set(existingProgress.completedSegmentIDs)
                overallProgress = existingProgress.percentComplete
            } else {
                // Start from beginning
                await selectSegment(at: 0)
            }
            
            print("✅ PLAYER VM: Loaded \(segments.count) segments")
            
        } catch {
            errorMessage = "Failed to load collection: \(error.localizedDescription)"
            print("❌ PLAYER VM: Failed to load: \(error)")
        }
        
        isLoading = false
    }
    
    /// Resume from saved position
    func resumePlayback() {
        guard let resumeInfo = resumeInfo else {
            Task { await selectSegment(at: 0) }
            return
        }
        
        showResumePrompt = false
        
        Task {
            await selectSegment(at: resumeInfo.segmentIndex)
            seek(to: resumeInfo.timestamp)
            play()
        }
    }
    
    /// Start from beginning (ignore saved progress)
    func startFromBeginning() {
        showResumePrompt = false
        resumeInfo = nil
        
        Task {
            await selectSegment(at: 0)
            play()
        }
    }
    
    // MARK: - Segment Navigation
    
    /// Select and load a specific segment
    func selectSegment(at index: Int) async {
        guard index >= 0 && index < segments.count else { return }
        
        // Save progress for current segment before switching
        await saveCurrentSegmentProgress()
        
        currentSegmentIndex = index
        currentSegment = segments[index]
        currentDuration = segments[index].duration
        currentTime = 0
        hasCountedView = false
        segmentWatchStartTime = nil
        segmentWatchDuration = 0
        
        // Load timestamped replies for this segment
        await loadTimestampedReplies(for: segments[index].id)
        
        print("📍 PLAYER VM: Selected segment \(index + 1)")
    }
    
    /// Go to next segment
    func nextSegment() {
        guard hasNextSegment else { return }
        
        Task {
            await selectSegment(at: currentSegmentIndex + 1)
            if autoAdvance {
                play()
            }
        }
    }
    
    /// Go to previous segment
    func previousSegment() {
        // If more than 3 seconds in, restart current segment
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        
        guard hasPreviousSegment else {
            seek(to: 0)
            return
        }
        
        Task {
            await selectSegment(at: currentSegmentIndex - 1)
            play()
        }
    }
    
    /// Jump to specific segment by ID
    func jumpToSegment(id: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        Task {
            await selectSegment(at: index)
            play()
        }
        
        showSegmentList = false
    }
    
    // MARK: - Playback Control
    
    /// Start/resume playback
    func play() {
        isPlaying = true
        segmentWatchStartTime = Date()
        
        // Start progress save timer
        startProgressSaveTimer()
    }
    
    /// Pause playback
    func pause() {
        isPlaying = false
        
        // Accumulate watch time
        if let startTime = segmentWatchStartTime {
            segmentWatchDuration += Date().timeIntervalSince(startTime)
            segmentWatchStartTime = nil
        }
    }
    
    /// Toggle play/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Seek to specific time
    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, currentDuration))
    }
    
    /// Skip forward by seconds
    func skipForward(seconds: TimeInterval = 10) {
        let newTime = currentTime + seconds
        
        if newTime >= currentDuration && hasNextSegment {
            // Skip to next segment
            nextSegment()
        } else {
            seek(to: min(newTime, currentDuration))
        }
    }
    
    /// Skip backward by seconds
    func skipBackward(seconds: TimeInterval = 10) {
        seek(to: max(0, currentTime - seconds))
    }
    
    /// Update current playback time (called by player)
    func updatePlaybackTime(_ time: TimeInterval) {
        currentTime = time
        
        // Check for view count
        if !hasCountedView && getTotalWatchTime() >= minimumWatchTime {
            hasCountedView = true
            Task { await recordView() }
        }
        
        // Check for segment completion
        if currentDuration > 0 && time >= currentDuration - 0.5 {
            onSegmentComplete()
        }
        
        // Check for reply markers
        checkReplyMarkers(at: time)
        
        // Check for preload
        if hasNextSegment && timeRemaining <= preloadThreshold {
            preloadNextSegment()
        }
    }
    
    /// Handle segment completion
    private func onSegmentComplete() {
        guard let segment = currentSegment else { return }
        
        // Mark segment as completed
        if !completedSegmentIDs.contains(segment.id) {
            completedSegmentIDs.insert(segment.id)
            
            Task {
                _ = try? await collectionService.markSegmentComplete(
                    userID: userID,
                    collectionID: collection.id,
                    segmentID: segment.id,
                    totalSegments: segments.count
                )
            }
        }
        
        // Update overall progress
        overallProgress = Double(completedSegmentIDs.count) / Double(segments.count)
        
        // Auto-advance
        if autoAdvance && hasNextSegment {
            nextSegment()
        } else if !hasNextSegment {
            // Collection complete
            pause()
            print("🎉 PLAYER VM: Collection playback complete!")
        }
    }
    
    // MARK: - Progress Tracking
    
    /// Setup progress tracking
    private func setupProgressTracking() {
        // Observe playback state changes
        $isPlaying
            .sink { [weak self] playing in
                if playing {
                    self?.startProgressSaveTimer()
                } else {
                    self?.progressSaveTask?.cancel()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Start periodic progress save timer
    private func startProgressSaveTimer() {
        progressSaveTask?.cancel()
        
        progressSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.progressSaveInterval ?? 10) * 1_000_000_000)
                
                guard !Task.isCancelled else { break }
                
                await self?.saveCurrentSegmentProgress()
            }
        }
    }
    
    /// Save current progress to Firebase
    private func saveCurrentSegmentProgress() async {
        guard let segment = currentSegment else { return }
        
        var currentProgress = progress ?? CollectionProgress.startWatching(
            userID: userID,
            collectionID: collection.id,
            firstSegmentID: segment.id
        )
        
        currentProgress.updateCurrentPosition(
            segmentID: segment.id,
            segmentIndex: currentSegmentIndex,
            timestamp: currentTime
        )
        
        currentProgress.addWatchTime(getTotalWatchTime())
        currentProgress.updatePercentComplete(totalSegments: segments.count)
        
        // Add completed segments
        for completedID in completedSegmentIDs {
            currentProgress.markSegmentCompleted(completedID)
        }
        
        do {
            try await collectionService.updateWatchProgress(currentProgress)
            progress = currentProgress
        } catch {
            print("❌ PLAYER VM: Failed to save progress: \(error)")
        }
    }
    
    /// Get total watch time for current segment
    private func getTotalWatchTime() -> TimeInterval {
        var total = segmentWatchDuration
        
        if let startTime = segmentWatchStartTime {
            total += Date().timeIntervalSince(startTime)
        }
        
        return total
    }
    
    /// Record view for current segment
    private func recordView() async {
        guard let segment = currentSegment else { return }
        
        do {
            try await videoService.trackVideoView(
                videoID: segment.id,
                userID: userID,
                watchTime: getTotalWatchTime()
            )
            print("👁️ PLAYER VM: Recorded view for segment \(segment.id)")
        } catch {
            print("❌ PLAYER VM: Failed to record view: \(error)")
        }
    }
    
    // MARK: - Timestamped Replies
    
    /// Load timestamped replies for a segment
    private func loadTimestampedReplies(for segmentID: String) async {
        do {
            let replies = try await videoService.getTimestampedReplies(segmentID: segmentID)
            
            timestampedReplies = replies.map { video in
                TimestampedReplyMarker(
                    id: video.id,
                    timestamp: video.replyTimestamp ?? 0,
                    creatorName: video.creatorName,
                    thumbnailURL: video.thumbnailURL
                )
            }
            
            print("💬 PLAYER VM: Loaded \(timestampedReplies.count) timestamped replies")
            
        } catch {
            print("❌ PLAYER VM: Failed to load replies: \(error)")
            timestampedReplies = []
        }
    }
    
    /// Check if any reply markers should be shown at current time
    private func checkReplyMarkers(at time: TimeInterval) {
        // Find replies within 1 second of current time
        let nearbyReplies = timestampedReplies.filter { reply in
            abs(reply.timestamp - time) <= 1.0
        }
        
        if let firstReply = nearbyReplies.first, activeReplyTimestamp != firstReply.timestamp {
            activeReplyTimestamp = firstReply.timestamp
            // Could show a subtle indicator or auto-pause here
        }
    }
    
    /// Get replies at specific timestamp
    func getReplies(at timestamp: TimeInterval) -> [TimestampedReplyMarker] {
        timestampedReplies.filter { abs($0.timestamp - timestamp) <= 2.0 }
    }
    
    /// Show replies at current position
    func showRepliesAtCurrentTime() {
        activeReplyTimestamp = currentTime
        showRepliesAtTimestamp = true
        pause()
    }
    
    // MARK: - Preloading
    
    /// Preload next segment
    private func preloadNextSegment() {
        guard hasNextSegment else { return }
        
        let nextIndex = currentSegmentIndex + 1
        let nextSegment = segments[nextIndex]
        
        // Notify preloading service (implementation depends on your video player)
        print("⏳ PLAYER VM: Preloading segment \(nextIndex + 1): \(nextSegment.videoURL)")
    }
    
    // MARK: - Helpers
    
    /// Format time interval as string
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Cleanup
    
    /// Save final progress when leaving
    func cleanup() async {
        pause()
        await saveCurrentSegmentProgress()
        progressSaveTask?.cancel()
    }
}

// MARK: - Supporting Types

/// Info for resume prompt
struct ResumePromptInfo {
    let segmentIndex: Int
    let segmentTitle: String
    let timestamp: TimeInterval
    let percentComplete: Double
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var promptMessage: String {
        "Continue from \(formattedTimestamp) in \(segmentTitle)?"
    }
    
    var percentCompleteText: String {
        String(format: "%.0f%% complete", percentComplete * 100)
    }
}

/// Marker for timestamped reply on scrubber
struct TimestampedReplyMarker: Identifiable, Hashable {
    let id: String
    let timestamp: TimeInterval
    let creatorName: String
    let thumbnailURL: String?
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Position on scrubber (0.0 to 1.0) given segment duration
    func position(in duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return timestamp / duration
    }
}

// MARK: - Array Extension

extension Array {
    /// Safe subscript that returns nil for out-of-bounds
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - Preview Support

#if DEBUG
extension CollectionPlayerViewModel {
    /// Create a preview instance
    static var preview: CollectionPlayerViewModel {
        let mockCollection = VideoCollection(
            id: "preview_collection",
            title: "SwiftUI Masterclass",
            description: "Complete guide to SwiftUI",
            creatorID: "creator_123",
            creatorName: "SwiftDev",
            coverImageURL: nil,
            segmentIDs: ["seg1", "seg2", "seg3"],
            segmentCount: 3,
            totalDuration: 1800,
            status: .published,
            visibility: .publicVisible,
            allowReplies: true,
            publishedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            totalViews: 5000,
            totalHypes: 450,
            totalCools: 20,
            totalReplies: 35,
            totalShares: 12
        )
        
        let vm = CollectionPlayerViewModel(
            collection: mockCollection,
            userID: "preview_user"
        )
        
        // Mock some segments
        vm.segments = [
            CoreVideoMetadata.collectionSegment(
                collectionID: mockCollection.id,
                segmentNumber: 1,
                segmentTitle: "Introduction",
                videoURL: "https://example.com/video1.mp4",
                thumbnailURL: "https://example.com/thumb1.jpg",
                duration: 300,
                creatorID: mockCollection.creatorID,
                creatorName: mockCollection.creatorName,
                fileSize: 50_000_000
            ),
            CoreVideoMetadata.collectionSegment(
                collectionID: mockCollection.id,
                segmentNumber: 2,
                segmentTitle: "Getting Started",
                videoURL: "https://example.com/video2.mp4",
                thumbnailURL: "https://example.com/thumb2.jpg",
                duration: 600,
                creatorID: mockCollection.creatorID,
                creatorName: mockCollection.creatorName,
                fileSize: 100_000_000
            ),
            CoreVideoMetadata.collectionSegment(
                collectionID: mockCollection.id,
                segmentNumber: 3,
                segmentTitle: "Advanced Topics",
                videoURL: "https://example.com/video3.mp4",
                thumbnailURL: "https://example.com/thumb3.jpg",
                duration: 900,
                creatorID: mockCollection.creatorID,
                creatorName: mockCollection.creatorName,
                fileSize: 150_000_000
            )
        ]
        
        vm.currentSegment = vm.segments.first
        vm.currentDuration = 300
        vm.currentTime = 45
        
        return vm
    }
}
#endif
