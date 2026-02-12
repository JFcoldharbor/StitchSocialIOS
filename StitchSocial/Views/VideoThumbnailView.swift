//
//  VideoThumbnailView.swift
//  StitchSocial
//
//  Layer 8: Views - Lightweight Video Thumbnail for Grid Display
//
//  CACHING: NSCache replaces Dictionary — auto-evicts on memory pressure,
//           thread-safe without @MainActor, cost-based limit (~50MB).
//           Generated thumbnails sized at 200x356 to keep memory per entry low.
//
//  THUMBNAIL PRIORITY: thumbnailURL (Firebase) → NSCache → AVAssetImageGenerator fallback
//  CLIPPING FIX: Badges use .overlay(alignment:) AFTER .clipped() so they never get cut.
//

import SwiftUI
import AVFoundation

struct VideoThumbnailView: View {
    
    let video: CoreVideoMetadata
    let onTap: () -> Void
    let showEngagementBadge: Bool
    
    @State private var isGeneratingThumbnail = false
    @State private var thumbnailError: String?
    @State private var cachedImage: UIImage?
    
    init(video: CoreVideoMetadata, showEngagementBadge: Bool = true, onTap: @escaping () -> Void) {
        self.video = video
        self.showEngagementBadge = showEngagementBadge
        self.onTap = onTap
    }
    
    // MARK: - Body
    
    var body: some View {
        Color.black
            .overlay(thumbnailContent)
            .aspectRatio(9.0/16.0, contentMode: .fill)
            .clipped()
            // Badges AFTER clipped — they sit on top, never cut
            .overlay(alignment: .topTrailing) {
                if showEngagementBadge, video.hypeCount > 0 {
                    engagementBadge.padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                durationBadge.padding(4)
            }
            .overlay(alignment: .topLeading) {
                if video.temperature != "neutral" && video.temperature != "warm" {
                    temperatureBadge.padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onAppear { loadThumbnail() }
    }
    
    // MARK: - Thumbnail Content
    
    @ViewBuilder
    private var thumbnailContent: some View {
        if let cachedImage = cachedImage {
            Image(uiImage: cachedImage)
                .resizable()
                .scaledToFill()
        } else if isGeneratingThumbnail {
            shimmerView
        } else {
            placeholderView.onAppear { generateThumbnailIfNeeded() }
        }
    }
    
    // MARK: - Placeholders
    
    private var placeholderView: some View {
        Color.gray.opacity(0.15)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray.opacity(0.4))
            )
    }
    
    private var shimmerView: some View {
        Color.gray.opacity(0.15)
            .overlay(ProgressView().scaleEffect(0.7).tint(.gray))
    }
    
    // MARK: - Badges
    
    private var engagementBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
            Text(formatCount(video.hypeCount))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
    }
    
    private var durationBadge: some View {
        Text(formatDuration(video.duration))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7)))
    }
    
    private var temperatureBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "thermometer")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(temperatureColor)
            Text(video.temperature.capitalized)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(temperatureColor)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(temperatureColor.opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(temperatureColor.opacity(0.6), lineWidth: 0.5))
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
    
    // MARK: - Thumbnail Loading
    
    private func loadThumbnail() {
        if let cached = ThumbnailCache.shared.get(video.id) {
            cachedImage = cached
            return
        }
        
        // Fetch from thumbnailURL into NSCache — replaces AsyncImage (which has no cache)
        if !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) {
            Task.detached(priority: .utility) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        ThumbnailCache.shared.set(image, for: video.id)
                        await MainActor.run { cachedImage = image }
                    }
                } catch {
                    // URL fetch failed — fall back to AVAssetImageGenerator
                    await MainActor.run { generateThumbnailIfNeeded() }
                }
            }
            return
        }
        
        // No thumbnailURL — generate from video file
        generateThumbnailIfNeeded()
    }
    
    private func generateThumbnailIfNeeded() {
        guard cachedImage == nil, !isGeneratingThumbnail else { return }
        isGeneratingThumbnail = true
        
        Task.detached(priority: .utility) {
            do {
                guard let url = URL(string: video.videoURL) else {
                    throw ThumbnailError.invalidURL
                }
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 200, height: 356)
                
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                let cgImage = try await generator.image(at: time).image
                let image = UIImage(cgImage: cgImage)
                
                ThumbnailCache.shared.set(image, for: video.id)
                
                await MainActor.run {
                    cachedImage = image
                    isGeneratingThumbnail = false
                }
            } catch {
                await MainActor.run {
                    thumbnailError = error.localizedDescription
                    isGeneratingThumbnail = false
                }
            }
        }
    }
    
    // MARK: - Formatting
    
    private func formatCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fK", Double(count) / 1000) : String(count)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60, s = Int(duration) % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "0:%02d", s)
    }
}

// MARK: - NSCache Thumbnail Cache
//
// WHY NSCache over Dictionary:
// - Auto-evicts on memory warnings (Dictionary holds strong refs until manually cleared)
// - Thread-safe without actors (Dictionary needs @MainActor or locks)
// - Cost-based eviction tracks actual image bytes, not just count
// - No need for manual LRU tracking
//

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50MB
    }
    
    func get(_ videoID: String) -> UIImage? {
        cache.object(forKey: videoID as NSString)
    }
    
    func set(_ image: UIImage, for videoID: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: videoID as NSString, cost: cost)
    }
    
    func remove(_ videoID: String) {
        cache.removeObject(forKey: videoID as NSString)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Errors

enum ThumbnailError: LocalizedError {
    case invalidURL, generationFailed, assetLoadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid video URL"
        case .generationFailed: return "Failed to generate thumbnail"
        case .assetLoadFailed: return "Failed to load video asset"
        }
    }
}
