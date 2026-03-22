//
//  NotificationService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Notification Management with Cloud Functions
//  Codebase: stitchnoti
//  Region: us-central1
//  Database: stitchfin
//  UPDATED: Added sendTipNotification + sendSubscriptionNotification
//  UPDATED: Added writeNotification helper (shared by tip/sub direct writes)
//
//  CACHING STRATEGY:
//  - Real-time listener (startListening) caches up to 50 notifications in memory
//    via NotificationViewModel — zero re-reads while listener is active.
//  - loadNotifications uses cursor pagination (lastDocument) — no full re-fetch.
//  - markAllAsRead uses batch write — single round trip for N docs.
//  - Tip cooldown: notification_cooldowns/{key} checked before every tip notify.
//    TTL = 60s. Prevents duplicate pushes across flush windows.
//  - Username cache in TipService (in-memory) — one user read per tipper per session.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging

@MainActor
class NotificationService: ObservableObject {

    // MARK: - Dependencies

    let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private var functions: Functions

    // MARK: - Published State

    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var pendingToasts: [NotificationToast] = []

    // MARK: - Configuration

    private let notificationsCollection = "notifications"
    private let functionPrefix = "stitchnoti_"

    // MARK: - Real-time Listener

    private var notificationListener: ListenerRegistration?

    // MARK: - Initialization

    init() {
        self.functions = Functions.functions(region: "us-central1")
        print("📬 NOTIFICATION SERVICE: Initialized")
        print("🔧 REGION: us-central1")
        print("🔧 PREFIX: \(functionPrefix)")
    }

    // MARK: - Authenticated Function Calls

    private func callFunction(name: String, data: [String: Any] = [:]) async throws -> Any? {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }

        let functionName = "\(functionPrefix)\(name)"
        print("📞 CALLING: \(functionName)")
        print("🔑 AUTH UID: \(user.uid)")

        do {
            let callable = functions.httpsCallable(functionName)
            let result = try await callable.call(data)
            print("✅ SUCCESS: \(functionName)")
            return result.data
        } catch {
            print("❌ ERROR: \(functionName) failed - \(error)")
            throw error
        }
    }

    // MARK: - Direct Firestore Write Helper
    // Used by tip/subscription notifications to write in-app notification directly.
    // Cloud Function (stitchnoti_processTip) handles FCM push separately.
    // This avoids an extra CF invocation for the in-app record.

    func writeNotification(_ notification: StitchNotification) async throws {
        var data: [String: Any] = [
            "id": notification.id,
            "recipientID": notification.recipientID,
            "senderID": notification.senderID,
            "type": notification.type.rawValue,
            "title": notification.title,
            "message": notification.message,
            "payload": notification.payload,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let expiresAt = notification.expiresAt {
            data["expiresAt"] = Timestamp(date: expiresAt)
        }

        try await db.collection(notificationsCollection)
            .document(notification.id)
            .setData(data)
    }

    // MARK: - Test Functions

    func sendTestPush() async throws {
        print("🧪 TEST: Sending test push notification")
        let result = try await callFunction(name: "sendTestPush")
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ TEST PUSH: Sent successfully")
        } else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Test push failed"
            ])
        }
    }

    func checkToken() async throws -> [String: Any] {
        print("🔍 CHECK: Verifying FCM token")
        let result = try await callFunction(name: "checkToken")
        guard let tokenData = result as? [String: Any] else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid token check response"
            ])
        }
        print("✅ TOKEN CHECK: \(tokenData)")
        return tokenData
    }

    // MARK: - Engagement Notifications

    func sendEngagementNotification(
        to recipientID: String,
        videoID: String,
        engagementType: String,
        videoTitle: String,
        threadID: String? = nil
    ) async throws {
        print("🔥 ENGAGEMENT: Sending \(engagementType) notification")
        var data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "engagementType": engagementType,
            "videoTitle": videoTitle
        ]
        if let threadID = threadID { data["threadID"] = threadID }
        let result = try await callFunction(name: "sendEngagement", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ ENGAGEMENT: Notification sent")
        }
    }

    // MARK: - Reply & Follow Notifications

    func sendReplyNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String,
        threadID: String? = nil
    ) async throws {
        print("💬 REPLY: Sending reply notification")
        var data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "videoTitle": videoTitle
        ]
        if let threadID = threadID { data["threadID"] = threadID }
        let result = try await callFunction(name: "sendReply", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ REPLY: Notification sent")
        }
    }

    func sendFollowNotification(to recipientID: String) async throws {
        print("👤 FOLLOW: Sending follow notification")
        let result = try await callFunction(name: "sendFollow", data: ["recipientID": recipientID])
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ FOLLOW: Notification sent")
        }
    }

    func sendMentionNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String,
        mentionContext: String = "video",
        threadID: String? = nil
    ) async throws {
        print("📌 MENTION: Sending mention notification")
        var data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "mentionContext": mentionContext
        ]
        if let threadID = threadID { data["threadID"] = threadID }
        let result = try await callFunction(name: "sendMention", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ MENTION: Notification sent")
        }
    }

    // MARK: - Stitch Notifications

    func sendStitchNotification(
        videoID: String,
        videoTitle: String,
        originalCreatorID: String,
        parentCreatorID: String?,
        threadUserIDs: [String],
        threadID: String? = nil
    ) async throws {
        print("🧵 STITCH: Sending stitch notification")
        print("   • Video: \(videoID)")
        print("   • Original Creator: \(originalCreatorID)")
        print("   • Parent Creator: \(parentCreatorID ?? "none")")
        print("   • Thread Users: \(threadUserIDs.count)")

        var data: [String: Any] = [
            "videoID": videoID,
            "videoTitle": videoTitle,
            "originalCreatorID": originalCreatorID,
            "parentCreatorID": parentCreatorID ?? "",
            "threadUserIDs": threadUserIDs
        ]
        if let threadID = threadID { data["threadID"] = threadID }

        let result = try await callFunction(name: "sendStitch", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ STITCH: Notifications sent to \(threadUserIDs.count + 1) users")
        }
    }

    // MARK: - Milestone Notifications

    func sendMilestoneNotification(
        milestone: Int,
        videoID: String,
        videoTitle: String,
        creatorID: String,
        followerIDs: [String],
        engagerIDs: [String],
        threadID: String? = nil
    ) async throws {
        print("🏆 MILESTONE: Sending milestone notification")
        var data: [String: Any] = [
            "milestone": milestone,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "creatorID": creatorID,
            "followerIDs": followerIDs,
            "engagerIDs": engagerIDs
        ]
        if let threadID = threadID { data["threadID"] = threadID }

        let result = try await callFunction(name: "sendMilestone", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ MILESTONE: Notifications sent to \(followerIDs.count + engagerIDs.count + 1) users")
        }
    }

    // MARK: - New Video Notifications

    func sendNewVideoNotification(
        creatorID: String,
        creatorUsername: String,
        videoID: String,
        videoTitle: String,
        followerIDs: [String],
        threadID: String? = nil
    ) async throws {
        print("🎬 NEW VIDEO: Notifying \(followerIDs.count) followers")
        var data: [String: Any] = [
            "creatorID": creatorID,
            "creatorUsername": creatorUsername,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "followerIDs": followerIDs
        ]
        if let threadID = threadID { data["threadID"] = threadID }

        let result = try await callFunction(name: "sendNewVideo", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            print("✅ NEW VIDEO: Notifications sent to \(followerIDs.count) followers")
        }
    }

    // MARK: - Tip Notification
    // Writes Firestore in-app notification directly (no CF for the record itself).
    // FCM push handled by stitchnoti_processTip Cloud Function called from TipService.
    // Cooldown: 60s per tipper→creator pair via notification_cooldowns collection.

    func sendTipNotification(
        to creatorID: String,
        fromUserID: String,
        fromUsername: String,
        amount: Int,
        videoID: String? = nil
    ) async throws {
        let cooldownKey = "tip_\(fromUserID)_\(creatorID)"
        guard await checkCooldown(key: cooldownKey, intervalSeconds: 60) else {
            print("⏱ TIP NOTIF: Cooldown active (\(fromUsername) → \(creatorID))")
            return
        }

        let amountText = amount == 1 ? "1 coin" : "\(amount) coins"
        var payload: [String: Any] = [
            "senderUsername": fromUsername,
            "senderID": fromUserID,
            "amount": amount,
            "notificationType": "tip"
        ]
        if let videoID = videoID { payload["videoID"] = videoID }

        let notification = StitchNotification(
            recipientID: creatorID,
            senderID: fromUserID,
            type: .tip,
            title: "💰 You got tipped!",
            message: "\(fromUsername) tipped you \(amountText)",
            payload: payload,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )

        try await writeNotification(notification)
        await updateCooldown(key: cooldownKey)
        print("✅ TIP NOTIF: \(amountText) tip notification written for \(creatorID)")
    }

    // MARK: - Subscription Notification
    // No cooldown — each subscription is meaningful and infrequent.
    // FCM push handled by stitchnoti_processTip CF (type = "subscription").

    func sendSubscriptionNotification(
        to creatorID: String,
        fromUserID: String,
        fromUsername: String,
        subscriptionTier: String? = nil
    ) async throws {
        let tierText = subscriptionTier.map { " (\($0))" } ?? ""
        let payload: [String: Any] = [
            "senderUsername": fromUsername,
            "senderID": fromUserID,
            "subscriptionTier": subscriptionTier ?? "",
            "notificationType": "subscription"
        ]

        let notification = StitchNotification(
            recipientID: creatorID,
            senderID: fromUserID,
            type: .subscription,
            title: "⭐ New Subscriber!",
            message: "\(fromUsername) subscribed to you\(tierText)",
            payload: payload,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )

        try await writeNotification(notification)
        print("✅ SUB NOTIF: Subscription notification written for \(creatorID)")
    }

    // MARK: - Re-Engagement Notifications

    func sendReEngagementNotification(
        userID: String,
        notificationType: String,
        payload: [String: Any]
    ) async throws -> ReEngagementResult {
        print("🔄 RE-ENGAGEMENT: Sending \(notificationType) to user \(userID)")

        let data: [String: Any] = [
            "userId": userID,
            "notificationType": notificationType,
            "payload": payload
        ]

        let result = try await callFunction(name: "sendReEngagement", data: data)

        guard let resultData = result as? [String: Any],
              let success = resultData["success"] as? Bool else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid re-engagement response"
            ])
        }

        if !success {
            if let reason = resultData["reason"] as? String, reason == "cooldown" {
                let hoursRemaining = resultData["hoursRemaining"] as? String ?? "unknown"
                print("⏸ RE-ENGAGEMENT: Cooldown active (\(hoursRemaining)h remaining)")
                return ReEngagementResult(
                    success: false, notificationId: nil, pushSent: false,
                    reason: .cooldown, hoursRemaining: Double(hoursRemaining) ?? 0
                )
            }
            return ReEngagementResult(success: false, notificationId: nil, pushSent: false, reason: .unknown, hoursRemaining: nil)
        }

        let notificationId = resultData["notificationId"] as? String
        let pushSent = resultData["pushSent"] as? Bool ?? false
        print("✅ RE-ENGAGEMENT: Sent successfully - Push: \(pushSent)")
        return ReEngagementResult(success: true, notificationId: notificationId, pushSent: pushSent, reason: nil, hoursRemaining: nil)
    }

    // MARK: - Resend Read Notifications

    func resendReadNotifications(limit: Int = 5) async throws -> ResendResult {
        print("🔁 RESEND: Resending up to \(limit) read notifications")

        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user"
            ])
        }

        let result = try await callFunction(name: "resendReadNotifications", data: [
            "userId": userID, "limit": limit
        ])

        guard let resultData = result as? [String: Any],
              let success = resultData["success"] as? Bool else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid resend response"
            ])
        }

        if !success {
            if let reason = resultData["reason"] as? String, reason == "no_token" {
                print("⚠️ RESEND: No FCM token found")
                return ResendResult(success: false, resent: 0, reason: .noToken)
            }
            return ResendResult(success: false, resent: 0, reason: .unknown)
        }

        let resent = resultData["resent"] as? Int ?? 0
        print("✅ RESEND: Successfully resent \(resent) notifications")
        return ResendResult(success: true, resent: resent, reason: nil)
    }

    // MARK: - Load Notifications

    func loadNotifications(
        for userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> NotificationLoadResult {
        print("📨 LOAD: Fetching \(limit) notifications for user \(userID)")

        var query = db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }

        let snapshot = try await query.getDocuments()

        let notifications = snapshot.documents.compactMap { doc -> StitchNotification? in
            let data = doc.data()
            return StitchNotification(
                id: data["id"] as? String ?? doc.documentID,
                recipientID: data["recipientID"] as? String ?? "",
                senderID: data["senderID"] as? String ?? "",
                type: StitchNotificationType(rawValue: data["type"] as? String ?? "system") ?? .system,
                title: data["title"] as? String ?? "",
                message: data["message"] as? String ?? "",
                payload: data["payload"] as? [String: Any] ?? [:],
                isRead: data["isRead"] as? Bool ?? false,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                readAt: (data["readAt"] as? Timestamp)?.dateValue(),
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        }

        let hasMore = snapshot.documents.count == limit
        print("✅ LOAD: Loaded \(notifications.count) notifications, hasMore: \(hasMore)")

        return NotificationLoadResult(
            notifications: notifications,
            lastDocument: snapshot.documents.last,
            hasMore: hasMore
        )
    }

    // MARK: - Mark as Read

    func markAsRead(_ notificationID: String) async throws {
        print("✅ MARK READ: Notification \(notificationID)")
        try await db.collection(notificationsCollection)
            .document(notificationID)
            .updateData(["isRead": true, "readAt": FieldValue.serverTimestamp()])
    }

    func markAllAsRead(for userID: String) async throws {
        print("✅ MARK ALL READ: User \(userID)")

        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        let batch = db.batch()
        for document in snapshot.documents {
            batch.updateData(["isRead": true, "readAt": FieldValue.serverTimestamp()], forDocument: document.reference)
        }
        try await batch.commit()
        print("✅ MARK ALL READ: Updated \(snapshot.documents.count) notifications")
    }

    // MARK: - Clear Notifications

    func clearAllNotifications() async throws -> Int {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user"
            ])
        }

        print("🗑️ CLEAR ALL: Clearing notifications for user \(userID)")

        let result = try await callFunction(name: "clearAllNotifications", data: ["userId": userID])

        guard let resultData = result as? [String: Any],
              let success = resultData["success"] as? Bool, success else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to clear notifications"
            ])
        }

        let deleted = resultData["deleted"] as? Int ?? 0
        print("✅ CLEAR ALL: Deleted \(deleted) notifications")
        return deleted
    }

    // MARK: - Real-time Listener

    func startListening(for userID: String, onUpdate: @escaping ([StitchNotification]) -> Void) {
        stopListening()

        notificationListener = db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil else { return }

                if let error = error {
                    print("❌ LISTENER: Error - \(error)")
                    return
                }

                guard let snapshot = snapshot else {
                    print("⚠️ LISTENER: No snapshot")
                    return
                }

                let notifications = snapshot.documents.compactMap { doc -> StitchNotification? in
                    let data = doc.data()
                    return StitchNotification(
                        id: data["id"] as? String ?? doc.documentID,
                        recipientID: data["recipientID"] as? String ?? "",
                        senderID: data["senderID"] as? String ?? "",
                        type: StitchNotificationType(rawValue: data["type"] as? String ?? "system") ?? .system,
                        title: data["title"] as? String ?? "",
                        message: data["message"] as? String ?? "",
                        payload: data["payload"] as? [String: Any] ?? [:],
                        isRead: data["isRead"] as? Bool ?? false,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        readAt: (data["readAt"] as? Timestamp)?.dateValue(),
                        expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
                    )
                }

                onUpdate(notifications)
            }

        print("👂 LISTENER: Started for user \(userID)")
    }

    func stopListening() {
        notificationListener?.remove()
        notificationListener = nil
        print("🛑 LISTENER: Stopped")
    }

    // MARK: - Debug

    func debugConfiguration() {
        print("🔍 DEBUG: Notification Service Configuration")
        print("  - Database: \(Config.Firebase.databaseName)")
        print("  - Region: us-central1")
        print("  - Function Prefix: \(functionPrefix)")
        print("  - User: \(Auth.auth().currentUser?.uid ?? "none")")
    }

    // MARK: - Private: Cooldown Helpers
    // Shared by sendTipNotification. Reads/writes notification_cooldowns/{key}.
    // One read + one write per tip flush — not per tap.

    private func checkCooldown(key: String, intervalSeconds: TimeInterval) async -> Bool {
        do {
            let doc = try await db.collection("notification_cooldowns").document(key).getDocument()
            guard doc.exists,
                  let ts = doc.data()?["lastNotificationAt"] as? Timestamp else { return true }
            return Date().timeIntervalSince(ts.dateValue()) >= intervalSeconds
        } catch {
            return true
        }
    }

    private func updateCooldown(key: String) async {
        try? await db.collection("notification_cooldowns")
            .document(key)
            .setData(["lastNotificationAt": Timestamp()], merge: true)
    }
}

// MARK: - Supporting Types

struct NotificationLoadResult {
    let notifications: [StitchNotification]
    let lastDocument: DocumentSnapshot?
    let hasMore: Bool
}

struct ReEngagementResult {
    let success: Bool
    let notificationId: String?
    let pushSent: Bool
    let reason: ReEngagementFailureReason?
    let hoursRemaining: Double?
}

enum ReEngagementFailureReason {
    case cooldown, noActivity, unknown
}

struct ResendResult {
    let success: Bool
    let resent: Int
    let reason: ResendFailureReason?
}

enum ResendFailureReason {
    case noToken, noReadNotifications, unknown
}
