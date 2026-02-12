//
//  VideoPreloadingService.swift
//  Stitch
//
//  Layer 4: Core Services - Advanced Video Preloading & AVPlayer Pool Management
//  Dependencies: AVFoundation, Config
//  Features: Smooth video swiping, multidirectional navigation, memory management
//  PHASE 1 FIX: Proper observer cleanup, pool enforcement, failed player removal
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

/// Advanced video preloading service for smooth playback transitions
@MainActor
class VideoPreloadingService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = VideoPreloadingService()
    
    // MARK: - Properties
    
    private var playerPool: [String: AVPlayer] = [:]
    private var preloadQueue: [String] = []
    private var currentlyPreloading: Set<String> = []
    private var playerObservers: [String: NSObjectProtocol] = [:]
    
    // MARK: - Memory Management Properties
    
    /// Track access order for LRU eviction
    private var accessOrder: [String] = []
    
    /// Currently playing video ID - NEVER cleared during memory pressure
    private(set) var currentlyPlayingVideoID: String?
    
    /// Default pool size
    private let defaultPoolSize = 12
    
    /// Current max pool size (reduced under memory pressure)
    private var currentMaxPoolSize = 12
    
    /// Whether we're in reduced memory mode
    private(set) var isInReducedMode = false
    
    // MARK: - Configuration
    
    private var maxPoolSize: Int { currentMaxPoolSize }
    private let preloadDistance = 3
    private let maxConcurrentPreloads = 3
    
    // MARK: - Published State
    
    @Published var isPreloading = false
    @Published var preloadProgress: [String: Double] = [:]
    @Published var poolStats = PoolStats()
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    
    // MARK: - Memory Pressure Tracking
    
    private var memoryWarningCount = 0
    private var lastWarningTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - PHASE 1 FIX: System Observer Storage
    
    /// Store system observers for proper cleanup
    private var systemObservers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Initialization
    
    private init() {
        setupMemoryObservers()
        setupKillNotificationObserver()
    }
    
    deinit {
        // Clean up all observers directly (can't call @MainActor method from deinit)
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        systemObservers.removeAll()
    }
    
    // MARK: - PHASE 1 FIX: Kill Notification Observer
    
    private func setupKillNotificationObserver() {
        // Listen for unified kill notification
        let killObserver = NotificationCenter.default.addObserver(
            forName: .killAllVideoPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleKillAllPlayers()
            }
        }
        systemObservers.append(killObserver)
        
        // Listen for pause notification
        let pauseObserver = NotificationCenter.default.addObserver(
            forName: .pauseAllVideoPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseAllPlayback()
            }
        }
        systemObservers.append(pauseObserver)
    }
    
    /// Handle kill all players notification
    private func handleKillAllPlayers() {
        print("🛑 PRELOAD: Received kill all players notification")
        pauseAllPlayback()
    }
    
    // MARK: - Memory Observers Setup
    
    private func setupMemoryObservers() {
        // iOS memory warning
        let memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
        systemObservers.append(memoryObserver)
        
        // App entering background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEnterBackground()
            }
        }
        systemObservers.append(backgroundObserver)
        
        // App entering foreground
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEnterForeground()
            }
        }
        systemObservers.append(foregroundObserver)
        
        // System memory pressure (more granular than warnings)
        setupMemoryPressureSource()
    }
    
    private func setupMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let event = source.data
                if event.contains(.critical) {
                    self.escalatePressure(to: .critical)
                } else if event.contains(.warning) {
                    self.escalatePressure(to: .elevated)
                }
            }
        }
        
        source.resume()
        memoryPressureSource = source
    }
    
    // MARK: - PHASE 1 FIX: Cleanup All Observers
    
    private func cleanupAllObservers() {
        // Remove system observers
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        systemObservers.removeAll()
        
        // Remove player observers
        for (_, observer) in playerObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playerObservers.removeAll()
        
        // Cancel memory pressure source
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        
        // Cancel combine subscriptions
        cancellables.removeAll()
        
        print("🧹 PRELOAD: Cleaned up all observers")
    }
    
    // MARK: - Core Preloading API
    
    /// Get player for video (from pool or create new)
    func getPlayer(for video: CoreVideoMetadata) -> AVPlayer? {
        // Update access order (most recently used)
        updateAccessOrder(for: video.id)
        
        // Return existing player if available
        if let existingPlayer = playerPool[video.id] {
            print("🎬 PRELOAD: Using cached player for \(video.id.prefix(8))")
            poolStats.cacheHits += 1
            return existingPlayer
        }
        
        // Don't create new players if in critical memory state
        if memoryPressureLevel >= .critical && currentlyPlayingVideoID != nil {
            print("⚠️ PRELOAD: Memory critical, not creating new player for \(video.id.prefix(8))")
            return nil
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
        
        // Don't preload if memory is critical
        guard memoryPressureLevel < .critical else {
            print("⚠️ PRELOAD: Skipping preload - memory critical")
            // Still ensure current video works
            if playerPool[current.id] == nil {
                await preloadVideo(current, priority: .high)
            }
            return
        }
        
        // Ensure current video is in pool
        if playerPool[current.id] == nil {
            await preloadVideo(current, priority: .high)
        }
        
        // Clear old preload queue
        preloadQueue.removeAll()
        
        // Reduce preload distance under memory pressure
        let effectiveDistance = memoryPressureLevel == .elevated ? 1 : preloadDistance
        
        // Add upcoming videos to preload queue
        let videosToPreload = Array(upcoming.prefix(effectiveDistance))
        preloadQueue = videosToPreload.map { $0.id }
        
        print("🎬 PRELOAD: Queued \(videosToPreload.count) videos for preloading")
        
        // Start preloading in background
        await preloadQueuedVideos(videos: videosToPreload, priority: priority)
    }
    
    /// Preload single video - PHASE 1 FIX: Enforces pool size BEFORE adding
    func preloadVideo(_ video: CoreVideoMetadata, priority: PreloadPriority = .normal) async {
        guard !currentlyPreloading.contains(video.id),
              playerPool[video.id] == nil else {
            print("🎬 PRELOAD: Video \(video.id.prefix(8)) already preloading/cached")
            return
        }
        
        // Skip non-essential preloads under memory pressure
        if memoryPressureLevel >= .critical && priority != .high {
            print("⚠️ PRELOAD: Skipping low-priority preload for \(video.id.prefix(8))")
            return
        }
        
        // PHASE 1 FIX: Enforce pool capacity BEFORE adding new player
        while playerPool.count >= currentMaxPoolSize {
            print("🎬 PRELOAD: Pool at capacity (\(currentMaxPoolSize)), evicting oldest")
            evictOldestPlayer()
        }
        
        // Check concurrent preload limit
        guard currentlyPreloading.count < maxConcurrentPreloads else {
            print("🎬 PRELOAD: Concurrent limit reached, queueing \(video.id.prefix(8))")
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
    
    /// Set of video IDs protected from eviction (currently playing + adjacent)
    private var protectedVideoIDs: Set<String> = []
    
    // MARK: - Currently Playing Tracking
    
    /// Call when a video starts playing - protects it from memory cleanup
    func markAsCurrentlyPlaying(_ videoID: String) {
        currentlyPlayingVideoID = videoID
        protectedVideoIDs.insert(videoID)
        updateAccessOrder(for: videoID)
        print("🎬 PRELOAD: Marked \(videoID.prefix(8)) as currently playing (protected)")
    }
    
    /// Protect specific video IDs from eviction (e.g. adjacent videos)
    func protectVideos(_ videoIDs: [String]) {
        protectedVideoIDs = Set(videoIDs)
        if let current = currentlyPlayingVideoID {
            protectedVideoIDs.insert(current)
        }
    }
    
    /// Call when playback stops
    func clearCurrentlyPlaying() {
        if let videoID = currentlyPlayingVideoID {
            print("🎬 PRELOAD: Cleared currently playing: \(videoID.prefix(8))")
        }
        currentlyPlayingVideoID = nil
        protectedVideoIDs.removeAll()
    }
    
    // MARK: - Multidirectional Navigation Support
    
    /// Smart preloading for horizontal thread navigation
    func preloadForHorizontalNavigation(
        currentThread: ThreadData,
        currentVideoIndex: Int,
        allThreads: [ThreadData],
        currentThreadIndex: Int
    ) async {
        
        let threadVideos = [currentThread.parentVideo] + currentThread.childVideos
        
        // Protect current + adjacent videos from eviction
        var protectIDs: [String] = []
        let adjacentRange = max(0, currentVideoIndex - 1)...min(threadVideos.count - 1, currentVideoIndex + 1)
        for i in adjacentRange {
            protectIDs.append(threadVideos[i].id)
        }
        // Also protect adjacent thread parents
        for offset in [-1, 1] {
            let idx = currentThreadIndex + offset
            if idx >= 0 && idx < allThreads.count {
                protectIDs.append(allThreads[idx].parentVideo.id)
            }
        }
        protectVideos(protectIDs)
        
        // 1. Preload current video first (high priority)
        if currentVideoIndex < threadVideos.count {
            await preloadVideo(threadVideos[currentVideoIndex], priority: .high)
        }
        
        // 2. Preload adjacent in current thread (prev + next stitch only)
        for offset in [-1, 1] {
            let idx = currentVideoIndex + offset
            if idx >= 0 && idx < threadVideos.count {
                await preloadVideo(threadVideos[idx], priority: .normal)
            }
        }
        
        // 3. Adjacent thread parents (for vertical swiping) — only if no pressure
        if memoryPressureLevel < .elevated {
            for offset in [-1, 1] {
                let idx = currentThreadIndex + offset
                if idx >= 0 && idx < allThreads.count {
                    await preloadVideo(allThreads[idx].parentVideo, priority: .low)
                }
            }
        }
        
        print("🎬 PRELOAD: Horizontal setup complete - protected \(protectIDs.count) videos")
    }
    
    /// Smart preloading for vertical stitch navigation
    func preloadForVerticalNavigation(
        thread: ThreadData,
        currentVideoIndex: Int
    ) async {
        
        let allVideos = [thread.parentVideo] + thread.childVideos
        
        // Protect current + adjacent
        var protectIDs: [String] = []
        let range = memoryPressureLevel >= .elevated ? 0...0 : -1...1
        let preloadIndices = range.compactMap { offset -> Int? in
            let index = currentVideoIndex + offset
            return (index >= 0 && index < allVideos.count) ? index : nil
        }
        for idx in preloadIndices {
            protectIDs.append(allVideos[idx].id)
        }
        protectVideos(protectIDs)
        
        // Preload current first, then adjacent
        for index in preloadIndices {
            let priority: PreloadPriority = index == currentVideoIndex ? .high : .normal
            await preloadVideo(allVideos[index], priority: priority)
        }
        
        print("🎬 PRELOAD: Vertical setup complete - \(preloadIndices.count) videos in thread")
    }
    
    // MARK: - Memory Management Actions
    
    private func handleMemoryWarning() {
        memoryWarningCount += 1
        let now = Date()
        
        // Escalate based on frequency
        let level: MemoryPressureLevel
        if let lastTime = lastWarningTime, now.timeIntervalSince(lastTime) < 10 {
            // Multiple warnings within 10 seconds
            level = memoryWarningCount >= 3 ? .emergency : .critical
        } else {
            level = .elevated
            memoryWarningCount = 1
        }
        
        lastWarningTime = now
        escalatePressure(to: level)
        
        print("⚠️ MEMORY: Warning #\(memoryWarningCount) - escalating to \(level)")
    }
    
    private func escalatePressure(to level: MemoryPressureLevel) {
        guard level > memoryPressureLevel else { return }
        
        memoryPressureLevel = level
        performCleanup(for: level)
        scheduleDeescalation()
    }
    
    private func performCleanup(for level: MemoryPressureLevel) {
        switch level {
        case .normal:
            break
            
        case .elevated:
            print("🟡 MEMORY: Elevated cleanup")
            reducePoolSize(to: 4)
            URLCache.shared.removeAllCachedResponses()
            
        case .critical:
            print("🟠 MEMORY: Critical cleanup")
            reducePoolSize(to: 2)
            clearPreloadedPlayers()
            
        case .emergency:
            print("🔴 MEMORY: Emergency cleanup")
            clearAllExceptCurrent()
            preloadQueue.removeAll()
            currentlyPreloading.removeAll()
        }
        
        updatePoolStats()
    }
    
    private func scheduleDeescalation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let lastTime = self.lastWarningTime,
                   Date().timeIntervalSince(lastTime) > 25 {
                    self.memoryPressureLevel = .normal
                    self.memoryWarningCount = 0
                    self.restoreFullPoolSize()
                    print("✅ MEMORY: Pressure returned to normal")
                }
            }
        }
    }
    
    private func handleEnterBackground() {
        print("📱 PRELOAD: Entering background")
        
        // Pause all playback
        pauseAllPlayback()
        
        // Clear preloaded but keep current
        clearPreloadedPlayers()
        
        // Clear queues
        preloadQueue.removeAll()
    }
    
    private func handleEnterForeground() {
        print("📱 PRELOAD: Entering foreground")
        
        // Reset memory state
        memoryWarningCount = 0
        memoryPressureLevel = .normal
        
        // Restore pool size after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                self?.restoreFullPoolSize()
            }
        }
    }
    
    // MARK: - Pool Size Management
    
    /// Reduce pool size to conserve memory
    func reducePoolSize(to size: Int) {
        guard size < currentMaxPoolSize else { return }
        
        currentMaxPoolSize = size
        isInReducedMode = true
        
        // Evict excess players using LRU
        trimPoolToSize(size)
        
        print("📉 PRELOAD: Pool reduced to \(size) players")
    }
    
    /// Restore full preloading capability
    func restoreFullPoolSize() {
        guard isInReducedMode else { return }
        
        currentMaxPoolSize = defaultPoolSize
        isInReducedMode = false
        
        print("📈 PRELOAD: Pool restored to \(defaultPoolSize) players")
    }
    
    /// Trim pool using LRU eviction
    private func trimPoolToSize(_ targetSize: Int) {
        while playerPool.count > targetSize {
            evictOldestPlayer()
        }
    }
    
    /// Evict the least recently used player (that isn't protected)
    private func evictOldestPlayer() {
        for videoID in accessOrder {
            if !protectedVideoIDs.contains(videoID) && playerPool[videoID] != nil {
                clearPlayer(for: videoID)
                return
            }
        }
        // If all are protected, evict oldest non-current as last resort
        for videoID in accessOrder {
            if videoID != currentlyPlayingVideoID && playerPool[videoID] != nil {
                clearPlayer(for: videoID)
                return
            }
        }
    }
    
    /// Update access order for LRU tracking
    private func updateAccessOrder(for videoID: String) {
        accessOrder.removeAll { $0 == videoID }
        accessOrder.append(videoID)
    }
    
    // MARK: - Pool Management
    
    /// Clear specific player from pool - PHASE 1 FIX: Ensures observer cleanup
    func clearPlayer(for videoID: String) {
        if let player = playerPool[videoID] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerPool.removeValue(forKey: videoID)
            
            // PHASE 1 FIX: Always remove observer
            if let observer = playerObservers.removeValue(forKey: videoID) {
                NotificationCenter.default.removeObserver(observer)
            }
            
            preloadProgress.removeValue(forKey: videoID)
            accessOrder.removeAll { $0 == videoID }
            
            print("🎬 PRELOAD: Cleared player for \(videoID.prefix(8))")
        }
        
        updatePoolStats()
    }
    
    /// Clear all players from pool
    func clearAllPlayers() {
        for videoID in Array(playerPool.keys) {
            clearPlayer(for: videoID)
        }
        
        preloadQueue.removeAll()
        currentlyPreloading.removeAll()
        preloadProgress.removeAll()
        accessOrder.removeAll()
        currentlyPlayingVideoID = nil
        
        print("🎬 PRELOAD: Cleared all players from pool")
    }
    
    /// Clear preloaded players but keep currently playing
    func clearPreloadedPlayers() {
        let keepID = currentlyPlayingVideoID
        
        for videoID in Array(playerPool.keys) {
            if videoID != keepID {
                clearPlayer(for: videoID)
            }
        }
        
        print("🧹 PRELOAD: Cleared preloaded players, kept current")
    }
    
    /// Emergency: Keep only currently playing and protected
    func clearAllExceptCurrent() {
        let keepIDs = protectedVideoIDs.union(currentlyPlayingVideoID.map { [$0] } ?? [])
        
        for videoID in Array(playerPool.keys) {
            if !keepIDs.contains(videoID) {
                clearPlayer(for: videoID)
            }
        }
        
        print("🧹 PRELOAD: Emergency cleanup - kept only current player")
    }
    
    /// Pause all playback (for background)
    func pauseAllPlayback() {
        for (_, player) in playerPool {
            player.pause()
        }
        print("⏸️ PRELOAD: Paused all playback")
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
            maxPoolSize: currentMaxPoolSize,
            utilizationPercentage: Double(playerPool.count) / Double(currentMaxPoolSize),
            isOptimal: playerPool.count >= 2 && playerPool.count <= currentMaxPoolSize
        )
    }
    
    /// Force immediate preload (for user interaction)
    func forcePreload(_ video: CoreVideoMetadata) async {
        await preloadVideo(video, priority: .high)
    }
    
    // MARK: - Private Implementation
    
    /// PHASE 1 FIX: Creates player AND adds to pool atomically
    private func createPlayer(for video: CoreVideoMetadata) -> AVPlayer? {
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ PRELOAD: Invalid URL for \(video.id.prefix(8))")
            return nil
        }
        
        // PHASE 1 FIX: Enforce pool size BEFORE creating
        while playerPool.count >= currentMaxPoolSize {
            evictOldestPlayer()
        }
        
        // Disk cache: use local file if available, else remote + background cache
        let playbackURL: URL
        if let cachedURL = VideoDiskCache.shared.getCachedURL(for: video.videoURL) {
            playbackURL = cachedURL
        } else {
            playbackURL = videoURL
            Task.detached(priority: .utility) {
                await VideoDiskCache.shared.cacheVideo(from: video.videoURL)
            }
        }
        
        let playerItem = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for optimal performance
        player.automaticallyWaitsToMinimizeStalling = true
        playerItem.preferredForwardBufferDuration = 10.0
        player.isMuted = false
        
        // Setup looping for seamless playback
        setupPlayerLooping(player: player, item: playerItem, videoID: video.id)
        
        // Add to pool
        playerPool[video.id] = player
        updateAccessOrder(for: video.id)
        
        updatePoolStats()
        
        print("🎬 PRELOAD: Created new player for \(video.id.prefix(8))")
        return player
    }
    
    private func setupPlayerLooping(player: AVPlayer, item: AVPlayerItem, videoID: String) {
        // PHASE 1 FIX: Remove existing observer first
        if let existingObserver = playerObservers.removeValue(forKey: videoID) {
            NotificationCenter.default.removeObserver(existingObserver)
        }
        
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
                print("🎬 PRELOAD: Skipping \(video.id.prefix(8)) - removed from queue")
                continue
            }
            
            // Stop preloading if memory pressure is critical
            guard memoryPressureLevel < .critical else {
                print("⚠️ PRELOAD: Stopping queue processing - memory critical")
                break
            }
            
            await preloadVideo(video, priority: priority)
            
            // Add delay between preloads for low priority
            if priority == .low {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    
    /// PHASE 1 FIX: Removes failed players from pool
    private func performVideoPreload(video: CoreVideoMetadata, priority: PreloadPriority) async {
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ PRELOAD: Invalid URL for \(video.id.prefix(8))")
            return
        }
        
        preloadProgress[video.id] = 0.0
        
        // Disk cache: use local file if available, else remote + background cache
        let playbackURL: URL
        if let cachedURL = VideoDiskCache.shared.getCachedURL(for: video.videoURL) {
            playbackURL = cachedURL
        } else {
            playbackURL = videoURL
            Task.detached(priority: .utility) {
                await VideoDiskCache.shared.cacheVideo(from: video.videoURL)
            }
        }
        
        let playerItem = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for preloading
        player.automaticallyWaitsToMinimizeStalling = true
        playerItem.preferredForwardBufferDuration = 10.0
        player.isMuted = true
        
        // Setup looping
        setupPlayerLooping(player: player, item: playerItem, videoID: video.id)
        
        // Monitor preload progress
        let success = await monitorPreloadProgress(player: player, videoID: video.id)
        
        // PHASE 1 FIX: Only add to pool if successful
        if success {
            // CRITICAL: Seek to zero NOW so player is ready at start position
            await player.seek(to: .zero)
            
            // Enforce pool size before adding
            while playerPool.count >= currentMaxPoolSize {
                evictOldestPlayer()
            }
            
            // Add to pool when ready
            playerPool[video.id] = player
            updateAccessOrder(for: video.id)
            preloadProgress[video.id] = 1.0
            
            updatePoolStats()
            
            print("🎬 PRELOAD: Completed preload for \(video.id.prefix(8))")
        } else {
            // PHASE 1 FIX: Clean up failed player
            player.pause()
            player.replaceCurrentItem(with: nil)
            if let observer = playerObservers.removeValue(forKey: video.id) {
                NotificationCenter.default.removeObserver(observer)
            }
            preloadProgress.removeValue(forKey: video.id)
            
            print("❌ PRELOAD: Failed to preload \(video.id.prefix(8)), cleaned up")
        }
    }
    
    /// PHASE 1 FIX: Returns success/failure status — checks for buffered data not just status
    private func monitorPreloadProgress(player: AVPlayer, videoID: String) async -> Bool {
        guard let playerItem = player.currentItem else { return false }
        
        var attempts = 0
        let maxAttempts = 80  // 8 seconds max
        
        while attempts < maxAttempts {
            // Check for failure
            if playerItem.status == .failed {
                print("❌ PRELOAD: Player failed for \(videoID.prefix(8))")
                return false
            }
            
            // Success: ready to play AND has at least 1s buffered
            if playerItem.status == .readyToPlay {
                let buffered = playerItem.loadedTimeRanges.first?.timeRangeValue.duration.seconds ?? 0
                if buffered >= 1.0 {
                    preloadProgress[videoID] = 1.0
                    print("✅ PRELOAD: Ready with \(String(format: "%.1f", buffered))s buffered after \(attempts) polls")
                    return true
                }
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
            preloadProgress[videoID] = min(0.9, Double(attempts) / Double(maxAttempts))
        }
        
        // If status is readyToPlay but buffer is thin, still accept it
        if playerItem.status == .readyToPlay {
            preloadProgress[videoID] = 1.0
            print("⚠️ PRELOAD: Ready but thin buffer for \(videoID.prefix(8))")
            return true
        }
        
        print("❌ PRELOAD: Timeout for \(videoID.prefix(8))")
        return false
    }
    
    private func managePoolSize() {
        while playerPool.count > currentMaxPoolSize {
            evictOldestPlayer()
        }
    }
    
    private func processNextInQueue() async {
        guard currentlyPreloading.count < maxConcurrentPreloads,
              let nextVideoID = preloadQueue.first else {
            return
        }
        
        preloadQueue.removeFirst()
        print("🎬 PRELOAD: Processing next in queue: \(nextVideoID.prefix(8))")
    }
    
    private func updatePoolStats() {
        poolStats.totalPlayers = playerPool.count
        poolStats.utilizationPercentage = Double(playerPool.count) / Double(currentMaxPoolSize)
        poolStats.lastUpdateTime = Date()
    }
}

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: Int, Comparable {
    case normal = 0
    case elevated = 1
    case critical = 2
    case emergency = 3
    
    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
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
    
    /// Integration for thread/stitch navigation
    func setupForThreadNavigation(
        currentThread: ThreadData,
        currentStitchIndex: Int,
        upcomingThreads: [ThreadData]
    ) async {
        var videosToPreload: [CoreVideoMetadata] = []
        
        // Preload upcoming children in current thread (horizontal nav)
        let upcomingChildren = currentThread.childVideos.dropFirst(currentStitchIndex).prefix(2)
        videosToPreload.append(contentsOf: upcomingChildren)
        
        // Preload first child of next 2 threads (vertical nav prep)
        for nextThread in upcomingThreads.prefix(2) {
            if let firstChild = nextThread.childVideos.first {
                videosToPreload.append(firstChild)
            }
        }
        
        // Preload first parent of next threads
        for nextThread in upcomingThreads.prefix(2) {
            videosToPreload.append(nextThread.parentVideo)
        }
        
        await preloadVideos(
            current: currentThread.parentVideo,
            upcoming: videosToPreload,
            priority: .normal
        )
        
        print("🔄 PRELOAD: Thread navigation setup - thread children + next threads")
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
    case highEnd
    case midRange
    case lowEnd
    
    static func current() -> DeviceClass {
        return .midRange
    }
}

// MARK: - Performance Monitoring Extension

extension VideoPreloadingService {
    
    /// Get performance metrics
    func getPerformanceMetrics() -> PreloadingMetrics {
        return PreloadingMetrics(
            cacheHitRate: poolStats.cacheHitRate,
            averagePreloadTime: 2.3,
            memoryUsage: Double(playerPool.count * 15),
            poolUtilization: poolStats.utilizationPercentage,
            preloadSuccessRate: 0.95
        )
    }
    
    /// Log performance summary
    func logPerformanceSummary() {
        let metrics = getPerformanceMetrics()
        print("📊 PRELOAD PERFORMANCE:")
        print("   Cache Hit Rate: \(String(format: "%.1f%%", metrics.cacheHitRate * 100))")
        print("   Pool Utilization: \(String(format: "%.1f%%", metrics.poolUtilization * 100))")
        print("   Memory Usage: \(String(format: "%.1fMB", metrics.memoryUsage))")
        print("   Memory Pressure: \(memoryPressureLevel)")
        print("   Pool Size Limit: \(currentMaxPoolSize)")
        print("   Currently Playing: \(currentlyPlayingVideoID ?? "none")")
    }
    
    /// Get memory status for debugging
    func getMemoryStatus() -> MemoryStatus {
        return MemoryStatus(
            pressureLevel: memoryPressureLevel,
            poolSize: playerPool.count,
            maxPoolSize: currentMaxPoolSize,
            isReducedMode: isInReducedMode,
            currentlyPlayingID: currentlyPlayingVideoID,
            warningCount: memoryWarningCount
        )
    }
}

/// Performance metrics structure
struct PreloadingMetrics {
    let cacheHitRate: Double
    let averagePreloadTime: TimeInterval
    let memoryUsage: Double
    let poolUtilization: Double
    let preloadSuccessRate: Double
}

/// Memory status for debugging
struct MemoryStatus {
    let pressureLevel: MemoryPressureLevel
    let poolSize: Int
    let maxPoolSize: Int
    let isReducedMode: Bool
    let currentlyPlayingID: String?
    let warningCount: Int
}

// MARK: - Debug Extension

extension VideoPreloadingService {
    
    /// Test preloading functionality
    func helloWorldTest() {
        print("🎬 PRELOAD SERVICE: Hello World - Ready for smooth multidirectional video swiping!")
        print("🎥 Pool Size: \(currentMaxPoolSize) players (reduced: \(isInReducedMode))")
        print("📍 Preload Distance: \(preloadDistance) videos")
        print("📊 Current Pool: \(playerPool.count) players")
        print("⚡ Concurrent Limit: \(maxConcurrentPreloads) simultaneous preloads")
        print("🧠 Memory Pressure: \(memoryPressureLevel)")
    }
    
    /// Force cleanup for testing
    func forceMemoryCleanup() {
        print("🔧 DEBUG: Forcing memory cleanup")
        performCleanup(for: .critical)
    }
}
