//
//  RecentUser.swift
//  StitchSocial
//
//  Created by James Garmon on 11/1/25.
//


//
//  LeaderboardModels.swift
//  StitchSocial
//
//  Layer 1: Foundation - Discovery and Leaderboard Data Models
//  Dependencies: NONE (Foundation only)
//  Features: Recent users, hype leaderboard video data
//

import Foundation

// MARK: - Recent User Model

/// Represents a recently joined user for "Just Joined" section
struct RecentUser: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String
    let profileImageURL: String?
    let joinedAt: Date
    let isVerified: Bool
    
    init(
        id: String,
        username: String,
        displayName: String,
        profileImageURL: String? = nil,
        joinedAt: Date,
        isVerified: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.joinedAt = joinedAt
        self.isVerified = isVerified
    }
}

// MARK: - Leaderboard Video Model

/// Represents a video in the hype leaderboard
struct LeaderboardVideo: Identifiable, Codable {
    let id: String
    let title: String
    let creatorID: String
    let creatorName: String
    let thumbnailURL: String?
    let hypeCount: Int
    let coolCount: Int
    let temperature: String
    let createdAt: Date
    
    init(
        id: String,
        title: String,
        creatorID: String,
        creatorName: String,
        thumbnailURL: String? = nil,
        hypeCount: Int,
        coolCount: Int,
        temperature: String,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.thumbnailURL = thumbnailURL
        self.hypeCount = hypeCount
        self.coolCount = coolCount
        self.temperature = temperature
        self.createdAt = createdAt
    }
}

// MARK: - Computed Properties

extension LeaderboardVideo {
    
    /// Net score (hypes - cools)
    var netScore: Int {
        hypeCount - coolCount
    }
    
    /// Temperature emoji
    var temperatureEmoji: String {
        switch temperature.lowercased() {
        case "fire", "blazing": return "🔥"
        case "hot": return "🌶️"
        case "warm": return "☀️"
        case "neutral": return "⚡"
        case "cool": return "❄️"
        case "cold", "frozen": return "🧊"
        default: return "📊"
        }
    }
    
    /// Rank badge color based on position
    func rankColor(position: Int) -> String {
        switch position {
        case 1: return "gold"
        case 2: return "silver"
        case 3: return "bronze"
        default: return "gray"
        }
    }
}

extension RecentUser {
    
    /// Time since joined (formatted)
    var joinedTimeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(joinedAt)
        let hours = Int(interval / 3600)
        
        if hours < 1 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if hours == 1 {
            return "1h ago"
        } else {
            return "\(hours)h ago"
        }
    }
}