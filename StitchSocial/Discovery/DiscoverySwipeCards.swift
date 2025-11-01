//
//  DiscoverySwipeCards.swift - BACK TO WORKING VERSION
//  StitchSocial
//
//  Layer 8: Views - Swipe Cards WITHOUT preloading complexity
//

import SwiftUI
import AVFoundation
import FirebaseAuth

struct DiscoverySwipeCards: View {
    
    // MARK: - Props
    let videos: [CoreVideoMetadata]
    @Binding var currentIndex: Int
    let onVideoTap: (CoreVideoMetadata) -> Void
    // Removed: onEngagement - Discovery cards don't need engagement
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
                ForEach(0..<min(maxCards, videos.count), id: \.self) { index in
                    if currentIndex + index < videos.count {
                        cardView(
                            video: videos[currentIndex + index],
                            index: index
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60)
            .padding(.vertical, 80)
        }
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
        .scaleEffect(scale)
        .offset(x: offset.width, y: offset.height + stackOffset)
        .rotationEffect(.degrees(isTopCard ? dragRotation : 0))
        .opacity(index < 2 ? 1.0 : 0.5)
        .zIndex(Double(maxCards - index))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if isTopCard && !isSwipeInProgress {
                        handleDragChanged(value: value)
                    }
                }
                .onEnded { value in
                    if isTopCard && !isSwipeInProgress {
                        handleDragEnded(value: value)
                    }
                }
        )
        .onTapGesture {
            if isTopCard {
                onVideoTap(video)
            }
        }
    }
    
    // MARK: - Drag Handling - ✅ LEFT/RIGHT NAVIGATION
    
    private func handleDragChanged(value: DragGesture.Value) {
        dragOffset = value.translation
        dragRotation = Double(value.translation.width / 20)
    }
    
    private func handleDragEnded(value: DragGesture.Value) {
        let translation = value.translation
        let velocity = value.velocity
        
        // Determine if swipe is primarily horizontal or vertical
        let isHorizontalSwipe = abs(translation.width) > abs(translation.height)
        
        if isHorizontalSwipe {
            // ✅ HORIZONTAL SWIPE = Navigation (Left/Right)
            if abs(translation.width) > swipeThreshold || abs(velocity.width) > 500 {
                isSwipeInProgress = true
                
                if translation.width > 0 {
                    // ✅ SWIPE RIGHT = Go to PREVIOUS video
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                    }
                    
                    DispatchQueue.main.async {
                        previousCard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSwipeInProgress = false
                        }
                    }
                } else {
                    // ✅ SWIPE LEFT = Go to NEXT video
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                    }
                    
                    DispatchQueue.main.async {
                        nextCard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSwipeInProgress = false
                        }
                    }
                }
            } else {
                // Snap back if threshold not met
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    resetCardPosition()
                }
            }
        } else {
            // ✅ VERTICAL SWIPE = Dismiss/Any direction swipe
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
                
                DispatchQueue.main.async {
                    nextCard()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSwipeInProgress = false
                    }
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            nextCard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSwipeInProgress = false
            }
        }
    }
    
    // MARK: - Navigation - ✅ WITH HISTORY
    
    private func nextCard() {
        if currentIndex + 1 < videos.count {
            currentIndex += 1
        } else {
            print("🔄 DISCOVERY SWIPE: Reached end, waiting for more content...")
        }
        
        resetCardPosition()
        
        // Clear old loop counts
        if currentIndex > 10 {
            let oldVideoID = videos[currentIndex - 10].id
            loopCounts.removeValue(forKey: oldVideoID)
        }
    }
    
    // ✅ NEW: Go back to previous video
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

// MARK: - Discovery Card Component (SIMPLE)

struct DiscoveryCard: View {
    let video: CoreVideoMetadata
    let shouldAutoPlay: Bool
    let onVideoLoop: (String) -> Void
    
    @State private var hasTrackedView = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if shouldAutoPlay {
                    VideoPlayerView(
                        video: video,
                        isActive: true,
                        onEngagement: { _ in }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .id(video.id)
                    .allowsHitTesting(false)
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        onVideoLoop(video.id)
                    }
                } else {
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(ProgressView().tint(.white))
                    }
                    .allowsHitTesting(false)
                }
                
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            }
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            // Track view when card appears (only for top card)
            if shouldAutoPlay, !hasTrackedView, let userID = Auth.auth().currentUser?.uid {
                // ✅ VALIDATE: Ensure videoID is not empty before tracking
                guard !video.id.isEmpty else {
                    print("❌ VIEW TRACKING: Skipped - empty video ID")
                    return
                }
                
                hasTrackedView = true
                
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    
                    let videoService = VideoService()
                    
                    // ✅ DOUBLE CHECK: Validate IDs before Firebase call
                    guard !video.id.isEmpty, !userID.isEmpty else {
                        print("❌ VIEW TRACKING: Invalid IDs - videoID: '\(video.id)', userID: '\(userID)'")
                        return
                    }
                    
                    do {
                        try await videoService.trackVideoView(
                            videoID: video.id,
                            userID: userID,
                            watchTime: 5.0
                        )
                        print("📊 VIEW TRACKED: \(video.id.prefix(8)) in Discovery")
                    } catch {
                        print("❌ VIEW TRACKING ERROR: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
