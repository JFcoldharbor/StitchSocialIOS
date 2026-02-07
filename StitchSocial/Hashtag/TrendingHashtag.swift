//
//  TrendingHashtag.swift
//  StitchSocial
//
//  Created by James Garmon on 2/5/26.
//


//
//  HashtagModels.swift
//  StitchSocial
//
//  Layer 1: Foundation - Hashtag Data Models
//  Dependencies: NONE (Foundation only)
//  Features: Trending hashtag model, hashtag stats, velocity tracking


import Foundation

// MARK: - Trending Hashtag Model

/// Represents a hashtag with engagement/velocity metrics for discovery
struct TrendingHashtag: Identifiable, Codable, Hashable {
    let id: String          // The hashtag string itself (no # prefix)
    let tag: String         // Display string (no # prefix)
    let videoCount: Int     // Total videos using this tag
    let recentVideoCount: Int // Videos in last 24h
    let totalHypes: Int     // Aggregate hypes across tagged videos
    let velocity: Double    // Engagement rate — hypes per hour in last 24h
    let lastUsedAt: Date
    
    init(
        tag: String,
        videoCount: Int = 0,
        recentVideoCount: Int = 0,
        totalHypes: Int = 0,
        velocity: Double = 0.0,
        lastUsedAt: Date = Date()
    ) {
        self.id = tag.lowercased()
        self.tag = tag.lowercased()
        self.videoCount = videoCount
        self.recentVideoCount = recentVideoCount
        self.totalHypes = totalHypes
        self.velocity = velocity
        self.lastUsedAt = lastUsedAt
    }
    
    // MARK: - Computed Properties
    
    /// Display string with # prefix
    var displayTag: String { "#\(tag)" }
    
    /// Velocity tier for UI indicators
    var velocityTier: HashtagVelocityTier {
        if velocity >= 50.0 { return .blazing }
        if velocity >= 20.0 { return .hot }
        if velocity >= 5.0  { return .rising }
        return .steady
    }
    
    /// Whether this tag is currently trending (recent activity + velocity)
    var isTrending: Bool {
        recentVideoCount >= 2 && velocity >= 5.0
    }
}

// MARK: - Velocity Tier

enum HashtagVelocityTier: String, CaseIterable, Codable {
    case blazing, hot, rising, steady
    
    var emoji: String {
        switch self {
        case .blazing: return "🔥"
        case .hot:     return "🌶️"
        case .rising:  return "📈"
        case .steady:  return "•"
        }
    }
    
    var displayName: String {
        switch self {
        case .blazing: return "Blazing"
        case .hot:     return "Hot"
        case .rising:  return "Rising"
        case .steady:  return "Steady"
        }
    }
}

// MARK: - Hashtag Filter State

/// Tracks active hashtag filter in SearchTab / DiscoveryView
struct HashtagFilterState {
    var activeTag: String?       // nil = no filter
    var videoCount: Int = 0
    var isFollowing: Bool = false
    
    var isActive: Bool { activeTag != nil }
    
    mutating func activate(tag: String, count: Int) {
        activeTag = tag.lowercased()
        videoCount = count
    }
    
    mutating func clear() {
        activeTag = nil
        videoCount = 0
        isFollowing = false
    }
}

