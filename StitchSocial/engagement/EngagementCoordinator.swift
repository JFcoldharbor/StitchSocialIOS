//
//  EngagementCoordinator.swift
//  CleanBeta
//
//  Layer 6: Coordination - Complete Engagement Workflow Orchestration
//  Dependencies: VideoService, EngagementCalculator, NotificationService
//  Orchestrates: Tap UI → Calculations → Database → Rewards → Visual Feedback
//

import Foundation
import SwiftUI

/// Video engagement structure for coordination layer
struct VideoEngagement {
    let videoID: String
    let creatorID: String
    let hypeCount: Int
    let coolCount: Int
    let shareCount: Int
    let replyCount: Int
    let viewCount: Int
    let lastEngagementAt: Date
}

/// Orchestrates complete engagement workflow with progressive tapping and visual feedback
/// Coordinates between UI interactions, calculations, database updates, and reward processing
@MainActor
class EngagementCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let notificationService: NotificationService
    
    // MARK: - Progressive Tapping State
    
    @Published var currentTaps: [String: Int] = [:] // videoID -> tap count
    @Published var requiredTaps: [String: Int] = [:] // videoID -> required taps
    @Published var tapProgress: [String: Double] = [:] // videoID -> progress (0.0-1.0)
    @Published var isProcessingTap: [String: Bool] = [:] // videoID -> processing state
    
    // MARK: - Visual Feedback State
    
    @Published var showingMilestone: [String: TapMilestone] = [:] // videoID -> milestone
    @Published var showingReward: [String: EngagementRewardType] = [:] // videoID -> reward
    @Published var activeAnimations: [String: AnimationType] = [:] // videoID -> animation
    
    // MARK: - Analytics & Monitoring
    
    @Published var engagementStats = EngagementStats()
    @Published var recentInteractions: [EngagementInteraction] = []
    @Published var sessionMetrics = SessionMetrics()
    
    // MARK: - Configuration
    
    private let maxRecentInteractions = 50
    private let tapCooldownMS = 100 // Minimum time between taps
    private let maxTapsPerSecond = 20 // Anti-spam protection
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        notificationService: NotificationService
    ) {
        self.videoService = videoService
        self.notificationService = notificationService
        
        print("🔥 ENGAGEMENT COORDINATOR: Initialized - Ready for progressive tapping workflow")
    }
    
    // MARK: - Primary Engagement Workflow
    
    /// Complete engagement workflow: Tap → Calculate → Update → Reward → Feedback
    func processEngagement(
        videoID: String,
        engagementType: InteractionType,
        userID: String,
        userTier: UserTier
    ) async throws {
        
        print("🔥 ENGAGEMENT: Processing \(engagementType.rawValue) for video \(videoID)")
        
        // Step 1: Handle progressive tapping for hype interactions
        if engagementType == .hype {
            let tapResult = await handleProgressiveTapping(videoID: videoID, userID: userID)
            
            // If tapping not complete, just update UI and return
            if !tapResult.isComplete {
                await updateTapProgress(videoID: videoID, result: tapResult)
                return
            }
            
            // Tapping complete - proceed with engagement
            await completeTapSequence(videoID: videoID, result: tapResult)
        }
        
        // Step 2: Get current video engagement state
        let currentEngagement = await getCurrentEngagementState(videoID: videoID)
        
        // Step 3: Calculate engagement metrics
        let calculations = calculateEngagementMetrics(
            engagementType: engagementType,
            userTier: userTier,
            videoID: videoID,
            currentEngagement: currentEngagement
        )
        
        // Step 4: Update database with real persistence
        try await updateEngagementDatabase(
            videoID: videoID,
            engagementType: engagementType,
            userID: userID,
            calculations: calculations
        )
        
        // Step 5: Process rewards and notifications
        await processEngagementRewards(
            videoID: videoID,
            engagementType: engagementType,
            userID: userID,
            calculations: calculations
        )
        
        // Step 6: Update analytics
        await updateAnalytics(
            videoID: videoID,
            engagementType: engagementType,
            calculations: calculations
        )
        
        print("✅ ENGAGEMENT: Complete workflow finished for \(engagementType.rawValue)")
    }
    
    // MARK: - Progressive Tapping System
    
    /// Handle progressive tapping workflow with visual feedback
    private func handleProgressiveTapping(videoID: String, userID: String) async -> TapResult {
        
        // Initialize tapping state if needed
        if currentTaps[videoID] == nil {
            let requiredTapsCount = EngagementCalculator.calculateProgressiveTapRequirement(currentTaps: 0)
            currentTaps[videoID] = 0
            requiredTaps[videoID] = requiredTapsCount
            tapProgress[videoID] = 0.0
        }
        
        // Anti-spam protection
        if isProcessingTap[videoID] == true {
            return TapResult(isComplete: false, milestone: nil, tapsRemaining: requiredTaps[videoID] ?? 0)
        }
        
        isProcessingTap[videoID] = true
        defer { isProcessingTap[videoID] = false }
        
        // Increment tap count
        let currentTapCount = (currentTaps[videoID] ?? 0) + 1
        let requiredTapCount = requiredTaps[videoID] ?? 2
        
        currentTaps[videoID] = currentTapCount
        
        // Calculate progress
        let progress = EngagementCalculator.calculateTapProgress(
            currentTaps: currentTapCount,
            targetTaps: requiredTapCount
        )
        tapProgress[videoID] = progress
        
        // Check for milestones
        let milestone = EngagementCalculator.calculateTapMilestone(
            currentTaps: currentTapCount,
            requiredTaps: requiredTapCount
        )
        
        // Update visual feedback
        if let milestone = milestone {
            showingMilestone[videoID] = milestone
            activeAnimations[videoID] = .tapMilestone
            
            // Send milestone notification
            do {
                try await notificationService.sendProgressiveTapMilestone(
                    to: userID,
                    videoID: videoID,
                    currentTaps: currentTapCount,
                    requiredTaps: requiredTapCount,
                    milestone: milestone
                )
            } catch {
                print("⚠️ ENGAGEMENT: Failed to send milestone notification - \(error)")
            }
            
            print("🎯 MILESTONE: \(milestone.rawValue) reached - \(currentTapCount)/\(requiredTapCount) taps")
        }
        
        // Check completion
        let isComplete = currentTapCount >= requiredTapCount
        if isComplete {
            // Reset for next progressive requirement
            let nextRequired = EngagementCalculator.calculateProgressiveTapRequirement(currentTaps: currentTapCount)
            requiredTaps[videoID] = nextRequired
            currentTaps[videoID] = 0
            tapProgress[videoID] = 0.0
        }
        
        print("👆 TAP PROGRESS: \(currentTapCount)/\(requiredTapCount) (\(Int(progress * 100))%) - Complete: \(isComplete)")
        
        return TapResult(
            isComplete: isComplete,
            milestone: milestone,
            tapsRemaining: max(0, requiredTapCount - currentTapCount)
        )
    }
    
    /// Update tap progress UI with smooth animations
    private func updateTapProgress(videoID: String, result: TapResult) async {
        
        // Trigger haptic feedback
        triggerHapticFeedback(for: result)
        
        // Animate progress indicators
        activeAnimations[videoID] = .tapProgress
        
        // Clear milestone after display
        if result.milestone != nil {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            showingMilestone[videoID] = nil
        }
        
        // Clear animation
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        activeAnimations[videoID] = nil
    }
    
    /// Complete tap sequence with celebration
    private func completeTapSequence(videoID: String, result: TapResult) async {
        
        // Show completion animation
        activeAnimations[videoID] = .tapComplete
        
        // Trigger success haptic
        triggerSuccessHaptic()
        
        // Clear completion animation
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        activeAnimations[videoID] = nil
        
        print("🎉 TAP COMPLETE: Progressive tapping sequence finished for video \(videoID)")
    }
    
    // MARK: - Database Integration
    
    /// Get current engagement state from database
    private func getCurrentEngagementState(videoID: String) async -> VideoEngagement {
        
        // Try to get current video from VideoService
        if let currentVideo = try? await videoService.getVideo(id: videoID) {
            return VideoEngagement(
                videoID: videoID,
                creatorID: currentVideo.creatorID,
                hypeCount: currentVideo.hypeCount,
                coolCount: currentVideo.coolCount,
                shareCount: currentVideo.shareCount,
                replyCount: currentVideo.replyCount,
                viewCount: currentVideo.viewCount,
                lastEngagementAt: currentVideo.lastEngagementAt ?? Date()
            )
        } else {
            // Fallback to empty state
            print("⚠️ ENGAGEMENT: Could not load current video state for \(videoID), using empty state")
            return VideoEngagement.empty(videoID: videoID)
        }
    }
    
    /// Calculate all engagement metrics for the interaction
    private func calculateEngagementMetrics(
        engagementType: InteractionType,
        userTier: UserTier,
        videoID: String,
        currentEngagement: VideoEngagement
    ) -> EngagementCalculations {
        
        // Calculate new metrics
        let cloutGain = EngagementCalculator.calculateCloutGain(
            engagementType: engagementType,
            giverTier: userTier
        )
        
        let newHypeCount = engagementType == .hype ? currentEngagement.hypeCount + 1 : currentEngagement.hypeCount
        let newCoolCount = engagementType == .cool ? currentEngagement.coolCount + 1 : currentEngagement.coolCount
        let newViewCount = engagementType == .view ? currentEngagement.viewCount + 1 : currentEngagement.viewCount
        
        let newTemperature = EngagementCalculator.calculateTemperature(
            hypeCount: newHypeCount,
            coolCount: newCoolCount
        )
        
        let newEngagementRatio = EngagementCalculator.calculateEngagementRatio(
            hype: newHypeCount,
            cool: newCoolCount,
            views: newViewCount
        )
        
        let hypeScore = EngagementCalculator.calculateHypeScore(
            taps: newHypeCount,
            requiredTaps: requiredTaps[videoID] ?? 2,
            giverTier: userTier
        )
        
        return EngagementCalculations(
            cloutGain: cloutGain,
            newHypeCount: newHypeCount,
            newCoolCount: newCoolCount,
            newViewCount: newViewCount,
            newTemperature: newTemperature,
            newEngagementRatio: newEngagementRatio,
            hypeScore: hypeScore
        )
    }
    
    /// Update engagement database with real VideoService integration
    private func updateEngagementDatabase(
        videoID: String,
        engagementType: InteractionType,
        userID: String,
        calculations: EngagementCalculations
    ) async throws {
        
        print("📊 DATABASE: Updating engagement for video \(videoID)")
        print("📊 DATABASE: Hype: \(calculations.newHypeCount), Cool: \(calculations.newCoolCount)")
        
        do {
            // Update video engagement in database using VideoService
            try await videoService.updateVideoEngagement(
                videoID: videoID,
                hypeCount: calculations.newHypeCount,
                coolCount: calculations.newCoolCount,
                viewCount: calculations.newViewCount,
                temperature: calculations.newTemperature,
                lastEngagementAt: Date()
            )
            
            // Record user's engagement interaction
            try await videoService.recordUserInteraction(
                videoID: videoID,
                userID: userID,
                interactionType: engagementType,
                watchTime: 0
            )

            
            print("✅ DATABASE: Successfully updated engagement for video \(videoID)")
            
        } catch {
            print("❌ DATABASE: Failed to update engagement - \(error.localizedDescription)")
            throw StitchError.processingError("Failed to update engagement: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rewards & Notifications
    
    /// Process engagement rewards and send notifications
    private func processEngagementRewards(
        videoID: String,
        engagementType: InteractionType,
        userID: String,
        calculations: EngagementCalculations
    ) async {
        
        // Check for reward triggers
        var rewardType: EngagementRewardType?
        
        // First hype reward
        if engagementType == .hype && calculations.newHypeCount == 1 {
            rewardType = .firstHype
        }
        
        // Viral video reward
        if calculations.newHypeCount >= 10000 {
            rewardType = .viralVideo
        }
        
        // Send reward notification if applicable
        if let reward = rewardType {
            showingReward[videoID] = reward
            activeAnimations[videoID] = .reward
            
            // Send engagement reward notification
            do {
                try await notificationService.sendEngagementRewardNotification(
                    to: userID,
                    type: reward,
                    details: EngagementRewardDetails(
                        senderID: userID,
                        engagementCount: calculations.newHypeCount + calculations.newCoolCount,
                        streakCount: 1,
                        rewardAmount: Double(Int(calculations.cloutGain))  // Convert to Int instead of Double
                    )
                )
            } catch {
                print("⚠️ ENGAGEMENT: Failed to send reward notification - \(error)")
            }
            
            print("🎁 REWARD: \(reward.rawValue) earned for video \(videoID)")
            print("🎁 REWARD: Engagement count: \(calculations.newHypeCount + calculations.newCoolCount)")
            print("🎁 REWARD: Clout gained: \(calculations.cloutGain)")
            
            // Clear reward display
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            showingReward[videoID] = nil
            activeAnimations[videoID] = nil
        }
    }
    
    // MARK: - Analytics Updates
    
    /// Update analytics tracking
    private func updateAnalytics(
        videoID: String,
        engagementType: InteractionType,
        calculations: EngagementCalculations
    ) async {
        
        // Record interaction for analytics
        let interaction = EngagementInteraction(
            id: UUID().uuidString,
            videoID: videoID,
            type: engagementType,
            timestamp: Date(),
            cloutGain: calculations.cloutGain,
            hypeScore: calculations.hypeScore
        )
        
        recentInteractions.insert(interaction, at: 0)
        if recentInteractions.count > maxRecentInteractions {
            recentInteractions.removeLast()
        }
        
        // Update session metrics
        sessionMetrics.totalInteractions += 1
        sessionMetrics.totalCloutGained += calculations.cloutGain
        
        switch engagementType {
        case .hype:
            sessionMetrics.hypesGiven += 1
        case .cool:
            sessionMetrics.coolsGiven += 1
        case .view:
            sessionMetrics.videosViewed += 1
        case .reply:
            sessionMetrics.repliesCreated += 1
        case .share:
            sessionMetrics.sharesCompleted += 1
        }
        
        // Update engagement stats
        engagementStats.averageEngagementRatio = calculateAverageEngagementRatio()
        engagementStats.mostActiveVideoID = findMostActiveVideo()
        
        print("📈 ANALYTICS: Updated session metrics and engagement stats")
    }
    
    // MARK: - Helper Methods
    
    /// Trigger haptic feedback based on tap result
    private func triggerHapticFeedback(for result: TapResult) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        if result.milestone != nil {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        }
    }
    
    /// Trigger success haptic for completed interactions
    private func triggerSuccessHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
    
    /// Calculate average engagement ratio across recent interactions
    private func calculateAverageEngagementRatio() -> Double {
        // TODO: Implement when CachingService is available
        // For now, return a reasonable default
        return 0.75
    }
    
    /// Find most active video by interaction count
    private func findMostActiveVideo() -> String? {
        let videoCounts = recentInteractions.reduce(into: [:]) { counts, interaction in
            counts[interaction.videoID, default: 0] += 1
        }
        
        return videoCounts.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - Public Interface
    
    /// Reset progressive tapping state for video
    func resetTappingState(videoID: String) {
        currentTaps[videoID] = nil
        requiredTaps[videoID] = nil
        tapProgress[videoID] = nil
        isProcessingTap[videoID] = nil
        showingMilestone[videoID] = nil
        showingReward[videoID] = nil
        activeAnimations[videoID] = nil
        
        print("🔄 RESET: Cleared tapping state for video \(videoID)")
    }
    
    /// Get current tap progress for video
    func getTapProgress(videoID: String) -> (current: Int, required: Int, progress: Double) {
        return (
            current: currentTaps[videoID] ?? 0,
            required: requiredTaps[videoID] ?? 2,
            progress: tapProgress[videoID] ?? 0.0
        )
    }
    
    /// Check if video has active engagement animation
    func hasActiveAnimation(videoID: String) -> AnimationType? {
        return activeAnimations[videoID]
    }
}

// MARK: - Supporting Types

/// Result of progressive tapping interaction
struct TapResult {
    let isComplete: Bool
    let milestone: TapMilestone?
    let tapsRemaining: Int
}

/// Calculated engagement metrics
struct EngagementCalculations {
    let cloutGain: Int
    let newHypeCount: Int
    let newCoolCount: Int
    let newViewCount: Int
    let newTemperature: String
    let newEngagementRatio: Double
    let hypeScore: Double
}

/// Engagement interaction record
struct EngagementInteraction: Identifiable {
    let id: String
    let videoID: String
    let type: InteractionType
    let timestamp: Date
    let cloutGain: Int
    let hypeScore: Double
}

/// Session engagement metrics
struct SessionMetrics {
    var totalInteractions: Int = 0
    var totalCloutGained: Int = 0
    var hypesGiven: Int = 0
    var coolsGiven: Int = 0
    var videosViewed: Int = 0
    var repliesCreated: Int = 0
    var sharesCompleted: Int = 0
    var sessionStartTime: Date = Date()
    
    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }
    
    var interactionsPerMinute: Double {
        let minutes = sessionDuration / 60.0
        return minutes > 0 ? Double(totalInteractions) / minutes : 0.0
    }
}

/// Overall engagement statistics
struct EngagementStats {
    var averageEngagementRatio: Double = 0.0
    var mostActiveVideoID: String?
    var totalEngagementsToday: Int = 0
    var engagementStreak: Int = 0
    var lastEngagementDate: Date?
    
    var engagementHealth: EngagementHealth {
        if averageEngagementRatio >= 0.8 { return .excellent }
        if averageEngagementRatio >= 0.6 { return .good }
        if averageEngagementRatio >= 0.4 { return .fair }
        return .poor
    }
}

/// Animation types for visual feedback
enum AnimationType: String, CaseIterable {
    case tapProgress = "tap_progress"
    case tapMilestone = "tap_milestone"
    case tapComplete = "tap_complete"
    case reward = "reward"
    case engagementUpdate = "engagement_update"
}

/// Engagement health status
enum EngagementHealth: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    
    var emoji: String {
        switch self {
        case .excellent: return "🔥"
        case .good: return "💚"
        case .fair: return "👌"
        case .poor: return "📉"
        }
    }
}

/// Engagement data for coordination layer
struct EngagementData {
    let videoID: String
    let hypeCount: Int
    let coolCount: Int
    let viewCount: Int
    let temperature: String
    let engagementRatio: Double
    let lastEngagementAt: Date
}

// MARK: - Extensions

/// VideoEngagement extension for convenience methods
extension VideoEngagement {
    static func empty(videoID: String) -> VideoEngagement {
        return VideoEngagement(
            videoID: videoID,
            creatorID: "",
            hypeCount: 0,
            coolCount: 0,
            shareCount: 0,
            replyCount: 0,
            viewCount: 0,
            lastEngagementAt: Date()
        )
    }
}
