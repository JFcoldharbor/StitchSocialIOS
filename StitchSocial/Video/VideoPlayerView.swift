//
//  VideoPlayerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Player with OptimizationConfig Integration (COMPATIBLE VERSION)
//  Dependencies: AVFoundation, CoreVideoMetadata, InteractionType, ContextualVideoOverlay
//  Features: Proper video display, ContextualVideoOverlay integration, thread navigation, edge-to-edge display
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
                        currentStitchIndex: 0, // Always 0 for parent video detection
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
            
            // TEMP: Test bubble after 3 seconds for debugging
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("🧪 TESTING: Forcing bubble to show")
                showFloatingBubble = true
            }
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
            
            // Check bubble visibility when active state changes
            updateFloatingBubbleVisibility()
        }
        .onChange(of: currentPlaybackTime) { _, newTime in
            // Check bubble visibility as time updates
            updateFloatingBubbleVisibility()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupVideo() {
        guard video.id != currentVideoID else { return }
        
        print("VIDEO PLAYER: Setting up video: \(video.title)")
        
        // Set up playback time monitoring
        playerManager.onTimeUpdate = { time in
            currentPlaybackTime = time
            print("⏰ TIME UPDATE: \(time) / \(video.duration)")
            updateFloatingBubbleVisibility()
        }
        
        // Configure optimization settings based on battery and performance
        let enableHardwareDecoding = !batteryOptimizationActive
        let enablePreloading = !memoryPressureDetected
        
        // Setup video with optimization settings
        playerManager.setupVideo(
            url: video.videoURL,
            enableHardwareDecoding: enableHardwareDecoding,
            enablePreloading: enablePreloading
        )
        
        // Update playback state
        if isActive {
            playerManager.play()
        } else {
            playerManager.pause()
        }
        
        currentVideoID = video.id
    }
    
    private func setupOptimizationMonitoring() {
        // Monitor every 5 seconds for optimization opportunities
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
        // Simple memory pressure detection
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = memoryInfo.resident_size
            let memoryThreshold: UInt64 = 500 * 1024 * 1024 // 500MB
            
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
                        
                        // Progress bar
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
        // Navigate to next video in thread
        navigateToNext()
        showFloatingBubble = false
    }
    
    private func updateFloatingBubbleVisibility() {
        let shouldShow = shouldShowFloatingBubble()
        
        // Debug logging
        print("🔄 BUBBLE UPDATE: shouldShow=\(shouldShow), currentlyShowing=\(showFloatingBubble)")
        
        if shouldShow != showFloatingBubble {
            print("🎬 BUBBLE STATE CHANGE: \(showFloatingBubble) -> \(shouldShow)")
            withAnimation(.easeInOut(duration: 0.3)) {
                showFloatingBubble = shouldShow
            }
        }
    }
    
    private func shouldShowFloatingBubble() -> Bool {
        // Debug logging to help diagnose the issue
        print("🔍 BUBBLE DEBUG:")
        print("  - totalStitchesInThread: \(totalStitchesInThread ?? 0)")
        print("  - currentThreadPosition: \(currentThreadPosition ?? 0)")
        print("  - video.duration: \(video.duration)")
        print("  - currentPlaybackTime: \(currentPlaybackTime)")
        print("  - isActive: \(isActive)")
        
        // Check if this is a parent video with replies
        guard let totalStitches = totalStitchesInThread, totalStitches > 1 else {
            print("  ❌ No replies (totalStitches: \(totalStitchesInThread ?? 0))")
            return false
        }
        
        // For now, let's be more permissive with the thread position check
        // Comment out the strict parent check to see if that's the issue
        // guard let threadPosition = currentThreadPosition, threadPosition == 1 else {
        //     print("  ❌ Not parent video (position: \(currentThreadPosition ?? 0))")
        //     return false
        // }
        
        guard video.duration > 0 else {
            print("  ❌ Invalid duration")
            return false
        }
        
        // Show bubble when video reaches 70% completion
        let triggerTime = video.duration * 0.7
        let shouldShow = currentPlaybackTime >= triggerTime
        
        print("  - triggerTime (70%): \(triggerTime)")
        print("  - shouldShow: \(shouldShow)")
        
        return shouldShow
    }
    
    private func getNextStitchTitle() -> String? {
        guard let threadVideos = threadVideos,
              currentIndex < threadVideos.count - 1 else { return nil }
        return threadVideos[currentIndex + 1].title
    }
    
    private func getNextStitchCreator() -> String? {
        guard let threadVideos = threadVideos,
              currentIndex < threadVideos.count - 1 else { return nil }
        return threadVideos[currentIndex + 1].creatorName
    }
}

// MARK: - Video Player Manager (OPTIMIZED)

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
    
    // OPTIMIZATION: Global player count to manage memory
    private static var globalActivePlayerCount = 0
    
    // Callback to update parent view's playback time
    var onTimeUpdate: ((TimeInterval) -> Void)?
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
    
    func setupVideo(url: String, enableHardwareDecoding: Bool = true, enablePreloading: Bool = true) {
        // Skip if URL hasn't changed
        if url == currentVideoURL && player != nil {
            print("VIDEO PLAYER OPTIMIZATION: Skipping duplicate setup for \(url)")
            return
        }
        
        cleanup()
        
        // Check concurrent player limits
        guard Self.globalActivePlayerCount < 10 else {
            print("🚫 VIDEO PLAYER OPTIMIZATION: Player creation blocked - at limit (\(Self.globalActivePlayerCount)/10)")
            return
        }
        
        guard let videoURL = URL(string: url) else {
            print("VIDEO MANAGER: Invalid URL: \(url)")
            return
        }
        
        print("VIDEO MANAGER: Setting up video: \(url)")
        currentVideoURL = url
        
        // Create player item with optimization settings
        let playerItem = AVPlayerItem(url: videoURL)
        
        // Apply optimization settings
        if !enableHardwareDecoding {
            // Force software decoding for low memory situations
            playerItem.videoComposition = nil
        }
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        
        if !enablePreloading {
            // Disable automatic preloading to save memory/battery
            player?.automaticallyWaitsToMinimizeStalling = false
        } else {
            // Optimize for better playback experience
            player?.automaticallyWaitsToMinimizeStalling = true
        }
        
        // Increment global count
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
        
        // Use optimization config for update frequency
        let maxFPS = 30.0
        let interval = 1.0 / Double(maxFPS)
        
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
                duration.isValid && !duration.isIndefinite ?
                    duration.seconds : 0.0
            }
            .assign(to: &$duration)
        
        player.publisher(for: \.timeControlStatus)
            .map { $0 == .playing }
            .assign(to: &$isPlaying)
    }
    
    private func setupKillObserver() {
        // Add observer for kill notifications
        killObserver = NotificationCenter.default.addObserver(
            forName: .RealkillAllVideoPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.player?.pause()
            self.isPlaying = false
            print("🛑 VIDEO PLAYER MANAGER: Killed and paused due to kill notification")
        }
        
        // Add observers for all UI interactions that should pause videos
        setupUIInteractionObservers()
    }
    
    private func setupUIInteractionObservers() {
        let notificationNames = [
            // Profile and fullscreen presentations
            "NavigateToProfile",
            "showingProfileFullscreen",
            
            // Recording interfaces
            "PresentRecording",
            "showingStitchRecording",
            "showingReplyRecording",
            
            // Thread and navigation
            "NavigateToThread",
            "NavigateToFullscreen",
            
            // Profile management
            "profileManagement",
            "profileSettings",
            
            // Any fullscreen modal
            "presentFullscreen",
            "showingFullscreenModal"
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
                print("🛑 VIDEO PLAYER MANAGER: Paused due to UI interaction: \(notificationName)")
            }
            uiInteractionObservers.append(observer)
        }
    }
    
    func forcePlay() {
        guard let player = player else {
            print("VIDEO: No player available")
            return
        }
        
        if player.timeControlStatus == .playing {
            print("VIDEO: Already playing - skipping")
            return
        }
        
        player.play()
        isPlaying = true
        print("VIDEO: Play executed - Status: \(player.timeControlStatus.rawValue)")
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
        
        player?.pause()
        player = nil
        cancellables.removeAll()
        currentVideoURL = nil
        
        // Update global player count
        if Self.globalActivePlayerCount > 0 {
            Self.globalActivePlayerCount = max(0, Self.globalActivePlayerCount - 1)
            print("VIDEO PLAYER OPTIMIZATION: Player cleaned up (\(Self.globalActivePlayerCount) remaining)")
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
        // Remove existing layer
        playerLayer?.removeFromSuperlayer()
        
        guard let player = player else {
            print("VIDEO UI: No player provided")
            return
        }
        
        // Create new player layer
        let newPlayerLayer = AVPlayerLayer(player: player)
        newPlayerLayer.videoGravity = gravity
        newPlayerLayer.frame = bounds
        
        // Add to view
        layer.addSublayer(newPlayerLayer)
        playerLayer = newPlayerLayer
        
        print("VIDEO UI: Player layer setup complete")
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
    case standalone
}
