//
//  ThreadView.swift
//  StitchSocial
//
//  Created by James Garmon on 8/25/25.
//

//
//  ThreadView.swift
//  StitchSocial
//
//  Layer 8: Views - Interactive Thread Dashboard
//  Dependencies: ThreadViewModel (Layer 7), CardVideoCarouselView (Layer 8)
//  Features: Thread hierarchy display, video navigation, carousel integration
//  ARCHITECTURE COMPLIANT: No business logic, no service calls
//

import SwiftUI
import AVFoundation

// MARK: - ThreadView

/// Interactive thread dashboard showing complete conversation structure
struct ThreadView: View {
    
    // MARK: - Properties
    let threadID: String
    
    // MARK: - Single Dependency (Layer 7)
    @StateObject private var viewModel: ThreadViewModel
    
    // MARK: - UI State Only
    @State private var showingError = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var showingVideoPlayer = false
    @State private var showingStitchCreation = false
    @State private var stitchingToVideoID: String?
    @State private var stitchLevel: StitchLevel = .child
    
    // MARK: - Card Video Carousel State
    @State private var showingVideoCarousel = false
    @State private var carouselVideos: [CoreVideoMetadata] = []
    @State private var carouselParentVideo: CoreVideoMetadata?
    
    // UI Configuration
    @State private var showPlaceholders = false
    @State private var maxChildSlots = 6
    @State private var maxStepchildSlots = 4
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Stitch Level
    enum StitchLevel {
        case child      // Reply to main thread
        case stepchild  // Reply to specific child
    }
    
    // MARK: - Initialization
    init(threadID: String, videoService: VideoService, userService: UserService) {
        self.threadID = threadID
        self._viewModel = StateObject(wrappedValue: ThreadViewModel(
            videoService: videoService,
            userService: userService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack {
                // DEBUG: Always visible test button
                HStack {
                    Button("🔴 TEST CAROUSEL") {
                        print("🧪 DEBUG: TEST CAROUSEL button tapped")
                        // Create test data if needed
                        let testStepchildren = createTestStepchildren()
                        let testParent = createTestParent()
                        
                        print("🧪 DEBUG: Force testing carousel with \(testStepchildren.count) test stepchildren")
                        
                        carouselVideos = testStepchildren
                        carouselParentVideo = testParent
                        showingVideoCarousel = true
                        print("🧪 DEBUG: showingVideoCarousel set to: \(showingVideoCarousel)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Loading: \(viewModel.isLoading ? "YES" : "NO")")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        
                        Text("Children: \(viewModel.getActualChildren().count)")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        
                        Text("Total Videos: \(viewModel.threadVideos.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.cyan)
                        
                        if let firstChild = viewModel.getActualChildren().first {
                            Text("Stepchildren: \(viewModel.getStepchildren(for: firstChild.id).count)")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Carousel: \(showingVideoCarousel ? "OPEN" : "CLOSED")")
                            .font(.system(size: 10))
                            .foregroundColor(showingVideoCarousel ? .green : .red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .zIndex(999)
                
                // Main Content
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error: error)
                } else if let thread = viewModel.currentThread {
                    ThreadDashboardView(
                        thread: thread,
                        viewModel: viewModel,
                        showPlaceholders: showPlaceholders,
                        maxChildSlots: maxChildSlots,
                        maxStepchildSlots: maxStepchildSlots,
                        onVideoTap: handleVideoTap,
                        onStitchTap: handleStitchTap,
                        onWatchBranch: handleWatchBranch
                    )
                } else {
                    emptyStateView
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.loadThread(threadID)
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerSheet(video: video)
            }
        }
        .fullScreenCover(isPresented: $showingVideoCarousel) {
            CardVideoCarouselView(
                videos: carouselVideos,
                parentVideo: carouselParentVideo,
                startingIndex: 0
            )
        }
        .sheet(isPresented: $showingStitchCreation) {
            StitchCreationSheet(
                threadID: threadID,
                replyToVideoID: stitchingToVideoID,
                stitchLevel: stitchLevel
            )
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleVideoTap(_ video: CoreVideoMetadata) {
        selectedVideo = video
        showingVideoPlayer = true
        print("🎬 THREAD VIEW: Playing video: \(video.title)")
    }
    
    private func handleStitchTap(to videoID: String?, level: StitchLevel) {
        stitchingToVideoID = videoID
        stitchLevel = level
        showingStitchCreation = true
        print("🎬 THREAD VIEW: Creating \(level) stitch to video: \(videoID ?? "main thread")")
    }
    
    private func handleWatchBranch(for videoID: String) {
        print("🎬 THREAD VIEW: Opening card carousel for video: \(videoID)")
        print("📍 STEP 1: Looking for parent video...")
        
        let parentVideo = viewModel.threadVideos.first(where: { $0.id == videoID })
        print("📍 STEP 2: Parent video found: \(parentVideo != nil)")
        
        if let parent = parentVideo {
            print("📍 STEP 3: Parent title: \(parent.title)")
            
            let stepchildren = viewModel.getStepchildren(for: videoID)
            print("📍 STEP 4: Stepchildren count: \(stepchildren.count)")
            
            if stepchildren.count > 0 {
                print("📍 STEP 5: Setting carousel data...")
                carouselParentVideo = parent
                carouselVideos = stepchildren
                print("📍 STEP 6: Triggering carousel...")
                showingVideoCarousel = true
                print("📍 STEP 7: showingVideoCarousel = \(showingVideoCarousel)")
            } else {
                print("📍 STEP 5: No stepchildren found")
                // Debug: Let's see what videos exist
                print("📍 DEBUG: All thread videos:")
                for video in viewModel.threadVideos {
                    print("📍   - \(video.id): depth=\(video.conversationDepth), replyTo=\(video.replyToVideoID ?? "nil")")
                }
            }
        } else {
            print("📍 STEP 3: Parent video NOT found")
        }
    }
    
    // MARK: - Debug Helper Functions
    
    private func createTestStepchildren() -> [CoreVideoMetadata] {
        return [
            CoreVideoMetadata(
                id: "debug_step_1",
                title: "Debug Stepchild 1",
                videoURL: "https://sample.com/test1.mp4",
                thumbnailURL: "",
                creatorID: "debug_user_1",
                creatorName: "DebugUser1",
                createdAt: Date().addingTimeInterval(-1800),
                threadID: threadID,
                replyToVideoID: "debug_parent",
                conversationDepth: 2,
                viewCount: 123,
                hypeCount: 15,
                coolCount: 2,
                replyCount: 0,
                shareCount: 3,
                temperature: "warm",
                qualityScore: 75,
                engagementRatio: 0.08,
                velocityScore: 0.3,
                trendingScore: 0.2,
                duration: 25.0,
                aspectRatio: 9.0/16.0,
                fileSize: 1200000,
                discoverabilityScore: 0.6,
                isPromoted: false,
                lastEngagementAt: Date()
            ),
            CoreVideoMetadata(
                id: "debug_step_2",
                title: "Debug Stepchild 2",
                videoURL: "https://sample.com/test2.mp4",
                thumbnailURL: "",
                creatorID: "debug_user_2",
                creatorName: "DebugUser2",
                createdAt: Date().addingTimeInterval(-900),
                threadID: threadID,
                replyToVideoID: "debug_parent",
                conversationDepth: 2,
                viewCount: 89,
                hypeCount: 8,
                coolCount: 1,
                replyCount: 0,
                shareCount: 1,
                temperature: "cool",
                qualityScore: 68,
                engagementRatio: 0.05,
                velocityScore: 0.2,
                trendingScore: 0.1,
                duration: 18.5,
                aspectRatio: 9.0/16.0,
                fileSize: 900000,
                discoverabilityScore: 0.4,
                isPromoted: false,
                lastEngagementAt: Date()
            )
        ]
    }
    
    private func createTestParent() -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: "debug_parent",
            title: "Debug Parent Video",
            videoURL: "https://sample.com/parent.mp4",
            thumbnailURL: "",
            creatorID: "debug_parent_user",
            creatorName: "ParentUser",
            createdAt: Date().addingTimeInterval(-3600),
            threadID: threadID,
            replyToVideoID: nil,
            conversationDepth: 1,
            viewCount: 456,
            hypeCount: 67,
            coolCount: 5,
            replyCount: 2,
            shareCount: 12,
            temperature: "hot",
            qualityScore: 85,
            engagementRatio: 0.12,
            velocityScore: 0.6,
            trendingScore: 0.4,
            duration: 35.0,
            aspectRatio: 9.0/16.0,
            fileSize: 1800000,
            discoverabilityScore: 0.8,
            isPromoted: false,
            lastEngagementAt: Date()
        )
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                .scaleEffect(1.2)
            
            Text("Loading Thread...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Unable to Load Thread")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await viewModel.loadThread(threadID)
                }
            }
            .buttonStyle(ThreadButtonStyle())
        }
        .padding()
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Thread Not Found")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("This thread may have been deleted or is no longer available.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button("Go Back") {
                dismiss()
            }
            .buttonStyle(ThreadButtonStyle())
        }
        .padding()
    }
}

// MARK: - ThreadDashboardView

/// Main thread dashboard showing interactive conversation map
struct ThreadDashboardView: View {
    let thread: ThreadContext
    let viewModel: ThreadViewModel
    let showPlaceholders: Bool
    let maxChildSlots: Int
    let maxStepchildSlots: Int
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onStitchTap: (String?, ThreadView.StitchLevel) -> Void
    let onWatchBranch: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                threadHeader
                
                // Main Thread Section
                mainThreadSection
                
                // Children Section with nested stepchildren
                childrenSection
                
                // Thread Stats
                threadStatsSection
                
                // Bottom padding for safe area
                Color.clear.frame(height: 100)
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Header
    
    private var threadHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            AsyncImage(url: URL(string: "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.gray.opacity(0.2)))
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Thread")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                // Thread Collective Hype
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("\(viewModel.collectiveHype)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    Text("collective hype")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Button(action: { onStitchTap(nil, .child) }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Main Thread Section
    
    private var mainThreadSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Original Thread")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("👑 Creator")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
            }
            .padding(.horizontal, 20)
            
            // Main thread video card
            ThreadVideoCard(
                video: thread.threadStarter,
                cardType: .mainThread,
                onTap: { onVideoTap(thread.threadStarter) },
                onStitchTap: { onStitchTap(nil, .child) }
            )
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Children Section
    
    private var childrenSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Replies")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(viewModel.getActualChildren().count) replies")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            
            // Children with nested stepchildren
            VStack(spacing: 8) {
                ForEach(viewModel.getActualChildren(), id: \.id) { child in
                    VStack(spacing: 6) {
                        // Child video card - Updated for carousel integration
                        ExpandedChildCard(
                            video: child,
                            stepchildrenCount: viewModel.getStepchildren(for: child.id).count,
                            onTap: { onVideoTap(child) },
                            onStitchTap: { onStitchTap(child.id, .stepchild) },
                            onWatchReplies: { onWatchBranch(child.id) }
                        )
                        
                        // Nested stepchildren (indented)
                        let stepchildren = viewModel.getStepchildren(for: child.id)
                        if !stepchildren.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(stepchildren, id: \.id) { stepchild in
                                    StepchildCard(
                                        video: stepchild,
                                        onTap: { onVideoTap(stepchild) }
                                    )
                                }
                            }
                            .padding(.leading, 40) // Indent stepchildren
                            .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 12) // Space between complete child-stepchild groups
                }
                
                // Placeholder children
                if showPlaceholders {
                    ForEach(0..<min(3, getPlaceholderChildCount()), id: \.self) { index in
                        CondensedPlaceholderCard(
                            onTap: { onStitchTap(nil, .child) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Thread Stats Section
    
    private var threadStatsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                statItem(
                    title: "Videos",
                    value: "\(viewModel.totalVideoCount)",
                    icon: "play.rectangle.on.rectangle",
                    color: .blue
                )
                
                statItem(
                    title: "Participants",
                    value: "\(viewModel.participantCount)",
                    icon: "person.3",
                    color: .green
                )
                
                statItem(
                    title: "Health",
                    value: "\(Int(viewModel.threadHealth * 100))%",
                    icon: "chart.line.uptrend.xyaxis",
                    color: viewModel.threadHealth > 0.7 ? .green : viewModel.threadHealth > 0.4 ? .orange : .red
                )
            }
            .padding(.horizontal, 20)
            
            // Thread temperature indicator
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                
                Text("Thread Temperature: Active")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("Last activity: 2h ago")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Helper Methods
    
    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func getPlaceholderChildCount() -> Int {
        return max(0, maxChildSlots - viewModel.getActualChildren().count)
    }
}

// MARK: - ExpandedChildCard

/// Expanded child card that shows more prominently in the hierarchy
struct ExpandedChildCard: View {
    let video: CoreVideoMetadata
    let stepchildrenCount: Int
    let onTap: () -> Void
    let onStitchTap: () -> Void
    let onWatchReplies: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Video thumbnail - larger for prominence
            Button(action: onTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 90, height: 70)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 28, height: 28)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.cyan, lineWidth: 2)
            )
            
            // Video info - expanded layout
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(video.creatorName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.cyan)
                
                // Engagement metrics row
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(video.hypeCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("\(video.viewCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    // Interactive buttons for stepchildren
                    if stepchildrenCount > 0 {
                        // Watch all replies button (carousel)
                        Button(action: onWatchReplies) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.on.rectangle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text("Watch (\(stepchildrenCount))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Reply button - more prominent
            Button(action: onStitchTap) {
                VStack(spacing: 2) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)
                    Text("Reply")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - StepchildCard

/// Compact stepchild card for nested display
struct StepchildCard: View {
    let video: CoreVideoMetadata
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Connection line visual
            VStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 2, height: 20)
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 20, height: 2)
                    Spacer()
                }
            }
            .frame(width: 20)
            
            // Mini video thumbnail
            Button(action: onTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 50, height: 40)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Compact info
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(video.creatorName)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange.opacity(0.8))
                        Text("\(video.hypeCount)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    HStack(spacing: 2) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.blue.opacity(0.8))
                        Text("\(video.viewCount)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            // Timestamp
            Text(formatTimeAgo(video.createdAt))
                .font(.system(size: 9))
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
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

// MARK: - CondensedPlaceholderCard

/// Placeholder card for empty child slots
struct CondensedPlaceholderCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add your stitch here")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("Be the first to reply")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.7))
                }
                
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))
        }
    }
}

// MARK: - Supporting Sheets

/// Video player sheet wrapper
struct VideoPlayerSheet: View {
    let video: CoreVideoMetadata
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VideoPlayerView(
                video: video,
                isActive: true,
                onEngagement: { interaction in
                    print("Video engagement: \(interaction)")
                }
            )
            
            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                }
                Spacer()
            }
        }
    }
}

/// Stitch creation sheet wrapper
struct StitchCreationSheet: View {
    let threadID: String
    let replyToVideoID: String?
    let stitchLevel: ThreadView.StitchLevel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("Create \(stitchLevel == .child ? "Reply" : "Response")")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Recording interface would go here")
                    .foregroundColor(.gray)
                
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.cyan)
            }
        }
    }
}

/// Video card component for thread display
struct ThreadVideoCard: View {
    let video: CoreVideoMetadata
    let cardType: CardType
    let onTap: () -> Void
    let onStitchTap: () -> Void
    
    enum CardType {
        case mainThread
        case child
        case stepchild
        
        var size: CGSize {
            switch self {
            case .mainThread: return CGSize(width: 350, height: 180)
            case .child: return CGSize(width: 280, height: 140)
            case .stepchild: return CGSize(width: 220, height: 110)
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .mainThread: return 16
            case .child: return 14
            case .stepchild: return 12
            }
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Video thumbnail placeholder
                RoundedRectangle(cornerRadius: cardType.cornerRadius)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: cardType.size.width, height: cardType.size.height)
                
                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                
                // Bottom info bar
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(video.creatorName)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text("\(video.hypeCount)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            HStack(spacing: 2) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                Text("\(video.viewCount)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: cardType.size.width, height: cardType.size.height * 0.25)
                .background(Color.black.opacity(0.8))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardType.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardType.cornerRadius)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Button Styles

struct ThreadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.cyan)
            .foregroundColor(.black)
            .font(.system(size: 16, weight: .semibold))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
