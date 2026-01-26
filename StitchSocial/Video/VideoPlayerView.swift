//
//  VideoPlayerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Player with OptimizationConfig Integration (FIXED VERSION)
//  Dependencies: AVFoundation, CoreVideoMetadata, InteractionType, ContextualVideoOverlay
//  Features: Proper video display, ContextualVideoOverlay integration, thread navigation, edge-to-edge display
//  UPDATED: Integrated StitchFullscreenThumbnail navigator with progress bars
//

import SwiftUI
import AVFoundation
import AVKit
import Combine

// MARK: - Enhanced Video Player with Thread Navigation and Optimization
struct VideoPlayerView: View {
    
    // MARK: - Core Properties
    let video: CoreVideoMetadata
    let isActive: Bool
    let onEngagement: ((InteractionType) -> Void)?
    let overlayContext: OverlayContext  // Context for ContextualVideoOverlay
    let isConversationParticipant: Bool  // NEW: For carousel participant detection
    
    // MARK: - Thread Navigation Properties
    let threadVideos: [CoreVideoMetadata]?
    let currentIndex: Int
    let onNavigate: ((VideoNavigationDirection, Int) -> Void)?
    let navigationContext: VideoPlayerContext?
    
    // MARK: - Thread/Stitch Count Properties
    let currentThreadPosition: Int?
    let totalStitchesInThread: Int?
    
    // MARK: - Player State with Optimization Tracking
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var currentVideoID: String = ""
    
    // MARK: - Thread Navigation State
    @State private var gestureDirection: VideoNavigationDirection = .none
    
    // ⭐ NEW: Track drag offset for thumbnail navigator
    @State private var threadDragOffset: CGFloat = 0
    
    // MARK: - OPTIMIZATION State
    @State private var memoryPressureDetected: Bool = false
    @State private var batteryOptimizationActive: Bool = false
    @State private var performanceTimer: Timer?
    
    // MARK: - Floating Bubble State
    @State private var showFloatingBubble = false
    @State private var currentPlaybackTime: TimeInterval = 0
    
    // MARK: - Default Initializer (Backward Compatible)
    init(
        video: CoreVideoMetadata,
        isActive: Bool,
        onEngagement: ((InteractionType) -> Void)?,
        overlayContext: OverlayContext = .homeFeed,  // Default to homeFeed for backward compatibility
        isConversationParticipant: Bool = false  // Default to false (not in carousel conversation)
    ) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
        self.overlayContext = overlayContext
        self.isConversationParticipant = isConversationParticipant
        self.threadVideos = nil
        self.currentIndex = 0
        self.onNavigate = nil
        self.navigationContext = nil
        self.currentThreadPosition = nil
        self.totalStitchesInThread = nil
    }
    
    // MARK: - Thread Navigation Initializer
    init(
        video: CoreVideoMetadata,
        isActive: Bool,
        onEngagement: ((InteractionType) -> Void)?,
        threadVideos: [CoreVideoMetadata]?,
        currentIndex: Int,
        navigationContext: VideoPlayerContext?,
        onNavigate: ((VideoNavigationDirection, Int) -> Void)?,
        overlayContext: OverlayContext = .homeFeed,  // Default to homeFeed
        isConversationParticipant: Bool = false  // Default to false
    ) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
        self.overlayContext = overlayContext
        self.isConversationParticipant = isConversationParticipant
        self.threadVideos = threadVideos
        self.currentIndex = currentIndex
        self.onNavigate = onNavigate
        self.navigationContext = navigationContext
        self.currentThreadPosition = nil
        self.totalStitchesInThread = threadVideos?.count
    }
    
    // MARK: - Thread/Stitch Counter Initializer
    init(
        video: CoreVideoMetadata,
        isActive: Bool,
        onEngagement: ((InteractionType) -> Void)?,
        threadVideos: [CoreVideoMetadata]?,
        currentIndex: Int,
        navigationContext: VideoPlayerContext?,
        currentThreadPosition: Int,
        totalStitchesInThread: Int,
        onNavigate: ((VideoNavigationDirection, Int) -> Void)?,
        overlayContext: OverlayContext = .homeFeed,  // Default to homeFeed
        isConversationParticipant: Bool = false  // Default to false
    ) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
        self.overlayContext = overlayContext
        self.isConversationParticipant = isConversationParticipant
        self.threadVideos = threadVideos
        self.currentIndex = currentIndex
        self.onNavigate = onNavigate
        self.navigationContext = navigationContext
        self.currentThreadPosition = currentThreadPosition
        self.totalStitchesInThread = totalStitchesInThread
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player Layer - Edge to Edge with OPTIMIZED configuration
                VideoPlayerRepresentable(
                    player: playerManager.player,
                    gravity: .resizeAspectFill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea(.all)
                .gesture(
                    // Thread navigation gestures with OPTIMIZATION constraints
                    DragGesture(minimumDistance: 50)
                        .onChanged { value in
                            if isActive && shouldAllowNavigation() && !memoryPressureDetected {
                                handleThreadDrag(value: value)
                            }
                        }
                        .onEnded { value in
                            if isActive && shouldAllowNavigation() && !memoryPressureDetected {
                                handleThreadDragEnd(value: value)
                            }
                        }
                )
                
                // Use ContextualVideoOverlay with optimization awareness
                if isActive && !batteryOptimizationActive {
                    ContextualVideoOverlay(
                        video: video,
                        context: overlayContext,  // Use the provided overlay context
                        currentUserID: "current-user-id",
                        threadVideo: nil,
                        isVisible: true,
                        actualReplyCount: nil,
                        isConversationParticipant: isConversationParticipant,  // Pass participant status
                        onAction: { action in
                            handleOverlayAction(action)
                        }
                    )
                } else if batteryOptimizationActive {
                    // Minimal overlay during battery optimization
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "battery.25")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("Power Saving")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    }
                }
                
                // ⭐ NEW: Thumbnail Navigator with Facebook Stories-style progress bars
                if let threadVideos = threadVideos, threadVideos.count > 1, isActive {
                    FullscreenThumbnailNavigator(
                        videos: threadVideos,
                        currentIndex: currentIndex,
                        offsetX: threadDragOffset
                    )
                }
                
                // Thread Position Indicator (overlay only if enabled)
                if shouldShowPositionIndicator() && isActive {
                    threadPositionIndicator
                }
                
                // Memory pressure warning overlay
                if memoryPressureDetected {
                    memoryPressureOverlay
                }
                
                // Floating bubble notification for thread navigation
                if showFloatingBubble && isActive {
                    FloatingBubbleNotification.parentVideoWithReplies(
                        videoDuration: video.duration,
                        currentPosition: currentPlaybackTime,
                        replyCount: (totalStitchesInThread ?? 1) - 1,
                        currentStitchIndex: 0,
                        onViewReplies: handleStitchReveal,
                        onDismiss: {
                            showFloatingBubble = false
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
        }
        .onAppear {
            setupVideo()
            setupOptimizationMonitoring()
        }
        .onDisappear {
            cleanupOptimizations()
        }
        .onChange(of: video.id) { _, newVideoID in
            if newVideoID != currentVideoID {
                setupVideo()
                currentVideoID = newVideoID
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                playerManager.play()
            } else {
                playerManager.pause()
            }
            updateFloatingBubbleVisibility()
        }
        .onChange(of: currentPlaybackTime) { _, newTime in
            updateFloatingBubbleVisibility()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupVideo() {
        guard video.id != currentVideoID else { return }
        
        print("VIDEO PLAYER: Setting up video: \(video.title)")
        
        playerManager.onTimeUpdate = { time in
            currentPlaybackTime = time
            updateFloatingBubbleVisibility()
        }
        
        let enableHardwareDecoding = !batteryOptimizationActive
        let enablePreloading = !memoryPressureDetected
        playerManager.setupVideo(
            url: video.videoURL,
            enableHardwareDecoding: enableHardwareDecoding,
            enablePreloading: enablePreloading
        )
    }
    
    private func setupOptimizationMonitoring() {
        // Note: Memory warnings are monitored in VideoPlayerManager
        // SwiftUI Views (structs) cannot use @objc and #selector
    }
    
    private func cleanupOptimizations() {
        playerManager.cleanup()
    }
    
    private func shouldAllowNavigation() -> Bool {
        return (threadVideos?.count ?? 0) > 1
    }
    
    private func shouldShowPositionIndicator() -> Bool {
        return (threadVideos?.count ?? 0) > 1 && currentThreadPosition == nil
    }
    
    private func handleThreadDrag(value: DragGesture.Value) {
        // ⭐ NEW: Track drag offset for thumbnail navigator
        threadDragOffset = value.translation.width
        
        let translation = value.translation
        let isDraggingHorizontally = abs(translation.width) > abs(translation.height)
        
        if isDraggingHorizontally {
            gestureDirection = .horizontal
        }
    }
    
    private func handleThreadDragEnd(value: DragGesture.Value) {
        // ⭐ NEW: Reset drag offset
        threadDragOffset = 0
        
        let translation = value.translation
        let threshold: CGFloat = 100
        let isDraggingRight = translation.width > threshold
        let isDraggingLeft = translation.width < -threshold
        
        if isDraggingRight && currentIndex > 0 {
            onNavigate?(.previous, currentIndex - 1)
            gestureDirection = .horizontal
        } else if isDraggingLeft && currentIndex < (threadVideos?.count ?? 1) - 1 {
            onNavigate?(.next, currentIndex + 1)
            gestureDirection = .horizontal
        }
        
        gestureDirection = .none
    }
    
    private func handleStitchReveal() {
        print("USER ACTION: Tapped view replies")
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        print("OVERLAY ACTION: \(action)")
    }
    
    private var threadPositionIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let position = currentThreadPosition, let total = totalStitchesInThread {
                Text("\(position + 1) of \(total)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))
            } else if let total = totalStitchesInThread {
                Text("1 of \(total)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            HStack(spacing: 2) {
                Image(systemName: "film.fill")
                    .font(.caption2)
                    .foregroundColor(.cyan)
                Text("Thread")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
        .padding()
    }
    
    private var memoryPressureOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory Pressure")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Some features are disabled")
                        .font(.caption2)
                        .opacity(0.8)
                }
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            .padding()
        }
    }
    
    private func updateFloatingBubbleVisibility() {
        let isShowingBubbleByTime = (currentPlaybackTime / max(video.duration, 1.0)) < 0.1
        showFloatingBubble = isShowingBubbleByTime && (totalStitchesInThread ?? 0) > 1 && currentIndex == 0
    }
}

// MARK: - Video Player Manager

class VideoPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    
    var onTimeUpdate: ((TimeInterval) -> Void)?
    
    var player: AVPlayer?
    private var timeObserver: Any?
    private var killObserver: NSObjectProtocol?
    private var uiInteractionObservers: [NSObjectProtocol] = []
    private var currentVideoURL: String?
    private var cancellables = Set<AnyCancellable>()
    
    private static var globalActivePlayerCount = 0
    
    override init() {
        super.init()
    }
    
    deinit {
        cleanup()
    }
    
    func setupVideo(url: String, enableHardwareDecoding: Bool = true, enablePreloading: Bool = true) {
        guard let videoURL = URL(string: url) else {
            print("VIDEO MANAGER: Invalid URL")
            return
        }
        
        print("VIDEO MANAGER: Setting up video")
        currentVideoURL = url
        
        let playerItem = AVPlayerItem(url: videoURL)
        
        if !enableHardwareDecoding {
            playerItem.videoComposition = nil
        }
        
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = enablePreloading
        
        Self.globalActivePlayerCount += 1
        print("VIDEO PLAYER OPTIMIZATION: Player created (\(Self.globalActivePlayerCount) active)")
        
        setupTimeObserver()
        setupLooping()
        setupPublishers()
        setupKillObserver()
    }
    
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        print("VIDEO MANAGER: Playing")
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
        print("VIDEO MANAGER: Paused")
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        let interval = 1.0 / 30.0
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
            self?.onTimeUpdate?(time.seconds)
        }
    }
    
    private func setupLooping() {
        guard let player = player else { return }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: CMTime.zero)
            player?.play()
        }
    }
    
    private func setupPublishers() {
        guard let player = player else { return }
        
        player.currentItem?.publisher(for: \.duration)
            .map { duration in
                duration.isValid && !duration.isIndefinite ? duration.seconds : 0.0
            }
            .assign(to: &$duration)
        
        player.publisher(for: \.timeControlStatus)
            .map { $0 == .playing }
            .assign(to: &$isPlaying)
    }
    
    private func setupKillObserver() {
        killObserver = NotificationCenter.default.addObserver(
            forName: .killAllVideoPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.player?.pause()
            self.isPlaying = false
            print("🛑 VIDEO PLAYER MANAGER: Killed due to notification")
        }
        
        setupUIInteractionObservers()
    }
    
    // ✅ FIXED: Removed profile notification listeners
    private func setupUIInteractionObservers() {
        let notificationNames = [
            // Recording interfaces only
            "PresentRecording",
            "showingStitchRecording",
            "showingReplyRecording",
            
            // Thread and navigation (specific contexts)
            "NavigateToThread",
            "NavigateToFullscreen"
        ]
        
        for notificationName in notificationNames {
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(notificationName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.player?.pause()
                self.isPlaying = false
                print("🛑 VIDEO PLAYER MANAGER: Paused due to: \(notificationName)")
            }
            uiInteractionObservers.append(observer)
        }
        
        print("✅ VIDEO PLAYER MANAGER: Setup \(notificationNames.count) context-aware observers")
    }
    
    func forcePlay() {
        guard let player = player else {
            print("VIDEO: No player available")
            return
        }
        
        if player.timeControlStatus == .playing {
            print("VIDEO: Already playing")
            return
        }
        
        player.play()
        isPlaying = true
        print("VIDEO: Force play executed")
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let observer = killObserver {
            NotificationCenter.default.removeObserver(observer)
            killObserver = nil
        }
        
        for observer in uiInteractionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        uiInteractionObservers.removeAll()
        
        player?.pause()
        player = nil
        cancellables.removeAll()
        currentVideoURL = nil
        
        if Self.globalActivePlayerCount > 0 {
            Self.globalActivePlayerCount = max(0, Self.globalActivePlayerCount - 1)
            print("VIDEO PLAYER OPTIMIZATION: Cleaned up (\(Self.globalActivePlayerCount) remaining)")
        }
    }
}

// MARK: - Video Player UIKit Representable

struct VideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer?
    let gravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> VideoPlayerUIView {
        let view = VideoPlayerUIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: VideoPlayerUIView, context: Context) {
        uiView.setupPlayer(player, gravity: gravity)
    }
}

// MARK: - Video Player UI View

class VideoPlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    func setupPlayer(_ player: AVPlayer?, gravity: AVLayerVideoGravity) {
        playerLayer?.removeFromSuperlayer()
        
        guard let player = player else {
            return
        }
        
        let newPlayerLayer = AVPlayerLayer(player: player)
        newPlayerLayer.videoGravity = gravity
        newPlayerLayer.frame = bounds
        
        layer.addSublayer(newPlayerLayer)
        playerLayer = newPlayerLayer
    }
}

// MARK: - Supporting Enums

enum VideoNavigationDirection {
    case none
    case horizontal
    case vertical
    case previous
    case next
}

enum VideoPlayerContext {
    case homeFeed
    case discovery
    case profileGrid
    case threadView
    case fullscreen
    case standalone
}
