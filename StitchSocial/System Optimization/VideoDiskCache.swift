//
//  VideoDiskCache.swift
//  StitchSocial
//
//  Layer 4: Core Services - Disk-Based Video File Cache
//  Dependencies: Foundation
//  Features: Downloads and caches actual video MP4 files to disk,
//            LRU eviction, size-capped storage, memory pressure cleanup
//
//  This solves the #1 performance issue: every video swipe was re-downloading
//  the full MP4 from Firebase Storage. Now videos are cached locally after
//  first play and served from disk on repeat views.
//

import Foundation

/// Disk-based cache for actual video file data (MP4s)
/// Prevents re-downloading videos from Firebase on every view
class VideoDiskCache {
    
    // MARK: - Singleton
    
    static let shared = VideoDiskCache()
    
    // MARK: - Configuration
    
    /// Max disk cache size: 500MB
    private let maxCacheSize: Int64 = 500 * 1024 * 1024
    
    /// Max age before auto-eviction: 7 days
    private let maxCacheAge: TimeInterval = 7 * 24 * 3600
    
    /// Max concurrent downloads
    private let maxConcurrentDownloads = 3
    
    // MARK: - State (protected by serial queue)
    
    /// Serial queue for thread-safe access to cache state
    private let queue = DispatchQueue(label: "com.stitchsocial.videodiskcache")
    
    /// Maps remote URL string -> local cached file URL
    private var cacheIndex: [String: CacheEntry] = [:]
    
    /// Currently downloading URLs
    private var activeDownloads: Set<String> = []
    
    /// Total cached bytes on disk
    private var totalCachedBytes: Int64 = 0
    
    // MARK: - Directory
    
    private let cacheDirectory: URL
    
    // MARK: - Init
    
    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("VideoFileCache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Load existing cache index from disk
        Task { await rebuildIndex() }
    }
    
    // MARK: - Public API
    
    /// Get local cached URL for a remote video URL, or nil if not cached
    /// Synchronous - safe to call from any context
    func getCachedURL(for remoteURL: String) -> URL? {
        queue.sync {
            guard let entry = cacheIndex[remoteURL] else { return nil }
            
            // Check expiration
            if Date().timeIntervalSince(entry.cachedAt) > maxCacheAge {
                _removeCacheEntry(for: remoteURL)
                return nil
            }
            
            // Verify file still exists
            guard FileManager.default.fileExists(atPath: entry.localURL.path) else {
                cacheIndex.removeValue(forKey: remoteURL)
                return nil
            }
            
            // Update access time for LRU
            cacheIndex[remoteURL]?.lastAccessedAt = Date()
            
            print("💾 VIDEO CACHE: Hit for \(remoteURL.suffix(20))")
            return entry.localURL
        }
    }
    
    /// Download and cache a video file in the background
    func cacheVideo(from remoteURLString: String) async {
        // Check state synchronously
        let shouldDownload: Bool = queue.sync {
            guard cacheIndex[remoteURLString] == nil,
                  !activeDownloads.contains(remoteURLString),
                  activeDownloads.count < maxConcurrentDownloads else { return false }
            activeDownloads.insert(remoteURLString)
            return true
        }
        
        guard shouldDownload, let remoteURL = URL(string: remoteURLString) else { return }
        
        defer {
            queue.sync { activeDownloads.remove(remoteURLString) }
        }
        
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            
            let filename = UUID().uuidString + ".mp4"
            let localURL = cacheDirectory.appendingPathComponent(filename)
            
            queue.sync {
                // Evict if needed
                while totalCachedBytes + fileSize > maxCacheSize && !cacheIndex.isEmpty {
                    _evictLeastRecentlyUsed()
                }
            }
            
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            
            queue.sync {
                let entry = CacheEntry(
                    remoteURL: remoteURLString,
                    localURL: localURL,
                    fileSize: fileSize,
                    cachedAt: Date(),
                    lastAccessedAt: Date()
                )
                cacheIndex[remoteURLString] = entry
                totalCachedBytes += fileSize
            }
            
            print("💾 VIDEO CACHE: Cached \(formatBytes(fileSize)) for \(remoteURLString.suffix(20))")
            
        } catch {
            print("⚠️ VIDEO CACHE: Download failed for \(remoteURLString.suffix(20)): \(error.localizedDescription)")
        }
    }
    
    /// Prefetch multiple videos
    func prefetchVideos(_ remoteURLs: [String]) async {
        for url in remoteURLs {
            let isCached = queue.sync { cacheIndex[url] != nil }
            guard !isCached else { continue }
            await cacheVideo(from: url)
        }
    }
    
    /// Clear entire cache
    func clearAll() {
        queue.sync {
            for (_, entry) in cacheIndex {
                try? FileManager.default.removeItem(at: entry.localURL)
            }
            cacheIndex.removeAll()
            totalCachedBytes = 0
        }
        print("🗑️ VIDEO CACHE: Cleared all cached videos")
    }
    
    /// Remove expired entries
    func cleanupExpired() {
        queue.sync {
            let now = Date()
            let expired = cacheIndex.filter { now.timeIntervalSince($0.value.cachedAt) > maxCacheAge }
            
            for (key, entry) in expired {
                try? FileManager.default.removeItem(at: entry.localURL)
                totalCachedBytes -= entry.fileSize
                cacheIndex.removeValue(forKey: key)
            }
            
            if !expired.isEmpty {
                print("🧹 VIDEO CACHE: Cleaned \(expired.count) expired entries")
            }
        }
    }
    
    /// Emergency cleanup - keeps only most recently accessed videos
    func emergencyCleanup(keepCount: Int = 5) {
        queue.sync {
            let sorted = cacheIndex.sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
            let toRemove = sorted.dropFirst(keepCount)
            
            for (key, entry) in toRemove {
                try? FileManager.default.removeItem(at: entry.localURL)
                totalCachedBytes -= entry.fileSize
                cacheIndex.removeValue(forKey: key)
            }
            
            print("🔴 VIDEO CACHE: Emergency cleanup - kept \(keepCount), removed \(toRemove.count)")
        }
    }
    
    // MARK: - Stats
    
    var stats: VideoCacheStats {
        VideoCacheStats(
            totalFiles: cacheIndex.count,
            totalBytes: totalCachedBytes,
            maxBytes: maxCacheSize,
            activeDownloads: activeDownloads.count
        )
    }
    
    // MARK: - Private
    
    // MARK: - Private (must be called inside queue.sync)
    
    private func _evictLeastRecentlyUsed() {
        guard let (key, _) = cacheIndex.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt }) else { return }
        _removeCacheEntry(for: key)
    }
    
    private func _removeCacheEntry(for key: String) {
        guard let entry = cacheIndex.removeValue(forKey: key) else { return }
        try? FileManager.default.removeItem(at: entry.localURL)
        totalCachedBytes -= entry.fileSize
        print("💾 VIDEO CACHE: Evicted \(formatBytes(entry.fileSize)) - \(key.suffix(20))")
    }
    
    /// Rebuild cache index from files on disk (app relaunch)
    private func rebuildIndex() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else { return }
        
        totalCachedBytes = 0
        
        for file in files {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) else { continue }
            let size = attrs[.size] as? Int64 ?? 0
            let created = attrs[.creationDate] as? Date ?? Date()
            
            // We can't map back to remote URLs from filename alone on relaunch
            // So we just track total size and remove old files
            if Date().timeIntervalSince(created) > maxCacheAge {
                try? FileManager.default.removeItem(at: file)
            } else {
                totalCachedBytes += size
            }
        }
        
        print("💾 VIDEO CACHE: Rebuilt index - \(formatBytes(totalCachedBytes)) on disk")
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes > 1024 * 1024 {
            return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
        } else if bytes > 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        }
        return "\(bytes)B"
    }
}

// MARK: - Supporting Types

struct CacheEntry {
    let remoteURL: String
    let localURL: URL
    let fileSize: Int64
    let cachedAt: Date
    var lastAccessedAt: Date
}

struct VideoCacheStats {
    let totalFiles: Int
    let totalBytes: Int64
    let maxBytes: Int64
    let activeDownloads: Int
    
    var usagePercent: Double {
        guard maxBytes > 0 else { return 0 }
        return Double(totalBytes) / Double(maxBytes) * 100.0
    }
}
