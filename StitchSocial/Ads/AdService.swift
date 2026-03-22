//
//  AdService.swift
//  StitchSocial
//
//  Service for ad auto-matching, partnerships, placement, and business campaigns.
//  Dependencies: AdRevenueShare (Layer 1), UserTier (Layer 1), Firebase Firestore
//
//  UPDATED: Added caching for opportunities, partnerships, and stats.
//  All tiers now earn passive ad revenue. Marketplace access still Influencer+.
//  Business accounts create campaigns — platform auto-matches to creators.
//
//  CACHING STRATEGY:
//  - Opportunities: 5 min TTL (auto-matched, moderate change rate)
//  - Active Partnerships: 10 min TTL (slow-changing once accepted)
//  - Creator Stats: 10 min TTL (aggregated, slow-changing)
//  - Business Stats: 10 min TTL (aggregated, slow-changing)
//  - Campaign list: 5 min TTL (business dashboard)
//  All caches invalidate on logout via clearAllCaches().
//  Mutations (accept/decline/end) invalidate relevant caches immediately.
//

import Foundation
import FirebaseFirestore

class AdService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AdService()
    
    // MARK: - Published State
    
    @Published var availableOpportunities: [AdOpportunity] = []
    @Published var activePartnerships: [AdPartnership] = []
    @Published var creatorStats: CreatorAdStats?
    @Published var businessStats: BusinessAdStats?
    @Published var businessCampaigns: [AdCampaign] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    
    // MARK: - Cache Storage
    
    /// Cached data with timestamps for TTL-based invalidation.
    /// Reduces Firestore reads significantly — ad data is read-heavy, write-light.
    private struct CacheEntry<T> {
        let data: T
        let cachedAt: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }
    
    private var opportunitiesCache: CacheEntry<[AdOpportunity]>?
    private var partnershipsCache: CacheEntry<[AdPartnership]>?
    private var creatorStatsCache: [String: CacheEntry<CreatorAdStats>] = [:]
    private var businessStatsCache: [String: CacheEntry<BusinessAdStats>] = [:]
    private var businessCampaignsCache: CacheEntry<[AdCampaign]>?
    
    // MARK: - Cache TTLs (from OptimizationConfig pattern)
    
    /// Opportunities refresh every 5 min — auto-matched, moderate churn
    private let opportunitiesTTL: TimeInterval = 300
    
    /// Partnerships are stable once accepted — 10 min TTL
    private let partnershipsTTL: TimeInterval = 600
    
    /// Stats are aggregated server-side — 10 min TTL
    private let statsTTL: TimeInterval = 600
    
    /// Business campaign list — 5 min TTL
    private let campaignsTTL: TimeInterval = 300
    
    // MARK: - Collections
    
    private enum Collections {
        static let campaigns = "ad_campaigns"
        static let opportunities = "ad_opportunities"
        static let partnerships = "ad_partnerships"
        static let placements = "ad_placements"
        static let creatorStats = "creator_ad_stats"
        static let businessStats = "business_ad_stats"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Access Control
    
    /// Check if user can earn ad revenue (all personal accounts)
    func canEarnAdRevenue(tier: UserTier, accountType: AccountType) -> Bool {
        return AdRevenueShare.canEarnAdRevenue(tier: tier, accountType: accountType)
    }
    
    /// Check if user can access the ad marketplace (Influencer+ personal accounts)
    func canAccessAdMarketplace(tier: UserTier) -> Bool {
        return AdRevenueShare.canAccessAdMarketplace(tier: tier)
    }
    
    /// Check if account can create campaigns (business accounts only)
    func canCreateCampaigns(accountType: AccountType) -> Bool {
        return AdRevenueShare.canCreateCampaigns(accountType: accountType)
    }
    
    // MARK: - Fetch Opportunities (Creator Side)
    
    /// Fetches auto-matched opportunities for a creator. Cached for 5 min.
    @MainActor
    func fetchOpportunities(for creatorID: String, tier: UserTier) async throws -> [AdOpportunity] {
        guard canAccessAdMarketplace(tier: tier) else {
            throw AdError.insufficientTier
        }
        
        // Check cache first — saves Firestore reads
        if let cached = opportunitiesCache, !cached.isExpired {
            self.availableOpportunities = cached.data
            return cached.data
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
        
        // Cache result
        opportunitiesCache = CacheEntry(data: opportunities, cachedAt: Date(), ttl: opportunitiesTTL)
        self.availableOpportunities = opportunities
        return opportunities
    }
    
    // MARK: - Fetch Active Partnerships (Creator Side)
    
    /// Fetches active partnerships for a creator. Cached for 10 min.
    @MainActor
    func fetchActivePartnerships(for creatorID: String) async throws -> [AdPartnership] {
        // Check cache first
        if let cached = partnershipsCache, !cached.isExpired {
            self.activePartnerships = cached.data
            return cached.data
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(Collections.partnerships)
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", isEqualTo: "active")
            .getDocuments()
        
        let partnerships = snapshot.documents.compactMap { doc -> AdPartnership? in
            try? doc.data(as: AdPartnership.self)
        }
        
        // Cache result
        partnershipsCache = CacheEntry(data: partnerships, cachedAt: Date(), ttl: partnershipsTTL)
        self.activePartnerships = partnerships
        return partnerships
    }
    
    // MARK: - Accept Opportunity
    
    /// Creator accepts a matched opportunity. Invalidates both caches.
    @MainActor
    func acceptOpportunity(_ opportunity: AdOpportunity, creatorTier: UserTier) async throws -> AdPartnership {
        guard canAccessAdMarketplace(tier: creatorTier) else {
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
        
        // Batch write: create partnership + update opportunity status
        let batch = db.batch()
        
        let partnershipRef = db.collection(Collections.partnerships).document(partnership.id)
        try batch.setData(from: partnership, forDocument: partnershipRef)
        
        let opportunityRef = db.collection(Collections.opportunities).document(opportunity.id)
        batch.updateData(["status": AdOpportunityStatus.accepted.rawValue], forDocument: opportunityRef)
        
        try await batch.commit()
        
        // Invalidate caches — data changed
        opportunitiesCache = nil
        partnershipsCache = nil
        creatorStatsCache.removeAll()
        
        // Update local state
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
        
        // Invalidate opportunities cache
        opportunitiesCache = nil
        availableOpportunities.removeAll { $0.id == opportunity.id }
        
        print("❌ AD: Declined opportunity from \(opportunity.campaign.brandName)")
    }
    
    // MARK: - Get Ad for Thread (Viewer Side)
    
    /// Returns ad partnership for thread, or nil if viewer is subscribed.
    /// No caching here — this is per-view and needs to be fresh for impression tracking.
    func getAdForThread(threadID: String, creatorID: String, viewerID: String) async throws -> AdPartnership? {
        // Subscribers skip ads — this is a key subscription perk
        let isSubscribed = try await checkSubscriptionStatus(viewerID: viewerID, creatorID: creatorID)
        if isSubscribed {
            print("💎 AD: Viewer is subscribed - skipping ad")
            return nil
        }
        
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
    
    /// Records an impression. Uses batch-friendly increment — no read-before-write.
    func recordImpression(partnershipID: String, threadID: String) async throws {
        let placementRef = db.collection(Collections.placements)
            .document("\(partnershipID)_\(threadID)")
        let partnershipRef = db.collection(Collections.partnerships).document(partnershipID)
        
        let placementDoc = try await placementRef.getDocument()
        
        if placementDoc.exists {
            // Increment existing — single write, no read needed
            try await placementRef.updateData([
                "impressions": FieldValue.increment(Int64(1))
            ])
        } else {
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
        
        // Update partnership total — atomic increment, no read needed
        try await partnershipRef.updateData([
            "totalImpressions": FieldValue.increment(Int64(1))
        ])
    }
    
    // MARK: - Check Subscription Status
    
    private func checkSubscriptionStatus(viewerID: String, creatorID: String) async throws -> Bool {
        if viewerID == creatorID { return false }
        let subscriptionService = SubscriptionService.shared
        let result = try await subscriptionService.checkSubscription(subscriberID: viewerID, creatorID: creatorID)
        return result.hasNoAds
    }
    
    // MARK: - Fetch Creator Stats
    
    /// Fetches aggregated ad stats for a creator. Cached per-creator for 10 min.
    @MainActor
    func fetchCreatorStats(creatorID: String) async throws -> CreatorAdStats {
        // Check per-creator cache
        if let cached = creatorStatsCache[creatorID], !cached.isExpired {
            self.creatorStats = cached.data
            return cached.data
        }
        
        let docRef = db.collection(Collections.creatorStats).document(creatorID)
        let doc = try await docRef.getDocument()
        
        let stats: CreatorAdStats
        if let fetched = try? doc.data(as: CreatorAdStats.self) {
            stats = fetched
        } else {
            stats = CreatorAdStats(
                creatorID: creatorID,
                totalPartnerships: 0,
                activePartnerships: 0,
                totalImpressions: 0,
                totalEarnings: 0,
                pendingPayout: 0,
                lastPayoutDate: nil,
                lastPayoutAmount: nil
            )
        }
        
        // Cache per-creator
        creatorStatsCache[creatorID] = CacheEntry(data: stats, cachedAt: Date(), ttl: statsTTL)
        self.creatorStats = stats
        return stats
    }
    
    // MARK: - Business Account: Create Campaign
    
    /// Business account creates a new ad campaign. Platform auto-matches to creators.
    /// Firestore: ad_campaigns/{campaignID}
    @MainActor
    func createCampaign(
        businessID: String,
        businessName: String,
        title: String,
        description: String,
        category: AdCategory,
        adVideoURL: String,
        adThumbnailURL: String,
        budgetMin: Double,
        budgetMax: Double,
        cpmRate: Double,
        requirements: CreatorRequirements = .default
    ) async throws -> AdCampaign {
        
        let campaign = AdCampaign(
            id: UUID().uuidString,
            brandID: businessID,
            brandName: businessName,
            brandLogoURL: nil,
            title: title,
            description: description,
            category: category,
            adVideoURL: adVideoURL,
            adThumbnailURL: adThumbnailURL,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            paymentModel: .cpm,
            cpmRate: cpmRate,
            cpaRate: nil,
            flatFee: nil,
            requirements: requirements,
            status: .active,
            startDate: Date(),
            endDate: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try db.collection(Collections.campaigns)
            .document(campaign.id)
            .setData(from: campaign)
        
        // Invalidate business campaigns cache
        businessCampaignsCache = nil
        
        print("📢 AD: Campaign '\(title)' created by business \(businessName)")
        
        // Trigger auto-matching (would be Cloud Function in production)
        // For now, mark that matching is needed
        try await db.collection("ad_match_queue").document(campaign.id).setData([
            "campaignID": campaign.id,
            "status": "pending",
            "createdAt": Timestamp()
        ])
        
        return campaign
    }
    
    // MARK: - Business Account: Fetch Campaigns
    
    /// Fetches all campaigns for a business account. Cached for 5 min.
    @MainActor
    func fetchBusinessCampaigns(businessID: String) async throws -> [AdCampaign] {
        // Check cache
        if let cached = businessCampaignsCache, !cached.isExpired {
            self.businessCampaigns = cached.data
            return cached.data
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(Collections.campaigns)
            .whereField("brandID", isEqualTo: businessID)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        let campaigns = snapshot.documents.compactMap { doc -> AdCampaign? in
            try? doc.data(as: AdCampaign.self)
        }
        
        // Cache result
        businessCampaignsCache = CacheEntry(data: campaigns, cachedAt: Date(), ttl: campaignsTTL)
        self.businessCampaigns = campaigns
        return campaigns
    }
    
    // MARK: - Business Account: Fetch Stats
    
    /// Fetches aggregated stats for a business account. Cached for 10 min.
    @MainActor
    func fetchBusinessStats(businessID: String) async throws -> BusinessAdStats {
        // Check cache
        if let cached = businessStatsCache[businessID], !cached.isExpired {
            self.businessStats = cached.data
            return cached.data
        }
        
        let docRef = db.collection(Collections.businessStats).document(businessID)
        let doc = try await docRef.getDocument()
        
        let stats: BusinessAdStats
        if let fetched = try? doc.data(as: BusinessAdStats.self) {
            stats = fetched
        } else {
            stats = BusinessAdStats(
                businessID: businessID,
                totalCampaigns: 0,
                activeCampaigns: 0,
                totalSpend: 0,
                totalImpressions: 0,
                totalClicks: 0,
                averageCPM: 0,
                lastCampaignDate: nil
            )
        }
        
        // Cache per-business
        businessStatsCache[businessID] = CacheEntry(data: stats, cachedAt: Date(), ttl: statsTTL)
        self.businessStats = stats
        return stats
    }
    
    // MARK: - Business Account: Pause/Resume Campaign
    
    @MainActor
    func pauseCampaign(_ campaignID: String) async throws {
        try await db.collection(Collections.campaigns)
            .document(campaignID)
            .updateData([
                "status": AdCampaignStatus.paused.rawValue,
                "updatedAt": Timestamp()
            ])
        businessCampaignsCache = nil
        print("⏸ AD: Campaign \(campaignID) paused")
    }
    
    @MainActor
    func resumeCampaign(_ campaignID: String) async throws {
        try await db.collection(Collections.campaigns)
            .document(campaignID)
            .updateData([
                "status": AdCampaignStatus.active.rawValue,
                "updatedAt": Timestamp()
            ])
        businessCampaignsCache = nil
        print("▶️ AD: Campaign \(campaignID) resumed")
    }
    
    // MARK: - Matching Algorithm
    
    /// Auto-match scoring. Business sets criteria, platform finds best creators.
    /// Called by Cloud Function when campaign is created — NOT client-side in production.
    func calculateMatchScore(campaign: AdCampaign, creator: BasicUserInfo, creatorMetrics: CreatorMetrics) -> Int {
        var score = 0
        let requirements = campaign.requirements
        
        // Tier check (required gate)
        guard creator.tier.cloutRange.lowerBound >= requirements.minimumTier.cloutRange.lowerBound else {
            return 0
        }
        score += 20
        
        // Stitchers/followers
        if let minStitchers = requirements.minimumStitchers {
            score += creatorMetrics.stitcherCount >= minStitchers ? 15 : -10
        } else {
            score += 10
        }
        
        // Hype rating
        if let minHypeRating = requirements.minimumHypeRating {
            score += creatorMetrics.hypeRating >= minHypeRating ? 15 : -10
        } else {
            score += 10
        }
        
        // Engagement rate
        if let minEngagement = requirements.minimumEngagementRate {
            score += creatorMetrics.engagementRate >= minEngagement ? 15 : -10
        } else {
            score += 10
        }
        
        // View count
        if let minViews = requirements.minimumViewCount {
            score += creatorMetrics.totalViews >= minViews ? 10 : -5
        } else {
            score += 5
        }
        
        // Category match — strong signal for relevance
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
            let matchCount = creatorMetrics.topHashtags.filter { requiredHashtags.contains($0) }.count
            score += min(matchCount * 5, 15)
        } else {
            score += 5
        }
        
        return max(0, min(score, 100))
    }
    
    // MARK: - End Partnership
    
    @MainActor
    func endPartnership(_ partnership: AdPartnership) async throws {
        try await db.collection(Collections.partnerships)
            .document(partnership.id)
            .updateData(["status": AdPartnershipStatus.ended.rawValue])
        
        // Invalidate caches
        partnershipsCache = nil
        creatorStatsCache.removeAll()
        
        activePartnerships.removeAll { $0.id == partnership.id }
        print("🔚 AD: Partnership ended with \(partnership.brandName)")
    }
    
    // MARK: - Cache Management
    
    /// Clear all ad caches. Called on logout.
    func clearAllCaches() {
        opportunitiesCache = nil
        partnershipsCache = nil
        creatorStatsCache.removeAll()
        businessStatsCache.removeAll()
        businessCampaignsCache = nil
        
        availableOpportunities = []
        activePartnerships = []
        creatorStats = nil
        businessStats = nil
        businessCampaigns = []
        
        print("🧹 AD: All caches cleared")
    }
    
    /// Force refresh — invalidates all caches, next fetch hits Firestore.
    func invalidateAllCaches() {
        opportunitiesCache = nil
        partnershipsCache = nil
        creatorStatsCache.removeAll()
        businessStatsCache.removeAll()
        businessCampaignsCache = nil
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
    case businessAccountRequired
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientTier:
            return "You need to be Influencer tier or higher to access the ad marketplace"
        case .opportunityExpired:
            return "This opportunity has expired"
        case .campaignNotFound:
            return "Campaign not found"
        case .alreadyAccepted:
            return "You've already accepted this opportunity"
        case .businessAccountRequired:
            return "A Business account is required to create ad campaigns"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
