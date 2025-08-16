//
//  VideoPlayerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Player with ContextualVideoOverlay Integration and Thread Navigation
//  Dependencies: AVFoundation, CoreVideoMetadata, InteractionType, ContextualVideoOverlay
//  Features: Proper video display, ContextualVideoOverlay integration, thread swiping, edge-to-edge display
//

import SwiftUI
import AVFoundation
import AVKit
import Combine

// MARK: - Enhanced Video Player with Thread Navigation
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
    let currentThreadPosition: Int? // Which thread you're viewing (1-based)
    let totalStitchesInThread: Int? // Total stitches/videos in current thread
    
    // MARK: - Player State
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var currentVideoID: String = ""
    
    // MARK: - Thread Navigation State
    @State private var gestureDirection: VideoNavigationDirection = .none
    
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
                // Video Player Layer - Edge to Edge with FIXED display
                VideoPlayerRepresentable(
                    player: playerManager.player,
                    gravity: .resizeAspectFill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea(.all)
                .gesture(
                    // Thread navigation gestures (contextual based on usage)
                    DragGesture(minimumDistance: 50)
                        .onChanged { value in
                            if isActive && shouldAllowNavigation() {
                                handleThreadDrag(value: value)
                            }
                        }
                        .onEnded { value in
                            if isActive && shouldAllowNavigation() {
                                handleThreadDragEnd(value: value)
                            }
                        }
                )
                
                // Use ContextualVideoOverlay instead of embedded overlay
                if isActive {
                    ContextualVideoOverlay(
                        video: video,
                        context: .homeFeed, // You can make this dynamic based on usage
                        currentUserID: "current-user-id", // Pass actual currentUserID
                        threadVideo: nil, // Pass threadVideo if available
                        isVisible: true,
                        onAction: { action in
                            handleOverlayAction(action)
                        }
                    )
                } else {
                    // Minimal grid overlay
                    gridModeOverlay(geometry: geometry)
                }
                
                // Thread position indicator (contextual display)
                if isActive && shouldShowPositionIndicator() {
                    threadPositionIndicator
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(isActive)
        .ignoresSafeArea(.all)
        .onAppear {
            setupVideoPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: isActive) { _, active in
            if active {
                forcePlay()
            } else {
                pauseVideo()
            }
        }
    }
    
    // MARK: - Contextual Navigation Logic
    
    private func shouldAllowNavigation() -> Bool {
        guard let context = navigationContext else {
            // Default: allow if threadVideos provided
            return threadVideos != nil
        }
        
        switch context {
        case .homeFeed:
            return true // Always allow in home feed
        case .discovery:
            return true // Always allow in discovery
        case .profileGrid:
            return threadVideos != nil // Only if part of thread
        case .standalone:
            return false // Never allow for standalone videos
        }
    }
    
    private func shouldShowPositionIndicator() -> Bool {
        guard let threadVideos = threadVideos, threadVideos.count > 1 else {
            return false
        }
        
        guard let context = navigationContext else {
            return true // Default: show if multiple videos
        }
        
        switch context {
        case .homeFeed, .discovery:
            return true // Always show in feeds
        case .profileGrid:
            return true // Show in profile when navigating
        case .standalone:
            return false // Never show for standalone
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
    
    // MARK: - Thread Navigation Gesture Handling
    
    private func handleThreadDrag(value: DragGesture.Value) {
        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)
        
        // Only set direction if movement is significant
        if gestureDirection == .none {
            if horizontalMovement > 50 && horizontalMovement > verticalMovement * 1.5 {
                gestureDirection = .horizontal
            } else if verticalMovement > 50 && verticalMovement > horizontalMovement * 1.5 {
                // Vertical gestures contextual based on usage
                if navigationContext == .homeFeed || navigationContext == .discovery {
                    gestureDirection = .vertical
                }
            }
        }
    }
    
    private func handleThreadDragEnd(value: DragGesture.Value) {
        let threshold: CGFloat = 100
        
        switch gestureDirection {
        case .horizontal:
            if value.translation.width > threshold {
                navigateToPrevious()
            } else if value.translation.width < -threshold {
                navigateToNext()
            }
        case .vertical:
            // Vertical navigation only in feed contexts
            if navigationContext == .homeFeed || navigationContext == .discovery {
                if value.translation.height > threshold {
                    onNavigate?(.vertical, -1) // Navigate up in feed
                } else if value.translation.height < -threshold {
                    onNavigate?(.vertical, 1) // Navigate down in feed
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
        
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func navigateToPrevious() {
        guard currentIndex > 0 else { return }
        
        let newIndex = currentIndex - 1
        onNavigate?(.horizontal, newIndex)
        
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    // MARK: - Grid Mode Overlay (Minimal)
    
    private func gridModeOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Duration overlay (top-right)
            if video.duration > 0 {
                Text(formatDuration(video.duration))
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: geometry.size.width - 30, y: 15)
            }
            
            // Engagement stats (bottom-left)
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
                interactionType = .reply // Map stitch to reply for now
            }
            onEngagement?(interactionType)
            
        default:
            print("Overlay action: \(action)")
        }
    }
    
    // MARK: - Player Setup and Control
    
    private func setupVideoPlayer() {
        guard let videoURL = URL(string: video.videoURL) else {
            print("Invalid video URL: \(video.videoURL)")
            return
        }
        
        guard currentVideoID != video.id else {
            print("VIDEO: Already setup for this video")
            return
        }
        
        print("VIDEO PLAYER: Setting up player for '\(video.title)'")
        playerManager.setupPlayer(with: videoURL)
        currentVideoID = video.id
        
        if isActive {
            forceAutoplay()
        }
    }
    
    private func forceAutoplay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            forcePlay()
            print("VIDEO PLAYER: Autoplay initiated for '\(video.title)'")
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

// MARK: - FIXED Video Player Manager
@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var isMuted: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var currentVideoURL: URL?
    
    func setupPlayer(with url: URL) {
        guard currentVideoURL != url else {
            print("VIDEO: Reusing existing player for same URL")
            return
        }
        
        cleanup()
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        currentVideoURL = url
        
        setupTimeObserver()
        setupPublishers()
        setupLooping()
        
        print("VIDEO: Player created for \(url.lastPathComponent)")
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
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
    }
}

// MARK: - FIXED Video Player UIKit Representable
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

// MARK: - FIXED Video Player UI View
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

/// Video navigation direction (renamed to avoid conflicts with HomeFeedView)
enum VideoNavigationDirection {
    case none
    case horizontal  // Left/right swipes within thread/content
    case vertical    // Up/down swipes between threads/feeds
}

/// Video player usage context for contextual navigation behavior
enum VideoPlayerContext {
    case homeFeed        // Home feed - allow all navigation
    case discovery       // Discovery feed - allow all navigation
    case profileGrid     // Profile grid - allow thread navigation only
    case standalone      // Standalone video - no navigation
}
