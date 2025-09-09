//
//  CardVideoCarouselView.swift
//  StitchSocial
//
//  Layer 8: Views - Dedicated Card-Based Video Carousel
//  Dependencies: CoreVideoMetadata (Layer 3) ONLY
//  Features: Focused video experience with card-based navigation
//  ARCHITECTURE COMPLIANT: Pure UI component, no business logic
//

import SwiftUI
import AVFoundation

// MARK: - CardVideoCarouselView

struct CardVideoCarouselView: View {
    
    // MARK: - Properties
    let videos: [CoreVideoMetadata]
    let parentVideo: CoreVideoMetadata?
    let startingIndex: Int
    
    // MARK: - UI State
    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @State private var isPlaying: Bool = true
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Configuration
    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 500
    private let cornerRadius: CGFloat = 24
    
    // MARK: - Initialization
    init(videos: [CoreVideoMetadata], parentVideo: CoreVideoMetadata? = nil, startingIndex: Int = 0) {
        self.videos = videos
        self.parentVideo = parentVideo
        self.startingIndex = startingIndex
        self._currentIndex = State(initialValue: startingIndex)
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            backgroundOverlay
            
            // Main Content
            VStack(spacing: 0) {
                // Header
                carouselHeader
                
                Spacer()
                
                // Card carousel
                cardCarouselView
                
                Spacer()
                
                // Bottom controls
                bottomControls
                    .padding(.bottom, 50)
            }
        }
        .gesture(dismissGesture)
        .offset(y: dragOffset.height * 0.3)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dragOffset)
        .onAppear {
            print("🎬 CAROUSEL: Opened with \(videos.count) videos, starting at index \(startingIndex)")
        }
    }
    
    // MARK: - Background Overlay
    
    private var backgroundOverlay: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .onTapGesture {
                dismissCarousel()
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
        case 1: return 0.7
        default: return 0.3
        }
    }
    
    private func getCardZIndex(for index: Int) -> Double {
        return Double(videos.count - abs(index - currentIndex))
    }
    
    // MARK: - Actions
    
    private func nextVideo() {
        guard currentIndex < videos.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex += 1
        }
        print("🎬 CAROUSEL: Next video - now at index \(currentIndex)")
    }
    
    private func previousVideo() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex -= 1
        }
        print("🎬 CAROUSEL: Previous video - now at index \(currentIndex)")
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        print("🎬 CAROUSEL: Playback toggled - isPlaying: \(isPlaying)")
    }
    
    private func handleDoubleTap(_ video: CoreVideoMetadata) {
        // Handle double tap action (hype, like, etc.)
        print("🎬 CAROUSEL: Double tapped video: \(video.title)")
        // TODO: Integrate with engagement system
    }
    
    private func dismissCarousel() {
        print("🎬 CAROUSEL: Dismissing carousel")
        dismiss()
    }
}

// MARK: - VideoCard Component

private struct VideoCard: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    let isPlaying: Bool
    let onTogglePlay: () -> Void
    let onDoubleTap: () -> Void
    
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.gray.opacity(0.2))
            .overlay(videoCardContent)
            .frame(width: 340, height: 500)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .onTapGesture {
                onTogglePlay()
            }
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
    }
    
    private var videoCardContent: some View {
        ZStack {
            // Video background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack {
                Spacer()
                
                // Play/pause overlay (only show when paused and active)
                if !isPlaying && isActive {
                    Button(action: onTogglePlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 80, height: 80)
                            )
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Video info overlay
                videoInfoOverlay
            }
        }
    }
    
    private var videoInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text(video.creatorName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.cyan)
                        
                        Text(formatTimeAgo(video.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
            }
            
            // Engagement metrics
            HStack(spacing: 20) {
                engagementMetric(
                    icon: "flame.fill",
                    count: video.hypeCount,
                    color: .orange
                )
                
                engagementMetric(
                    icon: "eye.fill",
                    count: video.viewCount,
                    color: .blue
                )
                
                engagementMetric(
                    icon: "heart",
                    count: video.coolCount,
                    color: .red
                )
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func engagementMetric(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text("\(count)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview {
    CardVideoCarouselView(
        videos: [
            CoreVideoMetadata(
                id: "preview1",
                title: "Amazing Reply Video #1",
                videoURL: "https://sample.com/video1.mp4",
                thumbnailURL: "",
                creatorID: "user1",
                creatorName: "TestCreator1",
                createdAt: Date().addingTimeInterval(-3600),
                threadID: "thread1",
                replyToVideoID: "parent1",
                conversationDepth: 2,
                viewCount: 245,
                hypeCount: 34,
                coolCount: 2,
                replyCount: 0,
                shareCount: 8,
                temperature: "hot",
                qualityScore: 85,
                engagementRatio: 0.12,
                velocityScore: 0.5,
                trendingScore: 0.3,
                duration: 28.5,
                aspectRatio: 9.0/16.0,
                fileSize: 1500000,
                discoverabilityScore: 0.7,
                isPromoted: false,
                lastEngagementAt: Date()
            ),
            CoreVideoMetadata(
                id: "preview2",
                title: "Great Response Video #2",
                videoURL: "https://sample.com/video2.mp4",
                thumbnailURL: "",
                creatorID: "user2",
                creatorName: "TestCreator2",
                createdAt: Date().addingTimeInterval(-1800),
                threadID: "thread1",
                replyToVideoID: "parent1",
                conversationDepth: 2,
                viewCount: 156,
                hypeCount: 19,
                coolCount: 1,
                replyCount: 0,
                shareCount: 3,
                temperature: "warm",
                qualityScore: 78,
                engagementRatio: 0.08,
                velocityScore: 0.3,
                trendingScore: 0.2,
                duration: 35.2,
                aspectRatio: 9.0/16.0,
                fileSize: 1800000,
                discoverabilityScore: 0.6,
                isPromoted: false,
                lastEngagementAt: Date()
            )
        ],
        parentVideo: CoreVideoMetadata(
            id: "parent",
            title: "Original Parent Video",
            videoURL: "https://sample.com/parent.mp4",
            thumbnailURL: "",
            creatorID: "parent_user",
            creatorName: "ParentCreator",
            createdAt: Date().addingTimeInterval(-7200),
            threadID: "thread1",
            replyToVideoID: nil,
            conversationDepth: 1,
            viewCount: 1250,
            hypeCount: 180,
            coolCount: 15,
            replyCount: 12,
            shareCount: 45,
            temperature: "blazing",
            qualityScore: 92,
            engagementRatio: 0.15,
            velocityScore: 0.8,
            trendingScore: 0.6,
            duration: 42.8,
            aspectRatio: 9.0/16.0,
            fileSize: 2500000,
            discoverabilityScore: 0.9,
            isPromoted: true,
            lastEngagementAt: Date()
        )
    )
    .preferredColorScheme(.dark)
}
