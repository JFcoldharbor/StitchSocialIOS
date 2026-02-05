//
//  SubscriptionTier.swift
//  StitchSocial
//
//  Created by James Garmon on 2/2/26.
//


//
//  SubscriptionModels.swift
//  StitchSocial
//
//  Subscription system models - tiers, plans, perks
//

import Foundation

// MARK: - Subscription Tier

enum SubscriptionTier: String, CaseIterable, Codable {
    case supporter = "supporter"
    case superFan = "super_fan"
    
    var displayName: String {
        switch self {
        case .supporter: return "Supporter"
        case .superFan: return "Super Fan"
        }
    }
    
    var coinRange: ClosedRange<Int> {
        switch self {
        case .supporter: return 150...250
        case .superFan: return 300...500
        }
    }
    
    var defaultCoins: Int {
        switch self {
        case .supporter: return 200
        case .superFan: return 400
        }
    }
    
    var hypeBoost: Double {
        switch self {
        case .supporter: return 0.05  // 5%
        case .superFan: return 0.10   // 10%
        }
    }
    
    var perks: [SubscriptionPerk] {
        switch self {
        case .supporter:
            return [.noAds, .topSupporterBadge, .hypeBoost5]
        case .superFan:
            return [.noAds, .topSupporterBadge, .hypeBoost10, .dmAccess, .commentAccess]
        }
    }
}

// MARK: - Subscription Perks

enum SubscriptionPerk: String, Codable, CaseIterable {
    case noAds = "no_ads"
    case topSupporterBadge = "top_supporter_badge"
    case hypeBoost5 = "hype_boost_5"
    case hypeBoost10 = "hype_boost_10"
    case dmAccess = "dm_access"
    case commentAccess = "comment_access"
    
    var displayName: String {
        switch self {
        case .noAds: return "Ad-Free Viewing"
        case .topSupporterBadge: return "Top Supporter Badge"
        case .hypeBoost5: return "5% Hype Boost"
        case .hypeBoost10: return "10% Hype Boost"
        case .dmAccess: return "DM Access"
        case .commentAccess: return "Comment on Videos"
        }
    }
    
    var icon: String {
        switch self {
        case .noAds: return "eye.slash"
        case .topSupporterBadge: return "star.fill"
        case .hypeBoost5, .hypeBoost10: return "flame.fill"
        case .dmAccess: return "message.fill"
        case .commentAccess: return "bubble.left.fill"
        }
    }
}

// MARK: - Creator Subscription Plan (Creator sets this up)

struct CreatorSubscriptionPlan: Codable, Identifiable {
    let id: String
    let creatorID: String
    var isEnabled: Bool
    var supporterPrice: Int      // Coins (150-250)
    var superFanPrice: Int       // Coins (300-500)
    var supporterEnabled: Bool
    var superFanEnabled: Bool
    var customWelcomeMessage: String?
    var subscriberCount: Int
    var totalEarned: Int         // Lifetime coins earned
    var createdAt: Date
    var updatedAt: Date
    
    init(creatorID: String) {
        self.id = UUID().uuidString
        self.creatorID = creatorID
        self.isEnabled = false
        self.supporterPrice = SubscriptionTier.supporter.defaultCoins
        self.superFanPrice = SubscriptionTier.superFan.defaultCoins
        self.supporterEnabled = true
        self.superFanEnabled = true
        self.customWelcomeMessage = nil
        self.subscriberCount = 0
        self.totalEarned = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func priceForTier(_ tier: SubscriptionTier) -> Int {
        switch tier {
        case .supporter: return supporterPrice
        case .superFan: return superFanPrice
        }
    }
    
    func isTierEnabled(_ tier: SubscriptionTier) -> Bool {
        switch tier {
        case .supporter: return supporterEnabled
        case .superFan: return superFanEnabled
        }
    }
}

// MARK: - Active Subscription (Viewer → Creator)

struct ActiveSubscription: Codable, Identifiable {
    let id: String
    let subscriberID: String
    let creatorID: String
    let tier: SubscriptionTier
    let coinsPaid: Int
    let status: SubscriptionStatus
    let startedAt: Date
    var expiresAt: Date
    var renewalEnabled: Bool
    var renewalCount: Int
    
    var isActive: Bool {
        return status == .active && Date() < expiresAt
    }
    
    var daysRemaining: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, remaining)
    }
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
    let tier: SubscriptionTier
    let coinAmount: Int
    let createdAt: Date
}

enum SubscriptionEventType: String, Codable {
    case newSubscription = "new"
    case renewal = "renewal"
    case upgrade = "upgrade"
    case downgrade = "downgrade"
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
    let tier: SubscriptionTier
    let subscribedAt: Date
    let totalPaid: Int           // Lifetime coins from this subscriber
    let renewalCount: Int
}

// MARK: - Subscription Check Result

struct SubscriptionCheckResult {
    let isSubscribed: Bool
    let tier: SubscriptionTier?
    let perks: [SubscriptionPerk]
    let hypeBoost: Double
    
    static let none = SubscriptionCheckResult(
        isSubscribed: false,
        tier: nil,
        perks: [],
        hypeBoost: 0
    )
    
    var hasNoAds: Bool {
        perks.contains(.noAds)
    }
    
    var hasDMAccess: Bool {
        perks.contains(.dmAccess)
    }
    
    var hasCommentAccess: Bool {
        perks.contains(.commentAccess)
    }
    
    var hasBadge: Bool {
        perks.contains(.topSupporterBadge)
    }
}