//
//  EngagementTypes.swift
//  StitchSocial
//
//  Layer 2: Protocols - Core Engagement Data Structures
//  Dependencies: Foundation, EngagementConfig (Layer 1) ONLY
//  Features: All engagement types defined, user-specific clout tracking for caps
//  UPDATED: Added clout tracking per user for anti-spam system
//

import Foundation

// MARK: - ENGAGEMENT RESULT (Primary Structure)

/// Result of engagement processing - SINGLE AUTHORITATIVE DEFINITION
struct EngagementResult {
    let success: Bool
    let cloutAwarded: Int
    let newHypeCount: Int
    let newCoolCount: Int
    let isFounderFirstTap: Bool
    let visualHypeIncrement: Int
    let visualCoolIncrement: Int
    let animationType: EngagementAnimationType
    let message: String
}

/// Animation types for different engagement results
enum EngagementAnimationType: String, CaseIterable, Codable {
    case founderExplosion   // First tap for premium tiers (Ambassador → Founder)
    case standardHype       // Normal hype animation
    case standardCool       // Normal cool animation
    case tapProgress        // Progressive tap feedback
    case tapMilestone       // Milestone reached
    case trollWarning       // Warning animation for potential trolling
    case tierMilestone      // Special tier-based effects
    case cloutCapReached    // User hit their clout cap for this video
    case none
    
    var displayName: String {
        switch self {
        case .founderExplosion: return "Premium Boost!"
        case .standardHype: return "Hype!"
        case .standardCool: return "Cool"
        case .tapProgress: return "Tapping..."
        case .tapMilestone: return "Milestone!"
        case .trollWarning: return "Warning"
        case .tierMilestone: return "Tier Up!"
        case .cloutCapReached: return "Cap Reached"
        case .none: return ""
        }
    }
}

// MARK: - PROGRESSIVE TAPPING RESULT

/// Result of progressive tapping interaction - SINGLE DEFINITION
struct TapResult: Codable {
    let isComplete: Bool
    let progress: Double        // 0.0 to 1.0
    let milestone: TapMilestone?
    let tapsRemaining: Int
    
    init(isComplete: Bool, progress: Double = 0.0, milestone: TapMilestone? = nil, tapsRemaining: Int) {
        self.isComplete = isComplete
        self.progress = progress
        self.milestone = milestone
        self.tapsRemaining = tapsRemaining
    }
}

/// Progressive tapping milestones for user feedback - SINGLE DEFINITION
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

// MARK: - VIDEO ENGAGEMENT STATE WITH USER-SPECIFIC CLOUT TRACKING

/// Per-video per-user engagement state - INSTANT ENGAGEMENTS
struct VideoEngagementState: Codable {
    let videoID: String
    let userID: String
    var totalEngagements: Int           // Combined hype + cool
    var hypeEngagements: Int            // Hype only count
    var coolEngagements: Int            // Cool only count
    var lastEngagementAt: Date
    var createdAt: Date
    
    // Clout tracking for anti-spam
    var totalCloutGiven: Int = 0
    var engagementHistory: [EngagementRecord] = []
    
    init(videoID: String, userID: String, createdAt: Date = Date()) {
        self.videoID = videoID
        self.userID = userID
        self.totalEngagements = 0
        self.hypeEngagements = 0
        self.coolEngagements = 0
        self.lastEngagementAt = Date()
        self.createdAt = createdAt
    }
    
    // MARK: - INSTANT ENGAGEMENT METHODS
    
    /// Add hype engagement (instant)
    mutating func addHypeEngagement() {
        totalEngagements += 1
        hypeEngagements += 1
        lastEngagementAt = Date()
    }
    
    /// Add cool engagement (instant)
    mutating func addCoolEngagement() {
        totalEngagements += 1
        coolEngagements += 1
        lastEngagementAt = Date()
    }
    
    /// Record clout awarded for an engagement
    mutating func recordCloutAwarded(_ clout: Int, isHype: Bool) {
        totalCloutGiven += clout
        
        let record = EngagementRecord(
            timestamp: Date(),
            type: isHype ? .hype : .cool,
            cloutAwarded: clout,
            tapNumber: isHype ? hypeEngagements : coolEngagements
        )
        
        engagementHistory.append(record)
    }
    
    // MARK: - Computed Properties
    
    /// Check if user has hit their clout cap for this video
    func hasHitCloutCap(for tier: UserTier) -> Bool {
        let maxAllowed = EngagementConfig.getMaxCloutPerUserPerVideo(for: tier)
        return totalCloutGiven >= maxAllowed
    }
    
    /// Get remaining clout allowance for this user on this video
    func getRemainingCloutAllowance(for tier: UserTier) -> Int {
        let maxAllowed = EngagementConfig.getMaxCloutPerUserPerVideo(for: tier)
        return max(0, maxAllowed - totalCloutGiven)
    }
    
    /// Check if user has hit engagement cap
    func hasHitEngagementCap() -> Bool {
        return totalEngagements >= EngagementConfig.maxEngagementsPerUserPerVideo
    }
    
    /// Time since last engagement
    var timeSinceLastEngagement: TimeInterval {
        return Date().timeIntervalSince(lastEngagementAt)
    }
    
    /// Check if state has expired (no activity for 24 hours)
    var isExpired: Bool {
        return timeSinceLastEngagement > 86400 // 24 hours
    }
}

// MARK: - NEW: Engagement Record

/// Individual engagement record for tracking
struct EngagementRecord: Codable {
    let timestamp: Date
    let type: EngagementInteractionType
    let cloutAwarded: Int
    let tapNumber: Int
}

/// Type of engagement interaction
enum EngagementInteractionType: String, Codable {
    case hype
    case cool
}

// MARK: - HELPER STRUCTURES

/// Current user hype rating information
struct HypeRatingState: Codable {
    var percent: Double
    var points: Double
    var lastUpdate: Date
    
    init(percent: Double = 25.0) {
        self.percent = percent
        self.points = (percent / 100.0) * 15000.0
        self.lastUpdate = Date()
    }
}

/// Engagement interaction record for Firebase
struct EngagementInteraction: Codable {
    let id: String
    let videoID: String
    let userID: String
    let type: String // "hype" or "cool"
    let cloutAwarded: Int
    let visualHypesAdded: Int  // NEW: Track visual hypes separately
    let hypeRatingCost: Double
    let createdAt: Date
    
    init(
        videoID: String,
        userID: String,
        type: String,
        cloutAwarded: Int,
        visualHypesAdded: Int,
        hypeRatingCost: Double
    ) {
        self.id = "\(videoID)_\(userID)_\(type)_\(Int(Date().timeIntervalSince1970))"
        self.videoID = videoID
        self.userID = userID
        self.type = type
        self.cloutAwarded = cloutAwarded
        self.visualHypesAdded = visualHypesAdded
        self.hypeRatingCost = hypeRatingCost
        self.createdAt = Date()
    }
}

// MARK: - Clout Cap Status

/// Status of clout caps for UI display
struct CloutCapStatus {
    let userCloutGiven: Int
    let userCloutCap: Int
    let videoTotalClout: Int
    let videoCloutCap: Int
    
    var userPercentage: Double {
        guard userCloutCap > 0 else { return 0.0 }
        return Double(userCloutGiven) / Double(userCloutCap)
    }
    
    var videoPercentage: Double {
        guard videoCloutCap > 0 else { return 0.0 }
        return Double(videoTotalClout) / Double(videoCloutCap)
    }
    
    var userIsNearCap: Bool {
        return userPercentage >= 0.8
    }
    
    var videoIsNearCap: Bool {
        return videoPercentage >= 0.8
    }
    
    var userHitCap: Bool {
        return userCloutGiven >= userCloutCap
    }
    
    var videoHitCap: Bool {
        return videoTotalClout >= videoCloutCap
    }
}
