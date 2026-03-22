//
//  AdRevenueShare.swift
//  StitchSocial
//
//  Ad revenue share configuration and account type definitions.
//  Dependencies: UserTier (Layer 1)
//
//  UPDATED: All tiers now earn ad revenue (was Influencer+ only).
//  Revenue shares updated to match new tier structure.
//  Added AccountType enum for Business vs Personal accounts.
//
//  CACHING NOTE: Revenue share lookups are pure static computations —
//  no caching needed here. Ad data caching lives in AdService.
//

import Foundation

// NOTE: AccountType enum is defined in UserTier.swift (Layer 1)

// MARK: - Revenue Share Configuration

/// Ad revenue share split between creator and platform.
/// All tiers earn ad revenue. Share scales with tier progression.
/// Business accounts do NOT earn ad rev — they pay into the ad pool.
enum AdRevenueShare {
    
    /// Creator's percentage of ad revenue generated on their content.
    /// Business accounts always return 0 — they are advertisers, not earners.
    static func creatorShare(for tier: UserTier) -> Double {
        switch tier {
        case .rookie:                return 0.10  // 10/90
        case .rising:                return 0.12  // 12/88
        case .veteran:               return 0.15  // 15/85
        case .influencer:            return 0.20  // 20/80
        case .ambassador:            return 0.35  // 35/65 — big jump, rewards sustained growth
        case .elite:                 return 0.45  // 45/55
        case .partner:               return 0.50  // 50/50
        case .legendary:             return 0.55  // 55/45
        case .topCreator:            return 0.65  // 65/35 — beats YouTube's flat 55%
        case .founder, .coFounder:   return 0.65  // Same as Top Creator
        case .business:              return 0.0   // Business accounts pay ads, don't earn
        }
    }
    
    /// Platform's percentage of ad revenue.
    static func platformShare(for tier: UserTier) -> Double {
        return 1.0 - creatorShare(for: tier)
    }
    
    /// All personal account tiers can earn ad revenue.
    /// Business accounts cannot — they are the advertisers.
    static func canEarnAdRevenue(tier: UserTier, accountType: AccountType) -> Bool {
        guard accountType == .personal else { return false }
        return true // All personal tiers earn ad rev now
    }
    
    /// Whether a user can access the ad opportunities marketplace.
    /// Influencer+ can browse/accept brand partnerships.
    /// Below Influencer still earns passive ad rev but can't do brand deals.
    static func canAccessAdMarketplace(tier: UserTier) -> Bool {
        switch tier {
        case .influencer, .ambassador, .elite, .partner,
             .legendary, .topCreator, .founder, .coFounder:
            return true
        default:
            return false
        }
    }
    
    /// Whether a business account can create ad campaigns.
    static func canCreateCampaigns(accountType: AccountType) -> Bool {
        return accountType == .business
    }
    
    // MARK: - Deprecated Compatibility
    
    /// Legacy accessor — use canAccessAdMarketplace or canEarnAdRevenue instead.
    @available(*, deprecated, renamed: "canAccessAdMarketplace")
    static func canAccessAds(tier: UserTier) -> Bool {
        return canAccessAdMarketplace(tier: tier)
    }
}

// MARK: - Ad Campaign (Created by Business Accounts)

struct AdCampaign: Codable, Identifiable, Hashable {
    let id: String
    let brandID: String              // Business account userID
    let brandName: String
    let brandLogoURL: String?
    let title: String
    let description: String
    let category: AdCategory
    let adVideoURL: String
    let adThumbnailURL: String
    let budgetMin: Double
    let budgetMax: Double
    let paymentModel: AdPaymentModel
    let cpmRate: Double?             // Cost per 1,000 impressions
    let cpaRate: Double?
    let flatFee: Double?
    let requirements: CreatorRequirements
    let status: AdCampaignStatus
    let startDate: Date
    let endDate: Date?
    let createdAt: Date
    let updatedAt: Date
    
    var budgetRange: String {
        "$\(Int(budgetMin))-\(Int(budgetMax))"
    }
}

// MARK: - Creator Requirements (Set by Business in Campaign)

struct CreatorRequirements: Codable, Hashable {
    let minimumTier: UserTier
    let minimumStitchers: Int?
    let minimumHypeScore: Double?
    let minimumHypeRating: Double?
    let minimumEngagementRate: Double?
    let minimumViewCount: Int?
    let minimumCommunityScore: Double?
    let requiredHashtags: [String]?
    let preferredCategories: [AdCategory]?
    
    /// Default requirements — platform auto-matches, business sets criteria
    static let `default` = CreatorRequirements(
        minimumTier: .influencer,
        minimumStitchers: nil,
        minimumHypeScore: nil,
        minimumHypeRating: nil,
        minimumEngagementRate: nil,
        minimumViewCount: nil,
        minimumCommunityScore: nil,
        requiredHashtags: nil,
        preferredCategories: nil
    )
}

// MARK: - Ad Opportunity (Auto-Matched to Creator)

struct AdOpportunity: Codable, Identifiable, Hashable {
    let id: String
    let campaign: AdCampaign
    let creatorID: String
    let matchScore: Int              // 0-100, computed by matching algorithm
    let status: AdOpportunityStatus
    let estimatedEarnings: Double?
    let createdAt: Date
    let expiresAt: Date?
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - Ad Partnership (Active Deal)

struct AdPartnership: Codable, Identifiable, Hashable {
    let id: String
    let campaignID: String
    let creatorID: String
    let brandID: String
    let brandName: String
    let adVideoURL: String
    let adThumbnailURL: String
    let revenueShareCreator: Double
    let revenueSharePlatform: Double
    let status: AdPartnershipStatus
    let acceptedAt: Date
    let totalImpressions: Int
    let totalEarnings: Double
    let lastPayoutAt: Date?
}

// MARK: - Ad Placement

struct AdPlacement: Codable, Identifiable, Hashable {
    let id: String
    let partnershipID: String
    let threadID: String
    let position: Int                // Insertion point in thread
    let impressions: Int
    let earnings: Double
    let placedAt: Date
}

// MARK: - Creator Ad Stats

struct CreatorAdStats: Codable {
    let creatorID: String
    let totalPartnerships: Int
    let activePartnerships: Int
    let totalImpressions: Int
    let totalEarnings: Double
    let pendingPayout: Double
    let lastPayoutDate: Date?
    let lastPayoutAmount: Double?
}

// MARK: - Business Ad Stats (Dashboard)

/// Stats shown on the Business account dashboard.
/// Firestore: business_ad_stats/{businessUserID}
struct BusinessAdStats: Codable {
    let businessID: String
    let totalCampaigns: Int
    let activeCampaigns: Int
    let totalSpend: Double
    let totalImpressions: Int
    let totalClicks: Int
    let averageCPM: Double
    let lastCampaignDate: Date?
}

// MARK: - Enums

enum AdCategory: String, Codable, CaseIterable, Hashable {
    case fitness = "fitness"
    case gaming = "gaming"
    case lifestyle = "lifestyle"
    case fashion = "fashion"
    case tech = "tech"
    case food = "food"
    case travel = "travel"
    case beauty = "beauty"
    case education = "education"
    case entertainment = "entertainment"
    case sports = "sports"
    case music = "music"
    case realEstate = "real_estate"
    case automotive = "automotive"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .realEstate: return "Real Estate"
        default: return rawValue.capitalized
        }
    }
    
    var icon: String {
        switch self {
        case .fitness: return "💪"
        case .gaming: return "🎮"
        case .lifestyle: return "🌱"
        case .fashion: return "👗"
        case .tech: return "📱"
        case .food: return "🍕"
        case .travel: return "✈️"
        case .beauty: return "💄"
        case .education: return "📚"
        case .entertainment: return "🎬"
        case .sports: return "⚽"
        case .music: return "🎵"
        case .realEstate: return "🏠"
        case .automotive: return "🚗"
        case .other: return "📦"
        }
    }
}

enum AdPaymentModel: String, Codable, Hashable {
    case cpm = "cpm"           // Per 1000 impressions — primary model
    case cpa = "cpa"           // Per engagement action
    case flat = "flat"         // Flat campaign fee
    case hybrid = "hybrid"     // Combination
}

enum AdCampaignStatus: String, Codable, Hashable {
    case draft = "draft"
    case active = "active"
    case paused = "paused"
    case completed = "completed"
    case cancelled = "cancelled"
}

enum AdOpportunityStatus: String, Codable, Hashable {
    case pending = "pending"
    case viewed = "viewed"
    case accepted = "accepted"
    case declined = "declined"
    case expired = "expired"
}

enum AdPartnershipStatus: String, Codable, Hashable {
    case active = "active"
    case paused = "paused"
    case ended = "ended"
}

// MARK: - Creator-Made Sponsored Content

struct SponsoredContentTag: Codable, Hashable {
    let brandName: String
    let brandID: String?
    let disclosureType: SponsoredDisclosure
}

enum SponsoredDisclosure: String, Codable, CaseIterable, Hashable {
    case paidPartnership = "paid_partnership"
    case sponsored = "sponsored"
    case ad = "ad"
    case gifted = "gifted"
    
    var displayText: String {
        switch self {
        case .paidPartnership: return "Paid Partnership"
        case .sponsored: return "Sponsored"
        case .ad: return "Ad"
        case .gifted: return "Gifted"
        }
    }
}
