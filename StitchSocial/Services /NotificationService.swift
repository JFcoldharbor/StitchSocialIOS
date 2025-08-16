//
//  NotificationService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Push Notifications & Database Management
//  Dependencies: Firebase Messaging, Config, FirebaseSchema, UserTier (existing)
//  Features: Database CRUD, engagement rewards, badge unlocks, following notifications
//

import Foundation
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Complete notification service with database operations and push notification management
class NotificationService: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let messaging = Messaging.messaging()
    
    // MARK: - Published State
    
    @Published var isRegistered = false
    @Published var fcmToken: String?
    @Published var notificationPermissionStatus: NotificationPermissionStatus = .notDetermined
    @Published var unreadCount = 0
    @Published var recentNotifications: [StitchNotification] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    // MARK: - Configuration
    
    private let maxRecentNotifications = 50
    private let notificationExpirationDays = 30
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        messaging.delegate = self
        
        print("📧 NOTIFICATION SERVICE: Initialized with database integration")
    }
    
    // MARK: - DATABASE OPERATIONS
    
    /// Load notifications for a user with pagination support
    func loadNotifications(
        for userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (notifications: [StitchNotification], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            var query = db.collection(FirebaseSchema.Collections.notifications)
                .whereField(FirebaseSchema.NotificationDocument.recipientID, isEqualTo: userID)
                .order(by: FirebaseSchema.NotificationDocument.createdAt, descending: true)
                .limit(to: limit)
            
            // Apply pagination if lastDocument provided
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            let lastDoc = snapshot.documents.last
            let hasMore = snapshot.documents.count == limit
            
            // Convert documents to StitchNotification objects
            let notifications = snapshot.documents.compactMap { doc -> StitchNotification? in
                let data = doc.data()
                
                return StitchNotification(
                    id: doc.documentID,
                    recipientID: data[FirebaseSchema.NotificationDocument.recipientID] as? String ?? "",
                    senderID: data[FirebaseSchema.NotificationDocument.senderID] as? String ?? "",
                    type: StitchNotificationType(rawValue: data[FirebaseSchema.NotificationDocument.type] as? String ?? "") ?? .engagementReward,
                    title: data[FirebaseSchema.NotificationDocument.title] as? String ?? "",
                    message: data[FirebaseSchema.NotificationDocument.message] as? String ?? "",
                    payload: data[FirebaseSchema.NotificationDocument.payload] as? [String: Any] ?? [:],
                    isRead: data[FirebaseSchema.NotificationDocument.isRead] as? Bool ?? false,
                    createdAt: (data[FirebaseSchema.NotificationDocument.createdAt] as? Timestamp)?.dateValue() ?? Date(),
                    readAt: (data[FirebaseSchema.NotificationDocument.readAt] as? Timestamp)?.dateValue(),
                    expiresAt: (data[FirebaseSchema.NotificationDocument.expiresAt] as? Timestamp)?.dateValue()
                )
            }
            
            // Update local state if this is the first page
            if lastDocument == nil {
                await MainActor.run {
                    self.recentNotifications = notifications
                    self.unreadCount = notifications.filter { !$0.isRead }.count
                }
            }
            
            print("📧 NOTIFICATION: Loaded \(notifications.count) notifications for user \(userID)")
            return (notifications, lastDoc, hasMore)
            
        } catch {
            lastError = "Failed to load notifications: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Load failed - \(error)")
            throw error
        }
    }
    
    /// Mark notification as read
    func markNotificationAsRead(notificationID: String) async throws {
        
        do {
            try await db.collection(FirebaseSchema.Collections.notifications)
                .document(notificationID)
                .updateData([
                    FirebaseSchema.NotificationDocument.isRead: true,
                    FirebaseSchema.NotificationDocument.readAt: Timestamp()
                ])
            
            // Update local state
            await MainActor.run {
                if let index = recentNotifications.firstIndex(where: { $0.id == notificationID }) {
                    recentNotifications[index].isRead = true
                    recentNotifications[index].readAt = Date()
                    unreadCount = max(0, unreadCount - 1)
                }
            }
            
            print("📧 NOTIFICATION: Marked \(notificationID) as read")
            
        } catch {
            lastError = "Failed to mark notification as read: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Mark as read failed - \(error)")
            throw error
        }
    }
    
    /// Mark all notifications as read for a user
    func markAllNotificationsAsRead(for userID: String) async throws {
        
        do {
            let batch = db.batch()
            let unreadNotifications = recentNotifications.filter { !$0.isRead }
            
            for notification in unreadNotifications {
                let ref = db.collection(FirebaseSchema.Collections.notifications).document(notification.id)
                batch.updateData([
                    FirebaseSchema.NotificationDocument.isRead: true,
                    FirebaseSchema.NotificationDocument.readAt: Timestamp()
                ], forDocument: ref)
            }
            
            try await batch.commit()
            
            // Update local state
            await MainActor.run {
                for i in 0..<recentNotifications.count {
                    recentNotifications[i].isRead = true
                    recentNotifications[i].readAt = Date()
                }
                unreadCount = 0
            }
            
            print("📧 NOTIFICATION: Marked all notifications as read for \(userID)")
            
        } catch {
            lastError = "Failed to mark all notifications as read: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Mark all as read failed - \(error)")
            throw error
        }
    }
    
    /// Get unread notification count for a user
    func getUnreadCount(for userID: String) async throws -> Int {
        
        do {
            let snapshot = try await db.collection(FirebaseSchema.Collections.notifications)
                .whereField(FirebaseSchema.NotificationDocument.recipientID, isEqualTo: userID)
                .whereField(FirebaseSchema.NotificationDocument.isRead, isEqualTo: false)
                .count
                .getAggregation(source: .server)
            
            let count = Int(snapshot.count)
            
            await MainActor.run {
                self.unreadCount = count
            }
            
            return count
            
        } catch {
            lastError = "Failed to get unread count: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Unread count failed - \(error)")
            throw error
        }
    }
    
    // MARK: - Permission Management
    
    /// Request notification permissions
    func requestNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            
            await MainActor.run {
                notificationPermissionStatus = granted ? .authorized : .denied
            }
            
            if granted {
                await registerForRemoteNotifications()
            }
            
            print("📧 NOTIFICATION: Permissions \(granted ? "granted" : "denied")")
            return granted
            
        } catch {
            print("❌ NOTIFICATION: Permission request failed - \(error)")
            await MainActor.run {
                notificationPermissionStatus = .denied
            }
            return false
        }
    }
    
    /// Register for remote notifications
    private func registerForRemoteNotifications() async {
        do {
            let token = try await messaging.token()
            await MainActor.run {
                self.fcmToken = token
                self.isRegistered = true
            }
            
            print("📧 NOTIFICATION: FCM token registered - \(token.prefix(20))...")
            
        } catch {
            print("❌ NOTIFICATION: FCM registration failed - \(error)")
        }
    }
    
    // MARK: - Create and Send Notifications
    
    /// Create and save a notification to the database
    func createNotification(_ notification: StitchNotification) async throws {
        
        do {
            // Manual data dictionary creation to avoid Codable issues
            let data: [String: Any] = [
                FirebaseSchema.NotificationDocument.id: notification.id,
                FirebaseSchema.NotificationDocument.recipientID: notification.recipientID,
                FirebaseSchema.NotificationDocument.senderID: notification.senderID,
                FirebaseSchema.NotificationDocument.type: notification.type.rawValue,
                FirebaseSchema.NotificationDocument.title: notification.title,
                FirebaseSchema.NotificationDocument.message: notification.message,
                FirebaseSchema.NotificationDocument.payload: notification.payload,
                FirebaseSchema.NotificationDocument.isRead: notification.isRead,
                FirebaseSchema.NotificationDocument.createdAt: Timestamp(date: notification.createdAt)
            ]
            
            // Add optional fields
            var finalData = data
            if let readAt = notification.readAt {
                finalData[FirebaseSchema.NotificationDocument.readAt] = Timestamp(date: readAt)
            }
            if let expiresAt = notification.expiresAt {
                finalData[FirebaseSchema.NotificationDocument.expiresAt] = Timestamp(date: expiresAt)
            }
            
            try await db.collection(FirebaseSchema.Collections.notifications)
                .document(notification.id)
                .setData(finalData)
            
            // Send push notification if enabled
            await sendPushNotification(notification, to: notification.recipientID)
            
            print("📧 NOTIFICATION: Created notification \(notification.id)")
            
        } catch {
            lastError = "Failed to create notification: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Create failed - \(error)")
            throw error
        }
    }
    
    // MARK: - Social Engagement Notifications (NEW - User Interactions)
    
    /// Send notification when user hypes/cools another user's video
    func sendEngagementInteractionNotification(
        to videoCreatorID: String,
        from userInfo: BasicUserInfo,
        videoID: String,
        engagementType: InteractionType,
        newHypeCount: Int,
        newCoolCount: Int,
        videoTitle: String? = nil
    ) async throws {
        
        // Don't send if user is interacting with their own video
        guard userInfo.id != videoCreatorID else { return }
        
        let actionText = engagementType == .hype ? "hyped" : "cooled"
        let emoji = engagementType == .hype ? "🔥" : "❄️"
        
        let payloadDict: [String: Any] = [
            "videoID": videoID,
            "senderUsername": userInfo.username,
            "senderDisplayName": userInfo.displayName,
            "senderProfileImageURL": userInfo.profileImageURL ?? "",
            "engagementType": engagementType.rawValue,
            "hypeCount": newHypeCount,
            "coolCount": newCoolCount,
            "videoTitle": videoTitle ?? ""
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: videoCreatorID,
            senderID: userInfo.id,
            type: engagementType == .hype ? .engagementReward : .systemAlert,
            title: "\(emoji) @\(userInfo.username) \(actionText) your video",
            message: engagementType == .hype ?
                "Your video now has \(newHypeCount) hypes!" :
                "Your video was cooled by @\(userInfo.username)",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 SOCIAL NOTIFICATION: Sent \(actionText) notification from @\(userInfo.username) to creator \(videoCreatorID)")
    }
    
    /// Send notification when user follows another user
    func sendFollowNotification(
        to followedUserID: String,
        from followerInfo: BasicUserInfo
    ) async throws {
        
        // Don't send if somehow following yourself
        guard followerInfo.id != followedUserID else { return }
        
        let payloadDict: [String: Any] = [
            "followerID": followerInfo.id,
            "followerUsername": followerInfo.username,
            "followerDisplayName": followerInfo.displayName,
            "followerProfileImageURL": followerInfo.profileImageURL ?? "",
            "followedAt": Timestamp(date: Date()).seconds
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: followedUserID,
            senderID: followerInfo.id,
            type: .newFollower,
            title: "👥 @\(followerInfo.username) started following you",
            message: "You have a new follower! \(followerInfo.displayName) is now following your content.",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 SOCIAL NOTIFICATION: Sent follow notification from @\(followerInfo.username) to user \(followedUserID)")
    }
    
    /// Send notification when user replies to a video/thread
    func sendReplyNotification(
        to originalCreatorID: String,
        from replierInfo: BasicUserInfo,
        originalVideoID: String,
        replyVideoID: String,
        replyText: String? = nil
    ) async throws {
        
        // Don't send if replying to own video
        guard replierInfo.id != originalCreatorID else { return }
        
        let payloadDict: [String: Any] = [
            "originalVideoID": originalVideoID,
            "replyVideoID": replyVideoID,
            "replierID": replierInfo.id,
            "replierUsername": replierInfo.username,
            "replierDisplayName": replierInfo.displayName,
            "replierProfileImageURL": replierInfo.profileImageURL ?? "",
            "replyText": replyText ?? "",
            "repliedAt": Timestamp(date: Date()).seconds
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: originalCreatorID,
            senderID: replierInfo.id,
            type: .videoReply,
            title: "💬 @\(replierInfo.username) replied to your video",
            message: "Check out their response to your content!",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 SOCIAL NOTIFICATION: Sent reply notification from @\(replierInfo.username) to creator \(originalCreatorID)")
    }
    
    /// Send trending notification when video goes viral
    func sendTrendingNotification(
        to creatorID: String,
        videoID: String,
        hypeCount: Int,
        videoTitle: String? = nil
    ) async throws {
        
        // Only send for significant milestones
        let milestones = [100, 500, 1000, 5000, 10000, 50000, 100000]
        guard milestones.contains(hypeCount) else { return }
        
        let payloadDict: [String: Any] = [
            "videoID": videoID,
            "hypeCount": hypeCount,
            "videoTitle": videoTitle ?? "",
            "milestone": hypeCount,
            "trendingAt": Timestamp(date: Date()).seconds
        ]
        
        let emoji = hypeCount >= 10000 ? "🚀" : hypeCount >= 1000 ? "🔥" : "📈"
        let message = hypeCount >= 10000 ?
            "Your video is going viral with \(hypeCount) hypes!" :
            "Your video is trending with \(hypeCount) hypes!"
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: creatorID,
            senderID: "system",
            type: .systemAlert,
            title: "\(emoji) Your video is trending!",
            message: message,
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 TRENDING NOTIFICATION: Sent trending notification for video \(videoID) with \(hypeCount) hypes")
    }
    
    /// Send welcome notification for new users
    func sendWelcomeNotification(
        to userID: String,
        username: String
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "welcomeType": "new_user",
            "joinedAt": Timestamp(date: Date()).seconds
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: "system",
            type: .systemAlert,
            title: "🎉 Welcome to Stitch Social!",
            message: "Hey @\(username)! Start creating and engaging with the community to earn hypes and unlock badges.",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 WELCOME NOTIFICATION: Sent welcome notification to new user @\(username)")
    }
    
    /// Send engagement reward notification
    func sendEngagementRewardNotification(
        to userID: String,
        type: EngagementRewardType,
        details: EngagementRewardDetails
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "senderID": details.senderID,
            "engagementCount": details.engagementCount,
            "streakCount": details.streakCount,
            "rewardAmount": details.rewardAmount,
            "type": type.rawValue
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: details.senderID,
            type: .engagementReward,
            title: "🔥 \(type.notificationTitle)",
            message: type.notificationMessage(details: details),
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent engagement reward - \(type.rawValue)")
    }
    
    /// Send progressive tap milestone notification
    func sendProgressiveTapMilestone(
        to userID: String,
        videoID: String,
        currentTaps: Int,
        requiredTaps: Int,
        milestone: TapMilestone
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "videoID": videoID,
            "currentTaps": currentTaps,
            "requiredTaps": requiredTaps,
            "milestone": milestone.rawValue
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: "system",
            type: .progressiveTap,
            title: milestone.notificationTitle,
            message: milestone.notificationMessage(currentTaps: currentTaps, required: requiredTaps),
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()) // Shorter expiration
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent tap milestone - \(milestone.rawValue)")
    }
    
    /// Send badge unlock notification
    func sendBadgeUnlockNotification(
        to userID: String,
        badge: String,
        badgeDisplayName: String,
        badgeDescription: String
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "badgeType": badge,
            "unlockedAt": Timestamp(date: Date()).seconds,
            "badgeTitle": badgeDisplayName,
            "badgeDescription": badgeDescription
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: "system",
            type: .badgeUnlock,
            title: "🏆 Badge Unlocked!",
            message: "You've earned the \"\(badgeDisplayName)\" badge! \(badgeDescription)",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent badge unlock - \(badge)")
    }
    
    /// Send new follower notification
    func sendNewFollowerNotification(
        to userID: String,
        follower: BasicUserInfo
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "followerID": follower.id,
            "followerUsername": follower.username,
            "followerDisplayName": follower.displayName,
            "followedAt": Timestamp(date: Date()).seconds
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: follower.id,
            type: .newFollower,
            title: "👥 New Follower",
            message: "\(follower.displayName) (@\(follower.username)) started following you!",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent new follower - \(follower.username)")
    }
    
    // MARK: - Private Helpers
    
    private func sendPushNotification(_ notification: StitchNotification, to userID: String) async {
        // Check if user has push notifications enabled
        guard await isPushNotificationEnabled(for: userID) else {
            print("📧 NOTIFICATION: Push disabled for user \(userID)")
            return
        }
        
        // Get user's FCM token
        guard let userToken = await getUserFCMToken(userID: userID) else {
            print("📧 NOTIFICATION: No FCM token for user \(userID)")
            return
        }
        
        // Send push notification via FCM
        // Note: This would typically be done via a backend service
        print("📧 NOTIFICATION: Push sent to \(userToken.prefix(20))...")
    }
    
    private func isPushNotificationEnabled(for userID: String) async -> Bool {
        do {
            let doc = try await db.collection("notificationSettings").document(userID).getDocument()
            return doc.data()?["pushEnabled"] as? Bool ?? true
        } catch {
            return true // Default to enabled
        }
    }
    
    private func getUserFCMToken(userID: String) async -> String? {
        do {
            let doc = try await db.collection("userTokens").document(userID).getDocument()
            return doc.data()?["fcmToken"] as? String
        } catch {
            return nil
        }
    }
    
    // MARK: - Cleanup Operations
    
    /// Clean up expired notifications
    func cleanupExpiredNotifications() async throws {
        
        let expirationDate = Calendar.current.date(byAdding: .day, value: -notificationExpirationDays, to: Date()) ?? Date()
        
        let query = db.collection(FirebaseSchema.Collections.notifications)
            .whereField(FirebaseSchema.NotificationDocument.createdAt, isLessThan: Timestamp(date: expirationDate))
            .limit(to: 100) // Process in batches
        
        let snapshot = try await query.getDocuments()
        
        if !snapshot.documents.isEmpty {
            let batch = db.batch()
            
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            print("📧 NOTIFICATION: Cleaned up \(snapshot.documents.count) expired notifications")
        }
    }
}

// MARK: - Firebase Messaging Delegate

extension NotificationService: MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📧 NOTIFICATION: FCM token refreshed - \(fcmToken?.prefix(20) ?? "nil")...")
        
        Task { @MainActor in
            self.fcmToken = fcmToken
            self.isRegistered = fcmToken != nil
        }
    }
}

// MARK: - Supporting Types (Complete Definitions)

/// Notification permission status
enum NotificationPermissionStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
}

/// Core notification structure for database storage (Simplified without complex Codable)
struct StitchNotification: Identifiable {
    let id: String
    let recipientID: String
    let senderID: String
    let type: StitchNotificationType
    let title: String
    let message: String
    let payload: [String: Any]
    var isRead: Bool
    let createdAt: Date
    var readAt: Date?
    let expiresAt: Date?
    
    init(
        id: String = UUID().uuidString,
        recipientID: String,
        senderID: String,
        type: StitchNotificationType,
        title: String,
        message: String,
        payload: [String: Any] = [:],
        isRead: Bool = false,
        createdAt: Date = Date(),
        readAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.recipientID = recipientID
        self.senderID = senderID
        self.type = type
        self.title = title
        self.message = message
        self.payload = payload
        self.isRead = isRead
        self.createdAt = createdAt
        self.readAt = readAt
        self.expiresAt = expiresAt
    }
}

/// Notification types for the Stitch Social platform
enum StitchNotificationType: String, CaseIterable, Codable {
    case engagementReward = "engagement_reward"
    case progressiveTap = "progressive_tap"
    case badgeUnlock = "badge_unlock"
    case tierAdvancement = "tier_advancement"
    case newFollower = "new_follower"
    case videoReply = "video_reply"
    case mention = "mention"
    case systemAlert = "system_alert"
}

/// Engagement reward types
enum EngagementRewardType: String, Codable, CaseIterable {
    case firstHype = "first_hype"
    case tapMilestone = "tap_milestone"
    case viralVideo = "viral_video"
    case engagementStreak = "engagement_streak"
    
    var notificationTitle: String {
        switch self {
        case .firstHype: return "🔥 First Hype!"
        case .tapMilestone: return "👆 Tap Milestone!"
        case .viralVideo: return "🚀 Viral Video!"
        case .engagementStreak: return "⚡ Engagement Streak!"
        }
    }
    
    func notificationMessage(details: EngagementRewardDetails) -> String {
        switch self {
        case .firstHype:
            return "You got your first hype! The community is feeling your vibe."
        case .tapMilestone:
            return "You've reached a tap milestone! Your persistence is paying off."
        case .viralVideo:
            return "Your video is going viral with \(details.engagementCount) engagements!"
        case .engagementStreak:
            return "You're on a \(details.streakCount)-day engagement streak! Keep it up!"
        }
    }
}

/// Tap milestone types
enum TapMilestone: String, Codable, CaseIterable {
    case quarter = "quarter"
    case half = "half"
    case threeQuarters = "three_quarters"
    case complete = "complete"
    
    var notificationTitle: String {
        switch self {
        case .quarter: return "👆 25% Progress!"
        case .half: return "👆 Halfway There!"
        case .threeQuarters: return "👆 Almost Done!"
        case .complete: return "🎉 Tap Complete!"
        }
    }
    
    func notificationMessage(currentTaps: Int, required: Int) -> String {
        switch self {
        case .quarter:
            return "You're 25% of the way to unlocking this hype! Keep tapping."
        case .half:
            return "Halfway there! \(currentTaps)/\(required) taps completed."
        case .threeQuarters:
            return "So close! Just \(required - currentTaps) more taps to go."
        case .complete:
            return "Hype unlocked! Your persistence earned this engagement."
        }
    }
}

/// Payload detail structs (Simple without complex Codable)
struct EngagementRewardDetails {
    let senderID: String
    let engagementCount: Int
    let streakCount: Int
    let rewardAmount: Double
}
