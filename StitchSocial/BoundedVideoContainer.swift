//
//  BoundedVideoContainer.swift
//  StitchSocial
//
//  Layer 8: Views - Context-Aware Video Container for Thread Navigation
//  Dependencies: AVFoundation, CoreVideoMetadata, ThreadData
//  Features: Background/foreground handling, memory efficient, loop detection, context-aware kill notifications
//  Purpose: Lightweight video player for continuous scrolling experiences
//  FIXED: Deinit crash - proper observer cleanup without retain cycle
//

import SwiftUI
import AVFoundation
import ObjectiveC

// MARK: - Context-Aware BoundedVideoContainer

struct MyBoundedVideoContainer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    let context: VideoPlayerContext
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // Create coordinator with context
        let coordinator = context.coordinator
        coordinator.containerView = containerView
        coordinator.setupPlayer(for: video, isActive: isActive)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        // Update active state
        if coordinator.currentVideoID != video.id || coordinator.isActive != isActive {
            coordinator.setupPlayer(for: video, isActive: isActive)
        }
    }
    
    func makeCoordinator() -> VideoContainerCoordinator {
        VideoContainerCoordinator(onVideoLoop: onVideoLoop, context: self.context)
    }
}

// MARK: - Context-Aware Video Container Coordinator

class VideoContainerCoordinator: NSObject {
    var containerView: UIView?
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    var currentVideoID: String?
    var isActive: Bool = false
    var notificationObserver: NSObjectProtocol?
    var killObserver: NSObjectProtocol?
    var backgroundObserver: NSObjectProtocol?
    var foregroundObserver: NSObjectProtocol?
    let onVideoLoop: (String) -> Void
    
    // Context awareness
    private let playerContext: VideoPlayerContext
    
    // View tracking properties
    private var viewTimer: Timer?
    private var viewStartTime: Date?
    private var hasRegisteredView: Bool = false
    private let minimumViewDuration: TimeInterval = 0.5
    
    init(onVideoLoop: @escaping (String) -> Void, context: VideoPlayerContext) {
        self.onVideoLoop = onVideoLoop
        self.playerContext = context
        super.init()
        setupKillObserver()
        setupBackgroundObservers()
        
        print("🎬 BOUNDED VIDEO [\(context.description)]: Initialized")
    }
    
    // MARK: - Context-Aware Kill Observer Setup
    
    private func setupKillObserver() {
        // Profile grid thumbnails DON'T respond to kill notifications
        guard playerContext != .profileGrid else {
            print("✅ BOUNDED VIDEO [profileGrid]: Skipping kill observer - thumbnails are immune")
            return
        }
        
        killObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("killAllVideoPlayers"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("🛑 BOUNDED VIDEO [\(self.playerContext.description)]: Received kill signal")
            self.killPlayer()
        }
        print("✅ BOUNDED VIDEO [\(playerContext.description)]: Kill observer active")
    }
    
    private func killPlayer() {
        print("🛑 BOUNDED VIDEO [\(playerContext.description)]: Killing player for video \(currentVideoID ?? "unknown")")
        
        // Complete destruction
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        currentVideoID = nil
        isActive = false
        
        stopViewTracking()
        resetViewTracking()
        
        print("✅ BOUNDED VIDEO [\(playerContext.description)]: Player destroyed")
    }
    
    // MARK: - Background & Foreground Observers
    
    private func setupBackgroundObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appDidEnterBackground()
        }
        
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appWillEnterForeground()
        }
    }
    
    private func appDidEnterBackground() {
        player?.pause()
        print("📱 BOUNDED VIDEO [\(playerContext.description)]: Paused (background)")
    }
    
    private func appWillEnterForeground() {
        if isActive {
            player?.play()
            print("📱 BOUNDED VIDEO [\(playerContext.description)]: Resumed (foreground)")
        }
    }
    
    // MARK: - Player Setup
    
    func setupPlayer(for video: CoreVideoMetadata, isActive: Bool) {
        guard let containerView = containerView else { return }
        
        self.isActive = isActive
        
        // Clean up existing player if different video
        if currentVideoID != video.id {
            cleanupCurrentPlayer()
            resetViewTracking()
            
            // Setup new player
            guard let url = URL(string: video.videoURL) else {
                print("❌ BOUNDED VIDEO [\(playerContext.description)]: Invalid URL")
                return
            }
            
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
            setupLoopDetection(for: video)
            
            print("✅ BOUNDED VIDEO [\(playerContext.description)]: Player created for \(video.id.prefix(8))")
        }
        
        // Update playback state
        if isActive && player != nil {
            player?.play()
            startViewTracking(for: video)
            print("▶️ BOUNDED VIDEO [\(playerContext.description)]: Playing")
        } else if !isActive && player != nil {
            player?.pause()
            stopViewTracking()
            print("⏸️ BOUNDED VIDEO [\(playerContext.description)]: Paused")
        } else if player == nil {
            print("🚫 BOUNDED VIDEO [\(playerContext.description)]: No player (was killed)")
        }
        
        // Update layer frame
        playerLayer?.frame = containerView.bounds
    }
    
    // MARK: - Loop Detection
    
    private func setupLoopDetection(for video: CoreVideoMetadata) {
        guard let player = player else { return }
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            self.player?.seek(to: .zero)
            if self.isActive {
                self.player?.play()
                self.onVideoLoop(video.id)
            }
            
            print("🔄 BOUNDED VIDEO [\(self.playerContext.description)]: Video looped")
        }
    }
    
    // MARK: - View Tracking
    
    private func startViewTracking(for video: CoreVideoMetadata) {
        viewStartTime = Date()
        
        viewTimer = Timer.scheduledTimer(withTimeInterval: minimumViewDuration, repeats: false) { [weak self] _ in
            self?.registerView(for: video)
        }
        
        print("👁️ VIEW TRACKING [\(playerContext.description)]: Started for \(video.id.prefix(8))")
    }
    
    private func registerView(for video: CoreVideoMetadata) {
        guard let startTime = viewStartTime, !hasRegisteredView else { return }
        
        let watchTime = Date().timeIntervalSince(startTime)
        hasRegisteredView = true
        print("✅ VIEW TRACKING [\(playerContext.description)]: Registered after \(String(format: "%.1f", watchTime))s")
        
        viewTimer?.invalidate()
        viewTimer = nil
    }
    
    private func stopViewTracking() {
        viewTimer?.invalidate()
        viewTimer = nil
        viewStartTime = nil
    }
    
    private func resetViewTracking() {
        stopViewTracking()
        hasRegisteredView = false
        viewStartTime = nil
    }
    
    // MARK: - Cleanup
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        stopViewTracking()
        
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentVideoID = nil
    }
    
    // MARK: - FIXED DEINIT
    
    deinit {
        // Stop view tracking first
        viewTimer?.invalidate()
        viewTimer = nil
        
        // Clean up player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        
        // Remove ALL observers explicitly by reference
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        if let observer = killObserver {
            NotificationCenter.default.removeObserver(observer)
            killObserver = nil
        }
        
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        
        // Clean up UI
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        
        print("🗑️ BOUNDED VIDEO [\(playerContext.description)]: Deinitialized safely")
    }
}

// MARK: - VideoPlayerContext Extension

extension VideoPlayerContext {
    var description: String {
        switch self {
        case .homeFeed: return "Home Feed"
        case .discovery: return "Discovery"
        case .profileGrid: return "Profile Grid"
        case .standalone: return "Standalone"
        @unknown default: return "Unknown"
        }
    }
}
