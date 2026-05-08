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
        #if DEBUG
        print("📬 NOTIFICATION SERVICE: Initialized")
        #endif
        #if DEBUG
        print("🔧 REGION: us-central1")
        #endif
        #if DEBUG
        print("🔧 PREFIX: \(functionPrefix)")
        #endif
    }

    // MARK: - Authenticated Function Calls

    private func callFunction(name: String, data: [String: Any] = [:]) async throws -> Any? {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }

        let functionName = "\(functionPrefix)\(name)"
        #if DEBUG
        print("📞 CALLING: \(functionName)")
        #endif
        #if DEBUG
        print("🔑 AUTH UID: \(user.uid)")
        #endif

        do {
            let callable = functions.httpsCallable(functionName)
            let result = try await callable.call(data)
            #if DEBUG
            print("✅ SUCCESS: \(functionName)")
            #endif
            return result.data
        } catch {
            #if DEBUG
            print("❌ ERROR: \(functionName) failed - \(error)")
            #endif
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
        #if DEBUG
        print("🧪 TEST: Sending test push notification")
        #endif
        let result = try await callFunction(name: "sendTestPush")
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            #if DEBUG
            print("✅ TEST PUSH: Sent successfully")
            #endif
        } else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Test push failed"
            ])
        }
    }

    func checkToken() async throws -> [String: Any] {
        #if DEBUG
        print("🔍 CHECK: Verifying FCM token")
        #endif
        let result = try await callFunction(name: "checkToken")
        guard let tokenData = result as? [String: Any] else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Invalid token check response"
            ])
        }
        #if DEBUG
        print("✅ TOKEN CHECK: \(tokenData)")
        #endif
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
        #if DEBUG
        print("🔥 ENGAGEMENT: Sending \(engagementType) notification")
        #endif
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
            #if DEBUG
            print("✅ ENGAGEMENT: Notification sent")
            #endif
        }
    }

    // MARK: - Reply & Follow Notifications

    func sendReplyNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String,
        threadID: String? = nil
    ) async throws {
        #if DEBUG
        print("💬 REPLY: Sending reply notification")
        #endif
        var data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "videoTitle": videoTitle
        ]
        if let threadID = threadID { data["threadID"] = threadID }
        let result = try await callFunction(name: "sendReply", data: data)
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            #if DEBUG
            print("✅ REPLY: Notification sent")
            #endif
        }
    }

    func sendFollowNotification(to recipientID: String) async throws {
        #if DEBUG
        print("👤 FOLLOW: Sending follow notification")
        #endif
        let result = try await callFunction(name: "sendFollow", data: ["recipientID": recipientID])
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool, success {
            #if DEBUG
            print("✅ FOLLOW: Notification sent")
            #endif
        }
    }

    func sendMentionNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String,
        mentionContext: String = "video",
        threadID: String? = nil
    ) async throws {
        #if DEBUG
        print("📌 MENTION: Sending mention notification")
        #endif
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
            #if DEBUG
            print("✅ MENTION: Notification sent")
            #endif
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
        #if DEBUG
        print("🧵 STITCH: Sending stitch notification")
        #endif
        #if DEBUG
        print("   • Video: \(videoID)")
        #endif
        #if DEBUG
        print("   • Original Creator: \(originalCreatorID)")
        #endif
        #if DEBUG
        print("   • Parent Creator: \(parentCreatorID ?? "none")")
        #endif
        #if DEBUG
        print("   • Thread Users: \(threadUserIDs.count)")
        #endif

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
            #if DEBUG
            print("✅ STITCH: Notifications sent to \(threadUserIDs.count + 1) users")
            #endif
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
        #if DEBUG
        print("🏆 MILESTONE: Sending milestone notification")
        #endif
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
            #if DEBUG
            print("✅ MILESTONE: Notifications sent to \(followerIDs.count + engagerIDs.count + 1) users")
            #endif
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
        #if DEBUG
        print("🎬 NEW VIDEO: Notifying \(followerIDs.count) followers")
        #endif
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
            #if DEBUG
            print("✅ NEW VIDEO: Notifications sent to \(followerIDs.count) followers")
            #endif
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
            #if DEBUG
            print("⏱ TIP NOTIF: Cooldown active (\(fromUsername) → \(creatorID))")
            #endif
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
        #if DEBUG
        print("✅ TIP NOTIF: \(amountText) tip notification written for \(creatorID)")
        #endif
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
        #if DEBUG
        print("✅ SUB NOTIF: Subscription notification written for \(creatorID)")
        #endif
    }

    // MARK: - Re-Engagement Notifications

    func sendReEngagementNotification(
        userID: String,
        notificationType: String,
        payload: [String: Any]
    ) async throws -> ReEngagementResult {
        #if DEBUG
        print("🔄 RE-ENGAGEMENT: Sending \(notificationType) to user \(userID)")
        #endif

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
                #if DEBUG
                print("⏸ RE-ENGAGEMENT: Cooldown active (\(hoursRemaining)h remaining)")
                #endif
                return ReEngagementResult(
                    success: false, notificationId: nil, pushSent: false,
                    reason: .cooldown, hoursRemaining: Double(hoursRemaining) ?? 0
                )
            }
            return ReEngagementResult(success: false, notificationId: nil, pushSent: false, reason: .unknown, hoursRemaining: nil)
        }

        let notificationId = resultData["notificationId"] as? String
        let pushSent = resultData["pushSent"] as? Bool ?? false
        #if DEBUG
        print("✅ RE-ENGAGEMENT: Sent successfully - Push: \(pushSent)")
        #endif
        return ReEngagementResult(success: true, notificationId: notificationId, pushSent: pushSent, reason: nil, hoursRemaining: nil)
    }

    // MARK: - New Episode Notification
    // Fans out to both followers AND active subscribers of the creator.
    // The Cloud Function (stitchnoti_sendNewEpisode) handles:
    //   1. Querying followers subcollection on the creator user doc
    //   2. Querying subscriptions collection for active subs
    //   3. Deduplicating (a user who is both follower + subscriber gets one notification)
    //   4. Batching FCM sends (max 500 per batch)
    // App side just passes episode metadata — CF does all fan-out reads.

    func sendNewEpisodeNotification(
        creatorID: String,
        creatorUsername: String,
        showTitle: String,
        episodeTitle: String,
        episodeID: String,
        showID: String,
        episodeNumber: Int?,
        isFree: Bool
    ) async throws {
        var data: [String: Any] = [
            "creatorID": creatorID,
            "creatorUsername": creatorUsername,
            "showTitle": showTitle,
            "episodeTitle": episodeTitle.isEmpty ? "New Episode" : episodeTitle,
            "episodeID": episodeID,
            "showID": showID,
            "isFree": isFree
        ]
        if let epNum = episodeNumber { data["episodeNumber"] = epNum }

        let result = try await callFunction(name: "sendNewEpisode", data: data)
        if let resultData = result as? [String: Any],
           let notified = resultData["notified"] as? Int {
            #if DEBUG
            print("✅ NEW EPISODE: Notifications sent to \(notified) followers/subscribers")
            #endif
        }
    }

    // MARK: - Resend Read Notifications

    func resendReadNotifications(limit: Int = 5) async throws -> ResendResult {
        #if DEBUG
        print("🔁 RESEND: Resending up to \(limit) read notifications")
        #endif

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
                #if DEBUG
                print("⚠️ RESEND: No FCM token found")
                #endif
                return ResendResult(success: false, resent: 0, reason: .noToken)
            }
            return ResendResult(success: false, resent: 0, reason: .unknown)
        }

        let resent = resultData["resent"] as? Int ?? 0
        #if DEBUG
        print("✅ RESEND: Successfully resent \(resent) notifications")
        #endif
        return ResendResult(success: true, resent: resent, reason: nil)
    }

    // MARK: - Load Notifications

    func loadNotifications(
        for userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> NotificationLoadResult {
        #if DEBUG
        print("📨 LOAD: Fetching \(limit) notifications for user \(userID)")
        #endif

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
        #if DEBUG
        print("✅ LOAD: Loaded \(notifications.count) notifications, hasMore: \(hasMore)")
        #endif

        return NotificationLoadResult(
            notifications: notifications,
            lastDocument: snapshot.documents.last,
            hasMore: hasMore
        )
    }

    // MARK: - Mark as Read

    func markAsRead(_ notificationID: String) async throws {
        #if DEBUG
        print("✅ MARK READ: Notification \(notificationID)")
        #endif
        try await db.collection(notificationsCollection)
            .document(notificationID)
            .updateData(["isRead": true, "readAt": FieldValue.serverTimestamp()])
    }

    func markAllAsRead(for userID: String) async throws {
        #if DEBUG
        print("✅ MARK ALL READ: User \(userID)")
        #endif

        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        let batch = db.batch()
        for document in snapshot.documents {
            batch.updateData(["isRead": true, "readAt": FieldValue.serverTimestamp()], forDocument: document.reference)
        }
        try await batch.commit()
        #if DEBUG
        print("✅ MARK ALL READ: Updated \(snapshot.documents.count) notifications")
        #endif
    }

    // MARK: - Clear Notifications

    func clearAllNotifications() async throws -> Int {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user"
            ])
        }

        #if DEBUG
        print("🗑️ CLEAR ALL: Clearing notifications for user \(userID)")
        #endif

        let result = try await callFunction(name: "clearAllNotifications", data: ["userId": userID])

        guard let resultData = result as? [String: Any],
              let success = resultData["success"] as? Bool, success else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to clear notifications"
            ])
        }

        let deleted = resultData["deleted"] as? Int ?? 0
        #if DEBUG
        print("✅ CLEAR ALL: Deleted \(deleted) notifications")
        #endif
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
                    #if DEBUG
                    print("❌ LISTENER: Error - \(error)")
                    #endif
                    return
                }

                guard let snapshot = snapshot else {
                    #if DEBUG
                    print("⚠️ LISTENER: No snapshot")
                    #endif
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

        #if DEBUG
        print("👂 LISTENER: Started for user \(userID)")
        #endif
    }

    func stopListening() {
        notificationListener?.remove()
        notificationListener = nil
        #if DEBUG
        print("🛑 LISTENER: Stopped")
        #endif
    }

    // MARK: - Debug

    func debugConfiguration() {
        #if DEBUG
        print("🔍 DEBUG: Notification Service Configuration")
        #endif
        #if DEBUG
        print("  - Database: \(Config.Firebase.databaseName)")
        #endif
        #if DEBUG
        print("  - Region: us-central1")
        #endif
        #if DEBUG
        print("  - Function Prefix: \(functionPrefix)")
        #endif
        #if DEBUG
        print("  - User: \(Auth.auth().currentUser?.uid ?? "none")")
        #endif
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
