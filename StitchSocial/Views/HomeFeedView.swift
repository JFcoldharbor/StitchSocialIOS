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
    
    // MARK: - OPTIMIZED GESTURE PHYSICS
    
    // Reduce calculations for smoother performance
    private let gestureMinimumDistance: CGFloat = 30 // Reduced from 35
    private let swipeThresholdHorizontal: CGFloat = 100 // Reduced from 120
    private let swipeThresholdVertical: CGFloat = 120 // Reduced from 140
    private let directionRatio: CGFloat = 2.0 // Reduced from 2.5
    private let animationDuration: TimeInterval = 0.2 // Reduced from 0.25
    
    // Simplified drag resistance
    private let dragResistance: CGFloat = 0.8 // Increased from 0.6 for less resistance
    private let maxDragDistance: CGFloat = 60 // Reduced from 80
    
    // MARK: - Initialization
    
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
        }
        .killBackgroundOnAppear(.stitches)
        .onDisappear {
            // Cleanup if needed
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
                containerID: "\(thread.id)-parent",
                onVideoLoop: { videoID in
                    incrementVideoPlayCount(for: videoID)
                },
                onVideoPositionUpdate: { position in
                    // Just log position for debugging - notification is handled in container
                    if threadIndex == currentThreadIndex && currentStitchIndex == 0 {
                        // Log position updates for active parent video only
                    }
                }
            )
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
                    containerID: "\(thread.id)-child-\(childIndex)",
                    onVideoLoop: { videoID in
                        incrementVideoPlayCount(for: videoID)
                    },
                    onVideoPositionUpdate: { position in
                        // Child videos don't need notification logic
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped() // CRITICAL: Prevent overflow
                .position(
                    x: geometry.size.width / 2 + (CGFloat(childIndex + 1) * geometry.size.width), // Stack horizontally for left/right swipe
                    y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height) // Same vertical level as parent
                )
            }
        }
        .id("\(thread.id)-\(thread.childVideos.count)") // Only rebuild when children change
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
        
        // Simplified drag resistance calculation
        let resistedWidth = min(abs(translation.width), maxDragDistance) * dragResistance * (translation.width < 0 ? -1 : 1)
        let resistedHeight = min(abs(translation.height), maxDragDistance) * dragResistance * (translation.height < 0 ? -1 : 1)
        
        // Quick direction check
        if abs(resistedWidth) > abs(resistedHeight) {
            // Check if horizontal movement is allowed (children exist)
            if let thread = getCurrentThread(), !thread.childVideos.isEmpty {
                dragOffset = CGSize(width: resistedWidth, height: 0)
            } else {
                dragOffset = CGSize(width: 0, height: resistedHeight)
            }
        } else {
            // Vertical drag only
            dragOffset = CGSize(width: 0, height: resistedHeight)
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
                print("🔚 AT END: Cannot go further in thread")
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
                // Check if we should load more content or reshuffle
                if shouldTriggerScrollLoad() {
                    loadMoreContentAndContinue()
                } else {
                    // At end with no more content - stay at current position
                    smoothSnapToCurrentPosition()
                }
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
        // Record user interaction
        recordUserInteraction()
        
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
        
        // Check if we should load more content based on scroll position
        // Only check every 3rd navigation to reduce overhead
        if peopleFinderTriggerCount % 3 == 0 {
            checkScrollBasedLoading()
        }
        
        // Track navigation for people finder less frequently
        // Only check every 5th navigation instead of every navigation
        if peopleFinderTriggerCount % 5 == 0 {
            trackNavigationForPeopleFinder()
        }
        
        peopleFinderTriggerCount += 1
        
        print("🎬 MOVED TO THREAD: \(threadIndex) - Videos should now activate")
    }
    
    private func smoothMoveToStitch(_ stitchIndex: Int, geometry: GeometryProxyProtocol) {
        // Record user interaction
        recordUserInteraction()
        
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
    
    // MARK: - Enhanced Content Loading with Updated Service Methods
    
    private func loadMoreContentAndContinue() {
        guard let currentUserID = authService.currentUserID else { return }
        
        Task {
            do {
                print("📤 LOADING MORE: Fetching content...")
                
                // Use updated HomeFeedService method for better content loading
                let updatedFeed = try await homeFeedService.getReshuffledFeed(userID: currentUserID)
                
                await MainActor.run {
                    if updatedFeed.count > currentFeed.count {
                        // Got new content - replace feed to avoid double cycling
                        currentFeed = updatedFeed
                        // Stay at current position in the updated feed
                        currentThreadIndex = min(currentThreadIndex, currentFeed.count - 1)
                        print("✅ LOADED MORE: Updated feed with \(updatedFeed.count) threads")
                        
                        // Trigger preloading for new content
                        preloadAdjacentThreads()
                    }
                }
                
                // Handle no new content case outside MainActor.run
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
                // Use existing refreshFeed method directly
                await refreshFeed()
            }
        }
    }
    
    // MARK: - Smart Scroll-Based Loading
    
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
        let triggerThreshold = 5 // Load more when 5 threads remaining
        
        return remainingThreads <= triggerThreshold &&
               !homeFeedService.isLoading
    }
    
    // MARK: - Intelligent Reshuffle with Diversification
    
    private func intelligentReshuffleAndResetFeed() {
        guard let currentUserID = authService.currentUserID else { return }
        
        isReshuffling = true
        
        Task {
            do {
                print("🔀 INTELLIGENT RESHUFFLE: Creating diverse content mix...")
                
                // Get fresh content with intelligent diversification
                let freshThreads = try await homeFeedService.refreshFeed(userID: currentUserID)
                
                // Simulate processing time for better UX
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                await MainActor.run {
                    // Replace entire feed with diversified content
                    currentFeed = freshThreads
                    currentThreadIndex = 0
                    currentStitchIndex = 0
                    verticalOffset = 0
                    horizontalOffset = 0
                    isReshuffling = false
                    
                    // Clear play counts for fresh start
                    videoPlayCounts.removeAll()
                    
                    print("✅ INTELLIGENT RESHUFFLE COMPLETE: Diverse feed with \(freshThreads.count) threads")
                }
                
                // Preload first few threads
                await preloadCurrentAndNext()
                
            } catch {
                await MainActor.run {
                    isReshuffling = false
                    loadingError = "Failed to refresh content: \(error.localizedDescription)"
                    print("❌ INTELLIGENT RESHUFFLE ERROR: \(error)")
                }
            }
        }
    }
    
    // MARK: - Content Loading and Management
    
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
    
    // MARK: - People Finder Integration
    
    /// Check if user should see people finder based on engagement patterns
    private func checkPeopleFinderEligibility() {
        guard let currentUserID = authService.currentUserID else { return }
        
        // Simple heuristic: check current feed size and following activity
        // If user has very few threads in feed, suggest people finder
        let shouldShow = currentFeed.count < 3 ||
                        peopleFinderTriggerCount % 20 == 0
        
        if shouldShow && !shouldShowPeopleFinderPrompt {
            shouldShowPeopleFinderPrompt = true
            print("👥 PEOPLE FINDER: Triggered - Feed size: \(currentFeed.count), Count: \(peopleFinderTriggerCount)")
        }
    }
    
    /// Track navigation for people finder triggers
    private func trackNavigationForPeopleFinder() {
        peopleFinderTriggerCount += 1
        
        // Check for discovery trigger every 20 views
        if peopleFinderTriggerCount % 20 == 0 {
            checkPeopleFinderEligibility()
        }
    }
    
    /// People Finder Prompt Overlay
    private var peopleFinderPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.cyan)
                
                // Title
                Text("Discover New Creators")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // Description
                Text("Follow more creators to see diverse content in your feed")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Buttons
                HStack(spacing: 16) {
                    Button("Maybe Later") {
                        shouldShowPeopleFinderPrompt = false
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Find People") {
                        shouldShowPeopleFinderPrompt = false
                        showingPeopleFinder = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .fontWeight(.semibold)
                }
            }
            .padding(30)
            .background(Color.black.opacity(0.9))
            .cornerRadius(20)
            .shadow(radius: 20)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowPeopleFinderPrompt)
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

// MARK: - People Finder View Integration

struct PeopleFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchViewModel = SearchViewModel()
    @State private var selectedTab: SearchTab = .users
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("Find People to Follow")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
                .padding()
                .background(Color.black)
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search for people...", text: $searchViewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Content
                if searchViewModel.searchText.isEmpty {
                    // Show "People You May Know" when no search
                    peopleYouMayKnowSection
                } else {
                    // Show search results
                    searchResultsSection
                }
            }
            .background(Color.black)
            .onChange(of: searchViewModel.searchText) { _, newValue in
                if !newValue.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if searchViewModel.searchText == newValue {
                            searchViewModel.performSearch()
                        }
                    }
                }
            }
        }
    }
    
    private var peopleYouMayKnowSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("People You May Know")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)
                
                if searchViewModel.isLoadingSuggestions {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(searchViewModel.suggestedUsers, id: \.id) { user in
                            PeopleFinderUserRow(
                                user: user,
                                followManager: searchViewModel.followManager
                            )
                        }
                    }
                }
            }
            .padding(.top)
        }
    }
    
    private var searchResultsSection: some View {
        ScrollView {
            if searchViewModel.isSearching {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(searchViewModel.userResults, id: \.id) { user in
                        PeopleFinderUserRow(
                            user: user,
                            followManager: searchViewModel.followManager
                        )
                    }
                }
            }
        }
    }
}

// MARK: - People Finder User Row Component

struct PeopleFinderUserRow: View {
    let user: BasicUserInfo
    @ObservedObject var followManager: FollowManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                if !user.displayName.isEmpty {
                    Text(user.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Follow button
            Button(action: {
                Task {
                    await followManager.toggleFollow(for: user.id)
                }
            }) {
                Text(followManager.isFollowing(user.id) ? "Following" : "Follow")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(followManager.isFollowing(user.id) ? .white : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(followManager.isFollowing(user.id) ? Color.gray.opacity(0.3) : Color.cyan)
                    .cornerRadius(20)
            }
            .disabled(followManager.isLoading(user.id))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Actual Video Player Implementation

struct BoundedVideoContainerView: View {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    let onVideoPositionUpdate: (TimeInterval) -> Void // Add position callback
    
    @EnvironmentObject var authService: AuthService
    @State private var currentVideoPosition: TimeInterval = 0
    @State private var previousActiveState: Bool = false
    
    private var isParentVideo: Bool {
        containerID.contains("-parent")
    }
    
    var body: some View {
        ZStack {
            // Strictly bounded video player
            BoundedVideoPlayer(
                video: video,
                isActive: isActive,
                shouldPlay: isActive,
                onVideoLoop: onVideoLoop,
                currentVideoPosition: $currentVideoPosition
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
        .onChange(of: isActive) { oldValue, newValue in
            if newValue != previousActiveState {
                previousActiveState = newValue
                if newValue {
                    print("▶️ CONTAINER ACTIVATED: \(video.id.prefix(8))")
                } else {
                    print("⏸️ CONTAINER DEACTIVATED: \(video.id.prefix(8))")
                }
            }
        }
        .onChange(of: currentVideoPosition) { _, newPosition in
            // Pass video position to parent
            onVideoPositionUpdate(newPosition)
        }
        .onChange(of: video.id) { _, _ in
            // Reset position when video changes
            currentVideoPosition = 0
        }
        .onAppear {
            previousActiveState = isActive
        }
    }
}

struct BoundedVideoPlayer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let isActive: Bool
    let shouldPlay: Bool
    let onVideoLoop: (String) -> Void
    @Binding var currentVideoPosition: TimeInterval
    
    func makeUIView(context: Context) -> BoundedVideoUIView {
        let view = BoundedVideoUIView()
        view.onVideoLoop = onVideoLoop
        view.onVideoPositionUpdate = { position in
            DispatchQueue.main.async {
                currentVideoPosition = position
            }
        }
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
    private var timeObserver: Any?
    private var currentVideoID: String?
    private var lastShouldPlay: Bool = false
    var onVideoLoop: ((String) -> Void)?
    var onVideoPositionUpdate: ((TimeInterval) -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    func setupVideo(video: CoreVideoMetadata, isActive: Bool, shouldPlay: Bool) {
        let actualShouldPlay = shouldPlay && isActive
        
        // If same video, just update playback state
        if currentVideoID == video.id {
            if lastShouldPlay != actualShouldPlay {
                updatePlaybackState(shouldPlay: actualShouldPlay)
                lastShouldPlay = actualShouldPlay
            }
            return
        }
        
        // Setup new video
        cleanupCurrentPlayer()
        currentVideoID = video.id
        lastShouldPlay = actualShouldPlay
        
        guard let url = URL(string: video.videoURL) else { return }
        
        // Create player and layer - keep existing for smooth preloading
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = bounds
        
        if let playerLayer = playerLayer {
            layer.addSublayer(playerLayer)
        }
        
        // Setup observers
        setupVideoEndObserver()
        setupTimeObserver()
        
        // Set initial playback state
        updatePlaybackState(shouldPlay: actualShouldPlay)
    }
    
    private func updatePlaybackState(shouldPlay: Bool) {
        guard let player = player else { return }
        
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }
    
    private func setupVideoEndObserver() {
        guard let player = player else { return }
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleVideoEnd()
        }
    }
    
    private func handleVideoEnd() {
        guard let videoID = currentVideoID else { return }
        onVideoLoop?(videoID)
        player?.seek(to: .zero)
        if lastShouldPlay {
            player?.play()
        }
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            let currentPosition = CMTimeGetSeconds(time)
            self?.onVideoPositionUpdate?(currentPosition)
        }
    }
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        currentVideoID = nil
        lastShouldPlay = false
    }
    
    deinit {
        cleanupCurrentPlayer()
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
