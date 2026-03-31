//
//  CollectionStatus.swift (UPDATED)
//  StitchSocial
//
//  Layer 1: Foundation - Core Collection Data Models
//  Dependencies: Foundation, SwiftUI, Show.swift (ShowFormat)
//  Single source of truth for video collections
//  UPDATED: Added show hierarchy fields (showId, seasonId, episodeNumber, format)
//  UPDATED: Added upload pipeline metadata (compressed, splitIntoFiles, file sizes)
//  UPDATED: Added AdSlot model for mid-roll ad placement
//

import Foundation
import SwiftUI

// MARK: - Collection Status

enum CollectionStatus: String, CaseIterable, Codable {
    case draft = "draft"
    case processing = "processing"
    case published = "published"
    case archived = "archived"
    case deleted = "deleted"
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .processing: return "Processing"
        case .published: return "Published"
        case .archived: return "Archived"
        case .deleted: return "Deleted"
        }
    }
    
    var isVisible: Bool { self == .published }
    var isEditable: Bool { self == .draft || self == .processing }
    
    var iconName: String {
        switch self {
        case .draft: return "doc.badge.ellipsis"
        case .processing: return "arrow.clockwise"
        case .published: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        case .deleted: return "trash"
        }
    }
}

// MARK: - Collection Visibility

enum CollectionVisibility: String, CaseIterable, Codable {
    case publicVisible = "public"
    case followers = "followers"
    case privateOnly = "private"
    
    var displayName: String {
        switch self {
        case .publicVisible: return "Public"
        case .followers: return "Followers Only"
        case .privateOnly: return "Private"
        }
    }
    
    var iconName: String {
        switch self {
        case .publicVisible: return "globe"
        case .followers: return "person.2.fill"
        case .privateOnly: return "lock.fill"
        }
    }
    
    var description: String {
        switch self {
        case .publicVisible: return "Anyone can view this collection"
        case .followers: return "Only your followers can view"
        case .privateOnly: return "Only you can view this collection"
        }
    }
}

// MARK: - Collection Content Type

enum CollectionContentType: String, CaseIterable, Codable {
    case standard = "standard"
    case podcast = "podcast"
    case shortFilm = "shortFilm"
    case interview = "interview"
    case series = "series"
    case documentary = "documentary"
    case tutorial = "tutorial"
    
    var displayName: String {
        switch self {
        case .standard: return "Collection"
        case .podcast: return "Podcast"
        case .shortFilm: return "Short Film"
        case .interview: return "Interview"
        case .series: return "Series"
        case .documentary: return "Documentary"
        case .tutorial: return "Tutorial"
        }
    }
    
    var icon: String {
        switch self {
        case .standard: return "square.stack.3d.up"
        case .podcast: return "mic.fill"
        case .shortFilm: return "film"
        case .interview: return "person.2.wave.2.fill"
        case .series: return "play.rectangle.on.rectangle"
        case .documentary: return "doc.text.image"
        case .tutorial: return "graduationcap.fill"
        }
    }
    
    var allowsStitchReplies: Bool {
        switch self {
        case .standard, .tutorial: return true
        case .podcast, .shortFilm, .interview, .series, .documentary: return false
        }
    }
}

// MARK: - Ad Slot (NEW — mid-roll ad placement from EpisodeEditor.jsx)

/// Ad placement marker within a collection (episode).
/// Stored on the episode/collection doc, not on individual segments.
/// Immutable after publish — caches with episode data, no extra reads.
struct AdSlot: Codable, Hashable {
    /// Which segment this ad plays AFTER (0-based index)
    let afterSegmentIndex: Int
    
    /// Time in the original video where this ad inserts (trimmer UI reference)
    let insertAfterTime: TimeInterval
    
    /// Ad type — "standard", "sponsored", "house"
    let type: String
    
    /// How long this ad slot is (seconds)
    let durationSeconds: TimeInterval
}

// MARK: - Video Collection

/// Core data model for a video collection (episode).
/// 1 Collection = 1 Episode. Contains ordered segments, aggregate metrics, and settings.
/// Firestore path (standalone): videoCollections/{collectionId}
/// Firestore path (show hierarchy): shows/{showId}/seasons/{seasonId}/episodes/{episodeId}
struct VideoCollection: Identifiable, Codable, Hashable {
    
    // MARK: - Core Identity
    
    let id: String
    let title: String
    let description: String
    let creatorID: String
    let creatorName: String
    let coverImageURL: String?
    
    // MARK: - Segment Management
    
    let segmentIDs: [String]
    let segmentCount: Int
    let totalDuration: TimeInterval
    
    // MARK: - Status & Settings
    
    let status: CollectionStatus
    let visibility: CollectionVisibility
    let allowReplies: Bool
    let contentType: CollectionContentType
    let allowStitchReplies: Bool
    
    // MARK: - Show Hierarchy (NEW — links episode to show/season)
    
    let showId: String?              // Parent show ID (nil for standalone collections)
    let seasonId: String?            // Parent season ID (nil for standalone collections)
    let episodeNumber: Int?          // Episode number within the season (1-based)
    let format: ShowFormat?          // Inherited from show (vertical/widescreen)
    
    // MARK: - Upload Pipeline Metadata (NEW — from EpisodeEditor.jsx)
    
    let compressed: Bool             // Whether video was compressed before splitting
    let splitIntoFiles: Bool         // Whether episode was split into individual segment files
    let originalFileSizeMB: Double?  // Original upload file size
    let compressedFileSizeMB: Double? // Compressed file size (if compressed)
    
    // MARK: - Ad Slots (NEW — mid-roll ad placement)
    
    let adSlots: [AdSlot]?           // Ad insertion points between segments
    
    // MARK: - Timestamps
    
    let publishedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - Aggregate Engagement (sum of all segments)
    
    let totalViews: Int
    let totalHypes: Int
    let totalCools: Int
    let totalReplies: Int
    let totalShares: Int
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        creatorID: String,
        creatorName: String,
        coverImageURL: String? = nil,
        segmentIDs: [String] = [],
        segmentCount: Int = 0,
        totalDuration: TimeInterval = 0,
        status: CollectionStatus = .draft,
        visibility: CollectionVisibility = .publicVisible,
        allowReplies: Bool = true,
        contentType: CollectionContentType = .standard,
        allowStitchReplies: Bool? = nil,
        // Show hierarchy (NEW — defaults nil for backwards compat)
        showId: String? = nil,
        seasonId: String? = nil,
        episodeNumber: Int? = nil,
        format: ShowFormat? = nil,
        // Upload pipeline (NEW — defaults for backwards compat)
        compressed: Bool = false,
        splitIntoFiles: Bool = false,
        originalFileSizeMB: Double? = nil,
        compressedFileSizeMB: Double? = nil,
        adSlots: [AdSlot]? = nil,
        // Timestamps
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        // Engagement
        totalViews: Int = 0,
        totalHypes: Int = 0,
        totalCools: Int = 0,
        totalReplies: Int = 0,
        totalShares: Int = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.coverImageURL = coverImageURL
        self.segmentIDs = segmentIDs
        self.segmentCount = segmentCount
        self.totalDuration = totalDuration
        self.status = status
        self.visibility = visibility
        self.allowReplies = allowReplies
        self.contentType = contentType
        self.allowStitchReplies = allowStitchReplies ?? contentType.allowsStitchReplies
        // Show hierarchy
        self.showId = showId
        self.seasonId = seasonId
        self.episodeNumber = episodeNumber
        self.format = format
        // Upload pipeline
        self.compressed = compressed
        self.splitIntoFiles = splitIntoFiles
        self.originalFileSizeMB = originalFileSizeMB
        self.compressedFileSizeMB = compressedFileSizeMB
        self.adSlots = adSlots
        // Timestamps
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // Engagement
        self.totalViews = totalViews
        self.totalHypes = totalHypes
        self.totalCools = totalCools
        self.totalReplies = totalReplies
        self.totalShares = totalShares
    }
    
    // MARK: - Computed Properties
    
    var isPublished: Bool { status == .published }
    
    var isDraft: Bool { status == .draft }
    
    var netScore: Int { totalHypes - totalCools }
    
    var isPartOfShow: Bool { showId != nil }
    
    var isStandalone: Bool { showId == nil }
    
    var episodeDisplayTitle: String {
        if let num = episodeNumber {
            return title.isEmpty ? "Episode \(num)" : "Ep \(num): \(title)"
        }
        return title.isEmpty ? "Untitled" : title
    }
    
    var formattedTotalDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var summaryText: String {
        "\(segmentCount) segments · \(formattedTotalDuration)"
    }
    
    var averageSegmentDuration: TimeInterval {
        guard segmentCount > 0 else { return 0 }
        return totalDuration / Double(segmentCount)
    }
    
    var totalEngagement: Int {
        totalViews + totalHypes + totalCools + totalReplies + totalShares
    }
    
    var engagementHealth: Double {
        let total = totalHypes + totalCools
        return total > 0 ? Double(totalHypes) / Double(total) : 0.5
    }
    
    var compressionSavings: Double? {
        guard let original = originalFileSizeMB, let compressed = compressedFileSizeMB, original > 0 else {
            return nil
        }
        return (1.0 - compressed / original) * 100.0
    }
    
    // MARK: - Hashable
    
    static func == (lhs: VideoCollection, rhs: VideoCollection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Factory Methods

extension VideoCollection {
    
    static func newDraft(
        title: String,
        description: String = "",
        creatorID: String,
        creatorName: String,
        visibility: CollectionVisibility = .publicVisible,
        allowReplies: Bool = true,
        contentType: CollectionContentType = .standard,
        showId: String? = nil,
        seasonId: String? = nil,
        episodeNumber: Int? = nil,
        format: ShowFormat? = nil
    ) -> VideoCollection {
        return VideoCollection(
            title: title,
            description: description,
            creatorID: creatorID,
            creatorName: creatorName,
            visibility: visibility,
            allowReplies: allowReplies,
            contentType: contentType,
            showId: showId,
            seasonId: seasonId,
            episodeNumber: episodeNumber,
            format: format
        )
    }
}

// MARK: - Update Methods

extension VideoCollection {
    
    func withUpdatedSegments(
        segmentIDs: [String],
        totalDuration: TimeInterval
    ) -> VideoCollection {
        return VideoCollection(
            id: id, title: title, description: description,
            creatorID: creatorID, creatorName: creatorName, coverImageURL: coverImageURL,
            segmentIDs: segmentIDs, segmentCount: segmentIDs.count, totalDuration: totalDuration,
            status: status, visibility: visibility, allowReplies: allowReplies,
            contentType: contentType, allowStitchReplies: allowStitchReplies,
            showId: showId, seasonId: seasonId, episodeNumber: episodeNumber, format: format,
            compressed: compressed, splitIntoFiles: splitIntoFiles,
            originalFileSizeMB: originalFileSizeMB, compressedFileSizeMB: compressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: publishedAt, createdAt: createdAt, updatedAt: Date(),
            totalViews: totalViews, totalHypes: totalHypes, totalCools: totalCools,
            totalReplies: totalReplies, totalShares: totalShares
        )
    }
    
    func withStatus(_ newStatus: CollectionStatus) -> VideoCollection {
        return VideoCollection(
            id: id, title: title, description: description,
            creatorID: creatorID, creatorName: creatorName, coverImageURL: coverImageURL,
            segmentIDs: segmentIDs, segmentCount: segmentCount, totalDuration: totalDuration,
            status: newStatus, visibility: visibility, allowReplies: allowReplies,
            contentType: contentType, allowStitchReplies: allowStitchReplies,
            showId: showId, seasonId: seasonId, episodeNumber: episodeNumber, format: format,
            compressed: compressed, splitIntoFiles: splitIntoFiles,
            originalFileSizeMB: originalFileSizeMB, compressedFileSizeMB: compressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: newStatus == .published ? Date() : publishedAt,
            createdAt: createdAt, updatedAt: Date(),
            totalViews: totalViews, totalHypes: totalHypes, totalCools: totalCools,
            totalReplies: totalReplies, totalShares: totalShares
        )
    }
    
    func withUpdatedMetadata(
        title: String? = nil,
        description: String? = nil,
        coverImageURL: String? = nil,
        visibility: CollectionVisibility? = nil,
        allowReplies: Bool? = nil,
        contentType: CollectionContentType? = nil,
        allowStitchReplies: Bool? = nil
    ) -> VideoCollection {
        return VideoCollection(
            id: id, title: title ?? self.title, description: description ?? self.description,
            creatorID: creatorID, creatorName: creatorName,
            coverImageURL: coverImageURL ?? self.coverImageURL,
            segmentIDs: segmentIDs, segmentCount: segmentCount, totalDuration: totalDuration,
            status: status, visibility: visibility ?? self.visibility,
            allowReplies: allowReplies ?? self.allowReplies,
            contentType: contentType ?? self.contentType,
            allowStitchReplies: allowStitchReplies ?? self.allowStitchReplies,
            showId: showId, seasonId: seasonId, episodeNumber: episodeNumber, format: format,
            compressed: compressed, splitIntoFiles: splitIntoFiles,
            originalFileSizeMB: originalFileSizeMB, compressedFileSizeMB: compressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: publishedAt, createdAt: createdAt, updatedAt: Date(),
            totalViews: totalViews, totalHypes: totalHypes, totalCools: totalCools,
            totalReplies: totalReplies, totalShares: totalShares
        )
    }
    
    func withUpdatedEngagement(
        totalViews: Int? = nil,
        totalHypes: Int? = nil,
        totalCools: Int? = nil,
        totalReplies: Int? = nil,
        totalShares: Int? = nil
    ) -> VideoCollection {
        return VideoCollection(
            id: id, title: title, description: description,
            creatorID: creatorID, creatorName: creatorName, coverImageURL: coverImageURL,
            segmentIDs: segmentIDs, segmentCount: segmentCount, totalDuration: totalDuration,
            status: status, visibility: visibility, allowReplies: allowReplies,
            contentType: contentType, allowStitchReplies: allowStitchReplies,
            showId: showId, seasonId: seasonId, episodeNumber: episodeNumber, format: format,
            compressed: compressed, splitIntoFiles: splitIntoFiles,
            originalFileSizeMB: originalFileSizeMB, compressedFileSizeMB: compressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: publishedAt, createdAt: createdAt, updatedAt: Date(),
            totalViews: totalViews ?? self.totalViews, totalHypes: totalHypes ?? self.totalHypes,
            totalCools: totalCools ?? self.totalCools, totalReplies: totalReplies ?? self.totalReplies,
            totalShares: totalShares ?? self.totalShares
        )
    }
    
    func withUploadPipelineData(
        compressed: Bool,
        splitIntoFiles: Bool,
        originalFileSizeMB: Double,
        compressedFileSizeMB: Double?,
        adSlots: [AdSlot]?
    ) -> VideoCollection {
        return VideoCollection(
            id: id, title: title, description: description,
            creatorID: creatorID, creatorName: creatorName, coverImageURL: coverImageURL,
            segmentIDs: segmentIDs, segmentCount: segmentCount, totalDuration: totalDuration,
            status: status, visibility: visibility, allowReplies: allowReplies,
            contentType: contentType, allowStitchReplies: allowStitchReplies,
            showId: showId, seasonId: seasonId, episodeNumber: episodeNumber, format: format,
            compressed: compressed, splitIntoFiles: splitIntoFiles,
            originalFileSizeMB: originalFileSizeMB, compressedFileSizeMB: compressedFileSizeMB,
            adSlots: adSlots,
            publishedAt: publishedAt, createdAt: createdAt, updatedAt: Date(),
            totalViews: totalViews, totalHypes: totalHypes, totalCools: totalCools,
            totalReplies: totalReplies, totalShares: totalShares
        )
    }
}

// MARK: - Validation

extension VideoCollection {
    
    struct ValidationResult {
        let isValid: Bool
        let errors: [String]
        
        static let valid = ValidationResult(isValid: true, errors: [])
        static func invalid(_ errors: [String]) -> ValidationResult {
            return ValidationResult(isValid: false, errors: errors)
        }
    }
    
    func validateForPublishing() -> ValidationResult {
        var errors: [String] = []
        
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title is required")
        }
        if title.count > 100 {
            errors.append("Title must be 100 characters or less")
        }
        if description.count > 500 {
            errors.append("Description must be 500 characters or less")
        }
        if segmentCount < 2 {
            errors.append("Collection must have at least 2 segments")
        }
        if segmentCount > 50 {
            errors.append("Collection cannot have more than 50 segments")
        }
        if status != .draft {
            errors.append("Only draft collections can be published")
        }
        
        return errors.isEmpty ? .valid : .invalid(errors)
    }
}

// MARK: - Segment Info (Lightweight reference)

struct CollectionSegmentInfo: Identifiable, Codable, Hashable {
    let id: String
    let segmentNumber: Int
    let title: String?
    let thumbnailURL: String?
    let duration: TimeInterval
    let replyCount: Int
    // NEW — segment time mapping
    let startTimeSeconds: TimeInterval?
    let endTimeSeconds: TimeInterval?
    let fileSizeMB: Double?
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var displayTitle: String {
        return title ?? "Part \(segmentNumber)"
    }
    
    var formattedTimeRange: String? {
        guard let start = startTimeSeconds, let end = endTimeSeconds else { return nil }
        let fmtStart = formatTime(start)
        let fmtEnd = formatTime(end)
        return "\(fmtStart) → \(fmtEnd)"
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
