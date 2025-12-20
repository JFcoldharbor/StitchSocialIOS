//
//  HomeFeedView.swift
//  StitchSocial
//
//  TikTok-style feed with manual gesture handling for smooth transitions
//  UPDATED: Added session resume and view history tracking
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine
import Network

// MARK: - Debug Helper
private let debug = HomeFeedDebugger.shared

// MARK: - Feed Item Types

enum FeedItem: Identifiable {
    case video(ThreadData)
    case suggestions([BasicUserInfo])
    case ad
    
    var id: String {
        switch self {
        case .video(let thread): return "video-\(thread.id)"
        case .suggestions(let users): return "suggestions-\(users.map { $0.id }.joined(separator: "-").prefix(20))"
        case .ad: return "ad-\(UUID().uuidString)"
        }
    }
    
    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

struct FeedInsertionConfig {
    static let suggestionsEvery = 6
    static let minUsersForSuggestion = 3
}

// MARK: - HomeFeedView

struct HomeFeedView: View {
    
    // MARK: - Services
    
    @StateObject private var homeFeedService = HomeFeedService(
        videoService: VideoService(),
        userService: UserService()
    )
    @StateObject private var suggestionService = SuggestionService()
    
    // MARK: - Feed State
    
    @State private var feedItems: [FeedItem] = []
    @State private var videoThreads: [ThreadData] = []
    @State private var currentItemIndex: Int = 0
    @State private var currentStitchIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadingError: String? = nil
    @State private var suggestedUsers: [BasicUserInfo] = []
    @State private var isLoadingMore: Bool = false
    
    // MARK: - Gesture State
    
    @State private var dragOffset: CGFloat = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var lockedAxis: Axis? = nil
    
    private enum Axis {
        case vertical
        case horizontal
    }
    
    // MARK: - Playback State
    
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var containerSize: CGSize = .zero
    
    // MARK: - Session Resume State (NEW)
    
    @State private var showResumePrompt: Bool = false
    @State private var savedPosition: FeedPosition? = nil
    @State private var isResumingSession: Bool = false
    
    // MARK: - View Tracking State (NEW)
    
    @State private var videoWatchStartTime: Date? = nil
    @State private var lastTrackedVideoID: String? = nil
    private let minWatchTimeForSeen: TimeInterval = 3.0
    
    // MARK: - Computed: Which items to render
    
    private var visibleIndices: [Int] {
        let prev = max(0, currentItemIndex - 1)
        let next = min(feedItems.count - 1, currentItemIndex + 1)
        return Array(Set([prev, currentItemIndex, next])).sorted()
    }
    
    // MARK: - Drag Progress (0 to 1 for next, 0 to -1 for previous)
    
    private var dragProgress: CGFloat {
        guard containerSize.height > 0 else { return 0 }
        return -dragOffset / containerSize.height
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let error = loadingError {
                    errorView(error: error)
                } else if isLoading {
                    loadingView
                } else if feedItems.isEmpty {
                    emptyFeedView
                } else {
                    manualFeed(geometry: geometry)
                }
                
                // Resume session prompt overlay (NEW)
                if showResumePrompt {
                    resumeSessionPrompt
                }
            }
            .onAppear {
                containerSize = geometry.size
                debug.feedViewAppeared()
                setupAudioSession()
                checkForSessionResume()
            }
            .onChange(of: geometry.size) { _, newSize in
                containerSize = newSize
            }
            .onDisappear {
                saveCurrentPosition()
                markCurrentVideoSeenIfQualified()
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Resume Session Prompt (NEW)
    
    private var resumeSessionPrompt: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    
                    Text("Pick up where you left off?")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { dismissResumePrompt() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                
                if let position = savedPosition {
                    Text("Continue from video \(position.itemIndex + 1)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 16) {
                    Button(action: { dismissResumePrompt() }) {
                        Text("Start Fresh")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(10)
                    }
                    
                    Button(action: { resumeSession() }) {
                        Text("Resume")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(100)
    }
    
    // MARK: - Session Resume Logic (NEW)
    
    private func checkForSessionResume() {
        let (canResume, position) = homeFeedService.checkSessionResume()
        
        if canResume, let position = position {
            savedPosition = position
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showResumePrompt = true
            }
            // Still load feed in background
            loadFeed()
        } else {
            loadFeed()
        }
    }
    
    private func resumeSession() {
        guard let position = savedPosition else {
            dismissResumePrompt()
            return
        }
        
        isResumingSession = true
        
        Task {
            do {
                if let threadIDs = homeFeedService.getLastSessionThreadIDs() {
                    let threads = try await homeFeedService.loadThreadsByIDs(threadIDs)
                    
                    await MainActor.run {
                        videoThreads = threads
                        feedItems = buildFeedItems(from: threads, suggestions: suggestedUsers)
                        
                        // Jump to saved position
                        if position.itemIndex < feedItems.count {
                            currentItemIndex = position.itemIndex
                            currentStitchIndex = position.stitchIndex
                        }
                        
                        isLoading = false
                        isResumingSession = false
                        dismissResumePrompt()
                        
                        startWatchTimeTracking()
                        loadChildrenForCurrentItem()
                        preloadAhead()
                    }
                } else {
                    await MainActor.run {
                        isResumingSession = false
                        dismissResumePrompt()
                    }
                }
            } catch {
                await MainActor.run {
                    isResumingSession = false
                    dismissResumePrompt()
                }
            }
        }
    }
    
    private func dismissResumePrompt() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showResumePrompt = false
        }
        savedPosition = nil
        homeFeedService.clearSessionData()
    }
    
    // MARK: - Position Saving (NEW)
    
    private func saveCurrentPosition() {
        let threadID = getCurrentThread()?.id
        homeFeedService.saveCurrentPosition(
            itemIndex: currentItemIndex,
            stitchIndex: currentStitchIndex,
            threadID: threadID
        )
        homeFeedService.saveCurrentFeed(videoThreads)
    }
    
    // MARK: - View Tracking (NEW)
    
    private func startWatchTimeTracking() {
        if let thread = getCurrentThread() {
            let allVideos = [thread.parentVideo] + thread.childVideos
            if currentStitchIndex < allVideos.count {
                let video = allVideos[currentStitchIndex]
                videoWatchStartTime = Date()
                lastTrackedVideoID = video.id
            }
        }
    }
    
    private func markCurrentVideoSeenIfQualified() {
        guard let startTime = videoWatchStartTime,
              let videoID = lastTrackedVideoID else { return }
        
        let watchTime = Date().timeIntervalSince(startTime)
        if watchTime >= minWatchTimeForSeen {
            homeFeedService.markVideoSeen(videoID)
            print("👁️ FEED: Marked video \(videoID.prefix(8)) as seen (watched \(Int(watchTime))s)")
        }
    }
    
    private func onVideoChanged() {
        // Mark previous video as seen if qualified
        markCurrentVideoSeenIfQualified()
        
        // Start tracking new video
        startWatchTimeTracking()
    }
    
    // MARK: - Manual Feed with Gesture Control
    
    private func manualFeed(geometry: GeometryProxy) -> some View {
        ZStack {
            // Render current, previous, and next items using STABLE video IDs
            ForEach(visibleIndices, id: \.self) { itemIndex in
                let item = feedItems[itemIndex]
                let yOffset = CGFloat(itemIndex - currentItemIndex) * geometry.size.height + dragOffset
                
                feedItemCell(
                    item: item,
                    itemIndex: itemIndex,
                    geometry: geometry
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(y: yOffset)
                .zIndex(itemIndex == currentItemIndex ? 1 : 0)
                .id(item.id) // Use stable ID to prevent recreation
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
                onNavigateToProfile: { _ in killAllVideoActivity(reason: "Profile from suggestions") }
            )
            
        case .ad:
            AdPlaceholderCard(isActive: itemIndex == currentItemIndex)
        }
    }
    
    // MARK: - Video Item (with horizontal stitch support)
    
    private func videoItemView(thread: ThreadData, itemIndex: Int, geometry: GeometryProxy) -> some View {
        let isCurrentItem = itemIndex == currentItemIndex
        let allVideos = [thread.parentVideo] + thread.childVideos
        
        return ZStack {
            Color.black
            
            if isCurrentItem && allVideos.count > 1 {
                // Current item with multiple stitches - show horizontal swipe
                horizontalStitchView(thread: thread, allVideos: allVideos, geometry: geometry)
            } else {
                // Single video (current or adjacent)
                let video = thread.parentVideo
                
                VideoPlayerCell(
                    video: video,
                    shouldPlay: isCurrentItem,
                    isCurrent: isCurrentItem,
                    dragProgress: 0,
                    onTimeUpdate: { time in
                        if isCurrentItem {
                            currentPlaybackTime = time
                        }
                    }
                )
                .equatable()
                .id(video.id)
                
                if isCurrentItem {
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
                    
                    if !thread.childVideos.isEmpty {
                        FloatingBubbleNotification.parentVideoWithReplies(
                            videoDuration: video.duration,
                            currentPosition: currentPlaybackTime,
                            replyCount: thread.childVideos.count,
                            currentStitchIndex: currentStitchIndex,
                            onViewReplies: { moveToNextStitch(thread: thread) },
                            onDismiss: {}
                        )
                    }
                }
            }
        }
        .clipped()
    }
    
    // MARK: - Horizontal Stitch View
    
    private func horizontalStitchView(thread: ThreadData, allVideos: [CoreVideoMetadata], geometry: GeometryProxy) -> some View {
        let visibleStitchIndices: [Int] = {
            let prev = max(0, currentStitchIndex - 1)
            let next = min(allVideos.count - 1, currentStitchIndex + 1)
            return Array(Set([prev, currentStitchIndex, next])).sorted()
        }()
        
        return ZStack {
            ForEach(visibleStitchIndices, id: \.self) { stitchIndex in
                let xOffset = CGFloat(stitchIndex - currentStitchIndex) * geometry.size.width + horizontalDragOffset
                let video = allVideos[stitchIndex]
                let isCurrentStitch = stitchIndex == currentStitchIndex
                
                ZStack {
                    VideoPlayerCell(
                        video: video,
                        shouldPlay: isCurrentStitch,
                        isCurrent: isCurrentStitch,
                        dragProgress: 0,
                        onTimeUpdate: { time in
                            if isCurrentStitch {
                                currentPlaybackTime = time
                            }
                        }
                    )
                    .equatable()
                    .id(video.id)
                    
                    if isCurrentStitch {
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
                        
                        if currentStitchIndex == 0 && !thread.childVideos.isEmpty {
                            FloatingBubbleNotification.parentVideoWithReplies(
                                videoDuration: video.duration,
                                currentPosition: currentPlaybackTime,
                                replyCount: thread.childVideos.count,
                                currentStitchIndex: currentStitchIndex,
                                onViewReplies: { moveToNextStitch(thread: thread) },
                                onDismiss: {}
                            )
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(x: xOffset)
            }
        }
    }
    
    // MARK: - Should Pre-Play Adjacent Stitch
    
    private func shouldPrePlayStitch(stitchIndex: Int, totalStitches: Int) -> Bool {
        let threshold: CGFloat = 0.3
        let progress = -horizontalDragOffset / containerSize.width
        
        if stitchIndex > currentStitchIndex {
            return progress > threshold
        } else if stitchIndex < currentStitchIndex {
            return progress < -threshold
        }
        return false
    }
    
    // MARK: - Move to Next Stitch
    
    private func moveToNextStitch(thread: ThreadData) {
        let totalStitches = 1 + thread.childVideos.count
        guard currentStitchIndex < totalStitches - 1 else { return }
        
        // Track video change
        onVideoChanged()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            horizontalDragOffset = -containerSize.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            currentStitchIndex += 1
            horizontalDragOffset = 0
            currentPlaybackTime = 0
        }
    }
    
    // MARK: - Should Pre-Play Adjacent Video
    
    private func shouldPrePlay(itemIndex: Int) -> Bool {
        // Pre-play when dragged 30% toward the adjacent item
        let threshold: CGFloat = 0.3
        
        if itemIndex > currentItemIndex {
            // Next item - dragging up (negative offset = positive progress)
            return dragProgress > threshold
        } else if itemIndex < currentItemIndex {
            // Previous item - dragging down (positive offset = negative progress)
            return dragProgress < -threshold
        }
        return false
    }
    
    // MARK: - Handle Vertical Drag End
    
    private func handleVerticalDragEnd(translation: CGFloat, velocity: CGFloat) {
        let threshold = containerSize.height * 0.3
        let velocityThreshold: CGFloat = 500
        
        let shouldMoveNext = translation < -threshold || velocity < -velocityThreshold
        let shouldMovePrev = translation > threshold || velocity > velocityThreshold
        
        if shouldMoveNext && currentItemIndex < feedItems.count - 1 {
            // Track video change
            onVideoChanged()
            
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = -containerSize.height
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.none) {
                    currentItemIndex += 1
                    dragOffset = 0
                }
                currentStitchIndex = 0
                currentPlaybackTime = 0
                onPageChanged()
            }
            
        } else if shouldMovePrev && currentItemIndex > 0 {
            // Track video change
            onVideoChanged()
            
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = containerSize.height
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.none) {
                    currentItemIndex -= 1
                    dragOffset = 0
                }
                currentStitchIndex = 0
                currentPlaybackTime = 0
                onPageChanged()
            }
            
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = 0
            }
        }
    }
    
    // MARK: - Handle Horizontal Drag End
    
    private func handleHorizontalDragEnd(translation: CGFloat, velocity: CGFloat) {
        guard let thread = getCurrentThread() else {
            withAnimation(.easeOut(duration: 0.2)) {
                horizontalDragOffset = 0
            }
            return
        }
        
        let totalStitches = 1 + thread.childVideos.count
        let threshold = containerSize.width * 0.3
        let velocityThreshold: CGFloat = 500
        
        let shouldMoveNext = translation < -threshold || velocity < -velocityThreshold
        let shouldMovePrev = translation > threshold || velocity > velocityThreshold
        
        if shouldMoveNext && currentStitchIndex < totalStitches - 1 {
            // Track video change
            onVideoChanged()
            
            withAnimation(.easeOut(duration: 0.25)) {
                horizontalDragOffset = -containerSize.width
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.none) {
                    currentStitchIndex += 1
                    horizontalDragOffset = 0
                }
                currentPlaybackTime = 0
            }
            
        } else if shouldMovePrev && currentStitchIndex > 0 {
            // Track video change
            onVideoChanged()
            
            withAnimation(.easeOut(duration: 0.25)) {
                horizontalDragOffset = containerSize.width
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.none) {
                    currentStitchIndex -= 1
                    horizontalDragOffset = 0
                }
                currentPlaybackTime = 0
            }
            
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                horizontalDragOffset = 0
            }
        }
    }
    
    // MARK: - Page Changed
    
    private func onPageChanged() {
        debug.log(.navigation, "Page changed to \(currentItemIndex)")
        loadChildrenForCurrentItem()
        preloadAhead()
        
        // Save position periodically
        if currentItemIndex % 5 == 0 {
            saveCurrentPosition()
        }
        
        if currentItemIndex >= feedItems.count - 3 {
            loadMoreContent()
        }
    }
    
    // MARK: - Navigation Helpers
    
    private func moveToNext() {
        guard currentItemIndex < feedItems.count - 1 else { return }
        
        onVideoChanged()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            dragOffset = -containerSize.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            currentItemIndex += 1
            dragOffset = 0
            onPageChanged()
        }
    }
    
    // MARK: - Overlay Actions
    
    private func handleOverlayAction(_ action: ContextualOverlayAction, video: CoreVideoMetadata, thread: ThreadData) {
        switch action {
        case .stitch, .reply:
            // Just pause for recording - don't kill everything
            pauseCurrentVideo()
        case .thread, .share, .more:
            killAllVideoActivity(reason: "Overlay action: \(action)")
        case .profile(let userID):
            killAllVideoActivity(reason: "Profile: \(userID.prefix(8))")
        default:
            break
        }
    }
    
    // MARK: - Pause Current Video (for recording)
    
    private func pauseCurrentVideo() {
        debug.log(.lifecycle, "⏸️ PAUSE: For recording")
        NotificationCenter.default.post(name: .pauseAllVideoPlayers, object: nil)
    }
    
    // MARK: - Kill Switch
    
    private func killAllVideoActivity(reason: String) {
        debug.log(.lifecycle, "🛑 KILL: \(reason)")
        PreloadCache.shared.clear()
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .pauseAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .stopAllBackgroundActivity, object: nil)
        NotificationCenter.default.post(name: .deactivateAllPlayers, object: nil)
    }
    
    // MARK: - Helpers
    
    private func getCurrentThread() -> ThreadData? {
        guard currentItemIndex < feedItems.count else { return nil }
        if case .video(let thread) = feedItems[currentItemIndex] {
            return thread
        }
        return nil
    }
    
    // MARK: - Preloading
    
    private func preloadAhead() {
        guard let thread = getCurrentThread() else { return }
        
        var videosToPreload: [CoreVideoMetadata] = []
        
        // Next thread's parent
        if currentItemIndex + 1 < feedItems.count,
           case .video(let nextThread) = feedItems[currentItemIndex + 1] {
            videosToPreload.append(nextThread.parentVideo)
        }
        
        // First child of current thread
        if !thread.childVideos.isEmpty {
            videosToPreload.append(thread.childVideos[0])
        }
        
        for video in videosToPreload.prefix(2) {
            PreloadCache.shared.preload(video: video)
        }
    }
    
    // MARK: - Feed Loading
    
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
                
                async let threadsTask = homeFeedService.loadFeed(userID: userID, limit: 15)
                async let suggestionsTask = loadSuggestedUsers()
                
                let (threads, suggestions) = try await (threadsTask, suggestionsTask)
                
                await MainActor.run {
                    videoThreads = threads
                    suggestedUsers = suggestions
                    feedItems = buildFeedItems(from: threads, suggestions: suggestions)
                    isLoading = false
                    debug.feedLoadCompleted(threadCount: threads.count, source: "network")
                    startWatchTimeTracking()
                    loadChildrenForCurrentItem()
                    preloadAhead()
                }
            } catch {
                await MainActor.run {
                    loadingError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func buildFeedItems(from threads: [ThreadData], suggestions: [BasicUserInfo]) -> [FeedItem] {
        var items: [FeedItem] = []
        var videoCount = 0
        var suggestionBatchIndex = 0
        
        for thread in threads {
            items.append(.video(thread))
            videoCount += 1
            
            if videoCount % FeedInsertionConfig.suggestionsEvery == 0 {
                let startIndex = suggestionBatchIndex * 5
                let endIndex = min(startIndex + 5, suggestions.count)
                
                if startIndex < suggestions.count {
                    let batch = Array(suggestions[startIndex..<endIndex])
                    if batch.count >= FeedInsertionConfig.minUsersForSuggestion {
                        items.append(.suggestions(batch))
                        suggestionBatchIndex += 1
                    }
                }
            }
        }
        
        return items
    }
    
    private func loadSuggestedUsers() async -> [BasicUserInfo] {
        do {
            return try await suggestionService.getSuggestions(limit: 30)
        } catch {
            return []
        }
    }
    
    private func loadChildrenForCurrentItem() {
        guard let thread = getCurrentThread(), thread.childVideos.isEmpty else { return }
        
        Task {
            do {
                let children = try await homeFeedService.loadThreadChildren(threadID: thread.id)
                await MainActor.run {
                    if let index = feedItems.firstIndex(where: {
                        if case .video(let t) = $0 { return t.id == thread.id }
                        return false
                    }) {
                        feedItems[index] = .video(ThreadData(
                            id: thread.id,
                            parentVideo: thread.parentVideo,
                            childVideos: children
                        ))
                    }
                }
            } catch {
                print("❌ Children load failed: \(error)")
            }
        }
    }
    
    private func loadMoreContent() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        Task {
            do {
                guard let userID = Auth.auth().currentUser?.uid else { return }
                let moreThreads = try await homeFeedService.loadMoreContent(userID: userID)
                
                await MainActor.run {
                    let existingIDs = Set(videoThreads.map { $0.id })
                    let newThreads = moreThreads.filter { !existingIDs.contains($0.id) }
                    
                    if !newThreads.isEmpty {
                        videoThreads.append(contentsOf: newThreads)
                        let newItems = buildFeedItems(from: newThreads, suggestions: suggestedUsers)
                        feedItems.append(contentsOf: newItems)
                    }
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run { isLoadingMore = false }
            }
        }
    }
    
    // MARK: - Audio Setup
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio error: \(error)")
        }
    }
    
    // MARK: - Placeholder Views
    
    private var loadingView: some View {
        VStack {
            ProgressView().scaleEffect(1.5).progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Loading...").foregroundColor(.gray).padding(.top)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 50)).foregroundColor(.red)
            Text(error).foregroundColor(.white).multilineTextAlignment(.center)
            Button("Retry") { loadFeed() }.foregroundColor(.blue)
        }.padding()
    }
    
    private var emptyFeedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash").font(.system(size: 50)).foregroundColor(.gray)
            Text("No videos yet").foregroundColor(.white)
        }
    }
}

// MARK: - Video Player Cell (Handles play state and volume)

struct VideoPlayerCell: View, Equatable {
    let video: CoreVideoMetadata
    let shouldPlay: Bool
    let isCurrent: Bool
    let dragProgress: CGFloat
    var onTimeUpdate: ((TimeInterval) -> Void)?
    
    static func == (lhs: VideoPlayerCell, rhs: VideoPlayerCell) -> Bool {
        lhs.video.id == rhs.video.id && lhs.shouldPlay == rhs.shouldPlay
    }
    
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var hasError = false
    @State private var timeObserver: Any?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                
                if hasError {
                    VStack {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.red)
                        Text("Failed to load").foregroundColor(.white)
                    }
                } else if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            setupPlayer()
            updatePlayState()
        }
        .onDisappear {
            player?.pause()
            destroyPlayer()
        }
        .onChange(of: shouldPlay) { _, _ in
            updatePlayState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .killAllVideoPlayers)) { _ in
            destroyPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseAllVideoPlayers)) { _ in
            player?.pause()
        }
    }
    
    private func updatePlayState() {
        guard let player = player else { return }
        if shouldPlay {
            if player.currentItem?.status == .readyToPlay {
                player.seek(to: .zero)
                player.play()
            }
        } else {
            player.pause()
        }
    }
    
    private func setupPlayer() {
        guard player == nil else { return }
        
        if let preloaded = PreloadCache.shared.getPlayer(for: video.id) {
            player = preloaded
            preloaded.volume = 1.0
            isReady = true
            setupTimeObserver(for: preloaded)
            setupLooping(for: preloaded)
            if shouldPlay {
                preloaded.seek(to: .zero)
                preloaded.play()
            } else {
                preloaded.pause()
            }
            return
        }
        
        guard let url = URL(string: video.videoURL), !video.videoURL.isEmpty else {
            hasError = true
            return
        }
        
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.volume = 1.0
        player = newPlayer
        
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [self] status in
                if status == .readyToPlay {
                    isReady = true
                    setupTimeObserver(for: newPlayer)
                    setupLooping(for: newPlayer)
                    if shouldPlay {
                        newPlayer.play()
                    }
                } else if status == .failed {
                    hasError = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            onTimeUpdate?(time.seconds)
        }
    }
    
    private func setupLooping(for player: AVPlayer) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            if shouldPlay {
                player.seek(to: .zero)
                player.play()
            }
        }
    }
    
    private func destroyPlayer() {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

// MARK: - PreloadCache

class PreloadCache {
    static let shared = PreloadCache()
    private var cache: [String: AVPlayer] = [:]
    private var order: [String] = []
    private let maxPlayers = 2
    private let queue = DispatchQueue(label: "preload.cache")
    
    private init() {
        NotificationCenter.default.addObserver(forName: .killAllVideoPlayers, object: nil, queue: .main) { [weak self] _ in
            self?.clear()
        }
    }
    
    func preload(video: CoreVideoMetadata) {
        queue.async { [weak self] in
            guard let self = self, !self.cache.keys.contains(video.id), let url = URL(string: video.videoURL) else { return }
            while self.cache.count >= self.maxPlayers, let oldest = self.order.first { self.evict(videoID: oldest) }
            let player = AVPlayer(url: url)
            player.automaticallyWaitsToMinimizeStalling = false
            self.cache[video.id] = player
            self.order.append(video.id)
        }
    }
    
    func getPlayer(for videoID: String) -> AVPlayer? {
        queue.sync {
            if let player = cache[videoID] {
                cache.removeValue(forKey: videoID)
                order.removeAll { $0 == videoID }
                return player
            }
            return nil
        }
    }
    
    private func evict(videoID: String) {
        cache[videoID]?.pause()
        cache[videoID]?.replaceCurrentItem(with: nil)
        cache.removeValue(forKey: videoID)
        order.removeAll { $0 == videoID }
    }
    
    func clear() {
        queue.async { [weak self] in
            self?.cache.values.forEach { $0.pause(); $0.replaceCurrentItem(with: nil) }
            self?.cache.removeAll()
            self?.order.removeAll()
        }
    }
}

// MARK: - Ad Placeholder

struct AdPlaceholderCard: View {
    let isActive: Bool
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack.badge.play").font(.system(size: 50)).foregroundColor(.gray)
                Text("Ad Space").font(.title2).foregroundColor(.gray)
                Text("Coming Soon").font(.caption).foregroundColor(Color.gray.opacity(0.7))
            }
        }
    }
}
