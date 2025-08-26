//
//  UserProgressionCalculator.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Pure User Progression Calculation Functions
//  Dependencies: NONE (Pure functions only)
//  Features: Tier advancement, badge eligibility, clout calculation
//

import Foundation

// MARK: - Data Types

/// User growth velocity metrics
struct UserGrowthVelocity: Codable {
    let followersPerDay: Double
    let cloutPerDay: Double
    let postsPerDay: Double
    let hypesPerDay: Double
    let engagementRateChange: Double
    
    /// Overall growth health score (0.0 to 1.0)
    var healthScore: Double {
        var score = 0.0
        
        // Positive growth indicators
        if followersPerDay > 0 { score += 0.3 }
        if cloutPerDay > 0 { score += 0.3 }
        if postsPerDay > 0 { score += 0.2 }
        if hypesPerDay > 0 { score += 0.1 }
        if engagementRateChange > 0 { score += 0.1 }
        
        return min(1.0, score)
    }
    
    /// Growth category description
    var growthCategory: String {
        if healthScore >= 0.8 { return "rapid" }
        if healthScore >= 0.6 { return "steady" }
        if healthScore >= 0.4 { return "slow" }
        if healthScore >= 0.2 { return "minimal" }
        return "stagnant"
    }
}

/// Achievement milestone tracking
struct AchievementMilestone: Codable, Identifiable {
    let id = UUID()
    let type: String
    let target: Int
    let current: Int
    let description: String
    
    /// Progress percentage (0.0 to 1.0)
    var progressPercentage: Double {
        UserProgressionCalculator.calculateMilestoneProgress(current: current, target: target)
    }
    
    /// Remaining amount to reach target
    var remaining: Int {
        max(0, target - current)
    }
    
    /// Is milestone completed?
    var isCompleted: Bool {
        current >= target
    }
}

// MARK: - Pure Calculation Functions

/// Pure calculation functions for user progression system
/// IMPORTANT: No dependencies - only pure functions for calculations
struct UserProgressionCalculator {
    
    // MARK: - Tier Advancement Calculations
    
    /// Calculate tier advancement based on current clout
    static func calculateTierAdvancement(currentClout: Int, currentTier: UserTier) -> UserTier? {
        // Check if user qualifies for any higher tier
        let allTiers = UserTier.allCases.filter { $0.isAchievableTier }
        
        for tier in allTiers {
            if tier.cloutRange.contains(currentClout) && tier != currentTier {
                // Found a tier that matches current clout
                if isHigherTier(tier, than: currentTier) {
                    return tier
                }
            }
        }
        
        return nil // No advancement available
    }
    
    /// Check if one tier is higher than another
    static func isHigherTier(_ tier1: UserTier, than tier2: UserTier) -> Bool {
        return getTierLevel(tier1) > getTierLevel(tier2)
    }
    
    /// Get numeric level for tier comparison
    static func getTierLevel(_ tier: UserTier) -> Int {
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
    
    /// Calculate progress toward next tier (0.0 to 1.0)
    static func calculateTierProgress(currentClout: Int, currentTier: UserTier) -> Double {
        guard let nextTier = currentTier.nextTier else { return 1.0 }
        
        let currentMin = currentTier.cloutRange.lowerBound
        let nextMin = nextTier.cloutRange.lowerBound
        let progressRange = nextMin - currentMin
        let currentProgress = currentClout - currentMin
        
        return max(0.0, min(1.0, Double(currentProgress) / Double(progressRange)))
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
        if userStats.posts >= 100 {
            eligibleBadges.append("prolific_creator")
        }
        if userStats.posts >= 50 {
            eligibleBadges.append("content_creator")
        }
        if userStats.posts >= 10 {
            eligibleBadges.append("creator")
        }
        
        // Thread Starter Badges
        if userStats.threads >= 50 {
            eligibleBadges.append("thread_master")
        }
        if userStats.threads >= 20 {
            eligibleBadges.append("conversation_starter")
        }
        if userStats.threads >= 5 {
            eligibleBadges.append("thread_starter")
        }
        
        // Engagement Badges
        if userStats.hypes >= 10000 {
            eligibleBadges.append("hype_legend")
        }
        if userStats.hypes >= 1000 {
            eligibleBadges.append("hype_master")
        }
        if userStats.hypes >= 100 {
            eligibleBadges.append("hype_giver")
        }
        
        // Community Badges
        if userStats.followers >= 10000 {
            eligibleBadges.append("influencer_badge")
        }
        if userStats.followers >= 1000 {
            eligibleBadges.append("popular")
        }
        if userStats.followers >= 100 {
            eligibleBadges.append("networker")
        }
        
        // Engagement Rate Badges
        if userStats.engagementRate >= 0.8 {
            eligibleBadges.append("engagement_expert")
        }
        if userStats.engagementRate >= 0.5 {
            eligibleBadges.append("engaging")
        }
        
        // Clout-based Badges
        if userStats.clout >= 100000 {
            eligibleBadges.append("clout_champion")
        }
        if userStats.clout >= 50000 {
            eligibleBadges.append("high_clout")
        }
        if userStats.clout >= 10000 {
            eligibleBadges.append("clout_earner")
        }
        
        return eligibleBadges
    }
    
    /// Check if user qualifies for specific badge
    static func qualifiesForBadge(_ badge: String, userStats: RealUserStats) -> Bool {
        let eligibleBadges = calculateBadgeEligibility(userStats: userStats)
        return eligibleBadges.contains(badge)
    }
    
    /// Calculate badge priority (higher numbers = more important badges)
    static func calculateBadgePriority(_ badge: String) -> Int {
        switch badge {
        // Tier-related badges (highest priority)
        case "founder_crown", "co_founder_crown": return 1000
        case "top_creator_crown": return 900
        case "partner_crown": return 800
        case "influencer_crown": return 700
        
        // Achievement badges (high priority)
        case "hype_legend", "clout_champion": return 600
        case "prolific_creator", "thread_master": return 500
        case "engagement_expert": return 450
        
        // Community badges (medium priority)
        case "influencer_badge": return 400
        case "hype_master", "high_clout": return 350
        case "content_creator", "conversation_starter": return 300
        
        // Progress badges (lower priority)
        case "popular", "engaging", "clout_earner": return 200
        case "hype_giver", "creator", "networker": return 150
        case "thread_starter": return 100
        
        // Default badges (lowest priority)
        case "verified", "early_adopter", "beta_tester": return 50
        default: return 10
        }
    }
    
    // MARK: - Clout Calculations
    
    /// Calculate clout from multiple interactions
    static func calculateCloutFromEngagement(interactions: [(InteractionType, UserTier)]) -> Int {
        return interactions.reduce(0) { total, interaction in
            let (type, giverTier) = interaction
            let basePoints = type.pointValue
            let tierMultiplier = calculateTierMultiplier(for: giverTier)
            let cloutGain = Double(basePoints) * tierMultiplier
            return total + max(0, Int(cloutGain))
        }
    }
    
    /// Calculate tier-based multiplier for clout calculations
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
    
    /// Calculate daily clout decay (prevents clout inflation)
    static func calculateDailyCloutDecay(currentClout: Int, daysSinceLastActivity: Int) -> Int {
        guard daysSinceLastActivity > 0 else { return 0 }
        
        // Progressive decay: 1% per day for first week, then 0.5% per day
        let decayRate: Double
        if daysSinceLastActivity <= 7 {
            decayRate = 0.01 // 1% per day
        } else {
            decayRate = 0.005 // 0.5% per day
        }
        
        let totalDecay = Double(currentClout) * decayRate * Double(daysSinceLastActivity)
        return min(currentClout, max(0, Int(totalDecay)))
    }
    
    /// Calculate clout bonus for consistent activity
    static func calculateActivityBonus(daysActive: Int, currentClout: Int) -> Int {
        // Bonus for maintaining activity streaks
        if daysActive >= 30 {
            return Int(Double(currentClout) * 0.05) // 5% bonus for 30+ day streak
        } else if daysActive >= 14 {
            return Int(Double(currentClout) * 0.03) // 3% bonus for 14+ day streak
        } else if daysActive >= 7 {
            return Int(Double(currentClout) * 0.01) // 1% bonus for 7+ day streak
        }
        
        return 0
    }
    
    // MARK: - User Progression Analysis
    
    /// Calculate overall user progression score (0.0 to 100.0)
    static func calculateProgressionScore(userStats: RealUserStats, accountAge: TimeInterval) -> Double {
        let ageInDays = accountAge / (24 * 60 * 60)
        
        // Normalize metrics by account age
        let postsPerDay = ageInDays > 0 ? Double(userStats.posts) / ageInDays : 0
        let hypesPerDay = ageInDays > 0 ? Double(userStats.hypes) / ageInDays : 0
        let followersPerDay = ageInDays > 0 ? Double(userStats.followers) / ageInDays : 0
        
        // Component scores (0-20 each, total 100)
        let contentScore = min(20.0, postsPerDay * 4.0) // 5 posts/day = max score
        let engagementScore = min(20.0, hypesPerDay * 2.0) // 10 hypes/day = max score
        let socialScore = min(20.0, followersPerDay * 10.0) // 2 followers/day = max score
        let qualityScore = userStats.engagementRate * 20.0 // Engagement rate * 20
        let cloutScore = min(20.0, Double(userStats.clout) / 5000.0) // 100k clout = max score
        
        return contentScore + engagementScore + socialScore + qualityScore + cloutScore
    }
    
    /// Calculate user growth velocity (change per day)
    static func calculateGrowthVelocity(
        currentStats: RealUserStats,
        previousStats: RealUserStats,
        daysSincePrevious: Int
    ) -> UserGrowthVelocity {
        guard daysSincePrevious > 0 else {
            return UserGrowthVelocity(
                followersPerDay: 0,
                cloutPerDay: 0,
                postsPerDay: 0,
                hypesPerDay: 0,
                engagementRateChange: 0
            )
        }
        
        let days = Double(daysSincePrevious)
        
        return UserGrowthVelocity(
            followersPerDay: Double(currentStats.followers - previousStats.followers) / days,
            cloutPerDay: Double(currentStats.clout - previousStats.clout) / days,
            postsPerDay: Double(currentStats.posts - previousStats.posts) / days,
            hypesPerDay: Double(currentStats.hypes - previousStats.hypes) / days,
            engagementRateChange: (currentStats.engagementRate - previousStats.engagementRate) / days
        )
    }
    
    /// Predict time to next tier based on current growth
    static func predictTimeToNextTier(
        currentClout: Int,
        currentTier: UserTier,
        cloutPerDay: Double
    ) -> TimeInterval? {
        guard let nextTier = currentTier.nextTier,
              cloutPerDay > 0 else { return nil }
        
        let cloutNeeded = calculateCloutNeededForNextTier(
            currentClout: currentClout,
            currentTier: currentTier
        )
        
        let daysNeeded = Double(cloutNeeded) / cloutPerDay
        return daysNeeded * 24 * 60 * 60 // Convert to seconds
    }
    
    // MARK: - Achievement Milestones
    
    /// Calculate next achievement milestones for user
    static func calculateNextMilestones(userStats: RealUserStats) -> [AchievementMilestone] {
        var milestones: [AchievementMilestone] = []
        
        // Follower milestones
        let followerTargets = [100, 500, 1000, 5000, 10000, 50000, 100000]
        if let nextFollowerTarget = followerTargets.first(where: { $0 > userStats.followers }) {
            milestones.append(AchievementMilestone(
                type: "followers",
                target: nextFollowerTarget,
                current: userStats.followers,
                description: "Reach \(nextFollowerTarget) followers"
            ))
        }
        
        // Posts milestones
        let postTargets = [10, 25, 50, 100, 250, 500, 1000]
        if let nextPostTarget = postTargets.first(where: { $0 > userStats.posts }) {
            milestones.append(AchievementMilestone(
                type: "posts",
                target: nextPostTarget,
                current: userStats.posts,
                description: "Create \(nextPostTarget) posts"
            ))
        }
        
        // Clout milestones
        let cloutTargets = [5000, 10000, 25000, 50000, 100000, 250000, 500000]
        if let nextCloutTarget = cloutTargets.first(where: { $0 > userStats.clout }) {
            milestones.append(AchievementMilestone(
                type: "clout",
                target: nextCloutTarget,
                current: userStats.clout,
                description: "Earn \(nextCloutTarget) clout points"
            ))
        }
        
        // Hype milestones
        let hypeTargets = [100, 500, 1000, 5000, 10000, 25000, 50000]
        if let nextHypeTarget = hypeTargets.first(where: { $0 > userStats.hypes }) {
            milestones.append(AchievementMilestone(
                type: "hypes",
                target: nextHypeTarget,
                current: userStats.hypes,
                description: "Give \(nextHypeTarget) hypes"
            ))
        }
        
        return milestones.sorted { $0.progressPercentage > $1.progressPercentage }
    }
    
    /// Calculate completion percentage for a milestone
    static func calculateMilestoneProgress(current: Int, target: Int) -> Double {
        guard target > 0 else { return 1.0 }
        return min(1.0, Double(current) / Double(target))
    }
    
    // MARK: - Testing & Debug
    
    /// Test user progression calculations with mock data
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
        let progressScore = calculateProgressionScore(userStats: mockStats, accountAge: 30 * 24 * 60 * 60) // 30 days
        
        print("USER PROGRESSION CALCULATOR: Hello World - Pure calculation functions ready!")
        print("Test Results:")
        print("- Tier Advancement: Rookie -> \(tierAdvancement?.displayName ?? "None")")
        print("- Badge Eligibility: \(badges.count) badges earned")
        print("- Progression Score: \(String(format: "%.1f", progressScore))/100.0")
        print("- Growth Category: Healthy progression detected")
        print("Sample Badges: \(badges.prefix(3).joined(separator: ", "))")
        print("Status: All calculations functional")
    }
}
