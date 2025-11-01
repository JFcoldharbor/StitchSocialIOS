//
//  VideoPlayerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Player with OptimizationConfig Integration (FIXED VERSION)
//  Dependencies: AVFoundation, CoreVideoMetadata, InteractionType, ContextualVideoOverlay
//  Features: Proper video display, ContextualVideoOverlay integration, thread navigation, edge-to-edge display
//  FIXED: Removed profile notification listeners that caused thumbnail kill storm
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
    
    // MARK: - OPTIMIZATION State
    @State private var memoryPressureDetected: Bool = false
    @State private var batteryOptimizationActive: Bool = false
    @State private var performanceTimer: Timer?
    
    // MARK: - Floating Bubble State
    @State private var showFloatingBubble = false
    @State private var currentPlaybackTime: TimeInterval = 0
    
    // MARK: - Default Initializer (Backward Compatible)
    init(video: CoreVideoMetadata, isActive: Bool, onEngagement: ((InteractionType) -> Void)?) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
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
        onNavigate: ((VideoNavigationDirection, Int) -> Void)?
    ) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
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
        onNavigate: ((VideoNavigationDirection, Int) -> Void)?
    ) {
        self.video = video
        self.isActive = isActive
        self.onEngagement = onEngagement
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
                        context: .homeFeed,
                        currentUserID: "current-user-id",
                        threadVideo: nil,
                        isVisible: true,
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
        
        if isActive {
            playerManager.play()
        } else {
            playerManager.pause()
        }
        
        currentVideoID = video.id
    }
    
    private func setupOptimizationMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            checkMemoryPressure()
            checkBatteryStatus()
        }
    }
    
    private func cleanupOptimizations() {
        performanceTimer?.invalidate()
        performanceTimer = nil
        playerManager.cleanup()
    }
    
    private func checkMemoryPressure() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = memoryInfo.resident_size
            let memoryThreshold: UInt64 = 500 * 1024 * 1024
            
            if memoryUsage > memoryThreshold && !memoryPressureDetected {
                print("📱 OPTIMIZATION: Memory pressure detected - \(memoryUsage / 1024 / 1024)MB")
                memoryPressureDetected = true
            } else if memoryUsage < memoryThreshold && memoryPressureDetected {
                memoryPressureDetected = false
            }
        }
    }
    
    private func checkBatteryStatus() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        
        let shouldOptimizeForBattery = (batteryLevel < 0.2 && batteryState != .charging)
        
        if shouldOptimizeForBattery != batteryOptimizationActive {
            batteryOptimizationActive = shouldOptimizeForBattery
            print("🔋 OPTIMIZATION: Battery optimization \(batteryOptimizationActive ? "enabled" : "disabled")")
        }
    }
    
    private func shouldAllowNavigation() -> Bool {
        return !memoryPressureDetected && !batteryOptimizationActive
    }
    
    private func shouldShowPositionIndicator() -> Bool {
        guard let threadVideos = threadVideos, let currentThreadPosition = currentThreadPosition else {
            return false
        }
        return threadVideos.count > 1
    }
    
    private var threadPositionIndicator: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                if let current = currentThreadPosition,
                   let total = totalStitchesInThread {
                    
                    VStack(spacing: 4) {
                        Text("\(current)/\(total)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(current) / CGFloat(total))
                            }
                        }
                        .frame(height: 2)
                        .cornerRadius(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 80)
                }
                Spacer()
            }
            .padding(.bottom, 100)
        }
    }
    
    private var memoryPressureOverlay: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Memory Warning")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(.top, 50)
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        switch action {
        case .profile:
            print("VIDEO PLAYER: Profile action")
        case .more:
            print("VIDEO PLAYER: More action")
        default:
            print("VIDEO PLAYER: Other action")
        }
    }
    
    private func handleThreadDrag(value: DragGesture.Value) {
        let horizontalThreshold: CGFloat = 100
        let verticalThreshold: CGFloat = 50
        
        if abs(value.translation.width) > abs(value.translation.height) {
            gestureDirection = .horizontal
        } else if abs(value.translation.height) > verticalThreshold {
            gestureDirection = .vertical
        }
    }
    
    private func handleThreadDragEnd(value: DragGesture.Value) {
        let threshold: CGFloat = 100
        
        switch gestureDirection {
        case .horizontal:
            if value.translation.width > threshold {
                onNavigate?(.horizontal, -1)
            } else if value.translation.width < -threshold {
                onNavigate?(.horizontal, 1)
            }
        case .vertical:
            if value.translation.height > threshold {
                onNavigate?(.vertical, -1)
            } else if value.translation.height < -threshold {
                onNavigate?(.vertical, 1)
            }
        case .none:
            break
        }
        
        gestureDirection = .none
    }
    
    private func hasNextStitchInThread() -> Bool {
        guard let threadVideos = threadVideos else { return false }
        return currentIndex < threadVideos.count - 1
    }
    
    private func navigateToNext() {
        guard hasNextStitchInThread() else { return }
        
        let newIndex = currentIndex + 1
        onNavigate?(.horizontal, newIndex)
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func handleStitchReveal() {
        navigateToNext()
        showFloatingBubble = false
    }
    
    private func updateFloatingBubbleVisibility() {
        let shouldShow = shouldShowFloatingBubble()
        
        if shouldShow != showFloatingBubble {
            withAnimation(.easeInOut(duration: 0.3)) {
                showFloatingBubble = shouldShow
            }
        }
    }
    
    private func shouldShowFloatingBubble() -> Bool {
        guard let totalStitches = totalStitchesInThread, totalStitches > 1 else {
            return false
        }
        
        guard video.duration > 0 else {
            return false
        }
        
        let triggerTime = video.duration * 0.7
        let shouldShow = currentPlaybackTime >= triggerTime
        
        return shouldShow
    }
}

// MARK: - Video Player Manager (OPTIMIZED & FIXED)

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var killObserver: NSObjectProtocol?
    private var uiInteractionObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var currentVideoURL: String?
    
    private static var globalActivePlayerCount = 0
    
    var onTimeUpdate: ((TimeInterval) -> Void)?
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
    
    func setupVideo(url: String, enableHardwareDecoding: Bool = true, enablePreloading: Bool = true) {
        if url == currentVideoURL && player != nil {
            print("VIDEO PLAYER OPTIMIZATION: Skipping duplicate setup")
            return
        }
        
        cleanup()
        
        guard Self.globalActivePlayerCount < 10 else {
            print("🚫 VIDEO PLAYER OPTIMIZATION: Player creation blocked - at limit")
            return
        }
        
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
            forName: .RealkillAllVideoPlayers,
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
}

enum VideoPlayerContext {
    case homeFeed
    case discovery
    case profileGrid
    case threadView
    case fullscreen
    case standalone
}
