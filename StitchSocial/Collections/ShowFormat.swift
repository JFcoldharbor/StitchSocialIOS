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

/// All content is 9:16 vertical on Stitch Social.
/// Kept as enum for Firestore compat but only one value used.
enum ShowFormat: String, CaseIterable, Codable {
    case vertical = "vertical"
    
    var displayName: String { "9:16 Vertical" }
    var aspectRatio: Double { 9.0 / 16.0 }
    var icon: String { "rectangle.portrait" }
}

// MARK: - Show Genre

enum ShowGenre: String, CaseIterable, Codable {
    case podcast = "podcast"
    case tutorial = "tutorial"
    case movie = "movie"
    case shortFilm = "shortFilm"
    case irl = "irl"
    case documentary = "documentary"
    case interview = "interview"
    case series = "series"
    case music = "music"
    case comedy = "comedy"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .podcast: return "Podcast"
        case .tutorial: return "Tutorial"
        case .movie: return "Movie"
        case .shortFilm: return "Short Film"
        case .irl: return "IRL"
        case .documentary: return "Documentary"
        case .interview: return "Interview"
        case .series: return "Series"
        case .music: return "Music"
        case .comedy: return "Comedy"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .podcast: return "mic.fill"
        case .tutorial: return "graduationcap.fill"
        case .movie: return "film"
        case .shortFilm: return "film.stack"
        case .irl: return "video.fill"
        case .documentary: return "doc.text.image"
        case .interview: return "person.2.wave.2.fill"
        case .series: return "play.rectangle.on.rectangle"
        case .music: return "music.note"
        case .comedy: return "theatermasks"
        case .other: return "square.grid.2x2"
        }
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
    var isFree: Bool          // When true, all episodes are free regardless of episode setting
    
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

    // MARK: - Release Schedule

    var scheduleConfig: ShowScheduleConfig?   // nil = no cadence set yet

    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        title: String = "",
        description: String = "",
        creatorID: String,
        creatorName: String = "",
        format: ShowFormat = .vertical,
        genre: ShowGenre = .other,
        contentType: CollectionContentType = .series,
        tags: [ShowTag] = [],
        coverImageURL: String? = nil,
        thumbnailURL: String? = nil,
        status: ShowStatus = .draft,
        isFeatured: Bool = false,
        isFree: Bool = false,
        seasonCount: Int = 0,
        totalEpisodes: Int = 0,
        totalViews: Int = 0,
        totalHypes: Int = 0,
        totalCools: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scheduleConfig: ShowScheduleConfig? = nil
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
        self.isFree = isFree
        self.seasonCount = seasonCount
        self.totalEpisodes = totalEpisodes
        self.totalViews = totalViews
        self.totalHypes = totalHypes
        self.totalCools = totalCools
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduleConfig = scheduleConfig
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
