//
//  DiscoverySwipeCards.swift - STABLE SLOT ARCHITECTURE
//  StitchSocial
//
//  Layer 8: Views - Swipe Cards with shared player pool
//  Uses 3 stable card slots that rebind video data on swipe
//  instead of destroying/recreating views (prevents service re-init)
//

import SwiftUI
import AVFoundation
import FirebaseAuth

struct DiscoverySwipeCards: View {
    
    // MARK: - Props
    let videos: [CoreVideoMetadata]
    @Binding var currentIndex: Int
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onNavigateToProfile: (String) -> Void
    let onNavigateToThread: (String) -> Void
    var isFullscreenActive: Bool = false
    
    // MARK: - Discovery Engagement Tracker
    @ObservedObject private var discoveryTracker = DiscoveryEngagementTracker.shared
    
    // MARK: - Environment
    @EnvironmentObject var muteManager: MuteContextManager
    @State private var dragOffset = CGSize.zero
    @State private var dragRotation: Double = 0
    @State private var isSwipeInProgress = false
    @State private var loopCounts: [String: Int] = [:]
    
    // MARK: - Configuration
    private let maxCards = 3
    private let swipeThreshold: CGFloat = 80
    private let targetLoops = 2
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 3 STABLE CARD SLOTS â€” rendered in reverse so slot 0 (top) renders last
                // ForEach over fixed Int range = SwiftUI reuses these views, never destroys them
                ForEach((0..<maxCards).reversed(), id: \.self) { slot in
                    let videoIndex = currentIndex + slot
                    
                    if videoIndex < videos.count {
                        cardSlot(
                            slot: slot,
                            video: videos[videoIndex],
                            geometry: geometry
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60)
            .padding(.vertical, 80)
            .onAppear {
                discoveryTracker.startNewSession()
                notifyTrackerOfActiveCard()
            }
            .onChange(of: currentIndex) { _, _ in
                notifyTrackerOfActiveCard()
            }
        }
    }
    
    // MARK: - Stable Card Slot
    
    private func cardSlot(slot: Int, video: CoreVideoMetadata, geometry: GeometryProxy) -> some View {
        let isTopCard = slot == 0
        let offset = isTopCard ? dragOffset : CGSize.zero
        let scale = 1.0 - (Double(slot) * 0.05)
        let stackOffset = Double(slot) * 10
        
        return DiscoveryCard(
            video: video,
            shouldAutoPlay: isTopCard && !isFullscreenActive,
            isFullscreenActive: isFullscreenActive,
            onVideoLoop: { videoID in
                handleVideoLoop(videoID: videoID)
            }
        )
        .scaleEffect(scale)
        .offset(x: offset.width, y: offset.height + stackOffset)
        .rotationEffect(.degrees(isTopCard ? dragRotation : 0))
        .opacity(slot < 2 ? 1.0 : 0.5)
        .zIndex(Double(maxCards - slot))
        .allowsHitTesting(isTopCard)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isTopCard && !isSwipeInProgress else { return }
                    handleDragChanged(value: value)
                }
                .onEnded { value in
                    guard isTopCard && !isSwipeInProgress else { return }
                    handleDragEnded(value: value)
                }
        )
        .onTapGesture {
            if isTopCard {
                discoveryTracker.cardTappedFullscreen(videoID: video.id, creatorID: video.creatorID)
                onVideoTap(video)
            }
        }
    }
    
    // MARK: - Drag Handling - LEFT/RIGHT NAVIGATION
    
    private func handleDragChanged(value: DragGesture.Value) {
        dragOffset = CGSize(width: value.translation.width, height: 0)
        dragRotation = Double(value.translation.width / 20)
    }
    
    private func handleDragEnded(value: DragGesture.Value) {
        let translation = value.translation
        let velocity = value.velocity
        
        let isHorizontalSwipe = abs(translation.width) > abs(translation.height)
        
        if isHorizontalSwipe {
            if abs(translation.width) > swipeThreshold || abs(velocity.width) > 500 {
                isSwipeInProgress = true
                
                if translation.width > 0 {
                    // Swipe right = go back (rewatch)
                    discoveryTracker.cardSwipedAway(wasSwipeBack: true)
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        previousCard()
                        isSwipeInProgress = false
                    }
                } else {
                    // Swipe left = next card (manual swipe away)
                    discoveryTracker.cardSwipedAway(wasSwipeBack: false)
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        nextCard()
                        isSwipeInProgress = false
                    }
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    resetCardPosition()
                }
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                resetCardPosition()
            }
        }
    }
    
    // MARK: - Loop Handling
    
    private func handleVideoLoop(videoID: String) {
        guard currentIndex < videos.count else { return }
        let currentVideo = videos[currentIndex]
        guard currentVideo.id == videoID else { return }
        
        let currentLoops = loopCounts[videoID, default: 0] + 1
        loopCounts[videoID] = currentLoops
        
        if currentLoops >= targetLoops {
            autoAdvanceToNext()
        }
    }
    
    private func autoAdvanceToNext() {
        guard !isSwipeInProgress && !isFullscreenActive else { return }
        isSwipeInProgress = true
        
        // Notify tracker this was auto-advance (no manual intent)
        discoveryTracker.cardAutoAdvanced()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
        }
        
        // Wait for animation to fully complete before changing index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            nextCard()
            isSwipeInProgress = false
        }
    }
    
    // MARK: - Navigation
    
    private func nextCard() {
        if currentIndex + 1 < videos.count {
            currentIndex += 1
        }
        resetCardPosition()
        
        if currentIndex > 10 {
            let oldVideoID = videos[currentIndex - 10].id
            loopCounts.removeValue(forKey: oldVideoID)
        }
    }
    
    private func previousCard() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
        resetCardPosition()
    }
    
    private func resetCardPosition() {
        dragOffset = .zero
        dragRotation = 0
    }
    
    // MARK: - Discovery Tracker Helpers
    
    private func notifyTrackerOfActiveCard() {
        guard currentIndex < videos.count else { return }
        let video = videos[currentIndex]
        discoveryTracker.cardBecameActive(videoID: video.id, creatorID: video.creatorID)
    }
}

// MARK: - Discovery Card Component (STABLE SLOT - REUSES VIEW)

struct DiscoveryCard: View {
    let video: CoreVideoMetadata
    let shouldAutoPlay: Bool
    let isFullscreenActive: Bool
    let onVideoLoop: (String) -> Void
    
    // Environment
    @EnvironmentObject var muteManager: MuteContextManager
    
    // Shared preloading service
    private var preloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var hasTrackedView = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var creatorProfileURL: String? = nil
    @State private var creatorDisplayName: String? = nil
    @State private var currentVideoID: String? = nil
    @State private var cachedThumbnail: UIImage? = nil
    @State private var setupTask: Task<Void, Never>? = nil
    
    private var displayName: String {
        if let fetched = creatorDisplayName, !fetched.isEmpty {
            return fetched
        }
        if !video.creatorName.isEmpty {
            return video.creatorName
        }
        return "Creator"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                // Thumbnail — cached UIImage for instant display, no network flash
                if let thumb = cachedThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                
                if let player = player {
                    CustomVideoPlayerView(player: player, onReadyForDisplay: {
                        withAnimation(.easeIn(duration: 0.15)) {
                            isReady = true
                        }
                    })
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(isReady ? 1 : 0)
                } else if video.thumbnailURL.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                
                if shouldAutoPlay {
                    cardOverlay
                }
                
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            loadThumbnail()
            bindVideo()
        }
        .onDisappear {
            teardown()
        }
        .onChange(of: video.id) { oldID, newID in
            // Card slot got new video data â€” rebind without destroying view
            guard newID != currentVideoID else { return }
            cachedThumbnail = nil
            isReady = false
            unbindCurrent()
            loadThumbnail()
            bindVideo()
            
            // If this is the top card, ensure playback starts after rebind settles
            if shouldAutoPlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard shouldAutoPlay, currentVideoID == video.id else { return }
                    if let p = player, p.rate == 0 {
                        // Player exists but isn't playing â€” kick it
                        preloadingService.markAsCurrentlyPlaying(video.id)
                        p.isMuted = muteManager.isMuted
                        p.seek(to: .zero)
                        p.play()
                        setupLoopObserver()
                    } else if player == nil {
                        // Still no player â€” force rebind
                        bindVideo()
                    }
                }
            }
        }
        .onChange(of: shouldAutoPlay) { _, isTop in
            if isTop {
                // Became top card â€” protect FIRST, then play
                preloadingService.markAsCurrentlyPlaying(video.id)
                
                // Delay must outlast swipe animation (0.4s) to avoid race
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    // Re-check: still top card and still same video?
                    guard shouldAutoPlay, currentVideoID == video.id else { return }
                    
                    if let p = player {
                        // FIXED: Only seek+play if not already playing
                        // attachPlayer() already started playback — don't restart
                        if p.rate == 0 {
                            p.isMuted = muteManager.isMuted
                            p.seek(to: .zero)
                            p.play()
                            setupLoopObserver()
                        }
                        loadCreatorProfile()
                        trackViewIfNeeded()
                    } else {
                        // Player was evicted â€” rebind
                        bindVideo()
                    }
                }
            } else {
                // No longer top card â€” stop looping but delay pause
                // so it doesn't race with new top card's play()
                removeLoopObserver()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !shouldAutoPlay else { return }
                    player?.pause()
                }
            }
        }
        .onChange(of: muteManager.isMuted) { _, isMuted in
            player?.isMuted = isMuted
        }
        .onChange(of: isFullscreenActive) { _, isActive in
            if isActive {
                // Going fullscreen â€” pause after brief delay so transition is smooth
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard isFullscreenActive else { return }
                    player?.pause()
                }
            } else if shouldAutoPlay {
                // Returning from fullscreen â€” re-protect and play
                preloadingService.markAsCurrentlyPlaying(video.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard shouldAutoPlay, !isFullscreenActive else { return }
                    player?.isMuted = muteManager.isMuted
                    player?.play()
                }
            }
        }
    }
    
    // MARK: - Card Overlay
    
    private var cardOverlay: some View {
        VStack {
            if video.replyCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right.fill")
                        .font(.system(size: 10))
                    
                    Text("\(video.replyCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.7), .blue.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: .cyan.opacity(0.6), radius: 6, x: 0, y: 0)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .alignmentGuide(.leading) { _ in 0 }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            Spacer()
            
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    CreatorPill(
                        creator: video,
                        isThread: video.isThread,
                        colors: temperatureColors,
                        displayName: displayName,
                        profileImageURL: creatorProfileURL,
                        onTap: { }
                    )
                    
                    if !video.title.isEmpty {
                        Text(video.title)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 16) {
                        if video.hypeCount > 0 {
                            Label("\(video.hypeCount)", systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if video.viewCount > 0 {
                            Label("\(video.viewCount)", systemImage: "eye.fill")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Label(video.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Temperature Colors
    
    private var temperatureColors: [Color] {
        switch video.temperature.lowercased() {
        case "blazing", "fire": return [.red, .orange]
        case "hot": return [.orange, .yellow]
        case "warm": return [.yellow, .green]
        case "cool": return [.cyan, .blue]
        case "cold", "frozen": return [.blue, .purple]
        default: return [.gray, .white]
        }
    }
    
    // MARK: - Video Binding (stable slot pattern)
    
    /// Bind this card slot to a video â€” get or create player
    // MARK: - Thumbnail Loading
    
    /// Load thumbnail from NSCache synchronously, or fetch async on miss
    private func loadThumbnail() {
        // Try NSCache first — instant, no network
        if let cached = ThumbnailCache.shared.get(video.id) {
            cachedThumbnail = cached
            return
        }
        
        // Cache miss — fetch from thumbnailURL and store
        guard !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    ThumbnailCache.shared.set(image, for: video.id)
                    await MainActor.run { cachedThumbnail = image }
                }
            } catch {
                // Silent fail — player will show eventually
            }
        }
    }
    
    // MARK: - Video Binding
    
    private func bindVideo() {
        currentVideoID = video.id
        hasTrackedView = false
        creatorProfileURL = nil
        creatorDisplayName = nil
        
        // Protect if active card
        if shouldAutoPlay {
            preloadingService.markAsCurrentlyPlaying(video.id)
        }
        
        // Try pool first (instant)
        if let poolPlayer = preloadingService.getPlayer(for: video) {
            attachPlayer(poolPlayer)
            return
        }
        
        // Preload async with retry
        setupTask = Task {
            await preloadingService.preloadVideo(video, priority: shouldAutoPlay ? .high : .normal)
            
            // Re-protect after preload cycle
            if shouldAutoPlay {
                preloadingService.markAsCurrentlyPlaying(video.id)
            }
            
            // Check we haven't been rebound
            guard currentVideoID == video.id else { return }
            
            if let poolPlayer = preloadingService.getPlayer(for: video) {
                await MainActor.run { attachPlayer(poolPlayer) }
            } else if shouldAutoPlay {
                // One retry for the active card
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard currentVideoID == video.id else { return }
                await preloadingService.forcePreload(video)
                if let retryPlayer = preloadingService.getPlayer(for: video) {
                    await MainActor.run { attachPlayer(retryPlayer) }
                }
            }
        }
    }
    
    /// Attach a player and start playback if top card
    private func attachPlayer(_ newPlayer: AVPlayer) {
        self.player = newPlayer
        // isReady stays false until CustomVideoPlayerView fires onReadyForDisplay
        // Thumbnail stays visible underneath until then — no black flash
        
        if shouldAutoPlay {
            newPlayer.isMuted = muteManager.isMuted
            newPlayer.seek(to: .zero)
            newPlayer.play()
            setupLoopObserver()
            loadCreatorProfile()
            trackViewIfNeeded()
        }
    }
    
    /// Unbind current video (card slot getting new data)
    private func unbindCurrent() {
        setupTask?.cancel()
        setupTask = nil
        player?.pause()
        removeLoopObserver()
        player = nil
        isReady = false
    }
    
    /// Full teardown (view disappearing)
    private func teardown() {
        setupTask?.cancel()
        setupTask = nil
        player?.pause()
        removeLoopObserver()
    }
    
    private func setupLoopObserver() {
        guard let item = player?.currentItem else { return }
        removeLoopObserver()
        
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            self.player?.play()
            self.onVideoLoop(video.id)
        }
    }
    
    private func removeLoopObserver() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
    
    private func loadCreatorProfile() {
        guard !video.creatorID.isEmpty else { return }
        let creatorID = video.creatorID
        
        Task {
            let userService = UserService()
            if let profile = try? await userService.getUser(id: creatorID) {
                guard currentVideoID == video.id else { return }
                await MainActor.run {
                    self.creatorProfileURL = profile.profileImageURL
                    self.creatorDisplayName = profile.displayName.isEmpty ? profile.username : profile.displayName
                }
            }
        }
    }
    
    private func trackViewIfNeeded() {
        guard !hasTrackedView, let userID = Auth.auth().currentUser?.uid, !video.id.isEmpty else { return }
        hasTrackedView = true
        
        let trackedVideoID = video.id
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard currentVideoID == trackedVideoID else { return }
            let videoService = VideoService()
            try? await videoService.trackVideoView(videoID: trackedVideoID, userID: userID, watchTime: 5.0)
        }
    }
}
