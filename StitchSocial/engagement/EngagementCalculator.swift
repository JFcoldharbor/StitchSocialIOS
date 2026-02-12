//
//  EngagementCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Pure Engagement Calculation Functions
//  Dependencies: EngagementConfig, EngagementTypes (Layer 1-2) ONLY
//  Features: Progressive tapping logic, milestone detection, hybrid clout calculations
//  UPDATED: Long press burst system - regular tap vs burst calculations split
//

import Foundation

/// Pure calculation functions for engagement system
struct EngagementCalculator {
    
    // MARK: - Progressive Tapping System
    
    /// Check if engagement is in instant mode (first 4 engagements)
    static func isInstantMode(totalEngagements: Int) -> Bool {
        return totalEngagements < EngagementConfig.instantEngagementThreshold
    }
    
    /// Calculate progressive tap requirement for specific engagement number
    static func calculateProgressiveTaps(engagementNumber: Int) -> Int {
        if engagementNumber <= EngagementConfig.instantEngagementThreshold {
            return 1
        }
        let progressiveIndex = engagementNumber - EngagementConfig.instantEngagementThreshold - 1
        let requirement = EngagementConfig.firstProgressiveTaps * Int(pow(2.0, Double(progressiveIndex)))
        return min(requirement, EngagementConfig.maxTapRequirement)
    }
    
    /// Calculate tap progress as percentage (0.0 to 1.0)
    static func calculateTapProgress(current: Int, required: Int) -> Double {
        guard required > 0 else { return 0.0 }
        return min(1.0, Double(current) / Double(required))
    }
    
    /// Detect milestone reached during tapping progress
    static func detectMilestone(progress: Double) -> TapMilestone? {
        if progress >= 1.0 { return .complete }
        if progress >= 0.9 { return .almostDone }
        if progress >= 0.75 { return .threeQuarters }
        if progress >= 0.5 { return .half }
        if progress >= 0.25 { return .quarter }
        return nil
    }
    
    /// Calculate remaining taps needed for completion
    static func calculateRemainingTaps(current: Int, required: Int) -> Int {
        return max(0, required - current)
    }
    
    /// Check if tapping sequence is complete
    static func isTappingComplete(current: Int, required: Int) -> Bool {
        return current >= required
    }
    
    // MARK: - 🆕 Burst-Aware Clout Calculation System
    
    /// Calculate clout award for completed engagement
    /// Regular tap = reduced base clout. Burst (long press) = full tier clout.
    static func calculateCloutReward(
        giverTier: UserTier,
        tapNumber: Int,
        isFirstEngagement: Bool,
        currentCloutFromThisUser: Int,
        isBurst: Bool = false
    ) -> Int {
        return EngagementConfig.calculateClout(
            tier: giverTier,
            tapNumber: tapNumber,
            isFirstEngagement: isFirstEngagement,
            currentCloutFromUser: currentCloutFromThisUser,
            isBurst: isBurst
        )
    }
    
    /// Calculate visual hype increment (burst-aware)
    /// Regular tap = +1 for all tiers. Burst = full tier multiplier.
    static func calculateVisualHypeIncrement(giverTier: UserTier, isBurst: Bool = false) -> Int {
        return EngagementConfig.getVisualHypeMultiplier(for: giverTier, isBurst: isBurst)
    }
    
    /// Check if user can give more clout to this video
    static func canGiveMoreClout(
        giverTier: UserTier,
        currentCloutFromThisUser: Int
    ) -> Bool {
        let maxAllowed = EngagementConfig.getMaxCloutPerUserPerVideo(for: giverTier)
        return currentCloutFromThisUser < maxAllowed
    }
    
    /// Check if video can receive more clout
    static func canReceiveMoreClout(currentTotalClout: Int) -> Bool {
        return currentTotalClout < EngagementConfig.maxTotalCloutPerVideo
    }
    
    /// Calculate remaining clout allowance for user on this video
    static func calculateRemainingCloutAllowance(
        giverTier: UserTier,
        currentCloutFromThisUser: Int
    ) -> Int {
        let maxAllowed = EngagementConfig.getMaxCloutPerUserPerVideo(for: giverTier)
        return max(0, maxAllowed - currentCloutFromThisUser)
    }
    
    // MARK: - Hype Rating Calculations
    
    /// Calculate hype rating cost for specific user tier (burst costs more)
    static func calculateHypeRatingCost(tier: UserTier, isBurst: Bool = false) -> Double {
        return EngagementConfig.getHypeCost(for: tier, isBurst: isBurst)
    }
    
    /// Check if user can afford engagement based on hype rating
    static func canAffordEngagement(currentHypeRating: Double, cost: Double) -> Bool {
        return currentHypeRating >= cost
    }
    
    /// Calculate hype rating after deduction
    static func applyHypeRatingCost(currentRating: Double, cost: Double) -> Double {
        return max(0.0, currentRating - cost)
    }
    
    // MARK: - Cool Engagement Calculations
    
    /// Calculate clout penalty for cool engagements
    static func calculateCoolPenalty() -> Int {
        return EngagementConfig.coolCloutPenalty
    }
    
    // MARK: - Complete Engagement Result Calculation
    
    /// Calculate complete engagement result (INSTANT ENGAGEMENTS)
    static func calculateEngagementResult(
        currentVideoHypeCount: Int,
        currentVideoCoolCount: Int,
        userTier: UserTier,
        isHypeEngagement: Bool,
        tapNumber: Int,
        isFirstEngagement: Bool,
        currentCloutFromThisUser: Int,
        isBurst: Bool = false
    ) -> EngagementResult {
        
        let visualHypeIncrement: Int
        let visualCoolIncrement: Int
        let cloutAwarded: Int
        let animationType: EngagementAnimationType
        let message: String
        
        if isHypeEngagement {
            // Calculate visual hype increment (regular = +1, burst = tier multiplier)
            visualHypeIncrement = calculateVisualHypeIncrement(giverTier: userTier, isBurst: isBurst)
            visualCoolIncrement = 0
            
            // Calculate clout (regular = reduced, burst = full)
            cloutAwarded = calculateCloutReward(
                giverTier: userTier,
                tapNumber: tapNumber,
                isFirstEngagement: isFirstEngagement,
                currentCloutFromThisUser: currentCloutFromThisUser,
                isBurst: isBurst
            )
            
            // Determine animation type
            if isBurst && isFirstEngagement && EngagementConfig.hasFirstTapBonus(tier: userTier) {
                animationType = .founderExplosion  // Premium tier first burst
                message = "Premium burst: +\(visualHypeIncrement) hypes!"
            } else if isBurst && EngagementConfig.isBurstEligible(tier: userTier) {
                animationType = .burstEngagement  // Burst engagement
                message = "Burst: +\(visualHypeIncrement) hypes!"
            } else {
                animationType = .standardHype
                message = "Hype added!"
            }
            
        } else {
            // Cool engagement (no burst variant)
            visualHypeIncrement = 0
            visualCoolIncrement = 1
            cloutAwarded = calculateCoolPenalty()
            animationType = .standardCool
            message = "Cool added"
        }
        
        let newHypeCount = currentVideoHypeCount + visualHypeIncrement
        let newCoolCount = currentVideoCoolCount + visualCoolIncrement
        
        return EngagementResult(
            success: true,
            cloutAwarded: cloutAwarded,
            newHypeCount: newHypeCount,
            newCoolCount: newCoolCount,
            isFounderFirstTap: isFirstEngagement && userTier == .founder && isBurst,
            visualHypeIncrement: visualHypeIncrement,
            visualCoolIncrement: visualCoolIncrement,
            animationType: animationType,
            message: message
        )
    }
    
    // MARK: - Engagement Type Logic
    
    /// Determine next tap requirement for hype engagement
    static func calculateNextHypeRequirement(currentHypeEngagements: Int) -> Int {
        let nextEngagementNumber = currentHypeEngagements + 1
        return calculateProgressiveTaps(engagementNumber: nextEngagementNumber)
    }
    
    /// Determine next tap requirement for cool engagement
    static func calculateNextCoolRequirement(currentCoolEngagements: Int) -> Int {
        let nextEngagementNumber = currentCoolEngagements + 1
        return calculateProgressiveTaps(engagementNumber: nextEngagementNumber)
    }
    
    /// Check if next engagement will be instant
    static func isNextEngagementInstant(totalEngagements: Int) -> Bool {
        return isInstantMode(totalEngagements: totalEngagements)
    }
    
    // MARK: - Validation Functions
    
    /// Validate engagement parameters
    static func validateEngagementParameters(
        currentTaps: Int,
        requiredTaps: Int,
        hypeRating: Double,
        userTier: UserTier,
        isBurst: Bool = false
    ) -> (isValid: Bool, error: String?) {
        
        if currentTaps < 0 {
            return (false, "Current taps cannot be negative")
        }
        
        if requiredTaps < 1 {
            return (false, "Required taps must be at least 1")
        }
        
        if currentTaps > requiredTaps {
            return (false, "Current taps cannot exceed required taps")
        }
        
        if hypeRating < 0 || hypeRating > 100 {
            return (false, "Hype rating must be between 0 and 100")
        }
        
        let cost = calculateHypeRatingCost(tier: userTier, isBurst: isBurst)
        if !canAffordEngagement(currentHypeRating: hypeRating, cost: cost) {
            return (false, "Insufficient hype rating for engagement")
        }
        
        return (true, nil)
    }
    
    /// Validate clout award against caps
    static func validateCloutAward(
        giverTier: UserTier,
        currentCloutFromUser: Int,
        proposedClout: Int,
        currentVideoTotalClout: Int
    ) -> (isValid: Bool, adjustedClout: Int, reason: String?) {
        
        let maxPerUser = EngagementConfig.getMaxCloutPerUserPerVideo(for: giverTier)
        if currentCloutFromUser >= maxPerUser {
            return (false, 0, "User has reached max clout for this video (\(maxPerUser))")
        }
        
        let remainingUserAllowance = maxPerUser - currentCloutFromUser
        var adjustedClout = min(proposedClout, remainingUserAllowance)
        
        let maxPerVideo = EngagementConfig.maxTotalCloutPerVideo
        if currentVideoTotalClout >= maxPerVideo {
            return (false, 0, "Video has reached max total clout (\(maxPerVideo))")
        }
        
        let remainingVideoAllowance = maxPerVideo - currentVideoTotalClout
        adjustedClout = min(adjustedClout, remainingVideoAllowance)
        
        if adjustedClout < proposedClout {
            return (true, adjustedClout, "Clout adjusted to fit within caps")
        }
        
        return (true, adjustedClout, nil)
    }
}

// MARK: - Testing & Validation

extension EngagementCalculator {
    
    /// Test burst vs regular clout system
    static func testBurstCloutSystem() -> String {
        var report = "🧪 TESTING BURST vs REGULAR CLOUT SYSTEM\n\n"
        
        // Test Founder - Regular Taps
        report += "📊 FOUNDER REGULAR TAPS (+1 hype, 5 clout/tap)\n"
        var cumulativeClout = 0
        for tap in 1...10 {
            let clout = calculateCloutReward(
                giverTier: .founder, tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: cumulativeClout,
                isBurst: false
            )
            let visual = calculateVisualHypeIncrement(giverTier: .founder, isBurst: false)
            cumulativeClout += clout
            report += "  Tap \(tap): +\(visual) hype, +\(clout) clout (total: \(cumulativeClout))\n"
        }
        
        // Test Founder - Burst (Long Press)
        report += "\n📊 FOUNDER BURST (LONG PRESS) (+20 hype, 50 clout/tap)\n"
        cumulativeClout = 0
        for tap in 1...10 {
            let clout = calculateCloutReward(
                giverTier: .founder, tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: cumulativeClout,
                isBurst: true
            )
            let visual = calculateVisualHypeIncrement(giverTier: .founder, isBurst: true)
            cumulativeClout += clout
            report += "  Burst \(tap): +\(visual) hype, +\(clout) clout (total: \(cumulativeClout))\n"
        }
        
        // Test Rookie (no burst benefit)
        report += "\n📊 ROOKIE (no burst benefit, same either way)\n"
        cumulativeClout = 0
        for tap in 1...5 {
            let regularClout = calculateCloutReward(
                giverTier: .rookie, tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: cumulativeClout,
                isBurst: false
            )
            let burstClout = calculateCloutReward(
                giverTier: .rookie, tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: cumulativeClout,
                isBurst: true
            )
            cumulativeClout += regularClout
            report += "  Tap \(tap): regular=\(regularClout), burst=\(burstClout) (same)\n"
        }
        
        report += "\n✅ Burst Clout System Tests Complete!\n"
        return report
    }
}
