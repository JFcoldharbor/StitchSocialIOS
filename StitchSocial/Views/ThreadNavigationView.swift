//
//  ThreadNavigationView.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Thread Navigation Container
//  Dependencies: ThreadNavigationCoordinator (Layer 6), VideoPlayerView, BoundedVideoContainer
//  Features: Context-aware navigation, gesture handling, smooth animations
//  Purpose: Shared navigation UI for HomeFeedView and ProfileView
//

import SwiftUI
import AVFoundation
import ObjectiveC

// MARK: - ThreadNavigationView

struct ThreadNavigationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var coordinator: ThreadNavigationCoordinator
    let context: ThreadNavigationContext
    let onVideoLoop: ((String) -> Void)?
    let onEngagement: ((InteractionType, CoreVideoMetadata) -> Void)?
    
    // MARK: - Initial Data
    
    private let initialThreads: [ThreadData]
    
    // MARK: - State
    
    @State private var containerSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init(
        threads: [ThreadData],
        context: ThreadNavigationContext,
        videoService: VideoService,
        onVideoLoop: ((String) -> Void)? = nil,
        onEngagement: ((InteractionType, CoreVideoMetadata) -> Void)? = nil
    ) {
        self.initialThreads = threads
        self.context = context
        self.onVideoLoop = onVideoLoop
        self.onEngagement = onEngagement
        self._coordinator = StateObject(wrappedValue: ThreadNavigationCoordinator(
            videoService: videoService,
            context: context
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Context-specific background
                contextBackground
                
                // Main content container
                threadNavigationContainer(geometry: geometry)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { coordinator.handleDragChanged($0) }
                            .onEnded { coordinator.handleDragEnded($0) }
                    )
                
                // Context-specific overlays
                contextOverlays
            }
            .onAppear {
                containerSize = geometry.size
                coordinator.setThreads(initialThreads)
            }
            .onChange(of: geometry.size) { newSize in
                containerSize = newSize
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    // MARK: - Thread Navigation Container
    
    private func threadNavigationContainer(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(coordinator.threads.enumerated()), id: \.offset) { threadIndex, thread in
                threadContainer(
                    thread: thread,
                    threadIndex: threadIndex,
                    geometry: geometry
                )
            }
        }
        .offset(
            x: coordinator.navigationState.horizontalOffset +
               (coordinator.navigationState.isAnimating ? 0 : coordinator.navigationState.dragOffset.width),
            y: coordinator.navigationState.verticalOffset +
               (coordinator.navigationState.isAnimating ? 0 : coordinator.navigationState.dragOffset.height)
        )
        .animation(
            coordinator.navigationState.isAnimating ? coordinator.animationSpring : nil,
            value: coordinator.navigationState.verticalOffset
        )
        .animation(
            coordinator.navigationState.isAnimating ? coordinator.animationSpring : nil,
            value: coordinator.navigationState.horizontalOffset
        )
    }
    
    // MARK: - Individual Thread Container
    
    private func threadContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            // Parent video container
            parentVideoContainer(
                thread: thread,
                threadIndex: threadIndex,
                geometry: geometry
            )
            
            // Child video containers (horizontal layout)
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                childVideoContainer(
                    childVideo: childVideo,
                    thread: thread,
                    threadIndex: threadIndex,
                    childIndex: childIndex,
                    geometry: geometry
                )
            }
        }
        .id("\(thread.id)-\(thread.childVideos.count)")
    }
    
    // MARK: - Video Container Components
    
    private func parentVideoContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        videoContainer(
            video: thread.parentVideo,
            thread: thread,
            isActive: isVideoActive(threadIndex: threadIndex, stitchIndex: 0),
            containerID: "\(thread.id)-parent"
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .position(
            x: geometry.size.width / 2,
            y: geometry.size.height / 2 + verticalPosition(for: threadIndex, geometry: geometry)
        )
    }
    
    private func childVideoContainer(
        childVideo: CoreVideoMetadata,
        thread: ThreadData,
        threadIndex: Int,
        childIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        videoContainer(
            video: childVideo,
            thread: thread,
            isActive: isVideoActive(threadIndex: threadIndex, stitchIndex: childIndex + 1),
            containerID: "\(thread.id)-child-\(childIndex)"
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .position(
            x: geometry.size.width / 2 + horizontalPosition(for: childIndex + 1, geometry: geometry),
            y: geometry.size.height / 2 + verticalPosition(for: threadIndex, geometry: geometry)
        )
    }
    
    // MARK: - Video Container Factory
    
    private func videoContainer(
        video: CoreVideoMetadata,
        thread: ThreadData,
        isActive: Bool,
        containerID: String
    ) -> some View {
        Group {
            if context.useBoundedContainers {
                BoundedVideoContainer(
                    video: video,
                    thread: thread,
                    isActive: isActive,
                    containerID: containerID,
                    onVideoLoop: { videoID in
                        onVideoLoop?(videoID)
                    }
                )
            } else {
                VideoPlayerView(
                    video: video,
                    isActive: isActive,
                    onEngagement: { interactionType in
                        onEngagement?(interactionType, video)
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isVideoActive(threadIndex: Int, stitchIndex: Int) -> Bool {
        return threadIndex == coordinator.navigationState.currentThreadIndex &&
               stitchIndex == coordinator.navigationState.currentStitchIndex &&
               !coordinator.navigationState.isAnimating
    }
    
    private func verticalPosition(for threadIndex: Int, geometry: GeometryProxy) -> CGFloat {
        let offset = CGFloat(threadIndex - coordinator.navigationState.currentThreadIndex)
        return offset * geometry.size.height
    }
    
    private func horizontalPosition(for stitchIndex: Int, geometry: GeometryProxy) -> CGFloat {
        let offset = CGFloat(stitchIndex - coordinator.navigationState.currentStitchIndex)
        return offset * geometry.size.width
    }
    
    // MARK: - Background Configurations
    
    private var contextBackground: some View {
        Group {
            switch context {
            case .homeFeed:
                Color.black.ignoresSafeArea()
                
            case .discovery:
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
            case .profile:
                Color.black.opacity(0.95).ignoresSafeArea()
                
            case .fullscreen:
                Color.black.ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Context-Specific Overlays
    
    private var contextOverlays: some View {
        VStack {
            switch context {
            case .homeFeed:
                // Home feed specific overlays
                Spacer()
                
            case .discovery:
                // Discovery specific overlays
                Spacer()
                
            case .profile:
                // Profile specific overlays
                Spacer()
                
            case .fullscreen:
                // Fullscreen specific overlays
                Spacer()
            }
        }
    }
}

// MARK: - ThreadNavigationView Public Interface

extension ThreadNavigationView {
    
    /// Get the currently active video
    func getCurrentVideo() -> CoreVideoMetadata? {
        return coordinator.getCurrentVideo()
    }
    
    func getCurrentThread() -> ThreadData? {
        return coordinator.getCurrentThread()
    }
    
    // Navigation control methods
    func moveToThread(_ index: Int) {
        coordinator.smoothMoveToThread(index)
    }
    
    func moveToStitch(_ index: Int) {
        coordinator.smoothMoveToStitch(index)
    }
}

// MARK: - ✅ REAL BoundedVideoContainer Implementation
// REPLACES THE STUB - Full video player functionality with kill notifications

struct BoundedVideoContainer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    // Optional view tracking dependencies
    var videoService: VideoService? = nil
    var currentUserID: String? = nil
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // Create video player directly without coordinator conflicts
        let playerManager = BoundedVideoPlayerManager(
            containerView: containerView,
            onVideoLoop: onVideoLoop
        )
        
        // Store manager in the view for updates
        containerView.tag = 999 // Special tag to identify our managed view
        objc_setAssociatedObject(containerView, "playerManager", playerManager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // Setup initial video
        playerManager.setupPlayer(for: video, isActive: isActive)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Get the stored player manager
        guard let playerManager = objc_getAssociatedObject(uiView, "playerManager") as? BoundedVideoPlayerManager else {
            return
        }
        
        // Update video if needed
        playerManager.setupPlayer(for: video, isActive: isActive)
    }
}

// MARK: - ✅ Direct Player Manager (No Coordinator Conflicts)

class BoundedVideoPlayerManager: NSObject {
    private weak var containerView: UIView?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentVideoID: String?
    private var isActive: Bool = false
    private var notificationObserver: NSObjectProtocol?
    private var killObserver: NSObjectProtocol? // ✅ CRITICAL: Kill notification observer
    private let onVideoLoop: (String) -> Void
    
    // View tracking properties
    private var viewTimer: Timer?
    private var viewStartTime: Date?
    private var hasRegisteredView: Bool = false
    
    // Constants
    private let minimumViewDuration: TimeInterval = 0.5
    
    init(containerView: UIView, onVideoLoop: @escaping (String) -> Void) {
        self.containerView = containerView
        self.onVideoLoop = onVideoLoop
        super.init()
        setupKillObserver() // ✅ SETUP KILL NOTIFICATIONS
        setupBackgroundObservers()
    }
    
    // MARK: - ✅ KILL NOTIFICATION SETUP
    
    private func setupKillObserver() {
        // Use existing kill notification name (don't redeclare)
        killObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("killAllVideoPlayers"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("KILL NOTIFICATION: BoundedVideoContainer received kill signal")
            self?.killPlayer()
        }
        print("KILL NOTIFICATION: BoundedVideoContainer observer setup complete")
    }
    
    private func killPlayer() {
        print("KILL NOTIFICATION: Killing BoundedVideoContainer player for video \(currentVideoID ?? "unknown")")
        
        // COMPLETE DESTRUCTION - Not just pause
        
        // 1. Stop and destroy player
        player?.pause()
        player?.replaceCurrentItem(with: nil) // Remove video completely
        
        // 2. Remove notification observers
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        // 3. Remove player layer from view hierarchy
        playerLayer?.removeFromSuperlayer()
        
        // 4. Destroy player and layer objects
        player = nil
        playerLayer = nil
        
        // 5. Clear all state
        currentVideoID = nil
        isActive = false
        
        // 6. Stop any view tracking
        stopViewTracking()
        resetViewTracking()
        
        print("KILL NOTIFICATION: BoundedVideoContainer player COMPLETELY DESTROYED")
    }
    
    // MARK: - Background & Foreground Observers
    
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        player?.pause()
        print("📱 BOUNDED VIDEO: Paused due to background")
    }
    
    @objc private func appWillEnterForeground() {
        if isActive {
            player?.play()
            print("📱 BOUNDED VIDEO: Resumed due to foreground")
        }
    }
    
    // MARK: - Player Setup
    
    func setupPlayer(for video: CoreVideoMetadata, isActive: Bool) {
        guard let containerView = containerView else {
            print("BOUNDED CONTAINER: No container view available")
            return
        }
        
        self.isActive = isActive
        
        // Always recreate player if it doesn't exist (killed) or different video
        if player == nil || currentVideoID != video.id {
            print("BOUNDED CONTAINER: Creating new player for video \(video.id)")
            
            // Clean up any existing player first
            cleanupCurrentPlayer()
            resetViewTracking()
            
            // Setup new player
            guard let url = URL(string: video.videoURL) else {
                print("BOUNDED CONTAINER: Invalid video URL for \(video.id)")
                return
            }
            
            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)
            
            // Setup player layer
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.frame = containerView.bounds
            playerLayer?.videoGravity = .resizeAspectFill
            
            if let playerLayer = playerLayer {
                // Clear any existing sublayers
                containerView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                containerView.layer.addSublayer(playerLayer)
            }
            
            currentVideoID = video.id
            
            // Setup loop notification
            setupLoopDetection()
            
            print("BOUNDED CONTAINER: New player created for \(video.id)")
        }
        
        // Update playback state and view tracking
        if isActive && player != nil {
            player?.play()
            startViewTracking(for: video)
            print("▶️ BOUNDED VIDEO: Playing \(currentVideoID?.prefix(8) ?? "unknown")")
        } else if !isActive && player != nil {
            player?.pause()
            stopViewTracking()
            print("⏸️ BOUNDED VIDEO: Paused \(currentVideoID?.prefix(8) ?? "unknown")")
        } else if player == nil {
            print("🚫 BOUNDED VIDEO: No player available (was killed)")
        }
        
        // Update layer frame if player exists
        if player != nil {
            DispatchQueue.main.async { [weak self] in
                self?.playerLayer?.frame = containerView.bounds
            }
        }
    }
    
    // MARK: - Loop Detection
    
    private func setupLoopDetection() {
        guard let player = player, let currentVideoID = currentVideoID else { return }
        
        // Remove existing observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Add new observer
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            print("BOUNDED CONTAINER: Video \(currentVideoID) reached end, triggering loop")
            
            // Restart video
            self?.player?.seek(to: .zero) { _ in
                if self?.isActive == true {
                    self?.player?.play()
                    self?.onVideoLoop(currentVideoID)
                }
            }
        }
    }
    
    // MARK: - View Tracking (0.5 second requirement)
    
    private func startViewTracking(for video: CoreVideoMetadata) {
        viewStartTime = Date()
        
        // Set timer for 0.5 second view registration
        viewTimer = Timer.scheduledTimer(withTimeInterval: minimumViewDuration, repeats: false) { [weak self] _ in
            self?.registerView(for: video)
        }
        
        print("VIEW TRACKING: Started for video \(video.id)")
    }
    
    private func registerView(for video: CoreVideoMetadata) {
        guard let startTime = viewStartTime, !hasRegisteredView else { return }
        
        let watchTime = Date().timeIntervalSince(startTime)
        hasRegisteredView = true
        print("VIEW TRACKING: ✅ Registered view for \(video.id) after \(String(format: "%.1f", watchTime))s")
        
        viewTimer?.invalidate()
        viewTimer = nil
    }
    
    private func stopViewTracking() {
        viewTimer?.invalidate()
        viewTimer = nil
        viewStartTime = nil
        print("VIEW TRACKING: Stopped")
    }
    
    private func resetViewTracking() {
        stopViewTracking()
        hasRegisteredView = false
        viewStartTime = nil
        print("VIEW TRACKING: Reset for new video")
    }
    
    // MARK: - Cleanup
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        stopViewTracking()
        
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentVideoID = nil
    }
    
    deinit {
        cleanupCurrentPlayer()
        resetViewTracking()
        
        // ✅ CRITICAL: Cleanup kill observer
        if let observer = killObserver {
            NotificationCenter.default.removeObserver(observer)
            killObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self)
        print("BOUNDED CONTAINER: Deinitializing with proper cleanup")
    }
}

// MARK: - Thread Navigation Context Extension

extension ThreadNavigationContext {
    var useBoundedContainers: Bool {
        switch self {
        case .homeFeed, .discovery:
            return false // Use VideoPlayerView
        case .profile, .fullscreen:
            return true // Use BoundedVideoContainer
        }
    }
}

// MARK: - ThreadNavigationView Previews

#if DEBUG
struct ThreadNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        ThreadNavigationView(
            threads: [],
            context: .homeFeed,
            videoService: VideoService()
        )
        .previewDisplayName("Home Feed Navigation")
        
        ThreadNavigationView(
            threads: [],
            context: .profile,
            videoService: VideoService()
        )
        .previewDisplayName("Profile Navigation")
    }
}
#endif
