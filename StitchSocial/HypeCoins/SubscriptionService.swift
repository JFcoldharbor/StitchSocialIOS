//
//  SubscriptionService.swift
//  StitchSocial
//
//  Created by James Garmon on 2/2/26.
//


//
//  SubscriptionService.swift
//  StitchSocial
//
//  Service for subscriptions, perks, and subscriber management
//

import Foundation
import FirebaseFirestore

class SubscriptionService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SubscriptionService()
    
    // MARK: - Properties
    
    private let db = FirebaseConfig.firestore
    private let coinService = HypeCoinService.shared
    
    @Published var mySubscriptions: [ActiveSubscription] = []
    @Published var mySubscribers: [SubscriberInfo] = []
    @Published var creatorPlan: CreatorSubscriptionPlan?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Cache for quick perk lookups — cached per session, cleared on logout
    private var subscriptionCache: [String: SubscriptionCheckResult] = [:]
    
    // MARK: - Developer Bypass
    // These emails get full subscription access without payment.
    // Cached on login so we never re-check Firestore for this.
    
    private static let developerEmails: Set<String> = [
        "developers@stitchsocial.me",
        "james@stitchsocial.me"
    ]
    
    private var cachedUserEmail: String?
    
    /// Call once on login with the authenticated user's email
    func setCurrentUserEmail(_ email: String?) {
        cachedUserEmail = email?.lowercased().trimmingCharacters(in: .whitespaces)
    }
    
    /// True if current user bypasses all subscription gates
    var isDeveloper: Bool {
        guard let email = cachedUserEmail else { return false }
        return Self.developerEmails.contains(email)
    }
    
    // MARK: - Collections
    
    private enum Collections {
        static let plans = "subscription_plans"
        static let subscriptions = "subscriptions"
        static let subscribers = "subscribers"
        static let events = "subscription_events"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Creator Plan Setup
    
    @MainActor
    func fetchCreatorPlan(creatorID: String) async throws -> CreatorSubscriptionPlan? {
        let docRef = db.collection(Collections.plans).document(creatorID)
        let doc = try await docRef.getDocument()
        
        if let plan = try? doc.data(as: CreatorSubscriptionPlan.self) {
            self.creatorPlan = plan
            return plan
        }
        
        return nil
    }
    
    @MainActor
    func createOrUpdatePlan(
        creatorID: String,
        isEnabled: Bool,
        supporterPrice: Int,
        superFanPrice: Int,
        supporterEnabled: Bool,
        superFanEnabled: Bool,
        welcomeMessage: String?
    ) async throws -> CreatorSubscriptionPlan {
        
        // Validate prices
        guard SubscriptionTier.supporter.coinRange.contains(supporterPrice) else {
            throw SubscriptionError.invalidPrice
        }
        guard SubscriptionTier.superFan.coinRange.contains(superFanPrice) else {
            throw SubscriptionError.invalidPrice
        }
        
        let docRef = db.collection(Collections.plans).document(creatorID)
        let existingDoc = try await docRef.getDocument()
        
        var plan: CreatorSubscriptionPlan
        
        if existingDoc.exists, var existing = try? existingDoc.data(as: CreatorSubscriptionPlan.self) {
            // Update existing
            existing.isEnabled = isEnabled
            existing.supporterPrice = supporterPrice
            existing.superFanPrice = superFanPrice
            existing.supporterEnabled = supporterEnabled
            existing.superFanEnabled = superFanEnabled
            existing.customWelcomeMessage = welcomeMessage
            existing.updatedAt = Date()
            plan = existing
        } else {
            // Create new
            plan = CreatorSubscriptionPlan(creatorID: creatorID)
            plan.isEnabled = isEnabled
            plan.supporterPrice = supporterPrice
            plan.superFanPrice = superFanPrice
            plan.supporterEnabled = supporterEnabled
            plan.superFanEnabled = superFanEnabled
            plan.customWelcomeMessage = welcomeMessage
        }
        
        try docRef.setData(from: plan)
        self.creatorPlan = plan
        
        print("âœ… SUBS: Plan updated for \(creatorID)")
        return plan
    }
    
    // MARK: - Subscribe
    
    @MainActor
    func subscribe(
        subscriberID: String,
        creatorID: String,
        tier: SubscriptionTier
    ) async throws -> ActiveSubscription {
        
        isLoading = true
        defer { isLoading = false }
        
        // Fetch creator's plan
        guard let plan = try await fetchCreatorPlan(creatorID: creatorID),
              plan.isEnabled,
              plan.isTierEnabled(tier) else {
            throw SubscriptionError.subscriptionsNotEnabled
        }
        
        let price = plan.priceForTier(tier)
        
        // Check if already subscribed
        if let existing = try await getSubscription(subscriberID: subscriberID, creatorID: creatorID) {
            if existing.isActive {
                throw SubscriptionError.alreadySubscribed
            }
        }
        
        // Transfer coins
        try await coinService.transferCoins(
            fromUserID: subscriberID,
            toUserID: creatorID,
            amount: price,
            type: .subscriptionReceived,
            subscriptionID: nil
        )
        
        // Create subscription
        let subscription = ActiveSubscription(
            id: "\(subscriberID)_\(creatorID)",
            subscriberID: subscriberID,
            creatorID: creatorID,
            tier: tier,
            coinsPaid: price,
            status: .active,
            startedAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
            renewalEnabled: true,
            renewalCount: 0
        )
        
        try db.collection(Collections.subscriptions)
            .document(subscription.id)
            .setData(from: subscription)
        
        // Update creator's plan stats
        try await db.collection(Collections.plans)
            .document(creatorID)
            .updateData([
                "subscriberCount": FieldValue.increment(Int64(1)),
                "totalEarned": FieldValue.increment(Int64(price))
            ])
        
        // Record event
        let event = SubscriptionEvent(
            id: UUID().uuidString,
            subscriptionID: subscription.id,
            subscriberID: subscriberID,
            creatorID: creatorID,
            type: .newSubscription,
            tier: tier,
            coinAmount: price,
            createdAt: Date()
        )
        
        try db.collection(Collections.events)
            .document(event.id)
            .setData(from: event)
        
        // Clear cache
        subscriptionCache.removeValue(forKey: "\(subscriberID)_\(creatorID)")
        
        // Refresh my subscriptions
        _ = try await fetchMySubscriptions(userID: subscriberID)
        
        print("ðŸŽ‰ SUBS: \(subscriberID) subscribed to \(creatorID) at \(tier.displayName)")
        return subscription
    }
    
    // MARK: - Cancel Subscription
    
    @MainActor
    func cancelSubscription(subscriberID: String, creatorID: String) async throws {
        let subRef = db.collection(Collections.subscriptions).document("\(subscriberID)_\(creatorID)")
        
        try await subRef.updateData([
            "renewalEnabled": false,
            "status": SubscriptionStatus.cancelled.rawValue
        ])
        
        // Record event
        let event = SubscriptionEvent(
            id: UUID().uuidString,
            subscriptionID: "\(subscriberID)_\(creatorID)",
            subscriberID: subscriberID,
            creatorID: creatorID,
            type: .cancellation,
            tier: .supporter, // Will be overwritten
            coinAmount: 0,
            createdAt: Date()
        )
        
        try db.collection(Collections.events)
            .document(event.id)
            .setData(from: event)
        
        subscriptionCache.removeValue(forKey: "\(subscriberID)_\(creatorID)")
        
        print("âŒ SUBS: \(subscriberID) cancelled subscription to \(creatorID)")
    }
    
    // MARK: - Check Subscription Status
    
    func checkSubscription(subscriberID: String, creatorID: String) async throws -> SubscriptionCheckResult {
        // Developer bypass — full superFan access, no Firestore read
        if isDeveloper {
            return SubscriptionCheckResult(
                isSubscribed: true,
                tier: .superFan,
                perks: SubscriptionTier.superFan.perks,
                hypeBoost: SubscriptionTier.superFan.hypeBoost
            )
        }
        
        // Check cache first
        let cacheKey = "\(subscriberID)_\(creatorID)"
        if let cached = subscriptionCache[cacheKey] {
            return cached
        }
        
        guard let subscription = try await getSubscription(subscriberID: subscriberID, creatorID: creatorID),
              subscription.isActive else {
            let result = SubscriptionCheckResult.none
            subscriptionCache[cacheKey] = result
            return result
        }
        
        let result = SubscriptionCheckResult(
            isSubscribed: true,
            tier: subscription.tier,
            perks: subscription.tier.perks,
            hypeBoost: subscription.tier.hypeBoost
        )
        
        subscriptionCache[cacheKey] = result
        return result
    }
    
    // MARK: - Get Subscription
    
    func getSubscription(subscriberID: String, creatorID: String) async throws -> ActiveSubscription? {
        let docRef = db.collection(Collections.subscriptions).document("\(subscriberID)_\(creatorID)")
        let doc = try await docRef.getDocument()
        return try? doc.data(as: ActiveSubscription.self)
    }
    
    // MARK: - Fetch My Subscriptions (as subscriber)
    
    @MainActor
    func fetchMySubscriptions(userID: String) async throws -> [ActiveSubscription] {
        let snapshot = try await db.collection(Collections.subscriptions)
            .whereField("subscriberID", isEqualTo: userID)
            .whereField("status", isEqualTo: "active")
            .getDocuments()
        
        let subscriptions = snapshot.documents.compactMap { doc -> ActiveSubscription? in
            try? doc.data(as: ActiveSubscription.self)
        }
        
        self.mySubscriptions = subscriptions
        return subscriptions
    }
    
    // MARK: - Fetch My Subscribers (as creator)
    
    @MainActor
    func fetchMySubscribers(creatorID: String) async throws -> [SubscriberInfo] {
        let snapshot = try await db.collection(Collections.subscriptions)
            .whereField("creatorID", isEqualTo: creatorID)
            .whereField("status", isEqualTo: "active")
            .order(by: "startedAt", descending: true)
            .getDocuments()
        
        // Would need to join with user data for full info
        // Simplified version:
        var subscribers: [SubscriberInfo] = []
        
        for doc in snapshot.documents {
            if let sub = try? doc.data(as: ActiveSubscription.self) {
                let info = SubscriberInfo(
                    id: sub.id,
                    subscriberID: sub.subscriberID,
                    username: "", // Fetch separately
                    displayName: "", // Fetch separately
                    profileImageURL: nil,
                    tier: sub.tier,
                    subscribedAt: sub.startedAt,
                    totalPaid: sub.coinsPaid * (sub.renewalCount + 1),
                    renewalCount: sub.renewalCount
                )
                subscribers.append(info)
            }
        }
        
        self.mySubscribers = subscribers
        return subscribers
    }
    
    // MARK: - Get Hype Boost for Engagement
    
    func getHypeBoost(userID: String, creatorID: String) async throws -> Double {
        if isDeveloper { return SubscriptionTier.superFan.hypeBoost }
        let result = try await checkSubscription(subscriberID: userID, creatorID: creatorID)
        return result.hypeBoost
    }
    
    // MARK: - Check Perk Access
    
    func hasPerk(_ perk: SubscriptionPerk, userID: String, creatorID: String) async throws -> Bool {
        if isDeveloper { return true }
        let result = try await checkSubscription(subscriberID: userID, creatorID: creatorID)
        return result.perks.contains(perk)
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        subscriptionCache.removeAll()
    }
    
    func clearCache(for subscriberID: String, creatorID: String) {
        subscriptionCache.removeValue(forKey: "\(subscriberID)_\(creatorID)")
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case subscriptionsNotEnabled
    case invalidPrice
    case alreadySubscribed
    case notSubscribed
    case insufficientCoins
    
    var errorDescription: String? {
        switch self {
        case .subscriptionsNotEnabled:
            return "This creator hasn't enabled subscriptions"
        case .invalidPrice:
            return "Invalid subscription price"
        case .alreadySubscribed:
            return "You're already subscribed"
        case .notSubscribed:
            return "You're not subscribed to this creator"
        case .insufficientCoins:
            return "Not enough Hype Coins"
        }
    }
}
