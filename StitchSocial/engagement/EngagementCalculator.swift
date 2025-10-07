//
//  EngagementCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Pure Engagement Calculation Functions
//  Dependencies: EngagementConfig, EngagementTypes (Layer 1-2) ONLY
//  Features: Progressive tapping logic, milestone detection, cost calculations
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
    
    // MARK: - Clout Reward Calculations
    
    /// Calculate clout reward for specific user tier
    static func calculateCloutReward(giverTier: UserTier) -> Int {
        return EngagementConfig.getCloutReward(for: giverTier)
    }
    
    /// Calculate regular clout based on 5-hype threshold
    static func calculateRegularClout(userTier: UserTier, currentHypeCount: Int) -> Int {
        // Award clout every 5 hypes
        if currentHypeCount % EngagementConfig.regularCloutThreshold == 0 {
            return calculateCloutReward(giverTier: userTier)
        }
        return 0
    }
    
    /// Calculate clout penalty for cool engagements
    static func calculateCoolPenalty() -> Int {
        return EngagementConfig.coolCloutPenalty
    }
    
    /// Calculate total clout for multiple engagements
    static func calculateTotalClout(engagementCount: Int, giverTier: UserTier) -> Int {
        let rewardPerEngagement = calculateCloutReward(giverTier: giverTier)
        return engagementCount * rewardPerEngagement
    }
    
    // MARK: - State Update Calculations
    
    /// Calculate complete engagement state update
    static func calculateStateUpdate(
        currentState: VideoEngagementState,
        isHypeEngagement: Bool,
        additionalTaps: Int = 1
    ) -> (newState: VideoEngagementState, isComplete: Bool, progress: Double, milestone: TapMilestone?) {
        
        var newState = currentState
        var isComplete = false
        var progress = 0.0
        var milestone: TapMilestone? = nil
        
        if isHypeEngagement {
            // Update hype taps
            newState.hypeCurrentTaps += additionalTaps
            
            // Calculate progress
            progress = calculateTapProgress(
                current: newState.hypeCurrentTaps,
                required: newState.hypeRequiredTaps
            )
            
            // Check completion
            if isTappingComplete(current: newState.hypeCurrentTaps, required: newState.hypeRequiredTaps) {
                isComplete = true
                newState.completeHypeEngagement()
                milestone = .complete
            } else {
                milestone = detectMilestone(progress: progress)
            }
            
        } else {
            // Update cool taps
            newState.coolCurrentTaps += additionalTaps
            
            // Calculate progress
            progress = calculateTapProgress(
                current: newState.coolCurrentTaps,
                required: newState.coolRequiredTaps
            )
            
            // Check completion
            if isTappingComplete(current: newState.coolCurrentTaps, required: newState.coolRequiredTaps) {
                isComplete = true
                newState.completeCoolEngagement()
                milestone = .complete
            } else {
                milestone = detectMilestone(progress: progress)
            }
        }
        
        return (newState, isComplete, progress, milestone)
    }
    
    /// Calculate complete engagement result
    static func calculateEngagementResult(
        currentVideoHypeCount: Int,
        currentVideoCoolCount: Int,
        userTier: UserTier,
        isHypeEngagement: Bool,
        isComplete: Bool,
        isFounderFirstTap: Bool = false
    ) -> EngagementResult {
        
        if isComplete {
            // Successful engagement
            let cloutAwarded: Int
            let visualHypeIncrement: Int
            let visualCoolIncrement: Int
            let animationType: EngagementAnimationType
            let message: String
            
            if isHypeEngagement {
                if isFounderFirstTap {
                    // Founder first tap: 20 hypes + 200 clout
                    cloutAwarded = EngagementConfig.founderFirstTapCloutBonus
                    visualHypeIncrement = EngagementConfig.founderFirstTapMultiplier
                    visualCoolIncrement = 0
                    animationType = .founderExplosion
                    message = "Founder boost: +20 hypes!"
                } else {
                    // Regular hype
                    cloutAwarded = calculateCloutReward(giverTier: userTier)
                    visualHypeIncrement = 1
                    visualCoolIncrement = 0
                    animationType = .standardHype
                    message = "Hype added!"
                }
            } else {
                // Cool engagement
                cloutAwarded = calculateCoolPenalty()
                visualHypeIncrement = 0
                visualCoolIncrement = 1
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
                isFounderFirstTap: isFounderFirstTap,
                visualHypeIncrement: visualHypeIncrement,
                visualCoolIncrement: visualCoolIncrement,
                animationType: animationType,
                message: message
            )
            
        } else {
            // Still in progress
            return EngagementResult(
                success: false,
                cloutAwarded: 0,
                newHypeCount: currentVideoHypeCount,
                newCoolCount: currentVideoCoolCount,
                isFounderFirstTap: false,
                visualHypeIncrement: 0,
                visualCoolIncrement: 0,
                animationType: .tapProgress,
                message: "Keep tapping..."
            )
        }
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
}
