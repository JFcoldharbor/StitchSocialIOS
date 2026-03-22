//
//  BadgeService.swift
//  StitchSocial
//
//  Layer 3: Service — Badge Evaluation + Caching
//  Dependencies: BadgeTypes, Foundation, FirebaseFirestore
//
//  ──────────────────────────────────────────────────────────────
//  CACHING STRATEGY:
//  • definitionLookup  — populated from BadgeDefinition.allBadges at init,
//    delegates to file-scoped _badgeLookup (nonisolated). Zero Firestore reads.
//  • earnedBadgeCache  — [userID: [EarnedBadge]] in-memory + UserDefaults offline.
//    Driven by a single snapshot listener per user — no repeated get() calls.
//  • activeBoostCache  — [userID: Double] derived from earned seasonal badges.
//    Recomputed only on badge award or listener update.
//  • Firestore reads   — ONE snapshot listener per user. All writes are batched.
//  ──────────────────────────────────────────────────────────────

import Foundation
import FirebaseFirestore

@MainActor
final class BadgeService: ObservableObject {

    static let shared = BadgeService()
    private init() {}

    // MARK: - Caches

    /// Convenience wrapper — delegates to nonisolated _badgeLookup in BadgeTypes.swift
    func definition(id: String) -> BadgeDefinition? { BadgeDefinition.findBadge(id: id) }

    @Published private(set) var earnedBadgeCache: [String: [EarnedBadge]] = [:]
    @Published private(set) var activeBoostCache: [String: Double] = [:]

    private var listeners: [String: ListenerRegistration] = [:]
    private let db = Firestore.firestore()
    private let udKey = "badgeCache_v1"

    // MARK: - Public API

    func earnedBadges(for userID: String) -> [EarnedBadge] {
        earnedBadgeCache[userID] ?? []
    }

    func hypeBoostMultiplier(for userID: String) -> Double {
        activeBoostCache[userID] ?? 1.0
    }

    /// Start realtime listener — call once on profile appear.
    /// Single listener replaces all repeated get() calls.
    func listenForBadges(userID: String) {
        guard listeners[userID] == nil else { return }
        // Seed from UserDefaults immediately — view shows earned badges before async snap fires
        if earnedBadgeCache[userID] == nil {
            let cached = loadFromUserDefaults(userID: userID)
            if !cached.isEmpty {
                earnedBadgeCache[userID] = cached
                recomputeBoost(userID: userID, badges: cached)
            }
        }
        let ref = db.collection("users").document(userID).collection("badges")
        let listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            let badges = snap.documents.compactMap { try? $0.data(as: EarnedBadge.self) }
            Task { @MainActor in
                self.earnedBadgeCache[userID] = badges
                self.recomputeBoost(userID: userID, badges: badges)
                self.persistToUserDefaults(userID: userID, badges: badges)
            }
        }
        listeners[userID] = listener
    }

    func stopListening(userID: String) {
        listeners[userID]?.remove()
        listeners.removeValue(forKey: userID)
    }

    // MARK: - Evaluate & Award (standard badges)

    func evaluateAndAwardBadges(
        userID: String,
        stats: RealUserStats,
        tierRaw: String,
        xp: Int,
        coinsGiven: Int = 0,
        subscriptionsGiven: Int = 0,
        subscribersEarned: Int = 0
    ) async {
        let alreadyEarned = Set(earnedBadges(for: userID).map { $0.id })
        let now = Date()
        var toAward: [EarnedBadge] = []

        for badge in BadgeDefinition.allBadges {
            guard !alreadyEarned.contains(badge.id),
                  !badge.requirements.isManuallyAwarded,
                  badge.requirements.signalBadgeKind == nil   // signal badges use separate path
            else { continue }
            if let season = badge.requirements.seasonRequired, !season.isActive(on: now) { continue }
            if meetsRequirements(badge.requirements, stats: stats, tierRaw: tierRaw, xp: xp, coinsGiven: coinsGiven, subscriptionsGiven: subscriptionsGiven, subscribersEarned: subscribersEarned) {
                toAward.append(EarnedBadge(id: badge.id, earnedAt: now, isPinned: false, isNew: true))
            }
        }

        if !toAward.isEmpty { await batchWrite(userID: userID, badges: toAward) }
    }

    // MARK: - Evaluate & Award (signal badges)

    func evaluateSignalBadges(userID: String, signalStats: SignalStats) async {
        let alreadyEarned = Set(earnedBadges(for: userID).map { $0.id })
        let toAward = SignalBadgeEvaluator.evaluate(stats: signalStats, alreadyEarned: alreadyEarned)
        if !toAward.isEmpty { await batchWrite(userID: userID, badges: toAward) }
    }

    // MARK: - Manual Award

    func awardManualBadge(userID: String, badgeID: String) async {
        let badge = EarnedBadge(id: badgeID, earnedAt: Date(), isPinned: false, isNew: true)
        await batchWrite(userID: userID, badges: [badge])
    }

    // MARK: - Rookie Welcome Badge (called by AuthService on user doc creation)
    // Zero Firestore reads — fires once at signup, no evaluation needed.
    func awardRookieBadge(userID: String) async {
        let alreadyEarned = Set(earnedBadges(for: userID).map { $0.id })
        guard !alreadyEarned.contains("tier_rookie") else { return }
        await batchWrite(userID: userID, badges: [
            EarnedBadge(id: "tier_rookie", earnedAt: Date(), isPinned: false, isNew: true)
        ])
    }

    // MARK: - Tier Badge Award (called by UserService.checkAndAdvanceTier)
    // Pass the NEW tier raw string — no extra Firestore read needed, tier comes
    // from the same user doc snapshot that triggered tier advancement.
    // CACHING: earnedBadgeCache check prevents duplicate awards without a read.
    func evaluateTierBadge(userID: String, newTierRaw: String) async {
        let badgeID = "tier_\(newTierRaw)"   // e.g. "tier_rising", "tier_elite"
        let alreadyEarned = Set(earnedBadges(for: userID).map { $0.id })
        guard !alreadyEarned.contains(badgeID),
              BadgeDefinition.findBadge(id: badgeID) != nil else { return }
        await batchWrite(userID: userID, badges: [
            EarnedBadge(id: badgeID, earnedAt: Date(), isPinned: false, isNew: true)
        ])
    }

    // MARK: - Pin / Unpin

    func togglePin(userID: String, badgeID: String) async {
        var badges = earnedBadges(for: userID)
        guard let idx = badges.firstIndex(where: { $0.id == badgeID }) else { return }
        let pinnedCount = badges.filter { $0.isPinned }.count
        guard badges[idx].isPinned || pinnedCount < 3 else { return }
        badges[idx].isPinned.toggle()
        earnedBadgeCache[userID] = badges
        try? await db.collection("users").document(userID)
            .collection("badges").document(badgeID)
            .updateData(["isPinned": badges[idx].isPinned])
    }

    func markSeen(userID: String, badgeID: String) async {
        guard var badges = earnedBadgeCache[userID],
              let idx = badges.firstIndex(where: { $0.id == badgeID }) else { return }
        badges[idx].isNew = false
        earnedBadgeCache[userID] = badges
        try? await db.collection("users").document(userID)
            .collection("badges").document(badgeID)
            .updateData(["isNew": false])
    }

    // MARK: - Progress

    func badgeProgress(for userID: String, stats: RealUserStats, xp: Int) -> [BadgeProgress] {
        let earned = Set(earnedBadges(for: userID).map { $0.id })
        let now = Date()
        var result: [BadgeProgress] = []
        for badge in BadgeDefinition.allBadges {
            guard !earned.contains(badge.id),
                  !badge.requirements.isManuallyAwarded,
                  badge.requirements.signalBadgeKind == nil else { continue }
            // Skip seasonal badges when their season is not currently active
            if let season = badge.requirements.seasonRequired, !season.isActive(on: now) { continue }
            if let p = computeProgress(badge: badge, stats: stats, xp: xp) { result.append(p) }
        }
        return result.sorted { $0.progressFraction > $1.progressFraction }
    }

    // MARK: - Private helpers

    private func meetsRequirements(
        _ req: BadgeRequirements,
        stats: RealUserStats,
        tierRaw: String,
        xp: Int,
        coinsGiven: Int = 0,
        subscriptionsGiven: Int = 0,
        subscribersEarned: Int = 0
    ) -> Bool {
        if xp < req.minXP                          { return false }
        if stats.clout < req.minClout              { return false }
        if stats.hypes < req.minHypesGiven         { return false }
        if stats.posts < req.minPosts              { return false }
        if stats.followers < req.minFollowers      { return false }
        if coinsGiven < req.minCoinsGiven          { return false }
        if subscriptionsGiven < req.minSubscriptionsGiven { return false }
        if subscribersEarned < req.minSubscribersEarned   { return false }
        if let tier = req.requiredTier {
            guard isTierAtOrAbove(tierRaw, required: tier) else { return false }
        }
        return true
    }

    private func isTierAtOrAbove(_ current: String, required: String) -> Bool {
        let order = ["rookie","rising","veteran","influencer","ambassador",
                     "elite","partner","legendary","top_creator","founder","co_founder"]
        guard let ci = order.firstIndex(of: current),
              let ri = order.firstIndex(of: required) else { return false }
        return ci >= ri
    }

    private func computeProgress(badge: BadgeDefinition, stats: RealUserStats, xp: Int) -> BadgeProgress? {
        let req = badge.requirements
        // Build all applicable (current, target) pairs, pick the bottleneck (lowest fraction)
        var pairs: [(Int, Int)] = []
        if req.minHypesGiven > 0        { pairs.append((stats.hypes,                req.minHypesGiven)) }
        if req.minCoolsGiven > 0        { pairs.append((stats.hypes,                req.minCoolsGiven)) }
        if req.minPosts > 0             { pairs.append((stats.posts,                req.minPosts)) }
        if req.minFollowers > 0         { pairs.append((stats.followers,            req.minFollowers)) }
        if req.minClout > 0             { pairs.append((stats.clout,                req.minClout)) }
        if req.minCoinsGiven > 0        { pairs.append((stats.coinsGiven,           req.minCoinsGiven)) }
        if req.minSubscriptionsGiven > 0 { pairs.append((stats.subscriptionsGiven, req.minSubscriptionsGiven)) }
        if req.minSubscribersEarned > 0  { pairs.append((stats.subscribersEarned,  req.minSubscribersEarned)) }
        if req.minXP > 0                { pairs.append((xp,                         req.minXP)) }
        // Pick the bottleneck — lowest fraction (hardest to complete)
        guard let bottleneck = pairs.min(by: { Double($0.0)/Double($0.1) < Double($1.0)/Double($1.1) }) else { return nil }
        let (current, target) = bottleneck
        let fraction = min(1.0, Double(current) / Double(target))
        return BadgeProgress(id: badge.id, definition: badge,
                             progressFraction: fraction,
                             currentValue: current, targetValue: target)
    }

    private func recomputeBoost(userID: String, badges: [EarnedBadge]) {
        let now = Date()
        var multiplier = 1.0
        for badge in badges {
            guard let def = BadgeDefinition.findBadge(id: badge.id),
                  def.grantsSeasonalBoost,
                  let season = def.season,
                  season.isActive(on: now) else { continue }
            multiplier = max(multiplier, season.hypeBoostMultiplier)
        }
        activeBoostCache[userID] = multiplier
    }

    private func batchWrite(userID: String, badges: [EarnedBadge]) async {
        let batch = db.batch()
        let col   = db.collection("users").document(userID).collection("badges")
        for badge in badges {
            guard let data = try? Firestore.Encoder().encode(badge) else { continue }
            batch.setData(data, forDocument: col.document(badge.id))
        }
        try? await batch.commit()
        // earnedBadgeCache updates automatically via snapshot listener — no extra read
    }

    private func persistToUserDefaults(userID: String, badges: [EarnedBadge]) {
        if let data = try? JSONEncoder().encode(badges) {
            UserDefaults.standard.set(data, forKey: "\(udKey)_\(userID)")
        }
    }

    func loadFromUserDefaults(userID: String) -> [EarnedBadge] {
        guard let data = UserDefaults.standard.data(forKey: "\(udKey)_\(userID)"),
              let badges = try? JSONDecoder().decode([EarnedBadge].self, from: data) else { return [] }
        return badges
    }
}
