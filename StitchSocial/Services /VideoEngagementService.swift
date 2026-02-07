//
//  VideoEngagementService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video Engagement & Milestone Management
//  Dependencies: VideoService (video data), UserService (clout), NotificationService (notifications)
//  Features: Progressive tapping, first engagement tracking, milestone detection, notification triggering
//  UPDATED: Added videoID to all notification calls
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Handles all video engagement operations including progressive tapping, milestones, and notifications
@MainActor
class VideoEngagementService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let videoService: VideoService
    private let userService: UserService
    private let notificationService: NotificationService
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService,
        notificationService: NotificationService? = nil
    ) {
        self.videoService = videoService
        self.userService = userService
        self.notificationService = notificationService ?? NotificationService()
        
        print("Ã°Å¸Å½Â¯ VIDEO ENGAGEMENT SERVICE: Initialized with milestone tracking + notifications")
    }
    
    // MARK: - Progressive Tapping System
    
    /// Process progressive tap (main entry point for engagement)
    func processProgressiveTap(
        videoID: String,
        userID: String,
        engagementType: InteractionType,
        userTier: UserTier
    ) async throws -> ProgressiveTapResult {
        
        print("Ã°Å¸Å½Â¯ ENGAGEMENT SERVICE: Processing \(engagementType.rawValue) tap for video \(videoID)")
        
        // Get current tap progress
        let currentProgress = try await getTapProgress(videoID: videoID, userID: userID, type: engagementType)
        
        // Calculate required taps based on user's total engagements with this video
        let totalEngagements = try await getTotalEngagements(videoID: videoID, userID: userID)
        let requiredTaps = calculateProgressiveTaps(engagementNumber: totalEngagements + 1)
        
        // Update tap count
        let newTapCount = currentProgress.currentTaps + 1
        let newProgress = TapProgressState(currentTaps: newTapCount, requiredTaps: requiredTaps)
        
        // Save updated progress
        try await updateTapProgress(
            videoID: videoID,
            userID: userID,
            type: engagementType,
            currentTaps: newTapCount,
            requiredTaps: requiredTaps
        )
        
        if newProgress.isComplete {
            // Complete engagement!
            let result = try await completeEngagement(
                videoID: videoID,
                userID: userID,
                type: engagementType,
                userTier: userTier
            )
            
            // Reset tap progress for next engagement
            try await resetTapProgress(videoID: videoID, userID: userID, type: engagementType)
            
            print("Ã¢Å“â€¦ ENGAGEMENT SERVICE: \(engagementType.rawValue) engagement completed!")
            
            return ProgressiveTapResult(
                isComplete: true,
                progress: 1.0,
                milestone: .complete,
                message: "\(engagementType.rawValue.capitalized) added!",
                newVideoHypeCount: result.newHypeCount,
                newVideoCoolCount: result.newCoolCount,
                cloutAwarded: result.cloutAwarded
            )
            
        } else {
            // Still tapping...
            print("Ã°Å¸â€â€ž ENGAGEMENT SERVICE: \(engagementType.rawValue) progress: \(newTapCount)/\(requiredTaps)")
            
            return ProgressiveTapResult(
                isComplete: false,
                progress: newProgress.progress,
                milestone: newProgress.milestone,
                message: "Keep tapping... (\(newTapCount)/\(requiredTaps))",
                newVideoHypeCount: nil,
                newVideoCoolCount: nil,
                cloutAwarded: nil
            )
        }
    }
    
    // MARK: - Tap Progress Management
    
    /// Get current tap progress from tap_progress collection
    private func getTapProgress(videoID: String, userID: String, type: InteractionType) async throws -> TapProgressState {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        let document = try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).getDocument()
        
        if document.exists, let data = document.data() {
            let currentTaps = data[FirebaseSchema.TapProgressDocument.currentTaps] as? Int ?? 0
            let requiredTaps = data[FirebaseSchema.TapProgressDocument.requiredTaps] as? Int ?? 1
            return TapProgressState(currentTaps: currentTaps, requiredTaps: requiredTaps)
        } else {
            // No progress yet - determine required taps
            let totalEngagements = try await getTotalEngagements(videoID: videoID, userID: userID)
            let requiredTaps = calculateProgressiveTaps(engagementNumber: totalEngagements + 1)
            return TapProgressState(currentTaps: 0, requiredTaps: requiredTaps)
        }
    }
    
    /// Update tap count in tap_progress collection
    private func updateTapProgress(
        videoID: String,
        userID: String,
        type: InteractionType,
        currentTaps: Int,
        requiredTaps: Int
    ) async throws {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        
        let progressData: [String: Any] = [
            FirebaseSchema.TapProgressDocument.videoID: videoID,
            FirebaseSchema.TapProgressDocument.userID: userID,
            FirebaseSchema.TapProgressDocument.engagementType: type.rawValue,
            FirebaseSchema.TapProgressDocument.currentTaps: currentTaps,
            FirebaseSchema.TapProgressDocument.requiredTaps: requiredTaps,
            FirebaseSchema.TapProgressDocument.lastTapTime: Timestamp(),
            FirebaseSchema.TapProgressDocument.isCompleted: currentTaps >= requiredTaps,
            FirebaseSchema.TapProgressDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).setData(progressData, merge: true)
    }
    
    /// Reset tap progress after engagement completion
    private func resetTapProgress(videoID: String, userID: String, type: InteractionType) async throws {
        let progressID = "\(videoID)_\(userID)_\(type.rawValue)"
        try await db.collection(FirebaseSchema.Collections.tapProgress).document(progressID).delete()
    }
    
    // MARK: - Engagement Completion with Milestone Detection
    
    /// Complete engagement - award clout, update video counts, check milestones, send notifications
    private func completeEngagement(
        videoID: String,
        userID: String,
        type: InteractionType,
        userTier: UserTier
    ) async throws -> (newHypeCount: Int, newCoolCount: Int, cloutAwarded: Int) {
        
        // Get current video
        let video = try await videoService.getVideo(id: videoID)
        
        // Calculate clout reward
        let cloutAwarded = calculateCloutReward(giverTier: userTier)
        
        // Update video counts
        let newHypeCount = type == .hype ? video.hypeCount + 1 : video.hypeCount
        let newCoolCount = type == .cool ? video.coolCount + 1 : video.coolCount
        
        // Check if this is the FIRST engagement of this type
        let isFirstHype = type == .hype && video.hypeCount == 0
        let isFirstCool = type == .cool && video.coolCount == 0
        
        // Check if hitting a milestone
        let milestone = FirebaseSchema.ValidationRules.checkMilestoneReached(hypeCount: newHypeCount)
        
        // Update shards + milestone tracking
        try await updateVideoWithMilestone(
            videoID: videoID,
            engagementType: type,
            isFirstHype: isFirstHype,
            isFirstCool: isFirstCool,
            milestone: milestone
        )
        
        // Award clout to creator
        try await userService.awardClout(userID: video.creatorID, amount: cloutAwarded)
        
        // Create interaction record
        try await recordInteraction(
            videoID: videoID,
            userID: userID,
            type: type,
            cloutAwarded: cloutAwarded
        )
        
        // SEND NOTIFICATIONS
        await sendEngagementNotifications(
            videoID: videoID,
            videoTitle: video.title,
            creatorID: video.creatorID,
            engagerUserID: userID,
            engagementType: type,
            isFirstHype: isFirstHype,
            isFirstCool: isFirstCool,
            milestone: milestone,
            newHypeCount: newHypeCount
        )
        
        print("Ã¢Å“â€¦ ENGAGEMENT SERVICE: Completed \(type.rawValue) for \(videoID)")
        return (newHypeCount, newCoolCount, cloutAwarded)
    }
    
    // MARK: - Milestone Tracking
    
    /// Update video with milestone flags
    private func updateVideoWithMilestone(
        videoID: String,
        engagementType: InteractionType,
        isFirstHype: Bool,
        isFirstCool: Bool,
        milestone: Int?
    ) async throws {
        
        // 1. Write count increment to shard (scalable)
        if engagementType == .hype {
            try await videoService.incrementHypeShard(videoID: videoID, amount: 1)
        } else {
            try await videoService.incrementCoolShard(videoID: videoID, amount: 1)
        }
        
        // 2. Write milestone flags to video doc (infrequent, no contention)
        var updateData: [String: Any] = [
            FirebaseSchema.VideoDocument.lastEngagementAt: Timestamp(),
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ]
        
        // 2a. Recalculate quality and discoverability scores
        // Fetch fresh video data for accurate calculation
        if let freshVideo = try? await videoService.getVideo(id: videoID) {
            let (newQuality, newDiscoverability) = ContentScoreCalculator.recalculateScores(for: freshVideo)
            updateData[FirebaseSchema.VideoDocument.qualityScore] = newQuality
            updateData[FirebaseSchema.VideoDocument.discoverabilityScore] = newDiscoverability
            print("📊 SCORE UPDATE: \(videoID) quality=\(newQuality), disc=\(String(format: "%.2f", newDiscoverability))")
        }
        
        // Track first engagements
        if isFirstHype {
            updateData[FirebaseSchema.VideoDocument.firstHypeReceived] = true
            print("MILESTONE: First hype received on video \(videoID)")
        }
        
        if isFirstCool {
            updateData[FirebaseSchema.VideoDocument.firstCoolReceived] = true
            print("MILESTONE: First cool received on video \(videoID)")
        }
        
        // Track milestone achievements
        if let milestone = milestone {
            switch milestone {
            case 10:
                updateData[FirebaseSchema.VideoDocument.milestone10Reached] = true
                updateData[FirebaseSchema.VideoDocument.milestone10ReachedAt] = Timestamp()
                print("MILESTONE: Video \(videoID) reached 10 hypes (Heating Up)")
            case 400:
                updateData[FirebaseSchema.VideoDocument.milestone400Reached] = true
                updateData[FirebaseSchema.VideoDocument.milestone400ReachedAt] = Timestamp()
                print("MILESTONE: Video \(videoID) reached 400 hypes (Must See)")
            case 1000:
                updateData[FirebaseSchema.VideoDocument.milestone1000Reached] = true
                updateData[FirebaseSchema.VideoDocument.milestone1000ReachedAt] = Timestamp()
                print("MILESTONE: Video \(videoID) reached 1000 hypes (Hot)")
            case 15000:
                updateData[FirebaseSchema.VideoDocument.milestone15000Reached] = true
                updateData[FirebaseSchema.VideoDocument.milestone15000ReachedAt] = Timestamp()
                print("MILESTONE: Video \(videoID) reached 15000 hypes (Viral)")
            default:
                break
            }
        }
        
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData(updateData)
    }
    
    // MARK: - Notification Sending
    
    /// Send all relevant notifications for this engagement
    private func sendEngagementNotifications(
        videoID: String,
        videoTitle: String,
        creatorID: String,
        engagerUserID: String,
        engagementType: InteractionType,
        isFirstHype: Bool,
        isFirstCool: Bool,
        milestone: Int?,
        newHypeCount: Int
    ) async {
        
        // Don't notify if user is engaging with their own video
        guard creatorID != engagerUserID else { return }
        
        // Get engager username for notifications
        guard let engagerUser = try? await userService.getUser(id: engagerUserID) else { return }
        
        // 1. CHECK COOLDOWN (30 seconds between notifications to same creator)
        let canNotify = await checkNotificationCooldown(
            engagerID: engagerUserID,
            creatorID: creatorID
        )
        
        if canNotify {
            // Send engagement notification (hype or cool)
            do {
                if engagementType == .hype {
                    // Ã¢Å“â€¦ FIXED: Added videoID parameter
                    try await notificationService.sendEngagementNotification(
                        to: creatorID,
                        videoID: videoID,              // Ã¢Å“â€¦ ADDED
                        engagementType: "hype",
                        videoTitle: videoTitle
                    )
                    print("Ã¢Å“â€¦ NOTIFICATION: Hype sent to creator \(creatorID)")
                } else {
                    // Ã¢Å“â€¦ FIXED: Added videoID parameter
                    try await notificationService.sendEngagementNotification(
                        to: creatorID,
                        videoID: videoID,              // Ã¢Å“â€¦ ADDED
                        engagementType: "cool",
                        videoTitle: videoTitle
                    )
                    print("Ã¢Å“â€¦ NOTIFICATION: Cool sent to creator \(creatorID)")
                }
                
                // Update cooldown timestamp
                await updateNotificationCooldown(
                    engagerID: engagerUserID,
                    creatorID: creatorID
                )
                
            } catch {
                print("Ã¢Å¡Â Ã¯Â¸Â NOTIFICATION: Failed to send engagement - \(error)")
            }
        } else {
            print("Ã¢ÂÂ±Ã¯Â¸Â NOTIFICATION: Cooldown active, skipping")
        }
        
        // 2. MILESTONE NOTIFICATIONS (always send regardless of cooldown)
        if let milestone = milestone {
            await sendMilestoneNotification(
                milestone: milestone,
                videoID: videoID,
                videoTitle: videoTitle,
                creatorID: creatorID,
                currentHypeCount: newHypeCount
            )
        }
    }
    
    // MARK: - Notification Cooldown Management
    
    /// Check if enough time has passed since last notification
    private func checkNotificationCooldown(
        engagerID: String,
        creatorID: String
    ) async -> Bool {
        let cooldownKey = "\(engagerID)_\(creatorID)"
        
        do {
            let doc = try await db.collection("notification_cooldowns")
                .document(cooldownKey)
                .getDocument()
            
            if doc.exists,
               let lastNotification = doc.data()?["lastNotificationAt"] as? Timestamp {
                let timeSince = Date().timeIntervalSince(lastNotification.dateValue())
                return timeSince >= 30.0 // 30 second cooldown
            }
            
            return true // No previous notification, allow
            
        } catch {
            print("Ã¢Å¡Â Ã¯Â¸Â COOLDOWN CHECK: Failed - \(error)")
            return true // Default to allowing notification
        }
    }
    
    /// Update cooldown timestamp after sending notification
    private func updateNotificationCooldown(
        engagerID: String,
        creatorID: String
    ) async {
        let cooldownKey = "\(engagerID)_\(creatorID)"
        
        do {
            try await db.collection("notification_cooldowns")
                .document(cooldownKey)
                .setData([
                    "engagerID": engagerID,
                    "creatorID": creatorID,
                    "lastNotificationAt": Timestamp(),
                    "updatedAt": Timestamp()
                ])
            
            print("Ã¢ÂÂ±Ã¯Â¸Â COOLDOWN: Updated for \(cooldownKey)")
            
        } catch {
            print("Ã¢Å¡Â Ã¯Â¸Â COOLDOWN UPDATE: Failed - \(error)")
        }
    }
    
    /// Send milestone notification with appropriate audience
    private func sendMilestoneNotification(
        milestone: Int,
        videoID: String,
        videoTitle: String,
        creatorID: String,
        currentHypeCount: Int
    ) async {
        
        do {
            // Determine recipients based on milestone
            var followerIDs: [String] = []
            var engagerIDs: [String] = []
            
            if milestone == 1000 {
                // Hot milestone - notify creator + all followers
                followerIDs = try await getCreatorFollowers(creatorID: creatorID)
                print("Ã°Å¸Å’Â¶Ã¯Â¸Â MILESTONE: Notifying creator + \(followerIDs.count) followers")
                
            } else if milestone == 15000 {
                // Viral milestone - notify creator + all engagers
                engagerIDs = try await getAllEngagers(videoID: videoID)
                print("Ã°Å¸Å¡â‚¬ MILESTONE: Notifying creator + \(engagerIDs.count) engagers")
            }
            
            // Send milestone notification
            try await notificationService.sendMilestoneNotification(
                milestone: milestone,
                videoID: videoID,
                videoTitle: videoTitle,
                creatorID: creatorID,
                followerIDs: followerIDs,
                engagerIDs: engagerIDs
            )
            
            print("Ã¢Å“â€¦ MILESTONE NOTIFICATION: Sent for \(milestone) hypes")
            
        } catch {
            print("Ã¢Å¡Â Ã¯Â¸Â MILESTONE NOTIFICATION: Failed - \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get total engagements by user for this video
    private func getTotalEngagements(videoID: String, userID: String) async throws -> Int {
        let hypeID = "\(videoID)_\(userID)_hype"
        let coolID = "\(videoID)_\(userID)_cool"
        
        let hypeDoc = try await db.collection(FirebaseSchema.Collections.interactions).document(hypeID).getDocument()
        let coolDoc = try await db.collection(FirebaseSchema.Collections.interactions).document(coolID).getDocument()
        
        let hypeCount = hypeDoc.exists ? 1 : 0
        let coolCount = coolDoc.exists ? 1 : 0
        
        return hypeCount + coolCount
    }
    
    /// Calculate progressive taps needed
    private func calculateProgressiveTaps(engagementNumber: Int) -> Int {
        if engagementNumber <= 4 {
            return 1  // Instant for first 4
        }
        
        // 5th = 2, 6th = 4, 7th = 8, etc.
        let progressiveIndex = engagementNumber - 5
        let requirement = 2 * Int(pow(2.0, Double(progressiveIndex)))
        return min(requirement, 256)  // Cap at 256
    }
    
    /// Calculate clout reward based on giver tier
    private func calculateCloutReward(giverTier: UserTier) -> Int {
        switch giverTier {
        case .rookie: return 1
        case .rising: return 3
        case .veteran: return 10
        case .influencer: return 25
        case .ambassador: return 35
        case .elite: return 50
        case .partner: return 100
        case .legendary: return 250
        case .topCreator: return 500
        case .founder, .coFounder: return 1000
        }
    }
    
    /// Record interaction in Firebase
    private func recordInteraction(
        videoID: String,
        userID: String,
        type: InteractionType,
        cloutAwarded: Int
    ) async throws {
        let interactionID = FirebaseSchema.DocumentIDPatterns.generateInteractionID(
            videoID: videoID,
            userID: userID,
            type: type.rawValue
        )
        
        let interactionData: [String: Any] = [
            FirebaseSchema.InteractionDocument.userID: userID,
            FirebaseSchema.InteractionDocument.videoID: videoID,
            FirebaseSchema.InteractionDocument.engagementType: type.rawValue,
            FirebaseSchema.InteractionDocument.timestamp: Timestamp(),
            FirebaseSchema.InteractionDocument.isCompleted: true,
            FirebaseSchema.InteractionDocument.impactValue: cloutAwarded
        ]
        
        try await db.collection(FirebaseSchema.Collections.interactions)
            .document(interactionID)
            .setData(interactionData)
    }
    
    /// Get all follower IDs for a creator
    private func getCreatorFollowers(creatorID: String) async throws -> [String] {
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(creatorID)
            .collection("followers")
            .getDocuments()
        
        return snapshot.documents.compactMap { $0.data()["userID"] as? String }
    }
    
    /// Get all users who have engaged with this video
    private func getAllEngagers(videoID: String) async throws -> [String] {
        let snapshot = try await db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .getDocuments()
        
        let engagers = Set(snapshot.documents.compactMap { $0.data()[FirebaseSchema.InteractionDocument.userID] as? String })
        return Array(engagers)
    }
    
    // MARK: - Legacy Support Methods
    
    /// Save engagement state to Firebase (for EngagementCoordinator compatibility)
    func saveEngagementState(key: String, state: VideoEngagementState) async throws {
        let data: [String: Any] = [
            "videoID": state.videoID,
            "userID": state.userID,
            "totalEngagements": state.totalEngagements,
            "hypeEngagements": state.hypeEngagements,
            "coolEngagements": state.coolEngagements,
            "totalCloutGiven": state.totalCloutGiven,
            "lastEngagementAt": Timestamp(date: state.lastEngagementAt),
            "createdAt": Timestamp(date: state.createdAt)
        ]
        
        try await db.collection("engagement_states").document(key).setData(data)
    }
    
    /// Load engagement state from Firebase (for EngagementCoordinator compatibility)
    func loadEngagementState(key: String) async throws -> VideoEngagementState? {
        let document = try await db.collection("engagement_states").document(key).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        guard let videoID = data["videoID"] as? String,
              let userID = data["userID"] as? String,
              let totalEngagements = data["totalEngagements"] as? Int,
              let hypeEngagements = data["hypeEngagements"] as? Int,
              let coolEngagements = data["coolEngagements"] as? Int,
              let lastEngagementTimestamp = data["lastEngagementAt"] as? Timestamp else {
            return nil
        }
        
        // Get optional fields
        let totalCloutGiven = data["totalCloutGiven"] as? Int ?? 0
        
        // Get createdAt timestamp or fallback to lastEngagementAt
        let createdAtTimestamp = data["createdAt"] as? Timestamp ?? lastEngagementTimestamp
        
        // Create state with all properties
        var state = VideoEngagementState(videoID: videoID, userID: userID, createdAt: createdAtTimestamp.dateValue())
        state.totalEngagements = totalEngagements
        state.hypeEngagements = hypeEngagements
        state.coolEngagements = coolEngagements
        state.totalCloutGiven = totalCloutGiven
        state.lastEngagementAt = lastEngagementTimestamp.dateValue()
        
        return state
    }
}

// MARK: - Supporting Types

/// Tap progress state
struct TapProgressState {
    let currentTaps: Int
    let requiredTaps: Int
    
    var progress: Double {
        guard requiredTaps > 0 else { return 0.0 }
        return min(1.0, Double(currentTaps) / Double(requiredTaps))
    }
    
    var isComplete: Bool {
        return currentTaps >= requiredTaps
    }
    
    var milestone: TapMilestone? {
        if progress >= 1.0 { return .complete }
        if progress >= 0.75 { return .threeQuarters }
        if progress >= 0.5 { return .half }
        if progress >= 0.25 { return .quarter }
        return nil
    }
}

/// Progressive tap result
struct ProgressiveTapResult {
    let isComplete: Bool
    let progress: Double
    let milestone: TapMilestone?
    let message: String
    let newVideoHypeCount: Int?
    let newVideoCoolCount: Int?
    let cloutAwarded: Int?
}

// MARK: - Type Aliases
// Using types defined in Layer 1 (UserTier.swift) and Layer 2 (EngagementTypes.swift)
// InteractionType: defined in UserTier.swift (Layer 1)
// TapMilestone: defined in EngagementTypes.swift (Layer 2)
