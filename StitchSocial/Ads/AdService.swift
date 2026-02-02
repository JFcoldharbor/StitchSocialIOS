//
//  AdService.swift
//  StitchSocial
//
//  Service for ad matching, partnerships, and placement
//

import Foundation
import FirebaseFirestore

class AdService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AdService()
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    
    @Published var availableOpportunities: [AdOpportunity] = []
    @Published var activePartnerships: [AdPartnership] = []
    @Published var creatorStats: CreatorAdStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Collections
    
    private enum Collections {
        static let campaigns = "ad_campaigns"
        static let opportunities = "ad_opportunities"
        static let partnerships = "ad_partnerships"
        static let placements = "ad_placements"
        static let creatorStats = "creator_ad_stats"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Access Control
    
    func canAccessAds(tier: UserTier) -> Bool {
        return AdRevenueShare.canAccessAds(tier: tier)
    }
    
    // MARK: - Fetch Opportunities
    
    @MainActor
    func fetchOpportunities(for creatorID: String, tier: UserTier) async throws -> [AdOpportunity] {
        guard canAccessAds(tier: tier) else {
            throw AdError.insufficientTier
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(Collections.opportunities)
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", in: ["pending", "viewed"])
            .order(by: "matchScore", descending: true)
            .limit(to: 20)
            .getDocuments()
        
        let opportunities = snapshot.documents.compactMap { doc -> AdOpportunity? in
            try? doc.data(as: AdOpportunity.self)
        }.filter { !$0.isExpired }
        
        self.availableOpportunities = opportunities
        return opportunities
    }
    
    // MARK: - Fetch Active Partnerships
    
    @MainActor
    func fetchActivePartnerships(for creatorID: String) async throws -> [AdPartnership] {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(Collections.partnerships)
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", isEqualTo: "active")
            .getDocuments()
        
        let partnerships = snapshot.documents.compactMap { doc -> AdPartnership? in
            try? doc.data(as: AdPartnership.self)
        }
        
        self.activePartnerships = partnerships
        return partnerships
    }
    
    // MARK: - Accept Opportunity
    
    @MainActor
    func acceptOpportunity(_ opportunity: AdOpportunity, creatorTier: UserTier) async throws -> AdPartnership {
        guard canAccessAds(tier: creatorTier) else {
            throw AdError.insufficientTier
        }
        
        let creatorShare = AdRevenueShare.creatorShare(for: creatorTier)
        let platformShare = AdRevenueShare.platformShare(for: creatorTier)
        
        let partnership = AdPartnership(
            id: UUID().uuidString,
            campaignID: opportunity.campaign.id,
            creatorID: opportunity.creatorID,
            brandID: opportunity.campaign.brandID,
            brandName: opportunity.campaign.brandName,
            adVideoURL: opportunity.campaign.adVideoURL,
            adThumbnailURL: opportunity.campaign.adThumbnailURL,
            revenueShareCreator: creatorShare,
            revenueSharePlatform: platformShare,
            status: .active,
            acceptedAt: Date(),
            totalImpressions: 0,
            totalEarnings: 0,
            lastPayoutAt: nil
        )
        
        // Save partnership
        try db.collection(Collections.partnerships)
            .document(partnership.id)
            .setData(from: partnership)
        
        // Update opportunity status
        try await db.collection(Collections.opportunities)
            .document(opportunity.id)
            .updateData(["status": AdOpportunityStatus.accepted.rawValue])
        
        // Remove from available list
        availableOpportunities.removeAll { $0.id == opportunity.id }
        activePartnerships.append(partnership)
        
        print("✅ AD: Partnership created with \(opportunity.campaign.brandName)")
        return partnership
    }
    
    // MARK: - Decline Opportunity
    
    @MainActor
    func declineOpportunity(_ opportunity: AdOpportunity) async throws {
        try await db.collection(Collections.opportunities)
            .document(opportunity.id)
            .updateData(["status": AdOpportunityStatus.declined.rawValue])
        
        availableOpportunities.removeAll { $0.id == opportunity.id }
        print("❌ AD: Declined opportunity from \(opportunity.campaign.brandName)")
    }
    
    // MARK: - Get Ad for Thread
    
    func getAdForThread(threadID: String, creatorID: String) async throws -> AdPartnership? {
        // Get active partnership for this creator
        let snapshot = try await db.collection(Collections.partnerships)
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", isEqualTo: "active")
            .limit(to: 1)
            .getDocuments()
        
        guard let doc = snapshot.documents.first,
              let partnership = try? doc.data(as: AdPartnership.self) else {
            return nil
        }
        
        return partnership
    }
    
    // MARK: - Record Ad Impression
    
    func recordImpression(partnershipID: String, threadID: String) async throws {
        let placementRef = db.collection(Collections.placements)
            .document("\(partnershipID)_\(threadID)")
        let partnershipRef = db.collection(Collections.partnerships).document(partnershipID)
        
        // Check if placement exists
        let placementDoc = try await placementRef.getDocument()
        
        if placementDoc.exists {
            // Increment existing
            try await placementRef.updateData([
                "impressions": FieldValue.increment(Int64(1))
            ])
        } else {
            // Create new placement record
            let placement = AdPlacement(
                id: "\(partnershipID)_\(threadID)",
                partnershipID: partnershipID,
                threadID: threadID,
                position: 2,
                impressions: 1,
                earnings: 0,
                placedAt: Date()
            )
            try placementRef.setData(from: placement)
        }
        
        // Update partnership total impressions
        try await partnershipRef.updateData([
            "totalImpressions": FieldValue.increment(Int64(1))
        ])
    }
    
    // MARK: - Fetch Creator Stats
    
    @MainActor
    func fetchCreatorStats(creatorID: String) async throws -> CreatorAdStats {
        let docRef = db.collection(Collections.creatorStats).document(creatorID)
        let doc = try await docRef.getDocument()
        
        if let stats = try? doc.data(as: CreatorAdStats.self) {
            self.creatorStats = stats
            return stats
        }
        
        // Return empty stats if none exist
        let emptyStats = CreatorAdStats(
            creatorID: creatorID,
            totalPartnerships: 0,
            activePartnerships: 0,
            totalImpressions: 0,
            totalEarnings: 0,
            pendingPayout: 0,
            lastPayoutDate: nil,
            lastPayoutAmount: nil
        )
        self.creatorStats = emptyStats
        return emptyStats
    }
    
    // MARK: - Matching Algorithm
    
    func calculateMatchScore(campaign: AdCampaign, creator: BasicUserInfo, creatorMetrics: CreatorMetrics) -> Int {
        var score = 0
        let requirements = campaign.requirements
        
        // Tier check (required)
        guard creator.tier.cloutRange.lowerBound >= requirements.minimumTier.cloutRange.lowerBound else {
            return 0
        }
        score += 20
        
        // Stitchers/followers
        if let minStitchers = requirements.minimumStitchers {
            if creatorMetrics.stitcherCount >= minStitchers {
                score += 15
            } else {
                score -= 10
            }
        } else {
            score += 10
        }
        
        // Hype rating
        if let minHypeRating = requirements.minimumHypeRating {
            if creatorMetrics.hypeRating >= minHypeRating {
                score += 15
            } else {
                score -= 10
            }
        } else {
            score += 10
        }
        
        // Engagement rate
        if let minEngagement = requirements.minimumEngagementRate {
            if creatorMetrics.engagementRate >= minEngagement {
                score += 15
            } else {
                score -= 10
            }
        } else {
            score += 10
        }
        
        // View count
        if let minViews = requirements.minimumViewCount {
            if creatorMetrics.totalViews >= minViews {
                score += 10
            } else {
                score -= 5
            }
        } else {
            score += 5
        }
        
        // Category match
        if let preferredCategories = requirements.preferredCategories,
           let creatorCategory = creatorMetrics.primaryCategory {
            if preferredCategories.contains(creatorCategory) {
                score += 20
            }
        } else {
            score += 10
        }
        
        // Hashtag relevance
        if let requiredHashtags = requirements.requiredHashtags,
           !requiredHashtags.isEmpty {
            let matchingHashtags = creatorMetrics.topHashtags.filter { requiredHashtags.contains($0) }
            let hashtagScore = (matchingHashtags.count * 5).clamped(to: 0...15)
            score += hashtagScore
        } else {
            score += 5
        }
        
        return score.clamped(to: 0...100)
    }
    
    // MARK: - End Partnership
    
    @MainActor
    func endPartnership(_ partnership: AdPartnership) async throws {
        try await db.collection(Collections.partnerships)
            .document(partnership.id)
            .updateData(["status": AdPartnershipStatus.ended.rawValue])
        
        activePartnerships.removeAll { $0.id == partnership.id }
        print("🔚 AD: Partnership ended with \(partnership.brandName)")
    }
}

// MARK: - Creator Metrics (for matching)

struct CreatorMetrics: Codable {
    let stitcherCount: Int
    let hypeRating: Double
    let hypeScore: Double
    let engagementRate: Double
    let totalViews: Int
    let communityScore: Double
    let primaryCategory: AdCategory?
    let topHashtags: [String]
}

// MARK: - Errors

enum AdError: LocalizedError {
    case insufficientTier
    case opportunityExpired
    case campaignNotFound
    case alreadyAccepted
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientTier:
            return "You need to be Influencer tier or higher to access ad opportunities"
        case .opportunityExpired:
            return "This opportunity has expired"
        case .campaignNotFound:
            return "Campaign not found"
        case .alreadyAccepted:
            return "You've already accepted this opportunity"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Helpers

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
