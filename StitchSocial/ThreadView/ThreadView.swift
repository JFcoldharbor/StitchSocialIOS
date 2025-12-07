//
//  ThreadView.swift
//  StitchSocial
//
//  Layer 8: Views - Streamlined Spatial Thread Interface with Fullscreen Support
//  Dependencies: SpatialThreadMapView, CardVideoCarouselView, FullscreenVideoView
//  Features: Fullscreen parent video, proper video arrays, carousel navigation
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
    @State private var showingFullscreenVideo = false
    @State private var fullscreenStartVideo: CoreVideoMetadata?
    
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
                // Main child first, then stepchildren
                let carouselVideos = [selectedChild] + stepchildren
                CardVideoCarouselView(
                    videos: carouselVideos,
                    parentVideo: parentThread,
                    startingIndex: 0
                )
            }
        }
        .fullScreenCover(isPresented: $showingFullscreenVideo) {
            if let video = fullscreenStartVideo {
                FullscreenVideoView(
                    video: video,
                    onDismiss: {
                        showingFullscreenVideo = false
                        fullscreenStartVideo = nil
                    }
                )
            }
        }
        .onChange(of: showingCardCarousel) { _, isShowing in
            if isShowing {
                killAllVideoPlayers()
            } else {
                selectedChild = nil
                stepchildren = []
            }
        }
        .onChange(of: showingFullscreenVideo) { _, isShowing in
            if isShowing {
                killAllVideoPlayers()
            }
        }
    }
    
    // MARK: - Main Interface
    
    private func mainInterface(parentThread: CoreVideoMetadata) -> some View {
        ZStack {
            // Background color
            Color.black.ignoresSafeArea()
            
            // Spatial Orbital Interface with central parent video
            SpatialThreadMapView(
                parentThread: parentThread,
                children: children,
                onChildSelected: handleChildTapped,
                onEngagement: handleEngagement,
                onParentTapped: {
                    openParentInFullscreen(parentThread)
                }
            )
            
            // Close Button - Top Layer
            VStack {
                HStack {
                    Button {
                        print("❌ CLOSE TAPPED")
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .padding(.top, 60)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                
                Spacer()
            }
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
        
        // Load stepchildren for carousel
        Task {
            do {
                print("🔄 LOADING: Stepchildren for child \(child.id)")
                let loadedStepchildren = try await videoService.getThreadChildren(threadID: child.id)
                
                await MainActor.run {
                    stepchildren = loadedStepchildren
                    print("✅ LOADED: \(loadedStepchildren.count) stepchildren")
                    
                    // Always show carousel (even if no stepchildren)
                    showingCardCarousel = true
                    print("🎬 CAROUSEL: Opening with main child + \(loadedStepchildren.count) replies")
                }
            } catch {
                await MainActor.run {
                    stepchildren = []
                    // Still show carousel with just the main child
                    showingCardCarousel = true
                    print("⚠️ ERROR: Failed to load stepchildren, showing main child only")
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
    
    // MARK: - Fullscreen Video Helpers
    
    private func openParentInFullscreen(_ video: CoreVideoMetadata) {
        killAllVideoPlayers()
        fullscreenStartVideo = video
        showingFullscreenVideo = true
        print("🎬 THREAD: Opening parent video in fullscreen")
    }
    
    private func parentThumbnailView(_ video: CoreVideoMetadata) -> some View {
        ZStack {
            // Actual video thumbnail
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .empty:
                    // Loading state
                    LinearGradient(
                        colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
                    
                case .success(let image):
                    // Display thumbnail
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    
                case .failure:
                    // Error fallback
                    LinearGradient(
                        colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "video.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    
                @unknown default:
                    EmptyView()
                }
            }
            
            // Dark overlay gradient for readability
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Video info overlay
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text(video.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    
                    Text("by \(video.creatorName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .padding(.bottom, 40)
            }
            
            // Play button overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        }
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
