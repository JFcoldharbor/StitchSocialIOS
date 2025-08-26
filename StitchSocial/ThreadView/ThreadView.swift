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
//  Dependencies: ThreadViewModel (Layer 7) ONLY
//  Features: Thread hierarchy display, video navigation, stitch creation
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
    
    // MARK: - Initialization (Architecture Compliant)
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
        .navigationBarHidden(true)
        .task {
            await viewModel.loadThread(threadID)
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerSheet(video: video)
            }
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
        print("🎬 THREAD VIEW: Watching branch for video: \(videoID)")
        // TODO: Navigate to ReplyView for this specific branch
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
                
                // Children Section
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
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.gray.opacity(0.2)))
            }
            
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
            
            // Children list
            VStack(spacing: 12) {
                // Actual children
                ForEach(viewModel.getActualChildren(), id: \.id) { child in
                    CondensedChildCard(
                        video: child,
                        stepchildrenCount: viewModel.getStepchildren(for: child.id).count,
                        onTap: { onVideoTap(child) },
                        onStitchTap: { onStitchTap(child.id, .stepchild) },
                        onRepliesTap: { onWatchBranch(child.id) }
                    )
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
                    icon: "play.rectangle.stack",
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
                    color: viewModel.threadHealth > 0.7 ? .green : .orange
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }
    
    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    // MARK: - Helper Methods
    
    private func getPlaceholderChildCount() -> Int {
        return max(0, maxChildSlots - viewModel.getActualChildren().count)
    }
}

// MARK: - Supporting Card Components

/// Condensed child video card for replies
struct CondensedChildCard: View {
    let video: CoreVideoMetadata
    let stepchildrenCount: Int
    let onTap: () -> Void
    let onStitchTap: () -> Void
    let onRepliesTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Video thumbnail
            Button(action: onTap) {
                ZStack {
                    AsyncThumbnailView.videoThumbnail(url: video.thumbnailURL)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Play button overlay
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 24, height: 24)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.cyan, lineWidth: 2)
            )
            
            // Video info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title.isEmpty ? "Untitled Video" : video.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text("@\(video.creatorName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                
                // Stats row
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(video.hypeCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    if stepchildrenCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.cyan)
                            Text("\(stepchildrenCount)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 8) {
                Button(action: onStitchTap) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.cyan)
                }
                
                if stepchildrenCount > 0 {
                    Button(action: onRepliesTap) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

/// Placeholder card for empty thread slots
struct CondensedPlaceholderCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Placeholder thumbnail
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.cyan.opacity(0.6))
                            Text("Add Video")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.gray.opacity(0.8))
                        }
                    )
                    .frame(width: 80, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4]))
                    )
                
                // Placeholder info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Empty Slot")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("Tap to create")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    )
            )
        }
    }
}

/// Main thread video card component
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
            case .mainThread: return CGSize(width: 280, height: 200)
            case .child: return CGSize(width: 240, height: 160)
            case .stepchild: return CGSize(width: 200, height: 140)
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .mainThread: return 16
            case .child: return 12
            case .stepchild: return 8
            }
        }
        
        var titleFont: Font {
            switch self {
            case .mainThread: return .system(size: 16, weight: .bold)
            case .child: return .system(size: 14, weight: .semibold)
            case .stepchild: return .system(size: 12, weight: .medium)
            }
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Video thumbnail - FIXED: Use AsyncThumbnailView
                AsyncThumbnailView.videoThumbnail(url: video.thumbnailURL)
                    .frame(width: cardType.size.width, height: cardType.size.height * 0.75)
                    .overlay(
                        // Play button overlay
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 32, height: 32)
                            )
                    )
                    .clipped()
                
                // Video info overlay
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title.isEmpty ? "Untitled Video" : video.title)
                                .font(cardType.titleFont)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text("@\(video.creatorName)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: onStitchTap) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    // Stats
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
