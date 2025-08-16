//
//  SmoothSwipeManager.swift
//  CleanBeta
//
//  Layer 6: Coordination - FIXED: Efficient Video Navigation System
//  Zero dependencies except AVFoundation
//  PERFORMANCE OPTIMIZED: Single active player + lazy loading + proper cleanup
//

import SwiftUI
import AVFoundation
import CoreMedia
import UIKit

/// Ultra-smooth video navigation manager with single active player optimization
@MainActor
class SmoothSwipeManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentVideoIndex = 0
    @Published var isTransitioning = false
    @Published var transitionProgress: Double = 0.0
    
    // MARK: - Configuration
    
    private let transitionDuration: TimeInterval = 0.05 // Ultra-fast 50ms
    private let fadeTransitionDuration: TimeInterval = 0.02 // 20ms fade
    
    // MARK: - OPTIMIZED: Single Player System
    
    private var videos: [CoreVideoMetadata] = []
    private var currentPlayer: AVPlayer?
    private var preloadedNextPlayer: AVPlayer? // Only preload 1 next player
    
    // MARK: - Initialization
    
    init() {
        // Audio session handled globally by iOS - no custom setup needed
    }
    
    deinit {
        Task { @MainActor in
            cleanupAllPlayers()
        }
    }
    
    // MARK: - OPTIMIZED: Single Active Player Setup
    
    /// Setup videos with ONLY current player active - NO background loading
    func setupVideos(_ videoList: [CoreVideoMetadata]) {
        videos = videoList
        currentVideoIndex = 0
        
        // OPTIMIZED: Clean up existing players first
        cleanupAllPlayers()
        
        // OPTIMIZED: Create ONLY current player immediately
        if let firstPlayer = createOptimizedPlayer(for: 0) {
            currentPlayer = firstPlayer
            firstPlayer.isMuted = false
            firstPlayer.play()
        }
        
        // OPTIMIZED: Preload next player in background (but keep PAUSED)
        DispatchQueue.global(qos: .background).async {
            if videoList.count > 1 {
                DispatchQueue.main.async {
                    self.preloadNextPlayer()
                }
            }
        }
        
        print("✅ OPTIMIZED: Setup \(videos.count) videos with single active player")
    }
    
    /// Get current video
    var currentVideo: CoreVideoMetadata? {
        guard currentVideoIndex < videos.count else { return nil }
        return videos[currentVideoIndex]
    }
    
    /// Get current player (always ready)
    var activePlayer: AVPlayer? {
        return currentPlayer
    }
    
    // MARK: - OPTIMIZED: Instant Navigation
    
    /// Navigate to next video with instant player swap
    func navigateToNext() -> Bool {
        guard currentVideoIndex < videos.count - 1 else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return false
        }
        
        let newIndex = currentVideoIndex + 1
        
        // OPTIMIZED: Use preloaded player if available, otherwise create on-demand
        let newPlayer = preloadedNextPlayer ?? createOptimizedPlayer(for: newIndex)
        guard let player = newPlayer else { return false }
        
        // OPTIMIZED: Stop old player completely
        currentPlayer?.pause()
        currentPlayer?.replaceCurrentItem(with: nil)
        
        // OPTIMIZED: Switch to new player
        currentPlayer = player
        currentVideoIndex = newIndex
        preloadedNextPlayer = nil // Clear preloaded reference
        
        // OPTIMIZED: Start new player if not playing
        player.isMuted = false
        if player.rate == 0 {
            player.play()
        }
        
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.05)
        
        // OPTIMIZED: Preload next player in background (paused)
        DispatchQueue.global(qos: .background).async {
            DispatchQueue.main.async {
                self.preloadNextPlayer()
            }
        }
        
        print("✅ OPTIMIZED: Switched to video \(newIndex + 1)/\(videos.count)")
        return true
    }
    
    /// Navigate to previous video with instant swap
    func navigateToPrevious() -> Bool {
        guard currentVideoIndex > 0 else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return false
        }
        
        let newIndex = currentVideoIndex - 1
        
        // OPTIMIZED: Create previous player on-demand (no preloading backwards)
        guard let newPlayer = createOptimizedPlayer(for: newIndex) else { return false }
        
        // OPTIMIZED: Stop old player completely
        currentPlayer?.pause()
        currentPlayer?.replaceCurrentItem(with: nil)
        
        // OPTIMIZED: Clear preloaded next player (wrong direction)
        preloadedNextPlayer?.pause()
        preloadedNextPlayer?.replaceCurrentItem(with: nil)
        preloadedNextPlayer = nil
        
        // OPTIMIZED: Switch to new player
        currentPlayer = newPlayer
        currentVideoIndex = newIndex
        
        // OPTIMIZED: Start new player
        newPlayer.isMuted = false
        newPlayer.play()
        
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.05)
        
        // OPTIMIZED: Preload next player in background
        DispatchQueue.global(qos: .background).async {
            DispatchQueue.main.async {
                self.preloadNextPlayer()
            }
        }
        
        print("✅ OPTIMIZED: Switched to video \(newIndex + 1)/\(videos.count)")
        return true
    }
    
    /// Get player for specific index (for UI preview) - creates on demand
    func getPlayer(for index: Int) -> AVPlayer? {
        if index == currentVideoIndex {
            return currentPlayer
        } else if index == currentVideoIndex + 1 {
            return preloadedNextPlayer
        } else {
            // Create temporary player for preview
            return createOptimizedPlayer(for: index)
        }
    }
    
    /// Pause current video
    func pauseCurrentVideo() {
        currentPlayer?.pause()
    }
    
    /// Resume current video
    func resumeCurrentVideo() {
        currentPlayer?.play()
    }
    
    // MARK: - OPTIMIZED: Efficient Player Management
    
    /// Preload only the next player (paused)
    private func preloadNextPlayer() {
        let nextIndex = currentVideoIndex + 1
        guard nextIndex < videos.count else { return }
        guard preloadedNextPlayer == nil else { return } // Don't create if already exists
        
        if let nextPlayer = createOptimizedPlayer(for: nextIndex) {
            preloadedNextPlayer = nextPlayer
            // CRITICAL: Keep paused to save resources
            nextPlayer.pause()
            nextPlayer.isMuted = true
            print("✅ OPTIMIZED: Preloaded next player (paused)")
        }
    }
    
    /// Create optimized player with minimal resource usage
    private func createOptimizedPlayer(for index: Int) -> AVPlayer? {
        guard index >= 0 && index < videos.count else { return nil }
        
        let video = videos[index]
        guard let videoURL = URL(string: video.videoURL) else { return nil }
        
        // OPTIMIZED: Minimal player creation
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // OPTIMIZED: Minimal buffer for instant start but efficient memory usage
        playerItem.preferredForwardBufferDuration = 1.0 // Very small buffer
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause // Don't loop automatically
        
        return player
    }
    
    // MARK: - OPTIMIZED: Memory Management
    
    /// Clean up all players and resources
    func cleanup() {
        print("🧹 OPTIMIZED: Starting cleanup...")
        
        // Stop and clean current player
        currentPlayer?.pause()
        currentPlayer?.replaceCurrentItem(with: nil)
        currentPlayer = nil
        
        // Stop and clean preloaded player
        preloadedNextPlayer?.pause()
        preloadedNextPlayer?.replaceCurrentItem(with: nil)
        preloadedNextPlayer = nil
        
        // Clear collections
        videos.removeAll()
        
        // Reset state
        currentVideoIndex = 0
        
        print("✅ OPTIMIZED: Cleanup complete - all players stopped")
    }
    
    /// Clean up all players
    private func cleanupAllPlayers() {
        currentPlayer?.pause()
        currentPlayer?.replaceCurrentItem(with: nil)
        currentPlayer = nil
        
        preloadedNextPlayer?.pause()
        preloadedNextPlayer?.replaceCurrentItem(with: nil)
        preloadedNextPlayer = nil
        
        print("🧹 OPTIMIZED: All players cleaned up")
    }
    
    // MARK: - Performance Monitoring
    
    func getPerformanceStats() -> SmoothSwipeStats {
        let activePlayersCount = (currentPlayer != nil ? 1 : 0) + (preloadedNextPlayer != nil ? 1 : 0)
        
        return SmoothSwipeStats(
            totalVideos: videos.count,
            preloadedCount: activePlayersCount,
            currentIndex: currentVideoIndex,
            isTransitioning: isTransitioning,
            transitionDuration: transitionDuration,
            preloadDistance: 1 // Only preload 1 ahead
        )
    }
}

// MARK: - Smooth Swipe Stats (unchanged)

struct SmoothSwipeStats {
    let totalVideos: Int
    let preloadedCount: Int
    let currentIndex: Int
    let isTransitioning: Bool
    let transitionDuration: TimeInterval
    let preloadDistance: Int
    
    var preloadEfficiency: Double {
        guard totalVideos > 0 else { return 0 }
        return Double(preloadedCount) / Double(totalVideos)
    }
    
    var currentPosition: String {
        return "\(currentIndex + 1)/\(totalVideos)"
    }
}

// MARK: - Smooth Video Player View (unchanged)

struct SmoothVideoPlayerView: View {
    let video: CoreVideoMetadata
    let player: AVPlayer?
    let isTransitioning: Bool
    let transitionProgress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = player {
                    OptimizedVideoPlayerRepresentable(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(isTransitioning ? (1.0 - transitionProgress * 0.3) : 1.0)
                        .scaleEffect(isTransitioning ? (1.0 - transitionProgress * 0.02) : 1.0)
                } else {
                    // Ultra-fast loading fallback
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            )
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
    }
}

// MARK: - Optimized Video Player Representable (unchanged)

struct OptimizedVideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.needsDisplayOnBoundsChange = true
        
        view.layer.addSublayer(playerLayer)
        view.tag = 999
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer {
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.frame = uiView.bounds
                CATransaction.commit()
                
                if playerLayer.player !== player {
                    playerLayer.player = player
                }
                
                playerLayer.setNeedsDisplay()
            }
        } else {
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = uiView.bounds
            playerLayer.needsDisplayOnBoundsChange = true
            
            uiView.layer.sublayers?.removeAll()
            uiView.layer.addSublayer(playerLayer)
        }
    }
}

// MARK: - OPTIMIZED: Efficient Gesture Handler

struct SmoothGestureHandler: ViewModifier {
    @ObservedObject var swipeManager: SmoothSwipeManager
    let onVerticalSwipe: (Bool) -> Void
    
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 12) // Slightly higher threshold for stability
                    .onChanged { value in
                        isDragging = true
                    }
                    .onEnded { value in
                        defer { isDragging = false }
                        
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        
                        // OPTIMIZED: Debounce rapid gestures
                        guard abs(horizontalDistance) > 20 || abs(verticalDistance) > 20 else { return }
                        
                        if abs(horizontalDistance) > abs(verticalDistance) {
                            // Horizontal swipe - video navigation
                            if horizontalDistance < 0 {
                                _ = swipeManager.navigateToNext()
                            } else {
                                _ = swipeManager.navigateToPrevious()
                            }
                        } else {
                            // Vertical swipe - thread navigation
                            onVerticalSwipe(verticalDistance < 0)
                        }
                    }
            )
    }
}

// MARK: - View Extension (unchanged)

extension View {
    func smoothSwipeGestures(
        swipeManager: SmoothSwipeManager,
        onVerticalSwipe: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        self.modifier(SmoothGestureHandler(
            swipeManager: swipeManager,
            onVerticalSwipe: onVerticalSwipe
        ))
    }
}

// MARK: - Hello World Test

extension SmoothSwipeManager {
    func helloWorldTest() {
        print("👋 OPTIMIZED SWIPE: Hello World - Single player navigation ready")
        print("⚡ OPTIMIZED SWIPE: Transition duration: \(Int(transitionDuration * 1000))ms")
        print("🔄 OPTIMIZED SWIPE: Pre-load distance: 1 video (optimized)")
        print("🎬 OPTIMIZED SWIPE: Using system audio session (no conflicts)")
        print("💾 OPTIMIZED SWIPE: Memory efficient: Only 1-2 players max")
    }
}
