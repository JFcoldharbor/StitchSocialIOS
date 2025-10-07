//
//  EngagementTypes.swift
//  StitchSocial
//
//  Layer 2: Protocols - Core Engagement Data Structures WITH FIXED TAP PROGRESSION
//  Dependencies: Foundation, EngagementConfig (Layer 1) ONLY
//  Features: All engagement types defined ONCE - no duplicates, FIXED TAP COUNTING
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
    case founderExplosion   // First founder tap = massive hype explosion
    case standardHype       // Normal hype animation
    case standardCool       // Normal cool animation
    case tapProgress        // Progressive tap feedback
    case tapMilestone       // Milestone reached
    case trollWarning       // Warning animation for potential trolling
    case tierMilestone      // Special tier-based effects
    case none
    
    var displayName: String {
        switch self {
        case .founderExplosion: return "Founder Boost!"
        case .standardHype: return "Hype!"
        case .standardCool: return "Cool"
        case .tapProgress: return "Tapping..."
        case .tapMilestone: return "Milestone!"
        case .trollWarning: return "Warning"
        case .tierMilestone: return "Tier Up!"
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

// MARK: - VIDEO ENGAGEMENT STATE WITH FIXED TAP PROGRESSION

/// Per-video per-user engagement state - SINGLE DEFINITION WITH WORKING TAP LOGIC
struct VideoEngagementState: Codable {
    let videoID: String
    let userID: String
    var totalEngagements: Int           // Combined hype + cool
    var hypeEngagements: Int            // Hype only count
    var coolEngagements: Int            // Cool only count
    var hypeCurrentTaps: Int            // Current tap progress for hype
    var hypeRequiredTaps: Int           // Required taps for next hype
    var coolCurrentTaps: Int            // Current tap progress for cool
    var coolRequiredTaps: Int           // Required taps for next cool
    var lastEngagementAt: Date
    var createdAt: Date
    
    init(videoID: String, userID: String, createdAt: Date = Date()) {
        self.videoID = videoID
        self.userID = userID
        self.totalEngagements = 0
        self.hypeEngagements = 0
        self.coolEngagements = 0
        self.hypeCurrentTaps = 0
        self.hypeRequiredTaps = 1
        self.coolCurrentTaps = 0
        self.coolRequiredTaps = 1
        self.lastEngagementAt = Date()
        self.createdAt = createdAt
    }
    
    // MARK: - FIXED TAP METHODS
    
    /// Add tap for hype - returns true if complete - FIXED VERSION
    mutating func addHypeTap() -> Bool {
        hypeCurrentTaps += 1
        lastEngagementAt = Date()
        
        let isComplete = hypeCurrentTaps >= hypeRequiredTaps
        return isComplete
    }
    
    /// Add tap for cool - returns true if complete - FIXED VERSION
    mutating func addCoolTap() -> Bool {
        coolCurrentTaps += 1
        lastEngagementAt = Date()
        
        let isComplete = coolCurrentTaps >= coolRequiredTaps
        return isComplete
    }
    
    /// Complete hype engagement and reset for next - FIXED VERSION
    mutating func completeHypeEngagement() {
        totalEngagements += 1
        hypeEngagements += 1
        hypeCurrentTaps = 0  // Reset current taps
        
        // Calculate next requirement using proper formula
        let nextEngagementNumber = hypeEngagements + 1
        hypeRequiredTaps = calculateProgressiveTaps(engagementNumber: nextEngagementNumber)
        
        lastEngagementAt = Date()
    }
    
    /// Complete cool engagement and reset for next - FIXED VERSION
    mutating func completeCoolEngagement() {
        totalEngagements += 1
        coolEngagements += 1
        coolCurrentTaps = 0  // Reset current taps
        
        // Calculate next requirement using proper formula
        let nextEngagementNumber = coolEngagements + 1
        coolRequiredTaps = calculateProgressiveTaps(engagementNumber: nextEngagementNumber)
        
        lastEngagementAt = Date()
    }
    
    // MARK: - Computed Properties
    
    /// Current hype tap progress (0.0 to 1.0)
    var hypeProgress: Double {
        guard hypeRequiredTaps > 0 else { return 0.0 }
        return min(1.0, Double(hypeCurrentTaps) / Double(hypeRequiredTaps))
    }
    
    /// Current cool tap progress (0.0 to 1.0)
    var coolProgress: Double {
        guard coolRequiredTaps > 0 else { return 0.0 }
        return min(1.0, Double(coolCurrentTaps) / Double(coolRequiredTaps))
    }
    
    /// Remaining taps needed for hype completion
    var hypeRemainingTaps: Int {
        return max(0, hypeRequiredTaps - hypeCurrentTaps)
    }
    
    /// Remaining taps needed for cool completion
    var coolRemainingTaps: Int {
        return max(0, coolRequiredTaps - coolCurrentTaps)
    }
    
    /// Check if next hype engagement will be instant (first 4)
    var isNextHypeInstant: Bool {
        return hypeEngagements < 4 // EngagementConfig.instantEngagementThreshold
    }
    
    /// Check if next cool engagement will be instant (first 4)
    var isNextCoolInstant: Bool {
        return coolEngagements < 4 // EngagementConfig.instantEngagementThreshold
    }
    
    /// Time since last engagement
    var timeSinceLastEngagement: TimeInterval {
        return Date().timeIntervalSince(lastEngagementAt)
    }
    
    /// Check if state has expired (no activity for 24 hours)
    var isExpired: Bool {
        return timeSinceLastEngagement > 86400 // 24 hours
    }
    
    // MARK: - PROGRESSIVE TAP CALCULATION (Temporary - matches EngagementCalculator)
    
    /// Calculate progressive taps needed for specific engagement number
    private func calculateProgressiveTaps(engagementNumber: Int) -> Int {
        // Engagements 1-4 are instant (1 tap)
        if engagementNumber <= 4 {
            return 1
        }
        
        // Progressive tapping starts at 5th engagement
        // 5th = 2 taps, 6th = 4 taps, 7th = 8 taps, 8th = 16 taps, etc.
        let progressiveIndex = engagementNumber - 5
        let requirement = 2 * Int(pow(2.0, Double(progressiveIndex)))
        
        // Cap at maximum to prevent infinite progression
        return min(requirement, 256) // Max 256 taps
    }
}

// MARK: - HELPER STRUCTURES

/// Current user hype rating information
struct HypeRatingState: Codable {
    var percent: Double
    var points: Double
    var lastUpdate: Date
    
    init(percent: Double = 25.0) {
        self.percent = percent
        self.points = (percent / 100.0) * 15000.0 // EngagementConfig.maxHypeRatingPoints
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
    let hypeRatingCost: Double
    let createdAt: Date
    
    init(videoID: String, userID: String, type: String, cloutAwarded: Int, hypeRatingCost: Double) {
        self.id = "\(videoID)_\(userID)_\(type)_\(Int(Date().timeIntervalSince1970))"
        self.videoID = videoID
        self.userID = userID
        self.type = type
        self.cloutAwarded = cloutAwarded
        self.hypeRatingCost = hypeRatingCost
        self.createdAt = Date()
    }
}
