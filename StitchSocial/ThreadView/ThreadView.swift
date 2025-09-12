//
//  ThreadView.swift
//  StitchSocial
//
//  Layer 8: Views - Streamlined Spatial Thread Interface
//  Dependencies: SpatialThreadMapView, CardVideoCarouselView
//  Features: Thumbnail-only parent, proper video arrays, carousel navigation
//

import SwiftUI
import AVFoundation

struct ThreadView: View {
    
    // MARK: - Properties
    let threadID: String
    let videoService: VideoService
    let userService: UserService
    
    // MARK: - Core State
    @State private var parentThread: CoreVideoMetadata?
    @State private var children: [CoreVideoMetadata] = []
    @State private var selectedChild: CoreVideoMetadata?
    @State private var stepchildren: [CoreVideoMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // MARK: - UI State
    @State private var showingCardCarousel = false
    @State private var isParentVideoPlaying = false
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                loadingInterface
            } else if let parentThread = parentThread {
                mainInterface(parentThread: parentThread)
            } else {
                errorInterface
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadThreadData()
        }
        .onDisappear {
            killAllVideoPlayers()
        }
        .fullScreenCover(isPresented: $showingCardCarousel) {
            if let selectedChild = selectedChild {
                // ✅ FIXED: Main child first, then stepchildren
                let carouselVideos = [selectedChild] + stepchildren
                CardVideoCarouselView(
                    videos: carouselVideos,        // Main child + all replies
                    parentVideo: parentThread,     // Thread context
                    startingIndex: 0               // Start with main child user tapped
                )
            }
        }
        .onChange(of: showingCardCarousel) { _, isShowing in
            if isShowing {
                killAllVideoPlayers()
                isParentVideoPlaying = false
            } else {
                // Reset carousel state when closed
                selectedChild = nil
                stepchildren = []
            }
        }
    }
    
    // MARK: - Main Interface
    
    private func mainInterface(parentThread: CoreVideoMetadata) -> some View {
        ZStack {
            // Background: Parent Thread Video Card (Thumbnail + Play Button)
            ThreadVideoCard(
                video: parentThread,
                isPlaying: isParentVideoPlaying,
                onTogglePlay: {
                    isParentVideoPlaying.toggle()
                }
            )
            
            // Foreground: Spatial Orbital Interface
            SpatialThreadMapView(
                parentThread: parentThread,
                children: children,
                onChildSelected: handleChildTapped,
                onEngagement: handleEngagement
            )
            .background(Color.clear)
            
            // Top Navigation Bar
            navigationBar
        }
    }
    
    // MARK: - Thread Video Card Component
    
    private struct ThreadVideoCard: View {
        let video: CoreVideoMetadata
        let isPlaying: Bool
        let onTogglePlay: () -> Void
        
        var body: some View {
            ZStack {
                if isPlaying {
                    // Real video player when playing
                    VideoPlayerView(
                        video: video,
                        isActive: true,
                        onEngagement: { type in
                            print("🎬 PARENT VIDEO: Engagement \(type) on \(video.title)")
                        }
                    )
                } else {
                    // Static thumbnail when paused
                    videoThumbnail
                }
                
                // Play/pause overlay
                if !isPlaying {
                    playButtonOverlay
                }
            }
            .clipped()
        }
        
        private var videoThumbnail: some View {
            ZStack {
                // Background gradient as placeholder
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(video.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)
                    
                    Text("by \(video.creatorName)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        
        private var playButtonOverlay: some View {
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
    }
    
    // MARK: - Navigation Bar
    
    private var navigationBar: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("Thread")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(children.count + 1) videos")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    // MARK: - Loading Interface
    
    private var loadingInterface: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                        .frame(width: CGFloat(100 + ring * 50))
                        .rotationEffect(.degrees(Double(ring) * 120))
                }
                
                Image(systemName: "video.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.cyan)
            }
            
            Text("Loading Thread...")
                .foregroundColor(.white)
                .font(.headline)
        }
    }
    
    // MARK: - Error Interface
    
    private var errorInterface: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Load Thread")
                .foregroundColor(.white)
                .font(.headline)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Try Again") {
                loadThreadData()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadThreadData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let thread = try await videoService.getVideo(id: threadID)
                let loadedChildren = try await videoService.getThreadChildren(threadID: threadID)
                
                await MainActor.run {
                    parentThread = thread
                    children = loadedChildren
                    isLoading = false
                }
                
                print("✅ THREAD: Loaded thread with \(loadedChildren.count) children")
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                
                print("❌ THREAD: Failed to load - \(error)")
            }
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleChildTapped(_ child: CoreVideoMetadata) {
        print("🔵 CHILD TAPPED: \(child.creatorName) (ID: \(child.id))")
        
        selectedChild = child
        
        // Kill all videos before loading stepchildren
        killAllVideoPlayers()
        isParentVideoPlaying = false
        
        // Load stepchildren for carousel
        Task {
            do {
                print("📡 LOADING: Stepchildren for child \(child.id)")
                let loadedStepchildren = try await videoService.getThreadChildren(threadID: child.id)
                
                await MainActor.run {
                    stepchildren = loadedStepchildren
                    print("✅ LOADED: \(loadedStepchildren.count) stepchildren")
                    
                    // ✅ FIXED: Always show carousel (even if no stepchildren)
                    showingCardCarousel = true
                    print("🎬 CAROUSEL: Opening with main child + \(loadedStepchildren.count) replies")
                }
            } catch {
                await MainActor.run {
                    stepchildren = []
                    // Still show carousel with just the main child
                    showingCardCarousel = true
                    print("❌ ERROR: Failed to load stepchildren, showing main child only")
                }
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func handleEngagement(video: CoreVideoMetadata, type: InteractionType) {
        print("💫 ENGAGEMENT: \(type.rawValue) on video by \(video.creatorName)")
        
        // Add engagement handling logic here
        Task {
            // Process engagement through your existing system
            // engagementCoordinator.processEngagement(...)
        }
    }
    
    // MARK: - Video Cleanup
    
    private func killAllVideoPlayers() {
        // Stop all video players immediately
        NotificationCenter.default.post(
            name: NSNotification.Name("KillAllVideoPlayers"),
            object: nil
        )
        
        // Also try the existing notification name for compatibility
        NotificationCenter.default.post(
            name: NSNotification.Name("StopAllVideoPlayers"),
            object: nil
        )
        
        print("🛑 VIDEO: Killed all video players")
    }
}

// MARK: - Preview

#Preview {
    ThreadView(
        threadID: "sample-thread-id",
        videoService: VideoService(),
        userService: UserService()
    )
}
