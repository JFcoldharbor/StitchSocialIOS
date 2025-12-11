//
//  CollectionRowViewModel.swift
//  StitchSocial
//
//  Layer 3: ViewModels - Collection Row Display Logic
//  Dependencies: CollectionService, VideoCollection, CoreVideoMetadata
//  Features: Collection card display, segment preview loading, engagement formatting
//  CREATED: Phase 3 - Collections feature ViewModels
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for displaying a single collection card/row in feeds and profile grids
/// Handles loading segment previews, formatting display data, and navigation state
@MainActor
class CollectionRowViewModel: ObservableObject, Identifiable {
    
    // MARK: - Identity
    
    let id: String
    
    // MARK: - Dependencies
    
    private let collectionService: CollectionService
    
    // MARK: - Published State
    
    /// The collection being displayed
    @Published private(set) var collection: VideoCollection
    
    /// First few segment thumbnails for preview strip
    @Published private(set) var segmentPreviews: [SegmentPreview] = []
    
    /// Loading state for segment previews
    @Published private(set) var isLoadingPreviews: Bool = false
    
    /// Error state
    @Published private(set) var error: String?
    
    /// Whether this collection is bookmarked by current user
    @Published var isBookmarked: Bool = false
    
    // MARK: - Configuration
    
    /// Maximum number of segment previews to show
    private let maxPreviewCount: Int = 4
    
    // MARK: - Initialization
    
    init(collection: VideoCollection, collectionService: CollectionService) {
        self.id = collection.id
        self.collection = collection
        self.collectionService = collectionService
    }
    
    /// Convenience initializer with default service
    convenience init(collection: VideoCollection) {
        self.init(collection: collection, collectionService: CollectionService())
    }
    
    // MARK: - Display Properties
    
    /// Collection title
    var title: String {
        collection.title
    }
    
    /// Creator name with @ prefix
    var creatorDisplayName: String {
        "@\(collection.creatorName)"
    }
    
    /// Cover image URL (uses first segment thumbnail if no cover)
    var coverImageURL: String? {
        collection.coverImageURL ?? segmentPreviews.first?.thumbnailURL
    }
    
    /// Formatted segment count (e.g., "5 parts")
    var segmentCountText: String {
        let count = collection.segmentCount
        return count == 1 ? "1 part" : "\(count) parts"
    }
    
    /// Formatted total duration (e.g., "12:34" or "1:02:34")
    var durationText: String {
        collection.formattedTotalDuration
    }
    
    /// Summary text combining segment count and duration
    var summaryText: String {
        "\(segmentCountText) • \(durationText)"
    }
    
    /// Formatted view count (e.g., "1.2K views")
    var viewCountText: String {
        formatCount(collection.totalViews) + " views"
    }
    
    /// Formatted hype count
    var hypeCountText: String {
        formatCount(collection.totalHypes)
    }
    
    /// Formatted cool count
    var coolCountText: String {
        formatCount(collection.totalCools)
    }
    
    /// Net score (hypes - cools)
    var netScore: Int {
        collection.netScore
    }
    
    /// Net score formatted with sign
    var netScoreText: String {
        let score = netScore
        if score > 0 {
            return "+\(formatCount(score))"
        } else if score < 0 {
            return formatCount(score)
        } else {
            return "0"
        }
    }
    
    /// Color for net score display
    var netScoreColor: Color {
        if netScore > 0 {
            return .green
        } else if netScore < 0 {
            return .red
        } else {
            return .secondary
        }
    }
    
    /// Total engagement count
    var totalEngagementText: String {
        formatCount(collection.totalEngagement) + " interactions"
    }
    
    /// Reply count text
    var replyCountText: String {
        let count = collection.totalReplies
        return count == 1 ? "1 reply" : "\(formatCount(count)) replies"
    }
    
    /// Relative time since publication (e.g., "2 days ago")
    var timeAgoText: String {
        guard let publishedAt = collection.publishedAt else {
            return "Draft"
        }
        return formatTimeAgo(from: publishedAt)
    }
    
    /// Whether collection is published
    var isPublished: Bool {
        collection.isPublished
    }
    
    /// Whether collection is a draft
    var isDraft: Bool {
        collection.isDraft
    }
    
    /// Status badge text
    var statusBadgeText: String? {
        switch collection.status {
        case .draft:
            return "Draft"
        case .processing:
            return "Processing"
        case .archived:
            return "Archived"
        case .published, .deleted:
            return nil
        }
    }
    
    /// Status badge color
    var statusBadgeColor: Color {
        switch collection.status {
        case .draft:
            return .orange
        case .processing:
            return .blue
        case .archived:
            return .gray
        case .published:
            return .green
        case .deleted:
            return .red
        }
    }
    
    /// Visibility icon name
    var visibilityIconName: String {
        collection.visibility.iconName
    }
    
    /// Whether replies are allowed
    var allowsReplies: Bool {
        collection.allowReplies
    }
    
    // MARK: - Segment Preview Strip
    
    /// Number of additional segments not shown in preview
    var additionalSegmentCount: Int {
        max(0, collection.segmentCount - maxPreviewCount)
    }
    
    /// Text for additional segments (e.g., "+3 more")
    var additionalSegmentsText: String? {
        let additional = additionalSegmentCount
        return additional > 0 ? "+\(additional)" : nil
    }
    
    /// Whether to show the "more segments" indicator
    var showMoreSegmentsIndicator: Bool {
        additionalSegmentCount > 0
    }
    
    // MARK: - Actions
    
    /// Load segment preview thumbnails
    func loadSegmentPreviews() async {
        guard segmentPreviews.isEmpty && !isLoadingPreviews else { return }
        
        isLoadingPreviews = true
        error = nil
        
        do {
            let segments = try await collectionService.getCollectionSegments(collectionID: collection.id)
            
            // Take first N segments for preview
            let previewSegments = Array(segments.prefix(maxPreviewCount))
            
            segmentPreviews = previewSegments.enumerated().map { index, video in
                SegmentPreview(
                    id: video.id,
                    segmentNumber: index + 1,
                    thumbnailURL: video.thumbnailURL,
                    duration: video.duration
                )
            }
            
            // If no segments returned but we have segment IDs, create placeholders
            if segmentPreviews.isEmpty && !collection.segmentIDs.isEmpty {
                segmentPreviews = collection.segmentIDs.prefix(maxPreviewCount).enumerated().map { index, segmentID in
                    SegmentPreview(
                        id: segmentID,
                        segmentNumber: index + 1,
                        thumbnailURL: nil,
                        duration: nil
                    )
                }
            }
            
        } catch {
            self.error = "Failed to load previews"
            print("❌ COLLECTION ROW VM: Failed to load segment previews: \(error)")
        }
        
        isLoadingPreviews = false
    }
    
    /// Toggle bookmark state
    func toggleBookmark() {
        isBookmarked.toggle()
        // TODO: Persist bookmark state to Firebase
        print("📚 COLLECTION ROW VM: Bookmark toggled to \(isBookmarked) for \(collection.id)")
    }
    
    /// Refresh collection data
    func refresh() async {
        do {
            if let updated = try await collectionService.getCollection(id: collection.id) {
                collection = updated
            }
        } catch {
            print("❌ COLLECTION ROW VM: Failed to refresh: \(error)")
        }
    }
    
    // MARK: - Formatting Helpers
    
    /// Format large numbers (e.g., 1234 -> "1.2K")
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        } else if count >= 1_000 {
            let value = Double(count) / 1_000.0
            return String(format: "%.1fK", value)
        } else {
            return "\(count)"
        }
    }
    
    /// Format relative time
    private func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        let weeks = Int(interval / 604800)
        let months = Int(interval / 2592000)
        let years = Int(interval / 31536000)
        
        if years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        } else if months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        } else if weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        } else if days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if minutes > 0 {
            return minutes == 1 ? "1 min ago" : "\(minutes) mins ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Segment Preview Model

/// Lightweight model for segment preview display
struct SegmentPreview: Identifiable, Hashable {
    let id: String
    let segmentNumber: Int
    let thumbnailURL: String?
    let duration: TimeInterval?
    
    /// Formatted duration for overlay
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Part label (e.g., "Part 1")
    var partLabel: String {
        "Part \(segmentNumber)"
    }
}

// MARK: - Equatable

extension CollectionRowViewModel: Equatable {
    static func == (lhs: CollectionRowViewModel, rhs: CollectionRowViewModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension CollectionRowViewModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview Support

#if DEBUG
extension CollectionRowViewModel {
    /// Create a preview instance with mock data
    static var preview: CollectionRowViewModel {
        let mockCollection = VideoCollection(
            id: "preview_collection_1",
            title: "SwiftUI Tutorial Series",
            description: "Learn SwiftUI from basics to advanced topics",
            creatorID: "user_123",
            creatorName: "SwiftDev",
            coverImageURL: nil,
            segmentIDs: ["seg1", "seg2", "seg3", "seg4", "seg5"],
            segmentCount: 5,
            totalDuration: 1845, // 30:45
            status: .published,
            visibility: .publicVisible,
            allowReplies: true,
            publishedAt: Date().addingTimeInterval(-86400 * 3), // 3 days ago
            createdAt: Date().addingTimeInterval(-86400 * 5),
            updatedAt: Date().addingTimeInterval(-86400),
            totalViews: 12500,
            totalHypes: 890,
            totalCools: 45,
            totalReplies: 67,
            totalShares: 23
        )
        
        return CollectionRowViewModel(collection: mockCollection)
    }
    
    /// Create a draft preview instance
    static var draftPreview: CollectionRowViewModel {
        let mockCollection = VideoCollection(
            id: "preview_draft_1",
            title: "Upcoming Course",
            description: "Work in progress",
            creatorID: "user_123",
            creatorName: "Creator",
            coverImageURL: nil,
            segmentIDs: ["seg1", "seg2"],
            segmentCount: 2,
            totalDuration: 600,
            status: .draft,
            visibility: .privateOnly,
            allowReplies: true,
            publishedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            totalViews: 0,
            totalHypes: 0,
            totalCools: 0,
            totalReplies: 0,
            totalShares: 0
        )
        
        return CollectionRowViewModel(collection: mockCollection)
    }
}
#endif
