//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager
//  Dependencies: VideoEngagementService, VideoService, UserService
//  Features: Progressive tapping, hype rating management, INSTANT ENGAGEMENTS
//  UPDATED: Simplified to instant engagements (no progressive tapping)
//

import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Engagement Manager

@MainActor
class EngagementManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let videoEngagementService: VideoEngagementService
    private let userService: UserService
    
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
        videoEngagementService: VideoEngagementService? = nil
    ) {
        self.videoService = videoService
        self.userService = userService
        
        if let providedService = videoEngagementService {
            self.videoEngagementService = providedService
        } else {
            self.videoEngagementService = VideoEngagementService(
                videoService: videoService,
                userService: userService
            )
        }
        
        print("🎯 ENGAGEMENT MANAGER: Initialized with instant engagements")
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
    
    // MARK: - Process Hype (instant engagement)
    
    func processHype(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
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
        do {
            let video = try await videoService.getVideo(id: videoID)
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
        }
        
        print("🔥 HYPE: +\(visualHypeIncrement) hypes, +\(cloutAwarded) clout")
        
        // Post notification
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
    }
    
    // MARK: - Process Cool (instant engagement)
    
    func processCool(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Check engagement cap
        if state.hasHitEngagementCap() {
            throw StitchError.validationError("Engagement cap reached for this video")
        }
        
        // Instant engagement - no tapping progress
        state.addCoolEngagement()
        
        // Calculate rewards
        let visualCoolIncrement = 1  // Cool is always 1
        let tapNumber = state.coolEngagements
        let cloutPenalty = EngagementCalculator.calculateCoolPenalty()
        
        // Record clout (negative)
        state.recordCloutAwarded(cloutPenalty, isHype: false)
        engagementStates["\(videoID)_\(userID)"] = state
        await saveEngagementStateToFirebase(state)
        
        // UPDATE VIDEO IN FIREBASE - fetch, increment, update
        do {
            let video = try await videoService.getVideo(id: videoID)
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
        }
        
        print("❄️ COOL: +\(visualCoolIncrement) cool, \(cloutPenalty) clout")
        
        // Post notification
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            userInfo: ["videoID": videoID]
        )
        
        return true
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
        // No milestones with instant engagements
        return nil
    }
    
    func clearMilestone(videoID: String, userID: String) {
        // No-op for now
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
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
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
