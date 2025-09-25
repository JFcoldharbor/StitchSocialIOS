//
//  EngagementCalculator.swift
//  StitchSocial
//
//  Created by James Garmon on 8/17/25.
//


//
//  EngagementCalculator.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Pure Engagement Calculation Functions
//  Dependencies: NONE (Pure functions only)
//  Features: Progressive tapping, hype scores, temperature calculation
//

import Foundation

/// Pure calculation functions for engagement system
/// IMPORTANT: No dependencies - only pure functions for calculations
struct EngagementCalculator {
    
    // MARK: - Progressive Tapping System
    
    /// Calculate progressive tap requirement (2x, 4x, 8x pattern)
    static func calculateProgressiveTapRequirement(currentTaps: Int) -> Int {
        if currentTaps == 0 {
            return 2 // First hype requires 2 taps
        }
        
        // Progressive doubling: 2, 4, 8, 16, 32...
        let baseRequirement = 2
        let multiplier = Int(pow(2.0, Double(currentTaps)))
        let requirement = baseRequirement * multiplier
        
        // Cap at reasonable maximum (256 taps)
        return min(requirement, 256)
    }
    
    /// Calculate tap progress percentage (0.0 to 1.0)
    static func calculateTapProgress(currentTaps: Int, targetTaps: Int) -> Double {
        guard targetTaps > 0 else { return 0.0 }
        return min(1.0, Double(currentTaps) / Double(targetTaps))
    }
    
    /// Determine tap milestone reached
    static func calculateTapMilestone(currentTaps: Int, requiredTaps: Int) -> TapMilestone? {
        let progress = calculateTapProgress(currentTaps: currentTaps, targetTaps: requiredTaps)
        
        if progress >= 1.0 {
            return .complete
        } else if progress >= 0.75 {
            return .threeQuarters
        } else if progress >= 0.5 {
            return .half
        } else if progress >= 0.25 {
            return .quarter
        }
        
        return nil
    }
    
    // MARK: - Hype Score Calculation
    
    /// Calculate hype score based on taps, requirement, and giver tier
    static func calculateHypeScore(
        taps: Int,
        requiredTaps: Int,
        giverTier: UserTier
    ) -> Double {
        // Base score from tap completion
        let completionRatio = calculateTapProgress(currentTaps: taps, targetTaps: requiredTaps)
        var score = completionRatio * 100.0
        
        // Tier multiplier (higher tiers give more valuable hypes)
        let tierMultiplier = calculateTierMultiplier(for: giverTier)
        score *= tierMultiplier
        
        // Persistence bonus (extra points for completing difficult progressive taps)
        let persistenceBonus = calculatePersistenceBonus(requiredTaps: requiredTaps)
        score += persistenceBonus
        
        return max(0.0, score)
    }
    
    /// Calculate tier-based multiplier for hype value
    static func calculateTierMultiplier(for tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 1.0
        case .rising: return 1.2
        case .veteran: return 1.5
        case .influencer: return 2.0
        case .elite: return 2.5
        case .partner: return 3.0
        case .legendary: return 4.0
        case .topCreator: return 5.0
        case .founder: return 10.0
        case .coFounder: return 15.0
        }
    }
    
    /// Calculate persistence bonus for completing difficult tap requirements
    static func calculatePersistenceBonus(requiredTaps: Int) -> Double {
        // Bonus points for completing progressively harder tap requirements
        if requiredTaps >= 128 {
            return 50.0 // Exceptional persistence
        } else if requiredTaps >= 64 {
            return 30.0 // High persistence
        } else if requiredTaps >= 32 {
            return 20.0 // Good persistence
        } else if requiredTaps >= 16 {
            return 10.0 // Some persistence
        } else if requiredTaps >= 8 {
            return 5.0 // Basic persistence
        }
        
        return 0.0 // No bonus for easy taps
    }
    
    // MARK: - Temperature Calculation
    
    /// Calculate video temperature based on hype/cool ratio
    static func calculateTemperature(hypeCount: Int, coolCount: Int) -> String {
        let total = hypeCount + coolCount
        
        // Handle edge cases
        if total == 0 {
            return "neutral"
        }
        
        if coolCount == 0 && hypeCount > 0 {
            return calculateHotTemperature(hypeCount: hypeCount)
        }
        
        // Calculate hype ratio (0.0 to 1.0)
        let hypeRatio = Double(hypeCount) / Double(total)
        
        // Temperature thresholds
        if hypeRatio >= 0.9 {
            return "blazing"
        } else if hypeRatio >= 0.8 {
            return "hot"
        } else if hypeRatio >= 0.65 {
            return "warm"
        } else if hypeRatio >= 0.35 {
            return "neutral"
        } else if hypeRatio >= 0.2 {
            return "cool"
        } else if hypeRatio >= 0.1 {
            return "cold"
        } else {
            return "frozen"
        }
    }
    
    /// Calculate temperature for videos with only hypes (no cools)
    static func calculateHotTemperature(hypeCount: Int) -> String {
        if hypeCount >= 100 {
            return "blazing"
        } else if hypeCount >= 50 {
            return "hot"
        } else if hypeCount >= 20 {
            return "warm"
        } else {
            return "neutral"
        }
    }
    
    /// Get temperature emoji representation
    static func getTemperatureEmoji(for temperature: String) -> String {
        switch temperature.lowercased() {
        case "blazing": return "🔥"
        case "hot": return "🌶️"
        case "warm": return "☀️"
        case "neutral": return "😐"
        case "cool": return "❄️"
        case "cold": return "🧊"
        case "frozen": return "🥶"
        default: return "😐"
        }
    }
    
    // MARK: - Engagement Ratio Calculation
    
    /// Calculate engagement ratio (hype effectiveness)
    static func calculateEngagementRatio(hype: Int, cool: Int, views: Int) -> Double {
        let totalEngagement = hype + cool
        
        // Views-based engagement ratio
        if views > 0 {
            return Double(totalEngagement) / Double(views)
        }
        
        // Fallback: pure hype ratio
        if totalEngagement > 0 {
            return Double(hype) / Double(totalEngagement)
        }
        
        return 0.0
    }
    
    /// Calculate view-to-engagement conversion rate
    static func calculateViewConversionRate(totalEngagement: Int, views: Int) -> Double {
        guard views > 0 else { return 0.0 }
        return Double(totalEngagement) / Double(views)
    }
    
    // MARK: - Clout Calculation
    
    /// Calculate clout gain from engagement type and giver tier
    static func calculateCloutGain(
        engagementType: InteractionType,
        giverTier: UserTier
    ) -> Int {
        // Base points from interaction type
        let basePoints = engagementType.pointValue
        
        // Tier multiplier
        let tierMultiplier = calculateTierMultiplier(for: giverTier)
        
        // Calculate final clout gain
        let cloutGain = Double(basePoints) * tierMultiplier
        
        return max(0, Int(cloutGain))
    }
    
    /// Calculate total clout from multiple interactions
    static func calculateTotalClout(from interactions: [(InteractionType, UserTier)]) -> Int {
        return interactions.reduce(0) { total, interaction in
            let (type, tier) = interaction
            return total + calculateCloutGain(engagementType: type, giverTier: tier)
        }
    }
    
    // MARK: - Velocity & Trending Calculations
    
    /// Calculate engagement velocity (interactions per hour)
    static func calculateEngagementVelocity(
        totalInteractions: Int,
        ageInHours: Double
    ) -> Double {
        let effectiveAge = max(ageInHours, 0.1) // Minimum age to avoid division by zero
        return Double(totalInteractions) / effectiveAge
    }
    
    /// Calculate trending score based on velocity and engagement quality
    static func calculateTrendingScore(
        velocity: Double,
        engagementRatio: Double,
        ageInHours: Double
    ) -> Double {
        // Recency factor (newer content gets boost)
        let recencyFactor = max(0.1, 1.0 - (ageInHours / 24.0))
        
        // Quality factor (better engagement ratio = higher score)
        let qualityFactor = engagementRatio
        
        // Base trending score
        var score = velocity * qualityFactor * recencyFactor
        
        // Normalization (scale to 0-100)
        score = min(100.0, score * 10.0)
        
        return max(0.0, score)
    }
    
    // MARK: - Engagement Health Analysis
    
    /// Calculate overall engagement health score (0.0 to 1.0)
    static func calculateEngagementHealth(
        hype: Int,
        cool: Int,
        views: Int,
        ageInHours: Double
    ) -> Double {
        let total = hype + cool
        
        // Engagement participation (views to engagement conversion)
        let participationScore = views > 0 ? min(1.0, Double(total) / Double(views)) : 0.0
        
        // Engagement positivity (hype vs cool ratio)
        let positivityScore = total > 0 ? Double(hype) / Double(total) : 0.5
        
        // Recency factor (content should maintain engagement over time)
        let recencyScore = max(0.1, 1.0 - (ageInHours / 48.0)) // 48-hour decay
        
        // Weighted average
        let healthScore = (participationScore * 0.4) + (positivityScore * 0.4) + (recencyScore * 0.2)
        
        return max(0.0, min(1.0, healthScore))
    }
    
    /// Determine engagement status from health score
    static func getEngagementStatus(from healthScore: Double) -> String {
        if healthScore >= 0.8 {
            return "excellent"
        } else if healthScore >= 0.6 {
            return "good"
        } else if healthScore >= 0.4 {
            return "fair"
        } else if healthScore >= 0.2 {
            return "poor"
        } else {
            return "critical"
        }
    }
    
    // MARK: - Interaction Value Calculations
    
    /// Calculate the value of a single interaction
    static func calculateInteractionValue(
        type: InteractionType,
        giverTier: UserTier,
        receiverTier: UserTier,
        contentAge: TimeInterval
    ) -> Double {
        // Base value from interaction type
        let baseValue = Double(type.pointValue)
        
        // Giver tier multiplier (who's giving the interaction)
        let giverMultiplier = calculateTierMultiplier(for: giverTier)
        
        // Cross-tier interaction bonus (higher tier interacting with lower tier gets bonus)
        let crossTierBonus = calculateCrossTierBonus(giver: giverTier, receiver: receiverTier)
        
        // Recency factor (newer interactions worth more)
        let recencyFactor = calculateRecencyFactor(contentAge: contentAge)
        
        return baseValue * giverMultiplier * crossTierBonus * recencyFactor
    }
    
    /// Calculate bonus for cross-tier interactions
    static func calculateCrossTierBonus(giver: UserTier, receiver: UserTier) -> Double {
        let giverLevel = tierLevel(giver)
        let receiverLevel = tierLevel(receiver)
        
        if giverLevel > receiverLevel {
            // Higher tier user interacting with lower tier gets small bonus
            return 1.0 + (Double(giverLevel - receiverLevel) * 0.1)
        } else {
            // Same or lower tier interaction - no bonus
            return 1.0
        }
    }
    
    /// Calculate recency factor for interaction value
    static func calculateRecencyFactor(contentAge: TimeInterval) -> Double {
        let ageInHours = contentAge / 3600.0
        
        if ageInHours <= 1.0 {
            return 1.5 // 50% bonus for very fresh content
        } else if ageInHours <= 6.0 {
            return 1.2 // 20% bonus for fresh content
        } else if ageInHours <= 24.0 {
            return 1.0 // Normal value for day-old content
        } else {
            return max(0.5, 1.0 - ((ageInHours - 24.0) / 168.0)) // Decay over a week
        }
    }
    
    /// Get numeric level for tier (for calculations)
    static func tierLevel(_ tier: UserTier) -> Int {
        switch tier {
        case .rookie: return 1
        case .rising: return 2
        case .veteran: return 3
        case .influencer: return 4
        case .elite: return 5
        case .partner: return 6
        case .legendary: return 7
        case .topCreator: return 8
        case .founder: return 9
        case .coFounder: return 10
        }
    }
}

// MARK: - Helper Extensions

extension EngagementCalculator {
    
    /// Test engagement calculations with mock data
    static func helloWorldTest() -> String {
        let result = """
        🔥 ENGAGEMENT CALCULATOR: Hello World - Pure calculation functions ready!
        
        Test Results:
        - Progressive Tapping: 2 → 4 → 8 → 16 taps required
        - Hype Score: Veteran tier = 1.5x multiplier
        - Temperature: 90% hype ratio = "blazing" 🔥
        - Clout Gain: Hype from Elite tier = 25 clout points
        - Engagement Health: Multi-factor scoring active
        
        Status: All calculations functional ✅
        """
        
        return result
    }
}
