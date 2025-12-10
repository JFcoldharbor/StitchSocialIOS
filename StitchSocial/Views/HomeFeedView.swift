//
//  HomeFeedView.swift
//  StitchSocial
//
//  Layer 8: Views - INSTANT PLAYBACK Home Feed with Thread Navigation
//  Dependencies: VideoService, UserService, HomeFeedService, EngagementService
//  Features: Instant video switching, stabilized scrolling, VideoPlayerComponent integration
//  FIXED: Uses VideoPreloadingService.shared singleton
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine
import Network

// MARK: - GeometryProxy Protocol

protocol GeometryProxyProtocol {
    var size: CGSize { get }
}

extension GeometryProxy: GeometryProxyProtocol {}

// MARK: - MockGeometry Helper

struct MockGeometry: GeometryProxyProtocol {
    let size: CGSize
}

// MARK: - HomeFeedView

struct HomeFeedView: View {
    
    // MARK: - Service Dependencies
    
    @StateObject private var videoService: VideoService
    @StateObject private var userService: UserService
    @StateObject private var authService: AuthService
    @StateObject private var homeFeedService: HomeFeedService
    @StateObject private var cachingService: CachingService
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    
    // MARK: - Feed Cache (Offline Support)
    
    private var feedCache: FeedCache {
        FeedCache.shared
    }
    
    // MARK: - Preloading Service (FIXED: Use singleton)
    
    private var videoPreloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    // MARK: - Home Feed State
    
    @State private var currentFeed: [ThreadData] = []
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isShowingPlaceholder: Bool = true
    @State private var hasLoadedInitialFeed: Bool = false
    @State private var loadingError: String? = nil
    @State private var isReshuffling: Bool = false
    @State private var isOfflineMode: Bool = false
    @State private var isLoadingFresh: Bool = false
    
    // Video tracking (simplified)
    @State private var videoPlayCounts: [String: Int] = [:]
    @State private var lastUserInteraction: Date = Date()
    
    // MARK: - People Finder State
    
    @State private var showingPeopleFinder: Bool = false
    @State private var shouldShowPeopleFinderPrompt: Bool = false
    @State private var peopleFinderTriggerCount: Int = 0
    
    // MARK: - Viewport State
    
    @State private var containerSize: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimating: Bool = false
    @State private var gestureDebouncer: Timer?
    
    // MARK: - OPTIMIZED GESTURE PHYSICS (TIKTOK-STYLE)
    
    private let gestureMinimumDistance: CGFloat = 15  // Lower = faster detection
    private let swipeThresholdHorizontal: CGFloat = 60
    private let swipeThresholdVertical: CGFloat = 80
    private let directionRatio: CGFloat = 1.5
    private let animationDuration: TimeInterval = 0.25
    
    private let dragResistance: CGFloat = 0.6
    private let maxDragDistance: CGFloat = 80
    
    // Swipe state tracking
    @State private var hasPausedForSwipe: Bool = false
    
    // MARK: - Initialization (FIXED: Removed VideoPreloadingService instantiation)
    
    init(
        injectedVideoService: VideoService? = nil,
        injectedUserService: UserService? = nil,
        injectedAuthService: AuthService? = nil
    ) {
        let videoSvc = injectedVideoService ?? VideoService()
        let userSvc = injectedUserService ?? UserService()
        let authSvc = injectedAuthService ?? AuthService()
        let cachingService = CachingService()
        let homeFeedService = HomeFeedService(
            videoService: videoSvc,
            userService: userSvc
        )
        
        self._videoService = StateObject(wrappedValue: videoSvc)
        self._userService = StateObject(wrappedValue: userSvc)
        self._authService = StateObject(wrappedValue: authSvc)
        self._homeFeedService = StateObject(wrappedValue: homeFeedService)
        self._cachingService = StateObject(wrappedValue: cachingService)
    }
    
    // MARK: - Main Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea(.all)
                
                if let error = loadingError {
                    errorView(error: error)
                } else if currentFeed.isEmpty && !isShowingPlaceholder {
                    emptyFeedView
                } else {
                    stabilizedContainerGrid(geometry: geometry)
                }
                
                if isReshuffling {
                    reshuffleOverlay
                }
                
                // Offline indicator
                if isOfflineMode {
                    offlineIndicator
                }
                
                // Background refresh indicator
                if isLoadingFresh && !currentFeed.isEmpty {
                    backgroundLoadingIndicator
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .onAppear {
            print("🏠 HOMEFEED: View appeared")
            setupAudioSession()
            
            if !hasLoadedInitialFeed {
                print("🏠 HOMEFEED: Loading initial feed with cache")
                loadInstantFeedWithCache()
                hasLoadedInitialFeed = true
            } else {
                print("🏠 HOMEFEED: Returning to feed, triggering preload")
                Task {
                    await preloadCurrentAndNext()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preloadHomeFeed)) { _ in
            print("🎬 HOMEFEED: Received preload notification from tab switch")
            Task {
                await preloadCurrentAndNext()
            }
        }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected && isOfflineMode {
                print("📶 HOMEFEED: Back online, refreshing...")
                loadFreshFeedInBackground()
            }
        }
        .killBackgroundOnAppear(.stitches)
        .onDisappear {
            print("🏠 HOMEFEED: View disappeared")
        }
        .refreshable {
            Task {
                await refreshFeed()
            }
        }
    }
    
    // MARK: - Offline Indicator
    
    private var offlineIndicator: some View {
        VStack {
            HStack {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12))
                Text("Offline Mode")
                    .font(.caption.bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.9))
            .cornerRadius(16)
            .padding(.top, 50)
            
            Spacer()
        }
    }
    
    // MARK: - Background Loading Indicator
    
    private var backgroundLoadingIndicator: some View {
        VStack {
            HStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.7)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
                    .padding(.top, 50)
                    .padding(.trailing, 16)
            }
            Spacer()
        }
    }
    
    // MARK: - Reshuffle Overlay
    
    private var reshuffleOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "shuffle")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isReshuffling ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isReshuffling)
                
                Text("Reshuffling feed...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(24)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
        }
    }
    
    // MARK: - STABILIZED Container Grid
    
    private func stabilizedContainerGrid(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ZStack {
                ForEach(Array(currentFeed.enumerated()), id: \.offset) { threadIndex, thread in
                    stabilizedThreadContainer(
                        thread: thread,
                        threadIndex: threadIndex,
                        geometry: geometry
                    )
                }
            }
            .offset(
                x: horizontalOffset + (isAnimating ? 0 : dragOffset.width),
                y: verticalOffset + (isAnimating ? 0 : dragOffset.height)
            )
            .animation(
                isAnimating ?
                .spring(response: 0.25, dampingFraction: 0.95, blendDuration: 0) :
                nil,
                value: verticalOffset
            )
            .animation(
                isAnimating ?
                .spring(response: 0.25, dampingFraction: 0.95, blendDuration: 0) :
                nil,
                value: horizontalOffset
            )
        }
        .onAppear {
            containerSize = geometry.size
        }
        .gesture(
            DragGesture(minimumDistance: gestureMinimumDistance)
                .onChanged { value in
                    handleStabilizedDragChanged(value: value)
                }
                .onEnded { value in
                    handleStabilizedDragEnded(value: value, geometry: geometry)
                }
        )
    }
    
    // MARK: - Stabilized Thread Container (FIXED: Removed .environmentObject)
    
    private func stabilizedThreadContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            // Parent video - INSTANT PLAYBACK with VideoPlayerComponent
            InstantVideoContainer(
                video: thread.parentVideo,
                thread: thread,
                isActive: threadIndex == currentThreadIndex && currentStitchIndex == 0,
                containerID: "\(thread.id)-parent",
                onVideoLoop: { videoID in
                    incrementVideoPlayCount(for: videoID)
                }
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height)
            )
            
            // Child videos - INSTANT PLAYBACK with VideoPlayerComponent
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                InstantVideoContainer(
                    video: childVideo,
                    thread: thread,
                    isActive: threadIndex == currentThreadIndex && currentStitchIndex == (childIndex + 1),
                    containerID: "\(thread.id)-child-\(childIndex)",
                    onVideoLoop: { videoID in
                        incrementVideoPlayCount(for: videoID)
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .position(
                    x: geometry.size.width / 2 + (CGFloat(childIndex + 1) * geometry.size.width),
                    y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height)
                )
            }
        }
        .id("\(thread.id)-\(thread.childVideos.count)")
    }
    
    // MARK: - Gesture Handling (UNCHANGED)
    
    private func handleStabilizedDragChanged(value: DragGesture.Value) {
        recordUserInteraction()
        gestureDebouncer?.invalidate()
        guard !isAnimating && !isReshuffling else { return }
        
        // TIKTOK PATTERN: Pause video IMMEDIATELY when swipe starts
        if !hasPausedForSwipe {
            hasPausedForSwipe = true
            videoPreloadingService.pauseAllPlayback()
            print("⏸️ SWIPE START: Paused for swipe")
        }
        
        let translation = value.translation
        let resistedWidth = min(abs(translation.width), maxDragDistance) * dragResistance * (translation.width < 0 ? -1 : 1)
        let resistedHeight = min(abs(translation.height), maxDragDistance) * dragResistance * (translation.height < 0 ? -1 : 1)
        
        if abs(resistedWidth) > abs(resistedHeight) {
            if let thread = getCurrentThread(), !thread.childVideos.isEmpty {
                dragOffset = CGSize(width: resistedWidth, height: 0)
            } else {
                dragOffset = CGSize(width: 0, height: resistedHeight)
            }
        } else {
            dragOffset = CGSize(width: 0, height: resistedHeight)
        }
    }
    
    private func handleStabilizedDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        recordUserInteraction()
        
        let translation = value.translation
        let velocity = value.velocity
        
        // Velocity-boosted translation for snappier response
        let velocityFactor: CGFloat = 0.1
        let adjustedTranslation = CGSize(
            width: translation.width + (velocity.width * velocityFactor),
            height: translation.height + (velocity.height * velocityFactor)
        )
        
        let isHorizontalSwipe = abs(adjustedTranslation.width) > swipeThresholdHorizontal &&
                               abs(adjustedTranslation.width) > abs(adjustedTranslation.height) * directionRatio
        let isVerticalSwipe = abs(adjustedTranslation.height) > swipeThresholdVertical &&
                             abs(adjustedTranslation.height) > abs(adjustedTranslation.width) * directionRatio
        
        // Process immediately - no debouncer for faster response
        processStabilizedGesture(
            isHorizontal: isHorizontalSwipe,
            isVertical: isVerticalSwipe,
            translation: adjustedTranslation,
            velocity: velocity,
            geometry: geometry
        )
    }
    
    private func processStabilizedGesture(
        isHorizontal: Bool,
        isVertical: Bool,
        translation: CGSize,
        velocity: CGSize,
        geometry: GeometryProxy
    ) {
        isAnimating = true
        
        if isHorizontal {
            handleHorizontalSwipe(translation: translation, velocity: velocity, geometry: geometry)
        } else if isVertical {
            handleVerticalSwipe(translation: translation, velocity: velocity, geometry: geometry)
        } else {
            // No valid swipe - snap back and resume current video
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
        }
        
        withAnimation(.easeOut(duration: 0.1)) {
            dragOffset = .zero
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            isAnimating = false
            hasPausedForSwipe = false
        }
    }
    
    // MARK: - Resume Current Video
    
    private func resumeCurrentVideo() {
        guard let video = getCurrentVideo() else { return }
        if let player = videoPreloadingService.getPlayer(for: video) {
            player.play()
            print("▶️ RESUMED: \(video.id.prefix(8))")
        }
    }
    
    // MARK: - Navigation Methods (UNCHANGED)
    
    private func handleHorizontalSwipe(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        guard let currentThread = getCurrentThread() else {
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
            return
        }
        
        guard !currentThread.childVideos.isEmpty else {
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
            print("🚫 HORIZONTAL BLOCKED: No children in current thread")
            return
        }
        
        let isSwipeLeft = translation.width < 0
        let isSwipeRight = translation.width > 0
        
        if isSwipeLeft {
            if currentStitchIndex < currentThread.childVideos.count {
                let nextStitchIndex = currentStitchIndex + 1
                smoothMoveToStitch(nextStitchIndex, geometry: geometry)
                print("➡️ MOVED TO: Thread \(currentThreadIndex), Child \(nextStitchIndex)")
            } else {
                smoothSnapToCurrentPosition()
                resumeCurrentVideo()
                print("📚 AT END: Cannot go further in thread")
            }
        } else if isSwipeRight {
            if currentStitchIndex > 0 {
                let prevStitchIndex = currentStitchIndex - 1
                smoothMoveToStitch(prevStitchIndex, geometry: geometry)
                print("⬅️ MOVED TO: Thread \(currentThreadIndex), Child \(prevStitchIndex)")
            } else {
                smoothSnapToCurrentPosition()
                resumeCurrentVideo()
                print("🏠 AT PARENT: Cannot go back further in thread")
            }
        }
    }
    
    private func handleVerticalSwipe(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        let isSwipeUp = translation.height < 0
        let isSwipeDown = translation.height > 0
        
        if isSwipeUp {
            if currentThreadIndex < currentFeed.count - 1 {
                smoothMoveToThread(currentThreadIndex + 1, geometry: geometry)
            } else {
                if shouldTriggerScrollLoad() {
                    loadMoreContentAndContinue()
                } else {
                    smoothSnapToCurrentPosition()
                    resumeCurrentVideo()
                }
            }
        } else if isSwipeDown {
            if currentThreadIndex > 0 {
                smoothMoveToThread(currentThreadIndex - 1, geometry: geometry)
            } else {
                smoothSnapToCurrentPosition()
                resumeCurrentVideo()
            }
        }
    }
    
    private func smoothMoveToThread(_ threadIndex: Int, geometry: GeometryProxyProtocol) {
        recordUserInteraction()
        
        guard threadIndex >= 0 && threadIndex < currentFeed.count else {
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
            return
        }
        
        currentThreadIndex = threadIndex
        currentStitchIndex = 0
        
        // TIKTOK-STYLE: Snappy spring animation
        withAnimation(.interpolatingSpring(stiffness: 400, damping: 35)) {
            verticalOffset = -CGFloat(threadIndex) * geometry.size.height
            horizontalOffset = 0
        }
        
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
        
        // Trigger preload for smooth next swipe
        Task {
            await preloadCurrentAndNext()
        }
        
        preloadAdjacentThreads()
        
        if peopleFinderTriggerCount % 3 == 0 {
            checkScrollBasedLoading()
        }
        
        if peopleFinderTriggerCount % 5 == 0 {
            trackNavigationForPeopleFinder()
        }
        
        peopleFinderTriggerCount += 1
        
        print("🎬 MOVED TO THREAD: \(threadIndex)")
    }
    
    private func smoothMoveToStitch(_ stitchIndex: Int, geometry: GeometryProxyProtocol) {
        recordUserInteraction()
        
        guard let currentThread = getCurrentThread() else {
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
            return
        }
        
        let maxStitchIndex = currentThread.childVideos.count
        guard stitchIndex >= 0 && stitchIndex <= maxStitchIndex else {
            smoothSnapToCurrentPosition()
            resumeCurrentVideo()
            return
        }
        
        currentStitchIndex = stitchIndex
        
        // TIKTOK-STYLE: Snappy spring animation
        withAnimation(.interpolatingSpring(stiffness: 400, damping: 35)) {
            horizontalOffset = -CGFloat(stitchIndex) * geometry.size.width
        }
        
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
        
        print("🎯 MOVED TO STITCH: \(stitchIndex) in thread \(currentThreadIndex)")
    }
    
    private func smoothSnapToCurrentPosition() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.98)) {
            dragOffset = .zero
        }
        print("↩️ SNAPPED BACK: Staying at Thread \(currentThreadIndex), Child \(currentStitchIndex)")
    }
    
    // MARK: - Video Play Count Management
    
    private func incrementVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID, default: 0] += 1
        print("🎥 PLAY COUNT: Video \(videoID) played \(videoPlayCounts[videoID] ?? 0) times")
    }
    
    private func resetVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID] = 0
        print("🔄 RESET COUNT: Video \(videoID) play count reset")
    }
    
    // MARK: - User Interaction Tracking
    
    private func recordUserInteraction() {
        lastUserInteraction = Date()
        print("👆 USER INTERACTION: Recorded at \(lastUserInteraction)")
    }
    
    // MARK: - Content Loading (UNCHANGED)
    
    private func loadMoreContentAndContinue() {
        guard let currentUserID = authService.currentUserID else { return }
        
        Task {
            do {
                print("📤 LOADING MORE: Fetching content...")
                let updatedFeed = try await homeFeedService.getReshuffledFeed(userID: currentUserID)
                
                await MainActor.run {
                    if updatedFeed.count > currentFeed.count {
                        currentFeed = updatedFeed
                        currentThreadIndex = min(currentThreadIndex, currentFeed.count - 1)
                        print("✅ LOADED MORE: Updated feed with \(updatedFeed.count) threads")
                        preloadAdjacentThreads()
                    }
                }
                
                if updatedFeed.count <= currentFeed.count {
                    let freshThreads = try await homeFeedService.refreshFeed(userID: currentUserID)
                    await MainActor.run {
                        currentFeed = freshThreads
                        currentThreadIndex = 0
                        currentStitchIndex = 0
                        verticalOffset = 0
                        horizontalOffset = 0
                        print("🔄 REFRESHED: New feed with \(freshThreads.count) threads")
                    }
                }
            } catch {
                print("❌ LOAD MORE ERROR: \(error.localizedDescription)")
                await refreshFeed()
            }
        }
    }
    
    private func checkScrollBasedLoading() {
        guard let currentUserID = authService.currentUserID else { return }
        
        let shouldTriggerLoad = shouldTriggerScrollLoad()
        
        if shouldTriggerLoad {
            Task {
                do {
                    print("📱 SCROLL LOAD: Triggered at thread \(currentThreadIndex)")
                    let newThreads = try await homeFeedService.loadMoreContent(userID: currentUserID)
                    
                    await MainActor.run {
                        if !newThreads.isEmpty {
                            currentFeed.append(contentsOf: newThreads)
                            print("✅ SCROLL LOAD: Added \(newThreads.count) threads seamlessly")
                        }
                    }
                } catch {
                    print("❌ SCROLL LOAD ERROR: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func shouldTriggerScrollLoad() -> Bool {
        let remainingThreads = currentFeed.count - currentThreadIndex
        let triggerThreshold = 5
        
        return remainingThreads <= triggerThreshold &&
               !homeFeedService.isLoading
    }
    
    private func loadInstantFeed() {
        guard let currentUserID = authService.currentUserID else {
            loadingError = "Please sign in to view your feed"
            return
        }
        
        isShowingPlaceholder = true
        
        Task {
            do {
                print("🚀 HOME FEED: Loading instant feed for user \(currentUserID)")
                let threads = try await homeFeedService.loadFeed(userID: currentUserID)
                
                await MainActor.run {
                    currentFeed = threads
                    currentThreadIndex = 0
                    currentStitchIndex = 0
                    isShowingPlaceholder = false
                    loadingError = nil
                    verticalOffset = 0
                    horizontalOffset = 0
                }
                
                print("✅ HOME FEED: Feed loaded with \(threads.count) threads")
                
                // CRITICAL: Preload videos immediately after feed loads
                print("🎬 HOME FEED: Starting preload after feed load")
                await preloadCurrentAndNext()
                
            } catch {
                await MainActor.run {
                    loadingError = "Failed to load feed: \(error.localizedDescription)"
                    isShowingPlaceholder = false
                }
                print("❌ HOME FEED: Feed loading failed: \(error)")
            }
        }
    }
    
    // MARK: - Cache-First Loading (INSTANT APP OPEN)
    
    private func loadInstantFeedWithCache() {
        guard let currentUserID = authService.currentUserID else {
            loadingError = "Please sign in to view your feed"
            return
        }
        
        // Step 1: Try to show cached feed INSTANTLY
        if let cachedThreads = feedCache.loadCachedFeed() {
            currentFeed = cachedThreads
            isShowingPlaceholder = false
            isOfflineMode = !networkMonitor.isConnected
            print("⚡ HOMEFEED: Displaying cached feed instantly (\(cachedThreads.count) threads)")
            
            // Preload cached videos
            Task {
                await preloadCurrentAndNext()
            }
            
            // Step 2: If online, refresh in background
            if networkMonitor.isConnected {
                loadFreshFeedInBackground()
            }
        } else {
            // No cache - load normally
            isShowingPlaceholder = true
            
            Task {
                do {
                    print("🚀 HOME FEED: No cache, loading from network")
                    let threads = try await homeFeedService.loadFeed(userID: currentUserID)
                    
                    await MainActor.run {
                        currentFeed = threads
                        currentThreadIndex = 0
                        currentStitchIndex = 0
                        isShowingPlaceholder = false
                        loadingError = nil
                        verticalOffset = 0
                        horizontalOffset = 0
                        isOfflineMode = false
                    }
                    
                    // Cache for next time
                    feedCache.cacheFeed(threads)
                    print("💾 HOMEFEED: Cached \(threads.count) threads for offline")
                    
                    await preloadCurrentAndNext()
                    
                } catch {
                    await MainActor.run {
                        if currentFeed.isEmpty {
                            loadingError = "Failed to load feed: \(error.localizedDescription)"
                        }
                        isShowingPlaceholder = false
                    }
                    print("❌ HOME FEED: Feed loading failed: \(error)")
                }
            }
        }
    }
    
    private func loadFreshFeedInBackground() {
        guard let currentUserID = authService.currentUserID else { return }
        guard !isLoadingFresh else { return }
        
        isLoadingFresh = true
        
        Task {
            do {
                print("🔄 HOMEFEED: Background refresh started")
                let freshThreads = try await homeFeedService.loadFeed(userID: currentUserID)
                
                await MainActor.run {
                    // Preserve position if user hasn't scrolled far
                    if currentThreadIndex < 3 {
                        currentFeed = freshThreads
                        currentThreadIndex = 0
                        currentStitchIndex = 0
                        verticalOffset = 0
                        horizontalOffset = 0
                    }
                    isOfflineMode = false
                    isLoadingFresh = false
                }
                
                // Update cache
                feedCache.cacheFeed(freshThreads)
                print("✅ HOMEFEED: Background refresh complete (\(freshThreads.count) threads)")
                
                await preloadCurrentAndNext()
                
            } catch {
                await MainActor.run {
                    isLoadingFresh = false
                }
                print("⚠️ HOMEFEED: Background refresh failed: \(error)")
            }
        }
    }
    
    private func refreshFeed() async {
        guard let currentUserID = authService.currentUserID else { return }
        
        do {
            let refreshedThreads = try await homeFeedService.refreshFeed(userID: currentUserID)
            
            await MainActor.run {
                currentFeed = refreshedThreads
                currentThreadIndex = 0
                currentStitchIndex = 0
                verticalOffset = 0
                horizontalOffset = 0
                isOfflineMode = false
            }
            
            // Cache refreshed feed
            feedCache.cacheFeed(refreshedThreads)
            
            await preloadCurrentAndNext()
            
        } catch {
            await MainActor.run {
                loadingError = "Failed to refresh feed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Preloading Support (INSTAGRAM/TIKTOK PATTERN)
    
    private func preloadCurrentAndNext() async {
        guard !currentFeed.isEmpty else {
            print("⚠️ PRELOAD: Feed is empty, skipping")
            return
        }
        
        print("🎬 PRELOAD: Starting preload - currentThread: \(currentThreadIndex), currentStitch: \(currentStitchIndex)")
        
        // Get videos to preload
        var videosToPreload: [CoreVideoMetadata] = []
        
        // Current thread
        if currentThreadIndex < currentFeed.count {
            let currentThread = currentFeed[currentThreadIndex]
            videosToPreload.append(currentThread.parentVideo)
            videosToPreload.append(contentsOf: currentThread.childVideos.prefix(2))
            print("🎬 PRELOAD: Added current thread videos: \(videosToPreload.count) total")
        }
        
        // Next thread
        if currentThreadIndex + 1 < currentFeed.count {
            let nextThread = currentFeed[currentThreadIndex + 1]
            videosToPreload.append(nextThread.parentVideo)
            print("🎬 PRELOAD: Added next thread parent")
        }
        
        // Next next thread
        if currentThreadIndex + 2 < currentFeed.count {
            let nextNextThread = currentFeed[currentThreadIndex + 2]
            videosToPreload.append(nextNextThread.parentVideo)
            print("🎬 PRELOAD: Added next-next thread parent")
        }
        
        print("🎬 PRELOAD: Total videos to preload: \(videosToPreload.count)")
        
        // Preload into VideoPreloadingService pool
        for (index, video) in videosToPreload.enumerated() {
            let priority: PreloadPriority = index == 0 ? .high : .normal
            print("🎬 PRELOAD: Preloading video \(index + 1)/\(videosToPreload.count): \(video.id.prefix(8)) (priority: \(priority))")
            await videoPreloadingService.preloadVideo(video, priority: priority)
        }
        
        print("✅ PRELOAD: Completed loading \(videosToPreload.count) videos into player pool")
        
        // Log pool status
        let poolStatus = videoPreloadingService.getPoolStatus()
        print("📊 PRELOAD POOL STATUS: \(poolStatus.totalPlayers)/\(poolStatus.maxPoolSize) players (\(Int(poolStatus.utilizationPercentage * 100))% utilized)")
    }
    
    private func preloadThreadIfNeeded(index: Int) {
        guard index >= 0 && index < currentFeed.count else { return }
        
        let thread = currentFeed[index]
        if thread.childVideos.isEmpty {
            print("📤 PRELOAD: Thread \(thread.id) has no children, attempting to load...")
            loadThreadChildren(threadID: thread.id)
        } else {
            print("✅ PRELOAD: Thread \(thread.id) already has \(thread.childVideos.count) children")
        }
    }
    
    private func preloadAdjacentThreads() {
        preloadThreadIfNeeded(index: currentThreadIndex)
        if currentThreadIndex + 1 < currentFeed.count {
            preloadThreadIfNeeded(index: currentThreadIndex + 1)
        }
        if currentThreadIndex - 1 >= 0 {
            preloadThreadIfNeeded(index: currentThreadIndex - 1)
        }
    }
    
    private func loadThreadChildren(threadID: String) {
        Task {
            do {
                let children = try await homeFeedService.loadThreadChildren(threadID: threadID)
                
                await MainActor.run {
                    updateThreadWithChildren(threadID: threadID, children: children)
                }
            } catch {
                print("❌ CHILD LOADING ERROR: \(error)")
            }
        }
    }
    
    private func updateThreadWithChildren(threadID: String, children: [CoreVideoMetadata]) {
        if let index = currentFeed.firstIndex(where: { $0.id == threadID }) {
            currentFeed[index] = ThreadData(
                id: threadID,
                parentVideo: currentFeed[index].parentVideo,
                childVideos: children
            )
            
            print("✅ THREAD UPDATED: \(threadID) now has \(children.count) children")
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
        } else if currentStitchIndex <= thread.childVideos.count {
            return thread.childVideos[currentStitchIndex - 1]
        }
        
        return nil
    }
    
    // MARK: - UI Components
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Loading your feed...")
                .foregroundColor(.white)
                .font(.headline)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(error)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadingError = nil
                loadInstantFeed()
            }
            .foregroundColor(.cyan)
            .padding()
            .background(Color.cyan.opacity(0.2))
            .cornerRadius(8)
        }
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
    
    // MARK: - People Finder (Stub)
    
    private func checkPeopleFinderEligibility() {
        let shouldShow = currentFeed.count < 3 || peopleFinderTriggerCount % 20 == 0
        if shouldShow && !shouldShowPeopleFinderPrompt {
            shouldShowPeopleFinderPrompt = true
        }
    }
    
    private func trackNavigationForPeopleFinder() {
        peopleFinderTriggerCount += 1
        if peopleFinderTriggerCount % 20 == 0 {
            checkPeopleFinderEligibility()
        }
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("✅ AUDIO SESSION: Configured for video playback")
        } catch {
            print("❌ AUDIO SESSION: Failed to setup - \(error)")
        }
    }
}

// MARK: - INSTANT VIDEO CONTAINER (Uses VideoPlayerComponent)

struct InstantVideoContainer: View {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    @EnvironmentObject var authService: AuthService
    @State private var previousActiveState: Bool = false
    
    var body: some View {
        ZStack {
            // INSTANT PLAYBACK with MyVideoPlayerComponent
            MyVideoPlayerComponent(
                video: video,
                isActive: isActive
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            // Overlay only on active video
            if isActive {
                ContextualVideoOverlay(
                    video: video,
                    context: .homeFeed,
                    currentUserID: AuthService().currentUserID,
                    threadVideo: thread.parentVideo,
                    isVisible: true,
                    actualReplyCount: thread.childVideos.count,
                    onAction: { _ in }
                )
            }
        }
        .onChange(of: isActive) { oldValue, newValue in
            if newValue != previousActiveState {
                previousActiveState = newValue
                if newValue {
                    print("▶️ INSTANT CONTAINER ACTIVATED: \(video.id.prefix(8))")
                } else {
                    print("⏸️ INSTANT CONTAINER DEACTIVATED: \(video.id.prefix(8))")
                }
            }
        }
        .onAppear {
            previousActiveState = isActive
        }
    }
}

// MARK: - VideoPlayerComponent is defined in FullscreenVideoView.swift
// Using shared component for consistent playback across app

// MARK: - MyVideoPlayerComponent (FIXED: Uses VideoPreloadingService.shared)

struct MyVideoPlayerComponent: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    
    // FIXED: Use singleton directly instead of @EnvironmentObject
    private var videoPreloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var hasTrackedView = false
    @State private var killObserver: NSObjectProtocol?
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
            print("🎬 PLAYER APPEARED: \(video.id.prefix(8)), isActive: \(isActive)")
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
                        print("📊 VIEW TRACKED: \(video.id.prefix(8)) in HomeFeed")
                    }
                }
            }
        }
        .onDisappear {
            print("🎬 PLAYER DISAPPEARED: \(video.id.prefix(8))")
            pausePlayer()
        }
        .onChange(of: isActive) { oldValue, newValue in
            print("🔄 ACTIVE STATE CHANGED: \(oldValue) → \(newValue) for \(video.id.prefix(8))")
            
            if newValue {
                // Became active - play immediately (player should be at zero)
                if player != nil && player?.currentItem != nil {
                    player?.play()
                    print("▶️ PLAYING (onChange): \(video.id.prefix(8))")
                } else {
                    print("⚠️ PLAYER NOT READY: Trying to setup again for \(video.id.prefix(8))")
                    setupPlayer()
                }
            } else {
                // Became inactive - pause AND reset to zero for next activation
                player?.pause()
                player?.seek(to: .zero) // Async reset - will be ready when user swipes back
                print("⏸️ PAUSED + RESET: \(video.id.prefix(8))")
            }
        }
        .onChange(of: video.id) { oldID, newID in
            print("🔄 VIDEO CHANGED: \(oldID.prefix(8)) → \(newID.prefix(8))")
            setupPlayer()
        }
    }
    
    private func setupPlayer() {
        print("🎬 SETUP PLAYER: Starting for video \(video.id.prefix(8)), isActive: \(isActive)")
        
        // INSTAGRAM/TIKTOK PATTERN: Check preloaded pool FIRST
        if let preloadedPlayer = videoPreloadingService.getPlayer(for: video) {
            print("⚡ INSTANT: Found preloaded player for \(video.id.prefix(8))")
            player = preloadedPlayer
            
            // Player is already at position zero from preload - NO SEEK NEEDED
            // Just unmute and play immediately
            player?.isMuted = false
            
            // Verify player has valid item
            if player?.currentItem != nil {
                print("✅ PRELOADED PLAYER: Valid item, ready to play")
                isLoading = false
                
                setupKillObserver()
                
                if isActive {
                    player?.play()
                    print("▶️ INSTANT PLAY: \(video.id.prefix(8))")
                } else {
                    print("⏸️ PRELOADED BUT NOT ACTIVE: Waiting for activation")
                }
                return
            } else {
                print("⚠️ PRELOADED PLAYER: No current item, falling back to fresh player")
                // Fall through to create fresh player
            }
        } else {
            print("⚠️ POOL MISS: No preloaded player found for \(video.id.prefix(8))")
        }
        
        // FALLBACK: Create fresh player
        print("🔄 CREATING PLAYER: Building new AVPlayer for \(video.id.prefix(8))")
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ SETUP PLAYER: Invalid URL for \(video.id.prefix(8))")
            hasError = true
            isLoading = false
            return
        }
        
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false
        
        setupKillObserver()
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            print("🔄 LOOP: Video ended, seeking to zero")
            self.player?.seek(to: .zero)
            if self.isActive {
                self.player?.play()
            }
        }
        
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                print("📊 PLAYER STATUS: \(status.rawValue) for \(self.video.id.prefix(8))")
                switch status {
                case .readyToPlay:
                    print("✅ READY TO PLAY: \(self.video.id.prefix(8)), isActive: \(self.isActive)")
                    self.isLoading = false
                    if self.isActive {
                        self.player?.play()
                        print("▶️ AUTO-PLAYING FALLBACK: \(self.video.id.prefix(8))")
                    } else {
                        print("⏸️ NOT ACTIVE: Waiting for activation")
                    }
                case .failed:
                    print("❌ FAILED: \(self.video.id.prefix(8)) - \(playerItem.error?.localizedDescription ?? "unknown")")
                    self.hasError = true
                    self.isLoading = false
                case .unknown:
                    print("❓ UNKNOWN STATUS: \(self.video.id.prefix(8))")
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        print("🔄 FALLBACK COMPLETE: Created fresh player for \(video.id.prefix(8))")
    }
    
    private func setupKillObserver() {
        killObserver = NotificationCenter.default.addObserver(
            forName: .RealkillAllVideoPlayers,
            object: nil,
            queue: .main
        ) { _ in
            self.handleKillNotification()
        }
    }
    
    private func handleKillNotification() {
        player?.pause()
        print("🛑 HOME FEED PLAYER: Killed player via notification for video \(video.id.prefix(8))")
    }
    
    private func pausePlayer() {
        player?.pause()
        print("⏸️ PAUSED: Player kept in pool for \(video.id.prefix(8))")
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

// MARK: - NotificationCenter Extension

extension Notification.Name {
    static let RealkillAllVideoPlayers = Notification.Name("killAllVideoPlayers")
    // preloadHomeFeed is declared in MainTabContainer.swift
}

// MARK: - Preview

struct HomeFeedView_Previews: PreviewProvider {
    static var previews: some View {
        HomeFeedView()
    }
}
