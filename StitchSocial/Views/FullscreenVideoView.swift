//
//  FullscreenVideoView.swift
//  StitchSocial
//
//  Layer 8: Views - Fullscreen Video Player with AVPlayer
//  Dependencies: SwiftUI, AVFoundation, AVKit
//  Features: Edge-to-edge video playback with dismiss functionality
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth

struct FullscreenVideoView: View {
    let video: CoreVideoMetadata
    let onDismiss: (() -> Void)?
    
    @State private var player: AVPlayer?
    @State private var showingControls = true
    
    // Convenience initializer for backwards compatibility
    init(video: CoreVideoMetadata, onDismiss: (() -> Void)? = nil) {
        self.video = video
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(.all)
            
            // Edge-to-edge video player using HomeFeed approach
            if let _ = player {
                FullscreenVideoPlayerView(
                    video: video,
                    isActive: true,
                    shouldPlay: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls.toggle()
                    }
                }
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text("Loading video...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
            }
            
            // Controls overlay (when visible) - Overlaid on edge-to-edge video
            if showingControls {
                VStack {
                    // Top controls
                    HStack {
                        Button("Close") {
                            print("FULLSCREEN: Close button tapped")
                            onDismiss?()
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    // Contextual Video Overlay - No additional padding
                    ContextualVideoOverlay(
                        video: video,
                        context: .discovery,
                        currentUserID: getCurrentUserID(),
                        threadVideo: nil,
                        isVisible: showingControls
                    ) { action in
                        handleOverlayAction(action)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .onAppear {
            print("FULLSCREEN: View appeared for video: \(video.title)")
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .gesture(
            // Swipe down to dismiss
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        print("FULLSCREEN: Swipe down detected, dismissing")
                        onDismiss?()
                    }
                }
        )
    }
    
    // MARK: - Player Management
    
    private func setupPlayer() {
        guard URL(string: video.videoURL) != nil else {
            print("FULLSCREEN: Invalid video URL for \(video.title)")
            return
        }
        
        print("FULLSCREEN: Setting up custom player for \(video.title)")
        
        // Create a dummy player to trigger the UI update
        // The actual player is created in FullscreenVideoUIView
        player = AVPlayer()
        
        // Auto-hide controls after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls = false
            }
        }
    }
    
    private func cleanupPlayer() {
        print("FULLSCREEN: Cleaning up player")
        player = nil
    }
    
    
    // MARK: - Helper Functions
    
    private func getCurrentUserID() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        switch action {
        case .profile(let userID):
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToProfile"),
                object: nil,
                userInfo: ["userID": userID]
            )
            
        case .thread(let threadID):
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToThread"),
                object: nil,
                userInfo: ["threadID": threadID]
            )
            
        case .engagement(let type):
            handleEngagement(type)
            
        case .follow, .unfollow, .followToggle:
            handleFollowAction()
            
        case .share:
            shareVideo()
            
        case .reply:
            presentReplyInterface()
            
        case .stitch:
            presentStitchInterface()
            
        case .profileManagement, .profileSettings:
            NotificationCenter.default.post(
                name: NSNotification.Name("PresentSettings"),
                object: nil
            )
            
        case .more:
            presentMoreOptions()
        }
    }
    
    private func handleEngagement(_ type: ContextualEngagementType) {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        Task {
            let engagementCoordinator = EngagementCoordinator(
                videoService: VideoService(),
                notificationService: NotificationService()
            )
            
            switch type {
            case .hype:
                try await engagementCoordinator.processEngagement(
                    videoID: video.id,
                    engagementType: .hype,
                    userID: currentUserID,
                    userTier: .rookie
                )
            case .cool:
                try await engagementCoordinator.processEngagement(
                    videoID: video.id,
                    engagementType: .cool,
                    userID: currentUserID,
                    userTier: .rookie
                )
            case .share:
                shareVideo()
            case .reply:
                presentReplyInterface()
            case .stitch:
                presentStitchInterface()
            }
        }
    }
    
    private func handleFollowAction() {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let userService = UserService()
                try await userService.followUser(
                    followerID: currentUserID,
                    followingID: video.creatorID
                )
                print("FULLSCREEN: Follow action completed for user \(video.creatorID)")
            } catch {
                print("FULLSCREEN: Follow action failed: \(error)")
            }
        }
    }
    
    private func shareVideo() {
        let shareText = "Check out this video on Stitch Social!"
        let shareURL = URL(string: "https://stitchsocial.app/video/\(video.id)")!
        
        let activityController = UIActivityViewController(
            activityItems: [shareText, shareURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            activityController.popoverPresentationController?.sourceView = window
            activityController.popoverPresentationController?.sourceRect = CGRect(
                x: window.bounds.midX,
                y: window.bounds.midY,
                width: 0,
                height: 0
            )
            
            rootViewController.present(activityController, animated: true)
        }
    }
    
    private func presentReplyInterface() {
        NotificationCenter.default.post(
            name: NSNotification.Name("PresentRecording"),
            object: nil,
            userInfo: [
                "context": "replyToVideo",
                "videoID": video.id,
                "threadID": video.threadID ?? video.id
            ]
        )
    }
    
    private func presentStitchInterface() {
        NotificationCenter.default.post(
            name: NSNotification.Name("PresentRecording"),
            object: nil,
            userInfo: [
                "context": "stitchVideo",
                "videoID": video.id,
                "threadID": video.threadID ?? video.id
            ]
        )
    }
    
    private func presentMoreOptions() {
        print("FULLSCREEN: More options requested for video \(video.id)")
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Custom Fullscreen Video Player (HomeFeed Style)

struct FullscreenVideoPlayerView: UIViewRepresentable {
    let video: CoreVideoMetadata
    let isActive: Bool
    let shouldPlay: Bool
    
    func makeUIView(context: Context) -> FullscreenVideoUIView {
        let view = FullscreenVideoUIView()
        return view
    }
    
    func updateUIView(_ uiView: FullscreenVideoUIView, context: Context) {
        uiView.setupVideo(
            video: video,
            isActive: isActive,
            shouldPlay: shouldPlay
        )
    }
}

class FullscreenVideoUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var notificationObserver: NSObjectProtocol?
    private var currentVideoID: String?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStrictBounds()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStrictBounds()
    }
    
    // FIXED: Strict bounds setup like HomeFeed
    private func setupStrictBounds() {
        backgroundColor = .black
        clipsToBounds = true // CRITICAL: Prevent view overflow
        layer.masksToBounds = true // CRITICAL: Prevent layer overflow
        
        // Create player layer with strict bounds
        playerLayer = AVPlayerLayer()
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.masksToBounds = true // CRITICAL: Prevent player overflow
        layer.addSublayer(playerLayer!)
        
        print("FULLSCREEN PLAYER: Strict bounds setup complete")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // FIXED: Ensure player layer exactly matches view bounds
        playerLayer?.frame = bounds
    }
    
    func setupVideo(video: CoreVideoMetadata, isActive: Bool, shouldPlay: Bool) {
        // Only create new player if video changed
        if currentVideoID != video.id {
            cleanupCurrentPlayer()
            
            guard let url = URL(string: video.videoURL) else {
                print("FULLSCREEN PLAYER: Invalid URL for \(video.id)")
                return
            }
            
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            playerLayer?.player = newPlayer
            currentVideoID = video.id
            
            setupLooping()
            print("FULLSCREEN PLAYER: Created player for \(video.id)")
        }
        
        // Control playback based on active state
        if isActive && shouldPlay {
            player?.play()
            print("FULLSCREEN PLAYER: Playing \(video.id)")
        } else {
            player?.pause()
            print("FULLSCREEN PLAYER: Paused \(video.id)")
        }
    }
    
    private func setupLooping() {
        guard let player = player else { return }
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        player = nil
        playerLayer?.player = nil
        currentVideoID = nil
        
        print("FULLSCREEN PLAYER: Cleaned up player")
    }
    
    deinit {
        cleanupCurrentPlayer()
        NotificationCenter.default.removeObserver(self)
    }
}
