//
//  SubscriptionTier.swift
//  StitchSocial
//
//  Subscription system models — single subscription level per creator.
//  Perks are automatic based on creator's UserTier, not fan payment.
//
//  UPDATED: Removed .supporter/.superFan two-tier system.
//  Now: subscribe = one level. Perks scale with creator tier.
//  Pricing: Rookie–Veteran fixed 100. Influencer+ custom (100/250/500/1000/2500). Matches HypeCoinPackage tiers.
//  Cycles: 60-day first, 30-day recurring.
//

import Foundation
import FirebaseFirestore

// MARK: - Coin Price Options

/// Fixed price tiers creators can choose from (Influencer+).
/// Rookie–Veteran locked at 200.
enum CoinPriceTier: Int, CaseIterable, Codable {
    case starter  = 100
    case basic    = 250
    case plus     = 500
    case pro      = 1000
    case max      = 2500

    var displayName: String {
        switch self {
        case .starter: return "Starter"
        case .basic:   return "Basic"
        case .plus:    return "Plus"
        case .pro:     return "Pro"
        case .max:     return "Max"
        }
    }

    var coinsDisplay: String { "\(rawValue) coins/month" }
}

// MARK: - Subscription Perks (Auto from Creator Tier)

/// Perks a subscriber gets — determined by the CREATOR's tier, not payment amount.
/// Creators cannot toggle these yet (future feature).
enum SubscriptionPerk: String, Codable, CaseIterable, Hashable {
    case supportBadge = "support_badge"
    case communityAccess = "community_access"
    case exclusiveCollections = "exclusive_collections"
    case noAds = "no_ads"
    case dmAccess = "dm_access"
    case priorityQA = "priority_qa"
    case earlyContent = "early_content"
    case exclusiveEmotes = "exclusive_emotes"
    case commentHighlights = "comment_highlights"
    case coHostEligibility = "co_host_eligibility"
    case hypeBoost5 = "hype_boost_5"
    case hypeBoost10 = "hype_boost_10"
    case hypeBoost15 = "hype_boost_15"
    case hypeBoost20 = "hype_boost_20"
    case communityMod = "community_mod"
    
    var displayName: String {
        switch self {
        case .supportBadge: return "Supporter Badge"
        case .communityAccess: return "Community Access"
        case .exclusiveCollections: return "Exclusive Collections"
        case .noAds: return "Ad-Free Viewing"
        case .dmAccess: return "DM Creator"
        case .priorityQA: return "Priority Q&A"
        case .earlyContent: return "Early Content Access"
        case .exclusiveEmotes: return "Exclusive Emotes"
        case .commentHighlights: return "Comment Highlights"
        case .coHostEligibility: return "Co-Host Eligibility"
        case .communityMod: return "Community Mod"
        case .hypeBoost5: return "5% Hype Boost"
        case .hypeBoost10: return "10% Hype Boost"
        case .hypeBoost15: return "15% Hype Boost"
        case .hypeBoost20: return "20% Hype Boost"
        }
    }
    
    var icon: String {
        switch self {
        case .supportBadge: return "star.fill"
        case .communityAccess: return "bubble.left.and.bubble.right.fill"
        case .exclusiveCollections: return "rectangle.stack.fill"
        case .noAds: return "eye.slash"
        case .dmAccess: return "message.fill"
        case .priorityQA: return "questionmark.bubble.fill"
        case .earlyContent: return "clock.fill"
        case .exclusiveEmotes: return "face.smiling.fill"
        case .commentHighlights: return "text.bubble.fill"
        case .coHostEligibility: return "person.2.fill"
        case .hypeBoost5, .hypeBoost10, .hypeBoost15, .hypeBoost20: return "flame.fill"
        case .communityMod: return "shield.lefthalf.filled"
        }
    }
}

// MARK: - Perks by Creator Tier

/// Returns the perks a subscriber gets based on the CREATOR's tier.
/// Perks are cumulative — higher tiers include all lower tier perks.
enum SubscriptionPerks {
    
    // MARK: - Perks by Subscription Coin Tier
    // Tied to CoinPriceTier spend, not creator tier.
    // Cumulative — each tier includes all tiers below it.
    //
    // Starter  100  — Supporter Badge
    // Basic    250  — + Community Access
    // Plus     500  — + Ad-Free Viewing, DM Creator          ($9.99 threshold)
    // Pro     1000  — + Exclusive Collections, Hype Boost 15%, Early Content, Comment Highlights
    // Max     2500  — + Hype Boost 20%, Priority Q&A, Exclusive Emotes, Co-Host, Community Mod

    static func perks(for creatorTier: UserTier) -> [SubscriptionPerk] {
        switch creatorTier {
        case .rookie, .rising:
            return [.supportBadge, .communityAccess]

        case .veteran:
            return [.supportBadge, .communityAccess]
            // NOTE: communityAccess only granted at 250+ coins (Basic tier)
            // hasCommunityAccess gated by CoinPriceTier, not creator tier alone

        case .influencer:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess]

        case .ambassador:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess,
                    .exclusiveCollections, .hypeBoost15, .earlyContent, .commentHighlights]

        case .elite:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess,
                    .exclusiveCollections, .hypeBoost15, .earlyContent, .commentHighlights,
                    .hypeBoost20, .priorityQA, .exclusiveEmotes, .coHostEligibility, .communityMod]

        case .partner, .legendary, .topCreator, .founder, .coFounder:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess,
                    .exclusiveCollections, .hypeBoost20, .earlyContent, .commentHighlights,
                    .priorityQA, .exclusiveEmotes, .coHostEligibility, .communityMod]

        case .business:
            return []
        }
    }

    /// Perks unlocked at a specific CoinPriceTier spend level (cumulative)
    static func perks(for coinTier: CoinPriceTier) -> [SubscriptionPerk] {
        switch coinTier {
        case .starter:
            return [.supportBadge, .communityAccess]
        case .basic:
            return [.supportBadge, .communityAccess]
        case .plus:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess]
        case .pro:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess,
                    .exclusiveCollections, .hypeBoost15, .earlyContent, .commentHighlights]
        case .max:
            return [.supportBadge, .communityAccess, .noAds, .dmAccess,
                    .exclusiveCollections, .hypeBoost20, .earlyContent, .commentHighlights,
                    .priorityQA, .exclusiveEmotes, .coHostEligibility, .communityMod]
        }
    }
    
    /// Get the hype boost percentage for a creator tier's subscribers
    static func hypeBoost(for creatorTier: UserTier) -> Double {
        let p = perks(for: creatorTier)
        if p.contains(.hypeBoost20) { return 0.20 }
        if p.contains(.hypeBoost15) { return 0.15 }
        return 0.0
    }

    static func hypeBoost(for coinTier: CoinPriceTier) -> Double {
        let p = perks(for: coinTier)
        if p.contains(.hypeBoost20) { return 0.20 }
        if p.contains(.hypeBoost15) { return 0.15 }
        return 0.0
    }

    static func hasCommunityMod(coinTier: CoinPriceTier) -> Bool {
        perks(for: coinTier).contains(.communityMod)
    }
    
    /// Whether subscribing to this creator tier grants community access
    /// Community access requires BOTH creator tier >= veteran AND subscriber coinTier >= basic (250)
    static func hasCommunityAccess(creatorTier: UserTier, coinTier: CoinPriceTier = .basic) -> Bool {
        perks(for: creatorTier).contains(.communityAccess) && perks(for: coinTier).contains(.communityAccess)
    }
    
    /// Whether subscribing to this creator tier grants ad-free viewing
    static func hasNoAds(creatorTier: UserTier) -> Bool {
        perks(for: creatorTier).contains(.noAds)
    }
}

// MARK: - Creator Subscription Plan

/// One plan per creator. Single price (not tiered).
/// Firestore: subscription_plans/{creatorID}
/// Custom perk assignments per tier set by the creator.
/// Prices are fixed platform constants (CoinPriceTier.rawValue).
/// Supporter Badge auto-granted at every tier — not stored here.
/// CACHING: Stored in SubscriptionService.creatorPlanCache (10min TTL).
struct TierPricing: Codable {

    /// Key: CoinPriceTier.rawValue (String), Value: [SubscriptionPerk.rawValue]
    var customPerks: [String: [String]] = [:]

    // MARK: Price — fixed, not customizable
    func price(for tier: CoinPriceTier) -> Int { tier.rawValue }

    // MARK: Perks

    /// Returns perks for a tier. Supporter Badge always included.
    /// Uses creator custom config if set, otherwise platform defaults.
    func perks(for tier: CoinPriceTier) -> [SubscriptionPerk] {
        let key = String(tier.rawValue)
        if let raw = customPerks[key] {
            var perks: [SubscriptionPerk] = [.supportBadge]
            let custom = raw.compactMap { SubscriptionPerk(rawValue: $0) }
                           .filter { $0 != .supportBadge }
            perks.append(contentsOf: custom)
            return perks
        }
        return SubscriptionPerks.perks(for: tier) // platform default
    }

    mutating func setPerks(_ perks: [SubscriptionPerk], for tier: CoinPriceTier) {
        let key = String(tier.rawValue)
        // Always store without supportBadge — it's auto-added on read
        let filtered = perks.filter { $0 != .supportBadge }.map { $0.rawValue }
        customPerks[key] = filtered
    }

    mutating func togglePerk(_ perk: SubscriptionPerk, for tier: CoinPriceTier) {
        guard perk != .supportBadge else { return } // locked
        var current = perks(for: tier).filter { $0 != .supportBadge }
        if current.contains(perk) { current.removeAll { $0 == perk } }
        else { current.append(perk) }
        setPerks(current, for: tier)
    }

    var hasCustomPerks: Bool { !customPerks.isEmpty }
}

struct CreatorSubscriptionPlan: Codable, Identifiable {
    @DocumentID var id: String?   // doc path = creatorID — set by Firestore on read
    let creatorID: String
    var isEnabled: Bool
    var tierPricing: TierPricing            // Per-tier custom prices
    var customWelcomeMessage: String?
    var subscriberCount: Int
    var totalEarned: Int
    var lastPriceChangeAt: Date?
    var nextPriceChangeAllowedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    func price(for tier: CoinPriceTier) -> Int { tierPricing.price(for: tier) }

    var canChangePrice: Bool {
        guard let nextAllowed = nextPriceChangeAllowedAt else { return true }
        return Date() >= nextAllowed
    }

    var daysUntilPriceChange: Int {
        guard let nextAllowed = nextPriceChangeAllowedAt else { return 0 }
        return Swift.max(0, Calendar.current.dateComponents([.day], from: Date(), to: nextAllowed).day ?? 0)
    }

    init(creatorID: String, tierPricing: TierPricing = TierPricing()) {
        self.id = nil  // assigned by Firestore
        self.creatorID = creatorID
        self.isEnabled = true
        self.tierPricing = tierPricing
        self.customWelcomeMessage = nil
        self.subscriberCount = 0
        self.totalEarned = 0
        self.lastPriceChangeAt = nil
        self.nextPriceChangeAllowedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Active Subscription (Fan → Creator)

/// Firestore: subscriptions/{subscriberID}_{creatorID}
struct ActiveSubscription: Codable, Identifiable {
    @DocumentID var id: String?   // doc path = subscriberID_creatorID
    let subscriberID: String
    let creatorID: String
    let coinsPaid: Int              // Price locked at subscribe time
    let coinTier: CoinPriceTier     // Tier chosen by subscriber
    var status: SubscriptionStatus
    let subscribedAt: Date
    var currentPeriodStart: Date
    var currentPeriodEnd: Date
    var autoRenew: Bool
    var renewalCount: Int = 0
    var grantedPerks: [String]?     // Perk raw values stamped at subscribe time

    var isActive: Bool { status == .active && Date() < currentPeriodEnd }

    var daysRemaining: Int {
        Swift.max(0, Calendar.current.dateComponents([.day], from: Date(), to: currentPeriodEnd).day ?? 0)
    }

    /// Perks this subscriber actually has — uses stamped perks if available,
    /// falls back to platform defaults for legacy subscriptions without grantedPerks
    var perks: [SubscriptionPerk] {
        if let raw = grantedPerks, !raw.isEmpty {
            return raw.compactMap { SubscriptionPerk(rawValue: $0) }
        }
        return SubscriptionPerks.perks(for: coinTier) // legacy fallback
    }
    
    var totalPaid: Int { coinsPaid * Swift.max(1, renewalCount) }
}

enum SubscriptionStatus: String, Codable {
    case active = "active"
    case expired = "expired"
    case cancelled = "cancelled"
    case paused = "paused"
}

// MARK: - Subscription Event

struct SubscriptionEvent: Codable, Identifiable {
    let id: String
    let subscriptionID: String
    let subscriberID: String
    let creatorID: String
    let type: SubscriptionEventType
    let coinAmount: Int
    let createdAt: Date
}

enum SubscriptionEventType: String, Codable {
    case newSubscription = "new"
    case renewal = "renewal"
    case cancellation = "cancellation"
    case expiration = "expiration"
}

// MARK: - Subscriber Info (for creator's subscriber list)

struct SubscriberInfo: Codable, Identifiable {
    let id: String
    let subscriberID: String
    let username: String
    let displayName: String
    let profileImageURL: String?
    let coinsPaid: Int
    let subscribedAt: Date
    let totalPaid: Int                     // Lifetime coins from this subscriber
    let renewalCount: Int
}

// MARK: - Subscription Check Result

struct SubscriptionCheckResult {
    let isSubscribed: Bool
    let perks: [SubscriptionPerk]
    let hypeBoost: Double
    let coinsPaid: Int
    
    static let none = SubscriptionCheckResult(
        isSubscribed: false,
        perks: [],
        hypeBoost: 0,
        coinsPaid: 0
    )
    
    var hasNoAds: Bool { perks.contains(.noAds) }
    var hasDMAccess: Bool { perks.contains(.dmAccess) }
    var hasCommunityAccess: Bool { perks.contains(.communityAccess) }
    var hasExclusiveCollections: Bool { perks.contains(.exclusiveCollections) }
    var hasBadge: Bool { perks.contains(.supportBadge) }
}

// MARK: - Pricing Helpers

/// Determines what price options a creator has based on their tier.
enum CreatorPricingRules {
    
    /// Whether this creator tier can accept subscriptions at all
    static func canHaveSubscribers(tier: UserTier) -> Bool {
        switch tier {
        case .business: return false
        default: return true
        }
    }
    
    /// Whether this creator tier can set custom pricing
    /// All creators can customize all 5 tier prices (100–2500 each)
    static func canCustomizePrice(tier: UserTier) -> Bool {
        tier != .business
    }

    /// All creators offer all 5 tiers to subscribers
    static func availablePrices(for tier: UserTier) -> [CoinPriceTier] {
        tier == .business ? [] : CoinPriceTier.allCases
    }

    /// Valid price range per tier — creator can set any value between min and max
    static let minPricePerTier: [CoinPriceTier: Int] = [
        .starter: 100, .basic: 100, .plus: 100, .pro: 100, .max: 100
    ]
    static let maxPricePerTier: [CoinPriceTier: Int] = [
        .starter: 2500, .basic: 2500, .plus: 2500, .pro: 2500, .max: 2500
    ]
    
    /// Default price for a creator tier
    static func defaultPrice(for tier: UserTier) -> Int {
        return CoinPriceTier.starter.rawValue // 100 for everyone by default
    }
    
    /// Price change cooldown in days
    static let priceChangeCooldownDays = 60
}
