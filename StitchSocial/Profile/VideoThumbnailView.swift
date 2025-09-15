//
//  VideoThumbnailView.swift
//  StitchSocial
//
//  Layer 8: Views - Lightweight Video Thumbnail for Grid Display
//  Dependencies: AsyncThumbnailView, AVFoundation
//  Features: Smart caching, loading states, no video player conflicts
//

import SwiftUI
import AVFoundation

/// Lightweight video thumbnail component for grid display - NO VIDEO PLAYER
struct VideoThumbnailView: View {
    
    // MARK: - Properties
    
    let video: CoreVideoMetadata
    let onTap: () -> Void
    let showEngagementBadge: Bool
    
    // MARK: - State
    
    @State private var thumbnailURL: String?
    @State private var isGeneratingThumbnail = false
    @State private var thumbnailError: String?
    @State private var cachedImage: UIImage?
    
    // MARK: - Cache Manager
    
    @StateObject private var thumbnailCache = ThumbnailCacheManager.shared
    
    // MARK: - Initialization
    
    init(
        video: CoreVideoMetadata,
        showEngagementBadge: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.video = video
        self.showEngagementBadge = showEngagementBadge
        self.onTap = onTap
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .aspectRatio(9.0/16.0, contentMode: .fit)
            
            // Thumbnail content
            Group {
                if let cachedImage = cachedImage {
                    // Cached thumbnail
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else if isGeneratingThumbnail {
                    // Loading state
                    loadingView
                } else if let error = thumbnailError {
                    // Error state
                    errorView(error: error)
                } else {
                    // Try to load thumbnail
                    asyncThumbnailView
                }
            }
            
            // Overlay elements
            ZStack {
                // Engagement badge (top-right)
                if showEngagementBadge {
                    engagementBadge
                }
                
                // Duration badge (bottom-right)
                durationBadge
                
                // Temperature indicator (top-left)
                temperatureIndicator
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    // MARK: - Thumbnail Loading
    
    private var asyncThumbnailView: some View {
        AsyncImage(url: URL(string: video.videoURL)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "play.rectangle")
                        .font(.title2)
                        .foregroundColor(.gray)
                )
        }
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .onAppear {
            // Start background thumbnail generation for better caching
            generateThumbnailIfNeeded()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        ZStack {
            Color.gray.opacity(0.3)
            
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                
                Text("Loading...")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(error: String) -> some View {
        ZStack {
            Color.red.opacity(0.2)
            
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
                
                Text("Error")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Engagement Badge
    
    private var engagementBadge: some View {
        VStack {
            HStack {
                Spacer()
                
                if video.hypeCount > 0 {
                    engagementCounter(
                        count: video.hypeCount,
                        icon: "flame.fill",
                        color: .orange
                    )
                }
            }
            
            Spacer()
        }
        .padding(8)
    }
    
    private func engagementCounter(count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            
            Text(formatCount(count))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }
    
    // MARK: - Duration Badge
    
    private var durationBadge: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                Text(formatDuration(video.duration))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.7))
                    )
            }
        }
        .padding(8)
    }
    
    // MARK: - Temperature Indicator
    
    private var temperatureIndicator: some View {
        VStack {
            HStack {
                if video.temperature != "neutral" && video.temperature != "warm" {
                    temperatureBadge
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .padding(8)
    }
    
    private var temperatureBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(temperatureColor)
            
            Text(video.temperature.capitalized)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(temperatureColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(temperatureColor.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(temperatureColor.opacity(0.6), lineWidth: 0.5)
                )
        )
    }
    
    private var temperatureColor: Color {
        switch video.temperature.lowercased() {
        case "hot", "blazing": return .red
        case "cool": return .blue
        case "cold", "frozen": return .cyan
        default: return .orange
        }
    }
    
    // MARK: - Thumbnail Generation
    
    private func loadThumbnail() {
        // Check cache first
        if let cached = thumbnailCache.getCachedThumbnail(for: video.id) {
            cachedImage = cached
            return
        }
        
        // Generate thumbnail if not cached
        generateThumbnailIfNeeded()
    }
    
    private func generateThumbnailIfNeeded() {
        guard cachedImage == nil && !isGeneratingThumbnail else { return }
        
        isGeneratingThumbnail = true
        
        Task {
            do {
                let thumbnail = try await generateVideoThumbnail(from: video.videoURL)
                
                await MainActor.run {
                    cachedImage = thumbnail
                    isGeneratingThumbnail = false
                    
                    // Cache the generated thumbnail
                    thumbnailCache.cacheThumbnail(thumbnail, for: video.id)
                }
                
            } catch {
                await MainActor.run {
                    thumbnailError = error.localizedDescription
                    isGeneratingThumbnail = false
                }
            }
        }
    }
    
    private func generateVideoThumbnail(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw ThumbnailError.invalidURL
        }
        
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 356) // Optimized thumbnail size
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600) // 1 second in
        
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    let uiImage = UIImage(cgImage: cgImage)
                    continuation.resume(returning: uiImage)
                } else {
                    continuation.resume(throwing: ThumbnailError.generationFailed)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return String(count)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// MARK: - Thumbnail Cache Manager

@MainActor
class ThumbnailCacheManager: ObservableObject {
    static let shared = ThumbnailCacheManager()
    
    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 50 // Maximum thumbnails to cache
    private var accessOrder: [String] = [] // For LRU eviction
    
    private init() {}
    
    func getCachedThumbnail(for videoID: String) -> UIImage? {
        if let image = cache[videoID] {
            // Update access order (move to end)
            if let index = accessOrder.firstIndex(of: videoID) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(videoID)
            
            return image
        }
        return nil
    }
    
    func cacheThumbnail(_ image: UIImage, for videoID: String) {
        // Remove from cache if already exists
        cache.removeValue(forKey: videoID)
        if let index = accessOrder.firstIndex(of: videoID) {
            accessOrder.remove(at: index)
        }
        
        // Add to cache
        cache[videoID] = image
        accessOrder.append(videoID)
        
        // Evict oldest if needed
        while cache.count > maxCacheSize && !accessOrder.isEmpty {
            let oldestID = accessOrder.removeFirst()
            cache.removeValue(forKey: oldestID)
        }
        
        print("THUMBNAIL CACHE: Cached thumbnail for video \(videoID) (\(cache.count)/\(maxCacheSize))")
    }
    
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        print("THUMBNAIL CACHE: Cache cleared")
    }
    
    var cacheStats: String {
        return "Cache: \(cache.count)/\(maxCacheSize) thumbnails"
    }
}

// MARK: - Thumbnail Errors

enum ThumbnailError: LocalizedError {
    case invalidURL
    case generationFailed
    case assetLoadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid video URL"
        case .generationFailed:
            return "Failed to generate thumbnail"
        case .assetLoadFailed:
            return "Failed to load video asset"
        }
    }
}

// MARK: - Preview

struct VideoThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        VideoThumbnailView(
            video: CoreVideoMetadata(
                id: "1",
                title: "Sample Video",
                videoURL: "https://example.com/video.mp4",
                thumbnailURL: "",
                creatorID: "user1",
                creatorName: "Test User",
                createdAt: Date(),
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: 1234,
                hypeCount: 89,
                coolCount: 12,
                replyCount: 23,
                shareCount: 45,
                temperature: "hot",
                qualityScore: 85,
                engagementRatio: 0.88,
                velocityScore: 0.75,
                trendingScore: 0.82,
                duration: 30.0,
                aspectRatio: 9.0/16.0,
                fileSize: 5242880,
                discoverabilityScore: 0.79,
                isPromoted: false,
                lastEngagementAt: Date()
            )
        ) {
            print("Thumbnail tapped")
        }
        .frame(width: 120, height: 213)
        .background(Color.black)
    }
}
