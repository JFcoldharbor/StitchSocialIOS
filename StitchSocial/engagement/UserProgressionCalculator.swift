//
//  UserProgressionCalculator.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Pure User Progression Calculation Functions
//  Dependencies: UserTier (Layer 1) ONLY
//  Features: Tier advancement, badge eligibility, clout calculation
//  UPDATED: Added ambassador tier level support
//

import Foundation

// MARK: - Pure Calculation Functions

/// Pure calculation functions for user progression system
struct UserProgressionCalculator {
    
    // MARK: - Tier Advancement Calculations
    
    /// Calculate tier advancement based on current clout
    static func calculateTierAdvancement(currentClout: Int, currentTier: UserTier) -> UserTier? {
        let allTiers = UserTier.allCases.filter { $0.isAchievableTier }
        
        for tier in allTiers {
            if tier.cloutRange.contains(currentClout) && tier != currentTier {
                if isHigherTier(tier, than: currentTier) {
                    return tier
                }
            }
        }
        
        return nil
    }
    
    /// Check if one tier is higher than another
    static func isHigherTier(_ tier1: UserTier, than tier2: UserTier) -> Bool {
        return getTierLevel(tier1) > getTierLevel(tier2)
    }
    
    /// Get numeric level for tier comparison - UPDATED with ambassador
    static func getTierLevel(_ tier: UserTier) -> Int {
        switch tier {
        case .rookie: return 1
        case .rising: return 2
        case .veteran: return 3
        case .influencer: return 4
        case .ambassador: return 5        // NEW tier level
        case .elite: return 6             // ADJUSTED from 5
        case .partner: return 7           // ADJUSTED from 6
        case .legendary: return 8         // ADJUSTED from 7
        case .topCreator: return 9        // ADJUSTED from 8
        case .founder: return 10          // ADJUSTED from 9
        case .coFounder: return 11        // ADJUSTED from 10
        }
    }
    
    /// Calculate clout needed for next tier
    static func calculateCloutNeededForNextTier(currentClout: Int, currentTier: UserTier) -> Int {
        guard let nextTier = currentTier.nextTier else { return 0 }
        let nextTierMin = nextTier.cloutRange.lowerBound
        return max(0, nextTierMin - currentClout)
    }
    
    // MARK: - Badge Eligibility Calculations
    
    /// Calculate badge eligibility based on user statistics
    static func calculateBadgeEligibility(userStats: RealUserStats) -> [String] {
        var eligibleBadges: [String] = []
        
        // Content Creator Badges
        if userStats.posts >= 100 { eligibleBadges.append("prolific_creator") }
        if userStats.posts >= 50 { eligibleBadges.append("content_creator") }
        if userStats.posts >= 10 { eligibleBadges.append("creator") }
        
        // Thread Starter Badges
        if userStats.threads >= 50 { eligibleBadges.append("thread_master") }
        if userStats.threads >= 20 { eligibleBadges.append("conversation_starter") }
        if userStats.threads >= 5 { eligibleBadges.append("thread_starter") }
        
        // Engagement Badges
        if userStats.hypes >= 10000 { eligibleBadges.append("hype_legend") }
        if userStats.hypes >= 1000 { eligibleBadges.append("hype_master") }
        if userStats.hypes >= 100 { eligibleBadges.append("hype_giver") }
        
        // Community Badges
        if userStats.followers >= 10000 { eligibleBadges.append("influencer_badge") }
        if userStats.followers >= 1000 { eligibleBadges.append("popular") }
        if userStats.followers >= 100 { eligibleBadges.append("networker") }
        
        // Engagement Rate Badges
        if userStats.engagementRate >= 0.8 { eligibleBadges.append("engagement_expert") }
        if userStats.engagementRate >= 0.5 { eligibleBadges.append("engaging") }
        
        // Clout-based Badges
        if userStats.clout >= 100000 { eligibleBadges.append("clout_champion") }
        if userStats.clout >= 50000 { eligibleBadges.append("high_clout") }
        if userStats.clout >= 10000 { eligibleBadges.append("clout_earner") }
        
        return eligibleBadges
    }
    
    // MARK: - Progression Score Calculations
    
    /// Calculate overall user progression score (0.0 to 100.0)
    static func calculateProgressionScore(userStats: RealUserStats, accountAge: TimeInterval) -> Double {
        let ageInDays = max(1, accountAge / (24 * 60 * 60))
        
        // Calculate daily averages
        let postsPerDay = ageInDays > 0 ? Double(userStats.posts) / ageInDays : 0
        let hypesPerDay = ageInDays > 0 ? Double(userStats.hypes) / ageInDays : 0
        let followersPerDay = ageInDays > 0 ? Double(userStats.followers) / ageInDays : 0
        
        // Component scores (0-20 each, total 100)
        let contentScore = min(20.0, postsPerDay * 4.0)
        let engagementScore = min(20.0, hypesPerDay * 2.0)
        let socialScore = min(20.0, followersPerDay * 10.0)
        let qualityScore = userStats.engagementRate * 20.0
        let cloutScore = min(20.0, Double(userStats.clout) / 5000.0)
        
        return contentScore + engagementScore + socialScore + qualityScore + cloutScore
    }
    
    // MARK: - Testing
    
    /// Test user progression calculations
    static func helloWorldTest() {
        let mockStats = RealUserStats(
            followers: 150,
            hypes: 75,
            threads: 12,
            posts: 25,
            engagementRate: 0.65,
            clout: 3500
        )
        
        let tierAdvancement = calculateTierAdvancement(currentClout: 3500, currentTier: .rookie)
        let badges = calculateBadgeEligibility(userStats: mockStats)
        let progressScore = calculateProgressionScore(userStats: mockStats, accountAge: 30 * 24 * 60 * 60)
        
        print("USER PROGRESSION CALCULATOR: Test completed")
        print("Tier Advancement: \(tierAdvancement?.displayName ?? "None")")
        print("Badge Count: \(badges.count)")
        print("Progress Score: \(String(format: "%.1f", progressScore))")
    }
}
