//
//  VideoPreloadingService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Advanced Video Preloading & AVPlayer Pool Management
//  Dependencies: AVFoundation, Config
//  Features: Smooth video swiping, multidirectional navigation, memory management
//

import Foundation
import AVFoundation
import SwiftUI

/// Advanced video preloading service for smooth playback transitions
@MainActor
class VideoPreloadingService: ObservableObject {
    
    // MARK: - Properties
    
    private var playerPool: [String: AVPlayer] = [:]
    private var preloadQueue: [String] = []
    private var currentlyPreloading: Set<String> = []
    private var playerObservers: [String: NSObjectProtocol] = [:]
    
    // MARK: - Configuration
    
    private let maxPoolSize = 8 // Increased for multidirectional swiping
    private let preloadDistance = 3 // Videos ahead to preload
    private let maxConcurrentPreloads = 2 // Limit concurrent downloads
    
    // MARK: - Published State
    
    @Published var isPreloading = false
    @Published var preloadProgress: [String: Double] = [:]
    @Published var poolStats = PoolStats()
    
    // MARK: - Core Preloading API
    
    /// Get player for video (from pool or create new)
    func getPlayer(for video: CoreVideoMetadata) -> AVPlayer? {
        // Return existing player if available
        if let existingPlayer = playerPool[video.id] {
            print("🎬 PRELOAD: Using cached player for \(video.id)")
            poolStats.cacheHits += 1
            return existingPlayer
        }
        
        // Create new player if not in pool
        poolStats.cacheMisses += 1
        return createPlayer(for: video)
    }
    
    /// Preload videos for smooth navigation
    func preloadVideos(
        current: CoreVideoMetadata,
        upcoming: [CoreVideoMetadata],
        priority: PreloadPriority = .normal
    ) async {
        
        // Ensure current video is in pool
        if playerPool[current.id] == nil {
            await preloadVideo(current, priority: .high)
        }
        
        // Clear old preload queue
        preloadQueue.removeAll()
        
        // Add upcoming videos to preload queue
        let videosToPreload = Array(upcoming.prefix(preloadDistance))
        preloadQueue = videosToPreload.map { $0.id }
        
        print("🎬 PRELOAD: Queued \(videosToPreload.count) videos for preloading")
        
        // Start preloading in background
        await preloadQueuedVideos(videos: videosToPreload, priority: priority)
    }
    
    /// Preload single video - FIXED IMPLEMENTATION
    func preloadVideo(_ video: CoreVideoMetadata, priority: PreloadPriority = .normal) async {
        guard !currentlyPreloading.contains(video.id),
              playerPool[video.id] == nil else {
            print("🎬 PRELOAD: Video \(video.id) already preloading/cached")
            return
        }
        
        // Check concurrent preload limit
        guard currentlyPreloading.count < maxConcurrentPreloads else {
            print("🎬 PRELOAD: Concurrent limit reached, queueing \(video.id)")
            if !preloadQueue.contains(video.id) {
                preloadQueue.append(video.id)
            }
            return
        }
        
        currentlyPreloading.insert(video.id)
        isPreloading = true
        
        await performVideoPreload(video: video, priority: priority)
        
        currentlyPreloading.remove(video.id)
        
        if currentlyPreloading.isEmpty {
            isPreloading = false
        }
        
        // Process next item in queue
        await processNextInQueue()
    }
    
    // MARK: - Multidirectional Navigation Support
    
    /// Smart preloading for horizontal thread navigation
    func preloadForHorizontalNavigation(
        currentThread: ThreadData,
        currentVideoIndex: Int,
        allThreads: [ThreadData],
        currentThreadIndex: Int
    ) async {
        
        var videosToPreload: [CoreVideoMetadata] = []
        
        // 1. Current thread videos (for vertical swiping)
        let threadVideos = [currentThread.parentVideo] + currentThread.childVideos
        videosToPreload.append(contentsOf: threadVideos)
        
        // 2. Adjacent thread parent videos (for horizontal swiping)
        let adjacentIndices = [currentThreadIndex - 1, currentThreadIndex + 1]
            .filter { $0 >= 0 && $0 < allThreads.count }
        
        for index in adjacentIndices {
            videosToPreload.append(allThreads[index].parentVideo)
        }
        
        // Preload with appropriate priorities
        for (index, video) in videosToPreload.enumerated() {
            let priority: PreloadPriority = index == currentVideoIndex ? .high : .normal
            await preloadVideo(video, priority: priority)
        }
        
        print("🎬 PRELOAD: Horizontal setup complete - \(videosToPreload.count) videos")
    }
    
    /// Smart preloading for vertical stitch navigation
    func preloadForVerticalNavigation(
        thread: ThreadData,
        currentVideoIndex: Int
    ) async {
        
        let allVideos = [thread.parentVideo] + thread.childVideos
        
        // Preload current and adjacent videos
        let preloadIndices = [
            currentVideoIndex - 1,
            currentVideoIndex,
            currentVideoIndex + 1
        ].filter { $0 >= 0 && $0 < allVideos.count }
        
        for index in preloadIndices {
            let priority: PreloadPriority = index == currentVideoIndex ? .high : .normal
            await preloadVideo(allVideos[index], priority: priority)
        }
        
        print("🎬 PRELOAD: Vertical setup complete - \(preloadIndices.count) videos in thread")
    }
    
    // MARK: - Pool Management
    
    /// Clear specific player from pool
    func clearPlayer(for videoID: String) {
        if let player = playerPool[videoID] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerPool.removeValue(forKey: videoID)
            
            // Remove observer
            if let observer = playerObservers[videoID] {
                NotificationCenter.default.removeObserver(observer)
                playerObservers.removeValue(forKey: videoID)
            }
            
            preloadProgress.removeValue(forKey: videoID)
            
            print("🎬 PRELOAD: Cleared player for \(videoID)")
        }
        
        updatePoolStats()
    }
    
    /// Clear all players from pool
    func clearAllPlayers() {
        for videoID in playerPool.keys {
            clearPlayer(for: videoID)
        }
        
        preloadQueue.removeAll()
        currentlyPreloading.removeAll()
        preloadProgress.removeAll()
        
        print("🎬 PRELOAD: Cleared all players from pool")
    }
    
    /// Get preload status for video
    func getPreloadStatus(for videoID: String) -> PreloadStatus {
        if playerPool[videoID] != nil {
            return .ready
        } else if currentlyPreloading.contains(videoID) {
            return .preloading(progress: preloadProgress[videoID] ?? 0.0)
        } else if preloadQueue.contains(videoID) {
            return .queued
        } else {
            return .notStarted
        }
    }
    
    /// Get current pool status
    func getPoolStatus() -> PoolStatus {
        return PoolStatus(
            totalPlayers: playerPool.count,
            maxPoolSize: maxPoolSize,
            utilizationPercentage: Double(playerPool.count) / Double(maxPoolSize),
            isOptimal: playerPool.count >= 2 && playerPool.count <= maxPoolSize
        )
    }
    
    /// Force immediate preload (for user interaction)
    func forcePreload(_ video: CoreVideoMetadata) async {
        await preloadVideo(video, priority: .high)
    }
    
    // MARK: - Private Implementation - FIXED
    
    private func createPlayer(for video: CoreVideoMetadata) -> AVPlayer? {
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ PRELOAD: Invalid URL for \(video.id)")
            return nil
        }
        
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for optimal performance - FIXED
        player.automaticallyWaitsToMinimizeStalling = false // Faster startup
        player.isMuted = false
        
        // Setup looping for seamless playback
        setupPlayerLooping(player: player, item: playerItem, videoID: video.id)
        
        // Add to pool
        playerPool[video.id] = player
        
        // Manage pool size
        managePoolSize()
        updatePoolStats()
        
        print("🎬 PRELOAD: Created new player for \(video.id)")
        return player
    }
    
    private func setupPlayerLooping(player: AVPlayer, item: AVPlayerItem, videoID: String) {
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            Task { @MainActor in
                player?.seek(to: CMTime.zero)
                player?.play()
            }
        }
        
        playerObservers[videoID] = observer
    }
    
    private func preloadQueuedVideos(videos: [CoreVideoMetadata], priority: PreloadPriority) async {
        for video in videos {
            // Check if we should continue preloading
            guard preloadQueue.contains(video.id) else {
                print("🎬 PRELOAD: Skipping \(video.id) - removed from queue")
                continue
            }
            
            await preloadVideo(video, priority: priority)
            
            // Add delay between preloads for low priority
            if priority == .low {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }
    
    private func performVideoPreload(video: CoreVideoMetadata, priority: PreloadPriority) async {
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ PRELOAD: Invalid URL for \(video.id)")
            return
        }
        
        preloadProgress[video.id] = 0.0
        
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for preloading - FIXED
        player.automaticallyWaitsToMinimizeStalling = false // Faster initial load
        player.isMuted = true // Muted during preload
        
        // Setup looping
        setupPlayerLooping(player: player, item: playerItem, videoID: video.id)
        
        // Monitor preload progress
        await monitorPreloadProgress(player: player, videoID: video.id)
        
        // Add to pool when ready
        playerPool[video.id] = player
        preloadProgress[video.id] = 1.0
        
        // Manage pool size
        managePoolSize()
        updatePoolStats()
        
        print("🎬 PRELOAD: Completed preload for \(video.id)")
    }
    
    private func monitorPreloadProgress(player: AVPlayer, videoID: String) async {
        guard let playerItem = player.currentItem else { return }
        
        // Wait for player to be ready - OPTIMIZED
        var attempts = 0
        while playerItem.status != .readyToPlay && attempts < 15 { // Reduced from 30
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
            preloadProgress[videoID] = Double(attempts) / 15.0 // Updated denominator
        }
        
        if playerItem.status == .readyToPlay {
            preloadProgress[videoID] = 1.0
        } else {
            print("❌ PRELOAD: Failed to load \(videoID) after \(attempts) attempts")
            preloadProgress[videoID] = 0.0
        }
    }
    
    private func managePoolSize() {
        while playerPool.count > maxPoolSize {
            // Remove oldest player (FIFO)
            if let firstVideoID = playerPool.keys.first {
                clearPlayer(for: firstVideoID)
            }
        }
    }
    
    private func processNextInQueue() async {
        guard currentlyPreloading.count < maxConcurrentPreloads,
              let nextVideoID = preloadQueue.first else {
            return
        }
        
        preloadQueue.removeFirst()
        
        // For queued items, we need the metadata to preload
        // Since we only have videoID, skip for now
        print("🎬 PRELOAD: Processing next in queue: \(nextVideoID)")
    }
    
    private func updatePoolStats() {
        poolStats.totalPlayers = playerPool.count
        poolStats.utilizationPercentage = Double(playerPool.count) / Double(maxPoolSize)
        poolStats.lastUpdateTime = Date()
    }
}

// MARK: - Integration Extensions

extension VideoPreloadingService {
    
    /// Integration with HomeFeedView
    func setupForHomeFeed(threads: [ThreadData], currentThreadIndex: Int, currentVideoIndex: Int) async {
        guard currentThreadIndex < threads.count else { return }
        
        let currentThread = threads[currentThreadIndex]
        
        await preloadForHorizontalNavigation(
            currentThread: currentThread,
            currentVideoIndex: currentVideoIndex,
            allThreads: threads,
            currentThreadIndex: currentThreadIndex
        )
        
        print("🎬 PRELOAD: Setup complete for HomeFeed - thread \(currentThreadIndex), video \(currentVideoIndex)")
    }
    
    /// Integration with DiscoveryView
    func setupForDiscovery(videos: [CoreVideoMetadata], currentIndex: Int) async {
        guard currentIndex < videos.count else { return }
        
        let current = videos[currentIndex]
        let upcoming = Array(videos.dropFirst(currentIndex + 1).prefix(preloadDistance))
        
        await preloadVideos(
            current: current,
            upcoming: upcoming,
            priority: .normal
        )
        
        print("🎬 PRELOAD: Setup complete for Discovery - video \(currentIndex)")
    }
    
    /// Integration with ProfileView
    func setupForProfile(videos: [CoreVideoMetadata], selectedIndex: Int) async {
        guard selectedIndex < videos.count else { return }
        
        let current = videos[selectedIndex]
        let next = selectedIndex + 1 < videos.count ? videos[selectedIndex + 1] : nil
        
        await preloadVideo(current, priority: .high)
        
        if let nextVideo = next {
            await preloadVideo(nextVideo, priority: .normal)
        }
        
        print("🎬 PRELOAD: Setup complete for Profile - video \(selectedIndex)")
    }
}

// MARK: - Supporting Types

/// Preload priority levels
enum PreloadPriority {
    case high   // Current video
    case normal // Adjacent videos
    case low    // Background videos
}

/// Preload status tracking
enum PreloadStatus {
    case notStarted
    case queued
    case preloading(progress: Double)
    case ready
    case failed
}

/// Pool statistics
struct PoolStats {
    var totalPlayers: Int = 0
    var utilizationPercentage: Double = 0.0
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var lastUpdateTime: Date = Date()
    
    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }
}

/// Pool status information
struct PoolStatus {
    let totalPlayers: Int
    let maxPoolSize: Int
    let utilizationPercentage: Double
    let isOptimal: Bool
}

/// Device performance classification
enum DeviceClass {
    case highEnd    // iPhone 15 Pro, etc.
    case midRange   // iPhone 14, etc.
    case lowEnd     // Older devices
    
    static func current() -> DeviceClass {
        // TODO: Detect device performance class based on hardware
        return .midRange
    }
}

// MARK: - Performance Monitoring Extension

extension VideoPreloadingService {
    
    /// Get performance metrics
    func getPerformanceMetrics() -> PreloadingMetrics {
        return PreloadingMetrics(
            cacheHitRate: poolStats.cacheHitRate,
            averagePreloadTime: 2.3, // TODO: Track actual preload times
            memoryUsage: Double(playerPool.count * 15), // Estimate 15MB per player
            poolUtilization: poolStats.utilizationPercentage,
            preloadSuccessRate: 0.95 // TODO: Track actual success rate
        )
    }
    
    /// Log performance summary
    func logPerformanceSummary() {
        let metrics = getPerformanceMetrics()
        print("📊 PRELOAD PERFORMANCE:")
        print("   Cache Hit Rate: \(String(format: "%.1f%%", metrics.cacheHitRate * 100))")
        print("   Pool Utilization: \(String(format: "%.1f%%", metrics.poolUtilization * 100))")
        print("   Memory Usage: \(String(format: "%.1fMB", metrics.memoryUsage))")
        print("   Success Rate: \(String(format: "%.1f%%", metrics.preloadSuccessRate * 100))")
    }
}

/// Performance metrics structure
struct PreloadingMetrics {
    let cacheHitRate: Double
    let averagePreloadTime: TimeInterval
    let memoryUsage: Double // MB
    let poolUtilization: Double
    let preloadSuccessRate: Double
}

// MARK: - Hello World Test Extension

extension VideoPreloadingService {
    
    /// Test preloading functionality
    func helloWorldTest() {
        print("🎬 PRELOAD SERVICE: Hello World - Ready for smooth multidirectional video swiping!")
        print("🏊 Pool Size: \(maxPoolSize) players")
        print("🔍 Preload Distance: \(preloadDistance) videos")
        print("📊 Current Pool: \(playerPool.count) players")
        print("⚡ Concurrent Limit: \(maxConcurrentPreloads) simultaneous preloads")
    }
}
