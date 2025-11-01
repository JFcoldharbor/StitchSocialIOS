//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Main Engagement Processing Manager WITH FIREBASE PERSISTENCE
//  Dependencies: VideoEngagementService (Layer 4), VideoService (Layer 4), UserService (Layer 4)
//  Features: Progressive tapping, hype rating management, notification integration, FIREBASE PERSISTENCE
//  FIXED: Added NotificationCenter posts to trigger UI updates after engagement
//

import Foundation
import SwiftUI
import FirebaseAuth

/// Simple video engagement data for UI display
struct VideoEngagement: Codable, Identifiable {
    let id: String
    let videoID: String
    let creatorID: String
    var hypeCount: Int
    var coolCount: Int
    var shareCount: Int
    var replyCount: Int
    var viewCount: Int
    var lastEngagementAt: Date
    
    init(videoID: String, creatorID: String, hypeCount: Int = 0, coolCount: Int = 0, shareCount: Int = 0, replyCount: Int = 0, viewCount: Int = 0, lastEngagementAt: Date = Date()) {
        self.id = videoID
        self.videoID = videoID
        self.creatorID = creatorID
        self.hypeCount = hypeCount
        self.coolCount = coolCount
        self.shareCount = shareCount
        self.replyCount = replyCount
        self.viewCount = viewCount
        self.lastEngagementAt = lastEngagementAt
    }
    
    /// Total engagement count
    var totalEngagements: Int {
        return hypeCount + coolCount
    }
    
    /// Engagement ratio (hype vs total)
    var engagementRatio: Double {
        let total = totalEngagements
        return total > 0 ? Double(hypeCount) / Double(total) : 0.5
    }
}

/// Hype rating status for UI
struct HypeRatingStatus {
    let canEngage: Bool
    let currentPercent: Double
    let message: String
    let color: String
}

/// Main engagement processing manager WITH FIREBASE PERSISTENCE
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
        
        // Create VideoEngagementService if not provided
        if let providedService = videoEngagementService {
            self.videoEngagementService = providedService
        } else {
            self.videoEngagementService = VideoEngagementService(
                videoService: videoService,
                userService: userService
            )
        }
        
        print("🎯 ENGAGEMENT MANAGER: Initialized with VideoEngagementService + Firebase persistence")
    }
    
    // MARK: - Public Interface
    
    /// Get or create engagement state for video/user pair WITH FIREBASE LOADING
    func getEngagementState(videoID: String, userID: String) -> VideoEngagementState {
        let key = "\(videoID)_\(userID)"
        
        if let existingState = engagementStates[key] {
            return existingState
        }
        
        // Try to load from Firebase in background
        Task {
            await loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
        }
        
        // Return new state for immediate use
        let newState = VideoEngagementState(videoID: videoID, userID: userID)
        engagementStates[key] = newState
        return newState
    }
    
    /// Load engagement state from Firebase
    private func loadEngagementStateFromFirebase(videoID: String, userID: String) async {
        let key = "\(videoID)_\(userID)"
        
        do {
            if let loadedState = try await videoEngagementService.loadEngagementState(key: key) {
                await MainActor.run {
                    engagementStates[key] = loadedState
                    print("🔄 ENGAGEMENT MANAGER: Loaded state from Firebase for \(key)")
                }
            }
        } catch {
            print("⚠️ ENGAGEMENT MANAGER: Failed to load state from Firebase for \(key): \(error)")
        }
    }
    
    /// Save engagement state to Firebase
    private func saveEngagementStateToFirebase(_ state: VideoEngagementState) async {
        let key = "\(state.videoID)_\(state.userID)"
        
        do {
            try await videoEngagementService.saveEngagementState(key: key, state: state)
            print("💾 ENGAGEMENT MANAGER: Saved state to Firebase for \(key)")
        } catch {
            print("❌ ENGAGEMENT MANAGER: Failed to save state to Firebase for \(key): \(error)")
        }
    }
    
    /// Process hype engagement - returns true if successful WITH FIREBASE PERSISTENCE
    func processHype(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        // Check hype rating
        let cost = EngagementCalculator.calculateHypeRatingCost(tier: userTier)
        guard EngagementCalculator.canAffordEngagement(currentHypeRating: userHypeRating, cost: cost) else {
            throw StitchError.validationError("Insufficient hype rating")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        // Get engagement state (will load from Firebase if needed)
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Process tap
        let wasComplete = state.addHypeTap()
        
        // Update local state
        engagementStates["\(videoID)_\(userID)"] = state
        
        // ALWAYS SAVE STATE TO FIREBASE (for persistence)
        await saveEngagementStateToFirebase(state)
        
        if wasComplete {
            // Engagement complete - deduct hype rating
            userHypeRating = EngagementCalculator.applyHypeRatingCost(currentRating: userHypeRating, cost: cost)
            
            // Use VideoEngagementService to complete engagement
            // This handles: video update, clout award, milestone detection, and notifications
            let result = try await videoEngagementService.processProgressiveTap(
                videoID: videoID,
                userID: userID,
                engagementType: .hype,
                userTier: userTier
            )
            
            // Mark engagement complete and save again
            state.completeHypeEngagement()
            engagementStates["\(videoID)_\(userID)"] = state
            await saveEngagementStateToFirebase(state)
            
            print("🔥 ENGAGEMENT MANAGER: Hype engagement completed and persisted")
            print("🔥 Result: \(result.message)")
            
            // ✅ FIXED: Post notification to trigger UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
        }
        
        print("🔥 ENGAGEMENT MANAGER: Hype tap progress saved to Firebase")
        return false // Still tapping
    }
    
    /// Process cool engagement - returns true if successful WITH FIREBASE PERSISTENCE
    func processCool(videoID: String, userID: String, userTier: UserTier) async throws -> Bool {
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        isProcessingEngagement = true
        defer { isProcessingEngagement = false }
        
        lastEngagementTime[videoID] = Date()
        
        // Get engagement state (will load from Firebase if needed)
        var state = getEngagementState(videoID: videoID, userID: userID)
        
        // Process tap
        let wasComplete = state.addCoolTap()
        
        // Update local state
        engagementStates["\(videoID)_\(userID)"] = state
        
        // ALWAYS SAVE STATE TO FIREBASE (for persistence)
        await saveEngagementStateToFirebase(state)
        
        if wasComplete {
            // Use VideoEngagementService to complete engagement
            // This handles: video update, clout award, milestone detection, and notifications
            let result = try await videoEngagementService.processProgressiveTap(
                videoID: videoID,
                userID: userID,
                engagementType: .cool,
                userTier: userTier
            )
            
            // Mark engagement complete and save again
            state.completeCoolEngagement()
            engagementStates["\(videoID)_\(userID)"] = state
            await saveEngagementStateToFirebase(state)
            
            print("❄️ ENGAGEMENT MANAGER: Cool engagement completed and persisted")
            print("❄️ Result: \(result.message)")
            
            // ✅ FIXED: Post notification to trigger UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("VideoEngagementUpdated"),
                object: nil,
                userInfo: ["videoID": videoID]
            )
            
            return true
        }
        
        print("❄️ ENGAGEMENT MANAGER: Cool tap progress saved to Firebase")
        return false // Still tapping
    }
    
    /// Get hype rating status for UI
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
    
    /// Check if currently processing engagement
    func isCurrentlyProcessing(videoID: String, userID: String) -> Bool {
        return isProcessingEngagement
    }
    
    /// Get current milestone for UI display
    func getCurrentMilestone(videoID: String, userID: String) -> TapMilestone? {
        let state = getEngagementState(videoID: videoID, userID: userID)
        let progress = state.hypeProgress
        return EngagementCalculator.detectMilestone(progress: progress)
    }
    
    /// Clear milestone display
    func clearMilestone(videoID: String, userID: String) {
        // No-op for now - milestones are calculated dynamically
    }
    
    /// Set processing state
    func setProcessing(videoID: String, userID: String, isProcessing: Bool) {
        self.isProcessingEngagement = isProcessing
    }
    
    // MARK: - Preload States for Performance
    
    /// Preload engagement states for multiple videos (for feed performance)
    func preloadEngagementStates(videoIDs: [String], userID: String) async {
        print("📦 ENGAGEMENT MANAGER: Preloading \(videoIDs.count) engagement states")
        
        await withTaskGroup(of: Void.self) { group in
            for videoID in videoIDs {
                group.addTask {
                    await self.loadEngagementStateFromFirebase(videoID: videoID, userID: userID)
                }
            }
        }
        
        print("✅ ENGAGEMENT MANAGER: Preloading complete")
    }
    
    /// Clear old engagement states (memory management)
    func clearOldStates() {
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        let keysToRemove = engagementStates.compactMap { key, state in
            state.lastEngagementAt < cutoffTime ? key : nil
        }
        
        for key in keysToRemove {
            engagementStates.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            print("🧹 ENGAGEMENT MANAGER: Cleared \(keysToRemove.count) old states")
        }
    }
}
