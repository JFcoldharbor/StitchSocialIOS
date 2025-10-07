//
//  FullscreenVideoView.swift
//  StitchSocial
//
//  Layer 8: Views - Clean Fullscreen Video Player with Thread Navigation
//  Dependencies: SwiftUI, AVFoundation, AVKit
//  Features: Horizontal child navigation only, clean UI, actual video playback
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

struct FullscreenVideoView: View {
    let video: CoreVideoMetadata
    let onDismiss: (() -> Void)?
    
    // MARK: - State
    @State private var currentThread: ThreadData?
    @State private var currentVideoIndex: Int = 0
    @State private var isLoadingThread = true
    @State private var loadError: String?
    
    // Navigation state
    @State private var horizontalOffset: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimating = false
    
    // Services
    @StateObject private var videoService = VideoService()
    
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
        }
        .onDisappear {
            cleanupAudioSession()
        }
    }
    
    // MARK: - Main Content View
    
    private func mainContentView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Video players positioned horizontally
            ForEach(Array(allVideos.enumerated()), id: \.offset) { index, videoData in
                VideoPlayerComponent(
                    video: videoData,
                    isActive: index == currentVideoIndex && !isAnimating
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .ignoresSafeArea(.all)
                .position(
                    x: geometry.size.width / 2 + CGFloat(index) * geometry.size.width + horizontalOffset + dragOffset.width,
                    y: geometry.size.height / 2
                )
            }
            
            // UI Overlays
            overlayViews(geometry: geometry)
        }
        .gesture(swipeGesture(geometry: geometry))
    }
    
    // MARK: - UI Overlays
    
    private func overlayViews(geometry: GeometryProxy) -> some View {
        VStack {
            // Top area
            HStack {
                // Thread position indicator (left)
                if allVideos.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(currentVideoIndex + 1) of \(allVideos.count)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        if currentVideoIndex == 0 {
                            Text("Original video")
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
                
                Spacer()
                
                // Close button (right)
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                        )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            
            Spacer()
            
            // Bottom contextual overlay
            ContextualVideoOverlay(
                video: currentVideo,
                context: .profileOther,  // ✅ CORRECT - shows full overlay
                currentUserID: currentUserID,
                threadVideo: currentVideoIndex > 0 ? currentThread?.parentVideo : nil,
                isVisible: true,
                onAction: handleOverlayAction
            )
            .id("\(currentVideo.id)-\(currentVideoIndex)")
        }
    }
    
    // MARK: - Gesture Handling
    
    private func swipeGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if !isAnimating {
                    dragOffset = CGSize(
                        width: value.translation.width * 0.8,
                        height: 0
                    )
                }
            }
            .onEnded { value in
                handleSwipe(translation: value.translation, geometry: geometry)
            }
    }
    
    private func handleSwipe(translation: CGSize, geometry: GeometryProxy) {
        let threshold: CGFloat = 80
        let isSwipeLeft = translation.width < -threshold
        let isSwipeRight = translation.width > threshold
        
        if isSwipeLeft && currentVideoIndex < allVideos.count - 1 {
            // Next video
            moveToVideo(currentVideoIndex + 1, geometry: geometry)
        } else if isSwipeRight && currentVideoIndex > 0 {
            // Previous video
            moveToVideo(currentVideoIndex - 1, geometry: geometry)
        } else {
            // Snap back
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
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAnimating = false
        }
        
        print("FULLSCREEN: Moved to video \(index + 1) of \(allVideos.count)")
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
                }
                
                print("FULLSCREEN: Loaded thread with \(threadData.childVideos.count) children")
                
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.isLoadingThread = false
                }
                print("FULLSCREEN ERROR: \(error)")
            }
        }
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("FULLSCREEN: Failed to setup audio session: \(error)")
        }
    }
    
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("FULLSCREEN: Failed to cleanup audio session: \(error)")
        }
    }
    
    // MARK: - State Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            
            Text("Loading video thread...")
                .foregroundColor(.white)
                .font(.subheadline)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Failed to load video")
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
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    // MARK: - Action Handling
    
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
            print("FULLSCREEN: Engagement \(type) for video \(currentVideo.id)")
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            
        case .follow, .unfollow, .followToggle:
            print("FULLSCREEN: Follow action for creator \(currentVideo.creatorID)")
            
        case .share:
            shareVideo()
            
        case .reply:
            presentReplyInterface()
            
        case .stitch:
            presentStitchInterface()
            
        case .more, .profileManagement, .profileSettings:
            print("FULLSCREEN: More options requested")
        }
    }
    
    private func shareVideo() {
        let shareText = "Check out this video by \(currentVideo.creatorName) on Stitch Social!"
        let shareURL = URL(string: "https://stitchsocial.app/video/\(currentVideo.id)")!
        
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
                "videoID": currentVideo.id,
                "threadID": currentVideo.threadID ?? currentVideo.id
            ]
        )
    }
    
    private func presentStitchInterface() {
        NotificationCenter.default.post(
            name: NSNotification.Name("PresentRecording"),
            object: nil,
            userInfo: [
                "context": "stitchVideo",
                "videoID": currentVideo.id,
                "threadID": currentVideo.threadID ?? currentVideo.id
            ]
        )
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
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geometry in
            if hasError {
                errorState
            } else if isLoading {
                loadingState
            } else {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea(.all)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                player?.play()
            } else {
                player?.pause()
            }
        }
    }
    
    private func setupPlayer() {
        guard let videoURL = URL(string: video.videoURL) else {
            hasError = true
            isLoading = false
            return
        }
        
        let asset = AVAsset(url: videoURL)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Configure for looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            if isActive {
                player?.play()
            }
        }
        
        // Monitor loading state
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    isLoading = false
                    if isActive {
                        player?.play()
                    }
                case .failed:
                    hasError = true
                    isLoading = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerItem = nil
        cancellables.removeAll()
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

// MARK: - Preview

struct FullscreenVideoView_Previews: PreviewProvider {
    static var previews: some View {
        FullscreenVideoView(
            video: CoreVideoMetadata.newThread(
                title: "Preview Video",
                videoURL: "https://example.com/video.mp4",
                thumbnailURL: "https://example.com/thumb.jpg",
                creatorID: "creator1",
                creatorName: "Creator",
                duration: 30.0,
                fileSize: 1024
            ),
            onDismiss: {
                print("Preview dismiss")
            }
        )
    }
}
