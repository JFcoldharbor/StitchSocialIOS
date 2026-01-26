//
//  DiscoverySwipeCards.swift - SEAMLESS FULLSCREEN TRANSITION
//  StitchSocial
//
//  Layer 8: Views - Swipe Cards with shared player pool
//  Video continues playing seamlessly between card and fullscreen
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth

struct DiscoverySwipeCards: View {
    
    // MARK: - Props
    let videos: [CoreVideoMetadata]
    @Binding var currentIndex: Int
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onNavigateToProfile: (String) -> Void
    let onNavigateToThread: (String) -> Void
    
    // MARK: - State
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
                // Render cards in reverse order so top card is rendered last (on top)
                ForEach(Array(visibleVideos.enumerated()).reversed(), id: \.element.id) { index, video in
                    cardView(
                        video: video,
                        index: index
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60)
            .padding(.vertical, 80)
        }
    }
    
    // Computed property for visible videos
    private var visibleVideos: [CoreVideoMetadata] {
        var result: [CoreVideoMetadata] = []
        for i in 0..<maxCards {
            let videoIndex = currentIndex + i
            if videoIndex < videos.count {
                result.append(videos[videoIndex])
            }
        }
        return result
    }
    
    // MARK: - Card View
    
    private func cardView(video: CoreVideoMetadata, index: Int) -> some View {
        let isTopCard = index == 0
        let offset = isTopCard ? dragOffset : CGSize.zero
        let scale = 1.0 - (Double(index) * 0.05)
        let stackOffset = Double(index) * 10
        
        return DiscoveryCard(
            video: video,
            shouldAutoPlay: isTopCard,
            onVideoLoop: { videoID in
                handleVideoLoop(videoID: videoID)
            }
        )
        .id(video.id) // CRITICAL: Force new view when video changes
        .scaleEffect(scale)
        .offset(x: offset.width, y: offset.height + stackOffset)
        .rotationEffect(.degrees(isTopCard ? dragRotation : 0))
        .opacity(index < 2 ? 1.0 : 0.5)
        .zIndex(Double(maxCards - index)) // Ensure correct layering
        .allowsHitTesting(isTopCard) // Only top card responds to gestures
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
                onVideoTap(video)
            }
        }
    }
    
    // MARK: - Drag Handling - LEFT/RIGHT NAVIGATION
    
    private func handleDragChanged(value: DragGesture.Value) {
        dragOffset = value.translation
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
                    // SWIPE RIGHT = Go to PREVIOUS video
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                    }
                    
                    // FIXED: Delay index change until AFTER animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        previousCard()
                        isSwipeInProgress = false
                    }
                } else {
                    // SWIPE LEFT = Go to NEXT video
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                    }
                    
                    // FIXED: Delay index change until AFTER animation
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
            let totalTranslation = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
            let totalVelocity = sqrt(pow(velocity.width, 2) + pow(velocity.height, 2))
            
            if totalTranslation > swipeThreshold || totalVelocity > 500 {
                isSwipeInProgress = true
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    dragOffset = CGSize(
                        width: translation.width * 3,
                        height: translation.height * 3
                    )
                }
                
                // FIXED: Delay index change until AFTER animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    nextCard()
                    isSwipeInProgress = false
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    resetCardPosition()
                }
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
        guard !isSwipeInProgress else { return }
        isSwipeInProgress = true
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: 0, height: -1000)
        }
        
        // FIXED: Delay index change until AFTER animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            nextCard()
            isSwipeInProgress = false
        }
    }
    
    // MARK: - Navigation
    
    private func nextCard() {
        if currentIndex + 1 < videos.count {
            currentIndex += 1
        } else {
            print("🔄 DISCOVERY SWIPE: Reached end, waiting for more content...")
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
            print("⬅️ DISCOVERY SWIPE: Going back to video \(currentIndex)")
        } else {
            print("⬅️ DISCOVERY SWIPE: Already at first video")
        }
        
        resetCardPosition()
    }
    
    private func resetCardPosition() {
        dragOffset = .zero
        dragRotation = 0
    }
}

// MARK: - Discovery Card Component (SIMPLIFIED - VIDEO ONLY)

struct DiscoveryCard: View {
    let video: CoreVideoMetadata
    let shouldAutoPlay: Bool
    let onVideoLoop: (String) -> Void
    
    // Use shared preloading service
    private var preloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var hasTrackedView = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var creatorProfileURL: String? = nil
    @State private var creatorDisplayName: String? = nil
    
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
                // Background
                Color.black
                
                // Video Player - always try to show if we have a player
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .disabled(true)
                } else {
                    // Loading state
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                
                // Overlay - only show on top card
                if shouldAutoPlay {
                    cardOverlay
                }
                
                // Tap target
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            setupPlayer()
            if shouldAutoPlay {
                loadCreatorProfile()
                trackViewIfNeeded()
            }
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: shouldAutoPlay) { _, isTop in
            if isTop {
                // Became top card - play
                player?.isMuted = false
                player?.play()
                setupLoopObserver()
                loadCreatorProfile()
                print("▶️ CARD NOW TOP: \(video.id.prefix(8))")
            } else {
                // No longer top - pause
                player?.pause()
                removeLoopObserver()
                print("⏸️ CARD NO LONGER TOP: \(video.id.prefix(8))")
            }
        }
    }
    
    // MARK: - Card Overlay
    
    private var cardOverlay: some View {
        VStack {
            // ⭐ MOVED: Reply badge at top
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
                .shadow(
                    color: .cyan.opacity(0.6),
                    radius: 6,
                    x: 0,
                    y: 0
                )
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
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        // Get from pool first
        if let poolPlayer = preloadingService.getPlayer(for: video) {
            self.player = poolPlayer
            
            if shouldAutoPlay {
                poolPlayer.isMuted = false
                if poolPlayer.rate == 0 {
                    poolPlayer.play()
                }
                setupLoopObserver()
            } else {
                // Background card - keep paused, show first frame
                poolPlayer.pause()
            }
            
            isReady = true
            print("🎬 CARD: Got player for \(video.id.prefix(8)), autoplay: \(shouldAutoPlay)")
            return
        }
        
        // Preload if not in pool
        Task {
            await preloadingService.preloadVideo(video, priority: shouldAutoPlay ? .high : .normal)
            
            if let poolPlayer = preloadingService.getPlayer(for: video) {
                await MainActor.run {
                    self.player = poolPlayer
                    
                    if shouldAutoPlay {
                        poolPlayer.isMuted = false
                        poolPlayer.play()
                        setupLoopObserver()
                    } else {
                        poolPlayer.pause()
                    }
                    
                    isReady = true
                }
            }
        }
    }
    
    private func cleanup() {
        player?.pause()
        removeLoopObserver()
        print("🧹 CARD CLEANUP: \(video.id.prefix(8))")
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
        
        Task {
            let userService = UserService()
            if let profile = try? await userService.getUser(id: video.creatorID) {
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
        
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let videoService = VideoService()
            try? await videoService.trackVideoView(videoID: video.id, userID: userID, watchTime: 5.0)
            print("📊 VIEW TRACKED: \(video.id.prefix(8))")
        }
    }
}
