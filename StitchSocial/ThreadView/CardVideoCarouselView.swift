//
//  CardVideoCarouselView.swift
//  StitchSocial
//
//  Layer 8: Views - Card-based Video Carousel with Real Video Players
//  Dependencies: VideoPlayerView, CoreVideoMetadata, InteractionType
//  Features: Swipeable video cards, proper video playback, gesture controls
//

import SwiftUI
import AVFoundation

struct CardVideoCarouselView: View {
    
    // MARK: - Properties
    let videos: [CoreVideoMetadata]
    let parentVideo: CoreVideoMetadata?
    let startingIndex: Int
    
    // MARK: - State
    @State private var currentIndex: Int
    @State private var isPlaying: Bool = true
    @State private var dragOffset: CGSize = .zero
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Constants
    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 500
    
    init(videos: [CoreVideoMetadata], parentVideo: CoreVideoMetadata?, startingIndex: Int = 0) {
        self.videos = videos
        self.parentVideo = parentVideo
        self.startingIndex = startingIndex
        self._currentIndex = State(initialValue: startingIndex)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                carouselHeader
                
                Spacer()
                
                // Main carousel
                cardCarouselView
                    .offset(dragOffset)
                
                Spacer()
                
                // Bottom controls
                bottomControls
                    .padding(.bottom, 40)
            }
        }
        .gesture(dismissGesture)
        .onAppear {
            print("🎬 CAROUSEL: Appeared with \(videos.count) videos")
        }
        .onDisappear {
            print("🎬 CAROUSEL: Disappeared")
        }
    }
    
    // MARK: - Header
    
    private var carouselHeader: some View {
        VStack(spacing: 8) {
            // Handle indicator for swipe-to-dismiss
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 20)
            
            // Context information
            if let parent = parentVideo {
                VStack(spacing: 4) {
                    Text("Replies to \(parent.creatorName)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(videos.count) replies")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 16)
            }
        }
    }
    
    // MARK: - Card Carousel
    
    private var cardCarouselView: some View {
        ZStack {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                VideoCard(
                    video: video,
                    isActive: index == currentIndex,
                    isPlaying: isPlaying && index == currentIndex,
                    onTogglePlay: togglePlayback,
                    onDoubleTap: { handleDoubleTap(video) }
                )
                .scaleEffect(getCardScale(for: index))
                .offset(x: getCardOffset(for: index), y: 0)
                .opacity(getCardOpacity(for: index))
                .zIndex(getCardZIndex(for: index))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentIndex)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .gesture(horizontalSwipeGesture)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Progress indicator
            progressIndicator
            
            // Video counter
            Text("\(currentIndex + 1) of \(videos.count)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            // Action buttons
            actionButtons
            
            // Dismiss hint
            Text("Swipe down to close")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<videos.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentIndex ? 8 : 6, height: index == currentIndex ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 32) {
            // Previous button
            Button(action: previousVideo) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.3))
            }
            .disabled(currentIndex <= 0)
            
            // Play/pause button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            
            // Next button
            Button(action: nextVideo) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentIndex < videos.count - 1 ? .white : .white.opacity(0.3))
            }
            .disabled(currentIndex >= videos.count - 1)
        }
    }
    
    // MARK: - Actions
    
    private func togglePlayback() {
        isPlaying.toggle()
        print("🎬 CAROUSEL: Playback toggled - Playing: \(isPlaying)")
    }
    
    private func previousVideo() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        print("🎬 CAROUSEL: Navigated to previous video (index: \(currentIndex))")
    }
    
    private func nextVideo() {
        guard currentIndex < videos.count - 1 else { return }
        currentIndex += 1
        print("🎬 CAROUSEL: Navigated to next video (index: \(currentIndex))")
    }
    
    private func handleDoubleTap(_ video: CoreVideoMetadata) {
        print("🎬 CAROUSEL: Double tapped video: \(video.title)")
        // TODO: Integrate with engagement system - handle hype/cool interactions
    }
    
    private func dismissCarousel() {
        print("🎬 CAROUSEL: Dismissing carousel")
        dismiss()
    }
    
    // MARK: - Gestures
    
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                if value.translation.height > 150 {
                    dismissCarousel()
                } else {
                    dragOffset = .zero
                }
            }
    }
    
    private var horizontalSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 50
                
                if abs(value.translation.width) > threshold {
                    if value.translation.width > 0 && currentIndex > 0 {
                        previousVideo()
                    } else if value.translation.width < 0 && currentIndex < videos.count - 1 {
                        nextVideo()
                    }
                }
                
                dragOffset = .zero
            }
    }
    
    // MARK: - Card Layout Helpers
    
    private func getCardScale(for index: Int) -> CGFloat {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.85
        default: return 0.7
        }
    }
    
    private func getCardOffset(for index: Int) -> CGFloat {
        let diff = CGFloat(index - currentIndex)
        let maxOffset: CGFloat = 80
        
        if abs(diff) <= 1 {
            return diff * 60
        } else {
            return diff > 0 ? maxOffset : -maxOffset
        }
    }
    
    private func getCardOpacity(for index: Int) -> Double {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.8
        case 2: return 0.6
        default: return 0.4
        }
    }
    
    private func getCardZIndex(for index: Int) -> Double {
        return Double(videos.count - abs(index - currentIndex))
    }
}

// MARK: - VideoCard Component (FIXED WITH REAL VIDEO PLAYER)

private struct VideoCard: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    let isPlaying: Bool
    let onTogglePlay: () -> Void
    let onDoubleTap: () -> Void
    
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.black)
            .overlay(videoCardContent)
            .frame(width: 340, height: 500)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .onTapGesture {
                if isActive {
                    onTogglePlay()
                }
            }
            .onTapGesture(count: 2) {
                if isActive {
                    onDoubleTap()
                }
            }
    }
    
    private var videoCardContent: some View {
        ZStack {
            // REAL VIDEO PLAYER (FIXED)
            if isActive {
                VideoPlayerView(
                    video: video,
                    isActive: isActive && isPlaying,
                    onEngagement: { type in
                        // Handle engagement through parent callback
                        print("🎬 CARD: Engagement \(type) on video \(video.title)")
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                // Static preview for inactive cards
                videoPreview
            }
            
            // Overlay controls (only show when paused and active)
            if isActive && !isPlaying {
                playPauseOverlay
            }
            
            // Video metadata overlay
            videoMetadataOverlay
        }
    }
    
    // MARK: - Video Preview (for inactive cards)
    
    private var videoPreview: some View {
        ZStack {
            // Background color
            Color.gray.opacity(0.2)
            
            // Thumbnail placeholder (could be enhanced with actual thumbnails)
            VStack {
                Spacer()
                
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(video.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Play/Pause Overlay
    
    private var playPauseOverlay: some View {
        Button(action: onTogglePlay) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 80, height: 80)
                )
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Video Metadata Overlay
    
    private var videoMetadataOverlay: some View {
        VStack {
            Spacer()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.creatorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(video.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Engagement indicators (could be enhanced)
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    
                    Text("\(video.hypeCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}
