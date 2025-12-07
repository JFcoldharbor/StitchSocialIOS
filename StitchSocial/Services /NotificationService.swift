//
//  NotificationService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Notification Management with Cloud Functions
//  Codebase: stitchnoti
//  Region: us-central1
//  Database: stitchfin
//  FIXED: Changed StitchError to NSError for compatibility
//  UPDATED: Added sendStitchNotification method back
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
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
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
        // Configure for us-central1 region
        self.functions = Functions.functions(region: "us-central1")
        
        print("📬 NOTIFICATION SERVICE: Initialized")
        print("🔧 REGION: us-central1")
        print("🔧 PREFIX: \(functionPrefix)")
    }
    
    // MARK: - Authenticated Function Calls
    
    /// Call Cloud Function using Firebase Callable Functions SDK (handles auth automatically)
    private func callFunction(name: String, data: [String: Any] = [:]) async throws -> Any? {
        // Verify authentication
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }
        
        let functionName = "\(functionPrefix)\(name)"
        print("📞 CALLING: \(functionName)")
        print("🔐 AUTH UID: \(user.uid)")
        
        do {
            // ✅ Use Firebase Callable Functions SDK (handles auth automatically)
            let callable = functions.httpsCallable(functionName)
            
            let result = try await callable.call(data)
            
            print("✅ SUCCESS: \(functionName)")
            return result.data
            
        } catch {
            print("❌ ERROR: \(functionName) failed - \(error)")
            throw error
        }
    }
    
    // MARK: - Test Functions
    
    /// Send test push notification
    func sendTestPush() async throws {
        print("🧪 TEST: Sending test push notification")
        
        let result = try await callFunction(name: "sendTestPush")
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ TEST PUSH: Sent successfully")
        } else {
            throw NSError(domain: "NotificationService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Test push failed"
            ])
        }
    }
    
    /// Check FCM token status
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
    
    /// Send engagement notification (hype/cool)
    func sendEngagementNotification(
        to recipientID: String,
        videoID: String,
        engagementType: String,
        videoTitle: String
    ) async throws {
        print("🔥 ENGAGEMENT: Sending \(engagementType) notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "engagementType": engagementType,
            "videoTitle": videoTitle
        ]
        
        let result = try await callFunction(name: "sendEngagement", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ ENGAGEMENT: Notification sent")
        }
    }
    
    // MARK: - Reply & Follow Notifications
    
    /// Send reply notification
    func sendReplyNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String
    ) async throws {
        print("💬 REPLY: Sending reply notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "videoTitle": videoTitle
        ]
        
        let result = try await callFunction(name: "sendReply", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ REPLY: Notification sent")
        }
    }
    
    /// Send follow notification
    func sendFollowNotification(to recipientID: String) async throws {
        print("👤 FOLLOW: Sending follow notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID
        ]
        
        let result = try await callFunction(name: "sendFollow", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ FOLLOW: Notification sent")
        }
    }
    
    /// Send mention notification
    func sendMentionNotification(
        to recipientID: String,
        videoID: String,
        videoTitle: String,
        mentionContext: String = "video"
    ) async throws {
        print("📌 MENTION: Sending mention notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "mentionContext": mentionContext
        ]
        
        let result = try await callFunction(name: "sendMention", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ MENTION: Notification sent")
        }
    }
    
    // MARK: - Stitch/Reply Notifications
    
    /// Send stitch/reply notification to thread participants
    func sendStitchNotification(
        videoID: String,
        videoTitle: String,
        originalCreatorID: String,
        parentCreatorID: String?,
        threadUserIDs: [String]
    ) async throws {
        print("🧵 STITCH: Sending stitch notification")
        print("   • Video: \(videoID)")
        print("   • Original Creator: \(originalCreatorID)")
        print("   • Parent Creator: \(parentCreatorID ?? "none")")
        print("   • Thread Users: \(threadUserIDs.count)")
        
        let data: [String: Any] = [
            "videoID": videoID,
            "videoTitle": videoTitle,
            "originalCreatorID": originalCreatorID,
            "parentCreatorID": parentCreatorID ?? "",
            "threadUserIDs": threadUserIDs
        ]
        
        let result = try await callFunction(name: "sendStitch", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ STITCH: Notifications sent to \(threadUserIDs.count + 1) users")
        }
    }
    
    // MARK: - Milestone Notifications
    
    /// Send milestone notification to creator, followers, and engagers
    func sendMilestoneNotification(
        milestone: Int,
        videoID: String,
        videoTitle: String,
        creatorID: String,
        followerIDs: [String],
        engagerIDs: [String]
    ) async throws {
        print("🏆 MILESTONE: Sending milestone notification")
        print("   • Milestone: \(milestone) hypes")
        print("   • Video: \(videoID)")
        print("   • Creator: \(creatorID)")
        print("   • Followers: \(followerIDs.count)")
        print("   • Engagers: \(engagerIDs.count)")
        
        let data: [String: Any] = [
            "milestone": milestone,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "creatorID": creatorID,
            "followerIDs": followerIDs,
            "engagerIDs": engagerIDs
        ]
        
        let result = try await callFunction(name: "sendMilestone", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            let totalNotified = followerIDs.count + engagerIDs.count + 1 // +1 for creator
            print("✅ MILESTONE: Notifications sent to \(totalNotified) users")
        }
    }
    
    // MARK: - New Video Notifications
    
    /// Notify all followers when creator uploads new video
    func sendNewVideoNotification(
        creatorID: String,
        creatorUsername: String,
        videoID: String,
        videoTitle: String,
        followerIDs: [String]
    ) async throws {
        print("🎬 NEW VIDEO: Notifying \(followerIDs.count) followers")
        
        let data: [String: Any] = [
            "creatorID": creatorID,
            "creatorUsername": creatorUsername,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "followerIDs": followerIDs
        ]
        
        let result = try await callFunction(name: "sendNewVideo", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ NEW VIDEO: Notifications sent to \(followerIDs.count) followers")
        }
    }
    
    // MARK: - Re-Engagement Notifications (NEW)
    
    /// Send re-engagement notification (TikTok/Instagram style)
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
            // Check if cooldown
            if let reason = resultData["reason"] as? String, reason == "cooldown" {
                let hoursRemaining = resultData["hoursRemaining"] as? String ?? "unknown"
                print("⏸️ RE-ENGAGEMENT: Cooldown active (\(hoursRemaining)h remaining)")
                return ReEngagementResult(
                    success: false,
                    notificationId: nil,
                    pushSent: false,
                    reason: .cooldown,
                    hoursRemaining: Double(hoursRemaining) ?? 0
                )
            }
            
            return ReEngagementResult(
                success: false,
                notificationId: nil,
                pushSent: false,
                reason: .unknown,
                hoursRemaining: nil
            )
        }
        
        let notificationId = resultData["notificationId"] as? String
        let pushSent = resultData["pushSent"] as? Bool ?? false
        
        print("✅ RE-ENGAGEMENT: Sent successfully - Push: \(pushSent)")
        
        return ReEngagementResult(
            success: true,
            notificationId: notificationId,
            pushSent: pushSent,
            reason: nil,
            hoursRemaining: nil
        )
    }
    
    // MARK: - Resend Read Notifications (NEW - TikTok Style)
    
    /// Resend read notifications as reminders (TikTok/Instagram style)
    func resendReadNotifications(limit: Int = 5) async throws -> ResendResult {
        print("🔁 RESEND: Resending up to \(limit) read notifications")
        
        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user"
            ])
        }
        
        let data: [String: Any] = [
            "userId": userID,
            "limit": limit
        ]
        
        let result = try await callFunction(name: "resendReadNotifications", data: data)
        
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
                payload: data["payload"] as? [String: String] ?? [:],
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
            .updateData([
                "isRead": true,
                "readAt": FieldValue.serverTimestamp()
            ])
    }
    
    func markAllAsRead(for userID: String) async throws {
        print("✅ MARK ALL READ: User \(userID)")
        
        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        let batch = db.batch()
        
        for document in snapshot.documents {
            batch.updateData([
                "isRead": true,
                "readAt": FieldValue.serverTimestamp()
            ], forDocument: document.reference)
        }
        
        try await batch.commit()
        print("✅ MARK ALL READ: Updated \(snapshot.documents.count) notifications")
    }
    
    // MARK: - Clear Notifications
    
    /// Clear all notifications for user
    func clearAllNotifications() async throws -> Int {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user"
            ])
        }
        
        print("🗑️ CLEAR ALL: Clearing notifications for user \(userID)")
        
        let data: [String: Any] = [
            "userId": userID
        ]
        
        let result = try await callFunction(name: "clearAllNotifications", data: data)
        
        guard let resultData = result as? [String: Any],
              let success = resultData["success"] as? Bool,
              success else {
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
                guard let self = self else { return }
                
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
                        payload: data["payload"] as? [String: String] ?? [:],
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
    case cooldown
    case noActivity
    case unknown
}

struct ResendResult {
    let success: Bool
    let resent: Int
    let reason: ResendFailureReason?
}

enum ResendFailureReason {
    case noToken
    case noReadNotifications
    case unknown
}
