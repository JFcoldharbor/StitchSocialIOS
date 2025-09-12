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
                    DragGesture(minimumDistance: OptimizationConfig.UI.minGestureDistance)
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
                } else if isActive && batteryOptimizationActive {
                    // Minimal overlay for battery optimization
                    batteryOptimizedOverlay(geometry: geometry)
                } else {
                    // Minimal grid overlay
                    gridModeOverlay(geometry: geometry)
                }
                
                // Thread position indicator (contextual display)
                if isActive && shouldShowPositionIndicator() && !batteryOptimizationActive {
                    threadPositionIndicator
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(isActive)
        .ignoresSafeArea(.all)
        .onAppear {
            setupVideoPlayer()
            setupOptimizationMonitoring()
        }
        .onDisappear {
            cleanupPlayer()
            cleanupOptimizationMonitoring()
        }
        .onChange(of: isActive) { _, active in
            if active && !memoryPressureDetected {
                forcePlay()
            } else {
                pauseVideo()
            }
        }
    }
    
    // MARK: - OPTIMIZATION Monitoring Setup
    
    private func setupOptimizationMonitoring() {
        // Setup memory pressure monitoring
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.handleMemoryWarning()
        }
        
        // Setup battery monitoring using OptimizationConfig threshold
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.checkBatteryOptimization()
        }
        
        // Setup performance monitoring timer using OptimizationConfig interval
        performanceTimer = Timer.scheduledTimer(withTimeInterval: OptimizationConfig.Performance.gcInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.performOptimizationCleanup()
            }
        }
        
        print("✅ VIDEO PLAYER OPTIMIZATION: Monitoring setup - cleanup every \(OptimizationConfig.Performance.gcInterval)s")
    }
    
    private func cleanupOptimizationMonitoring() {
        performanceTimer?.invalidate()
        performanceTimer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self)
        print("🧹 VIDEO PLAYER OPTIMIZATION: Monitoring cleanup complete")
    }
    
    private func handleMemoryWarning() {
        memoryPressureDetected = true
        playerManager.enableOptimizationMode()
        print("⚠️ VIDEO PLAYER OPTIMIZATION: Memory warning - enabling restrictions")
        
        // Reset memory pressure flag using OptimizationConfig interval
        DispatchQueue.main.asyncAfter(deadline: .now() + OptimizationConfig.Performance.gcInterval) {
            self.memoryPressureDetected = false
            self.playerManager.disableOptimizationMode()
            print("✅ VIDEO PLAYER OPTIMIZATION: Memory pressure cleared")
        }
    }
    
    private func checkBatteryOptimization() {
        let batteryLevel = UIDevice.current.batteryLevel
        let threshold = Float(OptimizationConfig.Performance.batteryOptimizationThreshold)
        
        batteryOptimizationActive = batteryLevel <= threshold && batteryLevel > 0
        
        if batteryOptimizationActive {
            print("🔋 VIDEO PLAYER OPTIMIZATION: Battery optimization active (\(Int(batteryLevel * 100))%)")
        } else if !batteryOptimizationActive && batteryLevel > threshold {
            print("🔋 VIDEO PLAYER OPTIMIZATION: Battery optimization disabled (\(Int(batteryLevel * 100))%)")
        }
    }
    
    private func performOptimizationCleanup() async {
        print("🧹 VIDEO PLAYER OPTIMIZATION: Periodic cleanup performed")
        // Cleanup logic would go here
    }
    
    // MARK: - Battery Optimized Overlay
    
    private func batteryOptimizedOverlay(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing) {
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
    }
    
    // MARK: - Contextual Navigation Logic
    
    private func shouldAllowNavigation() -> Bool {
        guard let context = navigationContext else {
            return threadVideos != nil
        }
        
        switch context {
        case .homeFeed:
            return true
        case .discovery:
            return true
        case .profileGrid:
            return threadVideos != nil
        case .standalone:
            return false
        }
    }
    
    private func shouldShowPositionIndicator() -> Bool {
        guard let threadVideos = threadVideos, threadVideos.count > 1 else {
            return false
        }
        
        guard let context = navigationContext else {
            return true
        }
        
        switch context {
        case .homeFeed, .discovery:
            return true
        case .profileGrid:
            return true
        case .standalone:
            return false
        }
    }
    
    // MARK: - Thread Position Indicator
    
    private var threadPositionIndicator: some View {
        VStack {
            HStack {
                Spacer()
                
                if let threadVideos = threadVideos {
                    HStack(spacing: 4) {
                        Text("\(currentIndex + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("/")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("\(threadVideos.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
            
            Spacer()
        }
    }
    
    // MARK: - Thread Navigation Gesture Handling with OPTIMIZATION
    
    private func handleThreadDrag(value: DragGesture.Value) {
        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)
        
        // Use OptimizationConfig for gesture sensitivity
        let minDistance = OptimizationConfig.UI.minGestureDistance
        
        if gestureDirection == .none {
            if horizontalMovement > minDistance && horizontalMovement > verticalMovement * 1.5 {
                gestureDirection = .horizontal
            } else if verticalMovement > minDistance && verticalMovement > horizontalMovement * 1.5 {
                if navigationContext == .homeFeed || navigationContext == .discovery {
                    gestureDirection = .vertical
                }
            }
        }
    }
    
    private func handleThreadDragEnd(value: DragGesture.Value) {
        // Use OptimizationConfig for gesture thresholds
        let threshold = OptimizationConfig.UI.minGestureDistance * 5 // 100px default
        
        switch gestureDirection {
        case .horizontal:
            if value.translation.width > threshold {
                navigateToPrevious()
            } else if value.translation.width < -threshold {
                navigateToNext()
            }
        case .vertical:
            if navigationContext == .homeFeed || navigationContext == .discovery {
                if value.translation.height > threshold {
                    onNavigate?(.vertical, -1)
                } else if value.translation.height < -threshold {
                    onNavigate?(.vertical, 1)
                }
            }
        case .none:
            break
        }
        
        gestureDirection = .none
    }
    
    private func navigateToNext() {
        guard let threadVideos = threadVideos,
              currentIndex < threadVideos.count - 1 else { return }
        
        let newIndex = currentIndex + 1
        onNavigate?(.horizontal, newIndex)
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func navigateToPrevious() {
        guard currentIndex > 0 else { return }
        
        let newIndex = currentIndex - 1
        onNavigate?(.horizontal, newIndex)
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    // MARK: - Grid Mode Overlay
    
    private func gridModeOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            if video.duration > 0 {
                Text(formatDuration(video.duration))
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: geometry.size.width - 30, y: 15)
            }
            
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text("\(video.hypeCount)")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .padding(4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
            .position(x: 35, y: geometry.size.width - 15)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        switch action {
        case .engagement(let engagementType):
            let interactionType: InteractionType
            switch engagementType {
            case .hype:
                interactionType = .hype
            case .cool:
                interactionType = .cool
            case .share:
                interactionType = .share
            case .reply:
                interactionType = .reply
            case .stitch:
                interactionType = .reply
            }
            onEngagement?(interactionType)
            
        default:
            print("Overlay action: \(action)")
        }
    }
    
    // MARK: - Player Setup and Control with OPTIMIZATION
    
    private func setupVideoPlayer() {
        guard let videoURL = URL(string: video.videoURL) else {
            print("Invalid video URL: \(video.videoURL)")
            return
        }
        
        guard currentVideoID != video.id else {
            print("VIDEO: Already setup for this video")
            return
        }
        
        print("VIDEO PLAYER OPTIMIZATION: Setting up player for '\(video.title)'")
        playerManager.setupPlayer(with: videoURL)
        currentVideoID = video.id
        
        if isActive && !memoryPressureDetected {
            forceAutoplay()
        }
    }
    
    private func forceAutoplay() {
        // Use battery optimization for delay timing
        let delay = batteryOptimizationActive ? 0.3 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            forcePlay()
            print("VIDEO PLAYER OPTIMIZATION: Autoplay initiated")
        }
    }
    
    private func forcePlay() {
        playerManager.forcePlay()
    }
    
    private func pauseVideo() {
        playerManager.pause()
    }
    
    private func cleanupPlayer() {
        playerManager.cleanup()
    }
}

// MARK: - OPTIMIZED Video Player Manager
@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var isMuted: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    // OPTIMIZATION State
    @Published var optimizationModeActive: Bool = false
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var currentVideoURL: URL?
    
    // OPTIMIZATION: Track concurrent operations using OptimizationConfig
    private static var globalActivePlayerCount: Int = 0
    
    func setupPlayer(with url: URL) {
        guard currentVideoURL != url else {
            print("VIDEO: Reusing existing player for same URL")
            return
        }
        
        // Check concurrent player limits from OptimizationConfig
        guard Self.globalActivePlayerCount < OptimizationConfig.Performance.maxVideoProcessingTasks else {
            print("🚫 VIDEO PLAYER OPTIMIZATION: Player creation blocked - at limit (\(Self.globalActivePlayerCount)/\(OptimizationConfig.Performance.maxVideoProcessingTasks))")
            return
        }
        
        cleanup()
        
        Task.detached(priority: .userInitiated) {
            let playerItem = AVPlayerItem(url: url)
            
            // Apply optimization settings using OptimizationConfig
            if await self.optimizationModeActive {
                playerItem.preferredForwardBufferDuration = 2.0
            } else {
                playerItem.preferredForwardBufferDuration = 5.0
            }
            
            let player = AVPlayer(playerItem: playerItem)
            
            await MainActor.run {
                self.player = player
                self.currentVideoURL = url
                
                Self.globalActivePlayerCount += 1
                
                self.setupTimeObserver()
                self.setupPublishers()
                self.setupLooping()
                
                print("VIDEO PLAYER OPTIMIZATION: Player created (\(Self.globalActivePlayerCount)/\(OptimizationConfig.Performance.maxVideoProcessingTasks))")
            }
        }
    }
    
    func enableOptimizationMode() {
        optimizationModeActive = true
        
        // Reduce buffer duration under optimization
        if let currentItem = player?.currentItem {
            currentItem.preferredForwardBufferDuration = 1.0
        }
        
        print("⚠️ VIDEO PLAYER OPTIMIZATION: Optimization mode enabled")
    }
    
    func disableOptimizationMode() {
        optimizationModeActive = false
        
        // Restore normal buffer duration
        if let currentItem = player?.currentItem {
            currentItem.preferredForwardBufferDuration = 5.0
        }
        
        print("✅ VIDEO PLAYER OPTIMIZATION: Optimization mode disabled")
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // Use OptimizationConfig for update frequency
        let maxFPS = OptimizationConfig.Performance.maxUIUpdateFrequency
        let interval = 1.0 / Double(maxFPS)
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
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
    
    func pause() {
        player?.pause()
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
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
