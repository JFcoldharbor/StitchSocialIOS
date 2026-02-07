//
//  HomeFeedView.swift
//  StitchSocial
//
//  TikTok-style feed with VideoPlayerComponent + axis-locking gestures
//  Combines proven gesture handling with clean VideoPlayerComponent architecture
//

import SwiftUI
import FirebaseAuth
import Combine
import AVFoundation
import AVKit

@MainActor
struct HomeFeedView: View {
    
    // MARK: - Services
    
    @StateObject private var homeFeedService = HomeFeedService(
        videoService: VideoService(),
        userService: UserService()
    )
    @StateObject private var suggestionService = SuggestionService()
    private let videoService = VideoService()
    private let userService = UserService()
    private let preloadService = VideoPreloadingService.shared  // Add preloader
    
    // MARK: - Feed State
    
    @State private var feedItems: [FeedItem] = []
    @State private var currentItemIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadingError: String? = nil
    @State private var followingCount: Int = 0
    
    // MARK: - Thread State
    
    @State private var threadChildrenLoaded: Bool = false
    // MARK: - Environment
    @EnvironmentObject var muteManager: MuteContextManager
    @EnvironmentObject var authService: AuthService
    @State private var suggestedUsers: [BasicUserInfo] = []
    
    // MARK: - Pagination
    
    @State private var isLoadingMore: Bool = false
    @State private var lastAutoLoadIndex: Int = -999
    @State private var hasRecycledOnce: Bool = false
    @State private var lastTapTime: Date = Date.distantPast  // Debounce rapid taps
    
    // MARK: - Gesture State
    
    @State private var dragOffset: CGFloat = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var lockedAxis: Axis? = nil
    
    private enum Axis {
        case vertical
        case horizontal
    }
    
    @State private var selectedUserForProfile: String?
    @State private var showingProfileView = false
    
    // MARK: - Navigation
    
    @State private var containerSize: CGSize = .zero
    @State private var currentPlaybackTime: TimeInterval = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.white)
                } else if let error = loadingError {
                    errorView(error)
                } else if !feedItems.isEmpty {
                    manualFeed(geometry: geometry)
                }
            }
            .onAppear {
                containerSize = geometry.size
                loadFeed()
                setupAudioSession()
            }
            .onDisappear {
                cleanupAudioSession()
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)  // Hide iOS status bar to maximize screen space
        .sheet(isPresented: $showingProfileView) {
            if let userID = selectedUserForProfile {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService
                )
            }
        }
    }
    
    // MARK: - Manual Feed with Axis Locking
    
    private func manualFeed(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { itemIndex in
                let item = feedItems[itemIndex]
                let yOffset = CGFloat(itemIndex - currentItemIndex) * geometry.size.height + dragOffset
                
                feedItemCell(item: item, itemIndex: itemIndex, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: yOffset)
                    .zIndex(itemIndex == currentItemIndex ? 1 : 0)
                    // REMOVED: .id(item.id) — was destroying/recreating views on swipe
            }
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    isDragging = true
                    
                    // Lock axis after initial movement
                    if lockedAxis == nil {
                        if abs(value.translation.width) > abs(value.translation.height) {
                            lockedAxis = .horizontal
                        } else {
                            lockedAxis = .vertical
                        }
                    }
                    
                    // Apply drag to locked axis only
                    switch lockedAxis {
                    case .vertical:
                        dragOffset = value.translation.height
                        horizontalDragOffset = 0
                    case .horizontal:
                        horizontalDragOffset = value.translation.width
                        dragOffset = 0
                    case .none:
                        break
                    }
                }
                .onEnded { value in
                    isDragging = false
                    let axis = lockedAxis
                    lockedAxis = nil
                    
                    switch axis {
                    case .vertical:
                        handleVerticalDragEnd(
                            translation: value.translation.height,
                            velocity: value.predictedEndTranslation.height - value.translation.height
                        )
                    case .horizontal:
                        handleHorizontalDragEnd(
                            translation: value.translation.width,
                            velocity: value.predictedEndTranslation.width - value.translation.width
                        )
                    case .none:
                        break
                    }
                }
        )
    }
    
    // MARK: - Feed Item Cell
    
    @ViewBuilder
    private func feedItemCell(item: FeedItem, itemIndex: Int, geometry: GeometryProxy) -> some View {
        switch item {
        case .video(let thread):
            videoItemView(thread: thread, itemIndex: itemIndex, geometry: geometry)
            
        case .suggestions(let users):
            SuggestionCardVideoItem(
                suggestions: users,
                onDismiss: { moveToNext() },
                onNavigateToProfile: { userID in
                    selectedUserForProfile = userID
                    showingProfileView = true
                }
            )
        }
    }
    
    // MARK: - Video Item View
    
    private func videoItemView(thread: ThreadData, itemIndex: Int, geometry: GeometryProxy) -> some View {
        let isCurrentItem = itemIndex == currentItemIndex
        
        // ThreadData structure ensures:
        // - parentVideo: the original video
        // - childVideos: ONLY direct replies (level 1)
        // - NO grandchildren or deeper nesting (no stepchildren)
        let allVideos = [thread.parentVideo] + thread.childVideos
        
        return ZStack {
            Color.black
            
            // CRITICAL FIX: Always render stitch view
            // Never conditionally switch views (prevents destruction/recreation)
            // This keeps videos in preload pool consistently
            // BUT: Only activate videos if this is the current item
            horizontalStitchView(thread: thread, allVideos: allVideos, geometry: geometry, isCurrentItem: isCurrentItem)
            
            // Overlay content
            if isCurrentItem {
                ContextualVideoOverlay(
                    video: getCurrentVideo(thread: thread),
                    context: .homeFeed,
                    currentUserID: Auth.auth().currentUser?.uid,
                    threadVideo: thread.parentVideo,
                    isVisible: true,
                    actualReplyCount: thread.childVideos.count,
                    isConversationParticipant: false,
                    onAction: { action in
                        handleOverlayAction(action, thread: thread)
                    }
                )
                .id(currentStitchIndex)  // Force refresh when stitch changes
                
                // Navigation peeks for next/previous stitch videos
                if feedItems.count > 1 {
                    VideoNavigationPeeks(
                        allVideos: allVideos,
                        currentVideoIndex: currentStitchIndex
                    )
                    .ignoresSafeArea()
                }
                
                // Stitch indicator
                if !thread.childVideos.isEmpty && threadChildrenLoaded {
                    stitchIndicator(count: allVideos.count)
                }
                
                // Mute/Unmute button (top-right)
                VStack {
                    Spacer()
                }
            }
        }
        .clipped()
    }
    
    // MARK: - Horizontal Stitch View
    
    // IMPORTANT: VideoPlayerComponent MUST handle .onChange(of: video.id) internally
    // to rebind its player when the video prop changes, since we removed .id(currentStitchIndex).
    // If VideoPlayerComponent doesn't have this, add the same bindVideo/unbindCurrent pattern
    // used in DiscoveryCard to VideoPlayerComponent's body.
    
    private func horizontalStitchView(thread: ThreadData, allVideos: [CoreVideoMetadata], geometry: GeometryProxy, isCurrentItem: Bool) -> some View {
        // Render current stitch video
        // VideoPlayerComponent handles video.id changes internally via .onChange
        // NO .id() modifier — prevents destroying/recreating player on stitch swipe
        
        guard currentStitchIndex < allVideos.count else { return AnyView(Color.black) }
        
        let video = allVideos[currentStitchIndex]
        let isCurrentStitch = isCurrentItem
        
        return AnyView(
            ZStack {
                VideoPlayerComponent(
                    video: video,
                    isActive: isCurrentStitch
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // REMOVED: .id(currentStitchIndex) — was destroying player on every stitch swipe
                
                // Invisible tap zone to toggle mute
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let timeSinceLastTap = Date().timeIntervalSince(lastTapTime)
                        guard timeSinceLastTap > 0.3 else { return }
                        lastTapTime = Date()
                        muteManager.toggle()
                    }
            }
        )
    }
    
    // MARK: - Stitch Indicator
    
    private func stitchIndicator(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentStitchIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.2), value: currentStitchIndex)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
    
    // MARK: - Drag Handlers
    
    private func handleVerticalDragEnd(translation: CGFloat, velocity: CGFloat) {
        let threshold = containerSize.height * 0.2
        let shouldMoveNext = translation < -threshold || velocity < -500
        let shouldMovePrev = translation > threshold || velocity > 500
        
        withAnimation(.easeOut(duration: 0.3)) {
            if shouldMoveNext && currentItemIndex < feedItems.count - 1 {
                currentItemIndex += 1
                currentStitchIndex = 0
            } else if shouldMovePrev && currentItemIndex > 0 {
                currentItemIndex -= 1
                currentStitchIndex = 0
            }
            dragOffset = 0
        }
        
        onPageChanged()
    }
    
    private func handleHorizontalDragEnd(translation: CGFloat, velocity: CGFloat) {
        guard let thread = getCurrentThread() else { return }
        
        let threshold = containerSize.width * 0.2
        let totalStitches = 1 + thread.childVideos.count
        let shouldMoveNext = translation < -threshold || velocity < -500
        let shouldMovePrev = translation > threshold || velocity > 500
        
        withAnimation(.easeOut(duration: 0.3)) {
            if shouldMoveNext && currentStitchIndex < totalStitches - 1 {
                currentStitchIndex += 1
            } else if shouldMovePrev && currentStitchIndex > 0 {
                currentStitchIndex -= 1
            }
            horizontalDragOffset = 0
        }
        
        preloadNextVideos()
    }
    
    // MARK: - Data Loading
    
    private func loadFeed() {
        Task {
            do {
                guard let userID = Auth.auth().currentUser?.uid else {
                    loadingError = "Not logged in"
                    isLoading = false
                    return
                }
                
                let threads = try await homeFeedService.loadFeed(userID: userID, limit: 15)
                let suggestions = try await suggestionService.getSuggestions(limit: 30)
                
                // Build feed items with suggestions interspersed
                var items: [FeedItem] = []
                for thread in threads {
                    items.append(.video(thread))
                }
                
                // Add suggestions every 6 videos
                if !suggestions.isEmpty && items.count >= 6 {
                    let suggestionBatch = Array(suggestions.prefix(5))
                    items.insert(.suggestions(suggestionBatch), at: 6)
                }
                
                feedItems = items
                suggestedUsers = suggestions
                isLoading = false
                
                loadChildrenForCurrentItem()
                preloadNextVideos()
            } catch {
                loadingError = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func loadChildrenForCurrentItem() {
        guard let thread = getCurrentThread() else { return }
        
        let threadID = thread.id
        
        Task {
            do {
                let allChildren = try await homeFeedService.loadThreadChildren(threadID: threadID)
                
                // CRITICAL: Only keep direct children (depth 1)
                let directChildren = allChildren.filter { child in
                    child.isSpinOff == false
                }
                
                if let index = feedItems.firstIndex(where: { item in
                    if case .video(let t) = item { return t.id == threadID }
                    return false
                }) {
                    feedItems[index] = .video(ThreadData(
                        id: thread.id,
                        parentVideo: thread.parentVideo,
                        childVideos: directChildren
                    ))
                    threadChildrenLoaded = true
                    print("✅ THREAD: Loaded \(directChildren.count) direct children (filtered from \(allChildren.count))")
                    
                    // Preload children via preloadNextVideos
                    preloadNextVideos()
                }
            } catch {
                print("❌ THREAD: Load failed \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private var visibleIndices: [Int] {
        let prev = max(0, currentItemIndex - 1)
        let next = min(feedItems.count - 1, currentItemIndex + 1)
        return Array(Set([prev, currentItemIndex, next])).sorted()
    }
    
    private func getCurrentThread() -> ThreadData? {
        guard currentItemIndex < feedItems.count else { return nil }
        if case .video(let thread) = feedItems[currentItemIndex] {
            return thread
        }
        return nil
    }
    
    private func getCurrentVideo(thread: ThreadData) -> CoreVideoMetadata {
        if currentStitchIndex == 0 {
            return thread.parentVideo
        }
        let childIndex = currentStitchIndex - 1
        guard childIndex < thread.childVideos.count else {
            return thread.parentVideo
        }
        return thread.childVideos[childIndex]
    }
    
    private func onPageChanged() {
        threadChildrenLoaded = false
        loadChildrenForCurrentItem()
        checkAndLoadMore()
        preloadNextVideos()
        
        // Mark current video as playing for preloader memory management
        if let currentVideo = getCurrentThread()?.parentVideo {
            preloadService.markAsCurrentlyPlaying(currentVideo.id)
        }
    }
    
    private func moveToNext() {
        if currentItemIndex < feedItems.count - 1 {
            withAnimation(.easeOut(duration: 0.3)) {
                currentItemIndex += 1
                currentStitchIndex = 0
            }
            onPageChanged()
        }
    }
    
    private func checkAndLoadMore() {
        let remainingItems = feedItems.count - currentItemIndex
        
        if remainingItems <= 5 && !isLoadingMore && currentItemIndex > lastAutoLoadIndex + 5 {
            lastAutoLoadIndex = currentItemIndex
            loadMoreFeed()
        }
    }
    
    private func preloadNextVideos() {
        guard !feedItems.isEmpty, currentItemIndex < feedItems.count else { return }
        guard let currentThread = getCurrentThread() else { return }
        
        // Get all video items (filter out suggestions)
        let allThreads = feedItems.compactMap { item -> ThreadData? in
            if case .video(let thread) = item { return thread }
            return nil
        }
        
        Task {
            // For horizontal stitch navigation (within current thread)
            await preloadService.preloadForVerticalNavigation(
                thread: currentThread,
                currentVideoIndex: currentStitchIndex
            )
            
            // For vertical feed navigation (between threads)
            await preloadService.preloadForHorizontalNavigation(
                currentThread: currentThread,
                currentVideoIndex: currentStitchIndex,
                allThreads: allThreads,
                currentThreadIndex: currentItemIndex
            )
        }
    }
    
    private func loadMoreFeed() {
        isLoadingMore = true
        
        Task {
            do {
                guard let userID = Auth.auth().currentUser?.uid else {
                    isLoadingMore = false
                    return
                }
                
                let moreThreads = try await homeFeedService.loadFeed(userID: userID, limit: 15)
                
                if !moreThreads.isEmpty {
                    let newItems = moreThreads.map { FeedItem.video($0) }
                    feedItems.append(contentsOf: newItems)
                    hasRecycledOnce = false
                    print("📥 FEED: Loaded 15 more videos")
                } else if !hasRecycledOnce {
                    recycleVideos()
                }
                isLoadingMore = false
            } catch {
                isLoadingMore = false
                print("❌ FEED: Load more failed \(error)")
            }
        }
    }
    
    private func recycleVideos() {
        let videoItems = feedItems.compactMap { item -> FeedItem? in
            if case .video(let thread) = item {
                return .video(thread)
            }
            return nil
        }
        
        let shuffledVideos = videoItems.shuffled()
        feedItems.append(contentsOf: shuffledVideos)
        hasRecycledOnce = true
        print("🔄 FEED: Recycled videos")
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction, thread: ThreadData) {
        print("📺 OVERLAY: \(action)")
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("⚠️ Audio session error: \(error)")
        }
    }
    
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("⚠️ Audio cleanup error: \(error)")
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Error loading feed")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
            
            Button("Retry") {
                isLoading = true
                loadFeed()
            }
            .padding()
            .background(Color.cyan)
            .foregroundColor(.black)
            .cornerRadius(8)
        }
    }
}

// MARK: - Feed Item Type

enum FeedItem: Identifiable {
    case video(ThreadData)
    case suggestions([BasicUserInfo])
    
    var id: String {
        switch self {
        case .video(let thread): return "video-\(thread.id)"
        case .suggestions(let users): return "suggestions-\(users.map { $0.id }.joined(separator: "-"))"
        }
    }
}
