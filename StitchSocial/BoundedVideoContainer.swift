//
//  BoundedVideoContainer.swift
//  StitchSocial
//
//  Layer 8: Views - Optimized Video Container for Thread Navigation
//  Dependencies: AVFoundation, CoreVideoMetadata, ThreadData, VideoService
//  Features: Background/foreground handling, memory efficient, loop detection, 0.5s view tracking
//  Purpose: Lightweight video player for continuous scrolling experiences
//

import SwiftUI
import AVFoundation

// MARK: - Standalone Bounded Video Container

struct StandaloneBoundedVideoContainer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    // NEW: View tracking dependencies
    let videoService: VideoService?
    let currentUserID: String?
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // Create coordinator with view tracking
        let coordinator = context.coordinator
        coordinator.containerView = containerView
        coordinator.videoService = videoService
        coordinator.currentUserID = currentUserID
        coordinator.setupPlayer(for: video, isActive: isActive)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        // Update active state and view tracking
        if coordinator.currentVideoID != video.id || coordinator.isActive != isActive {
            coordinator.setupPlayer(for: video, isActive: isActive)
        }
    }
    
    func makeCoordinator() -> StandaloneVideoContainerCoordinator {
        StandaloneVideoContainerCoordinator(onVideoLoop: onVideoLoop)
    }
}

// MARK: - Standalone Video Container Coordinator with View Tracking

class StandaloneVideoContainerCoordinator: NSObject {
    var containerView: UIView?
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    var currentVideoID: String?
    var isActive: Bool = false
    var notificationObserver: NSObjectProtocol?
    let onVideoLoop: (String) -> Void
    
    // NEW: 0.5-second view tracking properties
    private var viewTimer: Timer?
    private var viewStartTime: Date?
    private var hasRegisteredView: Bool = false
    weak var videoService: VideoService?
    var currentUserID: String?
    
    // View tracking constants
    private let minimumViewDuration: TimeInterval = 0.5
    
    init(onVideoLoop: @escaping (String) -> Void) {
        self.onVideoLoop = onVideoLoop
        super.init()
    }
    
    func setupPlayer(for video: CoreVideoMetadata, isActive: Bool) {
        guard let containerView = containerView else { return }
        
        self.isActive = isActive
        
        // Clean up existing player if different video
        if currentVideoID != video.id {
            cleanupCurrentPlayer()
            
            // Reset view tracking for new video
            resetViewTracking()
            
            // Setup new player
            guard let url = URL(string: video.videoURL) else { return }
            
            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)
            
            // Setup player layer
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.frame = containerView.bounds
            playerLayer?.videoGravity = .resizeAspectFill
            
            if let playerLayer = playerLayer {
                containerView.layer.sublayers?.removeAll()
                containerView.layer.addSublayer(playerLayer)
            }
            
            currentVideoID = video.id
            
            // Setup loop notification
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                if self?.isActive == true {
                    self?.player?.play()
                    self?.onVideoLoop(video.id)
                }
            }
        }
        
        // Update playback state and view tracking
        if isActive {
            player?.play()
            startViewTracking(for: video)
        } else {
            player?.pause()
            stopViewTracking()
        }
        
        // Update layer frame
        playerLayer?.frame = containerView.bounds
    }
    
    // MARK: - NEW: 0.5-Second View Tracking Methods
    
    private func startViewTracking(for video: CoreVideoMetadata) {
        // Don't track if already registered for this video or missing dependencies
        guard !hasRegisteredView,
              let videoService = videoService,
              let userID = currentUserID else {
            return
        }
        
        // Record view start time
        viewStartTime = Date()
        
        // Start 0.5-second timer
        viewTimer = Timer.scheduledTimer(withTimeInterval: minimumViewDuration, repeats: false) { [weak self] _ in
            self?.registerViewIfQualified(video: video, videoService: videoService, userID: userID)
        }
        
        print("VIEW TRACKING: Started 0.5s timer for video \(video.id)")
    }
    
    private func stopViewTracking() {
        viewTimer?.invalidate()
        viewTimer = nil
        
        // Don't reset hasRegisteredView here - keep it for this video session
        print("VIEW TRACKING: Stopped timer")
    }
    
    private func registerViewIfQualified(video: CoreVideoMetadata, videoService: VideoService, userID: String) {
        // Verify minimum watch time met
        guard let startTime = viewStartTime,
              Date().timeIntervalSince(startTime) >= minimumViewDuration,
              !hasRegisteredView else {
            print("VIEW TRACKING: View not qualified for \(video.id)")
            return
        }
        
        // Calculate actual watch time
        let watchTime = Date().timeIntervalSince(startTime)
        
        // Register view with VideoService
        Task {
            do {
                try await videoService.incrementViewCount(
                    videoID: video.id,
                    userID: userID,
                    watchTime: watchTime
                )
                
                await MainActor.run {
                    self.hasRegisteredView = true
                    print("VIEW TRACKING: ✅ Registered view for \(video.id) after \(String(format: "%.1f", watchTime))s")
                }
            } catch {
                print("VIEW TRACKING: ❌ Failed to register view for \(video.id): \(error.localizedDescription)")
            }
        }
        
        // Clean up timer
        viewTimer?.invalidate()
        viewTimer = nil
    }
    
    private func resetViewTracking() {
        stopViewTracking()
        hasRegisteredView = false
        viewStartTime = nil
        print("VIEW TRACKING: Reset for new video")
    }
    
    // MARK: - Existing Cleanup Methods
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        // Clean up view tracking
        stopViewTracking()
        
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentVideoID = nil
    }
    
    deinit {
        cleanupCurrentPlayer()
        resetViewTracking()
    }
}
