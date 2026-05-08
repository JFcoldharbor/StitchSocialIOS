//
//  ReEngagementService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Re-Engagement Notification System
//  Dependencies: Firebase Functions, UserService, VideoService
//  Features: Activity-based re-engagement with 24h cooldown, TikTok/Instagram style
//  FIXED: BasicUserInfo field access, PaginatedResult iteration, StitchError type
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

@MainActor
class ReEngagementService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let functions = Functions.functions(region: "us-central1")
    private let videoService: VideoService
    private let userService: UserService
    
    // MARK: - Published State
    
    @Published var isChecking = false
    @Published var lastCheckTime: Date?
    @Published var canSendReEngagement = true
    @Published var lastReEngagementType: String?
    
    // MARK: - Configuration
    
    private let minInactiveHours: Double = 6.0
    private let cooldownHours: Double = 24.0
    private let maxReEngagementsPerWeek = 3
    
    // MARK: - Initialization
    
    init(videoService: VideoService, userService: UserService) {
        self.videoService = videoService
        self.userService = userService
        
        #if DEBUG
        print("🔄 RE-ENGAGEMENT SERVICE: Initialized")
        #endif
        #if DEBUG
        print("⏱️ Min inactive: \(minInactiveHours)h, Cooldown: \(cooldownHours)h")
        #endif
    }
    
    // MARK: - Main Check Function
    
    /// Check if user should receive re-engagement notification
    func checkReEngagement(userID: String) async throws {
        
        guard !isChecking else {
            #if DEBUG
            print("⏸️ RE-ENGAGEMENT: Already checking")
            #endif
            return
        }
        
        isChecking = true
        defer { isChecking = false }
        
        #if DEBUG
        print("🔍 RE-ENGAGEMENT: Checking for user \(userID)")
        #endif
        
        // 1. Get last active time from Firestore directly
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        guard userDoc.exists, let userData = userDoc.data() else {
            #if DEBUG
            print("❌ RE-ENGAGEMENT: User not found")
            #endif
            return
        }
        
        // Get lastActiveAt timestamp from Firestore
        let lastActive: Date
        if let timestamp = userData["lastActiveAt"] as? Timestamp {
            lastActive = timestamp.dateValue()
        } else {
            // Fallback to createdAt if lastActiveAt doesn't exist
            lastActive = (userData["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        }
        
        let inactiveHours = Date().timeIntervalSince(lastActive) / 3600
        
        #if DEBUG
        print("📊 RE-ENGAGEMENT: User inactive for \(String(format: "%.1f", inactiveHours))h")
        #endif
        
        // 2. Check if enough time passed
        guard inactiveHours >= minInactiveHours else {
            #if DEBUG
            print("⏸️ RE-ENGAGEMENT: Not enough inactivity (\(String(format: "%.1f", inactiveHours))h < \(minInactiveHours)h)")
            #endif
            return
        }
        
        // 3. Get new activity since last open
        let activity = try await getNewActivitySince(userID: userID, since: lastActive)
        
        #if DEBUG
        print("📊 RE-ENGAGEMENT: Activity Summary:")
        #endif
        #if DEBUG
        print("   • New stitches: \(activity.newStitches)")
        #endif
        #if DEBUG
        print("   • Milestone: \(activity.newMilestone?.displayName ?? "none")")
        #endif
        #if DEBUG
        print("   • Follower posts: \(activity.followerPosts)")
        #endif
        #if DEBUG
        print("   • Clout to next tier: \(activity.cloutToNextTier)")
        #endif
        
        // 4. Select notification type
        guard let notification = selectReEngagementType(
            activity: activity,
            inactiveHours: inactiveHours
        ) else {
            #if DEBUG
            print("⏸️ RE-ENGAGEMENT: No significant activity to notify about")
            #endif
            return
        }
        
        // 5. Send re-engagement
        try await sendReEngagement(userID: userID, notification: notification)
        
        lastCheckTime = Date()
        lastReEngagementType = notification.type
        #if DEBUG
        print("✅ RE-ENGAGEMENT: Check complete - sent \(notification.type)")
        #endif
    }
    
    // MARK: - Activity Detection
    
    private func getNewActivitySince(userID: String, since: Date) async throws -> UserActivity {
        
        #if DEBUG
        print("🔍 ACTIVITY: Checking activity since \(since)")
        #endif
        
        // FIX: Get user's videos returns PaginatedResult, access .items
        let userVideosResult = try await videoService.getUserVideos(userID: userID, limit: 20)
        let userVideos = userVideosResult.items
        
        var newStitches = 0
        var newMilestone: MilestoneType?
        
        // FIX: Iterate over items array instead of PaginatedResult
        for video in userVideos where video.conversationDepth == 0 {
            let children = try? await videoService.getThreadChildren(threadID: video.id)
            let newChildren = children?.filter { $0.createdAt > since } ?? []
            newStitches += newChildren.count
            
            // Check for milestone reached
            if let milestone = checkMilestoneReached(video: video, since: since) {
                newMilestone = milestone
                #if DEBUG
                print("🎯 ACTIVITY: Milestone detected - \(milestone.displayName)")
                #endif
            }
        }
        
        // Get follower activity
        let followerPosts = try await getFollowerPostsSince(userID: userID, since: since)
        
        // FIX: getUser returns optional BasicUserInfo?, unwrap before accessing
        guard let currentUser = try await userService.getUser(id: userID) else {
            throw StitchError.validationError("User not found for activity check")
        }
        
        let (remaining, nextTier) = calculateTierProximity(
            currentClout: currentUser.clout,
            currentTier: currentUser.tier
        )
        
        return UserActivity(
            newStitches: newStitches,
            newMilestone: newMilestone,
            followerPosts: followerPosts,
            cloutToNextTier: remaining,
            nextTier: nextTier
        )
    }
    
    private func getFollowerPostsSince(userID: String, since: Date) async throws -> Int {
        #if DEBUG
        print("👥 ACTIVITY: Checking follower posts since \(since)")
        #endif
        
        // Query following collection to get follower IDs
        let followingSnapshot = try await db.collection(FirebaseSchema.Collections.following)
            .whereField(FirebaseSchema.FollowingDocument.followingID, isEqualTo: userID)
            .whereField(FirebaseSchema.FollowingDocument.isActive, isEqualTo: true)
            .getDocuments()
        
        let followerIDs = followingSnapshot.documents.compactMap {
            $0.data()[FirebaseSchema.FollowingDocument.followerID] as? String
        }
        
        guard !followerIDs.isEmpty else {
            #if DEBUG
            print("👥 ACTIVITY: No followers found")
            #endif
            return 0
        }
        
        #if DEBUG
        print("👥 ACTIVITY: Found \(followerIDs.count) followers")
        #endif
        
        // Count videos from followers since timestamp
        let videosSnapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.creatorID, in: followerIDs)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThan: Timestamp(date: since))
            .getDocuments()
        
        #if DEBUG
        print("👥 ACTIVITY: \(videosSnapshot.documents.count) new follower posts")
        #endif
        return videosSnapshot.documents.count
    }
    
    private func checkMilestoneReached(video: CoreVideoMetadata, since: Date) -> MilestoneType? {
        // Check if milestone was reached after timestamp
        // Note: This is a simplified check - ideally would check milestone timestamp fields
        
        if video.hypeCount >= 15000 {
            return .viral
        } else if video.hypeCount >= 1000 {
            return .hot
        } else if video.hypeCount >= 400 {
            return .mustSee
        } else if video.hypeCount >= 10 {
            return .heatingUp
        }
        
        return nil
    }
    
    private func calculateTierProximity(currentClout: Int, currentTier: UserTier) -> (remaining: Int, nextTier: UserTier) {
        let tierThresholds: [(tier: UserTier, clout: Int)] = [
            (.rookie, 0),
            (.rising, 5000),
            (.veteran, 15000),
            (.influencer, 50000),
            (.elite, 150000)
        ]
        
        for (index, threshold) in tierThresholds.enumerated() {
            if currentTier == threshold.tier, index < tierThresholds.count - 1 {
                let nextThreshold = tierThresholds[index + 1]
                let remaining = nextThreshold.clout - currentClout
                return (remaining, nextThreshold.tier)
            }
        }
        
        return (0, currentTier)
    }
    
    // MARK: - Notification Selection
    
    private func selectReEngagementType(
        activity: UserActivity,
        inactiveHours: Double
    ) -> ReEngagementNotification? {
        
        #if DEBUG
        print("🎯 SELECTION: Choosing best re-engagement type...")
        #endif
        
        // Priority order: New stitches > Milestone > Follower posts > Tier proximity
        
        // 1. New stitches (threshold: 3+)
        if activity.newStitches >= 3 {
            #if DEBUG
            print("✅ SELECTION: New stitches (\(activity.newStitches)) - HIGH PRIORITY")
            #endif
            return .newStitches(count: activity.newStitches)
        }
        
        // 2. Milestone reached
        if let milestone = activity.newMilestone {
            #if DEBUG
            print("✅ SELECTION: Milestone (\(milestone.displayName)) - HIGH PRIORITY")
            #endif
            return .milestone(milestone)
        }
        
        // 3. Follower posts (threshold: 5+)
        if activity.followerPosts >= 5 {
            #if DEBUG
            print("✅ SELECTION: Follower activity (\(activity.followerPosts) posts)")
            #endif
            return .followerActivity(count: activity.followerPosts)
        }
        
        // 4. Tier proximity (threshold: within 100 clout)
        if activity.cloutToNextTier > 0 && activity.cloutToNextTier <= 100 {
            #if DEBUG
            print("✅ SELECTION: Tier proximity (\(activity.cloutToNextTier) clout to \(activity.nextTier.rawValue))")
            #endif
            return .tierProximity(
                remaining: activity.cloutToNextTier,
                nextTier: activity.nextTier
            )
        }
        
        #if DEBUG
        print("⏸️ SELECTION: No qualifying activity found")
        #endif
        return nil
    }
    
    // MARK: - Send Re-Engagement
    
    private func sendReEngagement(userID: String, notification: ReEngagementNotification) async throws {
        
        #if DEBUG
        print("📤 RE-ENGAGEMENT: Sending \(notification.type) to user \(userID)")
        #endif
        
        let callable = functions.httpsCallable("stitchnoti_sendReEngagement")
        
        let data: [String: Any] = [
            "userId": userID,
            "notificationType": notification.type,
            "payload": notification.payload
        ]
        
        let result = try await callable.call(data)
        
        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool else {
            // FIX: Use StitchError.validationError instead of serverError
            throw StitchError.validationError("Invalid response from re-engagement function")
        }
        
        if !success {
            if let reason = resultData["reason"] as? String, reason == "cooldown" {
                let hoursRemaining = resultData["hoursRemaining"] as? String ?? "unknown"
                #if DEBUG
                print("⏸️ RE-ENGAGEMENT: Cooldown active (\(hoursRemaining)h remaining)")
                #endif
                canSendReEngagement = false
            }
            return
        }
        
        if let notificationId = resultData["notificationId"] as? String {
            #if DEBUG
            print("✅ RE-ENGAGEMENT: Notification created - \(notificationId)")
            #endif
        }
        
        if let pushSent = resultData["pushSent"] as? Bool {
            #if DEBUG
            print("✅ RE-ENGAGEMENT: Push notification sent - \(pushSent)")
            #endif
        }
        
        #if DEBUG
        print("✅ RE-ENGAGEMENT: Sent successfully")
        #endif
    }
    
    // MARK: - Manual Check Trigger
    
    /// Manually trigger re-engagement check (for testing or background tasks)
    func manualCheck(userID: String) async {
        #if DEBUG
        print("🔄 RE-ENGAGEMENT: Manual check triggered")
        #endif
        
        do {
            try await checkReEngagement(userID: userID)
        } catch {
            #if DEBUG
            print("❌ RE-ENGAGEMENT: Manual check failed - \(error)")
            #endif
        }
    }
    
    // MARK: - Debug Information
    
    func logStatus() {
        #if DEBUG
        print("📊 RE-ENGAGEMENT STATUS:")
        #endif
        #if DEBUG
        print("   • Is checking: \(isChecking)")
        #endif
        #if DEBUG
        print("   • Last check: \(lastCheckTime?.formatted() ?? "never")")
        #endif
        #if DEBUG
        print("   • Last type: \(lastReEngagementType ?? "none")")
        #endif
        #if DEBUG
        print("   • Can send: \(canSendReEngagement)")
        #endif
        #if DEBUG
        print("   • Min inactive: \(minInactiveHours)h")
        #endif
        #if DEBUG
        print("   • Cooldown: \(cooldownHours)h")
        #endif
    }
}

// MARK: - Supporting Types

enum MilestoneType {
    case heatingUp, mustSee, hot, viral
    
    var displayName: String {
        switch self {
        case .heatingUp: return "Heating Up (10 hypes)"
        case .mustSee: return "Must See (400 hypes)"
        case .hot: return "Hot (1K hypes)"
        case .viral: return "Viral (15K hypes)"
        }
    }
    
    var emoji: String {
        switch self {
        case .heatingUp: return "🔥"
        case .mustSee: return "👀"
        case .hot: return "🌶️"
        case .viral: return "🚀"
        }
    }
}

struct UserActivity {
    let newStitches: Int
    let newMilestone: MilestoneType?
    let followerPosts: Int
    let cloutToNextTier: Int
    let nextTier: UserTier
}

enum ReEngagementNotification {
    case newStitches(count: Int)
    case milestone(MilestoneType)
    case followerActivity(count: Int)
    case tierProximity(remaining: Int, nextTier: UserTier)
    
    var type: String {
        switch self {
        case .newStitches: return "new_stitches"
        case .milestone: return "milestone"
        case .followerActivity: return "follower_activity"
        case .tierProximity: return "tier_proximity"
        }
    }
    
    var payload: [String: Any] {
        switch self {
        case .newStitches(let count):
            return ["count": count]
        case .milestone(let type):
            return ["milestoneName": type.displayName]
        case .followerActivity(let count):
            return ["count": count]
        case .tierProximity(let remaining, let nextTier):
            return [
                "remaining": remaining,
                "nextTier": nextTier.rawValue
            ]
        }
    }
    
    var title: String {
        switch self {
        case .newStitches(let count):
            return "🔥 \(count) new stitches on your thread"
        case .milestone(let type):
            return "\(type.emoji) Your video hit \(type.displayName)!"
        case .followerActivity(let count):
            return "👥 \(count) followers posted today"
        case .tierProximity(let remaining, let tier):
            return "⬆️ Just \(remaining) clout to \(tier.displayName)!"
        }
    }
}
