//
//  Season.swift
//  StitchSocial
//
//  Layer 1: Foundation - Season Data Model
//  Dependencies: Foundation
//  Middle of hierarchy: Show → Season → Episode (Collection) → Segments
//  Mirrors web dashboard season CRUD in ShowEditor.jsx
//
//  CACHING: Seasons per show change infrequently. Cache in CachingService keyed by showId
//  with 30-min TTL. Invalidate on add/delete only.
//  Batch-fetch all seasons for a show in one query (typically 1-5 seasons).
//

import Foundation

// MARK: - Season Status

enum SeasonStatus: String, CaseIterable, Codable {
    case draft = "draft"
    case published = "published"
    case completed = "completed"     // All episodes released
    case upcoming = "upcoming"       // Announced but no episodes yet
    
    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
    
    var icon: String {
        switch self {
        case .draft: return "doc.badge.ellipsis"
        case .published: return "checkmark.circle.fill"
        case .completed: return "flag.checkered"
        case .upcoming: return "calendar.badge.clock"
        }
    }
}

// MARK: - Season Model

/// A season within a show. Contains episodes (collections).
/// Firestore path: shows/{showId}/seasons/{seasonId}
struct Season: Identifiable, Codable, Hashable {
    
    // MARK: - Core Identity
    
    let id: String
    let showId: String
    
    // MARK: - Metadata
    
    var number: Int               // Season number (1-based)
    var title: String             // e.g. "Season 1" or custom title
    var description: String
    var coverImageURL: String?
    
    // MARK: - Status
    
    var status: SeasonStatus
    
    // MARK: - Counts (cached rollup)
    
    var episodeCount: Int
    
    // MARK: - Aggregate Engagement (sum of all episodes in season)
    
    var totalViews: Int
    var totalHypes: Int
    var totalCools: Int
    
    // MARK: - Timestamps
    
    let createdAt: Date
    var updatedAt: Date
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        showId: String,
        number: Int = 1,
        title: String = "",
        description: String = "",
        coverImageURL: String? = nil,
        status: SeasonStatus = .draft,
        episodeCount: Int = 0,
        totalViews: Int = 0,
        totalHypes: Int = 0,
        totalCools: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showId = showId
        self.number = number
        self.title = title.isEmpty ? "Season \(number)" : title
        self.description = description
        self.coverImageURL = coverImageURL
        self.status = status
        self.episodeCount = episodeCount
        self.totalViews = totalViews
        self.totalHypes = totalHypes
        self.totalCools = totalCools
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Hashable
    
    static func == (lhs: Season, rhs: Season) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Factory

extension Season {
    
    /// Create a new season for a show
    static func newSeason(showId: String, number: Int) -> Season {
        Season(showId: showId, number: number)
    }
}

// MARK: - Validation

extension Season {
    
    func validateForPublishing() -> [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Season title is required")
        }
        if episodeCount < 1 {
            errors.append("Season must have at least 1 episode")
        }
        return errors
    }
}
