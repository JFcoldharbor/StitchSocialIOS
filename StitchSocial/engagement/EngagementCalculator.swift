//
//  EngagementCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Pure Engagement Calculation Functions
//  Dependencies: EngagementConfig, EngagementTypes (Layer 1-2) ONLY
//  Features: Progressive tapping logic, milestone detection, NEW hybrid clout calculations
//  UPDATED: Decoupled visual hypes from clout, tier-based caps, diminishing returns, anti-spam
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
        // Engagements 1-4 are instant (1 tap)
        if engagementNumber <= EngagementConfig.instantEngagementThreshold {
            return 1
        }
        
        // Progressive tapping starts at 5th engagement
        // 5th = 2 taps, 6th = 4 taps, 7th = 8 taps, 8th = 16 taps, etc.
        let progressiveIndex = engagementNumber - EngagementConfig.instantEngagementThreshold - 1
        let requirement = EngagementConfig.firstProgressiveTaps * Int(pow(2.0, Double(progressiveIndex)))
        
        // Cap at maximum to prevent infinite progression
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
    
    // MARK: - NEW: Hybrid Clout Calculation System
    
    /// Calculate clout award for completed engagement (NEW SYSTEM)
    static func calculateCloutReward(
        giverTier: UserTier,
        tapNumber: Int,
        isFirstEngagement: Bool,
        currentCloutFromThisUser: Int
    ) -> Int {
        return EngagementConfig.calculateClout(
            tier: giverTier,
            tapNumber: tapNumber,
            isFirstEngagement: isFirstEngagement,
            currentCloutFromUser: currentCloutFromThisUser
        )
    }
    
    /// Calculate visual hype increment (decoupled from clout)
    static func calculateVisualHypeIncrement(giverTier: UserTier) -> Int {
        return EngagementConfig.getVisualHypeMultiplier(for: giverTier)
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
    
    /// Calculate hype rating cost for specific user tier
    static func calculateHypeRatingCost(tier: UserTier) -> Double {
        return EngagementConfig.getHypeCost(for: tier)
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
        currentCloutFromThisUser: Int
    ) -> EngagementResult {
        
        // All engagements complete instantly
        let visualHypeIncrement: Int
        let visualCoolIncrement: Int
        let cloutAwarded: Int
        let animationType: EngagementAnimationType
        let message: String
        
        if isHypeEngagement {
            // Calculate visual hype increment (tier-based, every tap)
            visualHypeIncrement = calculateVisualHypeIncrement(giverTier: userTier)
            visualCoolIncrement = 0
            
            // Calculate clout with new system (decoupled from visual hypes)
            cloutAwarded = calculateCloutReward(
                giverTier: userTier,
                tapNumber: tapNumber,
                isFirstEngagement: isFirstEngagement,
                currentCloutFromThisUser: currentCloutFromThisUser
            )
            
            // Determine animation type
            if isFirstEngagement && EngagementConfig.hasFirstTapBonus(tier: userTier) {
                animationType = .founderExplosion  // Premium tier first tap
                message = "Premium boost: +\(visualHypeIncrement) hypes!"
            } else {
                animationType = .standardHype
                message = "Hype added!"
            }
            
        } else {
            // Cool engagement
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
            isFounderFirstTap: isFirstEngagement && userTier == .founder,
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
        userTier: UserTier
    ) -> (isValid: Bool, error: String?) {
        
        // Check tap counts
        if currentTaps < 0 {
            return (false, "Current taps cannot be negative")
        }
        
        if requiredTaps < 1 {
            return (false, "Required taps must be at least 1")
        }
        
        if currentTaps > requiredTaps {
            return (false, "Current taps cannot exceed required taps")
        }
        
        // Check hype rating
        if hypeRating < 0 || hypeRating > 100 {
            return (false, "Hype rating must be between 0 and 100")
        }
        
        // Check if user can afford engagement
        let cost = calculateHypeRatingCost(tier: userTier)
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
        
        // Check per-user-per-video cap
        let maxPerUser = EngagementConfig.getMaxCloutPerUserPerVideo(for: giverTier)
        if currentCloutFromUser >= maxPerUser {
            return (false, 0, "User has reached max clout for this video (\(maxPerUser))")
        }
        
        // Check if proposed clout would exceed user cap
        let remainingUserAllowance = maxPerUser - currentCloutFromUser
        var adjustedClout = min(proposedClout, remainingUserAllowance)
        
        // Check per-video total cap
        let maxPerVideo = EngagementConfig.maxTotalCloutPerVideo
        if currentVideoTotalClout >= maxPerVideo {
            return (false, 0, "Video has reached max total clout (\(maxPerVideo))")
        }
        
        // Check if proposed clout would exceed video cap
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
    
    /// Test new hybrid clout system with examples
    static func testHybridCloutSystem() -> String {
        var report = "🧪 TESTING HYBRID CLOUT SYSTEM\n\n"
        
        // Test Founder
        report += "📊 FOUNDER TEST (20 hypes/tap, 50 base clout)\n"
        for tap in 1...15 {
            let clout = calculateCloutReward(
                giverTier: .founder,
                tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: (tap - 1) * 50
            )
            let visual = calculateVisualHypeIncrement(giverTier: .founder)
            report += "Tap \(tap): +\(visual) hypes, \(clout) clout\n"
        }
        
        report += "\n📊 INFLUENCER TEST (1 hype/tap, 5 base clout)\n"
        for tap in 1...10 {
            let clout = calculateCloutReward(
                giverTier: .influencer,
                tapNumber: tap,
                isFirstEngagement: tap == 1,
                currentCloutFromThisUser: (tap - 1) * 5
            )
            let visual = calculateVisualHypeIncrement(giverTier: .influencer)
            report += "Tap \(tap): +\(visual) hypes, \(clout) clout\n"
        }
        
        report += "\n✅ Hybrid Clout System Tests Complete!\n"
        
        return report
    }
}
