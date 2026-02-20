//
//  CollectionStatus.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CoreCollectionMetadata.swift
//  StitchSocial
//
//  Layer 1: Foundation - Core Collection Data Models
//  Dependencies: Foundation only
//  Single source of truth for video collections (Instagram Stories/Highlights style)
//  Handles collection lifecycle, visibility, and aggregate engagement metrics
//  CREATED: Collections feature for long-form segmented content
//

import Foundation
import SwiftUI

// MARK: - Collection Status

/// Lifecycle status of a video collection
enum CollectionStatus: String, CaseIterable, Codable {
    case draft = "draft"              // Being created, not visible to others
    case processing = "processing"    // Segments uploading/processing
    case published = "published"      // Live and visible
    case archived = "archived"        // Hidden but not deleted
    case deleted = "deleted"          // Soft deleted
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .processing: return "Processing"
        case .published: return "Published"
        case .archived: return "Archived"
        case .deleted: return "Deleted"
        }
    }
    
    var isVisible: Bool {
        return self == .published
    }
    
    var isEditable: Bool {
        return self == .draft || self == .processing
    }
    
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

/// Visibility settings for a collection
enum CollectionVisibility: String, CaseIterable, Codable {
    case publicVisible = "public"     // Anyone can see
    case followers = "followers"       // Only followers can see
    case privateOnly = "private"       // Only creator can see
    
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

/// What kind of content this collection represents
/// Drives discovery routing, player behavior, and reply rules
enum CollectionContentType: String, CaseIterable, Codable {
    case standard = "standard"          // Default collection
    case podcast = "podcast"            // Video podcast — long interviews, talk shows
    case shortFilm = "shortFilm"        // Short films, skits, narrative content
    case interview = "interview"        // Interviews, Q&A sessions
    case series = "series"              // Recurring episodic content
    case documentary = "documentary"    // Documentary-style long-form
    case tutorial = "tutorial"          // Educational/how-to content
    
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
    
    /// Whether video stitch replies are allowed (insert into chain)
    /// Podcasts, films, documentaries play uninterrupted — replies exist but don't stitch
    var allowsStitchReplies: Bool {
        switch self {
        case .standard, .tutorial: return true
        case .podcast, .shortFilm, .interview, .series, .documentary: return false
        }
    }
}

// MARK: - Video Collection

/// Core data model for a video collection (Instagram Stories/Highlights style)
/// Contains ordered segments, aggregate metrics, and collection settings
struct VideoCollection: Identifiable, Codable, Hashable {
    
    // MARK: - Core Identity
    
    let id: String
    let title: String
    let description: String
    let creatorID: String
    let creatorName: String
    let coverImageURL: String?
    
    // MARK: - Segment Management
    
    /// Ordered array of segment video IDs
    let segmentIDs: [String]
    
    /// Total number of segments (cached for quick access)
    let segmentCount: Int
    
    /// Total duration of all segments combined (seconds)
    let totalDuration: TimeInterval
    
    // MARK: - Status & Settings
    
    let status: CollectionStatus
    let visibility: CollectionVisibility
    let allowReplies: Bool
    
    /// What kind of content — drives discovery lane and reply behavior
    let contentType: CollectionContentType
    
    /// Whether video replies can stitch into the segment chain.
    /// false = replies exist as standard video comments but don't break playback.
    /// Defaults from contentType.allowsStitchReplies but can be overridden.
    let allowStitchReplies: Bool
    
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
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
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
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalViews = totalViews
        self.totalHypes = totalHypes
        self.totalCools = totalCools
        self.totalReplies = totalReplies
        self.totalShares = totalShares
    }
    
    // MARK: - Computed Properties
    
    /// True if collection is published and visible
    var isPublished: Bool {
        return status == .published
    }
    
    /// True if collection is still being created
    var isDraft: Bool {
        return status == .draft || status == .processing
    }
    
    /// True if collection has minimum required segments (2+)
    var hasMinimumSegments: Bool {
        return segmentCount >= 2
    }
    
    /// True if collection can be published
    var canPublish: Bool {
        return hasMinimumSegments && !title.isEmpty && status == .draft
    }
    
    /// Formatted total duration (e.g., "12:34" or "1:02:34")
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Average segment duration
    var averageSegmentDuration: TimeInterval {
        guard segmentCount > 0 else { return 0 }
        return totalDuration / Double(segmentCount)
    }
    
    /// Net engagement score (hypes - cools)
    var netScore: Int {
        return totalHypes - totalCools
    }
    
    /// Total engagement interactions
    var totalEngagement: Int {
        return totalHypes + totalCools + totalReplies + totalShares
    }
    
    /// Engagement ratio (hypes / total hypes+cools)
    var engagementRatio: Double {
        let total = totalHypes + totalCools
        return total > 0 ? Double(totalHypes) / Double(total) : 0.5
    }
    
    /// Views to engagement ratio
    var viewEngagementRatio: Double {
        return totalViews > 0 ? Double(totalEngagement) / Double(totalViews) : 0.0
    }
    
    /// Age since creation in hours
    var ageInHours: Double {
        return Date().timeIntervalSince(createdAt) / 3600.0
    }
    
    /// Age since publication in hours (nil if not published)
    var publishedAgeInHours: Double? {
        guard let publishedAt = publishedAt else { return nil }
        return Date().timeIntervalSince(publishedAt) / 3600.0
    }
    
    /// Display string for segment count
    var segmentCountDisplay: String {
        return segmentCount == 1 ? "1 segment" : "\(segmentCount) segments"
    }
    
    /// Short summary for display
    var summaryText: String {
        return "\(segmentCountDisplay) • \(formattedTotalDuration)"
    }
    
    // MARK: - Hashable & Equatable
    
    static func == (lhs: VideoCollection, rhs: VideoCollection) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Factory Methods

extension VideoCollection {
    
    /// Creates a new empty collection draft
    static func newDraft(
        title: String,
        description: String = "",
        creatorID: String,
        creatorName: String,
        visibility: CollectionVisibility = .publicVisible,
        allowReplies: Bool = true,
        contentType: CollectionContentType = .standard
    ) -> VideoCollection {
        return VideoCollection(
            id: UUID().uuidString,
            title: title,
            description: description,
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: nil,
            segmentIDs: [],
            segmentCount: 0,
            totalDuration: 0,
            status: .draft,
            visibility: visibility,
            allowReplies: allowReplies,
            contentType: contentType,
            publishedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            totalViews: 0,
            totalHypes: 0,
            totalCools: 0,
            totalReplies: 0,
            totalShares: 0
        )
    }
}

// MARK: - Update Methods

extension VideoCollection {
    
    /// Creates a copy with updated segments
    func withUpdatedSegments(
        segmentIDs: [String],
        totalDuration: TimeInterval
    ) -> VideoCollection {
        return VideoCollection(
            id: id,
            title: title,
            description: description,
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: coverImageURL,
            segmentIDs: segmentIDs,
            segmentCount: segmentIDs.count,
            totalDuration: totalDuration,
            status: status,
            visibility: visibility,
            allowReplies: allowReplies,
            contentType: contentType,
            allowStitchReplies: allowStitchReplies,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            totalViews: totalViews,
            totalHypes: totalHypes,
            totalCools: totalCools,
            totalReplies: totalReplies,
            totalShares: totalShares
        )
    }
    
    /// Creates a copy with updated status
    func withStatus(_ newStatus: CollectionStatus) -> VideoCollection {
        return VideoCollection(
            id: id,
            title: title,
            description: description,
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: coverImageURL,
            segmentIDs: segmentIDs,
            segmentCount: segmentCount,
            totalDuration: totalDuration,
            status: newStatus,
            visibility: visibility,
            allowReplies: allowReplies,
            contentType: contentType,
            allowStitchReplies: allowStitchReplies,
            publishedAt: newStatus == .published ? Date() : publishedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            totalViews: totalViews,
            totalHypes: totalHypes,
            totalCools: totalCools,
            totalReplies: totalReplies,
            totalShares: totalShares
        )
    }
    
    /// Creates a copy with updated metadata
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
            id: id,
            title: title ?? self.title,
            description: description ?? self.description,
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: coverImageURL ?? self.coverImageURL,
            segmentIDs: segmentIDs,
            segmentCount: segmentCount,
            totalDuration: totalDuration,
            status: status,
            visibility: visibility ?? self.visibility,
            allowReplies: allowReplies ?? self.allowReplies,
            contentType: contentType ?? self.contentType,
            allowStitchReplies: allowStitchReplies ?? self.allowStitchReplies,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            totalViews: totalViews,
            totalHypes: totalHypes,
            totalCools: totalCools,
            totalReplies: totalReplies,
            totalShares: totalShares
        )
    }
    
    /// Creates a copy with updated engagement metrics
    func withUpdatedEngagement(
        totalViews: Int? = nil,
        totalHypes: Int? = nil,
        totalCools: Int? = nil,
        totalReplies: Int? = nil,
        totalShares: Int? = nil
    ) -> VideoCollection {
        return VideoCollection(
            id: id,
            title: title,
            description: description,
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: coverImageURL,
            segmentIDs: segmentIDs,
            segmentCount: segmentCount,
            totalDuration: totalDuration,
            status: status,
            visibility: visibility,
            allowReplies: allowReplies,
            contentType: contentType,
            allowStitchReplies: allowStitchReplies,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            totalViews: totalViews ?? self.totalViews,
            totalHypes: totalHypes ?? self.totalHypes,
            totalCools: totalCools ?? self.totalCools,
            totalReplies: totalReplies ?? self.totalReplies,
            totalShares: totalShares ?? self.totalShares
        )
    }
}

// MARK: - Validation

extension VideoCollection {
    
    /// Validation result for collection
    struct ValidationResult {
        let isValid: Bool
        let errors: [String]
        
        static let valid = ValidationResult(isValid: true, errors: [])
        
        static func invalid(_ errors: [String]) -> ValidationResult {
            return ValidationResult(isValid: false, errors: errors)
        }
    }
    
    /// Validates collection for publishing
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

/// Lightweight segment reference for quick display without loading full video
struct CollectionSegmentInfo: Identifiable, Codable, Hashable {
    let id: String
    let segmentNumber: Int
    let title: String?
    let thumbnailURL: String?
    let duration: TimeInterval
    let replyCount: Int
    
    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Display title (segment number if no title)
    var displayTitle: String {
        return title ?? "Part \(segmentNumber)"
    }
}
