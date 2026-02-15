//
//  CommunityXPService.swift
//  StitchSocial
//
//  Layer 5: Services - Community XP Calculations, Level-Ups, Badge Unlocks
//  Dependencies: CommunityTypes (Layer 1), CommunityService (Layer 5)
//  Features: Award XP, level-up detection, badge eligibility, daily login, XP buffering
//
//  CACHING STRATEGY:
//  - xpLookupTable: Static array of 1000 cumulative XP values, built once at init
//  - pendingXP: In-memory buffer, flushes to Firestore every 30 seconds or on background
//  - badgeDefinitions: Static, never refetch (CommunityBadgeDefinition.allBadges)
//  - levelCache: Per user+community, invalidated on XP award
//  Add to CachingOptimization.swift under "Community XP Batching" section
//
//  BATCHING NOTES:
//  - XP awards accumulate in pendingXP buffer, NOT written per action
//  - Flush writes membership update + XP log entry in single batch
//  - Badge checks run locally against cached level, no Firestore reads
//  - Daily login uses lastDailyLoginAt field, one read per community per day
//

import Foundation
import FirebaseFirestore

class CommunityXPService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CommunityXPService()
    
    // MARK: - Properties
    
    private let db = FirebaseConfig.firestore
    private let communityService = CommunityService.shared
    
    @Published var lastLevelUp: LevelUpEvent?
    @Published var lastBadgeUnlock: CommunityBadgeDefinition?
    
    // MARK: - XP Lookup Table (Built Once, Never Refetch)
    
    /// Cumulative XP for each level 0-1000, computed at init
    /// Avoids recalculating the curve on every XP award
    private let xpLookupTable: [Int]
    
    // MARK: - XP Buffer (Batch Writes)
    
    /// Pending XP per community — flushed every 30 seconds
    /// Key: "userID_communityID"
    private var pendingXP: [String: PendingXPBuffer] = [:]
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 30
    
    private struct PendingXPBuffer {
        let userID: String
        let communityID: String
        var totalPending: Int
        var sources: [CommunityXPSource]
        var lastAddedAt: Date
    }
    
    // MARK: - Collections
    
    private enum Collections {
        static let communities = "communities"
        static let members = "members"
        static let xpLog = "xpLog"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Build lookup table once — 1000 entries, pure math, zero Firestore reads
        var table = [Int](repeating: 0, count: 1001)
        for level in 2...1000 {
            table[level] = table[level - 1] + CommunityXPCurve.xpRequired(for: level)
        }
        self.xpLookupTable = table
        
        startFlushTimer()
    }
    
    deinit {
        flushTimer?.invalidate()
    }
    
    // MARK: - Award XP (Buffered)
    
    /// Awards XP to a user in a community — DOES NOT write immediately
    /// Accumulates in buffer, flushed every 30 seconds
    func awardXP(
        userID: String,
        communityID: String,
        source: CommunityXPSource,
        multiplier: Double = 1.0
    ) {
        let amount = Int(Double(source.xpAmount) * multiplier)
        guard amount > 0 else { return }
        
        let key = "\(userID)_\(communityID)"
        
        if var existing = pendingXP[key] {
            existing.totalPending += amount
            existing.sources.append(source)
            existing.lastAddedAt = Date()
            pendingXP[key] = existing
        } else {
            pendingXP[key] = PendingXPBuffer(
                userID: userID,
                communityID: communityID,
                totalPending: amount,
                sources: [source],
                lastAddedAt: Date()
            )
        }
        
        print("📊 XP BUFFER: +\(amount) (\(source.displayName)) for \(userID) in \(communityID) — pending: \(pendingXP[key]?.totalPending ?? 0)")
    }
    
    /// Award XP immediately — use sparingly for critical events (level-up ceremonies, badge awards)
    @MainActor
    func awardXPImmediate(
        userID: String,
        communityID: String,
        source: CommunityXPSource,
        multiplier: Double = 1.0
    ) async throws -> XPAwardResult {
        let amount = Int(Double(source.xpAmount) * multiplier)
        return try await writeXP(userID: userID, communityID: communityID, amount: amount, source: source)
    }
    
    // MARK: - Flush Pending XP (Batched Write)
    
    /// Flushes all pending XP to Firestore — called by timer or app background
    @MainActor
    func flushPendingXP() async {
        guard !pendingXP.isEmpty else { return }
        
        let toFlush = pendingXP
        pendingXP.removeAll()
        
        for (_, buffer) in toFlush {
            do {
                let primarySource = buffer.sources.last ?? .textPost
                let result = try await writeXP(
                    userID: buffer.userID,
                    communityID: buffer.communityID,
                    amount: buffer.totalPending,
                    source: primarySource
                )
                
                if result.leveledUp {
                    print("🎉 XP FLUSH: \(buffer.userID) leveled up to \(result.newLevel) in \(buffer.communityID)")
                }
            } catch {
                // Re-queue failed flushes
                let key = "\(buffer.userID)_\(buffer.communityID)"
                pendingXP[key] = buffer
                print("⚠️ XP FLUSH FAILED: \(error.localizedDescription) — re-queued")
            }
        }
    }
    
    // MARK: - Core XP Write (Single Batched Operation)
    
    @MainActor
    private func writeXP(
        userID: String,
        communityID: String,
        amount: Int,
        source: CommunityXPSource
    ) async throws -> XPAwardResult {
        
        let memberRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.members)
            .document(userID)
        
        let doc = try await memberRef.getDocument()
        
        guard var membership = try? doc.data(as: CommunityMembership.self) else {
            throw CommunityError.notMember
        }
        
        let oldLevel = membership.level
        let oldXP = membership.localXP
        let newXP = oldXP + amount
        let newLevel = levelFromXP(newXP)
        let didLevelUp = newLevel > oldLevel
        
        // Check for badge unlocks
        let oldBadges = Set(membership.earnedBadgeIDs)
        let eligibleBadges = CommunityBadgeDefinition.badgesEarned(atLevel: newLevel)
        let newBadgeIDs = eligibleBadges.map { $0.id }.filter { !oldBadges.contains($0) }
        
        // Update membership
        membership.localXP = newXP
        membership.level = newLevel
        membership.earnedBadgeIDs.append(contentsOf: newBadgeIDs)
        membership.lastActiveAt = Date()
        
        // XP log entry
        let logEntry = CommunityXPTransaction(
            communityID: communityID,
            userID: userID,
            source: source,
            amount: amount,
            newTotalXP: newXP,
            newLevel: newLevel,
            leveledUp: didLevelUp,
            badgeUnlocked: newBadgeIDs.first
        )
        
        // BATCHED WRITE: membership update + xp log in one operation
        let batch = db.batch()
        
        try batch.setData(from: membership, forDocument: memberRef)
        
        let logRef = memberRef.collection(Collections.xpLog).document(logEntry.id)
        try batch.setData(from: logEntry, forDocument: logRef)
        
        try await batch.commit()
        
        // Invalidate membership cache so next fetch gets fresh data
        communityService.invalidateMembershipCache(userID: userID, creatorID: communityID)
        
        // Build result
        let result = XPAwardResult(
            xpAwarded: amount,
            newTotalXP: newXP,
            oldLevel: oldLevel,
            newLevel: newLevel,
            leveledUp: didLevelUp,
            newBadges: eligibleBadges.filter { newBadgeIDs.contains($0.id) },
            globalXPContribution: GlobalCommunityXP.globalContribution(from: amount)
        )
        
        // Publish events for UI
        if didLevelUp {
            self.lastLevelUp = LevelUpEvent(
                userID: userID,
                communityID: communityID,
                oldLevel: oldLevel,
                newLevel: newLevel,
                timestamp: Date()
            )
        }
        
        if let firstNewBadge = result.newBadges.first {
            self.lastBadgeUnlock = firstNewBadge
        }
        
        print("✅ XP WRITE: +\(amount) → \(newXP) total, Lv \(oldLevel)→\(newLevel), \(newBadgeIDs.count) new badges")
        return result
    }
    
    // MARK: - Level Calculation (Uses Lookup Table)
    
    /// O(log n) binary search on pre-computed lookup table — no math per call
    func levelFromXP(_ xp: Int) -> Int {
        guard xp > 0 else { return 1 }
        
        var low = 1
        var high = 1000
        
        while low < high {
            let mid = (low + high + 1) / 2
            if xpLookupTable[mid] <= xp {
                low = mid
            } else {
                high = mid - 1
            }
        }
        
        return low
    }
    
    /// Progress to next level using lookup table
    func progressToNext(currentXP: Int) -> Double {
        let level = levelFromXP(currentXP)
        guard level < 1000 else { return 1.0 }
        
        let currentLevelXP = xpLookupTable[level]
        let nextLevelXP = xpLookupTable[level + 1]
        let range = nextLevelXP - currentLevelXP
        
        guard range > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(currentXP - currentLevelXP) / Double(range)))
    }
    
    /// XP needed to reach next level
    func xpToNextLevel(currentXP: Int) -> Int {
        let level = levelFromXP(currentXP)
        guard level < 1000 else { return 0 }
        return xpLookupTable[level + 1] - currentXP
    }
    
    // MARK: - Daily Login XP
    
    /// Awards daily login XP if not already claimed today
    /// Single read to check lastDailyLoginAt, one write if eligible
    @MainActor
    func claimDailyLogin(userID: String, communityID: String) async throws -> DailyLoginResult {
        
        let memberRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.members)
            .document(userID)
        
        let doc = try await memberRef.getDocument()
        
        guard let membership = try? doc.data(as: CommunityMembership.self) else {
            throw CommunityError.notMember
        }
        
        // Check if already claimed today
        let calendar = Calendar.current
        if let lastLogin = membership.lastDailyLoginAt,
           calendar.isDateInToday(lastLogin) {
            return DailyLoginResult(
                awarded: false,
                xpAmount: 0,
                streak: membership.dailyLoginStreak,
                message: "Already claimed today"
            )
        }
        
        // Calculate streak
        var newStreak = 1
        if let lastLogin = membership.lastDailyLoginAt,
           calendar.isDateInYesterday(lastLogin) {
            newStreak = membership.dailyLoginStreak + 1
        }
        
        // Streak bonus: +1 XP per streak day, capped at +15
        let streakBonus = min(newStreak, 15)
        let totalXP = CommunityXPSource.dailyLogin.xpAmount + streakBonus
        
        // Update streak fields directly — no need to buffer daily login
        try await memberRef.updateData([
            "lastDailyLoginAt": Timestamp(date: Date()),
            "dailyLoginStreak": newStreak
        ])
        
        // Award XP through buffer
        awardXP(userID: userID, communityID: communityID, source: .dailyLogin, multiplier: Double(totalXP) / Double(CommunityXPSource.dailyLogin.xpAmount))
        
        communityService.invalidateMembershipCache(userID: userID, creatorID: communityID)
        
        print("✅ DAILY LOGIN: +\(totalXP) XP, streak: \(newStreak) in \(communityID)")
        
        return DailyLoginResult(
            awarded: true,
            xpAmount: totalXP,
            streak: newStreak,
            message: newStreak > 1 ? "🔥 \(newStreak) day streak! +\(streakBonus) bonus XP" : "Welcome back!"
        )
    }
    
    // MARK: - Bulk Badge Check
    
    /// Check all badge eligibility for a user — runs locally, no Firestore reads
    func checkBadgeEligibility(
        currentLevel: Int,
        earnedBadgeIDs: [String]
    ) -> BadgeCheckResult {
        let earned = Set(earnedBadgeIDs)
        let eligible = CommunityBadgeDefinition.allBadges.filter { $0.level <= currentLevel }
        let unearned = eligible.filter { !earned.contains($0.id) }
        let nextBadge = CommunityBadgeDefinition.nextBadge(afterLevel: currentLevel)
        
        return BadgeCheckResult(
            totalEarned: eligible.count,
            totalAvailable: CommunityBadgeDefinition.allBadges.count,
            newlyEligible: unearned,
            nextBadge: nextBadge,
            levelsToNextBadge: nextBadge != nil ? nextBadge!.level - currentLevel : 0
        )
    }
    
    // MARK: - Feature Gate Check (No Firestore)
    
    /// Check feature access using level — pure logic, no reads
    func canAccessFeature(_ feature: CommunityFeatureGate, atLevel level: Int) -> Bool {
        return level >= feature.requiredLevel
    }
    
    /// Get all unlocked features at a level
    func unlockedFeatures(atLevel level: Int) -> [CommunityFeatureGate] {
        return CommunityFeatureGate.allCases.filter { $0.requiredLevel <= level }
    }
    
    /// Get next feature unlock
    func nextFeatureUnlock(atLevel level: Int) -> CommunityFeatureGate? {
        return CommunityFeatureGate.allCases
            .sorted { $0.requiredLevel < $1.requiredLevel }
            .first { $0.requiredLevel > level }
    }
    
    // MARK: - XP from Coin Spending
    
    /// Award XP when user spends HypeCoin in a community
    /// Called by stream coin service or community actions
    func awardCoinSpendXP(userID: String, communityID: String, coinsSpent: Int) {
        // 20 XP per coin spent
        let totalXP = coinsSpent * CommunityXPSource.spentHypeCoin.xpAmount
        let sources = Array(repeating: CommunityXPSource.spentHypeCoin, count: coinsSpent)
        
        let key = "\(userID)_\(communityID)"
        if var existing = pendingXP[key] {
            existing.totalPending += totalXP
            existing.sources.append(contentsOf: sources)
            existing.lastAddedAt = Date()
            pendingXP[key] = existing
        } else {
            pendingXP[key] = PendingXPBuffer(
                userID: userID,
                communityID: communityID,
                totalPending: totalXP,
                sources: sources,
                lastAddedAt: Date()
            )
        }
        
        print("📊 XP BUFFER: +\(totalXP) from \(coinsSpent) coins spent in \(communityID)")
    }
    
    // MARK: - Flush Timer Management
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flushPendingXP()
            }
        }
    }
    
    /// Call on app entering background
    @MainActor
    func onAppBackground() async {
        await flushPendingXP()
    }
    
    /// Call on logout — flush then clear
    @MainActor
    func onLogout() async {
        await flushPendingXP()
        pendingXP.removeAll()
        flushTimer?.invalidate()
        lastLevelUp = nil
        lastBadgeUnlock = nil
    }
}

// MARK: - Result Types

struct XPAwardResult {
    let xpAwarded: Int
    let newTotalXP: Int
    let oldLevel: Int
    let newLevel: Int
    let leveledUp: Bool
    let newBadges: [CommunityBadgeDefinition]
    let globalXPContribution: Int
}

struct LevelUpEvent: Identifiable, Equatable {
    let id = UUID()
    let userID: String
    let communityID: String
    let oldLevel: Int
    let newLevel: Int
    let timestamp: Date
    
    static func == (lhs: LevelUpEvent, rhs: LevelUpEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct DailyLoginResult {
    let awarded: Bool
    let xpAmount: Int
    let streak: Int
    let message: String
}

struct BadgeCheckResult {
    let totalEarned: Int
    let totalAvailable: Int
    let newlyEligible: [CommunityBadgeDefinition]
    let nextBadge: CommunityBadgeDefinition?
    let levelsToNextBadge: Int
    
    var progress: Double {
        guard totalAvailable > 0 else { return 0 }
        return Double(totalEarned) / Double(totalAvailable)
    }
}
