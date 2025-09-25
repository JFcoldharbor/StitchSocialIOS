//
//  EngagementProtocols.swift
//  StitchSocial
//
//  Layer 2: Protocols - Engagement System Type Definitions
//  Dependencies: Layer 1 (Foundation, UserTier, InteractionType)
//  Defines all engagement-related protocols, enums, and data structures
//  Used by: EngagementCoordinator (Layer 6), Business Logic (Layer 5)
//

import Foundation

// MARK: - Progressive Tapping Results

/// Result of progressive tapping interaction
struct TapResult: Codable {
    let isComplete: Bool
    let milestone: TapMilestone?
    let tapsRemaining: Int
    
    init(isComplete: Bool, milestone: TapMilestone? = nil, tapsRemaining: Int) {
        self.isComplete = isComplete
        self.milestone = milestone
        self.tapsRemaining = tapsRemaining
    }
}

/// Progressive tapping milestones for user feedback
enum TapMilestone: String, CaseIterable, Codable {
    case quarter = "quarter"        // 25% progress
    case half = "half"             // 50% progress
    case threeQuarters = "three_quarters" // 75% progress
    case almostDone = "almost_done" // 90% progress
    case complete = "complete"      // 100% progress
    
    var displayName: String {
        switch self {
        case .quarter: return "Keep Going!"
        case .half: return "Halfway There!"
        case .threeQuarters: return "Almost Done!"
        case .almostDone: return "So Close!"
        case .complete: return "Complete!"
        }
    }
    
    var progressThreshold: Double {
        switch self {
        case .quarter: return 0.25
        case .half: return 0.5
        case .threeQuarters: return 0.75
        case .almostDone: return 0.9
        case .complete: return 1.0
        }
    }
}

// MARK: - Visual Feedback Types

/// Animation types for engagement feedback
enum AnimationType: String, CaseIterable, Codable {
    case tapProgress = "tap_progress"
    case tapMilestone = "tap_milestone"
    case tapComplete = "tap_complete"
    case reward = "reward"
    case hypeExplosion = "hype_explosion"
    case coolRipple = "cool_ripple"
    case tierUpgrade = "tier_upgrade"
    case none = "none"
    
    var displayName: String {
        switch self {
        case .tapProgress: return "Tap Progress"
        case .tapMilestone: return "Milestone"
        case .tapComplete: return "Complete"
        case .reward: return "Reward"
        case .hypeExplosion: return "Hype!"
        case .coolRipple: return "Cool"
        case .tierUpgrade: return "Tier Up!"
        case .none: return "None"
        }
    }
    
    var duration: TimeInterval {
        switch self {
        case .tapProgress: return 0.3
        case .tapMilestone: return 1.5
        case .tapComplete: return 2.0
        case .reward: return 3.0
        case .hypeExplosion: return 1.0
        case .coolRipple: return 0.8
        case .tierUpgrade: return 4.0
        case .none: return 0.0
        }
    }
}

/// Reward types for engagement achievements
enum EngagementRewardType: String, CaseIterable, Codable {
    case cloutBonus = "clout_bonus"
    case streakBonus = "streak_bonus"
    case firstHype = "first_hype"
    case milestone = "milestone"
    case tierProgress = "tier_progress"
    case specialBadge = "special_badge"
    case viralVideo = "viral_video"
    case none = "none"
    
    var displayName: String {
        switch self {
        case .cloutBonus: return "Clout Bonus!"
        case .streakBonus: return "Streak Bonus!"
        case .firstHype: return "First Hype!"
        case .milestone: return "Milestone!"
        case .tierProgress: return "Tier Progress!"
        case .specialBadge: return "Badge Earned!"
        case .viralVideo: return "Gone Viral!"
        case .none: return ""
        }
    }
    
    var iconName: String {
        switch self {
        case .cloutBonus: return "star.fill"
        case .streakBonus: return "flame.fill"
        case .firstHype: return "heart.fill"
        case .milestone: return "trophy.fill"
        case .tierProgress: return "arrow.up.circle.fill"
        case .specialBadge: return "shield.fill"
        case .viralVideo: return "bolt.fill"
        case .none: return ""
        }
    }
}

// MARK: - Analytics Data Structures

/// Engagement statistics for analytics
struct EngagementStats: Codable {
    var totalInteractions: Int
    var averageEngagementRatio: Double
    var mostActiveVideoID: String?
    var topEngagementHour: Int
    var dailyEngagementTarget: Int
    var currentStreak: Int
    
    init(
        totalInteractions: Int = 0,
        averageEngagementRatio: Double = 0.0,
        mostActiveVideoID: String? = nil,
        topEngagementHour: Int = 12,
        dailyEngagementTarget: Int = 50,
        currentStreak: Int = 0
    ) {
        self.totalInteractions = totalInteractions
        self.averageEngagementRatio = averageEngagementRatio
        self.mostActiveVideoID = mostActiveVideoID
        self.topEngagementHour = topEngagementHour
        self.dailyEngagementTarget = dailyEngagementTarget
        self.currentStreak = currentStreak
    }
}

/// Individual engagement interaction record
struct EngagementInteraction: Codable, Identifiable {
    let id: String
    let videoID: String
    let type: InteractionType
    let timestamp: Date
    let cloutGain: Int
    let hypeScore: Double
    
    init(
        id: String,
        videoID: String,
        type: InteractionType,
        timestamp: Date,
        cloutGain: Int,
        hypeScore: Double
    ) {
        self.id = id
        self.videoID = videoID
        self.type = type
        self.timestamp = timestamp
        self.cloutGain = cloutGain
        self.hypeScore = hypeScore
    }
}

/// Session-level engagement metrics
struct SessionMetrics: Codable {
    var totalInteractions: Int
    var totalCloutGained: Int
    var hypesGiven: Int
    var coolsGiven: Int
    var videosViewed: Int
    var repliesCreated: Int
    var sharesCompleted: Int
    var sessionStartTime: Date
    var lastInteractionTime: Date?
    
    init() {
        self.totalInteractions = 0
        self.totalCloutGained = 0
        self.hypesGiven = 0
        self.coolsGiven = 0
        self.videosViewed = 0
        self.repliesCreated = 0
        self.sharesCompleted = 0
        self.sessionStartTime = Date()
        self.lastInteractionTime = nil
    }
    
    var sessionDuration: TimeInterval {
        return Date().timeIntervalSince(sessionStartTime)
    }
    
    var interactionsPerMinute: Double {
        let minutes = sessionDuration / 60.0
        return minutes > 0 ? Double(totalInteractions) / minutes : 0.0
    }
}

/// Calculation results for engagement processing
struct EngagementCalculations: Codable {
    let cloutGain: Int
    let newHypeCount: Int
    let newCoolCount: Int
    let newViewCount: Int
    let newTemperature: String
    let newEngagementRatio: Double
    let hypeScore: Double
    
    init(
        cloutGain: Int,
        newHypeCount: Int,
        newCoolCount: Int,
        newViewCount: Int,
        newTemperature: String,
        newEngagementRatio: Double,
        hypeScore: Double
    ) {
        self.cloutGain = cloutGain
        self.newHypeCount = newHypeCount
        self.newCoolCount = newCoolCount
        self.newViewCount = newViewCount
        self.newTemperature = newTemperature
        self.newEngagementRatio = newEngagementRatio
        self.hypeScore = hypeScore
    }
}
