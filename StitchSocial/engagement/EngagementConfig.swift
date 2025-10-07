//
//  EngagementConfig.swift
//  StitchSocial
//
//  Created by James Garmon on 10/2/25.
//


//
//  EngagementConfig.swift
//  StitchSocial
//
//  Layer 1: Foundation - Engagement System Configuration
//  Dependencies: UserTier (Layer 1) ONLY
//  Features: All engagement constants, tier costs, progressive tapping settings
//

import Foundation

/// Core configuration for engagement system
struct EngagementConfig {
    
    // MARK: - Progressive Tapping Configuration
    
    /// First 4 engagements are instant (1 tap each)
    static let instantEngagementThreshold = 4
    
    /// Starting requirement for progressive tapping (5th engagement = 2 taps)
    static let firstProgressiveTaps = 2
    
    /// Maximum tap requirement to prevent infinite progression
    static let maxTapRequirement = 256
    
    // MARK: - Hype Rating Configuration
    
    /// Maximum hype rating points
    static let maxHypeRatingPoints = 15000.0
    
    /// Starting hype rating for new users (25%)
    static let newUserHypePercent = 25.0
    
    /// Passive regeneration rate per hour (0.5% per hour)
    static let passiveRegenPerHour = 0.5
    
    /// Low hype warning threshold (below 20%)
    static let lowHypeWarningThreshold = 20.0
    
    /// Critical hype threshold (below 10%)
    static let criticalHypeThreshold = 10.0
    
    // MARK: - Tier-Based Hype Costs (as percentages)
    
    /// Hype rating cost by user tier
    static let tierHypeCosts: [UserTier: Double] = [
        .rookie: 1.0,       // 1% per hype
        .rising: 0.67,      // 0.67% per hype
        .veteran: 0.5,      // 0.5% per hype
        .influencer: 0.33,  // 0.33% per hype
        .elite: 0.2,        // 0.2% per hype
        .partner: 0.13,     // 0.13% per hype
        .legendary: 0.1,    // 0.1% per hype
        .topCreator: 0.067, // 0.067% per hype
        .founder: 0.033     // 0.033% per hype (lowest cost)
    ]
    
    // MARK: - Tier-Based Clout Rewards
    
    /// Clout reward given to video creator by user tier
    static let tierCloutRewards: [UserTier: Int] = [
        .rookie: 1,         // 1 clout per hype
        .rising: 3,         // 3 clout per hype
        .veteran: 10,       // 10 clout per hype
        .influencer: 25,    // 25 clout per hype
        .elite: 50,         // 50 clout per hype
        .partner: 100,      // 100 clout per hype
        .legendary: 250,    // 250 clout per hype
        .topCreator: 500,   // 500 clout per hype
        .founder: 1000      // 1000 clout per hype (highest reward)
    ]
    
    // MARK: - Engagement Thresholds
    
    /// Regular clout threshold (every 5 hypes awards clout)
    static let regularCloutThreshold = 5
    
    /// Cool engagement penalty (clout deducted from creator)
    static let coolCloutPenalty = -5
    
    /// Maximum cool engagements per hour to prevent trolling
    static let maxCoolsPerHour = 10
    
    /// Maximum cool engagements per day
    static let maxCoolsPerDay = 50
    
    // MARK: - Rate Limiting
    
    /// Minimum time between engagements (seconds)
    static let engagementCooldown: TimeInterval = 0.5
    
    /// Tap processing cooldown (milliseconds)
    static let tapCooldownMS = 100
    
    /// Maximum engagements per minute per user
    static let maxEngagementsPerMinute = 30
    
    // MARK: - Founder Special Rules
    
    /// Founder first tap hype multiplier
    static let founderFirstTapMultiplier = 20
    
    /// Founder first tap clout bonus
    static let founderFirstTapCloutBonus = 200
    
    /// Founder follow-up tap clout bonus
    static let founderFollowUpCloutBonus = 20
    
    // MARK: - Helper Methods
    
    /// Get hype cost for specific tier
    static func getHypeCost(for tier: UserTier) -> Double {
        return tierHypeCosts[tier] ?? 1.0
    }
    
    /// Get clout reward for specific tier
    static func getCloutReward(for tier: UserTier) -> Int {
        return tierCloutRewards[tier] ?? 1
    }
    
    /// Calculate cost for specific engagement number and tier
    static func getCostForEngagement(engagementNumber: Int, userTier: UserTier) -> Double {
        let baseCost = getHypeCost(for: userTier)
        
        // Progressive cost increase for high engagement counts
        if engagementNumber > 10 {
            let multiplier = 1.0 + (Double(engagementNumber - 10) * 0.1)
            return baseCost * multiplier
        }
        
        return baseCost
    }
    
    /// Calculate reward for specific engagement
    static func getRewardForEngagement(engagementNumber: Int, userTier: UserTier) -> Int {
        let baseReward = getCloutReward(for: userTier)
        
        // Bonus for milestone engagements
        if engagementNumber % regularCloutThreshold == 0 {
            return baseReward
        }
        
        return 0 // No clout until threshold reached
    }
}