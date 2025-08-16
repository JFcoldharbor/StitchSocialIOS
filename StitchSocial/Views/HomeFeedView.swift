//
//  HomeFeedView.swift
//  StitchSocial
//
//  Layer 8: Views - Enhanced Feed with Instant Loading
//  Dependencies: HomeFeedService, AuthService, ContextualVideoOverlay, CachingService
//  Features: Instant startup, background loading, multidirectional swiping
//

import SwiftUI
import AVFoundation
import AVKit

/// Enhanced navigation shell with instant loading and contextual overlay integration
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
    
    // MARK: - Navigation State
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var gestureDirection: NavigationDirection = .none
    
    // MARK: - Loading State - SIMPLIFIED
    @State private var isLoading: Bool = false // Changed to false for instant start
    @State private var loadingError: String?
    
    // MARK: - Performance Debugging
    @State private var startTime: CFAbsoluteTime = 0
    @State private var loadingPhases: [String: CFAbsoluteTime] = [:]
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
                    mainFeedContent(geometry: geometry)
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .onAppear {
            // Start timing
            startTime = CFAbsoluteTimeGetCurrent()
            logPhase("onAppear_started")
            
            setupAudioSession()
            logPhase("audio_session_setup")
            
            // INSTANT LOADING - NO BLOCKING AWAIT
            if !hasLoadedInitialFeed {
                loadInstantFeed()
                hasLoadedInitialFeed = true
                logPhase("instant_feed_initiated")
            }
        }
        .refreshable {
            Task {
                await refreshFeed()
            }
        }
    }
    
    // MARK: - INSTANT LOADING IMPLEMENTATION
    
    /// Load feed instantly with placeholders, then replace with real data
    private func loadInstantFeed() {
        logPhase("loadInstantFeed_started")
        
        guard let currentUserID = authService.currentUserID else {
            loadingError = "Authentication required"
            logPhase("auth_error")
            return
        }
        
        print("🚀 INSTANT: Starting instant load for user \(currentUserID)")
        
        // STEP 1: Check cache for instant display (synchronous)
        logPhase("cache_check_started")
        if let cachedFeed = cachingService.getCachedFeed(userID: currentUserID, limit: 20),
           !cachedFeed.isEmpty {
            currentFeed = cachedFeed
            isShowingPlaceholder = false
            logPhase("cache_hit_complete")
            
            // Preload current video only
            Task {
                await preloadCurrentVideoOnly()
                logPhase("cached_preload_complete")
            }
            
            print("⚡ CACHE: Instant load with \(cachedFeed.count) cached threads")
            logTotalTime("CACHE_HIT_TOTAL")
            return
        }
        
        logPhase("cache_miss")
        
        // STEP 2: Show placeholders immediately (no await, no delay)
        showPlaceholderFeed()
        logPhase("placeholders_shown")
        
        // STEP 3: Load real data in background (non-blocking)
        Task {
            await loadRealFeedInBackground(userID: currentUserID)
        }
        
        print("✅ INSTANT: UI ready with placeholders")
        logTotalTime("PLACEHOLDER_DISPLAY")
    }
    
    /// Show placeholder feed immediately (no network calls)
    private func showPlaceholderFeed() {
        currentFeed = createPlaceholderThreads()
        isShowingPlaceholder = true
        
        print("📺 PLACEHOLDER: Showing \(currentFeed.count) placeholder threads")
    }
    
    /// Create placeholder threads for instant display
    private func createPlaceholderThreads() -> [ThreadData] {
        return [
            createPlaceholderThread(id: "placeholder_1", title: "Loading your feed..."),
            createPlaceholderThread(id: "placeholder_2", title: "Almost ready..."),
            createPlaceholderThread(id: "placeholder_3", title: "Getting latest videos...")
        ]
    }
    
    /// Create single placeholder thread
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
    
    /// Load real feed data in background and replace placeholders
    private func loadRealFeedInBackground(userID: String) async {
        logPhase("background_load_started")
        
        do {
            print("🔥 BACKGROUND: Loading real feed data...")
            
            logPhase("homefeed_service_call_started")
            let realFeed = try await homeFeedService.loadFeed(userID: userID)
            logPhase("homefeed_service_call_completed")
            
            await MainActor.run {
                logPhase("ui_update_started")
                // Replace placeholders with real data
                self.currentFeed = realFeed
                self.currentThreadIndex = 0
                self.currentStitchIndex = 0
                self.isShowingPlaceholder = false
                logPhase("ui_update_completed")
            }
            
            // Cache for future instant loads
            logPhase("caching_started")
            cachingService.cacheFeed(realFeed, userID: userID)
            logPhase("caching_completed")
            
            // Load additional content in background (non-blocking)
            Task {
                await loadEnhancementsInBackground()
            }
            
            print("✅ BACKGROUND: Real feed loaded with \(realFeed.count) threads")
            logTotalTime("REAL_FEED_LOADED")
            
        } catch {
            logPhase("background_load_error")
            await MainActor.run {
                self.loadingError = error.localizedDescription
                self.isShowingPlaceholder = false
            }
            print("❌ BACKGROUND: Failed to load real feed - \(error.localizedDescription)")
            logTotalTime("BACKGROUND_ERROR")
        }
    }
    
    /// Load only current video for immediate playback
    private func preloadCurrentVideoOnly() async {
        guard let currentVideo = getCurrentVideo() else {
            logPhase("preload_current_no_video")
            return
        }
        
        logPhase("preload_current_started")
        await videoPreloadingService.preloadVideo(currentVideo, priority: .high)
        logPhase("preload_current_completed")
        
        print("🎬 MINIMAL PRELOAD: Current video ready")
    }
    
    /// Load enhancements without blocking UI
    private func loadEnhancementsInBackground() async {
        logPhase("enhancements_started")
        
        await withTaskGroup(of: Void.self) { group in
            
            // Load current thread children for horizontal swiping
            group.addTask {
                await self.loadCurrentThreadChildrenOnly()
                self.logPhase("current_thread_children_loaded")
            }
            
            // Preload adjacent videos for smooth navigation
            group.addTask {
                await self.preloadAdjacentVideosOnly()
                self.logPhase("adjacent_videos_preloaded")
            }
            
            // Load remaining thread children in batches
            group.addTask {
                await self.batchLoadRemainingChildren()
                self.logPhase("remaining_children_loaded")
            }
        }
        
        logPhase("enhancements_completed")
        print("✅ BACKGROUND: All enhancements loaded")
        logTotalTime("ALL_ENHANCEMENTS_COMPLETE")
    }
    
    /// Load children for current thread only (for immediate horizontal swiping)
    private func loadCurrentThreadChildrenOnly() async {
        guard currentThreadIndex < currentFeed.count else { return }
        
        do {
            let threadID = currentFeed[currentThreadIndex].id
            let children = try await videoService.getThreadChildren(threadID: threadID)
            
            await MainActor.run {
                if currentThreadIndex < currentFeed.count {
                    currentFeed[currentThreadIndex] = ThreadData(
                        id: currentFeed[currentThreadIndex].id,
                        parentVideo: currentFeed[currentThreadIndex].parentVideo,
                        childVideos: children
                    )
                }
            }
            
            print("✅ VIDEO SERVICE: Loaded \(children.count) children for thread \(threadID)")
        } catch {
            print("❌ CURRENT THREAD: Failed to load children")
        }
    }
    
    /// Load adjacent videos only (reduce from downloading everything)
    private func preloadAdjacentVideosOnly() async {
        guard !currentFeed.isEmpty else { return }
        
        // Only preload 2 adjacent videos maximum (reduced scope)
        var videosToPreload: [CoreVideoMetadata] = []
        
        // Current thread - only next video
        if let currentThread = getCurrentThread() {
            let videosInThread = [currentThread.parentVideo] + currentThread.childVideos
            
            // Only next video in thread (not previous)
            if currentStitchIndex + 1 < videosInThread.count {
                videosToPreload.append(videosInThread[currentStitchIndex + 1])
            }
        }
        
        // Only next thread parent video (not previous)
        if currentThreadIndex + 1 < currentFeed.count {
            videosToPreload.append(currentFeed[currentThreadIndex + 1].parentVideo)
        }
        
        // Preload with delays between each video
        for (index, video) in videosToPreload.enumerated() {
            await videoPreloadingService.preloadVideo(video, priority: .low)
            
            // Add delay between preloads to prevent overwhelming
            if index < videosToPreload.count - 1 {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay
            }
        }
        
        print("🎬 PRELOAD: Adjacent preload complete - \(videosToPreload.count) videos")
    }
    
    /// Load remaining thread children in smaller batches (reduce batch size)
    private func batchLoadRemainingChildren() async {
        let threadsNeedingChildren = currentFeed.enumerated().compactMap { index, thread in
            index != currentThreadIndex && thread.childVideos.isEmpty ? (index, thread.id) : nil
        }
        
        guard !threadsNeedingChildren.isEmpty else { return }
        
        print("🔥 BATCH: Loading \(threadsNeedingChildren.count) remaining threads")
        
        // Reduced batch size from 3 to 1 to prevent overwhelming
        let batchSize = 1
        let batches = threadsNeedingChildren.batchedIntoChunks(size: batchSize)
        
        for batch in batches.prefix(5) { // Only process first 5 batches to limit total work
            await withTaskGroup(of: (Int, [CoreVideoMetadata]).self) { group in
                for (feedIndex, threadID) in batch {
                    group.addTask {
                        do {
                            let children = try await self.videoService.getThreadChildren(threadID: threadID)
                            return (feedIndex, children)
                        } catch {
                            return (feedIndex, [])
                        }
                    }
                }
                
                // Update feed on main thread
                for await (feedIndex, children) in group {
                    await MainActor.run {
                        if feedIndex < self.currentFeed.count {
                            self.currentFeed[feedIndex] = ThreadData(
                                id: self.currentFeed[feedIndex].id,
                                parentVideo: self.currentFeed[feedIndex].parentVideo,
                                childVideos: children
                            )
                        }
                    }
                }
            }
            
            // Longer delay between batches to spread out work
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
        }
        
        print("✅ BATCH: Completed \(min(5, batches.count)) priority threads")
    }
    
    // MARK: - Main Feed Content
    
    private func mainFeedContent(geometry: GeometryProxy) -> some View {
        ZStack {
            // Video Player Layer with Gesture Detection
            if let currentVideo = getCurrentVideo() {
                WorkingVideoPlayer(video: currentVideo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onChanged { value in
                                handleCombinedDrag(value: value, geometry: geometry)
                            }
                            .onEnded { value in
                                handleCombinedDragEnd(value: value, geometry: geometry)
                            }
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Text("No Video Available")
                            .foregroundColor(.white)
                            .font(.headline)
                    )
            }
            
            // Contextual Overlay Layer
            if let currentVideo = getCurrentVideo() {
                ContextualVideoOverlay(
                    video: currentVideo,
                    context: .homeFeed,
                    currentUserID: authService.currentUserID,
                    threadVideo: getCurrentThread()?.parentVideo,
                    isVisible: true,
                    onAction: { action in
                        handleOverlayAction(action)
                    }
                )
                .allowsHitTesting(true)
            }
            
                            // Loading indicator overlay (only for background loading)
            if isShowingPlaceholder {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white.opacity(0.7))
                        Text("Loading feed...")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.caption)
                        
                        // Debug timing display
                        if isDebugging {
                            Text("\(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms")
                                .foregroundColor(.yellow.opacity(0.8))
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                    .padding(.bottom, 100)
                    .onTapGesture {
                        // Toggle debugging with tap
                        toggleDebugging()
                    }
                }
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Working Video Player (Optimized)
    
    private struct WorkingVideoPlayer: UIViewRepresentable {
        let video: CoreVideoMetadata
        
        func makeUIView(context: Context) -> VideoUIView {
            let view = VideoUIView()
            view.backgroundColor = .black
            return view
        }
        
        func updateUIView(_ uiView: VideoUIView, context: Context) {
            uiView.setupVideo(video: video)
        }
    }
    
    private class VideoUIView: UIView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        private var notificationObserver: NSObjectProtocol?
        
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
        
        func setupVideo(video: CoreVideoMetadata) {
            // Clean up existing video completely
            cleanupCurrentVideo()
            
            guard let videoURL = URL(string: video.videoURL) else {
                print("Invalid video URL")
                return
            }
            
            print("Setting up new video: \(video.title)")
            
            // Create new player with fast loading settings
            let newPlayer = AVPlayer(url: videoURL)
            newPlayer.automaticallyWaitsToMinimizeStalling = false // Faster startup
            
            let newPlayerLayer = AVPlayerLayer(player: newPlayer)
            newPlayerLayer.videoGravity = .resizeAspectFill
            newPlayerLayer.frame = bounds
            
            layer.addSublayer(newPlayerLayer)
            
            player = newPlayer
            playerLayer = newPlayerLayer
            
            // Setup looping
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }
            
            // Start playing immediately
            newPlayer.play()
            
            print("Video setup complete: \(video.title)")
        }
        
        private func cleanupCurrentVideo() {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            playerLayer?.removeFromSuperlayer()
            
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
                notificationObserver = nil
            }
            
            player = nil
            playerLayer = nil
            
            print("Previous video cleaned up")
        }
        
        deinit {
            cleanupCurrentVideo()
        }
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowBluetooth, .allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - UI Components
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Feed Error")
                .foregroundColor(.white)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(error)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                loadInstantFeed()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
    
    private var emptyFeedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Videos Yet")
                .foregroundColor(.white)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Follow some users to see their videos in your feed!")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    // MARK: - Feed Management
    
    private func refreshFeed() async {
        do {
            guard let currentUserID = authService.currentUserID else { return }
            
            let refreshedFeed = try await homeFeedService.refreshFeed(userID: currentUserID)
            currentFeed = refreshedFeed
            currentThreadIndex = 0
            currentStitchIndex = 0
            isShowingPlaceholder = false
            
            // Cache refreshed feed
            cachingService.cacheFeed(refreshedFeed, userID: currentUserID)
            
            await preloadAdjacentVideosOnly()
            
        } catch {
            loadingError = error.localizedDescription
        }
    }
    
    // MARK: - Data Access
    
    private func getCurrentThread() -> ThreadData? {
        guard currentThreadIndex < currentFeed.count else { return nil }
        return currentFeed[currentThreadIndex]
    }
    
    private func getCurrentVideo() -> CoreVideoMetadata? {
        guard let thread = getCurrentThread() else { return nil }
        
        if currentStitchIndex == 0 {
            return thread.parentVideo
        } else {
            let childIndex = currentStitchIndex - 1
            guard childIndex < thread.childVideos.count else { return nil }
            return thread.childVideos[childIndex]
        }
    }
    
    // MARK: - Navigation Gesture Handling
    
    private func handleCombinedDrag(value: DragGesture.Value, geometry: GeometryProxy) {
        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)
        
        if gestureDirection == .none {
            if verticalMovement > 50 && verticalMovement > horizontalMovement * 1.5 {
                gestureDirection = .thread
            } else if horizontalMovement > 50 && horizontalMovement > verticalMovement * 1.5 {
                gestureDirection = .stitch
            }
        }
    }
    
    private func handleCombinedDragEnd(value: DragGesture.Value, geometry: GeometryProxy) {
        let threshold: CGFloat = 100
        
        if gestureDirection == .thread {
            if value.translation.height > threshold {
                navigateToPreviousThread()
            } else if value.translation.height < -threshold {
                navigateToNextThread()
            }
        } else if gestureDirection == .stitch {
            if value.translation.width > threshold {
                navigateToPreviousStitch()
            } else if value.translation.width < -threshold {
                navigateToNextStitch()
            }
        }
        
        gestureDirection = .none
    }
    
    // MARK: - Navigation Actions
    
    private func navigateToNextThread() {
        guard currentThreadIndex < currentFeed.count - 1 else { return }
        
        currentThreadIndex += 1
        currentStitchIndex = 0
        
        Task {
            await preloadAdjacentVideosOnly()
        }
    }
    
    private func navigateToPreviousThread() {
        guard currentThreadIndex > 0 else { return }
        
        currentThreadIndex -= 1
        currentStitchIndex = 0
        
        Task {
            await preloadAdjacentVideosOnly()
        }
    }
    
    private func navigateToNextStitch() {
        guard let thread = getCurrentThread() else { return }
        
        let maxStitchIndex = thread.childVideos.count
        guard currentStitchIndex < maxStitchIndex else { return }
        
        currentStitchIndex += 1
        
        Task {
            if let nextVideo = thread.video(at: currentStitchIndex + 1) {
                await videoPreloadingService.preloadVideo(nextVideo)
            }
        }
    }
    
    private func navigateToPreviousStitch() {
        guard currentStitchIndex > 0 else { return }
        
        currentStitchIndex -= 1
        
        Task {
            if let thread = getCurrentThread(),
               let prevVideo = thread.video(at: currentStitchIndex - 1) {
                await videoPreloadingService.preloadVideo(prevVideo)
            }
        }
    }
    
    // MARK: - Overlay Action Handlers
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        switch action {
        case .profile(let userID):
            print("👤 PROFILE: Opening profile for user \(userID)")
            
        case .thread(let threadID):
            print("🧵 THREAD: Opening thread \(threadID)")
            
        case .engagement(let type):
            print("🔥 ENGAGEMENT: \(type.rawValue)")
            
        case .follow:
            print("👤 FOLLOW: Following user")
            
        case .unfollow:
            print("👤 UNFOLLOW: Unfollowing user")
            
        case .share:
            print("📤 SHARE: Sharing video")
            
        case .reply:
            print("💬 REPLY: Creating reply")
            
        case .stitch:
            print("✂️ STITCH: Creating stitch")
            
        case .profileManagement:
            print("⚙️ PROFILE MANAGEMENT: Opening settings")
            
        case .more:
            print("⋯ MORE: Opening options menu")
            
        case .followToggle:
            print("🔄 FOLLOW TOGGLE: Toggle follow state")
            
        case .profileSettings:
            print("⚙️ PROFILE SETTINGS: Opening profile settings")
        }
    }
}

// MARK: - Performance Debugging Extensions

extension HomeFeedView {
    
    /// Log timing for specific phase
    private func logPhase(_ phase: String) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        loadingPhases[phase] = currentTime
        
        if isDebugging {
            let elapsed = currentTime - startTime
            print("🐞 DEBUG: \(phase) - \(String(format: "%.1f", elapsed * 1000))ms from start")
        }
    }
    
    /// Log total time from start with label
    private func logTotalTime(_ label: String) {
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ TIMING: \(label) - \(String(format: "%.1f", totalTime * 1000))ms total")
        
        if isDebugging {
            printDetailedTimingBreakdown()
        }
    }
    
    /// Print detailed timing breakdown of all phases
    private func printDetailedTimingBreakdown() {
        print("📊 DETAILED TIMING BREAKDOWN:")
        
        let sortedPhases = loadingPhases.sorted { $0.value < $1.value }
        var previousTime = startTime
        
        for (phase, time) in sortedPhases {
            let phaseTime = time - previousTime
            let totalTime = time - startTime
            print("   \(phase): +\(String(format: "%.1f", phaseTime * 1000))ms (total: \(String(format: "%.1f", totalTime * 1000))ms)")
            previousTime = time
        }
        
        // Find potential hangs (phases taking > 100ms)
        let slowPhases = loadingPhases.compactMap { (phase, time) -> (String, Double)? in
            let previousPhaseTime = loadingPhases.values.filter { $0 < time }.max() ?? startTime
            let phaseTime = time - previousPhaseTime
            return phaseTime > 0.1 ? (phase, phaseTime * 1000) : nil
        }.sorted { $0.1 > $1.1 }
        
        if !slowPhases.isEmpty {
            print("🚨 SLOW PHASES (>100ms):")
            for (phase, duration) in slowPhases {
                print("   \(phase): \(String(format: "%.1f", duration))ms")
            }
        }
    }
    
    /// Reset debugging timers
    private func resetDebugTimers() {
        startTime = CFAbsoluteTimeGetCurrent()
        loadingPhases.removeAll()
        print("🐞 DEBUG: Timers reset")
    }
    
    /// Toggle debugging on/off
    private func toggleDebugging() {
        isDebugging.toggle()
        print("🐞 DEBUG: Debugging \(isDebugging ? "enabled" : "disabled")")
    }
}

fileprivate extension Array {
    func batchedIntoChunks(size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Navigation Direction Enum

private enum NavigationDirection {
    case none
    case thread  // Vertical swipes for different threads
    case stitch  // Horizontal swipes for replies within thread
}

// MARK: - Preview

struct HomeFeedView_Previews: PreviewProvider {
    static var previews: some View {
        HomeFeedView()
    }
}
