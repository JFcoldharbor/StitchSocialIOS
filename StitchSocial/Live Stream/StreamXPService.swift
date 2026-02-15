//
//  StreamXPService.swift
//  StitchSocial
//
//  Layer 6: Services - Stream Viewer XP & Badge Awards
//  Dependencies: LiveStreamTypes, CommunityXPService, LiveStreamService, StreamCoinService
//  Features: Attendance XP, multiplier stacking, idle detection,
//            post-stream badge awards, full-stay bonus
//
//  CACHING:
//  - viewerState: 100% local during stream, zero Firestore per-tick
//  - idleTimer: Local 15-min check, no Firestore reads
//  - streamBadgeHistory: Cached per community, 10-min TTL
//  - All XP goes through CommunityXPService buffer (already batched)
//
//  BATCHING:
//  - Attendance XP: Awarded once on join (base) and once on stream end (full-stay)
//  - NOT per-minute — two writes total per viewer per stream
//  - Badge eligibility: Pure logic against cached completion count
//  - Badge awards: Single batch write post-stream
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class StreamXPService: ObservableObject {
    
    static let shared = StreamXPService()
    
    // MARK: - Published State
    
    @Published var baseXPAwarded: Bool = false
    @Published var isIdle: Bool = false
    @Published var idleWarningShown: Bool = false
    @Published var earnedBadges: [StreamBadgeDefinition] = []
    @Published var postStreamRecap: StreamRecap?
    
    // MARK: - Private
    
    private let db = FirebaseConfig.firestore
    private var idleTimer: Timer?
    private var xpTickTimer: Timer?
    private var joinedAt: Date?
    private var lastInteractionAt: Date = Date()
    private var pendingMicroXP: Double = 0.0
    private var dailyXPMultiplier: Double = 1.0
    private var currentStreamID: String?
    private var currentCommunityID: String?
    private var currentUserID: String?
    
    // Badge history cache
    private var badgeHistoryCache: [String: CachedItem<[StreamBadgeAward]>] = [:]
    private let badgeHistoryTTL: TimeInterval = 600
    
    private struct CachedItem<T> {
        let value: T
        let cachedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(cachedAt) > ttl }
    }
    
    private init() {}
    
    // MARK: - Viewer Joins Stream
    
    /// Called when viewer joins — awards base XP, starts idle tracking
    func viewerJoinedStream(
        userID: String,
        communityID: String,
        streamID: String,
        tier: StreamDurationTier
    ) async {
        currentStreamID = streamID
        currentCommunityID = communityID
        currentUserID = userID
        joinedAt = Date()
        lastInteractionAt = Date()
        baseXPAwarded = false
        isIdle = false
        idleWarningShown = false
        earnedBadges = []
        
        // Check if creator is past daily cap — affects everyone's XP
        let dailyStatus = try? await LiveStreamService.shared.getDailyStreamStatus(creatorID: communityID)
        self.dailyXPMultiplier = dailyStatus?.xpMultiplier ?? 1.0
        
        // Award base attendance XP immediately (scaled by daily cap)
        // attendedLive = 50 XP base, multiply to match tier baseXP
        let baseMultiplier = Double(tier.baseXP) / 50.0 * dailyXPMultiplier
        CommunityXPService.shared.awardXP(
            userID: userID,
            communityID: communityID,
            source: .attendedLive,
            multiplier: baseMultiplier
        )
        baseXPAwarded = true
        
        // Start idle detection timer (checks every 60 sec)
        startIdleDetection()
        
        if dailyXPMultiplier < 1.0 {
            print("⚠️ STREAM XP: Reduced XP (\(Int(dailyXPMultiplier * 100))%) — creator past daily cap")
        }
        print("✅ STREAM XP: Viewer joined, +\(Int(Double(tier.baseXP) * dailyXPMultiplier)) base XP")
    }
    
    // MARK: - Viewer Interaction (Resets Idle)
    
    /// Called on any viewer action — chat, tap, reaction, hype
    /// Local only, no Firestore write
    func recordInteraction() {
        lastInteractionAt = Date()
        isIdle = false
        idleWarningShown = false
        
        // Also tell LiveStreamService for heartbeat buffer
        LiveStreamService.shared.recordViewerInteraction()
    }
    
    /// Micro XP for rapid-fire hype taps. Accumulates locally, no Firestore write per tap.
    /// Flushed as part of the normal heartbeat buffer every 5 min.
    /// Cost: 0 writes per call. Accumulated in pendingMicroXP.
    func recordMicroInteraction(xp: Double) {
        pendingMicroXP += xp
        lastInteractionAt = Date()
        isIdle = false
        idleWarningShown = false
        
        LiveStreamService.shared.recordViewerInteraction()
    }
    
    // MARK: - Viewer Leaves / Stream Ends
    
    /// Calculate and award full-stay bonus, check badge eligibility
    func viewerLeftStream(
        streamEnded: Bool = false
    ) async -> StreamRecap? {
        guard let userID = currentUserID,
              let communityID = currentCommunityID,
              let stream = LiveStreamService.shared.activeStream ?? nil else {
            cleanup()
            return nil
        }
        
        let tier = stream.durationTier
        var fullStayBonus = 0
        var cloutBonus = 0
        var newBadges: [StreamBadgeDefinition] = []
        
        // Check if viewer stayed the full stream duration
        if let joined = joinedAt {
            let watchedSeconds = Int(Date().timeIntervalSince(joined))
            let streamDuration = stream.elapsedSeconds
            
            // Full stay = watched at least 90% of stream duration AND stream completed full tier
            let watchedEnough = Double(watchedSeconds) >= Double(streamDuration) * 0.9
            let streamCompleted = stream.isFullCompletion
            
            if watchedEnough && streamCompleted && !isIdle {
                fullStayBonus = tier.fullStayBonusXP
                cloutBonus = tier.viewerCloutBonus
                
                // Award full-stay XP (scaled by daily cap)
                let bonusMultiplier = Double(fullStayBonus) / 50.0 * dailyXPMultiplier
                CommunityXPService.shared.awardXP(
                    userID: userID,
                    communityID: communityID,
                    source: .attendedLive,
                    multiplier: bonusMultiplier
                )
                
                // Award clout bonus for Double/Triple
                if cloutBonus > 0 {
                    // TODO: Write clout bonus through engagement system
                    print("🏆 STREAM XP: Clout bonus +\(cloutBonus) for full \(tier.displayName)")
                }
                
                // Check badge eligibility
                newBadges = await checkStreamBadgeEligibility(
                    userID: userID,
                    communityID: communityID,
                    completedTier: tier
                )
                earnedBadges = newBadges
            }
        }
        
        // Flush accumulated hype tap XP (0.12 per tap, scaled by daily cap)
        if pendingMicroXP > 0, let uid = currentUserID, let cid = currentCommunityID {
            let scaledMicro = pendingMicroXP * dailyXPMultiplier
            let microXPInt = Int(scaledMicro)
            if microXPInt > 0 {
                let microMultiplier = Double(microXPInt) / 50.0
                CommunityXPService.shared.awardXP(
                    userID: uid,
                    communityID: cid,
                    source: .attendedLive,
                    multiplier: microMultiplier
                )
                print("🔥 STREAM XP: Flushed \(pendingMicroXP) micro XP from \(Int(pendingMicroXP / 0.12)) hype taps")
            }
        }
        
        // Build recap
        let coinsSpent = 0 // Viewer's individual coins tracked elsewhere
        let recap = LiveStreamService.shared.buildRecap(
            stream: stream,
            coinsSpent: coinsSpent,
            badgesEarned: newBadges
        )
        self.postStreamRecap = recap
        
        cleanup()
        
        print("📊 STREAM XP: Viewer left — fullStay: \(fullStayBonus), badges: \(newBadges.count)")
        return recap
    }
    
    // MARK: - Stream Badge Eligibility
    
    /// Check if viewer earned any new stream badges
    /// Pure logic against cached attendance history
    private func checkStreamBadgeEligibility(
        userID: String,
        communityID: String,
        completedTier: StreamDurationTier
    ) async -> [StreamBadgeDefinition] {
        
        // Get existing badge awards
        let existingAwards = await fetchBadgeHistory(
            userID: userID,
            communityID: communityID
        )
        let existingBadgeIDs = Set(existingAwards.map { $0.badgeID })
        
        // Get attendance counts per tier from completions
        // This reuses LiveStreamService's cached completions
        let completions = (try? await fetchViewerAttendanceHistory(
            userID: userID,
            communityID: communityID
        )) ?? [:]
        
        // Include current stream
        var counts = completions
        counts[completedTier, default: 0] += 1
        
        var newBadges: [StreamBadgeDefinition] = []
        
        for badge in StreamBadgeDefinition.allBadges {
            // Skip if already earned (unless timestamped — those are per-stream)
            if !badge.isTimestamped && existingBadgeIDs.contains(badge.id) {
                continue
            }
            
            // Check if attendance count meets requirement
            let tierCount = counts[badge.tier] ?? 0
            if tierCount >= badge.requiredFullAttendances {
                newBadges.append(badge)
                
                // Write badge award
                if let streamID = currentStreamID {
                    let award = StreamBadgeAward(
                        badge: badge,
                        userID: userID,
                        communityID: communityID,
                        streamID: streamID
                    )
                    try? await db.collection("communities/\(communityID)/members/\(userID)/streamBadges")
                        .document(award.id)
                        .setData(from: award)
                }
            }
        }
        
        // Invalidate badge cache
        let cacheKey = "\(userID)_\(communityID)"
        badgeHistoryCache.removeValue(forKey: cacheKey)
        
        return newBadges
    }
    
    // MARK: - Fetch Badge History (Cached)
    
    private func fetchBadgeHistory(
        userID: String,
        communityID: String
    ) async -> [StreamBadgeAward] {
        let cacheKey = "\(userID)_\(communityID)"
        
        if let cached = badgeHistoryCache[cacheKey], !cached.isExpired {
            return cached.value
        }
        
        let snapshot = try? await db
            .collection("communities/\(communityID)/members/\(userID)/streamBadges")
            .getDocuments()
        
        let awards = snapshot?.documents.compactMap {
            try? $0.data(as: StreamBadgeAward.self)
        } ?? []
        
        badgeHistoryCache[cacheKey] = CachedItem(
            value: awards,
            cachedAt: Date(),
            ttl: badgeHistoryTTL
        )
        
        return awards
    }
    
    // MARK: - Fetch Viewer Attendance History
    
    /// Count full-stay attendances per tier for this viewer in this community
    private func fetchViewerAttendanceHistory(
        userID: String,
        communityID: String
    ) async throws -> [StreamDurationTier: Int] {
        // Query all streams where this user has attendance with earnedFullStayXP
        let snapshot = try await db
            .collectionGroup("attendance")
            .whereField("userID", isEqualTo: userID)
            .whereField("communityID", isEqualTo: communityID)
            .whereField("earnedFullStayXP", isEqualTo: true)
            .getDocuments()
        
        var counts: [StreamDurationTier: Int] = [:]
        
        for doc in snapshot.documents {
            if let attendance = try? doc.data(as: StreamAttendance.self) {
                // Need to look up the stream's tier — get from parent path
                // The stream doc is the parent of attendance
                let streamRef = doc.reference.parent.parent
                if let streamDoc = try? await streamRef?.getDocument(),
                   let stream = try? streamDoc.data(as: LiveStream.self) {
                    counts[stream.durationTier, default: 0] += 1
                }
            }
        }
        
        return counts
    }
    
    // MARK: - Idle Detection
    
    private func startIdleDetection() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let idleSeconds = Date().timeIntervalSince(self.lastInteractionAt)
                
                if idleSeconds >= 900 { // 15 min
                    self.isIdle = true
                    if !self.idleWarningShown {
                        self.idleWarningShown = true
                        print("⚠️ STREAM XP: Viewer idle for 15+ min")
                    }
                }
            }
        }
    }
    
    private func stopIdleDetection() {
        idleTimer?.invalidate()
        idleTimer = nil
    }
    
    // MARK: - Get Effective XP Multiplier
    
    /// Combines stream coin multiplier with base rate
    /// Called when awarding any XP during stream
    func effectiveMultiplier() -> Int {
        return StreamCoinService.shared.currentMultiplier()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        stopIdleDetection()
        xpTickTimer?.invalidate()
        xpTickTimer = nil
        joinedAt = nil
        currentStreamID = nil
        currentCommunityID = nil
        currentUserID = nil
        baseXPAwarded = false
        isIdle = false
        idleWarningShown = false
        pendingMicroXP = 0.0
        dailyXPMultiplier = 1.0
    }
    
    func onLogout() {
        cleanup()
        badgeHistoryCache.removeAll()
        earnedBadges = []
        postStreamRecap = nil
    }
}
