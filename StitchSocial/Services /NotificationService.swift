//
//  NotificationService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Notification Management with Firebase
//  Dependencies: UserTier (Layer 1), Config (Layer 3), FirebaseSchema (Layer 3)
//  COMPLETE IMPLEMENTATION: Real Firebase integration, uses existing types
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Complete notification service with real Firebase integration
@MainActor
class NotificationService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var pendingToasts: [NotificationToast] = []
    
    // MARK: - Configuration
    
    private let toastDisplayDuration: TimeInterval = 4.0
    private let maxToastsDisplayed = 3
    private let notificationsCollection = "notifications"
    
    // MARK: - Initialization
    
    init() {
        print("🔔 NOTIFICATION SERVICE: Initialized with Firebase integration")
    }
    
    // MARK: - REAL FIREBASE IMPLEMENTATION
    
    /// Load notifications with actual Firebase pagination
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
            
            // Add pagination cursor if provided
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            let notifications = try snapshot.documents.compactMap { doc -> StitchNotification? in
                let data = doc.data()
                
                // Manual parsing to avoid Codable issues
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
            
            let hasMore = snapshot.documents.count == limit
            let lastDoc = snapshot.documents.last
            
            print("🔔 LOADED: \(notifications.count) notifications, hasMore: \(hasMore)")
            
            return NotificationLoadResult(
                notifications: notifications,
                lastDocument: lastDoc,
                hasMore: hasMore
            )
            
        } catch {
            print("❌ NOTIFICATION LOAD ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Mark notification as read with real Firebase update
    func markNotificationAsRead(notificationID: String) async throws {
        print("🔔 MARKING READ: \(notificationID)")
        
        do {
            try await db.collection(notificationsCollection)
                .document(notificationID)
                .updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ])
            
            print("✅ MARKED READ: \(notificationID)")
            
        } catch {
            print("❌ MARK READ ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Mark all notifications as read with real Firebase batch update
    func markAllNotificationsAsRead(for userID: String) async throws {
        print("🔔 MARKING ALL READ: \(userID)")
        
        do {
            // Get unread notifications
            let snapshot = try await db.collection(notificationsCollection)
                .whereField("recipientID", isEqualTo: userID)
                .whereField("isRead", isEqualTo: false)
                .getDocuments()
            
            // Batch update all unread notifications
            let batch = db.batch()
            
            for document in snapshot.documents {
                batch.updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ], forDocument: document.reference)
            }
            
            try await batch.commit()
            
            print("✅ MARKED ALL READ: \(snapshot.documents.count) notifications")
            
        } catch {
            print("❌ MARK ALL READ ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Get unread count with real Firebase count query
    func getUnreadCount(for userID: String) async throws -> Int {
        print("🔔 GETTING UNREAD COUNT: \(userID)")
        
        do {
            let snapshot = try await db.collection(notificationsCollection)
                .whereField("recipientID", isEqualTo: userID)
                .whereField("isRead", isEqualTo: false)
                .count
                .getAggregation(source: .server)
            
            let count = Int(snapshot.count)
            print("🔔 UNREAD COUNT: \(count)")
            return count
            
        } catch {
            print("❌ UNREAD COUNT ERROR: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Create notification with real Firebase write
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
            // Manual data creation to avoid Codable issues
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
                "expiresAt": notification.expiresAt ?? NSNull()
            ]
            
            try await db.collection(notificationsCollection)
                .document(notification.id)
                .setData(data)
            
            print("✅ CREATED: Notification \(notification.id)")
            
            // Show toast for immediate feedback if recipient is current user
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
    
    // MARK: - Toast Management (Real Implementation)
    
    /// Get toast display duration based on type
    private func getToastDuration(for type: StitchNotificationType) -> TimeInterval {
        switch type {
        case .hype, .cool: return 3.0
        case .follow: return 4.0
        case .reply, .mention: return 5.0
        case .tierUpgrade, .milestone: return 6.0
        case .system: return 8.0
        }
    }
    
    /// Show toast notification with real data and auto-dismiss
    func showToast(
        type: StitchNotificationType,
        title: String,
        message: String,
        senderUsername: String = "",
        payload: [String: String] = [:]
    ) {
        print("🍞 SHOWING TOAST: \(type.displayName) - \(title)")
        
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
                "newTier": newTier.rawValue
            ]
        )
    }
    
    // MARK: - Cleanup and Maintenance
    
    /// Clean up expired notifications
    func cleanupExpiredNotifications() async throws {
        print("🔔 CLEANUP: Starting expired notifications cleanup")
        
        do {
            let now = Date()
            let snapshot = try await db.collection(notificationsCollection)
                .whereField("expiresAt", isLessThan: now)
                .getDocuments()
            
            let batch = db.batch()
            
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            print("🔔 CLEANUP: Deleted \(snapshot.documents.count) expired notifications")
            
        } catch {
            print("❌ CLEANUP ERROR: \(error)")
            throw error
        }
    }
    
    // MARK: - Real-time Listeners (Production Ready)
    
    private var notificationListener: ListenerRegistration?
    
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
        
        showToast(
            type: notification.type,
            title: notification.title,
            message: notification.message,
            senderUsername: senderUsername,
            payload: notification.payload
        )
    }
}

// MARK: - Error Handling

extension NotificationService {
    enum NotificationError: LocalizedError {
        case userNotFound
        case invalidNotification
        case firebaseError(Error)
        
        var errorDescription: String? {
            switch self {
            case .userNotFound:
                return "User not found"
            case .invalidNotification:
                return "Invalid notification data"
            case .firebaseError(let error):
                return "Firebase error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Preview/Testing Support

extension NotificationService {
    /// Create sample notifications for testing
    static func createSampleNotifications(for userID: String) -> [StitchNotification] {
        return [
            StitchNotification(
                recipientID: userID,
                senderID: "user123",
                type: StitchNotificationType.hype,
                title: "🔥 Your video got hyped!",
                message: "testuser hyped your video 'Cool Dance'",
                payload: ["senderUsername": "testuser", "videoTitle": "Cool Dance"]
            ),
            StitchNotification(
                recipientID: userID,
                senderID: "user456",
                type: StitchNotificationType.follow,
                title: "👥 New Follower",
                message: "newuser started following you",
                payload: ["senderUsername": "newuser"]
            ),
            StitchNotification(
                recipientID: userID,
                senderID: "system",
                type: StitchNotificationType.tierUpgrade,
                title: "🎉 Tier Upgraded!",
                message: "You've reached Rising tier!",
                payload: ["newTier": "rising"]
            )
        ]
    }
}
