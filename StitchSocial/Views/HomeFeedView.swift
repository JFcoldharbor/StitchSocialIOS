//
//  HomeFeedView.swift
//  StitchSocial
//
//  Layer 8: Views - STABILIZED Home Feed with Thread Navigation
//  Dependencies: VideoService, UserService, HomeFeedService, EngagementService
//  Features: Stabilized scrolling, reduced wobble, improved gesture detection
//  FIXES: Gesture threshold optimization, animation spring physics, direction detection
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - GeometryProxy Protocol for Auto-Progression

protocol GeometryProxyProtocol {
    var size: CGSize { get }
}

extension GeometryProxy: GeometryProxyProtocol {}

// MARK: - MockGeometry Helper for Auto-Progression

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
    @StateObject private var videoPreloadingService: VideoPreloadingService
    @StateObject private var cachingService: CachingService
    
    // MARK: - Home Feed State
    
    @State private var currentFeed: [ThreadData] = []
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isShowingPlaceholder: Bool = true
    @State private var hasLoadedInitialFeed: Bool = false
    @State private var loadingError: String? = nil
    @State private var isReshuffling: Bool = false
    
    // ENHANCED Auto-progression tracking
    @State private var videoPlayCounts: [String: Int] = [:]
    @State private var videoStartTimes: [String: Date] = [:]
    @State private var autoProgressTimer: Timer?
    @State private var autoRefreshTimer: Timer?
    @State private var lastUserInteraction: Date = Date()
    @State private var isAutoProgressionEnabled: Bool = true
    @State private var isAutoRefreshEnabled: Bool = true
    
    // Auto-progression configuration
    private let maxPlaysPerVideo = 2
    private let minWatchTimeBeforeProgression: TimeInterval = 3.0
    private let autoRefreshInterval: TimeInterval = 300.0 // 5 minutes
    private let userInactivityThreshold: TimeInterval = 10.0 // 10 seconds
    
    // MARK: - Viewport State
    
    @State private var containerSize: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimating: Bool = false
    @State private var gestureDebouncer: Timer?
    
    // MARK: - STABILIZED GESTURE PHYSICS
    
    // Stricter thresholds for deliberate gestures
    private let gestureMinimumDistance: CGFloat = 35 // Increased from 20
    private let swipeThresholdHorizontal: CGFloat = 120 // Increased from 80
    private let swipeThresholdVertical: CGFloat = 140 // Increased from 100
    private let directionRatio: CGFloat = 2.5 // Increased from 2.0
    private let animationDuration: TimeInterval = 0.25 // Reduced for snappier feel
    
    // Drag resistance for stability
    private let dragResistance: CGFloat = 0.6 // New: reduces flimsy feeling
    private let maxDragDistance: CGFloat = 80 // New: clamps maximum drag
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService? = nil,
        userService: UserService? = nil,
        authService: AuthService? = nil
    ) {
        let videoSvc = videoService ?? VideoService()
        let userSvc = userService ?? UserService()
        let authSvc = authService ?? AuthService()
        let cachingService = CachingService()
        let homeFeedService = HomeFeedService(
            videoService: videoSvc,
            userService: userSvc
        )
        let videoPreloadingService = VideoPreloadingService()
        
        self._videoService = StateObject(wrappedValue: videoSvc)
        self._userService = StateObject(wrappedValue: userSvc)
        self._authService = StateObject(wrappedValue: authSvc)
        self._homeFeedService = StateObject(wrappedValue: homeFeedService)
        self._videoPreloadingService = StateObject(wrappedValue: videoPreloadingService)
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
                
                // Reshuffle indicator overlay
                if isReshuffling {
                    reshuffleOverlay
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
            startAutoProgressionTimer()
            startAutoRefreshTimer()
        }
        .onDisappear {
            stopAutoProgressionTimer()
            stopAutoRefreshTimer()
        }
        .refreshable {
            Task {
                await refreshFeed()
            }
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
    
    // MARK: - STABILIZED Container Grid - Absolute Positioning
    
    private func stabilizedContainerGrid(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Absolute positioned container grid
            ZStack {
                ForEach(Array(currentFeed.enumerated()), id: \.offset) { threadIndex, thread in
                    stabilizedThreadContainer(
                        thread: thread,
                        threadIndex: threadIndex,
                        geometry: geometry
                    )
                }
            }
            // STABILIZED VIEWPORT MOVEMENT - Tighter spring physics
            .offset(
                x: horizontalOffset + (isAnimating ? 0 : dragOffset.width),
                y: verticalOffset + (isAnimating ? 0 : dragOffset.height)
            )
            // IMPROVED SPRING ANIMATIONS - Tighter damping for stability
            .animation(
                isAnimating ?
                .spring(response: 0.25, dampingFraction: 0.95, blendDuration: 0) : // Tighter damping
                nil,
                value: verticalOffset
            )
            .animation(
                isAnimating ?
                .spring(response: 0.25, dampingFraction: 0.95, blendDuration: 0) : // Tighter damping
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
    
    // MARK: - Stabilized Thread Container
    
    private func stabilizedThreadContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            // Parent video container - absolute position
            BoundedVideoContainerView(
                video: thread.parentVideo,
                thread: thread,
                isActive: threadIndex == currentThreadIndex && currentStitchIndex == 0,
                containerID: "\(thread.id)-parent"
            ) { videoID in
                incrementVideoPlayCount(for: videoID)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped() // CRITICAL: Prevent overflow
            .position(
                x: geometry.size.width / 2, // Center horizontally
                y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height) // Stack vertically
            )
            
            // Child video containers - horizontally positioned for swipe navigation
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                BoundedVideoContainerView(
                    video: childVideo,
                    thread: thread,
                    isActive: threadIndex == currentThreadIndex && currentStitchIndex == (childIndex + 1),
                    containerID: "\(thread.id)-child-\(childIndex)"
                ) { videoID in
                    incrementVideoPlayCount(for: videoID)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped() // CRITICAL: Prevent overflow
                .position(
                    x: geometry.size.width / 2 + (CGFloat(childIndex + 1) * geometry.size.width), // Stack horizontally for left/right swipe
                    y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height) // Same vertical level as parent
                )
            }
        }
        .id("\(thread.id)-\(thread.childVideos.count)") // Rebuild when children count changes
    }
    
    // MARK: - ENHANCED Gesture Handling with User Interaction Tracking
    
    private func handleStabilizedDragChanged(value: DragGesture.Value) {
        // Record user interaction
        recordUserInteraction()
        
        // Clear debouncer on active drag
        gestureDebouncer?.invalidate()
        
        // Block gestures during animation or reshuffling
        guard !isAnimating && !isReshuffling else { return }
        
        let translation = value.translation
        
        // Apply drag resistance and clamping for stability
        let resistedTranslation = CGSize(
            width: min(abs(translation.width), maxDragDistance) * dragResistance * (translation.width < 0 ? -1 : 1),
            height: min(abs(translation.height), maxDragDistance) * dragResistance * (translation.height < 0 ? -1 : 1)
        )
        
        let isHorizontalDrag = abs(resistedTranslation.width) > abs(resistedTranslation.height)
        
        if isHorizontalDrag {
            // Check if horizontal movement is allowed (children exist)
            if let thread = getCurrentThread(), !thread.childVideos.isEmpty {
                dragOffset = CGSize(width: resistedTranslation.width, height: 0)
            } else {
                // Block horizontal drag but allow vertical
                dragOffset = CGSize(width: 0, height: resistedTranslation.height)
            }
        } else {
            // Vertical drag only
            dragOffset = CGSize(width: 0, height: resistedTranslation.height)
        }
    }
    
    private func handleStabilizedDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        // Record user interaction
        recordUserInteraction()
        
        let translation = value.translation
        let velocity = value.velocity
        
        // IMPROVED DIRECTION DETECTION with velocity consideration and stricter thresholds
        let velocityBoost = 1.2 // Reduced from 1.5 for more deliberate gestures
        let adjustedTranslation = CGSize(
            width: translation.width + (velocity.width * 0.05), // Reduced velocity influence
            height: translation.height + (velocity.height * 0.05)
        )
        
        // STRICTER THRESHOLDS for more deliberate gestures
        let isHorizontalSwipe = abs(adjustedTranslation.width) > swipeThresholdHorizontal &&
                               abs(adjustedTranslation.width) > abs(adjustedTranslation.height) * directionRatio
        let isVerticalSwipe = abs(adjustedTranslation.height) > swipeThresholdVertical &&
                             abs(adjustedTranslation.height) > abs(adjustedTranslation.width) * directionRatio
        
        // Debounce rapid gestures for stability
        gestureDebouncer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            processStabilizedGesture(
                isHorizontal: isHorizontalSwipe,
                isVertical: isVerticalSwipe,
                translation: adjustedTranslation,
                velocity: velocity,
                geometry: geometry
            )
        }
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
            // Ambiguous gesture - smooth snap back
            smoothSnapToCurrentPosition()
        }
        
        // Reset drag state with tight animation
        withAnimation(.easeOut(duration: 0.15)) {
            dragOffset = .zero
        }
        
        // End animation state
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            isAnimating = false
        }
    }
    
    // MARK: - Navigation Methods with Stabilization
    
    private func handleHorizontalSwipe(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        guard let currentThread = getCurrentThread() else {
            smoothSnapToCurrentPosition()
            return
        }
        
        guard !currentThread.childVideos.isEmpty else {
            smoothSnapToCurrentPosition()
            print("🚫 HORIZONTAL BLOCKED: No children in current thread")
            return
        }
        
        let isSwipeLeft = translation.width < 0  // Left swipe = go to next child/forward
        let isSwipeRight = translation.width > 0 // Right swipe = go to previous child/back
        
        if isSwipeLeft {
            // Go to next child (forward in thread)
            if currentStitchIndex < currentThread.childVideos.count {
                let nextStitchIndex = currentStitchIndex + 1
                smoothMoveToStitch(nextStitchIndex, geometry: geometry)
                print("➡️ MOVED TO: Thread \(currentThreadIndex), Child \(nextStitchIndex)")
            } else {
                // At end of children - snap back
                smoothSnapToCurrentPosition()
                print("📚 AT END: Cannot go further in thread")
            }
        } else if isSwipeRight {
            // Go to previous child (backward in thread)
            if currentStitchIndex > 0 {
                let prevStitchIndex = currentStitchIndex - 1
                smoothMoveToStitch(prevStitchIndex, geometry: geometry)
                print("⬅️ MOVED TO: Thread \(currentThreadIndex), Child \(prevStitchIndex)")
            } else {
                // At parent - snap back
                smoothSnapToCurrentPosition()
                print("🏠 AT PARENT: Cannot go back further in thread")
            }
        }
    }
    
    private func handleVerticalSwipe(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        let isSwipeUp = translation.height < 0    // Up swipe = next thread/forward
        let isSwipeDown = translation.height > 0  // Down swipe = previous thread/back
        
        if isSwipeUp {
            // Move to next thread
            if currentThreadIndex < currentFeed.count - 1 {
                smoothMoveToThread(currentThreadIndex + 1, geometry: geometry)
            } else {
                // Reshuffle when reaching bottom
                reshuffleAndResetFeed()
                print("🔀 REACHED BOTTOM: Reshuffling feed")
            }
        } else if isSwipeDown {
            // Move to previous thread
            if currentThreadIndex > 0 {
                smoothMoveToThread(currentThreadIndex - 1, geometry: geometry)
            } else {
                // At beginning - snap back
                smoothSnapToCurrentPosition()
            }
        }
    }
    
    // MARK: - Smooth Navigation Methods
    
    private func smoothMoveToThread(_ threadIndex: Int, geometry: GeometryProxyProtocol) {
        // Record user interaction if this is manual navigation
        if !(geometry is MockGeometry) {
            recordUserInteraction()
        }
        
        guard threadIndex >= 0 && threadIndex < currentFeed.count else {
            smoothSnapToCurrentPosition()
            return
        }
        
        currentThreadIndex = threadIndex
        currentStitchIndex = 0 // Always start at parent when moving to new thread
        
        // Smooth spring animation with tighter physics
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.95)) {
            verticalOffset = -CGFloat(threadIndex) * geometry.size.height
            horizontalOffset = 0 // Reset horizontal when changing threads
        }
        
        // Reset video play count for new thread
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
        
        // Preload adjacent content
        preloadAdjacentThreads()
        
        print("🎬 MOVED TO THREAD: \(threadIndex)")
    }
    
    private func smoothMoveToStitch(_ stitchIndex: Int, geometry: GeometryProxyProtocol) {
        // Record user interaction if this is manual navigation
        if !(geometry is MockGeometry) {
            recordUserInteraction()
        }
        
        guard let currentThread = getCurrentThread() else {
            smoothSnapToCurrentPosition()
            return
        }
        
        let maxStitchIndex = currentThread.childVideos.count
        guard stitchIndex >= 0 && stitchIndex <= maxStitchIndex else {
            smoothSnapToCurrentPosition()
            return
        }
        
        currentStitchIndex = stitchIndex
        
        // Smooth spring animation with tighter physics
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.95)) {
            horizontalOffset = -CGFloat(stitchIndex) * geometry.size.width
        }
        
        // Reset video play count for new video
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
        
        print("🎯 MOVED TO STITCH: \(stitchIndex) in thread \(currentThreadIndex)")
    }
    
    private func smoothSnapToCurrentPosition() {
        // Smooth return to current position with tight spring
        withAnimation(.spring(response: 0.2, dampingFraction: 0.98)) {
            dragOffset = .zero
        }
        print("↩️ SNAPPED BACK: Staying at Thread \(currentThreadIndex), Child \(currentStitchIndex)")
    }
    
    // MARK: - ENHANCED Auto-Progression System
    
    private func startAutoProgressionTimer() {
        // Start timer that checks every 1 second for progression conditions
        autoProgressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkAutoProgression()
        }
        print("🔄 AUTO-PROGRESSION: Timer started (checks every 1s)")
    }
    
    private func stopAutoProgressionTimer() {
        autoProgressTimer?.invalidate()
        autoProgressTimer = nil
        print("⏹️ AUTO-PROGRESSION: Timer stopped")
    }
    
    private func startAutoRefreshTimer() {
        // Start timer that checks for auto refresh every minute
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            checkAutoRefresh()
        }
        print("🔄 AUTO-REFRESH: Timer started (checks every 60s)")
    }
    
    private func stopAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        print("⏹️ AUTO-REFRESH: Timer stopped")
    }
    
    private func checkAutoProgression() {
        // Don't auto-progress if user recently interacted or auto-progression is disabled
        guard isAutoProgressionEnabled else { return }
        guard Date().timeIntervalSince(lastUserInteraction) > userInactivityThreshold else { return }
        guard let currentVideo = getCurrentVideo() else { return }
        
        let videoID = currentVideo.id
        let playCount = videoPlayCounts[videoID] ?? 0
        let watchTime = getVideoWatchTime(videoID: videoID)
        
        // Check if video has played enough times AND user has watched it long enough
        let shouldProgress = playCount >= maxPlaysPerVideo && watchTime >= minWatchTimeBeforeProgression
        
        if shouldProgress {
            print("⏭️ AUTO-PROGRESS: Advancing after \(playCount) plays, \(watchTime)s watch time")
            autoAdvanceToNext()
        }
    }
    
    private func checkAutoRefresh() {
        // Only auto-refresh if enabled and user has been inactive
        guard isAutoRefreshEnabled else { return }
        guard Date().timeIntervalSince(lastUserInteraction) > userInactivityThreshold else { return }
        
        // Check if enough time has passed since last refresh
        let timeSinceLastRefresh = Date().timeIntervalSince(homeFeedService.getFeedStats().lastRefreshTime ?? Date.distantPast)
        
        if timeSinceLastRefresh > autoRefreshInterval {
            print("🔄 AUTO-REFRESH: Refreshing feed after \(timeSinceLastRefresh)s")
            Task {
                await performAutoRefresh()
            }
        }
    }
    
    private func performAutoRefresh() async {
        guard let currentUserID = authService.currentUserID else { return }
        
        do {
            print("🔄 AUTO-REFRESH: Starting background refresh...")
            let freshThreads = try await homeFeedService.refreshFeed(userID: currentUserID)
            
            await MainActor.run {
                // Only update if we got new content
                if !freshThreads.isEmpty && freshThreads.count != currentFeed.count {
                    currentFeed = freshThreads
                    preloadAdjacentThreads()
                    print("✅ AUTO-REFRESH: Updated feed with \(freshThreads.count) threads")
                }
            }
        } catch {
            print("❌ AUTO-REFRESH: Failed - \(error.localizedDescription)")
        }
    }
    
    private func autoAdvanceToNext() {
        // Create a mock geometry for auto advancement
        let screenBounds = UIScreen.main.bounds
        let mockGeometry = MockGeometry(size: screenBounds.size)
        
        // Try to advance to next child first, then next thread
        guard let currentThread = getCurrentThread() else { return }
        
        if currentStitchIndex < currentThread.childVideos.count {
            // Move to next child
            smoothMoveToStitch(currentStitchIndex + 1, geometry: mockGeometry)
            print("⏭️ AUTO-PROGRESS: Moved to next child (\(currentStitchIndex + 1))")
        } else if currentThreadIndex < currentFeed.count - 1 {
            // Move to next thread
            smoothMoveToThread(currentThreadIndex + 1, geometry: mockGeometry)
            print("⏭️ AUTO-PROGRESS: Moved to next thread (\(currentThreadIndex + 1))")
        } else {
            // Check if we should load more content or reshuffle
            if homeFeedService.shouldLoadMoreContent(currentThreadIndex: currentThreadIndex) {
                loadMoreFeedContent()
            } else {
                reshuffleAndResetFeed()
                print("⏭️ AUTO-PROGRESS: Reshuffling at end of feed")
            }
        }
    }
    
    private func loadMoreFeedContent() {
        guard let currentUserID = authService.currentUserID else { return }
        
        Task {
            do {
                print("📥 LOADING MORE: Fetching additional content...")
                let moreThreads = try await homeFeedService.loadMoreContent(userID: currentUserID)
                
                await MainActor.run {
                    currentFeed = moreThreads
                    print("✅ LOADED MORE: Feed now has \(currentFeed.count) threads")
                }
            } catch {
                print("❌ LOAD MORE ERROR: \(error.localizedDescription)")
                // Fallback to reshuffle if loading more content fails
                reshuffleAndResetFeed()
            }
        }
    }
    
    // MARK: - Enhanced Video Play Count Management
    
    private func incrementVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID, default: 0] += 1
        
        // Track when video started playing
        if videoStartTimes[videoID] == nil {
            videoStartTimes[videoID] = Date()
        }
        
        print("🎥 PLAY COUNT: Video \(videoID) played \(videoPlayCounts[videoID] ?? 0) times")
    }
    
    private func resetVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID] = 0
        videoStartTimes[videoID] = Date()
        print("🔄 RESET COUNT: Video \(videoID) play count reset")
    }
    
    private func getVideoWatchTime(videoID: String) -> TimeInterval {
        guard let startTime = videoStartTimes[videoID] else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - User Interaction Tracking
    
    private func recordUserInteraction() {
        lastUserInteraction = Date()
        print("👆 USER INTERACTION: Recorded at \(lastUserInteraction)")
    }
    
    // MARK: - Auto-Progression Controls
    
    private func toggleAutoProgression() {
        isAutoProgressionEnabled.toggle()
        print("🔄 AUTO-PROGRESSION: \(isAutoProgressionEnabled ? "Enabled" : "Disabled")")
    }
    
    private func toggleAutoRefresh() {
        isAutoRefreshEnabled.toggle()
        print("🔄 AUTO-REFRESH: \(isAutoRefreshEnabled ? "Enabled" : "Disabled")")
    }
    
    // MARK: - Loading and Data Management
    
    private func loadInstantFeed() {
        guard let currentUserID = authService.currentUserID else {
            loadingError = "Please sign in to view your feed"
            return
        }
        
        isShowingPlaceholder = true
        
        Task {
            do {
                print("🚀 HOME FEED: Loading instant feed for user \(currentUserID)")
                
                // Load instant parent threads only
                let threads = try await homeFeedService.loadFeed(userID: currentUserID)
                
                await MainActor.run {
                    currentFeed = threads
                    currentThreadIndex = 0
                    currentStitchIndex = 0
                    isShowingPlaceholder = false
                    loadingError = nil
                    
                    // Reset viewport to first thread
                    verticalOffset = 0
                    horizontalOffset = 0
                }
                
                // Start preloading for smooth playback
                await preloadCurrentAndNext()
                
                print("✅ HOME FEED: Feed loaded with \(threads.count) threads")
                
            } catch {
                await MainActor.run {
                    loadingError = "Failed to load feed: \(error.localizedDescription)"
                    isShowingPlaceholder = false
                }
                print("❌ HOME FEED: Feed loading failed: \(error)")
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
                
                // Reset viewport
                verticalOffset = 0
                horizontalOffset = 0
            }
            
            await preloadCurrentAndNext()
            
        } catch {
            await MainActor.run {
                loadingError = "Failed to refresh feed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Reshuffle Functionality
    
    private func reshuffleAndResetFeed() {
        guard let currentUserID = authService.currentUserID else { return }
        
        isReshuffling = true
        
        Task {
            do {
                print("🔀 RESHUFFLING: Getting new feed order")
                
                // Simulate reshuffling delay
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                await MainActor.run {
                    // Reset to top with new shuffled content
                    currentThreadIndex = 0
                    currentStitchIndex = 0
                    verticalOffset = 0
                    horizontalOffset = 0
                    isReshuffling = false
                    
                    // Clear play counts
                    videoPlayCounts.removeAll()
                    
                    print("✅ RESHUFFLE COMPLETE: Feed reset to top")
                }
            } catch {
                await MainActor.run {
                    isReshuffling = false
                    print("❌ RESHUFFLE ERROR: \(error)")
                }
            }
        }
    }
    
    // MARK: - Preloading Support
    
    private func preloadCurrentAndNext() async {
        if currentThreadIndex < currentFeed.count {
            preloadThreadIfNeeded(index: currentThreadIndex)
        }
        
        if currentThreadIndex + 1 < currentFeed.count {
            preloadThreadIfNeeded(index: currentThreadIndex + 1)
        }
    }
    
    private func preloadThreadIfNeeded(index: Int) {
        guard index >= 0 && index < currentFeed.count else { return }
        
        let thread = currentFeed[index]
        if thread.childVideos.isEmpty {
            print("🔍 PRELOAD: Thread \(thread.id) has no children, attempting to load...")
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
                let children = try await videoService.getThreadChildren(threadID: threadID)
                
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
    
    private var reshufflingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "shuffle.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
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
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}

// MARK: - Actual Video Player Implementation

struct BoundedVideoContainerView: View {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    var body: some View {
        ZStack {
            // Strictly bounded video player
            BoundedVideoPlayer(
                video: video,
                isActive: isActive,
                shouldPlay: isActive,
                onVideoLoop: onVideoLoop
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // CRITICAL: Strict bounds enforcement
            
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
            print("🎬 BOUNDED CONTAINER: \(video.id.prefix(8)) - isActive: \(isActive)")
        }
        .onChange(of: isActive) { _, newValue in
            print("🔄 BOUNDED CONTAINER: \(video.id.prefix(8)) - Active changed to: \(newValue)")
        }
    }
}

struct BoundedVideoPlayer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let isActive: Bool
    let shouldPlay: Bool
    let onVideoLoop: (String) -> Void
    
    func makeUIView(context: Context) -> BoundedVideoUIView {
        let view = BoundedVideoUIView()
        view.onVideoLoop = onVideoLoop
        return view
    }
    
    func updateUIView(_ uiView: BoundedVideoUIView, context: Context) {
        uiView.setupVideo(
            video: video,
            isActive: isActive,
            shouldPlay: shouldPlay
        )
    }
}

class BoundedVideoUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var notificationObserver: NSObjectProtocol?
    private var currentVideoID: String?
    var onVideoLoop: ((String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStrictBounds()
        setupKillObserver()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStrictBounds()
        setupKillObserver()
    }
    
    // FIXED: Strict bounds setup for HomeFeed
    private func setupStrictBounds() {
        backgroundColor = .black
        clipsToBounds = true // CRITICAL: Prevent view overflow
        layer.masksToBounds = true // CRITICAL: Prevent layer overflow
        
        // Create player layer with strict bounds
        playerLayer = AVPlayerLayer()
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.masksToBounds = true // CRITICAL: Prevent player overflow
        layer.addSublayer(playerLayer!)
        
        print("✅ BOUNDED VIDEO: Strict bounds setup complete")
    }
    
    private func setupKillObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(killPlayer),
            name: .RealkillAllVideoPlayers,
            object: nil
        )
    }
    
    @objc private func killPlayer() {
        player?.pause()
        player?.seek(to: .zero)
        print("🛑 BOUNDED VIDEO: Killed player for \(currentVideoID ?? "unknown")")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure player layer exactly matches view bounds
        playerLayer?.frame = bounds
    }
    
    func setupVideo(video: CoreVideoMetadata, isActive: Bool, shouldPlay: Bool) {
        // Only create new player if video changed
        if currentVideoID != video.id {
            cleanupCurrentPlayer()
            
            guard let url = URL(string: video.videoURL) else {
                print("❌ BOUNDED VIDEO: Invalid URL for \(video.id)")
                return
            }
            
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            playerLayer?.player = newPlayer
            currentVideoID = video.id
            
            setupLooping()
            print("🎬 BOUNDED VIDEO: Created bounded player for \(video.id)")
        }
        
        // Control playback based on active state
        if isActive && shouldPlay {
            player?.play()
            print("▶️ BOUNDED VIDEO: Playing \(video.id)")
        } else {
            player?.pause()
            if currentVideoID == video.id {
                print("⏸️ BOUNDED VIDEO: Paused \(video.id)")
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
        ) { [weak self] _ in
            guard let self = self, let currentVideoID = self.currentVideoID else { return }
            
            // Call the loop callback
            self.onVideoLoop?(currentVideoID)
            
            // Restart video
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
        
        print("🗑️ BOUNDED VIDEO: Cleaned up bounded player")
    }
    
    deinit {
        cleanupCurrentPlayer()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NotificationCenter Extension

extension Notification.Name {
    static let RealkillAllVideoPlayers = Notification.Name("killAllVideoPlayers")
}

// MARK: - Preview

struct HomeFeedView_Previews: PreviewProvider {
    static var previews: some View {
        HomeFeedView()
    }
}
