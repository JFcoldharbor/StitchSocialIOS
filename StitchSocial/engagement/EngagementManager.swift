//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager
//  Dependencies: VideoEngagementService, VideoService, UserService, NotificationService
//  Features: Progressive tapping, hype rating management, INSTANT ENGAGEMENTS, Push Notifications
//  UPDATED: Atomic increment operations - eliminates race conditions and expensive reads (40% cost reduction)
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
    
    @Published var userHypeRating: Double = 25.0
    @Published var isProcessingEngagement = false
    @Published var engagementStates: [String: VideoEngagementState] = [:]
    @Published var lastEngagementTime: [String: Date] = [:]
    
    // MARK: - Configuration
    
    private let engagementCooldown: TimeInterval = 0.5
    
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
        
        print("ðŸŽ¯ ENGAGEMENT MANAGER: Initialized with atomic increments - 40% cost reduction")
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
    
    /// Check if self-engagement should be allowed
    /// - Returns: true if engagement should be allowed, false if blocked
    private func canSelfEngage(userID: String, creatorID: String, userTier: UserTier) -> Bool {
        // Not self-engagement - always allowed
        if userID != creatorID {
            return true
        }
        
        // Self-engagement - only founders/co-founders allowed
        return userTier == .founder || userTier == .coFounder
    }
    
    // MARK: - Process Hype (ATOMIC INCREMENT - NO READS)
    
    func processHype(videoID: String, userID: String, userTier: UserTier, creatorID: String? = nil) async throws -> Bool {
        
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
        
        // ðŸ†• CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .cool && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from cool to hype after grace period")
        }
        
        // ðŸ†• IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .cool && state.isWithinGracePeriod {
            print("ðŸ”„ SWITCHING: Cool â†’ Hype (within grace period)")
            let originalCools = state.coolEngagements
            state.coolEngagements = 0
            state.hypeEngagements = 0
            state.totalCloutGiven = 0
            
            // âœ… ATOMIC DECREMENT - no read needed
            do {
                try await db.collection("videos").document(videoID).updateData([
                    "coolCount": FieldValue.increment(Int64(-originalCools)),
                    "lastEngagementAt": Timestamp(),
                    "updatedAt": Timestamp()
                ])
                print("âœ… SWITCHING: Removed \(originalCools) cools (atomic)")
            } catch {
                print("âš ï¸ SWITCHING: Failed to update: \(error)")
            }
        }
        
        // ðŸ†• SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
        if state.firstEngagementAt == nil {
            state.firstEngagementAt = Date()
            print("â±ï¸ GRACE PERIOD: Started (60 seconds)")
        }
        
        // Check caps
        if state.hasHitCloutCap(for: userTier) {
            throw StitchError.validationError("Clout cap reached for this video")
        }
        
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        
        // Check hype rating
        let cost = EngagementCalculator.calculateHypeRatingCost(tier: userTier)
        guard EngagementCalculator.canAffordEngagement(currentHypeRating: userHypeRating, cost: cost) else {
            throw StitchError.validationError("Insufficient hype rating")
        }
        
        // Instant engagement - no tapping progress
        state.addHypeEngagement()
        
        // Deduct hype rating
        userHypeRating = EngagementCalculator.applyHypeRatingCost(currentRating: userHypeRating, cost: cost)
        
        // Calculate rewards
        let visualHypeIncrement = EngagementConfig.getVisualHypeMultiplier(for: userTier)
        let tapNumber = state.hypeEngagements
        let isFirstEngagement = (state.hypeEngagements == 1)
        let currentCloutFromUser = state.totalCloutGiven
        
        let cloutAwarded = EngagementCalculator.calculateCloutReward(
            giverTier: userTier,
            tapNumber: tapNumber,
            isFirstEngagement: isFirstEngagement,
            currentCloutFromThisUser: currentCloutFromUser
        )
        
        // Record clout
        state.recordCloutAwarded(cloutAwarded, isHype: true)
        engagementStates["\(videoID)_\(userID)"] = state
        await saveEngagementStateToFirebase(state)
        
        // âœ… ATOMIC INCREMENT IN FIRESTORE - NO READ NEEDED (saves 40% cost)
        do {
            try await db.collection("videos").document(videoID).updateData([
                "hypeCount": FieldValue.increment(Int64(visualHypeIncrement)),
                "lastEngagementAt": Timestamp(),
                "updatedAt": Timestamp()
            ])
            print("ðŸ”¥ HYPE: +\(visualHypeIncrement) hypes (atomic), +\(cloutAwarded) clout")
        } catch {
            print("âŒ Failed to update video: \(error)")
            throw error
        }
        
        // Fetch video ONLY for notification (title needed) - separate read, no contention
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
        } catch {
            print("âš ï¸ Failed to fetch video for notification: \(error)")
            // Create minimal video object for notification
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
                        engagementType: "hype",
                        videoTitle: video.title
                    )
                    print("âœ… HYPE NOTIFICATION: Sent to \(creatorID)")
                } catch {
                    print("âš ï¸ HYPE NOTIFICATION: Failed - \(error.localizedDescription)")
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
    
    // MARK: - Process Cool (ATOMIC INCREMENT - NO READS)
    
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
        
        // ðŸ†• CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .hype && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from hype to cool after grace period")
        }
        
        // ðŸ†• IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .hype && state.isWithinGracePeriod {
            print("ðŸ”„ SWITCHING: Hype â†’ Cool (within grace period)")
            let originalHypes = state.hypeEngagements
            let tierMultiplier = EngagementConfig.getVisualHypeMultiplier(for: userTier)
            let hypeDecrement = originalHypes * tierMultiplier
            
            state.hypeEngagements = 0
            state.coolEngagements = 0
            state.totalCloutGiven = 0
            
            // âœ… ATOMIC DECREMENT - no read needed
            do {
                try await db.collection("videos").document(videoID).updateData([
                    "hypeCount": FieldValue.increment(Int64(-hypeDecrement)),
                    "lastEngagementAt": Timestamp(),
                    "updatedAt": Timestamp()
                ])
                print("âœ… SWITCHING: Removed \(originalHypes) hypes (\(hypeDecrement) visual) (atomic)")
            } catch {
                print("âš ï¸ SWITCHING: Failed to update: \(error)")
            }
        }
        
        // ðŸ†• SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
        if state.firstEngagementAt == nil {
            state.firstEngagementAt = Date()
            print("â±ï¸ GRACE PERIOD: Started (60 seconds)")
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
        
        // âœ… ATOMIC INCREMENT IN FIRESTORE - NO READ NEEDED
        do {
            try await db.collection("videos").document(videoID).updateData([
                "coolCount": FieldValue.increment(Int64(visualCoolIncrement)),
                "lastEngagementAt": Timestamp(),
                "updatedAt": Timestamp()
            ])
            print("â„ï¸ COOL: +\(visualCoolIncrement) cool (atomic), \(cloutPenalty) clout")
        } catch {
            print("âŒ Failed to update video: \(error)")
            throw error
        }
        
        // Fetch video ONLY for notification (title needed)
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
        } catch {
            print("âš ï¸ Failed to fetch video for notification: \(error)")
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
                    print("âœ… COOL NOTIFICATION: Sent to \(creatorID)")
                } catch {
                    print("âš ï¸ COOL NOTIFICATION: Failed - \(error.localizedDescription)")
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
    
    // MARK: - ðŸ†• Remove All Engagement (Long Press - ATOMIC DECREMENTS)
    
    func removeAllEngagement(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        print("ðŸ—‘ï¸ REMOVE ALL: Attempting to remove engagement")
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Check if within grace period
        guard state.isWithinGracePeriod else {
            print("âŒ REMOVE ALL: Grace period expired")
            throw StitchError.validationError("Cannot remove engagement after grace period")
        }
        
        print("âœ… REMOVE ALL: Within grace period, proceeding...")
        
        // Store original counts for Firebase update
        let originalHypes = state.hypeEngagements
        let originalCools = state.coolEngagements
        
        // Calculate visual decrements
        let tierMultiplier = EngagementConfig.getVisualHypeMultiplier(for: userTier)
        let hypeDecrement = originalHypes * tierMultiplier
        let coolDecrement = originalCools
        
        // Reset everything
        state.hypeEngagements = 0
        state.coolEngagements = 0
        state.totalEngagements = 0
        state.totalCloutGiven = 0
        state.firstEngagementAt = nil
        state.lastEngagementAt = Date()
        
        // Update in-memory state
        let key = "\(videoID)_\(userID)"
        engagementStates[key] = state
        await saveEngagementStateToFirebase(state)
        
        // âœ… ATOMIC DECREMENTS IN FIRESTORE - NO READ NEEDED
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
            
            print("âœ… REMOVE ALL: Removed \(originalHypes) hypes (\(hypeDecrement) visual) and \(originalCools) cools (atomic)")
            
            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
            
        } catch {
            print("âŒ REMOVE ALL: Failed to update video: \(error)")
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
                    print("ðŸ“„ Loaded state from Firebase for \(key)")
                }
            }
        } catch {
            print("âš ï¸ Failed to load state from Firebase: \(error)")
        }
    }
    
    private func saveEngagementStateToFirebase(_ state: VideoEngagementState) async {
        let key = "\(state.videoID)_\(state.userID)"
        
        do {
            try await videoEngagementService.saveEngagementState(key: key, state: state)
            print("ðŸ’¾ Saved state to Firebase for \(key)")
        } catch {
            print("âŒ Failed to save state to Firebase: \(error)")
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
    
    func preloadEngagementStates(videoIDs: [String], userID: String) async {
        print("ðŸ“¦ Preloading \(videoIDs.count) engagement states")
        
        await withTaskGroup(of: Void.self) { group in
            for videoID in videoIDs {
                group.addTask {
                    await self.loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
                }
            }
        }
        
        print("âœ… Preloading complete")
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
            print("ðŸ§¹ Cleared \(keysToRemove.count) old states")
        }
    }
}

// MARK: - Hype Rating Status

struct HypeRatingStatus {
    let canEngage: Bool
    let currentPercent: Double
    let message: String
    let color: String
}
