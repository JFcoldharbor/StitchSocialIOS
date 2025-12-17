//
//  HomeFeedView.swift
//  StitchSocial
//
//  MINIMAL VERSION - No background services during swipe
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine
import Network

// MARK: - Debug Helper
private let debug = HomeFeedDebugger.shared

struct HomeFeedView: View {
    
    // MARK: - Services (Minimal)
    
    @StateObject private var homeFeedService = HomeFeedService(
        videoService: VideoService(),
        userService: UserService()
    )
    @StateObject private var authService = AuthService()
    
    // MARK: - Feed State
    
    @State private var currentFeed: [ThreadData] = []
    @State private var currentThreadIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadingError: String? = nil
    
    // MARK: - Gesture State
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var lockedAxis: SwipeAxis? = nil
    
    private enum SwipeAxis {
        case horizontal
        case vertical
    }
    
    // MARK: - Offsets for positioning
    
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var containerSize: CGSize = .zero
    @State private var currentPlaybackTime: TimeInterval = 0
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let error = loadingError {
                    errorView(error: error)
                } else if isLoading {
                    loadingView
                } else if currentFeed.isEmpty {
                    emptyFeedView
                } else {
                    // Simple video grid
                    videoGrid(geometry: geometry)
                }
            }
            .onAppear {
                containerSize = geometry.size
                debug.feedViewAppeared()
                setupAudioSession()
                loadFeed()
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .gesture(swipeGesture)
    }
    
    // MARK: - Video Grid
    
    private func videoGrid(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(currentFeed.enumerated()), id: \.offset) { threadIndex, thread in
                // Debug: Log thread children count
                let _ = {
                    if threadIndex == currentThreadIndex {
                        print("📊 THREAD \(threadIndex): parentID=\(thread.parentVideo.id.prefix(8)), children=\(thread.childVideos.count)")
                    }
                }()
                
                // Parent video
                videoCell(
                    video: thread.parentVideo,
                    thread: thread,
                    isActive: threadIndex == currentThreadIndex && currentStitchIndex == 0,
                    xPos: geometry.size.width / 2,
                    yPos: geometry.size.height / 2 + CGFloat(threadIndex) * geometry.size.height,
                    size: geometry.size
                )
                
                // Child videos (stitches)
                ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, child in
                    videoCell(
                        video: child,
                        thread: thread,
                        isActive: threadIndex == currentThreadIndex && currentStitchIndex == childIndex + 1,
                        xPos: geometry.size.width / 2 + CGFloat(childIndex + 1) * geometry.size.width,
                        yPos: geometry.size.height / 2 + CGFloat(threadIndex) * geometry.size.height,
                        size: geometry.size
                    )
                }
            }
        }
        .offset(
            x: horizontalOffset + dragOffset.width,
            y: verticalOffset + dragOffset.height
        )
    }
    
    private func videoCell(video: CoreVideoMetadata, thread: ThreadData, isActive: Bool, xPos: CGFloat, yPos: CGFloat, size: CGSize) -> some View {
        ZStack {
            Color.black
            
            // Only active video gets a player
            if isActive {
                ActiveVideoPlayer(
                    video: video,
                    onTimeUpdate: { time in
                        currentPlaybackTime = time
                    }
                )
            }
            
            // Overlay
            if isActive {
                ContextualVideoOverlay(
                    video: video,
                    context: .homeFeed,
                    currentUserID: Auth.auth().currentUser?.uid,
                    threadVideo: thread.parentVideo,
                    isVisible: true,
                    actualReplyCount: thread.childVideos.count,
                    onAction: { action in
                        handleOverlayAction(action, video: video, thread: thread)
                    }
                )
                
                // Floating bubble notification for replies
                if currentStitchIndex == 0 && !thread.childVideos.isEmpty {
                    FloatingBubbleNotification.parentVideoWithReplies(
                        videoDuration: video.duration,
                        currentPosition: currentPlaybackTime,
                        replyCount: thread.childVideos.count,
                        currentStitchIndex: currentStitchIndex,
                        onViewReplies: {
                            // Navigate to first stitch
                            moveToNextStitch()
                        },
                        onDismiss: {}
                    )
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .position(x: xPos, y: yPos)
    }
    
    // MARK: - Overlay Action Handler
    
    private func handleOverlayAction(_ action: ContextualOverlayAction, video: CoreVideoMetadata, thread: ThreadData) {
        switch action {
        case .stitch, .reply:
            // Kill all video activity before recording
            killAllVideoActivity(reason: "Stitch/Reply button pressed")
            debug.log(.lifecycle, "Stitch/Reply action - killed all players")
            
        case .thread:
            // Kill all video activity before thread view
            killAllVideoActivity(reason: "Thread view opened")
            debug.log(.lifecycle, "Thread action - killed all players")
            
        case .share:
            // Kill all video activity before sharing
            killAllVideoActivity(reason: "Share button pressed")
            debug.log(.lifecycle, "Share action - killed all players")
            
        case .profile(let userID):
            // Kill all video activity before profile view
            killAllVideoActivity(reason: "Profile opened: \(userID.prefix(8))")
            debug.log(.lifecycle, "Profile action - killed all players")
            
        case .more:
            // Kill all video activity before more menu
            killAllVideoActivity(reason: "More menu opened")
            debug.log(.lifecycle, "More action - killed all players")
            
        default:
            // Other actions (engagement, follow) don't need to kill players
            break
        }
    }
    
    // MARK: - Kill Switch
    
    private func killAllVideoActivity(reason: String) {
        debug.log(.lifecycle, "🛑 KILL SWITCH: \(reason)")
        
        // Clear preload cache
        PreloadCache.shared.clear()
        
        // Post kill notifications
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .pauseAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .stopAllBackgroundActivity, object: nil)
        NotificationCenter.default.post(name: .deactivateAllPlayers, object: nil)
        
        // Also use BackgroundActivityManager if available
        Task { @MainActor in
            BackgroundActivityManager.shared.killAllBackgroundActivity(reason: reason)
        }
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    lockedAxis = nil
                    debug.gestureDragStarted()
                }
                
                // Lock axis after threshold
                if lockedAxis == nil && (abs(value.translation.width) > 15 || abs(value.translation.height) > 15) {
                    lockedAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                
                // Only allow movement on locked axis
                switch lockedAxis {
                case .horizontal:
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                case .vertical:
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                case nil:
                    // Before lock, allow small movement
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                isDragging = false
                let axis = lockedAxis
                lockedAxis = nil
                
                handleSwipeEnd(translation: value.translation, velocity: value.velocity, axis: axis)
                
                // Reset drag offset with animation
                withAnimation(.easeOut(duration: 0.2)) {
                    dragOffset = .zero
                }
            }
    }
    
    private func handleSwipeEnd(translation: CGSize, velocity: CGSize, axis: SwipeAxis?) {
        let horizontalThreshold: CGFloat = 80
        let verticalThreshold: CGFloat = 80
        
        // Use locked axis if available, otherwise determine from translation
        let isHorizontal = axis == .horizontal || (axis == nil && abs(translation.width) > abs(translation.height))
        
        if isHorizontal {
            if translation.width < -horizontalThreshold {
                // Swipe left - next stitch
                moveToNextStitch()
                debug.gestureDragEnded(result: "horizontalLeft")
            } else if translation.width > horizontalThreshold {
                // Swipe right - previous stitch
                moveToPreviousStitch()
                debug.gestureDragEnded(result: "horizontalRight")
            } else {
                debug.gestureDragEnded(result: "cancelled")
            }
        } else {
            if translation.height < -verticalThreshold {
                // Swipe up - next thread
                moveToNextThread()
                debug.gestureDragEnded(result: "verticalUp")
            } else if translation.height > verticalThreshold {
                // Swipe down - previous thread
                moveToPreviousThread()
                debug.gestureDragEnded(result: "verticalDown")
            } else {
                debug.gestureDragEnded(result: "cancelled")
            }
        }
    }
    
    // MARK: - Navigation
    
    private func moveToNextThread() {
        debug.log(.navigation, "moveToNextThread called: current=\(currentThreadIndex), total=\(currentFeed.count)")
        
        guard currentThreadIndex < currentFeed.count - 1 else {
            debug.warning("At end of feed", details: "index \(currentThreadIndex) of \(currentFeed.count)")
            // Trigger load more
            loadMoreContent()
            return
        }
        
        currentThreadIndex += 1
        currentStitchIndex = 0
        currentPlaybackTime = 0  // Reset for new video
        
        withAnimation(.easeOut(duration: 0.25)) {
            verticalOffset = -CGFloat(currentThreadIndex) * containerSize.height
            horizontalOffset = 0
        }
        
        debug.navigationCompleted(toThread: currentThreadIndex, toStitch: currentStitchIndex, videoID: getCurrentVideoID())
        
        // Load children for current thread (and preload next)
        loadChildrenForCurrentThread()
        
        // Preload next 2 videos
        preloadAhead()
        
        // Preemptively load more if near end
        if currentThreadIndex >= currentFeed.count - 3 {
            loadMoreContent()
        }
    }
    
    private func moveToPreviousThread() {
        debug.log(.navigation, "moveToPreviousThread called: current=\(currentThreadIndex)")
        
        guard currentThreadIndex > 0 else {
            debug.warning("At start of feed")
            return
        }
        
        currentThreadIndex -= 1
        currentStitchIndex = 0
        currentPlaybackTime = 0  // Reset for new video
        
        withAnimation(.easeOut(duration: 0.25)) {
            verticalOffset = -CGFloat(currentThreadIndex) * containerSize.height
            horizontalOffset = 0
        }
        
        debug.navigationCompleted(toThread: currentThreadIndex, toStitch: currentStitchIndex, videoID: getCurrentVideoID())
        
        // Load children for current thread
        loadChildrenForCurrentThread()
        
        // Preload next 2 videos
        preloadAhead()
    }
    
    private func moveToNextStitch() {
        guard currentThreadIndex < currentFeed.count else {
            debug.warning("Invalid thread index")
            return
        }
        let thread = currentFeed[currentThreadIndex]
        
        debug.log(.navigation, "moveToNextStitch: current=\(currentStitchIndex), children=\(thread.childVideos.count)")
        
        guard currentStitchIndex < thread.childVideos.count else {
            debug.warning("No more stitches", details: "at \(currentStitchIndex) of \(thread.childVideos.count)")
            return
        }
        
        currentStitchIndex += 1
        
        // Reset playback time for new video
        currentPlaybackTime = 0
        
        withAnimation(.easeOut(duration: 0.25)) {
            horizontalOffset = -CGFloat(currentStitchIndex) * containerSize.width
        }
        
        debug.navigationCompleted(toThread: currentThreadIndex, toStitch: currentStitchIndex, videoID: getCurrentVideoID())
        
        // Preload next 2 videos
        preloadAhead()
    }
    
    private func moveToPreviousStitch() {
        debug.log(.navigation, "moveToPreviousStitch: current=\(currentStitchIndex)")
        
        guard currentStitchIndex > 0 else {
            debug.warning("At first stitch")
            return
        }
        
        currentStitchIndex -= 1
        
        // Reset playback time for new video
        currentPlaybackTime = 0
        
        withAnimation(.easeOut(duration: 0.25)) {
            horizontalOffset = -CGFloat(currentStitchIndex) * containerSize.width
        }
        
        debug.navigationCompleted(toThread: currentThreadIndex, toStitch: currentStitchIndex, videoID: getCurrentVideoID())
    }
    
    // MARK: - Preloading (2 videos ahead only)
    
    private func preloadAhead() {
        // Get next 2 videos to preload
        var videosToPreload: [CoreVideoMetadata] = []
        
        let thread = currentFeed[currentThreadIndex]
        
        // If on parent (stitch 0), preload first child and next thread's parent
        if currentStitchIndex == 0 {
            // First child of current thread
            if !thread.childVideos.isEmpty {
                videosToPreload.append(thread.childVideos[0])
            }
            // Next thread's parent
            if currentThreadIndex + 1 < currentFeed.count {
                videosToPreload.append(currentFeed[currentThreadIndex + 1].parentVideo)
            }
        } else {
            // On a child, preload next child or next thread
            let childIndex = currentStitchIndex - 1
            if childIndex + 1 < thread.childVideos.count {
                videosToPreload.append(thread.childVideos[childIndex + 1])
            }
            if currentThreadIndex + 1 < currentFeed.count {
                videosToPreload.append(currentFeed[currentThreadIndex + 1].parentVideo)
            }
        }
        
        // Preload (max 2)
        for video in videosToPreload.prefix(2) {
            PreloadCache.shared.preload(video: video)
        }
    }
    
    private func getCurrentVideoID() -> String {
        guard currentThreadIndex < currentFeed.count else { return "unknown" }
        let thread = currentFeed[currentThreadIndex]
        if currentStitchIndex == 0 {
            return thread.parentVideo.id
        } else if currentStitchIndex - 1 < thread.childVideos.count {
            return thread.childVideos[currentStitchIndex - 1].id
        }
        return "unknown"
    }
    
    // MARK: - Feed Loading
    
    @State private var isLoadingMore = false
    
    private func loadFeed() {
        debug.feedLoadStarted(source: "initial")
        
        Task {
            do {
                guard let userID = Auth.auth().currentUser?.uid else {
                    await MainActor.run {
                        loadingError = "Not logged in"
                        isLoading = false
                    }
                    return
                }
                
                let threads = try await homeFeedService.loadFeed(userID: userID, limit: 15)
                
                await MainActor.run {
                    currentFeed = threads
                    isLoading = false
                    debug.feedLoadCompleted(threadCount: threads.count, source: "network")
                    
                    // Load children for first few threads
                    loadChildrenForCurrentThread()
                    
                    // Preload first 2 videos after current
                    preloadAhead()
                }
            } catch {
                await MainActor.run {
                    loadingError = error.localizedDescription
                    isLoading = false
                    debug.feedLoadFailed(error: error)
                }
            }
        }
    }
    
    // MARK: - Load Thread Children
    
    private func loadChildrenForCurrentThread() {
        guard currentThreadIndex < currentFeed.count else { return }
        
        let thread = currentFeed[currentThreadIndex]
        
        // Skip if already has children
        guard thread.childVideos.isEmpty else {
            debug.log(.feed, "Thread \(thread.id.prefix(8)) already has \(thread.childVideos.count) children")
            return
        }
        
        debug.log(.feed, "Loading children for thread \(thread.id.prefix(8))...")
        
        Task {
            do {
                let children = try await homeFeedService.loadThreadChildren(threadID: thread.id)
                
                await MainActor.run {
                    // Update the thread with children
                    if let index = currentFeed.firstIndex(where: { $0.id == thread.id }) {
                        currentFeed[index] = ThreadData(
                            id: thread.id,
                            parentVideo: thread.parentVideo,
                            childVideos: children
                        )
                        debug.log(.feed, "✅ Loaded \(children.count) children for thread \(thread.id.prefix(8))")
                    }
                }
            } catch {
                debug.error("Failed to load children: \(error.localizedDescription)")
            }
        }
        
        // Also preload next thread's children
        if currentThreadIndex + 1 < currentFeed.count {
            let nextThread = currentFeed[currentThreadIndex + 1]
            if nextThread.childVideos.isEmpty {
                Task {
                    do {
                        let children = try await homeFeedService.loadThreadChildren(threadID: nextThread.id)
                        await MainActor.run {
                            if let index = currentFeed.firstIndex(where: { $0.id == nextThread.id }) {
                                currentFeed[index] = ThreadData(
                                    id: nextThread.id,
                                    parentVideo: nextThread.parentVideo,
                                    childVideos: children
                                )
                                debug.log(.feed, "✅ Preloaded \(children.count) children for next thread")
                            }
                        }
                    } catch {
                        // Silent fail for preload
                    }
                }
            }
        }
    }
    
    private func loadMoreContent() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        debug.log(.feed, "Loading more content...")
        
        Task {
            do {
                guard let userID = Auth.auth().currentUser?.uid else { return }
                
                let moreThreads = try await homeFeedService.loadMoreContent(userID: userID)
                
                await MainActor.run {
                    if !moreThreads.isEmpty {
                        currentFeed.append(contentsOf: moreThreads)
                        debug.log(.feed, "Added \(moreThreads.count) threads, total: \(currentFeed.count)")
                    } else {
                        debug.warning("No more content available")
                    }
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    debug.error("Load more failed: \(error.localizedDescription)")
                    isLoadingMore = false
                }
            }
        }
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("❌ Audio session error: \(error)")
        }
    }
    
    // MARK: - UI States
    
    private var loadingView: some View {
        ZStack {
            Color.black
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text("Error")
                .font(.title2)
                .foregroundColor(.white)
            Text(error)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var emptyFeedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No Videos")
                .font(.title2)
                .foregroundColor(.white)
        }
    }
}

// MARK: - ActiveVideoPlayer (Only created for active video)

struct ActiveVideoPlayer: View {
    let video: CoreVideoMetadata
    var onTimeUpdate: ((TimeInterval) -> Void)?
    
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var hasError = false
    @State private var timeObserver: Any?
    @State private var isKilled = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                
                if hasError {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Failed to load")
                            .foregroundColor(.white)
                    }
                } else if let player = player, !isKilled {
                    // Show player immediately - even before ready
                    // AVPlayer will show first frame as soon as it buffers
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                }
                // No loading spinner - just black until player appears
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            destroyPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .killAllVideoPlayers)) { _ in
            killPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("killAllVideoPlayers"))) { _ in
            killPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PauseAllVideos"))) { _ in
            player?.pause()
        }
    }
    
    private func killPlayer() {
        print("🛑 ActiveVideoPlayer: Kill signal received for \(video.id.prefix(8))")
        isKilled = true
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        // Remove time observer
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        player = nil
        isReady = false
    }
    
    private func setupPlayer() {
        // Check preload cache first
        if let preloaded = PreloadCache.shared.getPlayer(for: video.id) {
            player = preloaded
            preloaded.seek(to: .zero)
            preloaded.play()
            isReady = true
            setupTimeObserver(for: preloaded)
            return
        }
        
        // Create fresh player
        createFreshPlayer()
    }
    
    private func createFreshPlayer() {
        guard let url = URL(string: video.videoURL), !video.videoURL.isEmpty else {
            hasError = true
            return
        }
        
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        
        // Show player immediately
        player = newPlayer
        
        // Start playing as soon as possible
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                if status == .readyToPlay {
                    isReady = true
                    newPlayer.play()
                    setupTimeObserver(for: newPlayer)
                } else if status == .failed {
                    hasError = true
                }
            }
            .store(in: &cancellables)
        
        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        // Remove existing observer
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Add new observer for playback time
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            onTimeUpdate?(time.seconds)
        }
    }
    
    private func destroyPlayer() {
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Don't destroy if it came from preload cache - just pause
        if PreloadCache.shared.hasPlayer(for: video.id) {
            player?.pause()
        } else {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        player = nil
        isReady = false
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Minimal Preload Cache (Max 2 players)

class PreloadCache {
    static let shared = PreloadCache()
    
    private var cache: [String: AVPlayer] = [:]
    private var order: [String] = [] // Track insertion order for eviction
    private let maxPlayers = 2
    private let queue = DispatchQueue(label: "preload.cache")
    
    private init() {
        // Listen for kill notifications
        NotificationCenter.default.addObserver(
            forName: .killAllVideoPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clear()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("killAllVideoPlayers"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clear()
        }
    }
    
    func preload(video: CoreVideoMetadata) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Skip if already cached
            if self.cache[video.id] != nil { return }
            
            guard let url = URL(string: video.videoURL) else { return }
            
            // Evict oldest if at capacity
            if self.cache.count >= self.maxPlayers, let oldest = self.order.first {
                self.evict(videoID: oldest)
            }
            
            // Create player
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            
            // Store
            self.cache[video.id] = player
            self.order.append(video.id)
            
            print("🎬 PRELOAD: Cached \(video.id.prefix(8)) (\(self.cache.count)/\(self.maxPlayers))")
        }
    }
    
    func getPlayer(for videoID: String) -> AVPlayer? {
        queue.sync {
            if let player = cache[videoID] {
                // Move to end of order (most recently used)
                order.removeAll { $0 == videoID }
                order.append(videoID)
                print("⚡ PRELOAD: Hit for \(videoID.prefix(8))")
                return player
            }
            return nil
        }
    }
    
    func hasPlayer(for videoID: String) -> Bool {
        queue.sync { cache[videoID] != nil }
    }
    
    private func evict(videoID: String) {
        if let player = cache[videoID] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            cache.removeValue(forKey: videoID)
            order.removeAll { $0 == videoID }
            print("🗑️ PRELOAD: Evicted \(videoID.prefix(8))")
        }
    }
    
    func clear() {
        queue.async { [weak self] in
            self?.cache.values.forEach { player in
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            self?.cache.removeAll()
            self?.order.removeAll()
            print("🗑️ PRELOAD: Cleared all")
        }
    }
}
