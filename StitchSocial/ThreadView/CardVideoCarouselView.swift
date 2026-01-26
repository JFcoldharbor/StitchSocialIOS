//
//  CardVideoCarouselView.swift
//  StitchSocial
//
//  Layer 8: Views - Card-based Video Carousel with Real Video Players
//  REDESIGNED: Discovery-style cards matching ThreadView
//

import SwiftUI
import AVFoundation

struct CardVideoCarouselView: View {
    
    // MARK: - Properties
    let videos: [CoreVideoMetadata]
    let parentVideo: CoreVideoMetadata?
    let startingIndex: Int
    let currentUserID: String?
    let directReplies: [CoreVideoMetadata]?
    let onSelectReply: ((CoreVideoMetadata) -> Void)?
    
    // MARK: - State
    @State private var currentIndex: Int
    @State private var isPlaying: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var hasAppeared = false
    @State private var currentConversationPartner: String?
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Brand Colors
    private let brandCyan = Color(red: 0.0, green: 0.85, blue: 0.95)
    private let brandPurple = Color(red: 0.6, green: 0.4, blue: 0.95)
    private let brandPink = Color(red: 0.95, green: 0.4, blue: 0.7)
    private let brandCream = Color(red: 0.98, green: 0.97, blue: 0.96)
    private let brandDark = Color(red: 0.1, green: 0.1, blue: 0.15)
    
    // MARK: - Computed Properties
    
    private var conversationParticipantIDs: Set<String> {
        Set(videos.map { $0.creatorID })
    }
    
    private var isConversationParticipant: Bool {
        guard let userID = currentUserID else { return false }
        return conversationParticipantIDs.contains(userID)
    }
    
    init(
        videos: [CoreVideoMetadata],
        parentVideo: CoreVideoMetadata?,
        startingIndex: Int = 0,
        currentUserID: String? = nil,
        directReplies: [CoreVideoMetadata]? = nil,
        onSelectReply: ((CoreVideoMetadata) -> Void)? = nil
    ) {
        self.videos = videos
        self.parentVideo = parentVideo
        self.startingIndex = startingIndex
        self.currentUserID = currentUserID
        self.directReplies = directReplies
        self.onSelectReply = onSelectReply
        self._currentIndex = State(initialValue: startingIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Marble background (matching ThreadView)
                marbleBackground(in: geometry)
                
                VStack(spacing: 0) {
                    // Header
                    carouselHeader
                    
                    Spacer()
                    
                    // Main carousel
                    cardCarouselView(in: geometry)
                        .offset(dragOffset)
                    
                    Spacer()
                    
                    // Bottom section
                    if let replies = directReplies, !replies.isEmpty {
                        ConversationNavigationBar(
                            parentVideo: videos.first ?? parentVideo!,
                            directReplies: replies,
                            currentConversationPartner: currentConversationPartner,
                            onSelectReply: { selectedReply in
                                currentConversationPartner = selectedReply.creatorID
                                onSelectReply?(selectedReply)
                            }
                        )
                    } else {
                        bottomControls
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .gesture(dismissGesture)
        .onAppear {
            hasAppeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPlaying = true
            }
        }
        .onDisappear {
            isPlaying = false
            hasAppeared = false
        }
    }
    
    // MARK: - Marble Background
    
    private func marbleBackground(in geometry: GeometryProxy) -> some View {
        ZStack {
            brandCream
            
            Circle()
                .fill(brandCyan)
                .frame(width: geometry.size.width * 1.2)
                .blur(radius: 80)
                .opacity(0.4)
                .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.15)
            
            Circle()
                .fill(brandPurple)
                .frame(width: geometry.size.width * 1.0)
                .blur(radius: 90)
                .opacity(0.35)
                .position(x: geometry.size.width * 0.85, y: geometry.size.height * 0.4)
            
            Circle()
                .fill(brandPink)
                .frame(width: geometry.size.width * 0.9)
                .blur(radius: 70)
                .opacity(0.3)
                .position(x: geometry.size.width * 0.1, y: geometry.size.height * 0.75)
            
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.05)],
                center: .center,
                startRadius: geometry.size.width * 0.3,
                endRadius: geometry.size.width
            )
        }
    }
    
    // MARK: - Header
    
    private var carouselHeader: some View {
        VStack(spacing: 8) {
            // Top bar with close button
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(brandDark)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.1), radius: 8)
                        )
                }
                
                Spacer()
                
                // Handle indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(brandDark.opacity(0.3))
                    .frame(width: 40, height: 4)
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Context information
            if let parent = parentVideo {
                VStack(spacing: 4) {
                    Text("Replies to \(parent.creatorName)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(brandDark)
                    
                    Text("\(videos.count) replies")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(brandDark.opacity(0.7))
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Card Carousel
    
    private func cardCarouselView(in geometry: GeometryProxy) -> some View {
        let cardWidth: CGFloat = geometry.size.width * 0.58
        let cardHeight: CGFloat = cardWidth * 1.4
        
        return ZStack {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                CarouselDiscoveryCard(
                    video: video,
                    isActive: index == currentIndex,
                    isPlaying: isPlaying && index == currentIndex,
                    isConversationParticipant: isConversationParticipant,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    brandCyan: brandCyan,
                    brandPurple: brandPurple
                )
                .scaleEffect(getCardScale(for: index))
                .offset(x: getCardOffset(for: index, cardWidth: cardWidth), y: 0)
                .opacity(getCardOpacity(for: index))
                .zIndex(getCardZIndex(for: index))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentIndex)
            }
        }
        .frame(height: cardHeight + 40)
        .gesture(horizontalSwipeGesture)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 16) {
            progressIndicator
            
            Text("\(currentIndex + 1) of \(videos.count)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(brandDark.opacity(0.8))
            
            actionButtons
            
            Text("Swipe up or down to close")
                .font(.system(size: 12))
                .foregroundColor(brandDark.opacity(0.5))
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<videos.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? brandPurple : brandDark.opacity(0.3))
                    .frame(width: index == currentIndex ? 8 : 6, height: index == currentIndex ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 32) {
            Button(action: previousVideo) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentIndex > 0 ? brandDark.opacity(0.7) : brandDark.opacity(0.3))
            }
            .disabled(currentIndex <= 0)
            
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(brandPurple)
            }
            
            Button(action: nextVideo) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentIndex < videos.count - 1 ? brandDark.opacity(0.7) : brandDark.opacity(0.3))
            }
            .disabled(currentIndex >= videos.count - 1)
        }
    }
    
    // MARK: - Actions
    
    private func togglePlayback() {
        isPlaying.toggle()
    }
    
    private func previousVideo() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
    
    private func nextVideo() {
        guard currentIndex < videos.count - 1 else { return }
        currentIndex += 1
    }
    
    private func dismissCarousel() {
        dismiss()
    }
    
    // MARK: - Gestures
    
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Allow both up and down vertical drag
                if abs(value.translation.height) > abs(value.translation.width) {
                    let resistance: CGFloat = 0.6
                    dragOffset = CGSize(width: 0, height: value.translation.height * resistance)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                let velocityThreshold: CGFloat = 500
                let velocity = value.predictedEndTranslation.height - value.translation.height
                
                // Dismiss on swipe down OR swipe up
                if abs(value.translation.height) > threshold || abs(velocity) > velocityThreshold {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dismissCarousel()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }
    
    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    let resistance: CGFloat = 0.8
                    dragOffset = CGSize(width: value.translation.width * resistance, height: 0)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 30
                let velocityThreshold: CGFloat = 300
                let velocity = value.predictedEndTranslation.width - value.translation.width
                
                if abs(value.translation.width) > threshold || abs(velocity) > velocityThreshold {
                    if (value.translation.width > 0 || velocity > 0) && currentIndex > 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            previousVideo()
                        }
                    } else if (value.translation.width < 0 || velocity < 0) && currentIndex < videos.count - 1 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            nextVideo()
                        }
                    }
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = .zero
                }
            }
    }
    
    // MARK: - Card Layout Helpers
    
    private func getCardScale(for index: Int) -> CGFloat {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.88
        default: return 0.75
        }
    }
    
    private func getCardOffset(for index: Int, cardWidth: CGFloat) -> CGFloat {
        let diff = CGFloat(index - currentIndex)
        return diff * (cardWidth * 0.4)
    }
    
    private func getCardOpacity(for index: Int) -> Double {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.85
        default: return 0.5
        }
    }
    
    private func getCardZIndex(for index: Int) -> Double {
        return Double(videos.count - abs(index - currentIndex))
    }
}

// MARK: - Carousel Discovery Card (Matching ThreadView style)

private struct CarouselDiscoveryCard: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    let isPlaying: Bool
    let isConversationParticipant: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let brandCyan: Color
    let brandPurple: Color
    
    private let brandPink = Color(red: 0.95, green: 0.4, blue: 0.7)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if isActive {
                // Active card - show video player
                ZStack(alignment: .bottom) {
                    // Video player fills card
                    VideoPlayerView(
                        video: video,
                        isActive: isActive && isPlaying,
                        onEngagement: { _ in },
                        overlayContext: .carousel,
                        isConversationParticipant: isConversationParticipant
                    )
                    
                    // Loading overlay with thumbnail
                    if !isPlaying {
                        ZStack {
                            // Thumbnail background
                            thumbnailLayer
                            
                            // Subtle loading indicator
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.2)
                            }
                        }
                        .transition(.opacity)
                    }
                    
                    // Bottom gradient + CreatorPill (only when not playing, since overlay handles it)
                    if !isPlaying {
                        bottomOverlay
                    }
                }
                .animation(.easeOut(duration: 0.3), value: isPlaying)
            } else {
                // Inactive card - Discovery style preview
                thumbnailLayer
                bottomOverlay
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isActive
                            ? [brandCyan.opacity(0.6), brandPurple.opacity(0.6)]
                            : [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 2 : 1
                )
        )
        .shadow(
            color: isActive ? brandPurple.opacity(0.4) : Color.black.opacity(0.2),
            radius: isActive ? 20 : 10,
            y: 10
        )
    }
    
    private var thumbnailLayer: some View {
        ZStack {
            // Gradient background fallback
            LinearGradient(
                colors: [brandPurple.opacity(0.4), brandCyan.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Thumbnail
            if !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    private var bottomOverlay: some View {
        VStack {
            Spacer()
            
            // Gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cardHeight * 0.4)
            
            // Content overlay
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                
                CreatorPill(
                    creator: video,
                    isThread: false,
                    colors: [brandCyan, brandPurple],
                    displayName: video.creatorName,
                    profileImageURL: nil,
                    onTap: { }
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
