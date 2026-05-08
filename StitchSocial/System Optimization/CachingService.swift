//
//  CachingService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Memory-Based Caching with LRU Eviction
//  Dependencies: Foundation, Config
//  Features: Video metadata cache, user cache, thread cache, LRU management
//  OPTIMIZED: Added AI result cache cleanup coordination
//  OPTIMIZED: Now used by default in VideoCoordinator + ThreadComposer (was nil before)
//

import Foundation
import SwiftUI

/// Memory-based caching service with LRU eviction for instant app startup
@MainActor
class CachingService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CachingService()
    
    // MARK: - Cache Storage
    
    private var videoCache: [String: CachedVideo] = [:]
    private var userCache: [String: CachedUser] = [:]
    private var threadCache: [String: CachedThread] = [:]
    private var accessTimes: [String: Date] = [:]
    
    // MARK: - Configuration
    
    private let maxMemorySize: Int = 50 * 1024 * 1024 // 50MB memory limit
    private let maxVideoEntries = 100
    private let maxUserEntries = 200
    private let maxThreadEntries = 50
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    // MARK: - Published State
    
    @Published var cacheStats = CacheStats()
    @Published var isCleaningUp = false
    
    // MARK: - Video Caching
    
    /// Cache video metadata with priority
    func cacheVideo(_ video: CoreVideoMetadata, priority: CachePriority = .normal) {
        let cacheEntry = CachedVideo(
            video: video,
            cachedAt: Date(),
            priority: priority,
            accessCount: 1
        )
        
        videoCache[video.id] = cacheEntry
        accessTimes[video.id] = Date()
        
        // Manage cache size
        manageVideoCacheSize()
        updateCacheStats()
        
        #if DEBUG
        print("💾 CACHE: Video cached - \(video.id)")
        #endif
    }
    
    /// Get cached video if available and not expired
    func getCachedVideo(id: String) -> CoreVideoMetadata? {
        guard let cached = videoCache[id],
              !isCacheExpired(cached.cachedAt) else {
            cacheStats.misses += 1
            return nil
        }
        
        // Update access time and count
        accessTimes[id] = Date()
        videoCache[id]?.accessCount += 1
        
        cacheStats.hits += 1
        #if DEBUG
        print("💾 CACHE: Video hit - \(id)")
        #endif
        return cached.video
    }
    
    /// Cache multiple videos with batch optimization
    func cacheVideos(_ videos: [CoreVideoMetadata], priority: CachePriority = .normal) {
        for video in videos {
            cacheVideo(video, priority: priority)
        }
        
        #if DEBUG
        print("💾 CACHE: Batched \(videos.count) videos")
        #endif
    }
    
    /// Get all cached videos for a specific user, sorted by createdAt descending
    func getCachedVideosForUser(_ userID: String) -> [CoreVideoMetadata] {
        return videoCache.values
            .filter { !isCacheExpired($0.cachedAt) && $0.video.creatorID == userID }
            .sorted { $0.video.createdAt > $1.video.createdAt }
            .map { $0.video }
    }
    
    // MARK: - User Caching
    
    /// Cache user data
    func cacheUser(_ user: UserProfileData, priority: CachePriority = .normal) {
        let cacheEntry = CachedUser(
            user: user,
            cachedAt: Date(),
            priority: priority,
            accessCount: 1
        )
        
        userCache[user.id] = cacheEntry
        accessTimes[user.id] = Date()
        
        manageUserCacheSize()
        updateCacheStats()
        
        #if DEBUG
        print("💾 CACHE: User cached - \(user.id)")
        #endif
    }
    
    /// Get cached user if available
    func getCachedUser(id: String) -> UserProfileData? {
        guard let cached = userCache[id],
              !isCacheExpired(cached.cachedAt) else {
            cacheStats.misses += 1
            return nil
        }
        
        // Update access time and count
        accessTimes[id] = Date()
        userCache[id]?.accessCount += 1
        
        cacheStats.hits += 1
        return cached.user
    }
    
    // MARK: - Thread Caching
    
    /// Cache thread data for instant feed display
    func cacheThread(_ thread: ThreadData, priority: CachePriority = .normal) {
        let cacheEntry = CachedThread(
            thread: thread,
            cachedAt: Date(),
            priority: priority,
            accessCount: 1
        )
        
        threadCache[thread.id] = cacheEntry
        accessTimes[thread.id] = Date()
        
        manageThreadCacheSize()
        updateCacheStats()
        
        #if DEBUG
        print("💾 CACHE: Thread cached - \(thread.id)")
        #endif
    }
    
    /// Get cached thread if available
    func getCachedThread(id: String) -> ThreadData? {
        guard let cached = threadCache[id],
              !isCacheExpired(cached.cachedAt) else {
            cacheStats.misses += 1
            return nil
        }
        
        // Update access time and count
        accessTimes[id] = Date()
        threadCache[id]?.accessCount += 1
        
        cacheStats.hits += 1
        return cached.thread
    }
    
    /// Cache multiple threads for feed
    func cacheThreads(_ threads: [ThreadData], priority: CachePriority = .normal) {
        for thread in threads {
            cacheThread(thread, priority: priority)
        }
        
        #if DEBUG
        print("💾 CACHE: Batched \(threads.count) threads")
        #endif
    }
    
    // MARK: - Cache Management
    
    /// Check if cache entry is expired
    private func isCacheExpired(_ cachedAt: Date) -> Bool {
        return Date().timeIntervalSince(cachedAt) > cacheExpiration
    }
    
    /// Manage video cache size with LRU eviction
    private func manageVideoCacheSize() {
        while videoCache.count > maxVideoEntries {
            evictLeastRecentlyUsedVideo()
        }
    }
    
    /// Manage user cache size with LRU eviction
    private func manageUserCacheSize() {
        while userCache.count > maxUserEntries {
            evictLeastRecentlyUsedUser()
        }
    }
    
    /// Manage thread cache size with LRU eviction
    private func manageThreadCacheSize() {
        while threadCache.count > maxThreadEntries {
            evictLeastRecentlyUsedThread()
        }
    }
    
    /// Evict least recently used video
    private func evictLeastRecentlyUsedVideo() {
        guard let oldestVideoID = findLeastRecentlyUsed(in: Array(videoCache.keys)) else {
            return
        }
        
        videoCache.removeValue(forKey: oldestVideoID)
        accessTimes.removeValue(forKey: oldestVideoID)
        cacheStats.evictions += 1
        
        #if DEBUG
        print("💾 CACHE: Evicted video - \(oldestVideoID)")
        #endif
    }
    
    /// Evict least recently used user
    private func evictLeastRecentlyUsedUser() {
        guard let oldestUserID = findLeastRecentlyUsed(in: Array(userCache.keys)) else {
            return
        }
        
        userCache.removeValue(forKey: oldestUserID)
        accessTimes.removeValue(forKey: oldestUserID)
        cacheStats.evictions += 1
        
        #if DEBUG
        print("💾 CACHE: Evicted user - \(oldestUserID)")
        #endif
    }
    
    /// Evict least recently used thread
    private func evictLeastRecentlyUsedThread() {
        guard let oldestThreadID = findLeastRecentlyUsed(in: Array(threadCache.keys)) else {
            return
        }
        
        threadCache.removeValue(forKey: oldestThreadID)
        accessTimes.removeValue(forKey: oldestThreadID)
        cacheStats.evictions += 1
        
        #if DEBUG
        print("💾 CACHE: Evicted thread - \(oldestThreadID)")
        #endif
    }
    
    /// Find least recently used item by access time
    private func findLeastRecentlyUsed(in keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        
        var lruKey = keys[0]
        var lruTime = accessTimes[keys[0]] ?? Date.distantPast
        
        for key in keys.dropFirst() {
            let time = accessTimes[key] ?? Date.distantPast
            if time < lruTime {
                lruKey = key
                lruTime = time
            }
        }
        
        return lruKey
    }
    
    // MARK: - Cache Statistics and Monitoring
    
    /// Update cache statistics
    private func updateCacheStats() {
        cacheStats.totalEntries = videoCache.count + userCache.count + threadCache.count
        cacheStats.videoEntries = videoCache.count
        cacheStats.userEntries = userCache.count
        cacheStats.threadEntries = threadCache.count
        cacheStats.hitRate = calculateHitRate()
        cacheStats.memoryUsage = estimateMemoryUsage()
        cacheStats.lastUpdated = Date()
    }
    
    /// Calculate cache hit rate
    private func calculateHitRate() -> Double {
        let total = cacheStats.hits + cacheStats.misses
        return total > 0 ? Double(cacheStats.hits) / Double(total) : 0.0
    }
    
    /// Estimate current memory usage in bytes
    private func estimateMemoryUsage() -> Int {
        let videoSize = videoCache.count * 2048 // ~2KB per video metadata
        let userSize = userCache.count * 1024 // ~1KB per user
        let threadSize = threadCache.count * 4096 // ~4KB per thread with children
        
        return videoSize + userSize + threadSize
    }
    
    /// Log cache performance metrics
    func logCachePerformance() {
        let stats = cacheStats
        #if DEBUG
        print("📊 CACHE PERFORMANCE:")
        #endif
        #if DEBUG
        print("   Total Entries: \(stats.totalEntries)")
        #endif
        #if DEBUG
        print("   Hit Rate: \(String(format: "%.1f%%", stats.hitRate * 100))")
        #endif
        #if DEBUG
        print("   Memory Usage: \(formatMemorySize(stats.memoryUsage))")
        #endif
        #if DEBUG
        print("   Evictions: \(stats.evictions)")
        #endif
        #if DEBUG
        print("   Videos: \(stats.videoEntries), Users: \(stats.userEntries), Threads: \(stats.threadEntries)")
        #endif
    }
    
    /// Format memory size for display
    private func formatMemorySize(_ bytes: Int) -> String {
        if bytes > 1024 * 1024 {
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        } else if bytes > 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024)
        } else {
            return "\(bytes)B"
        }
    }
    
    // MARK: - Cache Cleanup
    
    /// Clean expired entries
    func cleanupExpiredEntries() {
        let now = Date()
        var removedCount = 0
        
        // Clean videos
        let expiredVideos = videoCache.filter { isCacheExpired($0.value.cachedAt) }
        for (videoID, _) in expiredVideos {
            videoCache.removeValue(forKey: videoID)
            accessTimes.removeValue(forKey: videoID)
            removedCount += 1
        }
        
        // Clean users
        let expiredUsers = userCache.filter { isCacheExpired($0.value.cachedAt) }
        for (userID, _) in expiredUsers {
            userCache.removeValue(forKey: userID)
            accessTimes.removeValue(forKey: userID)
            removedCount += 1
        }
        
        // Clean threads
        let expiredThreads = threadCache.filter { isCacheExpired($0.value.cachedAt) }
        for (threadID, _) in expiredThreads {
            threadCache.removeValue(forKey: threadID)
            accessTimes.removeValue(forKey: threadID)
            removedCount += 1
        }
        
        if removedCount > 0 {
            updateCacheStats()
            #if DEBUG
            print("💾 CACHE: Cleaned \(removedCount) expired entries")
            #endif
        }
        
        // Also clean AI result cache (coordinated cleanup)
        AIVideoAnalyzer.shared.cleanupAICache()
    }
    
    /// Clear all caches
    func clearAllCaches() {
        videoCache.removeAll()
        userCache.removeAll()
        threadCache.removeAll()
        accessTimes.removeAll()
        
        cacheStats = CacheStats()
        
        #if DEBUG
        print("💾 CACHE: Cleared all caches")
        #endif
    }
    
    // MARK: - Feed-Specific Caching for Instant Startup
    
    /// Cache entire feed for instant display
    func cacheFeed(_ threads: [ThreadData], userID: String) {
        let feedKey = "feed_\(userID)"
        
        // Cache individual threads
        for thread in threads {
            cacheThread(thread, priority: .high)
            
            // Cache thread videos
            cacheVideo(thread.parentVideo, priority: .high)
            for childVideo in thread.childVideos {
                cacheVideo(childVideo, priority: .normal)
            }
        }
        
        #if DEBUG
        print("💾 CACHE: Cached complete feed with \(threads.count) threads")
        #endif
    }
    
    /// Get cached feed for instant display
    func getCachedFeed(userID: String, limit: Int = 20) -> [ThreadData]? {
        let availableThreads = threadCache.values
            .filter { !isCacheExpired($0.cachedAt) }
            .sorted { $0.thread.parentVideo.createdAt > $1.thread.parentVideo.createdAt }
            .map { $0.thread }
        
        guard availableThreads.count >= min(5, limit / 2) else {
            return nil // Not enough cached content
        }
        
        let resultThreads = Array(availableThreads.prefix(limit))
        
        // Update access times
        for thread in resultThreads {
            accessTimes[thread.id] = Date()
        }
        
        cacheStats.hits += resultThreads.count
        #if DEBUG
        print("💾 CACHE: Feed hit - \(resultThreads.count) cached threads")
        #endif
        return resultThreads
    }
}

// MARK: - Supporting Types

/// Cached video entry
struct CachedVideo {
    let video: CoreVideoMetadata
    let cachedAt: Date
    let priority: CachePriority
    var accessCount: Int
}

/// Cached user entry
struct CachedUser {
    let user: UserProfileData
    let cachedAt: Date
    let priority: CachePriority
    var accessCount: Int
}

/// Cached thread entry
struct CachedThread {
    var thread: ThreadData
    var cachedAt: Date
    let priority: CachePriority
    var accessCount: Int
}

/// Cache priority levels
enum CachePriority {
    case low
    case normal
    case high
    case critical
}

/// Cache statistics
struct CacheStats {
    var totalEntries: Int = 0
    var videoEntries: Int = 0
    var userEntries: Int = 0
    var threadEntries: Int = 0
    var hits: Int = 0
    var misses: Int = 0
    var evictions: Int = 0
    var hitRate: Double = 0.0
    var memoryUsage: Int = 0
    var lastUpdated: Date = Date()
}

// MARK: - Integration Extensions for HomeFeedView

extension CachingService {
    
    /// Check if we have enough cached content for instant feed display
    func hasInstantFeedContent(userID: String, minimumThreads: Int = 5) -> Bool {
        let validThreads = threadCache.values
            .filter { !isCacheExpired($0.cachedAt) }
            .count
        
        return validThreads >= minimumThreads
    }
    
    /// Get instant feed for immediate display (no network calls)
    func getInstantFeed(userID: String, limit: Int = 20) -> [ThreadData] {
        return getCachedFeed(userID: userID, limit: limit) ?? []
    }
    
    /// Update cached feed entry with fresh data
    func updateCachedThread(_ thread: ThreadData) {
        if var existing = threadCache[thread.id] {
            existing.thread = thread
            existing.cachedAt = Date()
            existing.accessCount += 1
            threadCache[thread.id] = existing
            accessTimes[thread.id] = Date()
            
            #if DEBUG
            print("💾 CACHE: Updated thread - \(thread.id)")
            #endif
        } else {
            cacheThread(thread, priority: .normal)
        }
    }
}

// MARK: - Hello World Test Extension

extension CachingService {
    
    /// Test caching functionality
    func helloWorldTest() {
        #if DEBUG
        print("💾 CACHE SERVICE: Hello World - Ready for instant feed loading!")
        #endif
        #if DEBUG
        print("💾 Limits: \(maxVideoEntries) videos, \(maxUserEntries) users, \(maxThreadEntries) threads")
        #endif
        #if DEBUG
        print("💾 Memory: \(formatMemorySize(maxMemorySize)) limit")
        #endif
        #if DEBUG
        print("💾 Expiration: \(Int(cacheExpiration / 60)) minutes")
        #endif
    }
    
    /// Test cache with sample data
    func testCache() {
        // Create test video
        let testVideo = CoreVideoMetadata(
            id: "test_cache_123",
            title: "Test Video",
            videoURL: "https://example.com/test.mp4",
            thumbnailURL: "",
            creatorID: "test_creator",
            creatorName: "TestCreator",
            createdAt: Date(),
            threadID: nil,
            replyToVideoID: nil,
            conversationDepth: 0,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "warm",
            qualityScore: 75,
            engagementRatio: 0.05,
            velocityScore: 0.3,
            trendingScore: 0.2,
            duration: 60,
            aspectRatio: 9.0/16.0,
            fileSize: 1000000,
            discoverabilityScore: 0.6,
            isPromoted: false,
            lastEngagementAt: Date()
        )
        
        // Test caching
        cacheVideo(testVideo, priority: .high)
        
        // Test retrieval
        if let retrieved = getCachedVideo(id: testVideo.id) {
            #if DEBUG
            print("✅ CACHE: Test passed - video retrieved successfully")
            #endif
        } else {
            #if DEBUG
            print("❌ CACHE: Test failed - video not retrieved")
            #endif
        }
        
        // Log performance
        logCachePerformance()
    }
}
