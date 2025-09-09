//
//  NotificationService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Push Notifications & Database Management
//  Dependencies: Firebase Messaging, Config, FirebaseSchema
//  Features: Database CRUD, engagement rewards, badge unlocks, following notifications
//

import Foundation
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Complete notification service with database operations and notification management
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
            
            // Log that notification was created
            print("📧 NOTIFICATION: Created notification \(notification.id)")
            
            // Actually send the push notification
            let success = await FCMPushManager.shared.sendPushNotification(
                to: notification.recipientID,
                title: notification.title,
                body: notification.message,
                data: notification.payload
            )
            
            if success {
                print("📧 NOTIFICATION: Push sent successfully")
            } else {
                print("📧 NOTIFICATION: Push sending failed - check FCMPushManager configuration")
            }
            
        } catch {
            lastError = "Failed to create notification: \(error.localizedDescription)"
            print("❌ NOTIFICATION: Create failed - \(error)")
            throw error
        }
    }
    
    // MARK: - Social Engagement Notifications
    
    /// Send notification when user engages with another user's video
    func sendEngagementInteractionNotification(
        to videoCreatorID: String,
        from userInfo: BasicUserInfo,
        videoID: String,
        engagementType: String,
        newHypeCount: Int,
        newCoolCount: Int,
        videoTitle: String? = nil
    ) async throws {
        
        // Don't send if user is interacting with their own video
        guard userInfo.id != videoCreatorID else { return }
        
        let actionText = engagementType == "hype" ? "hyped" : "cooled"
        let emoji = engagementType == "hype" ? "🔥" : "❄️"
        
        let payloadDict: [String: Any] = [
            "videoID": videoID,
            "senderUsername": userInfo.username,
            "senderDisplayName": userInfo.displayName,
            "senderProfileImageURL": userInfo.profileImageURL ?? "",
            "engagementType": engagementType,
            "hypeCount": newHypeCount,
            "coolCount": newCoolCount,
            "videoTitle": videoTitle ?? ""
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: videoCreatorID,
            senderID: userInfo.id,
            type: .engagementReward,
            title: "\(emoji) @\(userInfo.username) \(actionText) your video!",
            message: "Your video now has \(newHypeCount) hypes and \(newCoolCount) cools",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent engagement interaction - \(userInfo.username) \(actionText) video")
    }
    
    /// Send welcome notification to new users
    func sendWelcomeNotification(to userID: String, username: String) async throws {
        
        let payloadDict: [String: Any] = [
            "type": "welcome",
            "isNewUser": true
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
            message: milestone.notificationMessage(currentTaps: currentTaps, requiredTaps: requiredTaps),
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent progressive tap milestone - \(milestone.rawValue)")
    }
    
    /// Send new follower notification
    func sendNewFollowerNotification(
        to userID: String,
        from follower: BasicUserInfo
    ) async throws {
        
        let payloadDict: [String: Any] = [
            "followerID": follower.id,
            "followerUsername": follower.username,
            "followerDisplayName": follower.displayName,
            "followerProfileImageURL": follower.profileImageURL ?? "",
            "followerTier": follower.tier.rawValue,
            "followerClout": follower.clout
        ]
        
        let notification = StitchNotification(
            id: FirebaseSchema.DocumentIDPatterns.generateNotificationID(),
            recipientID: userID,
            senderID: follower.id,
            type: .newFollower,
            title: "👥 New Follower!",
            message: "@\(follower.username) started following you!",
            payload: payloadDict,
            isRead: false,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: notificationExpirationDays, to: Date())
        )
        
        try await createNotification(notification)
        print("📧 NOTIFICATION: Sent new follower - \(follower.username)")
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

// MARK: - Supporting Types

/// Notification permission status
enum NotificationPermissionStatus {
    case notDetermined
    case denied
    case authorized
    case provisional
}

/// Core notification structure for database storage
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
            return "You're on fire! \(details.streakCount) day engagement streak!"
        }
    }
}

/// Engagement reward details structure
struct EngagementRewardDetails {
    let senderID: String
    let engagementCount: Int
    let streakCount: Int
    let rewardAmount: Double  // Changed back to Double to match usage
}

/// Tap milestone enumeration
enum TapMilestone: String, CaseIterable {
    case quarter = "quarter"
    case half = "half"
    case threeQuarters = "three_quarters"
    case complete = "complete"
    
    var notificationTitle: String {
        switch self {
        case .quarter: return "👆 25% There!"
        case .half: return "👆 Halfway!"
        case .threeQuarters: return "👆 Almost There!"
        case .complete: return "🎉 Tap Complete!"
        }
    }
    
    func notificationMessage(currentTaps: Int, requiredTaps: Int) -> String {
        switch self {
        case .quarter:
            return "You've made \(currentTaps) taps! Keep going to reach \(requiredTaps)."
        case .half:
            return "Halfway there! \(currentTaps) of \(requiredTaps) taps completed."
        case .threeQuarters:
            return "So close! \(currentTaps) of \(requiredTaps) taps - almost unlocked!"
        case .complete:
            return "Amazing! You completed all \(requiredTaps) taps and unlocked the content!"
        }
    }
}
