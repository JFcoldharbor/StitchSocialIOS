//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager
//  Dependencies: VideoEngagementService, VideoService, UserService, NotificationService
//  Features: Progressive tapping, hype rating management, INSTANT ENGAGEMENTS, Push Notifications
//  UPDATED: Atomic increment operations - eliminates race conditions and expensive reads (40% cost reduction)
//  UPDATED: Long press burst system - isBurst param controls regular vs burst clout/hype
//  UPDATED: Auto-cleanup timer for engagement state cache (prevents memory bloat)
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class EngagementManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let videoEngagementService: VideoEngagementService
    private let userService: UserService
    private let notificationService: NotificationService
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isProcessingEngagement = false
    @Published var engagementStates: [String: VideoEngagementState] = [:]
    @Published var lastEngagementTime: [String: Date] = [:]
    
    // MARK: - Hype Rating (delegate to HypeRatingService)
    
    var userHypeRating: Double {
        get { HypeRatingService.shared.currentRating }
        set { /* managed by HypeRatingService */ }
    }
    
    // MARK: - Configuration
    
    private let engagementCooldown: TimeInterval = 0.5
    
    // MARK: - 🆕 Cache Cleanup Timer
    // Caching note: engagementStates dict caches per-session but had no auto-cleanup.
    // clearOldStates() was never called automatically. This timer fires every 5 min
    // to evict stale entries (>1hr old), preventing memory bloat in long sessions.
    private var cleanupTimer: Timer?
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService,
        videoEngagementService: VideoEngagementService? = nil,
        notificationService: NotificationService? = nil
    ) {
        self.videoService = videoService
        self.userService = userService
        self.notificationService = notificationService ?? NotificationService()
        
        if let providedService = videoEngagementService {
            self.videoEngagementService = providedService
        } else {
            self.videoEngagementService = VideoEngagementService(
                videoService: videoService,
                userService: userService
            )
        }
        
        // 🆕 Start auto-cleanup timer for engagement state cache
        startCacheCleanupTimer()
        
        print("🎯 ENGAGEMENT MANAGER: Initialized with burst system + auto-cache cleanup")
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    /// Get or create engagement state for video/user pair
    func getEngagementState(videoID: String, userID: String) -> VideoEngagementState {
        let key = "\(videoID)_\(userID)"
        
        if let existingState = engagementStates[key] {
            return existingState
        }
        
        Task {
            await loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
        }
        
        let newState = VideoEngagementState(videoID: videoID, userID: userID)
        engagementStates[key] = newState
        return newState
    }
    
    // MARK: - Self-Engagement Validation
    
    private func canSelfEngage(userID: String, creatorID: String, userTier: UserTier) -> Bool {
        if userID != creatorID {
            return true
        }
        return userTier == .founder || userTier == .coFounder
    }
    
    // MARK: - Process Hype (ATOMIC INCREMENT - NO READS)
    // 🆕 isBurst: false = regular tap (+1 hype, reduced clout), true = long press (full tier multiplier)
    
    func processHype(videoID: String, userID: String, userTier: UserTier, creatorID: String? = nil, isBurst: Bool = false) async throws -> Bool {
        
        // Self-engagement validation
        if let creatorID = creatorID {
            guard canSelfEngage(userID: userID, creatorID: creatorID, userTier: userTier) else {
                throw StitchError.validationError("You can't hype your own content")
            }
        }
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .cool && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from cool to hype after grace period")
        }
        
        // IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .cool && state.isWithinGracePeriod {
            print("🔄 SWITCHING: Cool → Hype (within grace period)")
            let originalCools = state.coolEngagements
            state.coolEngagements = 0
            state.hypeEngagements = 0
            state.totalCloutGiven = 0
            state.totalVisualHypesGiven = 0
            
            do {
                try await db.collection("videos").document(videoID).updateData([
                    "coolCount": FieldValue.increment(Int64(-originalCools)),
                    "lastEngagementAt": Timestamp(),
                    "updatedAt": Timestamp()
                ])
                print("✅ SWITCHING: Removed \(originalCools) cools (atomic)")
            } catch {
                print("⚠️ SWITCHING: Failed to update: \(error)")
            }
        }
        
        // SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
        if state.firstEngagementAt == nil {
            state.firstEngagementAt = Date()
            print("⏱️ GRACE PERIOD: Started (60 seconds)")
        }
        
        // Check caps
        if state.hasHitCloutCap(for: userTier) {
            throw StitchError.validationError("Clout cap reached for this video")
        }
        
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        
        // Check hype rating (burst costs more)
        let cost = EngagementCalculator.calculateHypeRatingCost(tier: userTier, isBurst: isBurst)
        guard HypeRatingService.shared.canAfford(cost) else {
            throw StitchError.validationError("Insufficient hype rating" + (isBurst ? " for burst" : ""))
        }
        
        // 🆕 Calculate visual hype increment BEFORE recording (burst-aware)
        let visualHypeIncrement = EngagementConfig.getVisualHypeMultiplier(for: userTier, isBurst: isBurst)
        
        // Instant engagement with visual hype tracking
        state.addHypeEngagement(visualHypes: visualHypeIncrement)
        
        // Deduct hype rating
        HypeRatingService.shared.deductRating(cost)
        
        // Calculate rewards (burst-aware)
        let tapNumber = state.hypeEngagements
        let isFirstEngagement = (state.hypeEngagements == 1)
        let currentCloutFromUser = state.totalCloutGiven
        
        let cloutAwarded = EngagementCalculator.calculateCloutReward(
            giverTier: userTier,
            tapNumber: tapNumber,
            isFirstEngagement: isFirstEngagement,
            currentCloutFromThisUser: currentCloutFromUser,
            isBurst: isBurst
        )
        
        // Record clout
        state.recordCloutAwarded(cloutAwarded, isHype: true, isBurst: isBurst)
        engagementStates["\(videoID)_\(userID)"] = state
        await saveEngagementStateToFirebase(state)
        
        // ATOMIC INCREMENT IN FIRESTORE - NO READ NEEDED
        do {
            try await db.collection("videos").document(videoID).updateData([
                "hypeCount": FieldValue.increment(Int64(visualHypeIncrement)),
                "lastEngagementAt": Timestamp(),
                "updatedAt": Timestamp()
            ])
            let mode = isBurst ? "BURST" : "regular"
            print("🔥 HYPE (\(mode)): +\(visualHypeIncrement) hypes (atomic), +\(cloutAwarded) clout")
        } catch {
            print("❌ Failed to update video: \(error)")
            throw error
        }
        
        // Fetch video ONLY for notification (title needed) - separate read, no contention
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
        } catch {
            print("⚠️ Failed to fetch video for notification: \(error)")
            video = CoreVideoMetadata(
                id: videoID,
                title: "Video",
                description: "",
                taggedUserIDs: [],
                videoURL: "",
                thumbnailURL: "",
                creatorID: creatorID ?? "",
                creatorName: "",
                createdAt: Date(),
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: 0,
                hypeCount: 0,
                coolCount: 0,
                replyCount: 0,
                shareCount: 0,
                temperature: "neutral",
                qualityScore: 50,
                engagementRatio: 0.5,
                velocityScore: 0,
                trendingScore: 0,
                duration: 0,
                aspectRatio: 9.0/16.0,
                fileSize: 0,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil
            )
        }
        
        // SEND NOTIFICATION TO VIDEO CREATOR (async, non-blocking)
        print("🔍 HYPE NOTIF CHECK: creatorID='\(creatorID ?? "nil")', userID='\(userID)', videoID='\(videoID)', equal=\(creatorID == userID)")
        if let creatorID = creatorID, creatorID != userID {
            print("🔍 HYPE NOTIF GATE PASSED: Sending to creatorID='\(creatorID)'")
            Task {
                do {
                    try await notificationService.sendEngagementNotification(
                        to: creatorID,
                        videoID: videoID,
                        engagementType: isBurst ? "hype_burst" : "hype",
                        videoTitle: video.title
                    )
                    print("✅ HYPE NOTIFICATION: Sent to \(creatorID)")
                } catch {
                    print("⚠️ HYPE NOTIFICATION: Failed - \(error.localizedDescription)")
                }
                
                await HypeRatingService.shared.queueEngagementRegen(
                    source: .receivedHype,
                    amount: HypeRegenSource.receivedHype.baseRegenAmount
                )
            }
        }
        
        // Post notification for UI update
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
    }
    
    // MARK: - Process Cool (ATOMIC INCREMENT - NO READS)
    // Cool has no burst variant - long press on cool is not a thing
    
    func processCool(videoID: String, userID: String, userTier: UserTier, creatorID: String? = nil) async throws -> Bool {
        
        // Self-engagement validation
        if let creatorID = creatorID {
            guard canSelfEngage(userID: userID, creatorID: creatorID, userTier: userTier) else {
                throw StitchError.validationError("You can't cool your own content")
            }
        }
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .hype && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from hype to cool after grace period")
        }
        
        // IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .hype && state.isWithinGracePeriod {
            print("🔄 SWITCHING: Hype → Cool (within grace period)")
            // 🆕 Use tracked visual hypes for accurate decrement (not tierMultiplier * count)
            let hypeDecrement = state.totalVisualHypesGiven
            
            state.hypeEngagements = 0
            state.coolEngagements = 0
            state.totalCloutGiven = 0
            state.totalVisualHypesGiven = 0
            
            do {
                try await db.collection("videos").document(videoID).updateData([
                    "hypeCount": FieldValue.increment(Int64(-hypeDecrement)),
                    "lastEngagementAt": Timestamp(),
                    "updatedAt": Timestamp()
                ])
                print("✅ SWITCHING: Removed \(hypeDecrement) visual hypes (accurate atomic)")
            } catch {
                print("⚠️ SWITCHING: Failed to update: \(error)")
            }
        }
        
        // SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
        if state.firstEngagementAt == nil {
            state.firstEngagementAt = Date()
            print("⏱️ GRACE PERIOD: Started (60 seconds)")
        }
        
        // Check engagement cap
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        
        // Instant engagement - no tapping progress
        state.addCoolEngagement()
        
        // Calculate rewards
        let visualCoolIncrement = 1
        let cloutPenalty = EngagementCalculator.calculateCoolPenalty()
        
        // Record clout (negative)
        state.recordCloutAwarded(cloutPenalty, isHype: false)
        engagementStates["\(videoID)_\(userID)"] = state
        await saveEngagementStateToFirebase(state)
        
        // ATOMIC INCREMENT IN FIRESTORE - NO READ NEEDED
        do {
            try await db.collection("videos").document(videoID).updateData([
                "coolCount": FieldValue.increment(Int64(visualCoolIncrement)),
                "lastEngagementAt": Timestamp(),
                "updatedAt": Timestamp()
            ])
            print("❄️ COOL: +\(visualCoolIncrement) cool (atomic), \(cloutPenalty) clout")
        } catch {
            print("❌ Failed to update video: \(error)")
            throw error
        }
        
        // Fetch video ONLY for notification (title needed)
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
        } catch {
            print("⚠️ Failed to fetch video for notification: \(error)")
            video = CoreVideoMetadata(
                id: videoID,
                title: "Video",
                description: "",
                taggedUserIDs: [],
                videoURL: "",
                thumbnailURL: "",
                creatorID: creatorID ?? "",
                creatorName: "",
                createdAt: Date(),
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: 0,
                hypeCount: 0,
                coolCount: 0,
                replyCount: 0,
                shareCount: 0,
                temperature: "neutral",
                qualityScore: 50,
                engagementRatio: 0.5,
                velocityScore: 0,
                trendingScore: 0,
                duration: 0,
                aspectRatio: 9.0/16.0,
                fileSize: 0,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil
            )
        }
        
        // SEND NOTIFICATION TO VIDEO CREATOR (async, non-blocking)
        print("🔍 COOL NOTIF CHECK: creatorID='\(creatorID ?? "nil")', userID='\(userID)', videoID='\(videoID)', equal=\(creatorID == userID)")
        if let creatorID = creatorID, creatorID != userID {
            print("🔍 COOL NOTIF GATE PASSED: Sending to creatorID='\(creatorID)'")
            Task {
                do {
                    try await notificationService.sendEngagementNotification(
                        to: creatorID,
                        videoID: videoID,
                        engagementType: "cool",
                        videoTitle: video.title
                    )
                    print("✅ COOL NOTIFICATION: Sent to \(creatorID)")
                } catch {
                    print("⚠️ COOL NOTIFICATION: Failed - \(error.localizedDescription)")
                }
            }
        }
        
        // Post notification for UI update
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
    }
    
    // MARK: - Remove All Engagement (Long Press - ATOMIC DECREMENTS)
    // 🆕 Uses totalVisualHypesGiven for accurate decrement instead of tierMultiplier * count
    
    func removeAllEngagement(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        print("🗑️ REMOVE ALL: Attempting to remove engagement")
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Check if within grace period
        guard state.isWithinGracePeriod else {
            print("❌ REMOVE ALL: Grace period expired")
            throw StitchError.validationError("Cannot remove engagement after grace period")
        }
        
        print("✅ REMOVE ALL: Within grace period, proceeding...")
        
        // 🆕 Use tracked totals for accurate decrement (handles mixed regular + burst)
        let hypeDecrement = state.totalVisualHypesGiven
        let coolDecrement = state.coolEngagements
        
        // Reset everything
        state.hypeEngagements = 0
        state.coolEngagements = 0
        state.totalEngagements = 0
        state.totalCloutGiven = 0
        state.totalVisualHypesGiven = 0
        state.firstEngagementAt = nil
        state.lastEngagementAt = Date()
        
        // Update in-memory state
        let key = "\(videoID)_\(userID)"
        engagementStates[key] = state
        await saveEngagementStateToFirebase(state)
        
        // ATOMIC DECREMENTS IN FIRESTORE - NO READ NEEDED
        do {
            var updates: [String: Any] = [
                "lastEngagementAt": Timestamp(),
                "updatedAt": Timestamp()
            ]
            
            if hypeDecrement > 0 {
                updates["hypeCount"] = FieldValue.increment(Int64(-hypeDecrement))
            }
            
            if coolDecrement > 0 {
                updates["coolCount"] = FieldValue.increment(Int64(-coolDecrement))
            }
            
            try await db.collection("videos").document(videoID).updateData(updates)
            
            print("✅ REMOVE ALL: Removed \(hypeDecrement) visual hypes and \(coolDecrement) cools (accurate atomic)")
            
            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
            
        } catch {
            print("❌ REMOVE ALL: Failed to update video: \(error)")
            throw error
        }
    }
    
    // MARK: - Firebase Persistence
    
    private func loadEngagementStateFromFirebase(videoID: String, userID: String) async {
        let key = "\(videoID)_\(userID)"
        
        do {
            if let loadedState = try await videoEngagementService.loadEngagementState(key: key) {
                await MainActor.run {
                    engagementStates[key] = loadedState
                    print("📄 Loaded state from Firebase for \(key)")
                }
            }
        } catch {
            print("⚠️ Failed to load state from Firebase: \(error)")
        }
    }
    
    private func saveEngagementStateToFirebase(_ state: VideoEngagementState) async {
        let key = "\(state.videoID)_\(state.userID)"
        
        do {
            try await videoEngagementService.saveEngagementState(key: key, state: state)
            print("💾 Saved state to Firebase for \(key)")
        } catch {
            print("❌ Failed to save state to Firebase: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    func getHypeRatingStatus() -> HypeRatingStatus {
        let canEngage = userHypeRating >= 1.0
        
        let message: String
        let color: String
        
        if userHypeRating >= 80 {
            message = "Excellent - Engage freely"
            color = "green"
        } else if userHypeRating >= 60 {
            message = "Good - Strong engagement available"
            color = "yellow"
        } else if userHypeRating >= 40 {
            message = "Fair - Moderate engagement available"
            color = "orange"
        } else if userHypeRating >= 20 {
            message = "Low - Consider taking a break"
            color = "red"
        } else {
            message = "Critical - Wait for regeneration"
            color = "red"
        }
        
        return HypeRatingStatus(
            canEngage: canEngage,
            currentPercent: userHypeRating,
            message: message,
            color: color
        )
    }
    
    func isCurrentlyProcessing(videoID: String, userID: String) -> Bool {
        return isProcessingEngagement
    }
    
    func getCurrentMilestone(videoID: String, userID: String) -> TapMilestone? {
        return nil
    }
    
    func clearMilestone(videoID: String, userID: String) {
        // No-op
    }
    
    func setProcessing(videoID: String, userID: String, isProcessing: Bool) {
        self.isProcessingEngagement = isProcessing
    }
    
    // MARK: - Preload & Cleanup
    
    /// Batch preload engagement states to reduce individual Firebase reads
    /// Caching note: This batches concurrent reads via TaskGroup. Consider adding
    /// a dedup check to skip videoIDs already cached in engagementStates.
    func preloadEngagementStates(videoIDs: [String], userID: String) async {
        // 🆕 Dedup: skip already-cached states to avoid redundant Firebase reads
        let uncachedIDs = videoIDs.filter { engagementStates["\($0)_\(userID)"] == nil }
        
        guard !uncachedIDs.isEmpty else {
            print("✅ Preload: All \(videoIDs.count) states already cached")
            return
        }
        
        print("📦 Preloading \(uncachedIDs.count) engagement states (\(videoIDs.count - uncachedIDs.count) cached)")
        
        await withTaskGroup(of: Void.self) { group in
            for videoID in uncachedIDs {
                group.addTask {
                    await self.loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
                }
            }
        }
        
        print("✅ Preloading complete")
    }
    
    /// 🆕 Auto-cleanup: evict stale engagement states from memory cache
    /// Prevents unbounded memory growth in long sessions
    func clearOldStates() {
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour
        
        let keysToRemove = engagementStates.compactMap { key, state in
            state.lastEngagementAt < cutoffTime ? key : nil
        }
        
        for key in keysToRemove {
            engagementStates.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            print("🧹 Cleared \(keysToRemove.count) old engagement states from cache")
        }
    }
    
    /// 🆕 Start periodic cache cleanup timer
    private func startCacheCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.clearOldStates()
            }
        }
    }
    
    // MARK: - Passive Discovery Signals
    
    func isCreatorSuppressedInDiscovery(_ creatorID: String) -> Bool {
        return !DiscoveryEngagementTracker.shared.shouldShowCreator(creatorID)
    }
    
    func discoveryWeightForCreator(_ creatorID: String) -> Double {
        return DiscoveryEngagementTracker.shared.discoveryWeight(for: creatorID)
    }
}

// MARK: - Hype Rating Status

struct HypeRatingStatus {
    let canEngage: Bool
    let currentPercent: Double
    let message: String
    let color: String
}
