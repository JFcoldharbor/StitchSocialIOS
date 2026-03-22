//
//  HypeCoinModels.swift
//  StitchSocial
//
//  Hype Coin currency system models
//

import Foundation

// MARK: - Coin Packages (Purchase Options)

enum HypeCoinPackage: String, CaseIterable, Codable {
    case starter = "starter"
    case basic = "basic"
    case plus = "plus"
    case pro = "pro"
    case max = "max"
    
    var coins: Int {
        switch self {
        case .starter: return 100
        case .basic: return 250
        case .plus: return 500
        case .pro: return 1000
        case .max: return 2500
        }
    }
    
    var price: Double {
        switch self {
        case .starter: return 1.99
        case .basic: return 4.99
        case .plus: return 9.99
        case .pro: return 19.99
        case .max: return 49.99
        }
    }
    
    var cashValue: Double {
        return Double(coins) / 100.0
    }
    
    var displayName: String {
        switch self {
        case .starter: return "Starter"
        case .basic: return "Basic"
        case .plus: return "Plus"
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }
    
    /// Web purchase URL path
    var webPath: String {
        return "/purchase/coins/\(rawValue)"
    }
}

// MARK: - Coin Value

enum HypeCoinValue {
    /// 100 coins = $1.00 cash value
    static let coinsPerDollar: Int = 100
    
    static func toDollars(_ coins: Int) -> Double {
        return Double(coins) / Double(coinsPerDollar)
    }
    
    static func toCoins(_ dollars: Double) -> Int {
        return Int(dollars * Double(coinsPerDollar))
    }
}

// MARK: - User Coin Balance

struct HypeCoinBalance: Codable {
    let userID: String
    var availableCoins: Int
    var pendingCoins: Int      // Earned but not yet available
    var lifetimeEarned: Int
    var lifetimeSpent: Int
    var lastUpdated: Date
    
    var totalCoins: Int {
        return availableCoins + pendingCoins
    }
    
    var cashValue: Double {
        return HypeCoinValue.toDollars(availableCoins)
    }
    
    init(userID: String) {
        self.userID = userID
        self.availableCoins = 0
        self.pendingCoins = 0
        self.lifetimeEarned = 0
        self.lifetimeSpent = 0
        self.lastUpdated = Date()
    }
}

// MARK: - Coin Transaction

struct CoinTransaction: Codable, Identifiable {
    let id: String
    let userID: String
    let type: CoinTransactionType
    let amount: Int
    let balanceAfter: Int
    let relatedUserID: String?
    let relatedSubscriptionID: String?
    let description: String
    let createdAt: Date
}

enum CoinTransactionType: String, Codable {
    case purchase = "purchase"           // Bought coins
    case subscriptionReceived = "sub_received"  // Got coins from subscriber
    case subscriptionSent = "sub_sent"   // Spent coins on subscription
    case tipReceived = "tip_received"    // Got tipped
    case tipSent = "tip_sent"            // Sent tip
    case cashOut = "cash_out"            // Withdrew to bank
    case refund = "refund"               // Refunded
    case bonus = "bonus"                 // Promotional bonus
}

// MARK: - Cash Out

struct CashOutRequest: Codable, Identifiable {
    let id: String
    let userID: String
    let coinAmount: Int
    let userTier: UserTier
    let creatorPercentage: Double
    let creatorAmount: Double
    let platformAmount: Double
    let status: CashOutStatus
    let payoutMethod: PayoutMethod
    let createdAt: Date
    var processedAt: Date?
    var failureReason: String?
}

enum CashOutStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

enum PayoutMethod: String, Codable {
    case bankTransfer = "bank_transfer"
    case paypal = "paypal"
    case stripe = "stripe"
}

// MARK: - Revenue Split (Cash Out)

enum SubscriptionRevenueShare {
    
    /// Tier-based creator share (default, no overrides)
    static func creatorShare(for tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 0.30
        case .rising: return 0.35
        case .veteran: return 0.40
        case .influencer: return 0.50
        case .ambassador: return 0.65
        case .elite: return 0.80
        case .partner: return 0.85
        case .legendary: return 0.90
        case .topCreator: return 0.90
        case .founder, .coFounder: return 1.00
        case .business: return 0.0
        }
    }
    
    /// Override-aware creator share — checks custom share first, then tier table.
    /// Use this for actual revenue calculations.
    static func effectiveCreatorShare(
        tier: UserTier,
        customSubShare: Double?,
        customSubShareExpiresAt: Date?,
        customSubSharePermanent: Bool,
        referralCount: Int,
        referralGoal: Int?
    ) -> Double {
        guard let custom = customSubShare else {
            return creatorShare(for: tier)
        }
        
        // If they hit their referral goal → permanent override
        if let goal = referralGoal, referralCount >= goal {
            return custom
        }
        
        // If marked permanent (admin set or goal already confirmed)
        if customSubSharePermanent {
            return custom
        }
        
        // Check expiration — only expires if they HAVEN'T hit the goal
        if let expires = customSubShareExpiresAt, Date() >= expires {
            return creatorShare(for: tier) // Expired, fall back to tier
        }
        
        // Active override, not expired, goal not yet met
        return custom
    }
    
    /// Convenience: effective share from BasicUserInfo
    static func effectiveCreatorShare(for user: BasicUserInfo) -> Double {
        return effectiveCreatorShare(
            tier: user.tier,
            customSubShare: user.customSubShare,
            customSubShareExpiresAt: user.customSubShareExpiresAt,
            customSubSharePermanent: user.customSubSharePermanent,
            referralCount: user.referralCount,
            referralGoal: user.referralGoal
        )
    }
    
    static func platformShare(for tier: UserTier) -> Double {
        return 1.0 - creatorShare(for: tier)
    }
    
    /// Calculate cash out amounts — uses override-aware share
    static func calculateCashOut(
        coins: Int,
        tier: UserTier,
        customSubShare: Double? = nil,
        customSubShareExpiresAt: Date? = nil,
        customSubSharePermanent: Bool = false,
        referralCount: Int = 0,
        referralGoal: Int? = nil
    ) -> (creator: Double, platform: Double) {
        let totalValue = HypeCoinValue.toDollars(coins)
        let share = effectiveCreatorShare(
            tier: tier,
            customSubShare: customSubShare,
            customSubShareExpiresAt: customSubShareExpiresAt,
            customSubSharePermanent: customSubSharePermanent,
            referralCount: referralCount,
            referralGoal: referralGoal
        )
        let creatorCut = totalValue * share
        let platformCut = totalValue * (1.0 - share)
        return (creatorCut, platformCut)
    }
}

// MARK: - Minimum Cash Out

enum CashOutLimits {
    static let minimumCoins: Int = 1000  // $10 minimum
    static let maximumPerDay: Int = 100000  // $1000/day
}
