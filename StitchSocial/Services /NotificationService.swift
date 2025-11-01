//
//  NotificationService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Notification Management with Cloud Functions
//  Codebase: stitchnoti
//  Region: us-central1
//  Database: stitchfin
//  FIXED: Use Firebase Callable Functions SDK instead of direct HTTP
//  UPDATED: Added sendNewVideoNotification for follower notifications
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
        print("🔑 AUTH UID: \(user.uid)")
        
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
    
    // MARK: - First Engagement Notifications
    
    /// Send first hype notification to creator
    func sendFirstHypeNotification(
        to creatorID: String,
        videoID: String,
        videoTitle: String,
        senderUsername: String
    ) async throws {
        print("🔥 FIRST HYPE: Sending to creator \(creatorID)")
        
        let data: [String: Any] = [
            "recipientID": creatorID,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "senderUsername": senderUsername
        ]
        
        let result = try await callFunction(name: "sendFirstHype", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ FIRST HYPE: Notification sent")
        }
    }
    
    /// Send first cool notification to creator
    func sendFirstCoolNotification(
        to creatorID: String,
        videoID: String,
        videoTitle: String,
        senderUsername: String
    ) async throws {
        print("❄️ FIRST COOL: Sending to creator \(creatorID)")
        
        let data: [String: Any] = [
            "recipientID": creatorID,
            "videoID": videoID,
            "videoTitle": videoTitle,
            "senderUsername": senderUsername
        ]
        
        let result = try await callFunction(name: "sendFirstCool", data: data)
        
        if let resultData = result as? [String: Any],
           let success = resultData["success"] as? Bool,
           success {
            print("✅ FIRST COOL: Notification sent")
        }
    }
    
    // MARK: - Milestone Notifications
    
    /// Send milestone notification
    func sendMilestoneNotification(
        milestone: Int,
        videoID: String,
        videoTitle: String,
        creatorID: String,
        followerIDs: [String] = [],
        engagerIDs: [String] = []
    ) async throws {
        
        let milestoneEmoji: String
        let milestoneName: String
        
        switch milestone {
        case 10:
            milestoneEmoji = "🔥"
            milestoneName = "Heating Up"
        case 400:
            milestoneEmoji = "👀"
            milestoneName = "Must See"
        case 1000:
            milestoneEmoji = "🌶️"
            milestoneName = "Hot"
        case 15000:
            milestoneEmoji = "🚀"
            milestoneName = "Viral"
        default:
            print("⚠️ MILESTONE: Invalid milestone \(milestone)")
            return
        }
        
        print("\(milestoneEmoji) MILESTONE: Sending \(milestoneName) notification")
        
        let data: [String: Any] = [
            "milestone": milestone,
            "milestoneName": milestoneName,
            "milestoneEmoji": milestoneEmoji,
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
            print("✅ MILESTONE: \(milestoneName) notification sent")
        }
    }
    
    // MARK: - Stitch/Reply Notifications
    
    /// Send stitch/reply notifications with parent/child logic
    func sendStitchNotification(
        videoID: String,
        videoTitle: String,
        originalCreatorID: String,
        parentCreatorID: String?,
        threadUserIDs: [String]
    ) async throws {
        print("💬 STITCH: Sending reply/stitch notifications")
        
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
    
    // MARK: - Legacy Notification Sending
    
    /// Send engagement notification (hype/cool) - LEGACY
    func sendEngagementNotification(
        to recipientID: String,
        engagementType: String,
        videoTitle: String
    ) async throws {
        print("🔥 ENGAGEMENT: Sending \(engagementType) notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
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
    
    /// Send mention notification
    func sendMentionNotification(
        to recipientID: String,
        videoTitle: String,
        mentionContext: String
    ) async throws {
        print("📌 MENTION: Sending mention notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
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
    
    /// Send reply notification - LEGACY
    func sendReplyNotification(
        to recipientID: String,
        videoTitle: String
    ) async throws {
        print("💬 REPLY: Sending reply notification")
        
        let data: [String: Any] = [
            "recipientID": recipientID,
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
    
    // MARK: - Load Notifications
    
    func loadNotifications(
        for userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> NotificationLoadResult {
        
        print("📧 LOAD: Fetching \(limit) notifications for user \(userID)")
        
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
