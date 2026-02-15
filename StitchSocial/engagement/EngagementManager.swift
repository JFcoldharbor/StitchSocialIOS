//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager
//  UPDATED: Server-side validation via Cloud Function (stitchnoti_processEngagement)
//  - Client NO LONGER writes hypeCount/coolCount directly to Firestore
//  - Cloud Function validates: auth, self-engagement, caps, cooldown, grace period
//  - Function returns updated state → client caches locally (no extra read)
//  - Optimistic UI: buttons respond instantly, server confirms async
//  CACHING: Local engagementStates dict updated from server response.
//  Auto-cleanup timer evicts stale entries every 5 min.
//  Preload dedup skips already-cached states.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
class EngagementManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let videoEngagementService: VideoEngagementService
    private let userService: UserService
    private let notificationService: NotificationService
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    /// 🆕 Cloud Functions reference — all engagement writes go through here
    private let functions = Functions.functions()
    
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
    
    // MARK: - Cache Cleanup Timer
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
        
        startCacheCleanupTimer()
        print("🎯 ENGAGEMENT MANAGER: Server-validated mode + auto-cache cleanup")
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    func getEngagementState(videoID: String, userID: String) -> VideoEngagementState {
        let key = "\(videoID)_\(userID)"
        
        if let existingState = engagementStates[key] {
            return existingState
        }
        
        // Load from server dedup doc (new path: videos/{id}/engagements/{uid})
        Task {
            await loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
        }
        
        let newState = VideoEngagementState(videoID: videoID, userID: userID)
        engagementStates[key] = newState
        return newState
    }
    
    // MARK: - Self-Engagement Validation (client-side quick check)
    
    private func canSelfEngage(userID: String, creatorID: String, userTier: UserTier) -> Bool {
        if userID != creatorID { return true }
        return userTier == .founder || userTier == .coFounder
    }
    
    // MARK: - 🆕 Process Hype (via Cloud Function)
    // Client does optimistic UI update, server validates and confirms.
    // Server returns updated state → client syncs local cache.
    // NO direct Firestore writes to videos/{id}.hypeCount
    
    func processHype(videoID: String, userID: String, userTier: UserTier, creatorID: String? = nil, isBurst: Bool = false) async throws -> Bool {
        
        // Quick client-side checks (avoid unnecessary function calls)
        if let creatorID = creatorID {
            guard canSelfEngage(userID: userID, creatorID: creatorID, userTier: userTier) else {
                throw StitchError.validationError("You can't hype your own content")
            }
        }
        
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        let state = getEngagementState(videoID: videoID, userID: userID)
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        if state.hasHitCloutCap(for: userTier) {
            throw StitchError.validationError("Clout cap reached for this video")
        }
        
        // Check hype rating locally (burst costs more)
        let cost = EngagementCalculator.calculateHypeRatingCost(tier: userTier, isBurst: isBurst)
        guard HypeRatingService.shared.canAfford(cost) else {
            throw StitchError.validationError("Insufficient hype rating" + (isBurst ? " for burst" : ""))
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        // Deduct hype rating optimistically (will restore if server rejects)
        HypeRatingService.shared.deductRating(cost)
        
        // 🆕 Call Cloud Function instead of direct Firestore write
        do {
            let result = try await callProcessEngagement(
                videoID: videoID,
                creatorID: creatorID,
                engagementType: "hype",
                userTier: userTier,
                isBurst: isBurst
            )
            
            // Update local state from server response (no extra read needed)
            updateLocalStateFromServer(videoID: videoID, userID: userID, serverState: result)
            
            let mode = isBurst ? "BURST" : "regular"
            let visualIncrement = result["visualIncrement"] as? Int ?? 1
            let cloutAwarded = result["cloutAwarded"] as? Int ?? 0
            print("🔥 HYPE (\(mode)): +\(visualIncrement) hypes, +\(cloutAwarded) clout [SERVER VALIDATED]")
            
            // Post UI update notification
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            // Hype regen for creator (non-blocking)
            if let creatorID = creatorID, creatorID != userID {
                Task {
                    await HypeRatingService.shared.queueEngagementRegen(
                        source: .receivedHype,
                        amount: HypeRegenSource.receivedHype.baseRegenAmount
                    )
                }
            }
            
            return true
            
        } catch {
            // Server rejected — restore hype rating
            HypeRatingService.shared.restoreRating(cost)
            print("❌ HYPE REJECTED BY SERVER: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Process Cool (via Cloud Function)
    
    func processCool(videoID: String, userID: String, userTier: UserTier, creatorID: String? = nil) async throws -> Bool {
        
        if let creatorID = creatorID {
            guard canSelfEngage(userID: userID, creatorID: creatorID, userTier: userTier) else {
                throw StitchError.validationError("You can't cool your own content")
            }
        }
        
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        let state = getEngagementState(videoID: videoID, userID: userID)
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        // 🆕 Call Cloud Function
        do {
            let result = try await callProcessEngagement(
                videoID: videoID,
                creatorID: creatorID,
                engagementType: "cool",
                userTier: userTier,
                isBurst: false
            )
            
            updateLocalStateFromServer(videoID: videoID, userID: userID, serverState: result)
            
            print("❄️ COOL: +1 cool [SERVER VALIDATED]")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
            
        } catch {
            print("❌ COOL REJECTED BY SERVER: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - 🆕 Remove All Engagement (via Cloud Function)
    
    func removeAllEngagement(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        print("🗑️ REMOVE ALL: Calling server...")
        
        let state = getEngagementState(videoID: videoID, userID: userID)
        guard state.isWithinGracePeriod else {
            throw StitchError.validationError("Cannot remove engagement after grace period")
        }
        
        do {
            let result = try await functions.httpsCallable("stitchnoti_removeEngagement").call([
                "videoID": videoID
            ])
            
            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool, success else {
                throw StitchError.validationError("Server rejected removal")
            }
            
            // Reset local state
            let key = "\(videoID)_\(userID)"
            var resetState = VideoEngagementState(videoID: videoID, userID: userID)
            resetState.lastEngagementAt = Date()
            engagementStates[key] = resetState
            
            let removedHypes = data["removedHypes"] as? Int ?? 0
            let removedCools = data["removedCools"] as? Int ?? 0
            print("✅ REMOVE ALL: Removed \(removedHypes) hypes, \(removedCools) cools [SERVER VALIDATED]")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
            
        } catch {
            print("❌ REMOVE ALL REJECTED: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - 🆕 Cloud Function Caller
    
    /// Calls stitchnoti_processEngagement Cloud Function
    /// Returns the server response dict with updated state
    private func callProcessEngagement(
        videoID: String,
        creatorID: String?,
        engagementType: String,
        userTier: UserTier,
        isBurst: Bool
    ) async throws -> [String: Any] {
        
        var payload: [String: Any] = [
            "videoID": videoID,
            "engagementType": engagementType,
            "userTier": userTier.rawValue,
            "isBurst": isBurst,
        ]
        
        if let creatorID = creatorID {
            payload["creatorID"] = creatorID
        }
        
        let result = try await functions.httpsCallable("stitchnoti_processEngagement").call(payload)
        
        guard let data = result.data as? [String: Any],
              let success = data["success"] as? Bool, success else {
            let message = (result.data as? [String: Any])?["message"] as? String ?? "Unknown server error"
            throw StitchError.validationError(message)
        }
        
        return data
    }
    
    /// Updates local engagement state cache from server response
    /// No extra Firestore read needed — server returns everything
    private func updateLocalStateFromServer(videoID: String, userID: String, serverState: [String: Any]) {
        let key = "\(videoID)_\(userID)"
        
        guard let stateDict = serverState["state"] as? [String: Any] else { return }
        
        var state = engagementStates[key] ?? VideoEngagementState(videoID: videoID, userID: userID)
        
        state.totalEngagements = stateDict["totalEngagements"] as? Int ?? state.totalEngagements
        state.hypeEngagements = stateDict["hypeEngagements"] as? Int ?? state.hypeEngagements
        state.coolEngagements = stateDict["coolEngagements"] as? Int ?? state.coolEngagements
        state.totalCloutGiven = stateDict["totalCloutGiven"] as? Int ?? state.totalCloutGiven
        state.totalVisualHypesGiven = stateDict["totalVisualHypesGiven"] as? Int ?? state.totalVisualHypesGiven
        state.lastEngagementAt = Date()
        
        engagementStates[key] = state
    }
    
    // MARK: - Firebase Persistence (reads engagement dedup doc)
    
    /// 🆕 Reads from videos/{videoID}/engagements/{userID} (new dedup path)
    private func loadEngagementStateFromFirebase(videoID: String, userID: String) async {
        let key = "\(videoID)_\(userID)"
        
        // Dedup: skip if already cached
        if engagementStates[key] != nil { return }
        
        do {
            let doc = try await db.collection("videos").document(videoID)
                .collection("engagements").document(userID).getDocument()
            
            guard doc.exists, let data = doc.data() else { return }
            
            var state = VideoEngagementState(videoID: videoID, userID: userID)
            state.totalEngagements = data["totalEngagements"] as? Int ?? 0
            state.hypeEngagements = data["hypeEngagements"] as? Int ?? 0
            state.coolEngagements = data["coolEngagements"] as? Int ?? 0
            state.totalCloutGiven = data["totalCloutGiven"] as? Int ?? 0
            state.totalVisualHypesGiven = data["totalVisualHypesGiven"] as? Int ?? 0
            
            if let ts = data["firstEngagementAt"] as? Timestamp {
                state.firstEngagementAt = ts.dateValue()
            }
            if let ts = data["lastEngagementAt"] as? Timestamp {
                state.lastEngagementAt = ts.dateValue()
            }
            
            await MainActor.run {
                engagementStates[key] = state
                print("📄 Loaded engagement state from dedup doc for \(key)")
            }
        } catch {
            print("⚠️ Failed to load engagement state: \(error)")
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
    
    func clearMilestone(videoID: String, userID: String) {}
    
    func setProcessing(videoID: String, userID: String, isProcessing: Bool) {
        self.isProcessingEngagement = isProcessing
    }
    
    // MARK: - Preload & Cleanup
    
    /// Preload engagement states for a batch of videos
    /// 🆕 Reads from dedup docs, dedup skips already-cached states
    func preloadEngagementStates(videoIDs: [String], userID: String) async {
        let uncachedIDs = videoIDs.filter { engagementStates["\($0)_\(userID)"] == nil }
        
        guard !uncachedIDs.isEmpty else {
            print("📦 Preload: All \(videoIDs.count) states already cached")
            return
        }
        
        print("📦 Preloading \(uncachedIDs.count) engagement states (skipped \(videoIDs.count - uncachedIDs.count) cached)")
        
        await withTaskGroup(of: Void.self) { group in
            for videoID in uncachedIDs {
                group.addTask {
                    await self.loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
                }
            }
        }
        
        print("✅ Preloading complete")
    }
    
    /// Auto-cleanup: evict stale entries (>1hr old) every 5 minutes
    private func startCacheCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.clearOldStates()
            }
        }
    }
    
    func clearOldStates() {
        let cutoffTime = Date().addingTimeInterval(-3600)
        
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
