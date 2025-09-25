//
//  DiscoverySwipeCards.swift
//  StitchSocial
//
//  Layer 8: Views - Tinder-style Swipe Cards for Discovery
//  Dependencies: CoreVideoMetadata, EngagementProtocols
//  Features: Simple swipe gestures, fullscreen navigation, clean card stack
//

import SwiftUI

struct DiscoverySwipeCards: View {
    
    // MARK: - Props
    let videos: [CoreVideoMetadata]
    @Binding var currentIndex: Int
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onEngagement: (InteractionType, CoreVideoMetadata) -> Void
    let onNavigateToProfile: (String) -> Void
    let onNavigateToThread: (String) -> Void
    
    // MARK: - State
    @State private var dragOffset = CGSize.zero
    @State private var dragRotation: Double = 0
    @State private var swipeProgress: Double = 0
    @State private var isSwipeInProgress = false // NEW: Prevent double-swipes
    
    // MARK: - Configuration
    private let maxCards = 3
    private let swipeThreshold: CGFloat = 100
    
    var body: some View {
        print("🎯 SWIPE CARDS DEBUG:")
        print("   - Total videos: \(videos.count)")
        print("   - Current index: \(currentIndex)")
        print("   - Cards to show: \(min(maxCards, videos.count))")
        
        if !videos.isEmpty {
            for i in 0..<min(3, videos.count) {
                if currentIndex + i < videos.count {
                    print("   - Card \(i): Video '\(videos[currentIndex + i].title)' (ID: \(videos[currentIndex + i].id))")
                }
            }
        }
        
        return GeometryReader { geometry in
            ZStack {
                ForEach(0..<min(maxCards, videos.count), id: \.self) { index in
                    if currentIndex + index < videos.count {
                        cardView(
                            video: videos[currentIndex + index],
                            index: index,
                            geometry: geometry
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 60) // More padding for better centering
            .padding(.vertical, 80)   // Back to middle position - between 60 and 100
        }
    }
    
    // MARK: - Card View
    
    private func cardView(video: CoreVideoMetadata, index: Int, geometry: GeometryProxy) -> some View {
        let isTopCard = index == 0
        let offset = isTopCard ? dragOffset : CGSize.zero
        let scale = 1.0 - (Double(index) * 0.05)
        let yOffset = Double(index) * 10
        
        return VideoCardView(video: video, shouldAutoPlay: isTopCard)
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height + yOffset)
            .rotationEffect(.degrees(isTopCard ? dragRotation : 0))
            .opacity(index < 2 ? 1.0 : 0.5)
            .zIndex(Double(maxCards - index))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if isTopCard && !isSwipeInProgress {
                            print("🎯 SWIPE: Drag detected - \(value.translation)")
                            dragOffset = value.translation
                            dragRotation = Double(value.translation.width / 20)
                            swipeProgress = min(abs(value.translation.width) / swipeThreshold, 1.0)
                        }
                    }
                    .onEnded { value in
                        if isTopCard && !isSwipeInProgress {
                            print("🎯 SWIPE: Drag ended - \(value.translation)")
                            isSwipeInProgress = true // LOCK to prevent double-processing
                            handleSwipeEnd(value: value)
                        }
                    }
            )
            .onTapGesture {
                if isTopCard {
                    print("🎯 CARD TAP: Detected tap on video: \(video.title)")
                    print("🎯 CARD TAP: Calling onVideoTap callback")
                    onVideoTap(video)
                }
            }
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                dragRotation = Double(value.translation.width / 20)
                
                let progress = abs(value.translation.width) / swipeThreshold
                swipeProgress = min(progress, 1.0)
            }
            .onEnded { value in
                handleSwipeEnd(value: value)
            }
    }
    
    // MARK: - Swipe Handling
    
    private func handleSwipeEnd(value: DragGesture.Value) {
        let translation = value.translation
        let velocity = value.velocity
        
        print("🎯 SWIPE END: Translation X: \(translation.width), Velocity: \(velocity.width)")
        
        // Determine swipe direction
        if abs(translation.width) > swipeThreshold || abs(velocity.width) > 500 {
            print("🎯 SWIPE END: Threshold met - processing swipe")
            
            if translation.width > 0 {
                // Right swipe = Hype
                print("🎯 SWIPE END: Right swipe = HYPE")
                handleEngagement(.hype)
            } else {
                // Left swipe = Cool
                print("🎯 SWIPE END: Left swipe = COOL")
                handleEngagement(.cool)
            }
            
            // Move to next card
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dragOffset = CGSize(width: translation.width > 0 ? 1000 : -1000, height: 0)
            }
            
            // IMMEDIATE INDEX UPDATE - Don't wait for animation
            DispatchQueue.main.async {
                self.nextCard()
                // UNLOCK after processing complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isSwipeInProgress = false
                }
            }
            
        } else {
            print("🎯 SWIPE END: Threshold not met - returning to center")
            // Return to center
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                resetCardPosition()
            }
            // UNLOCK immediately for failed swipes
            isSwipeInProgress = false
        }
    }
    
    // MARK: - Card Actions
    
    private func handleEngagement(_ type: InteractionType) {
        guard currentIndex < videos.count else {
            print("❌ ENGAGEMENT ERROR: currentIndex \(currentIndex) >= videos.count \(videos.count)")
            return
        }
        let video = videos[currentIndex]
        print("🎯 ENGAGEMENT: Processing \(type.rawValue) for video: '\(video.title)' (ID: \(video.id)) at index \(currentIndex)")
        onEngagement(type, video)
    }
    
    private func nextCard() {
        print("🎯 NEXT CARD: About to move from index \(currentIndex)")
        if let currentVideo = currentIndex < videos.count ? videos[currentIndex] : nil {
            print("🎯 NEXT CARD: Current video: '\(currentVideo.title)' (ID: \(currentVideo.id))")
        }
        
        // Move to next video IMMEDIATELY without animation delay
        if currentIndex + 1 < videos.count {
            currentIndex += 1
            print("🎯 NEXT CARD: Moved to index \(currentIndex)")
        } else {
            // Reset to beginning for infinite loop
            currentIndex = 0
            print("🎯 NEXT CARD: Reset to beginning (index 0)")
        }
        
        if let newVideo = currentIndex < videos.count ? videos[currentIndex] : nil {
            print("🎯 NEXT CARD: New video: '\(newVideo.title)' (ID: \(newVideo.id))")
        }
        
        // FORCE IMMEDIATE RESET - No animation delay
        resetCardPosition()
        
        // Force SwiftUI to refresh the view hierarchy
        DispatchQueue.main.async {
            // This empty closure forces a UI update cycle
        }
    }
    
    private func resetCardPosition() {
        dragOffset = .zero
        dragRotation = 0
        swipeProgress = 0
        // Don't reset isSwipeInProgress here - it's managed by the swipe handler
    }
}

// MARK: - Video Card View

struct VideoCardView: View {
    let video: CoreVideoMetadata
    let shouldAutoPlay: Bool
    
    var body: some View {
        ZStack {
            // Auto-playing Video or Thumbnail
            if shouldAutoPlay {
                VideoPlayerView(
                    video: video,
                    isActive: true,
                    onEngagement: { _ in }
                )
                .id(video.id) // CRITICAL: Force VideoPlayer refresh when video changes
                .allowsHitTesting(false) // CRITICAL: Disable video touch events
            } else {
                // Video Thumbnail
                AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
                .clipped()
                .allowsHitTesting(false) // CRITICAL: Disable thumbnail touch events
            }
            
            // Transparent gesture overlay to ensure touches reach swipe gesture
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle()) // Make entire area receive touches
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return "\(count)"
        }
    }
}
