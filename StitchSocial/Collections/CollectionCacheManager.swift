//
//  CollectionCacheManager.swift
//  StitchSocial
//
//  Layer 4: Core Services - Collection Caching & Offline Support
//  Dependencies: Foundation, FileManager, CoreVideoMetadata, VideoCollection
//  Features: Video caching, metadata storage, progress persistence, offline playback, cache eviction
//  CREATED: Phase 7 - Collections feature Polish
//

import Foundation
import UIKit
import Combine

/// Manages caching for collections including video files, thumbnails, and metadata
/// Enables offline playback and reduces network usage
@MainActor
class CollectionCacheManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CollectionCacheManager()
    
    // MARK: - Configuration
    
    /// Maximum cache size in bytes (500 MB default)
    var maxCacheSize: Int64 = 500 * 1024 * 1024
    
    /// Maximum age for cached items (7 days)
    var maxCacheAge: TimeInterval = 7 * 24 * 60 * 60
    
    /// Whether to cache videos on WiFi only
    var cacheOnWiFiOnly: Bool = false
    
    // MARK: - Published State
    
    /// Current cache size in bytes
    @Published private(set) var currentCacheSize: Int64 = 0
    
    /// Number of cached collections
    @Published private(set) var cachedCollectionCount: Int = 0
    
    /// Number of cached videos
    @Published private(set) var cachedVideoCount: Int = 0
    
    /// Cache is being cleaned
    @Published private(set) var isCleaningCache: Bool = false
    
    /// Download progress for active downloads
    @Published private(set) var downloadProgress: [String: Double] = [:]
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    
    private var cacheDirectory: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("CollectionCache", isDirectory: true)
    }
    
    private var videoCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("videos", isDirectory: true)
    }
    
    private var thumbnailCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }
    
    private var metadataCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("metadata", isDirectory: true)
    }
    
    private var progressCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("progress", isDirectory: true)
    }
    
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Keys
    
    private let cachedCollectionsKey = "cached_collection_ids"
    private let cacheManifestKey = "collection_cache_manifest"
    
    // MARK: - Initialization
    
    private init() {
        setupCacheDirectories()
        loadCacheManifest()
        
        // Monitor for low disk space
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLowDiskSpace),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Periodic cache cleanup
        Task {
            await performPeriodicCleanup()
        }
        
        print("💾 CACHE MANAGER: Initialized with \(formatBytes(currentCacheSize)) cached")
    }
    
    // MARK: - Setup
    
    private func setupCacheDirectories() {
        let directories = [
            cacheDirectory,
            videoCacheDirectory,
            thumbnailCacheDirectory,
            metadataCacheDirectory,
            progressCacheDirectory
        ]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Collection Caching
    
    /// Cache a collection for offline playback
    func cacheCollection(
        _ collection: VideoCollection,
        segments: [CoreVideoMetadata],
        priority: CollectionCachePriority = .normal
    ) async throws {
        print("📥 CACHE MANAGER: Caching collection \(collection.id)")
        
        // Check available space
        guard await hasSpaceForCollection(segments: segments) else {
            throw CacheError.insufficientSpace
        }
        
        // Cache metadata first
        try await cacheCollectionMetadata(collection, segments: segments)
        
        // Cache thumbnails (fast)
        for segment in segments {
            try? await cacheThumbnail(for: segment)
        }
        
        // Cache videos (slow, in background)
        for (index, segment) in segments.enumerated() {
            let segmentPriority: CollectionCachePriority = index == 0 ? .high : priority
            try await cacheVideo(for: segment, priority: segmentPriority)
        }
        
        // Update manifest
        addToCacheManifest(collectionID: collection.id)
        
        print("✅ CACHE MANAGER: Cached collection \(collection.id) with \(segments.count) segments")
    }
    
    /// Cache only metadata and thumbnails (lightweight)
    func cacheCollectionPreview(
        _ collection: VideoCollection,
        segments: [CoreVideoMetadata]
    ) async throws {
        try await cacheCollectionMetadata(collection, segments: segments)
        
        for segment in segments {
            try? await cacheThumbnail(for: segment)
        }
    }
    
    /// Remove a collection from cache
    func uncacheCollection(_ collectionID: String) async {
        print("🗑️ CACHE MANAGER: Removing collection \(collectionID) from cache")
        
        // Load metadata to get segment IDs
        if let metadata = loadCollectionMetadata(collectionID: collectionID) {
            for segmentID in metadata.segmentIDs {
                removeVideo(segmentID: segmentID)
                removeThumbnail(segmentID: segmentID)
            }
        }
        
        // Remove metadata
        removeCollectionMetadata(collectionID: collectionID)
        
        // Update manifest
        removeFromCacheManifest(collectionID: collectionID)
        
        await updateCacheSize()
    }
    
    // MARK: - Video Caching
    
    /// Cache a video segment
    func cacheVideo(for segment: CoreVideoMetadata, priority: CollectionCachePriority = .normal) async throws {
        let cacheURL = videoCacheURL(for: segment.id)
        
        // Skip if already cached
        if fileManager.fileExists(atPath: cacheURL.path) {
            print("⏭️ CACHE MANAGER: Video \(segment.id) already cached")
            return
        }
        
        guard let videoURL = URL(string: segment.videoURL) else {
            throw CacheError.invalidURL
        }
        
        print("📥 CACHE MANAGER: Downloading video \(segment.id)")
        
        // Download video
        let (tempURL, _) = try await URLSession.shared.download(from: videoURL, delegate: DownloadDelegate(
            segmentID: segment.id,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[segment.id] = progress
                }
            }
        ))
        
        // Move to cache
        try fileManager.moveItem(at: tempURL, to: cacheURL)
        
        // Update progress
        downloadProgress.removeValue(forKey: segment.id)
        
        // Update cache size
        await updateCacheSize()
        
        print("✅ CACHE MANAGER: Cached video \(segment.id)")
    }
    
    /// Get cached video URL if available
    func getCachedVideoURL(segmentID: String) -> URL? {
        let cacheURL = videoCacheURL(for: segmentID)
        
        if fileManager.fileExists(atPath: cacheURL.path) {
            // Update access time
            touchFile(at: cacheURL)
            return cacheURL
        }
        
        return nil
    }
    
    /// Check if video is cached
    func isVideoCached(segmentID: String) -> Bool {
        let cacheURL = videoCacheURL(for: segmentID)
        return fileManager.fileExists(atPath: cacheURL.path)
    }
    
    /// Remove cached video
    func removeVideo(segmentID: String) {
        let cacheURL = videoCacheURL(for: segmentID)
        try? fileManager.removeItem(at: cacheURL)
    }
    
    private func videoCacheURL(for segmentID: String) -> URL {
        videoCacheDirectory.appendingPathComponent("\(segmentID).mp4")
    }
    
    // MARK: - Thumbnail Caching
    
    /// Cache thumbnail for a segment
    func cacheThumbnail(for segment: CoreVideoMetadata) async throws {
        let cacheURL = thumbnailCacheURL(for: segment.id)
        
        // Skip if already cached
        if fileManager.fileExists(atPath: cacheURL.path) {
            return
        }
        
        guard let thumbnailURL = URL(string: segment.thumbnailURL) else {
            return
        }
        
        let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
        try data.write(to: cacheURL)
    }
    
    /// Get cached thumbnail URL
    func getCachedThumbnailURL(segmentID: String) -> URL? {
        let cacheURL = thumbnailCacheURL(for: segmentID)
        
        if fileManager.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }
        
        return nil
    }
    
    /// Remove cached thumbnail
    func removeThumbnail(segmentID: String) {
        let cacheURL = thumbnailCacheURL(for: segmentID)
        try? fileManager.removeItem(at: cacheURL)
    }
    
    private func thumbnailCacheURL(for segmentID: String) -> URL {
        thumbnailCacheDirectory.appendingPathComponent("\(segmentID).jpg")
    }
    
    // MARK: - Metadata Caching
    
    /// Cache collection metadata
    func cacheCollectionMetadata(_ collection: VideoCollection, segments: [CoreVideoMetadata]) async throws {
        let metadata = CachedCollectionMetadata(
            collection: collection,
            segmentIDs: segments.map { $0.id },
            cachedAt: Date()
        )
        
        let cacheURL = metadataCacheURL(for: collection.id)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: cacheURL)
        
        // Cache segment metadata
        for segment in segments {
            try await cacheSegmentMetadata(segment)
        }
    }
    
    /// Load cached collection metadata
    func loadCollectionMetadata(collectionID: String) -> CachedCollectionMetadata? {
        let cacheURL = metadataCacheURL(for: collectionID)
        
        guard let data = try? Data(contentsOf: cacheURL),
              let metadata = try? JSONDecoder().decode(CachedCollectionMetadata.self, from: data) else {
            return nil
        }
        
        return metadata
    }
    
    /// Cache segment metadata
    func cacheSegmentMetadata(_ segment: CoreVideoMetadata) async throws {
        let cacheURL = segmentMetadataCacheURL(for: segment.id)
        let data = try JSONEncoder().encode(segment)
        try data.write(to: cacheURL)
    }
    
    /// Load cached segment metadata
    func loadSegmentMetadata(segmentID: String) -> CoreVideoMetadata? {
        let cacheURL = segmentMetadataCacheURL(for: segmentID)
        
        guard let data = try? Data(contentsOf: cacheURL),
              let segment = try? JSONDecoder().decode(CoreVideoMetadata.self, from: data) else {
            return nil
        }
        
        return segment
    }
    
    /// Remove collection metadata
    func removeCollectionMetadata(collectionID: String) {
        let cacheURL = metadataCacheURL(for: collectionID)
        try? fileManager.removeItem(at: cacheURL)
    }
    
    private func metadataCacheURL(for collectionID: String) -> URL {
        metadataCacheDirectory.appendingPathComponent("\(collectionID).json")
    }
    
    private func segmentMetadataCacheURL(for segmentID: String) -> URL {
        metadataCacheDirectory.appendingPathComponent("segment_\(segmentID).json")
    }
    
    // MARK: - Progress Caching
    
    /// Save watch progress locally
    func saveProgress(_ progress: CollectionProgress) {
        let cacheURL = progressCacheURL(for: progress.collectionID, userID: progress.userID)
        
        if let data = try? JSONEncoder().encode(progress) {
            try? data.write(to: cacheURL)
        }
    }
    
    /// Load cached watch progress
    func loadProgress(collectionID: String, userID: String) -> CollectionProgress? {
        let cacheURL = progressCacheURL(for: collectionID, userID: userID)
        
        guard let data = try? Data(contentsOf: cacheURL),
              let progress = try? JSONDecoder().decode(CollectionProgress.self, from: data) else {
            return nil
        }
        
        return progress
    }
    
    /// Remove progress cache
    func removeProgress(collectionID: String, userID: String) {
        let cacheURL = progressCacheURL(for: collectionID, userID: userID)
        try? fileManager.removeItem(at: cacheURL)
    }
    
    private func progressCacheURL(for collectionID: String, userID: String) -> URL {
        progressCacheDirectory.appendingPathComponent("\(userID)_\(collectionID).json")
    }
    
    // MARK: - Cache Manifest
    
    private func loadCacheManifest() {
        if let ids = userDefaults.array(forKey: cachedCollectionsKey) as? [String] {
            cachedCollectionCount = ids.count
        }
        
        Task {
            await updateCacheSize()
        }
    }
    
    private func addToCacheManifest(collectionID: String) {
        var ids = userDefaults.array(forKey: cachedCollectionsKey) as? [String] ?? []
        if !ids.contains(collectionID) {
            ids.append(collectionID)
            userDefaults.set(ids, forKey: cachedCollectionsKey)
            cachedCollectionCount = ids.count
        }
    }
    
    private func removeFromCacheManifest(collectionID: String) {
        var ids = userDefaults.array(forKey: cachedCollectionsKey) as? [String] ?? []
        ids.removeAll { $0 == collectionID }
        userDefaults.set(ids, forKey: cachedCollectionsKey)
        cachedCollectionCount = ids.count
    }
    
    /// Get all cached collection IDs
    func getCachedCollectionIDs() -> [String] {
        return userDefaults.array(forKey: cachedCollectionsKey) as? [String] ?? []
    }
    
    // MARK: - Cache Management
    
    /// Update current cache size
    func updateCacheSize() async {
        let size = calculateDirectorySize(cacheDirectory)
        currentCacheSize = size
        
        // Count cached videos
        if let contents = try? fileManager.contentsOfDirectory(atPath: videoCacheDirectory.path) {
            cachedVideoCount = contents.filter { $0.hasSuffix(".mp4") }.count
        }
    }
    
    /// Check if there's space for a collection
    func hasSpaceForCollection(segments: [CoreVideoMetadata]) async -> Bool {
        let estimatedSize = segments.reduce(0) { $0 + $1.fileSize }
        let availableSpace = maxCacheSize - currentCacheSize
        
        if estimatedSize > availableSpace {
            // Try to make space
            await evictOldItems(neededSpace: estimatedSize - availableSpace)
            return (maxCacheSize - currentCacheSize) >= estimatedSize
        }
        
        return true
    }
    
    /// Clear entire cache
    func clearCache() async {
        isCleaningCache = true
        
        try? fileManager.removeItem(at: cacheDirectory)
        setupCacheDirectories()
        
        userDefaults.removeObject(forKey: cachedCollectionsKey)
        
        currentCacheSize = 0
        cachedCollectionCount = 0
        cachedVideoCount = 0
        
        isCleaningCache = false
        
        print("🧹 CACHE MANAGER: Cache cleared")
    }
    
    /// Clear old cached items
    func clearOldCache() async {
        isCleaningCache = true
        
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        await evictItemsOlderThan(cutoffDate)
        
        isCleaningCache = false
    }
    
    /// Evict items to free up space
    private func evictOldItems(neededSpace: Int64) async {
        print("🧹 CACHE MANAGER: Evicting items to free \(formatBytes(neededSpace))")
        
        // Get all cached videos with modification dates
        guard let contents = try? fileManager.contentsOfDirectory(
            at: videoCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }
        
        // Sort by access date (oldest first)
        let sortedItems = contents.compactMap { url -> (URL, Date, Int64)? in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modDate = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int64 else {
                return nil
            }
            return (url, modDate, size)
        }.sorted { $0.1 < $1.1 }
        
        var freedSpace: Int64 = 0
        
        for (url, _, size) in sortedItems {
            if freedSpace >= neededSpace {
                break
            }
            
            try? fileManager.removeItem(at: url)
            freedSpace += size
            
            // Also remove associated thumbnail and metadata
            let segmentID = url.deletingPathExtension().lastPathComponent
            removeThumbnail(segmentID: segmentID)
        }
        
        await updateCacheSize()
        
        print("🧹 CACHE MANAGER: Freed \(formatBytes(freedSpace))")
    }
    
    /// Evict items older than a date
    private func evictItemsOlderThan(_ date: Date) async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: videoCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        
        for url in contents {
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let modDate = attributes[.modificationDate] as? Date,
               modDate < date {
                try? fileManager.removeItem(at: url)
                
                let segmentID = url.deletingPathExtension().lastPathComponent
                removeThumbnail(segmentID: segmentID)
            }
        }
        
        await updateCacheSize()
    }
    
    private func performPeriodicCleanup() async {
        // Run cleanup every hour
        while true {
            try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            
            // Check if over max size
            if currentCacheSize > maxCacheSize {
                let overage = currentCacheSize - maxCacheSize
                await evictOldItems(neededSpace: overage)
            }
            
            // Clear expired items
            await clearOldCache()
        }
    }
    
    // MARK: - Helpers
    
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var size: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                size += fileSize
            }
        }
        
        return size
    }
    
    private func touchFile(at url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    @objc private func handleLowDiskSpace() {
        Task {
            // Aggressive cleanup
            await evictOldItems(neededSpace: maxCacheSize / 2)
        }
    }
    
    // MARK: - Formatted Properties
    
    /// Formatted cache size string
    var formattedCacheSize: String {
        formatBytes(currentCacheSize)
    }
    
    /// Formatted max cache size
    var formattedMaxCacheSize: String {
        formatBytes(maxCacheSize)
    }
    
    /// Cache usage percentage
    var cacheUsagePercentage: Double {
        guard maxCacheSize > 0 else { return 0 }
        return Double(currentCacheSize) / Double(maxCacheSize)
    }
}

// MARK: - Supporting Types

/// Cache priority for downloads
enum CollectionCachePriority {
    case low
    case normal
    case high
}

/// Cached collection metadata
struct CachedCollectionMetadata: Codable {
    let collection: VideoCollection
    let segmentIDs: [String]
    let cachedAt: Date
    
    var age: TimeInterval {
        Date().timeIntervalSince(cachedAt)
    }
}

/// Cache errors
enum CacheError: LocalizedError {
    case insufficientSpace
    case invalidURL
    case downloadFailed
    case encodingFailed
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .insufficientSpace:
            return "Not enough storage space to cache this collection"
        case .invalidURL:
            return "Invalid video URL"
        case .downloadFailed:
            return "Failed to download video"
        case .encodingFailed:
            return "Failed to encode metadata"
        case .fileNotFound:
            return "Cached file not found"
        }
    }
}

// MARK: - Download Delegate

/// Tracks download progress
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let segmentID: String
    let onProgress: (Double) -> Void
    
    init(segmentID: String, onProgress: @escaping (Double) -> Void) {
        self.segmentID = segmentID
        self.onProgress = onProgress
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled in main code
    }
}

// MARK: - Offline Status

/// Tracks offline availability for a collection
struct CollectionOfflineStatus {
    let collectionID: String
    let isFullyCached: Bool
    let cachedSegmentCount: Int
    let totalSegmentCount: Int
    let cacheSize: Int64
    let cachedAt: Date?
    
    var cacheProgress: Double {
        guard totalSegmentCount > 0 else { return 0 }
        return Double(cachedSegmentCount) / Double(totalSegmentCount)
    }
    
    var isPartialCache: Bool {
        return cachedSegmentCount > 0 && cachedSegmentCount < totalSegmentCount
    }
    
    var statusText: String {
        if isFullyCached {
            return "Available offline"
        } else if isPartialCache {
            return "\(cachedSegmentCount)/\(totalSegmentCount) segments cached"
        } else {
            return "Not cached"
        }
    }
}

// MARK: - Cache Manager Extension

extension CollectionCacheManager {
    
    /// Get offline status for a collection
    func getOfflineStatus(collectionID: String, totalSegments: Int) -> CollectionOfflineStatus {
        let metadata = loadCollectionMetadata(collectionID: collectionID)
        
        var cachedCount = 0
        var totalSize: Int64 = 0
        
        if let segmentIDs = metadata?.segmentIDs {
            for segmentID in segmentIDs {
                if isVideoCached(segmentID: segmentID) {
                    cachedCount += 1
                    
                    if let attributes = try? fileManager.attributesOfItem(
                        atPath: videoCacheURL(for: segmentID).path
                    ) {
                        totalSize += attributes[.size] as? Int64 ?? 0
                    }
                }
            }
        }
        
        return CollectionOfflineStatus(
            collectionID: collectionID,
            isFullyCached: cachedCount == totalSegments && totalSegments > 0,
            cachedSegmentCount: cachedCount,
            totalSegmentCount: totalSegments,
            cacheSize: totalSize,
            cachedAt: metadata?.cachedAt
        )
    }
}
