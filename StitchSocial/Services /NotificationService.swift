//
//  NotificationService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Notification Management with Cloud Functions
//  Dependencies: UserTier (Layer 1), Config (Layer 3), FirebaseSchema (Layer 3)
//  COMPLETE: Firebase Cloud Functions integration for push notifications
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging

/// Notification service with Firebase Cloud Functions for push notifications
@MainActor
class NotificationService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let functions = Functions.functions()
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var pendingToasts: [NotificationToast] = []
    
    // MARK: - Real-time Listener
    
    private var notificationListener: ListenerRegistration?
    
    // MARK: - Configuration
    
    private let toastDisplayDuration: TimeInterval = 4.0
    private let maxToastsDisplayed = 3
    private let notificationsCollection = "notifications"
    
    // MARK: - Initialization
    
    init() {
        print("🔔 NOTIFICATION SERVICE: Initialized with Cloud Functions integration")
    }
    
    // MARK: - FIREBASE IMPLEMENTATION WITH CLOUD FUNCTIONS
    
    /// Load notifications with Firebase pagination
    func loadNotifications(
        for userID: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> NotificationLoadResult {
        print("🔔 LOADING: Notifications for user \(userID)")
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            var query = db.collection(notificationsCollection)
                .whereField("recipientID", isEqualTo: userID)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
            
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            let notifications = try snapshot.documents.compactMap { doc -> StitchNotification? in
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
                    expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
                )
            }
            
            let hasMore = notifications.count == limit
            let lastDoc = hasMore ? snapshot.documents.last : nil
            
            print("🔔 LOADED: \(notifications.count) notifications")
            return NotificationLoadResult(
                notifications: notifications,
                lastDocument: lastDoc,
                hasMore: hasMore
            )
            
        } catch {
            print("❌ LOAD NOTIFICATIONS ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    // MARK: - Create Notifications with FCM Token for Cloud Function
    
    /// Create notification that includes FCM token for Cloud Function processing
    func createNotification(
        recipientID: String,
        senderID: String,
        type: StitchNotificationType,
        title: String,
        message: String,
        payload: [String: String] = [:]
    ) async throws {
        print("🔔 CREATING: \(type.rawValue) notification from \(senderID) to \(recipientID)")
        
        // Don't send notification to self
        guard senderID != recipientID else { return }
        
        // Get recipient's FCM token first
        let fcmToken = await getFCMToken(for: recipientID)
        
        let notification = StitchNotification(
            recipientID: recipientID,
            senderID: senderID,
            type: type,
            title: title,
            message: message,
            payload: payload,
            expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        )
        
        do {
            // Create notification document with FCM token - Cloud Function will auto-send push
            let data: [String: Any] = [
                "id": notification.id,
                "recipientID": notification.recipientID,
                "senderID": notification.senderID,
                "type": notification.type.rawValue,
                "title": notification.title,
                "message": notification.message,
                "payload": notification.payload,
                "isRead": notification.isRead,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": notification.expiresAt ?? NSNull(),
                "fcmToken": fcmToken ?? "", // Cloud Function needs this
                "pushStatus": "pending" // Cloud Function will update this
            ]
            
            try await db.collection(notificationsCollection)
                .document(notification.id)
                .setData(data)
            
            print("✅ CREATED: Notification \(notification.id) with FCM token - Cloud Function will handle push")
            
            // Show immediate in-app toast if recipient is current user
            if recipientID == Auth.auth().currentUser?.uid {
                let senderUsername = payload["senderUsername"] ?? "Someone"
                showToast(
                    type: type,
                    title: title,
                    message: message,
                    senderUsername: senderUsername,
                    payload: payload
                )
            }
            
        } catch {
            print("❌ CREATE NOTIFICATION ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    // MARK: - FCM Token Management
    
    /// Store FCM token for user (called by AuthService)
    func storeFCMToken(for userID: String) async throws {
        do {
            // Get current FCM token from Firebase Messaging
            let token = try await Messaging.messaging().token()
            
            // Store in userTokens collection
            try await db.collection("userTokens").document(userID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "isActive": true
            ], merge: true)
            
            print("✅ FCM: Token stored for user \(userID)")
            
        } catch {
            print("❌ FCM: Failed to store token for user \(userID): \(error)")
            throw error
        }
    }
    
    /// Get FCM token for user from userTokens collection
    private func getFCMToken(for userID: String) async -> String? {
        do {
            let doc = try await db.collection("userTokens").document(userID).getDocument()
            
            guard doc.exists, let data = doc.data() else {
                print("📱 FCM: No token document found for user \(userID)")
                return nil
            }
            
            let token = data["fcmToken"] as? String
            print("📱 FCM: Retrieved token for user \(userID): \(token?.prefix(20) ?? "nil")...")
            return token
            
        } catch {
            print("📱 FCM: Error getting token for user \(userID): \(error)")
            return nil
        }
    }
    
    // MARK: - Test Notification via Cloud Function
    
    /// Send test notification using your existing Cloud Function
    func sendTestNotification() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NotificationError.userNotFound
        }
        
        do {
            let callable = functions.httpsCallable("sendTestNotification")
            let result = try await callable.call([
                "recipientID": currentUser.uid,
                "title": "🔥 Test Notification",
                "body": "Your push notifications are working perfectly!"
            ])
            
            print("✅ FCM: Test notification sent via Cloud Function")
            
        } catch {
            print("❌ FCM: Failed to send test notification: \(error)")
            throw error
        }
    }
    
    // MARK: - Mark as Read (Multiple Method Names for Compatibility)
    
    /// Mark notification as read
    func markAsRead(notificationID: String) async throws {
        do {
            try await db.collection(notificationsCollection)
                .document(notificationID)
                .updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ])
            
            print("✅ MARKED AS READ: \(notificationID)")
            
        } catch {
            print("❌ MARK AS READ ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Mark notification as read (alternative method name for ViewModel compatibility)
    func markNotificationAsRead(notificationID: String) async throws {
        try await markAsRead(notificationID: notificationID)
    }
    
    /// Mark all notifications as read for user
    func markAllAsRead(for userID: String) async throws {
        do {
            let unreadQuery = db.collection(notificationsCollection)
                .whereField("recipientID", isEqualTo: userID)
                .whereField("isRead", isEqualTo: false)
            
            let snapshot = try await unreadQuery.getDocuments()
            
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            print("✅ MARKED ALL AS READ: \(snapshot.documents.count) notifications")
            
        } catch {
            print("❌ MARK ALL AS READ ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Mark all notifications as read (alternative method name for ViewModel compatibility)
    func markAllNotificationsAsRead(for userID: String) async throws {
        try await markAllAsRead(for: userID)
    }
    
    /// Get unread notification count for user
    func getUnreadCount(for userID: String) async throws -> Int {
        do {
            let unreadQuery = db.collection(notificationsCollection)
                .whereField("recipientID", isEqualTo: userID)
                .whereField("isRead", isEqualTo: false)
            
            let snapshot = try await unreadQuery.getDocuments()
            return snapshot.documents.count
            
        } catch {
            print("❌ GET UNREAD COUNT ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    // MARK: - Real-time Listener
    
    /// Start real-time notification listener
    func startNotificationListener(for userID: String) {
        print("🔔 STARTING: Real-time listener for \(userID)")
        
        notificationListener = db.collection(notificationsCollection)
            .whereField("recipientID", isEqualTo: userID)
            .whereField("isRead", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ LISTENER ERROR: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Handle new notifications
                for change in snapshot.documentChanges {
                    if change.type == .added {
                        let data = change.document.data()
                        let notification = StitchNotification(
                            id: data["id"] as? String ?? change.document.documentID,
                            recipientID: data["recipientID"] as? String ?? "",
                            senderID: data["senderID"] as? String ?? "",
                            type: StitchNotificationType(rawValue: data["type"] as? String ?? "system") ?? .system,
                            title: data["title"] as? String ?? "",
                            message: data["message"] as? String ?? "",
                            payload: data["payload"] as? [String: String] ?? [:],
                            isRead: data["isRead"] as? Bool ?? false,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
                        )
                        
                        Task { @MainActor in
                            self?.handleNewNotification(notification)
                        }
                    }
                }
            }
    }
    
    /// Stop notification listener
    func stopNotificationListener() {
        notificationListener?.remove()
        notificationListener = nil
        print("🔔 STOPPED: Real-time listener")
    }
    
    /// Handle new notification from real-time listener
    private func handleNewNotification(_ notification: StitchNotification) {
        print("🔔 NEW NOTIFICATION: \(notification.type.rawValue)")
        
        let senderUsername = notification.payload["senderUsername"] ?? "Someone"
        
        // Show toast notification
        showToast(
            type: notification.type,
            title: notification.title,
            message: notification.message,
            senderUsername: senderUsername,
            payload: notification.payload
        )
    }
    
    // MARK: - Toast Notifications
    
    /// Show toast notification overlay
    private func showToast(
        type: StitchNotificationType,
        title: String,
        message: String,
        senderUsername: String,
        payload: [String: String]
    ) {
        let toast = NotificationToast(
            type: type,
            title: title,
            message: message,
            senderUsername: senderUsername,
            payload: payload
        )
        
        // Add to pending toasts
        pendingToasts.append(toast)
        
        // Limit number of toasts displayed
        if pendingToasts.count > maxToastsDisplayed {
            pendingToasts.removeFirst()
        }
        
        // Auto-dismiss after duration
        Task {
            let duration = getToastDuration(for: type)
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismissToast(toastID: toast.id)
        }
    }
    
    /// Dismiss specific toast
    func dismissToast(toastID: String) {
        pendingToasts.removeAll { $0.id == toastID }
        print("🍞 DISMISSED TOAST: \(toastID)")
    }
    
    /// Clear all toasts
    func clearAllToasts() {
        pendingToasts.removeAll()
        print("🍞 CLEARED ALL TOASTS")
    }
    
    /// Get toast duration based on type
    private func getToastDuration(for type: StitchNotificationType) -> TimeInterval {
        switch type {
        case .hype, .cool: return 3.0
        case .follow: return 4.0
        case .reply, .mention: return 5.0
        case .tierUpgrade, .milestone: return 6.0
        case .system: return 8.0
        }
    }
    
    // MARK: - Convenience Methods for Common Notifications
    
    /// Create hype notification
    func notifyHype(videoID: String, videoTitle: String, recipientID: String, senderID: String, senderUsername: String) async throws {
        try await createNotification(
            recipientID: recipientID,
            senderID: senderID,
            type: StitchNotificationType.hype,
            title: "🔥 Your video got hyped!",
            message: "\(senderUsername) hyped your video",
            payload: [
                "videoID": videoID,
                "videoTitle": videoTitle,
                "senderUsername": senderUsername
            ]
        )
    }
    
    /// Create follow notification
    func notifyFollow(recipientID: String, senderID: String, senderUsername: String) async throws {
        try await createNotification(
            recipientID: recipientID,
            senderID: senderID,
            type: StitchNotificationType.follow,
            title: "👥 New Follower",
            message: "\(senderUsername) started following you",
            payload: [
                "senderUsername": senderUsername
            ]
        )
    }
    
    /// Create reply notification
    func notifyReply(videoID: String, videoTitle: String, recipientID: String, senderID: String, senderUsername: String) async throws {
        try await createNotification(
            recipientID: recipientID,
            senderID: senderID,
            type: StitchNotificationType.reply,
            title: "💬 New Reply",
            message: "\(senderUsername) replied to your video",
            payload: [
                "videoID": videoID,
                "videoTitle": videoTitle,
                "senderUsername": senderUsername
            ]
        )
    }
    
    /// Create tier upgrade notification
    func notifyTierUpgrade(userID: String, newTier: UserTier) async throws {
        try await createNotification(
            recipientID: userID,
            senderID: "system",
            type: StitchNotificationType.tierUpgrade,
            title: "🎉 Tier Upgraded!",
            message: "You've reached \(newTier.displayName) tier!",
            payload: [
                "newTier": newTier.rawValue,
                "tierName": newTier.displayName
            ]
        )
    }
    
    // MARK: - Error Handling
    
    enum NotificationError: Error, LocalizedError {
        case invalidNotification
        case userNotFound
        case firebaseError(Error)
        
        var errorDescription: String? {
            switch self {
            case .invalidNotification:
                return "Invalid notification data"
            case .userNotFound:
                return "User not found"
            case .firebaseError(let error):
                return "Firebase error: \(error.localizedDescription)"
            }
        }
    }
}
