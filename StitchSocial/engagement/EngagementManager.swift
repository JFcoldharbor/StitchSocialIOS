//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager
//  Dependencies: VideoEngagementService, VideoService, UserService, NotificationService
//  Features: Progressive tapping, hype rating management, INSTANT ENGAGEMENTS, Push Notifications
//  UPDATED: Self-engagement restriction - only founders can engage with their own content
//  UPDATED: Added NotificationService integration for hype/cool notifications
//  UPDATED: Added 60-second grace period with side-switching and long-press removal
//

import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Engagement Side Enum


// MARK: - Engagement Manager

@MainActor
class EngagementManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let videoEngagementService: VideoEngagementService
    private let userService: UserService
    private let notificationService: NotificationService
    
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
        
        print("🎯 ENGAGEMENT MANAGER: Initialized with instant engagements, notifications, and grace period")
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
    
    // MARK: - Process Hype (instant engagement with grace period)
    
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
        
        // 🆕 CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .cool && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from cool to hype after grace period")
        }
        
        // 🆕 IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .cool && state.isWithinGracePeriod {
            print("🔄 SWITCHING: Cool → Hype (within grace period)")
            let originalCools = state.coolEngagements
            state.coolEngagements = 0
            state.hypeEngagements = 0
            state.totalCloutGiven = 0
            
            // Update video counts to remove cools
            do {
                let video = try await videoService.getVideo(id: videoID)
                let newCoolCount = max(0, video.coolCount - originalCools)
                try await videoService.updateVideoEngagement(
                    videoID: videoID,
                    hypeCount: video.hypeCount,
                    coolCount: newCoolCount,
                    viewCount: video.viewCount,
                    temperature: video.temperature,
                    lastEngagementAt: Date()
                )
                print("✅ SWITCHING: Removed \(originalCools) cools")
            } catch {
                print("⚠️ SWITCHING: Failed to update video counts: \(error)")
            }
        }
        
        // 🆕 SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
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
        
        // UPDATE VIDEO IN FIREBASE - fetch, increment, update
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
            let newHypeCount = video.hypeCount + visualHypeIncrement
            
            try await videoService.updateVideoEngagement(
                videoID: videoID,
                hypeCount: newHypeCount,
                coolCount: video.coolCount,
                viewCount: video.viewCount,
                temperature: video.temperature,
                lastEngagementAt: Date()
            )
        } catch {
            print("❌ Failed to update video: \(error)")
            throw error
        }
        
        print("🔥 HYPE: +\(visualHypeIncrement) hypes, +\(cloutAwarded) clout")
        
        // SEND NOTIFICATION TO VIDEO CREATOR
        if let creatorID = creatorID, creatorID != userID {
            Task {
                do {
                    try await notificationService.sendEngagementNotification(
                        to: creatorID,
                        videoID: videoID,
                        engagementType: "hype",
                        videoTitle: video.title
                    )
                    print("✅ HYPE NOTIFICATION: Sent to \(creatorID)")
                } catch {
                    print("⚠️ HYPE NOTIFICATION: Failed to send - \(error.localizedDescription)")
                }
            }
        }
        
        // Post notification
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
    }
    
    // MARK: - Process Cool (instant engagement with grace period)
    
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
        
        // 🆕 CHECK GRACE PERIOD IF TRYING TO SWITCH SIDES
        if state.currentSide == .hype && !state.isWithinGracePeriod {
            throw StitchError.validationError("Cannot switch from hype to cool after grace period")
        }
        
        // 🆕 IF SWITCHING DURING GRACE PERIOD - RESET
        if state.currentSide == .hype && state.isWithinGracePeriod {
            print("🔄 SWITCHING: Hype → Cool (within grace period)")
            let originalHypes = state.hypeEngagements
            let tierMultiplier = EngagementConfig.getVisualHypeMultiplier(for: userTier)
            let hypeDecrement = originalHypes * tierMultiplier
            
            state.hypeEngagements = 0
            state.coolEngagements = 0
            state.totalCloutGiven = 0
            
            // Update video counts to remove hypes
            do {
                let video = try await videoService.getVideo(id: videoID)
                let newHypeCount = max(0, video.hypeCount - hypeDecrement)
                try await videoService.updateVideoEngagement(
                    videoID: videoID,
                    hypeCount: newHypeCount,
                    coolCount: video.coolCount,
                    viewCount: video.viewCount,
                    temperature: video.temperature,
                    lastEngagementAt: Date()
                )
                print("✅ SWITCHING: Removed \(originalHypes) hypes (\(hypeDecrement) visual)")
            } catch {
                print("⚠️ SWITCHING: Failed to update video counts: \(error)")
            }
        }
        
        // 🆕 SET FIRST ENGAGEMENT TIMESTAMP IF FIRST TAP
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
        let tapNumber = state.coolEngagements
        let cloutPenalty = EngagementCalculator.calculateCoolPenalty()
        
        // Record clout (negative)
        state.recordCloutAwarded(cloutPenalty, isHype: false)
        engagementStates["\(videoID)_\(userID)"] = state
        await saveEngagementStateToFirebase(state)
        
        // UPDATE VIDEO IN FIREBASE - fetch, increment, update
        let video: CoreVideoMetadata
        do {
            video = try await videoService.getVideo(id: videoID)
            let newCoolCount = video.coolCount + visualCoolIncrement
            
            try await videoService.updateVideoEngagement(
                videoID: videoID,
                hypeCount: video.hypeCount,
                coolCount: newCoolCount,
                viewCount: video.viewCount,
                temperature: video.temperature,
                lastEngagementAt: Date()
            )
        } catch {
            print("❌ Failed to update video: \(error)")
            throw error
        }
        
        print("❄️ COOL: +\(visualCoolIncrement) cool, \(cloutPenalty) clout")
        
        // SEND NOTIFICATION TO VIDEO CREATOR
        if let creatorID = creatorID, creatorID != userID {
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
                    print("⚠️ COOL NOTIFICATION: Failed to send - \(error.localizedDescription)")
                }
            }
        }
        
        // Post notification
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
    }
    
    // MARK: - 🆕 Remove All Engagement (Long Press)
    
    func removeAllEngagement(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        print("🗑️ REMOVE ALL: Attempting to remove engagement")
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Check if within grace period
        guard state.isWithinGracePeriod else {
            print("❌ REMOVE ALL: Grace period expired")
            throw StitchError.validationError("Cannot remove engagement after grace period")
        }
        
        print("✅ REMOVE ALL: Within grace period, proceeding...")
        
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
        
        // Update video counts in Firebase
        do {
            let video = try await videoService.getVideo(id: videoID)
            
            let newHypeCount = max(0, video.hypeCount - hypeDecrement)
            let newCoolCount = max(0, video.coolCount - coolDecrement)
            
            try await videoService.updateVideoEngagement(
                videoID: videoID,
                hypeCount: newHypeCount,
                coolCount: newCoolCount,
                viewCount: video.viewCount,
                temperature: video.temperature,
                lastEngagementAt: Date()
            )
            
            print("✅ REMOVE ALL: Removed \(originalHypes) hypes (\(hypeDecrement) visual) and \(originalCools) cools")
            
            // Post notification
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
    
    func preloadEngagementStates(videoIDs: [String], userID: String) async {
        print("📦 Preloading \(videoIDs.count) engagement states")
        
        await withTaskGroup(of: Void.self) { group in
            for videoID in videoIDs {
                group.addTask {
                    await self.loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
                }
            }
        }
        
        print("✅ Preloading complete")
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
            print("🧹 Cleared \(keysToRemove.count) old states")
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
