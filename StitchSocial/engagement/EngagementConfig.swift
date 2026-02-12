//
//  EngagementConfig.swift
//  StitchSocial
//
//  Layer 1: Foundation - Engagement System Configuration
//  Dependencies: UserTier (Layer 1) ONLY
//  Features: All engagement constants, tier costs, progressive tapping settings
//  UPDATED: Long press burst system - regular tap = +1, long press = full tier multiplier
//  UPDATED: Hybrid clout system with tier-based caps, visual hype multipliers, and anti-spam
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
    
    // MARK: - 🆕 Long Press Burst System
    
    /// Regular tap: ALL tiers give +1 visual hype (cheap, standard engagement)
    static let regularTapVisualHype = 1
    
    /// Burst multiplier: ONLY premium tiers, activated by long press
    /// This is the full tier multiplier - the "big" engagement
    static let tierBurstMultiplier: [UserTier: Int] = [
        .founder: 20,       // Long press = +20 visual hypes
        .topCreator: 15,    // Long press = +15 visual hypes
        .legendary: 12,     // Long press = +12 visual hypes
        .partner: 10,       // Long press = +10 visual hypes
        .elite: 8,          // Long press = +8 visual hypes
        .ambassador: 6,     // Long press = +6 visual hypes
        .influencer: 1,     // No burst benefit (same as regular)
        .veteran: 1,        // No burst benefit
        .rising: 1,         // No burst benefit
        .rookie: 1          // No burst benefit
    ]
    
    /// Burst clout multiplier: long press awards more clout than regular tap
    static let burstCloutMultiplier = 2.0
    
    /// Hype rating cost multiplier for burst engagements (costs more to burst)
    static let burstHypeCostMultiplier = 3.0
    
    /// Minimum long press duration to activate burst (seconds)
    static let longPressDuration: TimeInterval = 0.5
    
    /// Premium tiers that benefit from long press burst
    static let burstEligibleTiers: Set<UserTier> = [
        .founder, .topCreator, .legendary,
        .partner, .elite, .ambassador
    ]
    
    // MARK: - OLD: Visual Hype Multipliers (REPLACED by burst system)
    // Kept for backward compatibility in validation - use getVisualHypeMultiplier(for:isBurst:) instead
    
    /// Visual hypes added per completed engagement (tier-based, EVERY tap)
    /// DEPRECATED: Use regularTapVisualHype for regular taps, tierBurstMultiplier for long press
    static let tierVisualHypeMultiplier: [UserTier: Int] = [
        .founder: 20,       // +20 visual hypes per tap
        .topCreator: 15,    // +15 visual hypes per tap
        .legendary: 12,     // +12 visual hypes per tap
        .partner: 10,       // +10 visual hypes per tap
        .elite: 8,          // +8 visual hypes per tap
        .ambassador: 6,     // +6 visual hypes per tap
        .influencer: 1,     // +1 visual hype per tap
        .veteran: 1,        // +1 visual hype per tap
        .rising: 1,         // +1 visual hype per tap
        .rookie: 1          // +1 visual hype per tap
    ]
    
    // MARK: - Tier-Based Clout System (Decoupled from Visual Hypes)
    
    /// Base clout awarded per REGULAR tap (before multipliers)
    static let tierBaseClout: [UserTier: Int] = [
        .founder: 5,        // 5 clout per regular tap (was 50 - REDUCED)
        .topCreator: 4,     // 4 clout per regular tap (was 40 - REDUCED)
        .legendary: 3,      // 3 clout per regular tap (was 30 - REDUCED)
        .partner: 3,        // 3 clout per regular tap (was 25 - REDUCED)
        .elite: 2,          // 2 clout per regular tap (was 20 - REDUCED)
        .ambassador: 2,     // 2 clout per regular tap (was 15 - REDUCED)
        .influencer: 5,     // 5 clout (unchanged - no burst path)
        .veteran: 5,        // 5 clout (unchanged)
        .rising: 5,         // 5 clout (unchanged)
        .rookie: 5          // 5 clout (unchanged)
    ]
    
    /// Burst clout awarded per LONG PRESS (premium tiers only)
    static let tierBurstClout: [UserTier: Int] = [
        .founder: 50,       // Full 50 clout on burst
        .topCreator: 40,    // Full 40 clout on burst
        .legendary: 30,     // Full 30 clout on burst
        .partner: 25,       // Full 25 clout on burst
        .elite: 20,         // Full 20 clout on burst
        .ambassador: 15,    // Full 15 clout on burst
        .influencer: 5,     // Same as regular (no burst)
        .veteran: 5,        // Same as regular
        .rising: 5,         // Same as regular
        .rookie: 5          // Same as regular
    ]
    
    /// Maximum clout a single user can give to one video (tier-based caps)
    static let maxCloutPerUserPerVideo: [UserTier: Int] = [
        .founder: 500,      // Founder can give max 500 clout to one video
        .topCreator: 400,   // Top Creator can give max 400 clout
        .legendary: 350,    // Legendary can give max 350 clout
        .partner: 300,      // Partner can give max 300 clout
        .elite: 250,        // Elite can give max 250 clout
        .ambassador: 200,   // Ambassador can give max 200 clout
        .influencer: 100,   // Influencer can give max 100 clout
        .veteran: 75,       // Veteran can give max 75 clout
        .rising: 50,        // Rising can give max 50 clout
        .rookie: 25         // Rookie can give max 25 clout
    ]
    
    /// First tap bonus multiplier for premium tiers (Ambassador → Founder)
    /// ONLY applies on burst (long press) first engagement
    static let firstTapBonusMultiplier = 2.0
    
    /// Premium tiers that receive first tap bonus (on burst only)
    static let premiumTiersWithFirstTapBonus: Set<UserTier> = [
        .founder, .topCreator, .legendary,
        .partner, .elite, .ambassador
    ]
    
    /// Diminishing returns multiplier by tap number (anti-spam)
    static func getDiminishingMultiplier(tapNumber: Int) -> Double {
        switch tapNumber {
        case 1...3: return 1.0   // 100% - Full value for first 3 taps
        case 4: return 0.9       // 90%
        case 5: return 0.8       // 80%
        case 6: return 0.7       // 70%
        case 7: return 0.6       // 60%
        case 8: return 0.5       // 50%
        default: return 0.4      // 40% - Floor for tap 9+
        }
    }
    
    // MARK: - Engagement Thresholds & Caps
    
    /// Maximum total engagements per user per video (universal cap)
    static let maxEngagementsPerUserPerVideo = 20
    
    /// Maximum total clout one video can earn (prevents runaway viral content)
    static let maxTotalCloutPerVideo = 10000
    
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
    
    // MARK: - Helper Methods
    
    /// Get hype cost for specific tier
    static func getHypeCost(for tier: UserTier) -> Double {
        return tierHypeCosts[tier] ?? 1.0
    }
    
    /// Get hype cost with burst modifier
    static func getHypeCost(for tier: UserTier, isBurst: Bool) -> Double {
        let baseCost = getHypeCost(for: tier)
        return isBurst ? baseCost * burstHypeCostMultiplier : baseCost
    }
    
    /// Get visual hype multiplier for specific tier and engagement type
    /// Regular tap = +1 for everyone. Burst (long press) = full tier multiplier.
    static func getVisualHypeMultiplier(for tier: UserTier, isBurst: Bool = false) -> Int {
        if isBurst && burstEligibleTiers.contains(tier) {
            return tierBurstMultiplier[tier] ?? 1
        }
        return regularTapVisualHype
    }
    
    /// Get base clout for specific tier and engagement type
    static func getBaseClout(for tier: UserTier, isBurst: Bool = false) -> Int {
        if isBurst && burstEligibleTiers.contains(tier) {
            return tierBurstClout[tier] ?? 5
        }
        return tierBaseClout[tier] ?? 5
    }
    
    /// Get max clout per user per video for specific tier
    static func getMaxCloutPerUserPerVideo(for tier: UserTier) -> Int {
        return maxCloutPerUserPerVideo[tier] ?? 25
    }
    
    /// Check if tier gets first tap bonus (burst only)
    static func hasFirstTapBonus(tier: UserTier) -> Bool {
        return premiumTiersWithFirstTapBonus.contains(tier)
    }
    
    /// Check if tier is eligible for burst engagement
    static func isBurstEligible(tier: UserTier) -> Bool {
        return burstEligibleTiers.contains(tier)
    }
    
    /// Calculate clout with all modifiers applied
    static func calculateClout(
        tier: UserTier,
        tapNumber: Int,
        isFirstEngagement: Bool,
        currentCloutFromUser: Int,
        isBurst: Bool = false
    ) -> Int {
        // Get base clout for tier (regular vs burst)
        var clout = getBaseClout(for: tier, isBurst: isBurst)
        
        // Apply first tap bonus if eligible (BURST ONLY)
        if isFirstEngagement && isBurst && hasFirstTapBonus(tier: tier) {
            clout = Int(Double(clout) * firstTapBonusMultiplier)
        }
        
        // Apply diminishing returns based on tap number
        let diminishingMultiplier = getDiminishingMultiplier(tapNumber: tapNumber)
        clout = Int(Double(clout) * diminishingMultiplier)
        
        // Check if adding this clout would exceed per-user-per-video cap
        let maxAllowed = getMaxCloutPerUserPerVideo(for: tier)
        let remainingAllowance = max(0, maxAllowed - currentCloutFromUser)
        clout = min(clout, remainingAllowance)
        
        return max(0, clout) // Never negative
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
    
    // MARK: - DEPRECATED (Old System - Kept for Migration)
    
    /// OLD: Clout reward given to video creator by user tier
    /// DEPRECATED: Use tierBaseClout instead
    static let tierCloutRewards: [UserTier: Int] = [
        .rookie: 5,
        .rising: 5,
        .veteran: 5,
        .influencer: 5,
        .elite: 20,
        .partner: 25,
        .legendary: 30,
        .topCreator: 40,
        .founder: 50
    ]
    
    /// OLD: Get clout reward for specific tier
    /// DEPRECATED: Use getBaseClout instead
    static func getCloutReward(for tier: UserTier) -> Int {
        return getBaseClout(for: tier)
    }
    
    /// OLD: Regular clout threshold (every 5 hypes awards clout)
    /// DEPRECATED: New system doesn't use milestone thresholds
    static let regularCloutThreshold = 5
    
    /// OLD: Founder first tap hype multiplier
    /// DEPRECATED: Use tierBurstMultiplier[.founder] instead
    static let founderFirstTapMultiplier = 20
    
    /// OLD: Founder first tap clout bonus
    /// DEPRECATED: Use calculateClout with first tap bonus instead
    static let founderFirstTapCloutBonus = 100
    
    /// OLD: Founder follow-up tap clout bonus
    /// DEPRECATED: No longer used
    static let founderFollowUpCloutBonus = 20
}

// MARK: - Validation

extension EngagementConfig {
    
    /// Validate engagement configuration on app launch
    static func validate() -> String {
        var report = "✅ ENGAGEMENT CONFIG VALIDATION (BURST SYSTEM)\n\n"
        
        // Check all tiers have values
        let allTiers: [UserTier] = [.rookie, .rising, .veteran, .influencer,
                                     .ambassador, .elite, .partner, .legendary, .topCreator, .founder]
        
        for tier in allTiers {
            let regularHype = getVisualHypeMultiplier(for: tier, isBurst: false)
            let burstHype = getVisualHypeMultiplier(for: tier, isBurst: true)
            let regularClout = getBaseClout(for: tier, isBurst: false)
            let burstClout = getBaseClout(for: tier, isBurst: true)
            let maxClout = getMaxCloutPerUserPerVideo(for: tier)
            let burstEligible = isBurstEligible(tier: tier)
            
            report += "→ \(tier.rawValue.capitalized):\n"
            report += "  Regular Tap: +\(regularHype) hype, \(regularClout) clout\n"
            report += "  Long Press:  +\(burstHype) hype, \(burstClout) clout\n"
            report += "  Cap: \(maxClout) max/video\n"
            report += "  Burst Eligible: \(burstEligible ? "YES" : "NO")\n\n"
        }
        
        report += "🎯 Anti-Spam Settings:\n"
        report += "→ Max taps/user/video: \(maxEngagementsPerUserPerVideo)\n"
        report += "→ Max clout/video: \(maxTotalCloutPerVideo)\n"
        report += "→ Burst hype cost: \(burstHypeCostMultiplier)x regular\n"
        report += "→ Long press duration: \(longPressDuration)s\n"
        report += "→ Diminishing starts: Tap 4 (90%)\n"
        report += "→ Diminishing floor: Tap 9+ (40%)\n\n"
        
        report += "✅ Configuration Valid!\n"
        
        return report
    }
}
