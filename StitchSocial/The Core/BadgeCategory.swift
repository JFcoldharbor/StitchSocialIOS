//
//  BadgeTypes.swift
//  StitchSocial
//
//  Layer 1: Data Types — Complete Badge System incl. Social Signal Badges
//  FIXED: Removed duplicate tier_rookie/tier_rising entries (caused _badgeLookup crash)
//  FIXED: EarnedBadge decodes Firestore Timestamp → Date (was silently returning 0 badges)

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Badge Category

enum BadgeCategory: String, CaseIterable, Codable {
    case seasonal     = "seasonal"
    case hypeMaster   = "hype_master"
    case coolVillain  = "cool_villain"
    case creator      = "creator"
    case engagement   = "engagement"
    case reputation   = "reputation"
    case social       = "social"
    case socialSignal = "social_signal"
    case special      = "special"

    var displayName: String {
        switch self {
        case .seasonal:     return "Seasonal"
        case .hypeMaster:   return "Hype Master"
        case .coolVillain:  return "Cool Villain"
        case .creator:      return "Creator"
        case .engagement:   return "Engagement"
        case .reputation:   return "Reputation"
        case .social:       return "Social"
        case .socialSignal: return "Signal"
        case .special:      return "Special"
        }
    }

    var accentColor: Color {
        switch self {
        case .seasonal:     return .orange
        case .hypeMaster:   return .yellow
        case .coolVillain:  return .purple
        case .creator:      return .blue
        case .engagement:   return .green
        case .reputation:   return .red
        case .social:       return .cyan
        case .socialSignal: return Color(red: 0.40, green: 0.80, blue: 1.00)
        case .special:      return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }
}

// MARK: - Season

enum BadgeSeason: String, Codable, CaseIterable {
    case halloween = "halloween"
    case christmas = "christmas"
    case summer    = "summer"
    case newYear   = "new_year"

    var displayName: String {
        switch self {
        case .halloween: return "Halloween"
        case .christmas: return "Christmas"
        case .summer:    return "Summer"
        case .newYear:   return "New Year"
        }
    }

    func isActive(on date: Date = Date()) -> Bool {
        let cal   = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        switch self {
        case .halloween: return month == 10
        case .christmas: return month == 12 && day <= 26
        case .summer:    return month == 6 || month == 7 || month == 8
        case .newYear:   return (month == 12 && day >= 28) || (month == 1 && day <= 7)
        }
    }

    var hypeBoostMultiplier: Double {
        switch self {
        case .halloween: return 1.20
        case .christmas: return 1.25
        case .summer:    return 1.10
        case .newYear:   return 1.15
        }
    }
}

// MARK: - Badge Rarity

enum BadgeRarity: Int, Codable, Comparable {
    case common    = 1
    case uncommon  = 2
    case rare      = 3
    case epic      = 4
    case legendary = 5

    static func < (lhs: BadgeRarity, rhs: BadgeRarity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .common:    return "Common"
        case .uncommon:  return "Uncommon"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        }
    }

    var glowColor: Color {
        switch self {
        case .common:    return .gray
        case .uncommon:  return .green
        case .rare:      return .blue
        case .epic:      return .purple
        case .legendary: return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }
}

// MARK: - Signal Badge Grade

enum SignalBadgeGrade: Int, Codable, CaseIterable, Comparable {
    case bronze   = 1
    case silver   = 2
    case gold     = 3
    case platinum = 4

    static func < (lhs: SignalBadgeGrade, rhs: SignalBadgeGrade) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }

    var color: Color {
        switch self {
        case .bronze:   return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver:   return Color(red: 0.75, green: 0.75, blue: 0.75)
        case .gold:     return Color(red: 1.00, green: 0.84, blue: 0.00)
        case .platinum: return Color(red: 0.60, green: 0.90, blue: 1.00)
        }
    }
}

// MARK: - Signal Badge Kind

enum SignalBadgeKind: String, Codable, CaseIterable {
    case influencerHype    = "influencer_hype"
    case singlePostSignals = "single_post_signals"
    case multiTierSignals  = "multi_tier_signals"
    case founderSignal     = "founder_signal"

    var displayName: String {
        switch self {
        case .influencerHype:    return "Signal Magnet"
        case .singlePostSignals: return "Viral Spark"
        case .multiTierSignals:  return "Cross-Tier Pull"
        case .founderSignal:     return "Founder's Pick"
        }
    }

    var emoji: String {
        switch self {
        case .influencerHype:    return "📡"
        case .singlePostSignals: return "⚡"
        case .multiTierSignals:  return "🌐"
        case .founderSignal:     return "🛡️"
        }
    }

    var badgeDescription: String {
        switch self {
        case .influencerHype:    return "Partner+ tier users hyped your content."
        case .singlePostSignals: return "Multiple Partner+ users signaled the same post."
        case .multiTierSignals:  return "Users from 3+ different tiers signaled your content."
        case .founderSignal:     return "A Founder or Co-Founder hyped your post."
        }
    }

    func threshold(for grade: SignalBadgeGrade) -> Int {
        switch (self, grade) {
        case (.influencerHype,    .bronze):   return 1
        case (.influencerHype,    .silver):   return 5
        case (.influencerHype,    .gold):     return 20
        case (.influencerHype,    .platinum): return 50
        case (.singlePostSignals, .bronze):   return 1
        case (.singlePostSignals, .silver):   return 3
        case (.singlePostSignals, .gold):     return 7
        case (.singlePostSignals, .platinum): return 15
        case (.multiTierSignals,  .bronze):   return 2
        case (.multiTierSignals,  .silver):   return 3
        case (.multiTierSignals,  .gold):     return 5
        case (.multiTierSignals,  .platinum): return 8
        case (.founderSignal,     .bronze):   return 1
        case (.founderSignal,     .silver):   return 3
        case (.founderSignal,     .gold):     return 7
        case (.founderSignal,     .platinum): return 15
        }
    }

    func badgeID(grade: SignalBadgeGrade) -> String {
        "signal_\(rawValue)_\(grade.rawValue)"
    }

    private func rarity(for grade: SignalBadgeGrade) -> BadgeRarity {
        switch grade {
        case .bronze:   return .uncommon
        case .silver:   return .rare
        case .gold:     return .epic
        case .platinum: return .legendary
        }
    }

    var allGrades: [BadgeDefinition] {
        SignalBadgeGrade.allCases.map { grade in
            let gradeEmoji: String
            switch grade {
            case .bronze:   gradeEmoji = "\(emoji)🥉"
            case .silver:   gradeEmoji = "\(emoji)🥈"
            case .gold:     gradeEmoji = "\(emoji)🥇"
            case .platinum: gradeEmoji = "\(emoji)💠"
            }
            var req = BadgeRequirements()
            req.minSignalCount   = threshold(for: grade)
            req.signalBadgeKind  = rawValue
            req.signalBadgeGrade = grade.rawValue
            return BadgeDefinition(
                id: badgeID(grade: grade),
                name: "\(displayName) — \(grade.label)",
                description: "\(badgeDescription) (\(threshold(for: grade))+ required)",
                emoji: gradeEmoji,
                category: .socialSignal,
                rarity: rarity(for: grade),
                requirements: req
            )
        }
    }
}

// MARK: - Signal Stats

struct SignalStats: Codable {
    var totalInfluencerHypes:  Int = 0
    var peakSinglePostSignals: Int = 0
    var distinctTierCount:     Int = 0
    var founderHypeCount:      Int = 0

    func count(for kind: SignalBadgeKind) -> Int {
        switch kind {
        case .influencerHype:    return totalInfluencerHypes
        case .singlePostSignals: return peakSinglePostSignals
        case .multiTierSignals:  return distinctTierCount
        case .founderSignal:     return founderHypeCount
        }
    }
}

// MARK: - Signal Badge Evaluator

struct SignalBadgeEvaluator {

    static func evaluate(stats: SignalStats, alreadyEarned: Set<String>) -> [EarnedBadge] {
        var toAward: [EarnedBadge] = []
        let now = Date()
        for kind in SignalBadgeKind.allCases {
            let count = stats.count(for: kind)
            for grade in SignalBadgeGrade.allCases {
                let id = kind.badgeID(grade: grade)
                guard !alreadyEarned.contains(id), count >= kind.threshold(for: grade) else { continue }
                toAward.append(EarnedBadge(id: id, earnedAt: now, isPinned: false, isNew: true))
            }
        }
        return toAward
    }

    static func progress(stats: SignalStats, alreadyEarned: Set<String>) -> [BadgeProgress] {
        var result: [BadgeProgress] = []
        for kind in SignalBadgeKind.allCases {
            let count = stats.count(for: kind)
            guard let nextGrade = SignalBadgeGrade.allCases.first(where: {
                !alreadyEarned.contains(kind.badgeID(grade: $0))
            }) else { continue }
            let target   = kind.threshold(for: nextGrade)
            let fraction = min(1.0, Double(count) / Double(target))
            guard let def = BadgeDefinition.findBadge(id: kind.badgeID(grade: nextGrade)) else { continue }
            result.append(BadgeProgress(id: def.id, definition: def,
                                        progressFraction: fraction,
                                        currentValue: count, targetValue: target))
        }
        return result
    }
}

// MARK: - Badge Requirements

struct BadgeRequirements: Codable {
    var minXP: Int            = 0
    var minHypesGiven: Int    = 0
    var minCoolsGiven: Int    = 0
    var minPosts: Int         = 0
    var minFollowers: Int     = 0
    var minHypesReceived: Int = 0
    var minClout: Int         = 0
    var requiredTier: String? = nil
    var seasonRequired: BadgeSeason? = nil
    var isManuallyAwarded: Bool = false
    var minSignalCount: Int      = 0
    var signalBadgeKind: String? = nil
    var signalBadgeGrade: Int    = 0
    var minCoinsGiven: Int        = 0
    var minSubscriptionsGiven: Int = 0
    var minSubscribersEarned: Int  = 0
}

// MARK: - Badge Definition

struct BadgeDefinition: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let category: BadgeCategory
    let rarity: BadgeRarity
    let requirements: BadgeRequirements
    var season: BadgeSeason?       = nil
    var grantsSeasonalBoost: Bool  = false

    static let allBadges: [BadgeDefinition] = {
        var b: [BadgeDefinition] = []

        // ── Seasonal ──────────────────────────────────────────
        b.append(.init(id: "halloween_pumpkin", name: "Pumpkin King",
            description: "Collected during Halloween. Grants 20% hype boost while active.",
            emoji: "🎃", category: .seasonal, rarity: .rare,
            requirements: BadgeRequirements(minXP: 500, seasonRequired: .halloween),
            season: .halloween, grantsSeasonalBoost: true))
        b.append(.init(id: "halloween_ghost", name: "Ghost Mode",
            description: "The silent haunter. 50 cools during Halloween.",
            emoji: "👻", category: .seasonal, rarity: .epic,
            requirements: BadgeRequirements(minCoolsGiven: 50, seasonRequired: .halloween),
            season: .halloween, grantsSeasonalBoost: true))
        b.append(.init(id: "christmas_elf", name: "Hype Elf",
            description: "Spread holiday hype. 25% boost active.",
            emoji: "🎄", category: .seasonal, rarity: .rare,
            requirements: BadgeRequirements(minXP: 0, minHypesGiven: 100, seasonRequired: .christmas),
            season: .christmas, grantsSeasonalBoost: true))
        b.append(.init(id: "christmas_legend", name: "Santa's Favorite",
            description: "Top 1% hype giver in December.",
            emoji: "🎅", category: .seasonal, rarity: .legendary,
            requirements: BadgeRequirements(minXP: 5000, minHypesGiven: 500, seasonRequired: .christmas),
            season: .christmas, grantsSeasonalBoost: true))
        b.append(.init(id: "summer_vibe", name: "Summer Vibe",
            description: "Kept the hype alive all summer.",
            emoji: "🌊", category: .seasonal, rarity: .uncommon,
            requirements: BadgeRequirements(minXP: 0, minHypesGiven: 50, seasonRequired: .summer),
            season: .summer, grantsSeasonalBoost: true))
        b.append(.init(id: "new_year_blast", name: "New Year Blaster",
            description: "Rang in the new year with maximum hype.",
            emoji: "🎆", category: .seasonal, rarity: .rare,
            requirements: BadgeRequirements(minXP: 1000, seasonRequired: .newYear),
            season: .newYear, grantsSeasonalBoost: true))

        // ── Hype Master ───────────────────────────────────────
        b.append(.init(id: "hype_initiate", name: "Hype Initiate",
            description: "Gave 100 hypes. The journey begins.", emoji: "🔥",
            category: .hypeMaster, rarity: .common,
            requirements: BadgeRequirements(minXP: 0, minHypesGiven: 100)))
        b.append(.init(id: "hype_master", name: "Hype Master",
            description: "Gave 1,000 hypes. You fuel the platform.", emoji: "⚡",
            category: .hypeMaster, rarity: .rare,
            requirements: BadgeRequirements(minXP: 2000, minHypesGiven: 1000)))
        b.append(.init(id: "hype_overlord", name: "Hype Overlord",
            description: "10,000 hypes given. You ARE the hype.", emoji: "👑",
            category: .hypeMaster, rarity: .legendary,
            requirements: BadgeRequirements(minXP: 10000, minHypesGiven: 10000, minClout: 50000)))

        // ── Cool Villain ──────────────────────────────────────
        b.append(.init(id: "cool_villain_rookie", name: "Petty Villain",
            description: "Dropped 50 cools. Chaos is your thing.", emoji: "😈",
            category: .coolVillain, rarity: .common,
            requirements: BadgeRequirements(minCoolsGiven: 50)))
        b.append(.init(id: "cool_villain_mid", name: "Cooldown Commander",
            description: "500 cools given. The platform respects your no.", emoji: "🦹",
            category: .coolVillain, rarity: .rare,
            requirements: BadgeRequirements(minXP: 1500, minCoolsGiven: 500)))
        b.append(.init(id: "cool_villain_legend", name: "The Villain Era",
            description: "5,000 cools. You are the anti-hype.", emoji: "💀",
            category: .coolVillain, rarity: .legendary,
            requirements: BadgeRequirements(minXP: 8000, minCoolsGiven: 5000, minClout: 20000)))

        // ── Creator ───────────────────────────────────────────
        b.append(.init(id: "first_post", name: "First Drop",
            description: "Posted your first video.", emoji: "🎬",
            category: .creator, rarity: .common,
            requirements: BadgeRequirements(minPosts: 1)))
        b.append(.init(id: "content_grinder", name: "Content Grinder",
            description: "50 posts. The grind is real.", emoji: "📹",
            category: .creator, rarity: .uncommon,
            requirements: BadgeRequirements(minXP: 1000, minPosts: 50)))
        b.append(.init(id: "prolific_creator", name: "Prolific Creator",
            description: "100 posts. You never stop.", emoji: "🎥",
            category: .creator, rarity: .rare,
            requirements: BadgeRequirements(minXP: 3000, minPosts: 100)))

        // ── Engagement ────────────────────────────────────────
        b.append(.init(id: "xp_climber", name: "XP Climber",
            description: "Reached 1,000 XP.", emoji: "📈",
            category: .engagement, rarity: .uncommon,
            requirements: BadgeRequirements(minXP: 1000)))
        b.append(.init(id: "clout_earner", name: "Clout Earner",
            description: "10,000 clout accumulated.", emoji: "💎",
            category: .engagement, rarity: .rare,
            requirements: BadgeRequirements(minXP: 2000, minClout: 10000)))
        b.append(.init(id: "clout_champion", name: "Clout Champion",
            description: "100,000 clout. Undeniable.", emoji: "🏆",
            category: .engagement, rarity: .legendary,
            requirements: BadgeRequirements(minXP: 20000, minClout: 100000)))

        // ── Big Tipper chain ──────────────────────────────────
        b.append(.init(id: "tipper", name: "Tipper",
            description: "Tipped 500 HypeCoins to other creators.", emoji: "💸",
            category: .engagement, rarity: .common,
            requirements: BadgeRequirements(minCoinsGiven: 500)))
        b.append(.init(id: "big_tipper", name: "Big Tipper",
            description: "Tipped 5,000 HypeCoins. You back your creators.", emoji: "🤑",
            category: .engagement, rarity: .rare,
            requirements: BadgeRequirements(minCoinsGiven: 5000)))
        b.append(.init(id: "whale", name: "Whale",
            description: "Tipped 50,000 HypeCoins. The platform lives because of you.", emoji: "🐋",
            category: .engagement, rarity: .legendary,
            requirements: BadgeRequirements(minCoinsGiven: 50000)))

        // ── Social ────────────────────────────────────────────
        b.append(.init(id: "networker", name: "Networker",
            description: "100 followers.", emoji: "🤝",
            category: .social, rarity: .common,
            requirements: BadgeRequirements(minFollowers: 100)))
        b.append(.init(id: "popular", name: "Popular",
            description: "1,000 followers.", emoji: "🌟",
            category: .social, rarity: .uncommon,
            requirements: BadgeRequirements(minFollowers: 1000)))
        b.append(.init(id: "influencer_badge", name: "Influencer",
            description: "10,000 followers. You're the real deal.", emoji: "💫",
            category: .social, rarity: .epic,
            requirements: BadgeRequirements(minXP: 5000, minFollowers: 10000)))
        b.append(.init(id: "first_sub", name: "First Sub",
            description: "Subscribed to your first creator.", emoji: "🎟️",
            category: .social, rarity: .common,
            requirements: BadgeRequirements(minSubscriptionsGiven: 1)))
        b.append(.init(id: "loyal_supporter", name: "Loyal Supporter",
            description: "Subscribed to 5 creators. True community member.", emoji: "💪",
            category: .social, rarity: .uncommon,
            requirements: BadgeRequirements(minSubscriptionsGiven: 5)))
        b.append(.init(id: "super_fan", name: "Super Fan",
            description: "Subscribed to 10 creators. You are the backbone.", emoji: "🫶",
            category: .social, rarity: .rare,
            requirements: BadgeRequirements(minSubscriptionsGiven: 10)))

        // ── Creator — subscriber earned ───────────────────────
        b.append(.init(id: "first_subscriber", name: "First Subscriber",
            description: "Someone believed in you enough to subscribe.", emoji: "🌟",
            category: .creator, rarity: .common,
            requirements: BadgeRequirements(minSubscribersEarned: 1)))
        b.append(.init(id: "growing_community", name: "Growing Community",
            description: "50 subscribers. Your community is real.", emoji: "🌱",
            category: .creator, rarity: .uncommon,
            requirements: BadgeRequirements(minSubscribersEarned: 50)))
        b.append(.init(id: "subscriber_king", name: "Subscriber King",
            description: "500 subscribers. You built something.", emoji: "👑",
            category: .creator, rarity: .epic,
            requirements: BadgeRequirements(minSubscribersEarned: 500)))

        // ── Reputation / Tier (NO DUPLICATES) ─────────────────
        b.append(.init(id: "tier_rookie", name: "Rookie",
            description: "Welcome to StitchSocial. Your journey starts here.", emoji: "🌱",
            category: .reputation, rarity: .common,
            requirements: BadgeRequirements(requiredTier: "rookie")))
        b.append(.init(id: "tier_rising", name: "Rising",
            description: "Reached Rising tier. 1,000 clout strong.", emoji: "📶",
            category: .reputation, rarity: .uncommon,
            requirements: BadgeRequirements(requiredTier: "rising")))
        b.append(.init(id: "tier_veteran", name: "Veteran",
            description: "Reached Veteran tier.", emoji: "🎖️",
            category: .reputation, rarity: .uncommon,
            requirements: BadgeRequirements(requiredTier: "veteran")))
        b.append(.init(id: "tier_influencer", name: "Influencer",
            description: "Reached Influencer tier. 10,000 clout.", emoji: "💫",
            category: .reputation, rarity: .rare,
            requirements: BadgeRequirements(requiredTier: "influencer")))
        b.append(.init(id: "tier_ambassador", name: "Ambassador",
            description: "Reached Ambassador tier. 15,000 clout.", emoji: "🌐",
            category: .reputation, rarity: .rare,
            requirements: BadgeRequirements(requiredTier: "ambassador")))
        b.append(.init(id: "tier_elite", name: "Elite",
            description: "Reached Elite tier.", emoji: "🔱",
            category: .reputation, rarity: .epic,
            requirements: BadgeRequirements(requiredTier: "elite")))
        b.append(.init(id: "tier_partner", name: "Partner",
            description: "Reached Partner tier. 50,000 clout.", emoji: "🤝",
            category: .reputation, rarity: .epic,
            requirements: BadgeRequirements(requiredTier: "partner")))
        b.append(.init(id: "tier_legendary", name: "Legendary Status",
            description: "Reached Legendary tier.", emoji: "⚜️",
            category: .reputation, rarity: .legendary,
            requirements: BadgeRequirements(requiredTier: "legendary")))
        b.append(.init(id: "tier_top_creator", name: "Top Creator",
            description: "Reached Top Creator tier. 500,000 clout.", emoji: "🚀",
            category: .reputation, rarity: .legendary,
            requirements: BadgeRequirements(requiredTier: "top_creator")))
        b.append(.init(id: "tier_founder_crest", name: "Founder Crest",
            description: "The architect. Built this from nothing.", emoji: "🏛️",
            category: .reputation, rarity: .legendary,
            requirements: BadgeRequirements(isManuallyAwarded: true)))

        // ── Special ───────────────────────────────────────────
        b.append(.init(id: "founder_badge", name: "Founder",
            description: "One of the original founders.", emoji: "🛡️",
            category: .special, rarity: .legendary,
            requirements: BadgeRequirements(isManuallyAwarded: true)))
        b.append(.init(id: "beta_tester", name: "Beta Tester",
            description: "Helped shape the platform before launch.", emoji: "🧪",
            category: .special, rarity: .epic,
            requirements: BadgeRequirements(isManuallyAwarded: true)))
        b.append(.init(id: "early_adopter", name: "Early Adopter",
            description: "Joined StitchSocial in its founding era (before July 2026).", emoji: "🌅",
            category: .special, rarity: .rare,
            requirements: BadgeRequirements(isManuallyAwarded: true)))

        // ── Social Signal — 16 badges (4 kinds × 4 grades) ───
        b.append(contentsOf: SignalBadgeKind.allCases.flatMap { $0.allGrades })

        return b
    }()

    static func findBadge(id: String) -> BadgeDefinition? { _badgeLookup[id] }
    static func badge(id: String)     -> BadgeDefinition? { _badgeLookup[id] }
}

/// Built once at app launch — nonisolated, safe for use anywhere
private let _badgeLookup: [String: BadgeDefinition] = {
    Dictionary(uniqueKeysWithValues: BadgeDefinition.allBadges.map { ($0.id, $0) })
}()

// MARK: - Earned Badge
// FIXED: Custom decoder handles Firestore Timestamp → Date (was silently failing)

struct EarnedBadge: Identifiable, Codable {
    let id: String
    let earnedAt: Date
    var isPinned: Bool
    var isNew: Bool

    var definition: BadgeDefinition? { BadgeDefinition.findBadge(id: id) }

    enum CodingKeys: String, CodingKey {
        case id, earnedAt, isPinned, isNew
    }

    init(id: String, earnedAt: Date, isPinned: Bool, isNew: Bool) {
        self.id       = id
        self.earnedAt = earnedAt
        self.isPinned = isPinned
        self.isNew    = isNew
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isNew    = try c.decodeIfPresent(Bool.self, forKey: .isNew)    ?? true

        // Firestore Timestamp → Date
        if let ts = try? c.decode(Timestamp.self, forKey: .earnedAt) {
            earnedAt = ts.dateValue()
        } else {
            earnedAt = try c.decodeIfPresent(Date.self, forKey: .earnedAt) ?? Date()
        }
    }
}

// MARK: - Badge Progress

struct BadgeProgress: Identifiable {
    let id: String
    let definition: BadgeDefinition
    var progressFraction: Double
    var currentValue: Int
    var targetValue: Int
}
