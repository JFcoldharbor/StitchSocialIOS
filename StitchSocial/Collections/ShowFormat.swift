//
//  ShowFormat.swift
//  StitchSocial
//
//  Created by James Garmon on 3/31/26.
//


//
//  Show.swift
//  StitchSocial
//
//  Layer 1: Foundation - Show Data Model
//  Dependencies: Foundation, SwiftUI
//  Top of content hierarchy: Show → Season → Episode (Collection) → Segments
//  Mirrors web dashboard ShowEditor.jsx structure
//
//  CACHING: Shows change rarely. Cache aggressively in CachingService with 30-min TTL.
//  Batch-fetch seasons + episode counts in a single parallel call on load.
//  Add to OptimizationConfig.Shows for TTL and limit constants.
//

import Foundation
import SwiftUI

// MARK: - Show Format

/// Video format/orientation for all content in this show
enum ShowFormat: String, CaseIterable, Codable {
    case vertical = "vertical"       // 9:16 — mobile native, drama box, stories
    case widescreen = "widescreen"   // 16:9 — podcasts, documentaries, films
    
    var displayName: String {
        switch self {
        case .vertical: return "9:16 Vertical"
        case .widescreen: return "16:9 Widescreen"
        }
    }
    
    var aspectRatio: Double {
        switch self {
        case .vertical: return 9.0 / 16.0
        case .widescreen: return 16.0 / 9.0
        }
    }
    
    var icon: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .widescreen: return "rectangle"
        }
    }
}

// MARK: - Show Genre

enum ShowGenre: String, CaseIterable, Codable {
    case drama, comedy, thriller, action, reality
    case documentary, music, sports, horror, romance
    case scifi, animation, other
    
    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

// MARK: - Show Status

enum ShowStatus: String, CaseIterable, Codable {
    case draft = "draft"
    case published = "published"
    case paused = "paused"
    case completed = "completed"    // No more seasons/episodes planned
    case removed = "removed"
    
    var displayName: String { rawValue.uppercased() }
    
    var isVisible: Bool {
        self == .published || self == .paused || self == .completed
    }
    
    var icon: String {
        switch self {
        case .draft: return "doc.badge.ellipsis"
        case .published: return "checkmark.circle.fill"
        case .paused: return "pause.circle"
        case .completed: return "flag.checkered"
        case .removed: return "trash"
        }
    }
}

// MARK: - Show Tag

/// Curated tags for discovery and featuring
enum ShowTag: String, CaseIterable, Codable {
    case exclusive, trending, new, premiere, binge, hot, featured
    
    var displayName: String { rawValue.uppercased() }
    
    var color: Color {
        switch self {
        case .exclusive: return .purple
        case .trending: return .orange
        case .new: return .green
        case .premiere: return .red
        case .binge: return .blue
        case .hot: return .pink
        case .featured: return .yellow
        }
    }
}

// MARK: - Show Model

/// Top-level content container. A show has seasons, each season has episodes (collections).
/// Firestore path: shows/{showId}
struct Show: Identifiable, Codable, Hashable {
    
    // MARK: - Core Identity
    
    let id: String
    var title: String
    var description: String
    let creatorID: String
    var creatorName: String
    
    // MARK: - Content Settings
    
    var format: ShowFormat
    var genre: ShowGenre
    var contentType: CollectionContentType   // Inherits down to all episodes
    var tags: [ShowTag]
    
    // MARK: - Media
    
    var coverImageURL: String?
    var thumbnailURL: String?
    
    // MARK: - Status
    
    var status: ShowStatus
    var isFeatured: Bool
    
    // MARK: - Counts (cached rollups — updated on season/episode add/delete)
    
    var seasonCount: Int
    var totalEpisodes: Int
    
    // MARK: - Aggregate Engagement (sum of all episodes)
    
    var totalViews: Int
    var totalHypes: Int
    var totalCools: Int
    
    // MARK: - Timestamps
    
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        title: String = "",
        description: String = "",
        creatorID: String,
        creatorName: String = "",
        format: ShowFormat = .vertical,
        genre: ShowGenre = .drama,
        contentType: CollectionContentType = .series,
        tags: [ShowTag] = [],
        coverImageURL: String? = nil,
        thumbnailURL: String? = nil,
        status: ShowStatus = .draft,
        isFeatured: Bool = false,
        seasonCount: Int = 0,
        totalEpisodes: Int = 0,
        totalViews: Int = 0,
        totalHypes: Int = 0,
        totalCools: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.format = format
        self.genre = genre
        self.contentType = contentType
        self.tags = tags
        self.coverImageURL = coverImageURL
        self.thumbnailURL = thumbnailURL
        self.status = status
        self.isFeatured = isFeatured
        self.seasonCount = seasonCount
        self.totalEpisodes = totalEpisodes
        self.totalViews = totalViews
        self.totalHypes = totalHypes
        self.totalCools = totalCools
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Hashable
    
    static func == (lhs: Show, rhs: Show) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Factory

extension Show {
    
    /// New blank show for creator
    static func newDraft(creatorID: String, creatorName: String) -> Show {
        Show(creatorID: creatorID, creatorName: creatorName)
    }
}

// MARK: - Validation

extension Show {
    
    func validateForPublishing() -> [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title is required")
        }
        if title.count > 100 {
            errors.append("Title must be 100 characters or less")
        }
        if seasonCount < 1 {
            errors.append("Show must have at least 1 season")
        }
        if totalEpisodes < 1 {
            errors.append("Show must have at least 1 episode")
        }
        return errors
    }
}