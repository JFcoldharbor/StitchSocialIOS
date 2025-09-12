import SwiftUI
import AVFoundation
import Combine

// MARK: - HomeFeedView

struct HomeFeedView: View {
    
    // MARK: - Service Dependencies (Unchanged)
    
    @StateObject private var videoService: VideoService
    @StateObject private var userService: UserService
    @StateObject private var authService: AuthService
    @StateObject private var homeFeedService: HomeFeedService
    @StateObject private var videoPreloadingService: VideoPreloadingService
    @StateObject private var cachingService: CachingService
    
    // MARK: - Home Feed State (Unchanged)
    
    @State private var currentFeed: [ThreadData] = []
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isShowingPlaceholder: Bool = true
    @State private var hasLoadedInitialFeed: Bool = false
    @State private var loadingError: String? = nil
    
    // MARK: - Viewport State (Unchanged)
    
    @State private var containerSize: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimating: Bool = false
    
    // MARK: - Debug State REMOVED
    // @State private var isDebugging: Bool = true  // REMOVED
    
    // MARK: - Initialization (Unchanged)
    
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

    // MARK: - Main UI (Debug Overlay Removed)
    
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
    
    // MARK: - FIXED Container Grid View - Absolute Positioning (Debug Overlay Removed)
    
    private func containerGridView(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // FIXED: Absolute positioned container grid
            ZStack {
                ForEach(Array(currentFeed.enumerated()), id: \.offset) { threadIndex, thread in
                    // FIXED: Use absolute container positioning instead of HStack
                    absolutePositionedThreadContainers(
                        thread: thread,
                        threadIndex: threadIndex,
                        geometry: geometry
                    )
                }
            }
            // Viewport movement - move entire grid
            .offset(
                x: horizontalOffset + dragOffset.width,
                y: verticalOffset + dragOffset.height
            )
            .animation(isAnimating ? .easeInOut(duration: 0.3) : nil, value: verticalOffset)
            .animation(isAnimating ? .easeInOut(duration: 0.25) : nil, value: horizontalOffset)
            
            // DEBUG OVERLAY REMOVED - No longer showing debug information
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
    
    // MARK: - FIXED Absolute Positioned Thread Containers
    
    private func absolutePositionedThreadContainers(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            // FIXED: Parent video container - absolute position
            BoundedVideoContainer(
                video: thread.parentVideo,
                thread: thread,
                isActive: threadIndex == currentThreadIndex && currentStitchIndex == 0,
                containerID: "\(thread.id)-parent"
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped() // CRITICAL: Prevent overflow
            .position(
                x: geometry.size.width / 2, // Center horizontally
                y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height) // Stack vertically
            )
            
            // FIXED: Child video containers - horizontally positioned for swipe navigation
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                BoundedVideoContainer(
                    video: childVideo,
                    thread: thread,
                    isActive: threadIndex == currentThreadIndex && currentStitchIndex == (childIndex + 1),
                    containerID: "\(thread.id)-child-\(childIndex)"
                )
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
    
    // MARK: - Helper Functions (Unchanged)
    
    private func getCurrentThread() -> ThreadData? {
        guard currentThreadIndex >= 0 && currentThreadIndex < currentFeed.count else {
            return nil
        }
        return currentFeed[currentThreadIndex]
    }
    
    // MARK: - Bounded Video Container Components
    
    private struct BoundedVideoContainer: View {
        let video: CoreVideoMetadata
        let thread: ThreadData
        let isActive: Bool
        let containerID: String
        
        var body: some View {
            ZStack {
                // FIXED: Strictly bounded video player
                BoundedContainerVideoPlayer(
                    video: video,
                    isActive: isActive,
                    shouldPlay: isActive
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
    
    private struct BoundedContainerVideoPlayer: UIViewRepresentable {
        let video: CoreVideoMetadata
        let isActive: Bool
        let shouldPlay: Bool
        
        func makeUIView(context: Context) -> BoundedContainerVideoUIView {
            let view = BoundedContainerVideoUIView()
            return view
        }
        
        func updateUIView(_ uiView: BoundedContainerVideoUIView, context: Context) {
            uiView.setupVideo(
                video: video,
                isActive: isActive,
                shouldPlay: shouldPlay
            )
        }
    }
    
    private class BoundedContainerVideoUIView: UIView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        private var notificationObserver: NSObjectProtocol?
        private var currentVideoID: String?
        
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
        
        // FIXED: Strict bounds setup
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
                name: .killAllVideoPlayers,
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
            // FIXED: Ensure player layer exactly matches view bounds
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
            
            print("🗑️ BOUNDED VIDEO: Cleaned up bounded player")
        }
        
        deinit {
            cleanupCurrentPlayer()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // MARK: - Viewport Movement Gesture Handling (Unchanged)
    
    private func handleDragChanged(value: DragGesture.Value) {
        // Add debug logging for children count
        if let thread = getCurrentThread() {
            print("🔍 DRAG DEBUG: Thread \(thread.id.prefix(8)) has \(thread.childVideos.count) children")
        }
        
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
        let horizontalThreshold: CGFloat = 60  // INCREASED: More deliberate swipe needed
        let verticalThreshold: CGFloat = 120   // INCREASED: More deliberate swipe needed
        
        // TIGHTENED: More restrictive direction detection
        let isHorizontalSwipe = abs(translation.width) > horizontalThreshold && abs(translation.width) > abs(translation.height) * 1.3
        let isVerticalSwipe = abs(translation.height) > verticalThreshold && abs(translation.height) > abs(translation.width) * 1.3
        
        isAnimating = true
        
        if isHorizontalSwipe {
            handleHorizontalSwipe(translation: translation, velocity: velocity, geometry: geometry)
        } else if isVerticalSwipe {
            handleVerticalSwipe(translation: translation, velocity: velocity, geometry: geometry)
        } else {
            // No clear swipe direction - snap back to current position
            snapToCurrentPosition()
        }
        
        // Reset drag state
        dragOffset = .zero
        
        // End animation after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isAnimating = false
        }
    }
    
    private func handleHorizontalSwipe(translation: CGSize, velocity: CGSize, geometry: GeometryProxy) {
        guard let currentThread = getCurrentThread() else {
            snapToCurrentPosition()
            return
        }
        
        // FIRST check if current thread has children at all
        if currentThread.childVideos.isEmpty {
            print("🚫 HORIZONTAL BLOCKED: No children in current thread")
            snapToCurrentPosition()
            return
        }
        
        let isSwipeLeft = translation.width < 0  // Left swipe = go to next child/forward
        let isSwipeRight = translation.width > 0 // Right swipe = go to previous child/back
        
        if isSwipeLeft {
            // Go to next child (forward in thread)
            if currentStitchIndex < currentThread.childVideos.count {
                let nextStitchIndex = currentStitchIndex + 1
                moveToStitch(nextStitchIndex, geometry: geometry)
                print("➡️ MOVED TO: Thread \(currentThreadIndex), Child \(nextStitchIndex)")
            } else {
                // At end of children - snap back
                snapToCurrentPosition()
                print("🔚 AT END: Cannot go further in thread")
            }
        } else if isSwipeRight {
            // Go to previous child (backward in thread)
            if currentStitchIndex > 0 {
                let prevStitchIndex = currentStitchIndex - 1
                moveToStitch(prevStitchIndex, geometry: geometry)
                print("⬅️ MOVED TO: Thread \(currentThreadIndex), Child \(prevStitchIndex)")
            } else {
                // At parent - snap back
                snapToCurrentPosition()
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
                moveToThread(currentThreadIndex + 1, geometry: geometry)
            } else {
                // At end - try to load more content
                loadMoreContentIfNeeded()
                snapToCurrentPosition()
            }
        } else if isSwipeDown {
            // Move to previous thread
            if currentThreadIndex > 0 {
                moveToThread(currentThreadIndex - 1, geometry: geometry)
            } else {
                // At beginning - snap back
                snapToCurrentPosition()
            }
        }
    }
    
    private func moveToThread(_ threadIndex: Int, geometry: GeometryProxy) {
        guard threadIndex >= 0 && threadIndex < currentFeed.count else { return }
        
        currentThreadIndex = threadIndex
        currentStitchIndex = 0 // Always start at parent when moving to new thread
        
        // Calculate viewport position
        verticalOffset = -CGFloat(threadIndex) * geometry.size.height
        horizontalOffset = 0 // Always start at parent (left edge)
        
        preloadThreadIfNeeded(index: threadIndex)
        
        print("🎬 MOVED TO THREAD: \(threadIndex)")
    }
    
    private func moveToStitch(_ stitchIndex: Int, geometry: GeometryProxy) {
        guard let currentThread = getCurrentThread() else { return }
        
        // Validate stitch index
        let maxStitchIndex = currentThread.childVideos.count // 0 = parent, 1+ = children
        guard stitchIndex >= 0 && stitchIndex <= maxStitchIndex else {
            snapToCurrentPosition()
            return
        }
        
        currentStitchIndex = stitchIndex
        
        // Calculate horizontal offset
        horizontalOffset = -CGFloat(stitchIndex) * geometry.size.width
        
        print("🎯 MOVED TO STITCH: \(stitchIndex) in thread \(currentThreadIndex)")
    }
    
    private func snapToCurrentPosition() {
        // No change needed - current offsets are correct
        print("↩️ SNAPPED BACK: Staying at Thread \(currentThreadIndex), Child \(currentStitchIndex)")
    }
    
    private func loadMoreContentIfNeeded() {
        guard let currentUserID = authService.currentUserID else { return }
        
        Task {
            do {
                let moreThreads = try await homeFeedService.loadMoreContent(userID: currentUserID)
                
                await MainActor.run {
                    currentFeed = moreThreads
                }
            } catch {
                print("❌ LOAD MORE ERROR: \(error)")
            }
        }
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
    
    // MARK: - Error Handling Views
    
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
