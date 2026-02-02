//
//  AdRevenueShare.swift
//  StitchSocial
//
//  Created by James Garmon on 2/2/26.
//


//
//  AdModels.swift
//  StitchSocial
//
//  Ad system models for sponsor campaigns and creator partnerships
//

import Foundation

// MARK: - Revenue Share Configuration

enum AdRevenueShare {
    static func creatorShare(for tier: UserTier) -> Double {
        switch tier {
        case .influencer: return 0.25
        case .ambassador: return 0.28
        case .elite: return 0.32
        case .partner: return 0.35
        case .legendary: return 0.38
        case .topCreator: return 0.40
        case .founder, .coFounder: return 0.50
        default: return 0.0 // Below influencer = no ads
        }
    }
    
    static func platformShare(for tier: UserTier) -> Double {
        return 1.0 - creatorShare(for: tier)
    }
    
    static func canAccessAds(tier: UserTier) -> Bool {
        switch tier {
        case .influencer, .ambassador, .elite, .partner, .legendary, .topCreator, .founder, .coFounder:
            return true
        default:
            return false
        }
    }
}

// MARK: - Ad Campaign (Created by Sponsors)

struct AdCampaign: Codable, Identifiable, Hashable {
    let id: String
    let brandID: String
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
    let cpmRate: Double?
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

// MARK: - Creator Requirements (Set by Sponsors)

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

// MARK: - Ad Opportunity (Matched to Creator)

struct AdOpportunity: Codable, Identifiable, Hashable {
    let id: String
    let campaign: AdCampaign
    let creatorID: String
    let matchScore: Int // 0-100
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
    let position: Int // Always 2 for now
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
    case other = "other"
    
    var displayName: String {
        rawValue.capitalized
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
        case .other: return "📦"
        }
    }
}

enum AdPaymentModel: String, Codable, Hashable {
    case cpm = "cpm"           // Per 1000 views
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