//
//  SubscriptionService.swift
//  StitchSocial
//
//  Handles creator subscription plans and fan active subscriptions.
//
//  CACHING:
//  - creatorPlanCache: [creatorID: CreatorSubscriptionPlan] — 10min TTL
//  - mySubsCache: [ActiveSubscription] — 5min TTL
//  - isSubscribedCache: [creatorID: Bool] — 5min TTL
//  Single reads on miss, no polling. Invalidate on write.
//
//  BATCHING: None needed — plan reads are per-creator, subs list is per-user.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

final class SubscriptionService: ObservableObject {

    static let shared = SubscriptionService()

    // MARK: - Published

    @Published private(set) var mySubscriptions: [ActiveSubscription] = []  // fan view
    @Published private(set) var mySubscribers:    [ActiveSubscription] = []  // creator view
    @Published private(set) var creatorPlan: CreatorSubscriptionPlan?

    // MARK: - Cache

    private var creatorPlanCache:   [String: (plan: CreatorSubscriptionPlan, fetchedAt: Date)] = [:]
    private var isSubscribedCache:  [String: (value: Bool, fetchedAt: Date)] = [:]
    private var mySubsFetchedAt:       Date?
    private var mySubscribersFetchedAt: Date?

    private let planTTL:  TimeInterval = 600   // 10 min
    private let subsTTL:  TimeInterval = 300   // 5 min

    // MARK: - Firestore

    private let db = FirebaseConfig.firestore

    private var plansCollection:  CollectionReference { db.collection("creator_subscription_plans") }
    private var subsCollection:   CollectionReference { db.collection("subscriptions") }

    private var currentUserEmail: String?

    private init() {}

    func setCurrentUserEmail(_ email: String?) {
        currentUserEmail = email
    }

    // MARK: - Creator Plan

    func fetchCreatorPlan(creatorID: String) async throws -> CreatorSubscriptionPlan? {
        guard Auth.auth().currentUser != nil else { return nil }

        if let cached = creatorPlanCache[creatorID],
           Date().timeIntervalSince(cached.fetchedAt) < planTTL {
            return cached.plan
        }

        let doc = try await plansCollection.document(creatorID).getDocument()
        guard doc.exists, let plan = try? doc.data(as: CreatorSubscriptionPlan.self) else {
            return nil
        }

        creatorPlanCache[creatorID] = (plan, Date())
        await MainActor.run { if plan.creatorID == Auth.auth().currentUser?.uid { creatorPlan = plan } }
        return plan
    }

    func createOrUpdatePlan(
        creatorID: String,
        creatorTier: UserTier,
        isEnabled: Bool,
        tierPricing: TierPricing,
        welcomeMessage: String?
    ) async throws -> CreatorSubscriptionPlan {
        var plan: CreatorSubscriptionPlan

        if let existing = try await fetchCreatorPlan(creatorID: creatorID) {
            plan = existing
            // 60-day cooldown applies to perk changes (prices are now fixed)
            if plan.tierPricing.customPerks != tierPricing.customPerks {
                guard plan.canChangePrice else {
                    throw SubscriptionError.priceCooldownActive(daysLeft: plan.daysUntilPriceChange)
                }
                plan.lastPriceChangeAt = Date()
                plan.nextPriceChangeAllowedAt = Calendar.current.date(byAdding: .day, value: 60, to: Date())
            }
            plan.isEnabled = isEnabled
            plan.tierPricing = tierPricing
            plan.customWelcomeMessage = welcomeMessage
            plan.updatedAt = Date()
        } else {
            plan = CreatorSubscriptionPlan(creatorID: creatorID, tierPricing: tierPricing)
            // id assigned by Firestore from doc path
            plan.isEnabled = isEnabled
            plan.customWelcomeMessage = welcomeMessage
        }

        try plansCollection.document(creatorID).setData(from: plan, merge: false)

        // Invalidate cache
        creatorPlanCache.removeValue(forKey: creatorID)
        await MainActor.run { creatorPlan = plan }
        return plan
    }

    // MARK: - Subscribe

    func subscribe(
        subscriberID: String,
        creatorID: String,
        creatorTier: UserTier,
        coinTier: CoinPriceTier = .starter
    ) async throws -> ActiveSubscription {
        guard let plan = try await fetchCreatorPlan(creatorID: creatorID), plan.isEnabled else {
            throw SubscriptionError.planNotFound
        }

        let price = coinTier.rawValue  // fixed platform price

        // Debit coins
        try await HypeCoinService.shared.transferCoins(
            fromUserID: subscriberID,
            toUserID: creatorID,
            amount: price,
            type: .subscriptionSent
        )

        // Resolve perks from creator's plan — uses custom config if set, otherwise platform defaults
        let resolvedPerks = plan.tierPricing.perks(for: coinTier)
        let perkRawValues = resolvedPerks.map { $0.rawValue }

        let subID = "\(subscriberID)_\(creatorID)"
        let sub = ActiveSubscription(
            subscriberID: subscriberID,
            creatorID: creatorID,
            coinsPaid: price,
            coinTier: coinTier,
            status: .active,
            subscribedAt: Date(),
            currentPeriodStart: Date(),
            currentPeriodEnd: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
            autoRenew: true,
            grantedPerks: perkRawValues
        )

        try subsCollection.document(subID).setData(from: sub, merge: false)

        // Increment subscriber count — fire and forget, non-critical
        try? await plansCollection.document(creatorID).updateData([
            "subscriberCount": FieldValue.increment(Int64(1)),
            "totalEarned": FieldValue.increment(Int64(price))
        ])

        // Invalidate
        isSubscribedCache.removeValue(forKey: creatorID)
        mySubsFetchedAt = nil
        return sub
    }

    // MARK: - Cancel

    func cancelSubscription(subscriberID: String, creatorID: String) async throws {
        let subID = "\(subscriberID)_\(creatorID)"
        try await subsCollection.document(subID).updateData([
            "status": SubscriptionStatus.cancelled.rawValue,
            "autoRenew": false,
            "updatedAt": Timestamp(date: Date())
        ])

        try? await plansCollection.document(creatorID).updateData([
            "subscriberCount": FieldValue.increment(Int64(-1))
        ])

        isSubscribedCache.removeValue(forKey: creatorID)
        mySubsFetchedAt = nil
        mySubscribersFetchedAt = nil

        await MainActor.run {
            mySubscriptions.removeAll { $0.creatorID == creatorID }
            mySubscribers.removeAll { $0.subscriberID == creatorID }
        }
    }

    // MARK: - Fetch My Subscriptions

    @discardableResult
    func fetchMySubscriptions(userID: String) async throws -> [ActiveSubscription] {
        guard Auth.auth().currentUser != nil else { return [] }

        if let fetched = mySubsFetchedAt,
           Date().timeIntervalSince(fetched) < subsTTL,
           !mySubscriptions.isEmpty { return mySubscriptions }

        let snapshot = try await subsCollection
            .whereField("subscriberID", isEqualTo: userID)
            .whereField("status", isEqualTo: SubscriptionStatus.active.rawValue)
            .getDocuments()

        let subs = snapshot.documents.compactMap { try? $0.data(as: ActiveSubscription.self) }
        mySubsFetchedAt = Date()
        await MainActor.run { mySubscriptions = subs }
        return subs
    }

    // MARK: - Is Subscribed

    func isSubscribed(subscriberID: String, creatorID: String) async throws -> Bool {
        guard Auth.auth().currentUser != nil else { return false }

        if let cached = isSubscribedCache[creatorID],
           Date().timeIntervalSince(cached.fetchedAt) < subsTTL {
            return cached.value
        }

        let subID = "\(subscriberID)_\(creatorID)"
        let doc = try await subsCollection.document(subID).getDocument()
        let value = doc.exists &&
            (doc.data()?["status"] as? String) == SubscriptionStatus.active.rawValue

        isSubscribedCache[creatorID] = (value, Date())
        return value
    }



    // MARK: - Fetch My Subscribers (Creator Side)
    // CACHING: 5min TTL — same as mySubscriptions
    @discardableResult
    func fetchMySubscribers(creatorID: String) async throws -> [ActiveSubscription] {
        guard Auth.auth().currentUser != nil else { return [] }

        if let fetched = mySubscribersFetchedAt,
           Date().timeIntervalSince(fetched) < subsTTL,
           !mySubscribers.isEmpty { return mySubscribers }

        let snapshot = try await subsCollection
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", isEqualTo: SubscriptionStatus.active.rawValue)
            .getDocuments()

        let subs = snapshot.documents.compactMap { try? $0.data(as: ActiveSubscription.self) }
        mySubscribersFetchedAt = Date()
        await MainActor.run { mySubscribers = subs }
        return subs
    }

    // MARK: - Developer Bypass
    // Used by CommunityService to skip subscription gate in dev/debug builds
    var isDeveloper: Bool {
        #if DEBUG
        return (currentUserEmail ?? Auth.auth().currentUser?.email)?.hasSuffix("@stitch.dev") == true
        #else
        return false
        #endif
    }

    // MARK: - Check Subscription (used by CommunityService)
    struct SubscriptionCheck {
        let isSubscribed: Bool
        let coinsPaid: Int
        let coinTier: CoinPriceTier?
        let grantedPerks: [SubscriptionPerk]

        var hasNoAds: Bool {
            grantedPerks.contains(.noAds)
        }
        
        var hasCommunityAccess: Bool {
            grantedPerks.contains(.communityAccess)
        }
    }

    func checkSubscription(subscriberID: String, creatorID: String) async throws -> SubscriptionCheck {
        guard Auth.auth().currentUser != nil else {
            return SubscriptionCheck(isSubscribed: false, coinsPaid: 0, coinTier: nil, grantedPerks: [])
        }
        let subID = "\(subscriberID)_\(creatorID)"
        let doc = try await subsCollection.document(subID).getDocument()
        guard doc.exists,
              let data = doc.data(),
              (data["status"] as? String) == SubscriptionStatus.active.rawValue else {
            return SubscriptionCheck(isSubscribed: false, coinsPaid: 0, coinTier: nil, grantedPerks: [])
        }
        let coinsPaid = data["coinsPaid"] as? Int ?? 0
        let tierRaw = data["coinTier"] as? Int ?? 0
        let coinTier = CoinPriceTier(rawValue: tierRaw)
        
        // Read stamped perks — fall back to platform defaults for legacy subs
        let perks: [SubscriptionPerk]
        if let rawPerks = data["grantedPerks"] as? [String], !rawPerks.isEmpty {
            perks = rawPerks.compactMap { SubscriptionPerk(rawValue: $0) }
        } else if let tier = coinTier {
            perks = SubscriptionPerks.perks(for: tier)
        } else {
            perks = []
        }
        
        isSubscribedCache[creatorID] = (true, Date())
        return SubscriptionCheck(isSubscribed: true, coinsPaid: coinsPaid, coinTier: coinTier, grantedPerks: perks)
    }

    // MARK: - Cache Invalidation

    func invalidatePlanCache(creatorID: String) {
        creatorPlanCache.removeValue(forKey: creatorID)
    }

    func invalidateAll() {
        creatorPlanCache.removeAll()
        isSubscribedCache.removeAll()
        mySubsFetchedAt = nil
        mySubscribersFetchedAt = nil
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case planNotFound
    case alreadySubscribed
    case priceCooldownActive(daysLeft: Int)
    case insufficientCoins

    var errorDescription: String? {
        switch self {
        case .planNotFound:               return "Subscription plan not found."
        case .alreadySubscribed:          return "You are already subscribed."
        case .priceCooldownActive(let d): return "Price locked for \(d) more days."
        case .insufficientCoins:          return "Not enough coins."
        }
    }
}
