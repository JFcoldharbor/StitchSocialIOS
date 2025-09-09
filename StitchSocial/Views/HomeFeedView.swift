//
//  HomeFeedView.swift
//  StitchSocial
//
//  Layer 8: Views - Container-First Video Feed Architecture
//  Dependencies: HomeFeedService, AuthService, ContextualVideoOverlay, CachingService
//  Features: Fixed containers, viewport movement, proper TikTok-style scrolling
//

import SwiftUI
import AVFoundation
import AVKit

/// Container-first video feed where videos stay in fixed containers and viewport moves
struct HomeFeedView: View {
    
    // MARK: - Backend Services
    
    @StateObject private var videoService: VideoService
    @StateObject private var userService: UserService
    @StateObject private var authService: AuthService
    @StateObject private var homeFeedService: HomeFeedService
    @StateObject private var videoPreloadingService: VideoPreloadingService
    @StateObject private var cachingService: CachingService
    
    // MARK: - Feed State
    @State private var currentFeed: [ThreadData] = []
    @State private var hasLoadedInitialFeed: Bool = false
    @State private var isShowingPlaceholder: Bool = true
    
    // MARK: - Container-First Navigation State
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    
    // MARK: - Viewport Control (Instead of Moving Videos)
    @State private var verticalOffset: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isAnimating: Bool = false
    @State private var dragOffset: CGSize = .zero
    
    // MARK: - Container Grid State
    @State private var containerSize: CGSize = .zero
    @State private var visibleContainers: Set<String> = []
    
    // MARK: - Loading State
    @State private var isLoading: Bool = false
    @State private var loadingError: String?
    @State private var isDebugging: Bool = true
    
    // MARK: - Initialization
    
    init() {
        let videoService = VideoService()
        let userService = UserService()
        let authService = AuthService()
        let cachingService = CachingService()
        let homeFeedService = HomeFeedService(
            videoService: videoService,
            userService: userService
        )
        let videoPreloadingService = VideoPreloadingService()
        
        self._videoService = StateObject(wrappedValue: videoService)
        self._userService = StateObject(wrappedValue: userService)
        self._authService = StateObject(wrappedValue: authService)
        self._homeFeedService = StateObject(wrappedValue: homeFeedService)
        self._videoPreloadingService = StateObject(wrappedValue: videoPreloadingService)
        self._cachingService = StateObject(wrappedValue: cachingService)
    }

    // MARK: - Main UI
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea(.all)
                
                if let error = loadingError {
                    errorView(error: error)
                } else if currentFeed.isEmpty && !isShowingPlaceholder {
                    emptyFeedView
                } else {
                    containerGridView(geometry: geometry)
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .onAppear {
            setupAudioSession()
            
            if !hasLoadedInitialFeed {
                loadInstantFeed()
                hasLoadedInitialFeed = true
            }
        }
        .refreshable {
            Task {
                await refreshFeed()
            }
        }
    }
    
    // MARK: - Container Grid View (TikTok-Style Fixed Containers)
    
    private func containerGridView(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // FIXED CONTAINER GRID - Videos stay in their containers
            ZStack {
                ForEach(Array(currentFeed.enumerated()), id: \.offset) { threadIndex, thread in
                    threadContainerStack(
                        thread: thread,
                        threadIndex: threadIndex,
                        geometry: geometry
                    )
                }
            }
            // VIEWPORT MOVEMENT - Move entire grid instead of individual videos
            .offset(
                x: horizontalOffset + dragOffset.width,
                y: verticalOffset + dragOffset.height
            )
            .animation(isAnimating ? .easeInOut(duration: 0.3) : nil, value: verticalOffset)
            .animation(isAnimating ? .easeInOut(duration: 0.25) : nil, value: horizontalOffset)
            
            // Debug overlay
            if isDebugging {
                debugOverlay(geometry: geometry)
            }
        }
        .onAppear {
            containerSize = geometry.size
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    if !isAnimating {
                        handleDragChanged(value: value)
                    }
                }
                .onEnded { value in
                    if !isAnimating {
                        handleDragEnded(value: value, geometry: geometry)
                    }
                }
        )
    }
    
    // MARK: - Thread Container Stack (Horizontal Layout)
    
    private func threadContainerStack(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        HStack(spacing: 0) {
            // Parent video container (always at position 0)
            FixedVideoContainer(
                video: thread.parentVideo,
                thread: thread,
                isActive: threadIndex == currentThreadIndex && currentStitchIndex == 0,
                containerID: "\(thread.id)-parent",
                onVisibilityChange: { isVisible in
                    updateContainerVisibility(containerID: "\(thread.id)-parent", isVisible: isVisible)
                }
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            
            // Child video containers (horizontal layout)
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                FixedVideoContainer(
                    video: childVideo,
                    thread: thread,
                    isActive: threadIndex == currentThreadIndex && currentStitchIndex == (childIndex + 1),
                    containerID: "\(thread.id)-child-\(childIndex)",
                    onVisibilityChange: { isVisible in
                        updateContainerVisibility(containerID: "\(thread.id)-child-\(childIndex)", isVisible: isVisible)
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        // FIXED POSITION - Each thread stack positioned in grid
        .position(
            x: geometry.size.width / 2, // Centered horizontally
            y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height) // Stacked vertically
        )
    }
    
    // MARK: - Fixed Video Container (Videos Stay Put)
    
    private struct FixedVideoContainer: View {
        let video: CoreVideoMetadata
        let thread: ThreadData
        let isActive: Bool
        let containerID: String
        let onVisibilityChange: (Bool) -> Void
        
        var body: some View {
            ZStack {
                // FIXED VIDEO PLAYER - Stays in container
                ContainerVideoPlayer(
                    video: video,
                    isActive: isActive,
                    shouldPlay: isActive
                )
                .clipped()
                
                // Overlay only on active video
                if isActive {
                    ContextualVideoOverlay(
                        video: video,
                        context: .homeFeed,
                        currentUserID: AuthService().currentUserID,
                        threadVideo: thread.parentVideo,
                        isVisible: true,
                        onAction: { _ in }
                    )
                }
            }
            .onAppear {
                onVisibilityChange(true)
            }
            .onDisappear {
                onVisibilityChange(false)
            }
        }
    }
    
    // MARK: - Container Video Player (Fixed in Container)
    
    private struct ContainerVideoPlayer: UIViewRepresentable {
        let video: CoreVideoMetadata
        let isActive: Bool
        let shouldPlay: Bool
        
        func makeUIView(context: Context) -> ContainerVideoUIView {
            let view = ContainerVideoUIView()
            view.backgroundColor = .black
            return view
        }
        
        func updateUIView(_ uiView: ContainerVideoUIView, context: Context) {
            uiView.setupVideo(
                video: video,
                isActive: isActive,
                shouldPlay: shouldPlay
            )
        }
    }
    
    private class ContainerVideoUIView: UIView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        private var notificationObserver: NSObjectProtocol?
        private var currentVideoID: String?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupPlayerLayer()
            setupKillObserver()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupPlayerLayer()
            setupKillObserver()
        }
        
        private func setupPlayerLayer() {
            playerLayer = AVPlayerLayer()
            playerLayer?.videoGravity = .resizeAspectFill
            playerLayer?.masksToBounds = true // STRICT CONTAINER BOUNDS
            layer.addSublayer(playerLayer!)
            layer.masksToBounds = true // PREVENT VIEW OVERFLOW
        }
        
        private func setupKillObserver() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(killPlayer),
                name: .killAllVideoPlayers,
                object: nil
            )
        }
        
        @objc private func killPlayer() {
            player?.pause()
            player?.seek(to: .zero)
            print("🛑 CONTAINER VIDEO: Killed player for \(currentVideoID ?? "unknown")")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
        
        func setupVideo(video: CoreVideoMetadata, isActive: Bool, shouldPlay: Bool) {
            // Only create new player if video changed
            if currentVideoID != video.id {
                cleanupCurrentPlayer()
                
                guard let url = URL(string: video.videoURL) else {
                    print("❌ CONTAINER VIDEO: Invalid URL for \(video.id)")
                    return
                }
                
                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                playerLayer?.player = newPlayer
                currentVideoID = video.id
                
                setupLooping()
                print("🎬 CONTAINER VIDEO: Created player for \(video.id) in fixed container")
            }
            
            // Control playback based on active state
            if isActive && shouldPlay {
                player?.play()
                print("▶️ CONTAINER VIDEO: Playing \(video.id)")
            } else {
                player?.pause()
                if currentVideoID == video.id {
                    print("⏸️ CONTAINER VIDEO: Paused \(video.id)")
                }
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
            
            print("🗑️ CONTAINER VIDEO: Cleaned up player")
        }
        
        deinit {
            cleanupCurrentPlayer()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // MARK: - Viewport Movement Gesture Handling
    
    private func handleDragChanged(value: DragGesture.Value) {
        // ONLY allow drag preview if children exist for horizontal movement
        let translation = value.translation
        let isHorizontalDrag = abs(translation.width) > abs(translation.height)
        
        if isHorizontalDrag {
            // Check if horizontal movement should be allowed
            if let thread = getCurrentThread(), !thread.childVideos.isEmpty {
                dragOffset = translation
                print("↔️ HORIZONTAL DRAG: Allowed (\(thread.childVideos.count) children)")
            } else {
                dragOffset = CGSize(width: 0, height: translation.height) // Only allow vertical
                print("🚫 HORIZONTAL DRAG: Blocked (no children)")
            }
        } else {
            dragOffset = translation // Allow vertical movement
        }
    }
    
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        let translation = value.translation
        let velocity = value.velocity
        let threshold: CGFloat = 80
        
        // Determine primary swipe direction
        let isHorizontalSwipe = abs(translation.width) > abs(translation.height) && abs(translation.width) > threshold
        let isVerticalSwipe = abs(translation.height) > abs(translation.width) && abs(translation.height) > threshold
        
        print("🎯 VIEWPORT SWIPE: dx=\(translation.width), dy=\(translation.height)")
        print("🎯 DIRECTION: horizontal=\(isHorizontalSwipe), vertical=\(isVerticalSwipe)")
        
        if isHorizontalSwipe {
            handleHorizontalViewportMove(translation: translation, velocity: velocity, geometry: geometry)
        } else if isVerticalSwipe {
            handleVerticalViewportMove(translation: translation, velocity: velocity, geometry: geometry)
        } else {
            // Snap back to current position
            snapToCurrentPosition()
        }
    }
    
    // MARK: - Horizontal Viewport Movement (Child Navigation)
    
    private func handleHorizontalViewportMove(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        let threshold: CGFloat = 80
        let shouldMove = abs(translation.width) > threshold || abs(velocity.width) > 400
        
        guard shouldMove else {
            snapToCurrentPosition()
            return
        }
        
        // Load children if needed
        preloadCurrentThreadChildren()
        
        if translation.width > 0 {
            // Swipe right - previous child
            moveViewportToPreviousChild(geometry: geometry)
        } else {
            // Swipe left - next child
            moveViewportToNextChild(geometry: geometry)
        }
    }
    
    private func moveViewportToNextChild(geometry: GeometryProxy) {
        guard let thread = getCurrentThread() else {
            snapToCurrentPosition()
            return
        }
        
        let maxChildIndex = thread.childVideos.count
        guard currentStitchIndex < maxChildIndex else {
            snapToCurrentPosition()
            return
        }
        
        let newStitchIndex = currentStitchIndex + 1
        moveViewportToChild(index: newStitchIndex, geometry: geometry)
    }
    
    private func moveViewportToPreviousChild(geometry: GeometryProxy) {
        guard currentStitchIndex > 0 else {
            snapToCurrentPosition()
            return
        }
        
        let newStitchIndex = currentStitchIndex - 1
        moveViewportToChild(index: newStitchIndex, geometry: geometry)
    }
    
    private func moveViewportToChild(index: Int, geometry: GeometryProxy) {
        // Stop current video before moving
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        
        isAnimating = true
        currentStitchIndex = index
        
        // Move viewport horizontally to show the target container
        // Parent at index 0 = position 0
        // Child 1 at index 1 = position -390px
        // Child 2 at index 2 = position -780px
        let targetHorizontalOffset = -CGFloat(index) * geometry.size.width
        
        print("📍 VIEWPORT MOVE: Moving to index \(index), offset: \(targetHorizontalOffset)")
        if index == 0 {
            print("🏠 VIEWPORT: Returning to parent position")
        } else {
            print("👶 VIEWPORT: Moving to child \(index) position")
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            horizontalOffset = targetHorizontalOffset
            dragOffset = .zero
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isAnimating = false
            let videoType = index == 0 ? "parent" : "child \(index)"
            print("✅ VIEWPORT: Successfully moved to \(videoType)")
        }
    }
    
    // MARK: - Vertical Viewport Movement (Thread Navigation)
    
    private func handleVerticalViewportMove(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        let threshold: CGFloat = 100
        let shouldMove = abs(translation.height) > threshold || abs(velocity.height) > 500
        
        guard shouldMove else {
            snapToCurrentPosition()
            return
        }
        
        if translation.height < 0 {
            // Swipe up - next thread
            moveViewportToNextThread(geometry: geometry)
        } else {
            // Swipe down - previous thread
            moveViewportToPreviousThread(geometry: geometry)
        }
    }
    
    private func moveViewportToNextThread(geometry: GeometryProxy) {
        guard currentThreadIndex < currentFeed.count - 1 else {
            snapToCurrentPosition()
            return
        }
        
        moveViewportToThread(index: currentThreadIndex + 1, geometry: geometry)
    }
    
    private func moveViewportToPreviousThread(geometry: GeometryProxy) {
        guard currentThreadIndex > 0 else {
            snapToCurrentPosition()
            return
        }
        
        moveViewportToThread(index: currentThreadIndex - 1, geometry: geometry)
    }
    
    private func moveViewportToThread(index: Int, geometry: GeometryProxy) {
        // Stop current video before moving
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        
        isAnimating = true
        currentThreadIndex = index
        currentStitchIndex = 0 // Reset to parent when changing threads
        
        // Move viewport vertically to show the thread container
        let targetVerticalOffset = -CGFloat(index) * geometry.size.height
        let targetHorizontalOffset: CGFloat = 0 // Reset to parent
        
        withAnimation(.easeInOut(duration: 0.3)) {
            verticalOffset = targetVerticalOffset
            horizontalOffset = targetHorizontalOffset
            dragOffset = .zero
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isAnimating = false
            print("⬆️⬇️ VIEWPORT: Moved to thread \(index)")
        }
    }
    
    // MARK: - Viewport Helpers
    
    private func snapToCurrentPosition() {
        withAnimation(.easeInOut(duration: 0.25)) {
            dragOffset = .zero
        }
    }
    
    private func updateContainerVisibility(containerID: String, isVisible: Bool) {
        if isVisible {
            visibleContainers.insert(containerID)
        } else {
            visibleContainers.remove(containerID)
        }
    }
    
    // MARK: - Child Loading Integration
    
    private func preloadCurrentThreadChildren() {
        guard let thread = getCurrentThread() else { return }
        
        if thread.childVideos.isEmpty {
            loadThreadChildren(threadID: thread.id)
        }
    }
    
    private func loadThreadChildren(threadID: String) {
        Task {
            do {
                let children = try await videoService.getThreadChildren(threadID: threadID)
                
                await MainActor.run {
                    if let index = currentFeed.firstIndex(where: { $0.id == threadID }) {
                        currentFeed[index] = ThreadData(
                            id: threadID,
                            parentVideo: currentFeed[index].parentVideo,
                            childVideos: children
                        )
                        print("✅ CHILDREN: Loaded \(children.count) children for \(threadID)")
                    }
                }
            } catch {
                print("❌ CHILDREN: Failed to load for \(threadID) - \(error)")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentThread() -> ThreadData? {
        guard currentThreadIndex >= 0 && currentThreadIndex < currentFeed.count else {
            return nil
        }
        return currentFeed[currentThreadIndex]
    }
    
    private func getCurrentVideo() -> CoreVideoMetadata? {
        guard let thread = getCurrentThread() else { return nil }
        
        if currentStitchIndex == 0 {
            return thread.parentVideo
        } else {
            let childIndex = currentStitchIndex - 1
            guard childIndex >= 0 && childIndex < thread.childVideos.count else {
                return thread.parentVideo
            }
            return thread.childVideos[childIndex]
        }
    }
    
    // MARK: - Debug Overlay
    
    private func debugOverlay(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing) {
                    Text("CONTAINER-FIRST ARCHITECTURE")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text("Thread: \(currentThreadIndex)/\(currentFeed.count-1)")
                    Text("Child: \(currentStitchIndex)")
                    Text("Viewport: (\(Int(verticalOffset + dragOffset.height)), \(Int(horizontalOffset + dragOffset.width)))")
                    Text("Drag: dx=\(Int(dragOffset.width)), dy=\(Int(dragOffset.height))")
                    Text("Animating: \(isAnimating)")
                    if let thread = getCurrentThread() {
                        Text("Children: \(thread.childVideos.count)")
                        let videoType = currentStitchIndex == 0 ? "Parent" : "Child \(currentStitchIndex)"
                        Text("Video: \(videoType)")
                        Text("Active Container: \(thread.id)-\(currentStitchIndex == 0 ? "parent" : "child-\(currentStitchIndex-1)")")
                        
                        // DEBUG: Show which containers should be active
                        Text("🎯 ACTIVE LOGIC:")
                            .foregroundColor(.green)
                        Text("threadIndex==currentThread: \(currentThreadIndex)==\(currentThreadIndex)")
                        Text("stitchIndex==currentStitch: \(currentStitchIndex)==\(currentStitchIndex)")
                    }
                    Text("Visible: \(visibleContainers.count) containers")
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .foregroundColor(.white)
                .font(.caption)
            }
        }
    }
    
    // MARK: - Basic Loading Implementation (Unchanged)
    
    private func loadInstantFeed() {
        guard let currentUserID = authService.currentUserID else {
            loadingError = "Authentication required"
            return
        }
        
        showPlaceholderFeed()
        
        Task {
            await loadRealFeedInBackground(userID: currentUserID)
        }
    }
    
    private func showPlaceholderFeed() {
        currentFeed = [
            createPlaceholderThread(id: "placeholder_1", title: "Loading your feed..."),
            createPlaceholderThread(id: "placeholder_2", title: "Almost ready..."),
            createPlaceholderThread(id: "placeholder_3", title: "Getting latest videos...")
        ]
        isShowingPlaceholder = true
    }
    
    private func createPlaceholderThread(id: String, title: String) -> ThreadData {
        let placeholderVideo = CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: "https://sample-videos.com/zip/10/mp4/720/SampleVideo_720x480_1mb.mp4",
            thumbnailURL: "",
            creatorID: "placeholder_creator",
            creatorName: "Loading...",
            createdAt: Date(),
            threadID: id,
            replyToVideoID: nil,
            conversationDepth: 0,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: 10.0,
            aspectRatio: 9.0/16.0,
            fileSize: 1024000,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
        
        return ThreadData(
            id: id,
            parentVideo: placeholderVideo,
            childVideos: []
        )
    }
    
    private func loadRealFeedInBackground(userID: String) async {
        do {
            let realFeed = try await homeFeedService.loadFeed(userID: userID)
            
            await MainActor.run {
                self.currentFeed = realFeed
                self.currentThreadIndex = 0
                self.currentStitchIndex = 0
                self.isShowingPlaceholder = false
                
                print("✅ FEED: Loaded \(realFeed.count) threads in container grid")
            }
            
            cachingService.cacheFeed(realFeed, userID: userID)
            
        } catch {
            await MainActor.run {
                self.loadingError = error.localizedDescription
                self.isShowingPlaceholder = false
            }
        }
    }
    
    private func refreshFeed() async {
        do {
            guard let currentUserID = authService.currentUserID else { return }
            
            let refreshedFeed = try await homeFeedService.refreshFeed(userID: currentUserID)
            
            currentFeed = refreshedFeed
            currentThreadIndex = 0
            currentStitchIndex = 0
            isShowingPlaceholder = false
            
            // Reset viewport to start
            verticalOffset = 0
            horizontalOffset = 0
            
            cachingService.cacheFeed(refreshedFeed, userID: currentUserID)
            
        } catch {
            loadingError = error.localizedDescription
        }
    }
    
    // MARK: - Audio Session Setup (Unchanged)
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AUDIO SESSION: Failed to setup - \(error)")
        }
    }
    
    // MARK: - Error & Empty Views (Unchanged)
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadingError = nil
                loadInstantFeed()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    private var emptyFeedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No videos to show")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Follow some creators or check back later for new content")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Preview

struct HomeFeedView_Previews: PreviewProvider {
    static var previews: some View {
        HomeFeedView()
    }
}
