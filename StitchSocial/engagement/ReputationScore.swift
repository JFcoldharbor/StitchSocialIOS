//
//  ReputationScore.swift
//  StitchSocial
//
//  Created by James Garmon on 2/11/26.
//


//
//  ReputationDecayCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Pure Reputation Decay Calculation Functions
//  Dependencies: UserTier (Layer 1) ONLY
//  Features: Reputation health scoring, decay triggers, tier demotion, troll detection
//
//  DESIGN PHILOSOPHY:
//  Clout = what you've earned (lifetime, goes up from engagement)
//  Reputation = whether you deserve to keep it (health score, can decay)
//  Effective Clout = Clout × Reputation Multiplier (this drives tier placement)
//
//  TRIGGERS (when reputation drops):
//  1. Consistently cooled content (people disagree with you)
//  2. Followers unfollowing you (people actively leaving)
//  3. Getting blocked by multiple users (red flag behavior)
//  4. Extended inactivity (relevance fades)
//  5. Deleting videos after farming engagement (sketchy behavior)
//  6. One-sided cool-only engagement (troll pattern)
//  7. Content reported/removed by moderation
//
//  CACHING: Daily reputation snapshot stored in users/{uid}/reputationHistory/{date}
//  Cloud Function calculates once per day, client reads cached score.
//  No recalculation on every feed load.
//
//  RUNS AS: Scheduled Cloud Function (daily) + event triggers
//

import Foundation

// MARK: - Reputation Score (0.0 to 1.0)

/// Reputation health score that modifies effective clout
/// 1.0 = perfect standing, 0.0 = completely degraded
struct ReputationScore {
    let overall: Double          // 0.0 to 1.0
    let coolRatioHealth: Double  // How well-received your content is
    let retentionHealth: Double  // Are followers staying?
    let activityHealth: Double   // Are you active?
    let communityHealth: Double  // Are you blocked/reported?
    let integrityHealth: Double  // Content deletion behavior
    let engagementHealth: Double // Are you a troll (cool-only)?
    
    /// Effective clout = raw clout × reputation multiplier
    /// At 1.0 reputation, full clout. At 0.5, half clout for tier calc.
    var reputationMultiplier: Double {
        // Floor at 0.3 — even worst reputation keeps 30% of clout
        // This prevents instant tier collapse from a bad week
        return max(0.3, overall)
    }
    
    /// Calculate effective clout for tier placement
    func effectiveClout(rawClout: Int) -> Int {
        return Int(Double(rawClout) * reputationMultiplier)
    }
    
    /// Human-readable grade
    var grade: String {
        if overall >= 0.9 { return "Excellent" }
        if overall >= 0.75 { return "Good" }
        if overall >= 0.6 { return "Fair" }
        if overall >= 0.4 { return "At Risk" }
        if overall >= 0.2 { return "Poor" }
        return "Critical"
    }
    
    /// Whether user should see a warning
    var shouldWarn: Bool {
        return overall < 0.6
    }
    
    /// Whether tier demotion should be evaluated
    var shouldEvaluateDemotion: Bool {
        return overall < 0.4
    }
}

// MARK: - Reputation Input Data

/// All data needed to calculate reputation (fetched once per calculation)
struct ReputationInput {
    // Content reception
    let totalHypesReceived: Int
    let totalCoolsReceived: Int
    let totalVideos: Int
    let averageEngagementRate: Double  // across all videos
    
    // Follower retention
    let currentFollowers: Int
    let followersGained30Days: Int      // new followers last 30 days
    let followersLost30Days: Int        // unfollows last 30 days
    
    // Community standing
    let timesBlocked: Int               // how many users blocked this person
    let timesReported: Int              // content reports received
    let contentRemoved: Int             // videos removed by moderation
    
    // Activity
    let lastPostDate: Date?             // when they last posted
    let lastEngagementDate: Date?       // when they last hyped/cooled anything
    let accountAge: TimeInterval        // seconds since account creation
    
    // Integrity
    let videosDeleted30Days: Int        // videos user deleted themselves
    let videosPosted30Days: Int         // videos posted in last 30 days
    
    // Engagement behavior
    let hypesGiven30Days: Int           // hypes this user gave others
    let coolsGiven30Days: Int           // cools this user gave others
    let uniqueCreatorsEngaged30Days: Int // how many different creators
    
    // Current state
    let currentTier: UserTier
    let rawClout: Int
}

// MARK: - Pure Calculation Functions

struct ReputationDecayCalculator {
    
    // MARK: - Main Calculation
    
    /// Calculate complete reputation score from input data
    /// Called once per day per user by Cloud Function
    static func calculateReputation(input: ReputationInput) -> ReputationScore {
        let coolRatio = calculateCoolRatioHealth(input: input)
        let retention = calculateRetentionHealth(input: input)
        let activity = calculateActivityHealth(input: input)
        let community = calculateCommunityHealth(input: input)
        let integrity = calculateIntegrityHealth(input: input)
        let engagement = calculateEngagementBehaviorHealth(input: input)
        
        // Weighted overall score
        // Content reception matters most, followed by community standing
        let overall = (coolRatio * 0.25)
                    + (retention * 0.15)
                    + (activity * 0.15)
                    + (community * 0.20)
                    + (integrity * 0.10)
                    + (engagement * 0.15)
        
        return ReputationScore(
            overall: clamp(overall),
            coolRatioHealth: coolRatio,
            retentionHealth: retention,
            activityHealth: activity,
            communityHealth: community,
            integrityHealth: integrity,
            engagementHealth: engagement
        )
    }
    
    // MARK: - 1. Cool Ratio Health (25% weight)
    // Are people consistently disagreeing with your content?
    
    static func calculateCoolRatioHealth(input: ReputationInput) -> Double {
        let totalEngagement = input.totalHypesReceived + input.totalCoolsReceived
        guard totalEngagement > 10 else { return 1.0 } // Not enough data
        
        let hypeRatio = Double(input.totalHypesReceived) / Double(totalEngagement)
        
        // 80%+ hype ratio = perfect health
        // 60-80% = minor concern
        // 40-60% = significant damage
        // <40% = severe (mostly cooled content)
        if hypeRatio >= 0.8 { return 1.0 }
        if hypeRatio >= 0.6 { return 0.7 + (hypeRatio - 0.6) * 1.5 } // 0.7 to 1.0
        if hypeRatio >= 0.4 { return 0.4 + (hypeRatio - 0.4) * 1.5 } // 0.4 to 0.7
        return max(0.1, hypeRatio) // Floor at 0.1
    }
    
    // MARK: - 2. Follower Retention Health (15% weight)
    // Are people actively choosing to leave?
    
    static func calculateRetentionHealth(input: ReputationInput) -> Double {
        guard input.currentFollowers > 5 else { return 1.0 } // Too small to matter
        
        let netChange = input.followersGained30Days - input.followersLost30Days
        let churnRate = input.currentFollowers > 0
            ? Double(input.followersLost30Days) / Double(input.currentFollowers)
            : 0.0
        
        // Positive net growth = healthy
        if netChange > 0 && churnRate < 0.05 { return 1.0 }
        
        // Some churn is normal (< 5% per month)
        if churnRate < 0.05 { return 0.9 }
        
        // Moderate churn (5-15%)
        if churnRate < 0.15 { return 0.7 }
        
        // High churn (15-30%) — people are leaving
        if churnRate < 0.30 { return 0.4 }
        
        // Hemorrhaging followers (30%+)
        return max(0.1, 1.0 - churnRate)
    }
    
    // MARK: - 3. Activity Health (15% weight)
    // Relevance fades with inactivity
    
    static func calculateActivityHealth(input: ReputationInput) -> Double {
        // Use most recent activity (post or engagement)
        let lastActivity: Date
        if let lastPost = input.lastPostDate, let lastEngage = input.lastEngagementDate {
            lastActivity = max(lastPost, lastEngage)
        } else if let lastPost = input.lastPostDate {
            lastActivity = lastPost
        } else if let lastEngage = input.lastEngagementDate {
            lastActivity = lastEngage
        } else {
            return 0.3 // No activity on record
        }
        
        let daysSinceActive = Date().timeIntervalSince(lastActivity) / 86400
        
        // Active within 3 days = perfect
        if daysSinceActive <= 3 { return 1.0 }
        
        // Active within a week = still good
        if daysSinceActive <= 7 { return 0.9 }
        
        // Active within 2 weeks = starting to fade
        if daysSinceActive <= 14 { return 0.75 }
        
        // Active within a month = noticeable decay
        if daysSinceActive <= 30 { return 0.5 }
        
        // Active within 3 months = significant decay
        if daysSinceActive <= 90 { return 0.3 }
        
        // 3+ months inactive = near floor
        return 0.15
    }
    
    // MARK: - 4. Community Health (20% weight)
    // Being blocked/reported is a serious signal
    
    static func calculateCommunityHealth(input: ReputationInput) -> Double {
        var health = 1.0
        
        // Blocks are the strongest signal — multiple people chose to never see you
        // 1-2 blocks: could be personal beef, minor impact
        // 3-5 blocks: pattern forming
        // 6+ blocks: serious problem
        if input.timesBlocked >= 10 {
            health -= 0.6
        } else if input.timesBlocked >= 6 {
            health -= 0.4
        } else if input.timesBlocked >= 3 {
            health -= 0.2
        } else if input.timesBlocked >= 1 {
            health -= 0.05
        }
        
        // Reports (unverified) — smaller impact per report
        // But moderation-confirmed removal is severe
        let reportImpact = min(0.3, Double(input.timesReported) * 0.05)
        health -= reportImpact
        
        // Content removed by moderation — this is confirmed bad behavior
        // Each removal is a heavy hit
        let removalImpact = min(0.5, Double(input.contentRemoved) * 0.15)
        health -= removalImpact
        
        return max(0.0, health)
    }
    
    // MARK: - 5. Integrity Health (10% weight)
    // Deleting videos after farming engagement is sketchy
    
    static func calculateIntegrityHealth(input: ReputationInput) -> Double {
        guard input.videosPosted30Days > 0 else { return 1.0 }
        
        // Deletion ratio: what % of recent posts did they delete?
        let deletionRatio = Double(input.videosDeleted30Days) / Double(input.videosPosted30Days + input.videosDeleted30Days)
        
        // Some deletion is normal (< 10%)
        if deletionRatio < 0.1 { return 1.0 }
        
        // Moderate deletion (10-30%) — maybe quality control
        if deletionRatio < 0.3 { return 0.8 }
        
        // High deletion (30-50%) — suspicious
        if deletionRatio < 0.5 { return 0.5 }
        
        // Majority deleted (50%+) — farming pattern
        return 0.2
    }
    
    // MARK: - 6. Engagement Behavior Health (15% weight)
    // Are you a troll? Do you only cool and never hype?
    
    static func calculateEngagementBehaviorHealth(input: ReputationInput) -> Double {
        let totalGiven = input.hypesGiven30Days + input.coolsGiven30Days
        guard totalGiven > 5 else { return 1.0 } // Not enough data
        
        // Cool-only ratio
        let coolOnlyRatio = Double(input.coolsGiven30Days) / Double(totalGiven)
        
        var health = 1.0
        
        // Mostly cooling (>70% cool) = troll-like behavior
        if coolOnlyRatio > 0.9 {
            health -= 0.5  // Almost exclusively negative
        } else if coolOnlyRatio > 0.7 {
            health -= 0.3  // Predominantly negative
        } else if coolOnlyRatio > 0.5 {
            health -= 0.1  // Slightly negative-leaning
        }
        
        // Engagement diversity bonus — engaging with many creators is healthy
        // Only engaging with 1-2 creators = potentially targeted harassment
        if input.uniqueCreatorsEngaged30Days < 3 && totalGiven > 20 {
            health -= 0.2  // Targeting specific creators
        }
        
        return max(0.1, health)
    }
    
    // MARK: - Tier Demotion Logic
    
    /// Check if user should be demoted based on effective clout
    /// Returns new tier if demotion is warranted, nil if no change
    static func evaluateTierDemotion(
        currentTier: UserTier,
        rawClout: Int,
        reputation: ReputationScore
    ) -> UserTier? {
        // Only evaluate if reputation is poor enough
        guard reputation.shouldEvaluateDemotion else { return nil }
        
        let effectiveClout = reputation.effectiveClout(rawClout: rawClout)
        
        // Find what tier the effective clout maps to
        let allTiers = UserTier.allCases.filter { $0.isAchievableTier }
        var mappedTier: UserTier = .rookie
        
        for tier in allTiers {
            if tier.cloutRange.contains(effectiveClout) {
                mappedTier = tier
                break
            }
        }
        
        // Only demote if mapped tier is lower than current
        let currentLevel = UserProgressionCalculator.getTierLevel(currentTier)
        let mappedLevel = UserProgressionCalculator.getTierLevel(mappedTier)
        
        if mappedLevel < currentLevel {
            // Protect against multi-tier drops — max 1 tier demotion per cycle
            let oneTierDown = allTiers.first { tier in
                UserProgressionCalculator.getTierLevel(tier) == currentLevel - 1
            }
            return oneTierDown ?? mappedTier
        }
        
        return nil
    }
    
    // MARK: - Recovery
    
    /// Calculate how much reputation recovers per day based on positive behavior
    /// This runs alongside decay — good behavior heals reputation
    static func calculateDailyRecovery(input: ReputationInput, currentReputation: Double) -> Double {
        guard currentReputation < 1.0 else { return 0.0 } // Already max
        
        var recovery = 0.0
        
        // Posting content = small recovery (shows you're contributing)
        if input.videosPosted30Days > 0 {
            recovery += 0.01
        }
        
        // Positive engagement ratio on recent content
        let totalRecent = input.totalHypesReceived + input.totalCoolsReceived
        if totalRecent > 0 {
            let recentHypeRatio = Double(input.totalHypesReceived) / Double(totalRecent)
            if recentHypeRatio > 0.8 {
                recovery += 0.02 // Content is well-received
            }
        }
        
        // Gaining followers = community trusts you
        if input.followersGained30Days > input.followersLost30Days {
            recovery += 0.01
        }
        
        // Healthy engagement behavior (more hypes than cools given)
        let totalGiven = input.hypesGiven30Days + input.coolsGiven30Days
        if totalGiven > 5 {
            let hypeGivenRatio = Double(input.hypesGiven30Days) / Double(totalGiven)
            if hypeGivenRatio > 0.6 {
                recovery += 0.01
            }
        }
        
        // Cap daily recovery at 3% — reputation heals slowly
        return min(0.03, recovery)
    }
    
    // MARK: - Decay Events (Triggered Immediately, Not Daily)
    
    /// Immediate reputation hit when someone unfollows
    static func unfollowPenalty(currentFollowers: Int) -> Double {
        guard currentFollowers > 10 else { return 0.0 } // Too small
        // Small per-unfollow hit, scales down as you grow
        return min(0.02, 1.0 / Double(currentFollowers))
    }
    
    /// Immediate reputation hit when blocked
    static func blockPenalty(totalBlocks: Int) -> Double {
        // First block: 0.02, escalates with pattern
        if totalBlocks <= 1 { return 0.02 }
        if totalBlocks <= 3 { return 0.05 }
        if totalBlocks <= 6 { return 0.08 }
        return 0.10
    }
    
    /// Immediate reputation hit when content is removed by moderation
    static func moderationRemovalPenalty(totalRemovals: Int) -> Double {
        // First removal could be a mistake, escalates
        if totalRemovals <= 1 { return 0.05 }
        if totalRemovals <= 3 { return 0.10 }
        return 0.15 // Repeat offender
    }
    
    /// Penalty for deleting a video that had engagement
    static func contentDeletionPenalty(videoHypeCount: Int, videoCoolCount: Int) -> Double {
        let totalEngagement = videoHypeCount + videoCoolCount
        
        // No penalty if video had minimal engagement (< 5)
        guard totalEngagement >= 5 else { return 0.0 }
        
        // Scaled penalty based on how much engagement was farmed
        if totalEngagement >= 100 { return 0.05 }
        if totalEngagement >= 50 { return 0.03 }
        return 0.01
    }
    
    // MARK: - Helpers
    
    private static func clamp(_ value: Double) -> Double {
        return max(0.0, min(1.0, value))
    }
}

// MARK: - Reputation Snapshot (stored in Firestore)

/// Cached daily reputation calculation
/// Path: users/{uid}/reputationHistory/{YYYY-MM-DD}
/// Client reads the latest snapshot instead of recalculating.
struct ReputationSnapshot: Codable {
    let userID: String
    let date: String                  // "2026-02-11"
    let overall: Double
    let coolRatioHealth: Double
    let retentionHealth: Double
    let activityHealth: Double
    let communityHealth: Double
    let integrityHealth: Double
    let engagementHealth: Double
    let rawClout: Int
    let effectiveClout: Int
    let currentTier: String
    let demotionWarning: Bool
    let demotedTo: String?            // nil if no demotion
    let calculatedAt: Date
    
    init(userID: String, score: ReputationScore, rawClout: Int, currentTier: UserTier, demotedTo: UserTier?) {
        self.userID = userID
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.date = formatter.string(from: Date())
        
        self.overall = score.overall
        self.coolRatioHealth = score.coolRatioHealth
        self.retentionHealth = score.retentionHealth
        self.activityHealth = score.activityHealth
        self.communityHealth = score.communityHealth
        self.integrityHealth = score.integrityHealth
        self.engagementHealth = score.engagementHealth
        self.rawClout = rawClout
        self.effectiveClout = score.effectiveClout(rawClout: rawClout)
        self.currentTier = currentTier.rawValue
        self.demotionWarning = score.shouldEvaluateDemotion
        self.demotedTo = demotedTo?.rawValue
        self.calculatedAt = Date()
    }
}

// MARK: - Reputation Event (for immediate triggers)

/// Logged when a reputation-affecting event occurs
/// Path: users/{uid}/reputationEvents/{eventID}
struct ReputationEvent: Codable {
    let id: String
    let userID: String
    let eventType: ReputationEventType
    let penalty: Double               // How much reputation was deducted
    let details: String               // Human-readable description
    let createdAt: Date
    
    init(userID: String, type: ReputationEventType, penalty: Double, details: String) {
        self.id = UUID().uuidString
        self.userID = userID
        self.eventType = type
        self.penalty = penalty
        self.details = details
        self.createdAt = Date()
    }
}

enum ReputationEventType: String, Codable {
    case unfollowed          // Someone unfollowed this user
    case blocked             // Someone blocked this user
    case contentRemoved      // Moderation removed content
    case contentDeleted      // User deleted their own engaged content
    case trollBehavior       // Cool-only engagement pattern detected
    case inactivityDecay     // Daily inactivity penalty
    case dailyRecovery       // Positive daily recovery
    case tierDemotion        // User was demoted
}

// MARK: - Testing

extension ReputationDecayCalculator {
    
    /// Test with realistic scenarios
    static func runTests() -> String {
        var report = "🧪 REPUTATION DECAY TESTS\n\n"
        
        // Healthy creator
        let healthy = ReputationInput(
            totalHypesReceived: 500, totalCoolsReceived: 30, totalVideos: 25,
            averageEngagementRate: 0.15,
            currentFollowers: 200, followersGained30Days: 20, followersLost30Days: 3,
            timesBlocked: 0, timesReported: 0, contentRemoved: 0,
            lastPostDate: Date().addingTimeInterval(-86400), lastEngagementDate: Date(),
            accountAge: 90 * 86400,
            videosDeleted30Days: 1, videosPosted30Days: 8,
            hypesGiven30Days: 50, coolsGiven30Days: 5, uniqueCreatorsEngaged30Days: 15,
            currentTier: .veteran, rawClout: 5000
        )
        let healthyScore = calculateReputation(input: healthy)
        report += "✅ HEALTHY CREATOR:\n"
        report += "   Overall: \(String(format: "%.2f", healthyScore.overall)) (\(healthyScore.grade))\n"
        report += "   Effective clout: \(healthyScore.effectiveClout(rawClout: 5000))/5000\n\n"
        
        // Troll (cool-only, few creators)
        let troll = ReputationInput(
            totalHypesReceived: 10, totalCoolsReceived: 50, totalVideos: 2,
            averageEngagementRate: 0.02,
            currentFollowers: 5, followersGained30Days: 0, followersLost30Days: 2,
            timesBlocked: 4, timesReported: 3, contentRemoved: 0,
            lastPostDate: Date().addingTimeInterval(-30 * 86400), lastEngagementDate: Date(),
            accountAge: 60 * 86400,
            videosDeleted30Days: 0, videosPosted30Days: 0,
            hypesGiven30Days: 3, coolsGiven30Days: 80, uniqueCreatorsEngaged30Days: 2,
            currentTier: .rising, rawClout: 1500
        )
        let trollScore = calculateReputation(input: troll)
        report += "🚨 TROLL PATTERN:\n"
        report += "   Overall: \(String(format: "%.2f", trollScore.overall)) (\(trollScore.grade))\n"
        report += "   Effective clout: \(trollScore.effectiveClout(rawClout: 1500))/1500\n"
        report += "   Should demote: \(trollScore.shouldEvaluateDemotion)\n\n"
        
        // Inactive creator (was big, went dark)
        let inactive = ReputationInput(
            totalHypesReceived: 2000, totalCoolsReceived: 100, totalVideos: 50,
            averageEngagementRate: 0.2,
            currentFollowers: 500, followersGained30Days: 2, followersLost30Days: 40,
            timesBlocked: 0, timesReported: 0, contentRemoved: 0,
            lastPostDate: Date().addingTimeInterval(-120 * 86400), lastEngagementDate: Date().addingTimeInterval(-90 * 86400),
            accountAge: 365 * 86400,
            videosDeleted30Days: 0, videosPosted30Days: 0,
            hypesGiven30Days: 0, coolsGiven30Days: 0, uniqueCreatorsEngaged30Days: 0,
            currentTier: .influencer, rawClout: 15000
        )
        let inactiveScore = calculateReputation(input: inactive)
        report += "💤 INACTIVE CREATOR:\n"
        report += "   Overall: \(String(format: "%.2f", inactiveScore.overall)) (\(inactiveScore.grade))\n"
        report += "   Effective clout: \(inactiveScore.effectiveClout(rawClout: 15000))/15000\n"
        report += "   Activity health: \(String(format: "%.2f", inactiveScore.activityHealth))\n\n"
        
        // Engagement farmer (posts and deletes)
        let farmer = ReputationInput(
            totalHypesReceived: 300, totalCoolsReceived: 20, totalVideos: 10,
            averageEngagementRate: 0.1,
            currentFollowers: 100, followersGained30Days: 10, followersLost30Days: 5,
            timesBlocked: 1, timesReported: 2, contentRemoved: 0,
            lastPostDate: Date(), lastEngagementDate: Date(),
            accountAge: 60 * 86400,
            videosDeleted30Days: 15, videosPosted30Days: 20,
            hypesGiven30Days: 20, coolsGiven30Days: 10, uniqueCreatorsEngaged30Days: 8,
            currentTier: .veteran, rawClout: 5000
        )
        let farmerScore = calculateReputation(input: farmer)
        report += "🚜 ENGAGEMENT FARMER:\n"
        report += "   Overall: \(String(format: "%.2f", farmerScore.overall)) (\(farmerScore.grade))\n"
        report += "   Integrity health: \(String(format: "%.2f", farmerScore.integrityHealth))\n"
        report += "   Effective clout: \(farmerScore.effectiveClout(rawClout: 5000))/5000\n\n"
        
        report += "✅ Reputation Decay Tests Complete!\n"
        return report
    }
}