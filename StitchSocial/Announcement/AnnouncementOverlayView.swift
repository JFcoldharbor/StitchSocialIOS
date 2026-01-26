//
//  AnnouncementOverlayView.swift
//  StitchSocial
//
//  Full-screen announcement overlay that users must watch/acknowledge
//  Uses existing VideoPlayerRepresentable from VideoPlayerView.swift
//  FIXED: Uses CreatorPill with profile navigation
//  FIXED: Pauses background videos when showing
//  FIXED: Continue button working properly
//  FIXED: Hidden countdown (tracks in background)
//

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Announcement Overlay View

struct AnnouncementOverlayView: View {
    let announcement: Announcement
    let onComplete: () -> Void
    let onDismiss: () -> Void
    
    // Services
    @EnvironmentObject private var videoService: VideoService
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    
    // Navigation state
    @State private var showingCreatorProfile: Bool = false
    @State private var creatorUserID: String?
    
    // Video state
    @State private var videoMetadata: CoreVideoMetadata?
    @State private var videoURL: URL?
    @State private var isLoadingVideo: Bool = true
    @State private var loadError: String?
    @State private var player: AVPlayer?
    
    // Watch tracking (hidden from UI)
    @State private var watchedSeconds: Int = 0
    @State private var canDismiss: Bool = false
    @State private var hasAcknowledged: Bool = false
    @State private var watchTimer: Timer?
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            if isLoadingVideo {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if player != nil {
                // Video player layer
                VideoPlayerRepresentable(
                    player: player,
                    gravity: .resizeAspectFill
                )
                .ignoresSafeArea()
                .onTapGesture {
                    togglePlayback()
                }
            }
            
            // Overlay Content
            VStack {
                // Top Bar
                announcementHeader
                
                Spacer()
                
                // Bottom Controls
                announcementFooter
            }
            .padding()
        }
        .onAppear {
            pauseBackgroundVideos()
        }
        .task {
            await loadVideoURL()
        }
        .onDisappear {
            cleanup()
        }
        .fullScreenCover(isPresented: $showingCreatorProfile) {
            if let creatorID = creatorUserID {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService,
                    viewingUserID: creatorID
                )
            }
        }
    }
    
    // MARK: - Pause Background Videos
    
    private func pauseBackgroundVideos() {
        print("📢 ANNOUNCEMENT: Killing ALL background activity")
        
        // Use the master kill switch to stop everything
        BackgroundActivityManager.shared.killAllBackgroundActivity(reason: "Announcement overlay")
        
        // Also post the notification for any stragglers
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        
        // Clear the preloading service player pool
        VideoPreloadingService.shared.clearAllPlayers()
        
        print("📢 ANNOUNCEMENT: Background videos killed")
    }
    
    // MARK: - Toggle Playback
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    
    // MARK: - Load Video URL
    
    private func loadVideoURL() async {
        isLoadingVideo = true
        defer { isLoadingVideo = false }
        
        do {
            // getVideo returns non-optional CoreVideoMetadata (throws if not found)
            let video = try await videoService.getVideo(id: announcement.videoId)
            videoMetadata = video
            creatorUserID = video.creatorID
            
            if let url = URL(string: video.videoURL) {
                videoURL = url
                
                // Create and configure player
                await MainActor.run {
                    let newPlayer = AVPlayer(url: url)
                    newPlayer.isMuted = false
                    newPlayer.actionAtItemEnd = .none
                    player = newPlayer
                    player?.play()
                    
                    // Setup looping
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: newPlayer.currentItem,
                        queue: .main
                    ) { _ in
                        newPlayer.seek(to: .zero)
                        newPlayer.play()
                    }
                }
                
                startWatchTimer()
            } else {
                loadError = "Invalid video URL"
            }
        } catch {
            loadError = "Failed to load video: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Loading announcement...")
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            Text(message)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button("Skip") {
                cleanup()
                onDismiss()
            }
            .padding()
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Header
    
    private var announcementHeader: some View {
        HStack {
            // Official badge
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.cyan)
                Text("Official Announcement")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            
            Spacer()
            
            // Type badge
            typeBadge
        }
        .padding(.top, 60)
    }
    
    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: announcement.type.icon)
                .font(.caption)
            Text(announcement.type.displayName.uppercased())
                .font(.caption2.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(priorityColor)
        .foregroundColor(.white)
        .clipShape(Capsule())
    }
    
    private var priorityColor: Color {
        switch announcement.priority {
        case .critical: return .red
        case .high: return .orange
        case .standard: return .blue
        case .low: return .gray
        }
    }
    
    // MARK: - Footer
    
    private var announcementFooter: some View {
        VStack(spacing: 16) {
            // Creator Pill (tappable to navigate to profile)
            if let video = videoMetadata {
                CreatorPill(
                    creator: video,
                    isThread: false,
                    colors: [.cyan, .blue],
                    displayName: video.creatorName.isEmpty ? "Stitch Official" : video.creatorName,
                    profileImageURL: nil,
                    onTap: {
                        showingCreatorProfile = true
                    }
                )
            }
            
            // Title and message
            VStack(spacing: 8) {
                Text(announcement.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if let message = announcement.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(16)
            
            // Continue button (only shows after minimum watch time)
            if canDismiss {
                if announcement.requiresAcknowledgment && !hasAcknowledged {
                    Button {
                        hasAcknowledged = true
                        completeAnnouncement()
                    } label: {
                        Text("I Understand")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .cornerRadius(12)
                    }
                } else if announcement.isDismissable {
                    Button {
                        completeAnnouncement()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }
    
    // MARK: - Timer (Hidden - tracks in background)
    
    private func startWatchTimer() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            watchedSeconds += 1
            
            // Check if minimum watch time reached
            if watchedSeconds >= announcement.minimumWatchSeconds && !canDismiss {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    canDismiss = true
                }
                print("📢 ANNOUNCEMENT: Minimum watch time reached (\(watchedSeconds)s)")
            }
        }
    }
    
    private func completeAnnouncement() {
        print("📢 ANNOUNCEMENT: Complete tapped, watchedSeconds=\(watchedSeconds)")
        cleanup()
        onComplete()
    }
    
    private func cleanup() {
        watchTimer?.invalidate()
        watchTimer = nil
        player?.pause()
        player = nil
        print("📢 ANNOUNCEMENT: Cleaned up")
    }
}

// NOTE: Notification.Name.killAllVideoPlayers is already defined in VideoPlayerView.swift

// MARK: - Preview

#Preview {
    let mockAnnouncement = Announcement(
        id: "preview_1",
        videoId: "video_123",
        creatorId: "stitch_official",
        title: "Welcome to Stitch 2.0! 🎉",
        message: "We've got exciting new features to show you",
        priority: .high,
        type: .feature,
        targetAudience: .all,
        startDate: Date(),
        endDate: nil,
        minimumWatchSeconds: 5,
        isDismissable: true,
        requiresAcknowledgment: false,
        createdAt: Date(),
        updatedAt: Date(),
        isActive: true
    )
    
    return AnnouncementOverlayView(
        announcement: mockAnnouncement,
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") }
    )
    .environmentObject(VideoService())
}
