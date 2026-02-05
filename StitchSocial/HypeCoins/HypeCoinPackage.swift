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
    
    static func creatorShare(for tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 0.70
        case .rising: return 0.75
        case .veteran: return 0.80
        case .influencer: return 0.85
        case .ambassador: return 0.87
        case .elite: return 0.90
        case .partner: return 0.92
        case .legendary: return 0.95
        case .topCreator: return 0.97
        case .founder, .coFounder: return 1.00
        }
    }
    
    static func platformShare(for tier: UserTier) -> Double {
        return 1.0 - creatorShare(for: tier)
    }
    
    /// Calculate cash out amounts
    static func calculateCashOut(coins: Int, tier: UserTier) -> (creator: Double, platform: Double) {
        let totalValue = HypeCoinValue.toDollars(coins)
        let creatorCut = totalValue * creatorShare(for: tier)
        let platformCut = totalValue * platformShare(for: tier)
        return (creatorCut, platformCut)
    }
}

// MARK: - Minimum Cash Out

enum CashOutLimits {
    static let minimumCoins: Int = 1000  // $10 minimum
    static let maximumPerDay: Int = 100000  // $1000/day
}
