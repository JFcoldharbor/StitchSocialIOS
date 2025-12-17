//
//  FullscreenVideoView.swift
//  StitchSocial
//
//  Layer 8: Views - Clean Fullscreen Video Player with Thread Navigation
//  Dependencies: SwiftUI, AVFoundation, AVKit
//  Features: Horizontal child navigation, video playback, view tracking
//  UPDATED: Integrated memory management for crash prevention
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

struct FullscreenVideoView: View {
    let video: CoreVideoMetadata
    let onDismiss: (() -> Void)?
    let overlayContext: OverlayContext
    
    // MARK: - Initializers
    
    /// Full initializer with context
    init(video: CoreVideoMetadata, overlayContext: OverlayContext = .fullscreen, onDismiss: (() -> Void)? = nil) {
        self.video = video
        self.overlayContext = overlayContext
        self.onDismiss = onDismiss
    }
    
    // MARK: - State
    @State private var currentThread: ThreadData?
    @State private var currentVideoIndex: Int = 0
    @State private var isLoadingThread = true
    @State private var loadError: String?
    
    // Navigation state
    @State private var horizontalOffset: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var verticalDragOffset: CGFloat = 0
    @State private var isAnimating = false
    @State private var isDismissing = false
    
    // Services
    @StateObject private var videoService = VideoService()
    
    // MARK: - Memory Management (NEW)
    
    /// Reference to preloading service for memory management
    private var preloadService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    // MARK: - Computed Properties
    
    private var allVideos: [CoreVideoMetadata] {
        guard let thread = currentThread else { return [video] }
        return [thread.parentVideo] + thread.childVideos
    }
    
    private var currentVideo: CoreVideoMetadata {
        guard currentVideoIndex >= 0 && currentVideoIndex < allVideos.count else { return video }
        return allVideos[currentVideoIndex]
    }
    
    private var currentUserID: String? {
        return Auth.auth().currentUser?.uid
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea(.all)
                
                if isLoadingThread {
                    loadingView
                } else if let error = loadError {
                    errorView(error)
                } else {
                    mainContentView(geometry: geometry)
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .onAppear {
            setupAudioSession()
            loadThreadData()
            
            // MEMORY: Mark initial video as protected
            preloadService.markAsCurrentlyPlaying(video.id)
            print("ðŸ§  MEMORY: Marked \(video.id.prefix(8)) as currently playing")
        }
        .onDisappear {
            cleanupAudioSession()
            
            // MEMORY: Clear protection when leaving fullscreen
            preloadService.clearCurrentlyPlaying()
            print("ðŸ§  MEMORY: Cleared currently playing on dismiss")
        }
    }
    
    // MARK: - Main Content View
    
    private func mainContentView(geometry: GeometryProxy) -> some View {
        // Calculate dismiss progress (0 to 1) - faster response
        let dismissProgress = min(abs(verticalDragOffset) / 150, 1.0)
        
        // Smoother scaling - less aggressive
        let scale = 1.0 - (dismissProgress * 0.1)
        
        // Subtle opacity fade
        let opacity = 1.0 - (dismissProgress * 0.2)
        
        // Add corner radius as you drag (like iOS app switcher)
        let cornerRadius = dismissProgress * 20
        
        return ZStack {
            // Video players
            videoPlayersLayer(geometry: geometry)
            
            // UI Overlays
            overlayViews(geometry: geometry)
        }
        .offset(y: verticalDragOffset)
        .scaleEffect(scale)
        .opacity(opacity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .gesture(combinedGesture(geometry: geometry))
    }
    
    // MARK: - Video Players Layer (FIXED - Proper Identity)
    
    private func videoPlayersLayer(geometry: GeometryProxy) -> some View {
        ForEach(Array(allVideos.enumerated()), id: \.element.id) { index, videoData in
            let xPosition = geometry.size.width / 2 +
                           CGFloat(index) * geometry.size.width +
                           horizontalOffset +
                           dragOffset.width
            
            VideoPlayerComponent(
                video: videoData,
                isActive: index == currentVideoIndex && !isAnimating
            )
            .id(videoData.id) // Force unique identity per video
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .ignoresSafeArea(.all)
            .position(x: xPosition, y: geometry.size.height / 2)
        }
    }
    
    // MARK: - UI Overlays
    
    private func overlayViews(geometry: GeometryProxy) -> some View {
        VStack {
            // Top area
            topBar
            
            Spacer()
            
            // Bottom contextual overlay
            bottomOverlay
        }
    }
    
    private var topBar: some View {
        HStack {
            // Thread position indicator
            if allVideos.count > 1 {
                threadPositionIndicator
            }
            
            Spacer()
            
            // Close button
            closeButton
        }
    }
    
    private var threadPositionIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(currentVideoIndex + 1) of \(allVideos.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            if currentVideoIndex == 0 {
                Text("Original")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            } else {
                Text("Reply \(currentVideoIndex)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    private var closeButton: some View {
        Button(action: {
            // Pause all playback before dismissing
            preloadService.pauseAllPlayback()
            print("â¸ï¸ FULLSCREEN: Paused on close button")
            onDismiss?()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.6)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    private var bottomOverlay: some View {
        ContextualVideoOverlay(
            video: currentVideo,
            context: overlayContext,
            currentUserID: currentUserID,
            threadVideo: currentVideoIndex > 0 ? currentThread?.parentVideo : nil,
            isVisible: true,
            onAction: handleOverlayAction
        )
        .id("\(currentVideo.id)-\(currentVideoIndex)")
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        print("FULLSCREEN: Overlay action - \(action)")
        
        // CRITICAL: Pause all playback for any action that leads away from current view
        // This prevents audio overlap when user starts recording or navigates
        let actionString = String(describing: action).lowercased()
        
        // Actions that require pausing all videos
        let pauseActions = ["stitch", "reply", "record", "create", "profile", "thread", "navigate", "share"]
        
        let shouldPause = pauseActions.contains { actionString.contains($0) }
        
        if shouldPause {
            preloadService.pauseAllPlayback()
            print("â¸ï¸ FULLSCREEN: Paused all playback for action: \(action)")
        }
    }
    
    // MARK: - Gesture Handling
    
    private func combinedGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if !isAnimating && !isDismissing {
                    // Determine primary direction based on initial movement
                    let isVerticalSwipe = abs(value.translation.height) > abs(value.translation.width)
                    
                    if isVerticalSwipe {
                        // Vertical swipe - 1:1 tracking for natural feel
                        verticalDragOffset = value.translation.height
                        // Reset horizontal offset during vertical drag
                        dragOffset = .zero
                    } else {
                        // Horizontal swipe - thread navigation
                        dragOffset = CGSize(width: value.translation.width * 0.8, height: 0)
                        // Reset vertical offset during horizontal drag
                        verticalDragOffset = 0
                    }
                }
            }
            .onEnded { value in
                let isVerticalSwipe = abs(value.translation.height) > abs(value.translation.width)
                
                if isVerticalSwipe {
                    handleVerticalSwipe(translation: value.translation, velocity: value.velocity)
                } else {
                    handleHorizontalSwipe(translation: value.translation, geometry: geometry)
                }
            }
    }
    
    private func handleVerticalSwipe(translation: CGSize, velocity: CGSize) {
        // Lower thresholds for easier dismiss
        let dismissThreshold: CGFloat = 80
        let velocityThreshold: CGFloat = 300
        
        // Dismiss if swiped up far enough OR with enough velocity (either direction for velocity)
        let shouldDismiss = translation.height < -dismissThreshold ||
                           velocity.height < -velocityThreshold
        
        if shouldDismiss {
            // CRITICAL: Pause all playback before dismissing
            preloadService.pauseAllPlayback()
            print("â¸ï¸ FULLSCREEN: Paused all playback on dismiss")
            
            // Animate out and dismiss
            isDismissing = true
            
            // Fluid ease-out animation
            withAnimation(.easeOut(duration: 0.2)) {
                verticalDragOffset = -UIScreen.main.bounds.height
            }
            
            // Light haptic for subtle feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onDismiss?()
            }
        } else {
            // Bouncy snap back
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) {
                verticalDragOffset = 0
            }
        }
    }
    
    private func handleHorizontalSwipe(translation: CGSize, geometry: GeometryProxy) {
        let threshold: CGFloat = 80
        
        if translation.width < -threshold && currentVideoIndex < allVideos.count - 1 {
            moveToVideo(currentVideoIndex + 1, geometry: geometry)
        } else if translation.width > threshold && currentVideoIndex > 0 {
            moveToVideo(currentVideoIndex - 1, geometry: geometry)
        } else {
            snapBack()
        }
    }
    
    private func moveToVideo(_ index: Int, geometry: GeometryProxy) {
        guard index >= 0 && index < allVideos.count else {
            snapBack()
            return
        }
        
        isAnimating = true
        currentVideoIndex = index
        
        let targetOffset = -CGFloat(index) * geometry.size.width
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            horizontalOffset = targetOffset
            dragOffset = .zero
        }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // MEMORY: Update currently playing when navigating within thread
        let newVideoID = allVideos[index].id
        preloadService.markAsCurrentlyPlaying(newVideoID)
        print("ðŸ§  MEMORY: Updated currently playing to \(newVideoID.prefix(8))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAnimating = false
        }
        
        print("FULLSCREEN: Moved to \(index + 1)/\(allVideos.count)")
    }
    
    private func snapBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = .zero
        }
    }
    
    // MARK: - Thread Data Loading
    
    private func loadThreadData() {
        Task {
            do {
                isLoadingThread = true
                loadError = nil
                
                let threadID = video.threadID ?? video.id
                let threadData = try await videoService.getCompleteThread(threadID: threadID)
                
                let startingIndex: Int
                if video.id == threadData.parentVideo.id {
                    startingIndex = 0
                } else if let childIndex = threadData.childVideos.firstIndex(where: { $0.id == video.id }) {
                    startingIndex = childIndex + 1
                } else {
                    startingIndex = 0
                }
                
                await MainActor.run {
                    self.currentThread = threadData
                    self.currentVideoIndex = startingIndex
                    self.isLoadingThread = false
                    
                    // MEMORY: Update protection to actual starting video
                    let startingVideoID = startingIndex < allVideos.count ? allVideos[startingIndex].id : video.id
                    preloadService.markAsCurrentlyPlaying(startingVideoID)
                }
                
                print("âœ… FULLSCREEN: Loaded thread - \(threadData.childVideos.count) replies")
                
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.isLoadingThread = false
                }
                print("âŒ FULLSCREEN: Load error - \(error)")
            }
        }
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("âŒ FULLSCREEN: Audio setup failed")
        }
    }
    
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("âŒ FULLSCREEN: Audio cleanup failed")
        }
    }
    
    // MARK: - State Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(1.5)
            
            Text("Loading thread...")
                .foregroundColor(.white)
                .font(.subheadline)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Failed to load")
                .foregroundColor(.white)
                .font(.headline)
            
            Text(message)
                .foregroundColor(.gray)
                .font(.caption)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Retry") {
                    loadThreadData()
                }
                .padding()
                .background(Color.cyan)
                .foregroundColor(.black)
                .cornerRadius(8)
                
                Button("Close") {
                    onDismiss?()
                }
                .padding()
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

// MARK: - Video Player Component

struct VideoPlayerComponent: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var hasTrackedView = false
    @State private var killObserver: NSObjectProtocol?
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Memory Management (NEW)
    
    /// Check memory pressure before creating players
    private var preloadService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    var body: some View {
        GeometryReader { geometry in
            if hasError {
                errorState
            } else if isLoading {
                loadingState
            } else {
                CustomVideoPlayerView(player: player)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .clipped()
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .onAppear {
            setupPlayer()
            
            if isActive, !hasTrackedView, let userID = Auth.auth().currentUser?.uid {
                hasTrackedView = true
                
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    
                    if isActive {
                        let videoService = VideoService()
                        try? await videoService.trackVideoView(
                            videoID: video.id,
                            userID: userID,
                            watchTime: 5.0
                        )
                        print("ðŸ“Š VIEW: Tracked \(video.id.prefix(8))")
                    }
                }
            }
        }
        .onDisappear {
            // Cleanup when view disappears
            player?.pause()
            if let observer = killObserver {
                NotificationCenter.default.removeObserver(observer)
                killObserver = nil
            }
            print("ðŸ§¹ FULLSCREEN: Cleanup \(video.id.prefix(8))")
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                // Became active - play
                player?.isMuted = false
                if player?.rate == 0 {
                    player?.play()
                }
                print("â–¶ï¸ FULLSCREEN ACTIVE: \(video.id.prefix(8))")
            } else {
                // No longer active - MUST PAUSE to prevent audio overlap
                player?.pause()
                print("â¸ï¸ FULLSCREEN INACTIVE: \(video.id.prefix(8))")
            }
        }
    }
    
    private func setupPlayer() {
        // MEMORY: Try to get player from preload cache first
        if let cachedPlayer = preloadService.getPlayer(for: video) {
            self.player = cachedPlayer
            self.player?.isMuted = false // Unmute (preloaded muted)
            self.isLoading = false
            
            // SEAMLESS: Only start playing if not already playing
            // This preserves continuity from Discovery cards
            if isActive && cachedPlayer.rate == 0 {
                cachedPlayer.play()
                print("â–¶ï¸ STARTING PLAY: \(video.id.prefix(8))")
            } else if cachedPlayer.rate > 0 {
                print("â–¶ï¸ CONTINUING PLAY: \(video.id.prefix(8)) (already playing)")
            }
            
            print("ðŸŽ¬ COMPONENT: Using cached player for \(video.id.prefix(8))")
            return
        }
        
        // MEMORY: Check if we should create new player under pressure
        if preloadService.memoryPressureLevel >= .critical && !isActive {
            print("âš ï¸ COMPONENT: Skipping player creation - memory critical")
            // Show thumbnail instead - let loading state handle it
            return
        }
        
        guard let videoURL = URL(string: video.videoURL) else {
            hasError = true
            isLoading = false
            return
        }
        
        let asset = AVAsset(url: videoURL)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        setupKillObserver()
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            if self.isActive {
                self.player?.play()
            }
        }
        
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    if self.isActive {
                        self.player?.play()
                    }
                case .failed:
                    self.hasError = true
                    self.isLoading = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupKillObserver() {
        killObserver = NotificationCenter.default.addObserver(
            forName: .killAllVideoPlayers,
            object: nil,
            queue: .main
        ) { _ in
            self.player?.pause()
        }
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerItem = nil
        cancellables.removeAll()
        
        if let observer = killObserver {
            NotificationCenter.default.removeObserver(observer)
            killObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private var loadingState: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                Text("Loading video...")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
        }
    }
    
    private var errorState: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text("Failed to load video")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
        }
    }
}
