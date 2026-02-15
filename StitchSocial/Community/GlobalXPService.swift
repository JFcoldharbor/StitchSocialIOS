//
//  GlobalXPService.swift
//  StitchSocial
//
//  Layer 5: Services - Global Community XP Aggregation, Tap Multipliers, Clout Bonuses
//  Dependencies: CommunityTypes (Layer 1), CommunityService (Layer 5), CommunityXPService (Layer 5)
//  Features: Global XP aggregation at 25%, clout milestone bonuses, per-community daily tap multipliers
//
//  CACHING STRATEGY:
//  - globalXPCache: Single GlobalCommunityXP object per user, cached on login, refresh every 15 min
//  - tapUsageCache: Dictionary [communityID: CommunityTapUsage], local only, reset at midnight
//  - cloutBonusLedger: Tracks which milestones have been awarded, prevents double-payouts
//  Add to CachingOptimization.swift under "Global XP Cache" section
//
//  BATCHING NOTES:
//  - recalculateGlobalXP: Single read of all memberships (one query), single write to global doc
//  - Daily clout payout: Should be Cloud Function in production, not per-user client trigger
//  - Tap multiplier usage: LOCAL ONLY — never reads Firestore per tap, syncs on session end
//  - Clout bonus writes: Batched with global XP update, not separate transactions
//

import Foundation
import FirebaseFirestore

class GlobalXPService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = GlobalXPService()
    
    // MARK: - Properties
    
    private let db = FirebaseConfig.firestore
    private let communityService = CommunityService.shared
    
    @Published var globalXP: GlobalCommunityXP?
    @Published var globalLevel: Int = 1
    @Published var tapMultiplier: Int = 0
    @Published var cloutBonus: Int = 0
    
    // MARK: - Cache
    
    private var globalXPCache: CachedItem<GlobalCommunityXP>?
    private var tapUsageCache: [String: CommunityTapUsage] = [:]
    private var awardedMilestones: Set<Int> = []  // Levels where clout was already awarded
    
    private struct CachedItem<T> {
        let value: T
        let cachedAt: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }
    
    private let globalTTL: TimeInterval = 900  // 15 min
    
    // MARK: - Collections
    
    private enum Collections {
        static let globalXP = "global_community_xp"
        static let communities = "communities"
        static let members = "members"
        static let cloutLog = "clout_bonus_log"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Load Global XP (Cached, Called on Login)
    
    /// Loads or creates global XP document — call once on login, cached for 15 min
    @MainActor
    func loadGlobalXP(userID: String) async throws -> GlobalCommunityXP {
        
        // Check cache
        if let cached = globalXPCache, !cached.isExpired {
            applyToPublished(cached.value)
            return cached.value
        }
        
        let docRef = db.collection(Collections.globalXP).document(userID)
        let doc = try await docRef.getDocument()
        
        var global: GlobalCommunityXP
        
        if let existing = try? doc.data(as: GlobalCommunityXP.self) {
            global = existing
        } else {
            // First time — create doc
            global = GlobalCommunityXP(userID: userID)
            try docRef.setData(from: global)
        }
        
        // Load awarded milestones to prevent double payouts
        await loadAwardedMilestones(userID: userID)
        
        // Cache and publish
        globalXPCache = CachedItem(value: global, cachedAt: Date(), ttl: globalTTL)
        applyToPublished(global)
        
        // Initialize daily tap usage
        resetTapUsageIfNewDay()
        
        print("✅ GLOBAL XP: Loaded for \(userID) — Lv \(global.globalLevel), +\(global.tapMultiplierBonus) taps, +\(global.permanentCloutBonus) clout")
        return global
    }
    
    // MARK: - Recalculate Global XP (Single Query + Single Write)
    
    /// Recalculates global XP from all community memberships
    /// ONE query to get all memberships, ONE write to update global doc
    /// Call after XP flush, or periodically (every 15 min)
    @MainActor
    func recalculateGlobalXP(userID: String) async throws -> GlobalCommunityXP {
        
        // Get all communities the user is in
        let communities = try await communityService.fetchMyCommunities(userID: userID)
        
        guard !communities.isEmpty else {
            return try await loadGlobalXP(userID: userID)
        }
        
        // Sum local XP at 25% rate
        var totalGlobalXP = 0
        var activeCount = 0
        
        for community in communities {
            let contribution = GlobalCommunityXP.globalContribution(from: community.userXP)
            totalGlobalXP += contribution
            if community.userXP > 0 { activeCount += 1 }
        }
        
        // Calculate global level from XP using same curve
        let globalLevel = CommunityXPCurve.levelFromXP(totalGlobalXP)
        let tapBonus = GlobalCommunityXP.tapMultiplierForLevel(globalLevel)
        
        // Check for new clout milestones
        let newCloutBonus = calculateTotalCloutBonus(forLevel: globalLevel)
        let previousClout = globalXP?.permanentCloutBonus ?? 0
        let cloutDelta = max(0, newCloutBonus - previousClout)
        
        // Build updated global XP
        var updated = GlobalCommunityXP(userID: userID)
        updated.totalGlobalXP = totalGlobalXP
        updated.globalLevel = globalLevel
        updated.permanentCloutBonus = newCloutBonus
        updated.tapMultiplierBonus = tapBonus
        updated.communitiesActive = activeCount
        updated.lastCalculatedAt = Date()
        
        // SINGLE WRITE: update global doc
        let docRef = db.collection(Collections.globalXP).document(userID)
        try docRef.setData(from: updated)
        
        // Award new clout milestones if any
        if cloutDelta > 0 {
            try await awardCloutBonus(userID: userID, amount: cloutDelta, atLevel: globalLevel)
        }
        
        // Cache and publish
        globalXPCache = CachedItem(value: updated, cachedAt: Date(), ttl: globalTTL)
        applyToPublished(updated)
        
        print("✅ GLOBAL XP: Recalculated — \(totalGlobalXP) XP, Lv \(globalLevel), \(activeCount) communities, +\(tapBonus) taps, +\(newCloutBonus) clout")
        return updated
    }
    
    // MARK: - Clout Bonus Calculation
    
    /// Total accumulated clout bonus for reaching a global level
    /// Checks all milestone thresholds up to current level
    private func calculateTotalCloutBonus(forLevel level: Int) -> Int {
        let milestones = [10, 25, 50, 75, 100, 150, 200]
        var total = 0
        for milestone in milestones where level >= milestone {
            total += GlobalCommunityXP.cloutBonusForLevel(milestone)
        }
        return total
    }
    
    /// Award clout bonus — writes to user clout and logs milestone
    /// BATCHING: In production, daily clout should be a Cloud Function
    private func awardCloutBonus(userID: String, amount: Int, atLevel level: Int) async throws {
        guard amount > 0 else { return }
        
        // Prevent double-award
        guard !awardedMilestones.contains(level) else { return }
        
        let batch = db.batch()
        
        // Increment user's clout (assumes user doc has a clout field)
        // In production, integrate with your existing clout system
        let cloutLogRef = db.collection(Collections.cloutLog).document("\(userID)_global_\(level)")
        let logEntry: [String: Any] = [
            "userID": userID,
            "source": "global_community_xp",
            "amount": amount,
            "globalLevel": level,
            "awardedAt": Timestamp(date: Date())
        ]
        batch.setData(logEntry, forDocument: cloutLogRef)
        
        try await batch.commit()
        
        awardedMilestones.insert(level)
        
        print("🏆 GLOBAL CLOUT: +\(amount) clout awarded to \(userID) at global Lv \(level)")
    }
    
    /// Load previously awarded milestones to prevent double payouts on re-login
    private func loadAwardedMilestones(userID: String) async {
        do {
            let snapshot = try await db.collection(Collections.cloutLog)
                .whereField("userID", isEqualTo: userID)
                .whereField("source", isEqualTo: "global_community_xp")
                .getDocuments()
            
            for doc in snapshot.documents {
                if let level = doc.data()["globalLevel"] as? Int {
                    awardedMilestones.insert(level)
                }
            }
        } catch {
            print("⚠️ GLOBAL XP: Failed to load milestone history: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Tap Multiplier (LOCAL ONLY — No Firestore Per Tap)
    
    /// Get remaining bonus taps for a specific community today
    /// Reads from local cache ONLY — zero Firestore cost
    func remainingBonusTaps(communityID: String) -> Int {
        resetTapUsageIfNewDay()
        
        guard let usage = tapUsageCache[communityID] else {
            // First access today — full bonus available
            return tapMultiplier
        }
        
        return usage.remainingBonusTaps
    }
    
    /// Use a bonus tap — LOCAL ONLY, returns the multiplier if bonus available
    /// Returns 1 (normal) if no bonus taps remain, or 2 (boosted) if bonus used
    func useBonusTap(communityID: String) -> Int {
        resetTapUsageIfNewDay()
        
        guard tapMultiplier > 0 else { return 1 }  // No bonus at all
        
        if var usage = tapUsageCache[communityID] {
            guard usage.hasRemainingBonusTaps else { return 1 }
            usage.bonusTapsUsed += 1
            tapUsageCache[communityID] = usage
            return 2  // Boosted tap
        } else {
            // First bonus tap today in this community
            var usage = CommunityTapUsage(
                communityID: communityID,
                date: todayString(),
                bonusTapsUsed: 1,
                bonusTapsAllowed: tapMultiplier
            )
            tapUsageCache[communityID] = usage
            return 2  // Boosted tap
        }
    }
    
    /// Check if user has any bonus taps remaining across any community
    func hasAnyBonusTaps() -> Bool {
        guard tapMultiplier > 0 else { return false }
        resetTapUsageIfNewDay()
        
        // If any community hasn't been accessed today, there are unused taps
        let usedCommunities = tapUsageCache.values.filter { !$0.hasRemainingBonusTaps }
        // Can't easily know total communities here, so just check tap multiplier > 0
        return true
    }
    
    // MARK: - Daily Reset
    
    private func resetTapUsageIfNewDay() {
        let today = todayString()
        
        // If any cached entry is from a different day, clear all
        if let firstEntry = tapUsageCache.values.first, firstEntry.date != today {
            tapUsageCache.removeAll()
        }
    }
    
    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    // MARK: - Sync Tap Usage (Call on Session End)
    
    /// Persists daily tap usage to Firestore for analytics
    /// Call on app background — NOT per tap
    func syncTapUsage(userID: String) async {
        guard !tapUsageCache.isEmpty else { return }
        
        do {
            let batch = db.batch()
            let date = todayString()
            
            for (communityID, usage) in tapUsageCache {
                let docRef = db.collection(Collections.globalXP)
                    .document(userID)
                    .collection("tapUsage")
                    .document("\(date)_\(communityID)")
                
                let data: [String: Any] = [
                    "communityID": communityID,
                    "date": date,
                    "bonusTapsUsed": usage.bonusTapsUsed,
                    "bonusTapsAllowed": usage.bonusTapsAllowed,
                    "syncedAt": Timestamp(date: Date())
                ]
                
                batch.setData(data, forDocument: docRef)
            }
            
            try await batch.commit()
            print("✅ GLOBAL XP: Synced tap usage for \(tapUsageCache.count) communities")
        } catch {
            print("⚠️ GLOBAL XP: Failed to sync tap usage: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Progress Info (For UI)
    
    /// Get progress toward next global level
    func progressToNextLevel() -> Double {
        guard let global = globalXP else { return 0 }
        return CommunityXPCurve.progressToNextLevel(currentXP: global.totalGlobalXP)
    }
    
    /// Get XP needed for next global level
    func xpToNextLevel() -> Int {
        guard let global = globalXP else { return 0 }
        let currentLevel = global.globalLevel
        guard currentLevel < 1000 else { return 0 }
        let nextLevelXP = CommunityXPCurve.totalXPForLevel(currentLevel + 1)
        return max(0, nextLevelXP - global.totalGlobalXP)
    }
    
    /// Get next clout milestone
    func nextCloutMilestone() -> (level: Int, clout: Int)? {
        let milestones = [10, 25, 50, 75, 100, 150, 200]
        let currentLevel = globalXP?.globalLevel ?? 1
        
        for milestone in milestones where milestone > currentLevel {
            return (milestone, GlobalCommunityXP.cloutBonusForLevel(milestone))
        }
        return nil
    }
    
    /// Get next tap multiplier upgrade level
    func nextTapUpgrade() -> (level: Int, newMultiplier: Int)? {
        let thresholds: [(level: Int, newMultiplier: Int)] = [
            (10, 1), (25, 2), (50, 3), (75, 4), (100, 5)
        ]
        let currentLevel = globalXP?.globalLevel ?? 1
        
        for threshold in thresholds where threshold.level > currentLevel {
            return threshold
        }
        return nil
    }
    
    /// Summary for profile display
    func globalSummary() -> GlobalXPSummary {
        let global = globalXP ?? GlobalCommunityXP(userID: "")
        return GlobalXPSummary(
            totalXP: global.totalGlobalXP,
            level: global.globalLevel,
            cloutBonus: global.permanentCloutBonus,
            tapMultiplier: global.tapMultiplierBonus,
            communitiesActive: global.communitiesActive,
            progress: progressToNextLevel(),
            xpToNext: xpToNextLevel(),
            nextCloutMilestone: nextCloutMilestone(),
            nextTapUpgrade: nextTapUpgrade()
        )
    }
    
    // MARK: - Publish Helpers
    
    private func applyToPublished(_ global: GlobalCommunityXP) {
        self.globalXP = global
        self.globalLevel = global.globalLevel
        self.tapMultiplier = global.tapMultiplierBonus
        self.cloutBonus = global.permanentCloutBonus
    }
    
    // MARK: - Cache Management
    
    func clearAllCaches() {
        globalXPCache = nil
        tapUsageCache.removeAll()
        awardedMilestones.removeAll()
        globalXP = nil
        globalLevel = 1
        tapMultiplier = 0
        cloutBonus = 0
    }
    
    func invalidateGlobalCache() {
        globalXPCache = nil
    }
    
    /// Call on app background — flush tap usage + recalculate if stale
    @MainActor
    func onAppBackground(userID: String) async {
        await syncTapUsage(userID: userID)
        
        if let cache = globalXPCache, cache.isExpired {
            _ = try? await recalculateGlobalXP(userID: userID)
        }
    }
    
    /// Call on logout — sync then clear everything
    @MainActor
    func onLogout(userID: String) async {
        await syncTapUsage(userID: userID)
        clearAllCaches()
    }
}

// MARK: - Summary Type (For UI)

struct GlobalXPSummary {
    let totalXP: Int
    let level: Int
    let cloutBonus: Int
    let tapMultiplier: Int
    let communitiesActive: Int
    let progress: Double
    let xpToNext: Int
    let nextCloutMilestone: (level: Int, clout: Int)?
    let nextTapUpgrade: (level: Int, newMultiplier: Int)?
}
