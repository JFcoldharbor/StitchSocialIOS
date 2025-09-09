//
//  FCMPushManager.swift
//  CleanBeta
//
//  Layer 4: Core Services - Firebase Cloud Messaging Integration
//  FIXED: Includes FCM token in all notification documents
//

import Foundation
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import UserNotifications
import UIKit

/// Firebase Cloud Messaging manager for push notifications
/// FIXED: All notification documents now include FCM tokens
@MainActor
final class FCMPushManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = FCMPushManager()
    
    // MARK: - Dependencies
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let auth = Auth.auth()
    
    // MARK: - Published State
    @Published var fcmToken: String?
    @Published var isRegistered = false
    @Published var lastTokenRefresh: Date?
    @Published var pushNotificationCount = 0
    @Published var lastError: String?
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    
    // MARK: - Private State
    private var currentUserID: String?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        
        setupFCM()
        setupAuthListener()
        
        // Check initial permission status
        Task {
            await checkPermissionStatus()
        }
        
        print("📱 FCM PUSH MANAGER: ✅ Service initialized")
    }
    
    // MARK: - FCM Setup
        
    private func setupFCM() {
        // Set FCM delegate
        Messaging.messaging().delegate = self
        
        // Set UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self
        
        print("📱 FCM PUSH MANAGER: FCM delegates configured")
    }
    
    /// Request notification permissions and register for FCM
    func requestPermissionsAndRegister() async {
        do {
            // Request permissions with all options
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            
            await MainActor.run {
                self.permissionStatus = granted ? .authorized : .denied
            }
            
            print("📱 FCM PUSH MANAGER: Permission granted: \(granted)")
            
            if granted {
                // Register for remote notifications on main thread
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Wait a bit for APNS token, then refresh FCM token
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await refreshFCMToken()
            } else {
                print("📱 FCM PUSH MANAGER: ❌ Permission denied by user")
                lastError = "Notification permission denied"
            }
            
        } catch {
            print("📱 FCM PUSH MANAGER: ❌ Permission request failed: \(error)")
            lastError = "Permission request failed: \(error.localizedDescription)"
        }
    }
    
    /// Check current permission status
    func checkPermissionStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            self.permissionStatus = settings.authorizationStatus
        }
        
        print("📱 FCM PUSH MANAGER: Current permission status: \(settings.authorizationStatus.rawValue)")
    }
    
    /// Refresh FCM token manually
    private func refreshFCMToken() async {
        // Check if APNS token is available first
        guard Messaging.messaging().apnsToken != nil else {
            print("📱 FCM PUSH MANAGER: ⚠️ APNS token not available yet")
            // Try again in 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if Messaging.messaging().apnsToken == nil {
                print("📱 FCM PUSH MANAGER: ❌ APNS token still not available after wait")
                lastError = "APNS token not available"
                return
            }
            return
        }
        
        do {
            let token = try await Messaging.messaging().token()
            await MainActor.run {
                self.fcmToken = token
                self.lastTokenRefresh = Date()
            }
            
            if let userID = auth.currentUser?.uid {
                await storeFCMToken(token: token, userID: userID)
                isRegistered = true
            }
            
            print("📱 FCM PUSH MANAGER: 🔄 Token refreshed: \(token.prefix(20))...")
            
        } catch {
            print("📱 FCM PUSH MANAGER: ❌ Token refresh failed: \(error)")
            lastError = "Token refresh failed: \(error.localizedDescription)"
        }
    }
    
    /// Store FCM token in Firebase for the given user
    private func storeFCMToken(token: String, userID: String) async {
        do {
            // Store in users collection with device info
            try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData([
                "fcmToken": token,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
                "deviceInfo": [
                    "platform": "iOS",
                    "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    "deviceModel": UIDevice.current.model,
                    "systemVersion": UIDevice.current.systemVersion,
                    "bundleID": Bundle.main.bundleIdentifier ?? "unknown"
                ]
            ])
            
            // ALSO store in userTokens collection for NotificationService compatibility
            try await db.collection("userTokens").document(userID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "isActive": true
            ], merge: true)
            
            print("📱 FCM PUSH MANAGER: ✅ Token stored for user: \(userID)")
            
        } catch {
            print("📱 FCM PUSH MANAGER: ❌ Failed to store FCM token: \(error)")
            lastError = "Failed to store FCM token: \(error.localizedDescription)"
        }
    }
    
    // MARK: - SENDING FUNCTIONALITY - FIXED WITH TOKEN INCLUSION
    
    /// Send push notification with FCM token included in document
    func sendPushNotification(
        to userID: String,
        title: String,
        body: String,
        data: [String: Any] = [:]
    ) async -> Bool {
        
        print("📱 FCM DEBUG: Direct approach - sending to userID: \(userID)")
        print("📱 FCM DEBUG: Title: \(title)")
        
        // Get FCM token directly from Firestore first
        guard let fcmToken = await getFCMTokenDirect(for: userID) else {
            print("📱 FCM: No token found for user \(userID)")
            return false
        }
        
        // Create notification document with FCM token included
        let notificationID = "notif_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 100...999))"
        let notificationData: [String: Any] = [
            FirebaseSchema.NotificationDocument.id: notificationID,
            FirebaseSchema.NotificationDocument.recipientID: userID,
            FirebaseSchema.NotificationDocument.senderID: auth.currentUser?.uid ?? "system",
            FirebaseSchema.NotificationDocument.type: data["type"] as? String ?? "general",
            FirebaseSchema.NotificationDocument.title: title,
            FirebaseSchema.NotificationDocument.message: body,
            FirebaseSchema.NotificationDocument.payload: data,
            FirebaseSchema.NotificationDocument.isRead: false,
            FirebaseSchema.NotificationDocument.createdAt: FieldValue.serverTimestamp(),
            // CRITICAL FIX: Always include FCM token for Cloud Function
            "fcmToken": fcmToken,
            "pushStatus": "pending"
        ]
        
        do {
            try await db.collection(FirebaseSchema.Collections.notifications)
                .document(notificationID)
                .setData(notificationData)
            
            print("📱 FCM: ✅ Created notification document for \(userID)")
            print("📱 FCM: Token included: \(fcmToken.prefix(20))...")
            return true
            
        } catch {
            print("📱 FCM: ❌ Failed to create notification: \(error)")
            lastError = "Failed to create notification: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Get FCM token directly from Firestore
    private func getFCMTokenDirect(for userID: String) async -> String? {
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
    
    /// Send multiple notifications efficiently with tokens
    func sendBatchNotifications(_ notifications: [(userID: String, title: String, body: String, data: [String: Any])]) async {
        
        for notification in notifications {
            let success = await sendPushNotification(
                to: notification.userID,
                title: notification.title,
                body: notification.body,
                data: notification.data
            )
            
            if !success {
                print("📱 FCM: Batch notification failed for user \(notification.userID)")
            }
        }
        
        print("📱 FCM: Batch of \(notifications.count) notifications processed")
    }
    
    /// Send test notification to current user
    func sendTestNotification() async {
        guard let currentUserID = auth.currentUser?.uid else {
            print("📱 FCM: No authenticated user for test")
            return
        }
        
        let success = await sendPushNotification(
            to: currentUserID,
            title: "🔥 Test Notification",
            body: "Your push notifications are working perfectly!",
            data: ["type": "test", "timestamp": "\(Date().timeIntervalSince1970)"]
        )
        
        print("📱 FCM: Test notification \(success ? "sent successfully" : "failed")")
    }
    
    // MARK: - Auth State Management
    
    private func setupAuthListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    await self?.handleUserAuthenticated(userID: user.uid)
                } else {
                    await self?.handleUserSignedOut()
                }
            }
        }
    }
    
    /// Handle user authentication - register FCM token
    private func handleUserAuthenticated(userID: String) async {
        self.currentUserID = userID
        
        // Register FCM token for new user
        if let token = fcmToken {
            await storeFCMToken(token: token, userID: userID)
            isRegistered = true
        } else {
            await refreshFCMToken()
        }
        
        print("📱 FCM PUSH MANAGER: ✅ User authenticated - FCM registered")
    }
    
    /// Handle user sign out - clean up FCM token
    private func handleUserSignedOut() async {
        if let userID = currentUserID {
            // Mark token as inactive instead of deleting
            do {
                try await db.collection("userTokens").document(userID).updateData([
                    "isActive": false,
                    "deactivatedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                print("📱 FCM PUSH MANAGER: ❌ Failed to deactivate FCM token: \(error)")
            }
        }
        
        self.currentUserID = nil
        self.isRegistered = false
        
        print("📱 FCM PUSH MANAGER: ✅ User signed out - FCM token deactivated")
    }
    
    // MARK: - DEBUG METHODS
    
    /// Comprehensive notification debug flow
    func debugNotificationFlow() async {
        print("🔍 FCM DEBUG: Starting comprehensive notification flow test...")
        
        // 1. Check permissions in detail
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        print("🔍 FCM DEBUG: NOTIFICATION SETTINGS REPORT:")
        print("  - Authorization Status: \(settings.authorizationStatus.rawValue) (\(authStatusDescription(settings.authorizationStatus)))")
        print("  - Alert Setting: \(settings.alertSetting.rawValue)")
        print("  - Sound Setting: \(settings.soundSetting.rawValue)")
        print("  - Badge Setting: \(settings.badgeSetting.rawValue)")
        print("  - Notification Center: \(settings.notificationCenterSetting.rawValue)")
        print("  - Lock Screen: \(settings.lockScreenSetting.rawValue)")
        print("  - Car Play: \(settings.carPlaySetting.rawValue)")
        
        // 2. Check FCM token status
        print("🔍 FCM DEBUG: TOKEN STATUS:")
        print("  - FCM Token exists: \(fcmToken != nil)")
        print("  - Token: \(fcmToken?.prefix(30) ?? "None")...")
        print("  - Last refresh: \(lastTokenRefresh?.description ?? "Never")")
        print("  - Is registered: \(isRegistered)")
        
        // 3. Check APNS token
        let apnsToken = Messaging.messaging().apnsToken
        print("🔍 FCM DEBUG: APNS TOKEN:")
        print("  - APNS Token exists: \(apnsToken != nil)")
        
        // 4. Check authentication
        print("🔍 FCM DEBUG: AUTH STATUS:")
        print("  - User authenticated: \(auth.currentUser != nil)")
        print("  - Current user ID: \(currentUserID ?? "None")")
        
        // 5. Test local notification capability
        await testLocalNotification()
        
        // 6. Test FCM token retrieval
        if auth.currentUser != nil {
            print("🔍 FCM DEBUG: Testing notification send...")
            await sendTestNotification()
        }
        
        print("🔍 FCM DEBUG: Flow test complete ✅")
    }
    
    /// Test local notification to verify basic notification capability
    private func testLocalNotification() async {
        do {
            let content = UNMutableNotificationContent()
            content.title = "🧪 Local Test"
            content.body = "Testing local notifications"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: "local-test-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            
            try await UNUserNotificationCenter.current().add(request)
            print("🔍 FCM DEBUG: Local test notification scheduled")
            
        } catch {
            print("🔍 FCM DEBUG: Local notification failed: \(error)")
        }
    }
    
    /// Get human-readable authorization status
    private func authStatusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    /// Force refresh of everything
    func forceRefreshEverything() async {
        print("🔄 FCM DEBUG: Force refreshing everything...")
        
        await checkPermissionStatus()
        await refreshFCMToken()
        
        if permissionStatus != .authorized {
            print("⚠️ FCM DEBUG: Permissions not authorized, requesting again...")
            await requestPermissionsAndRegister()
        }
    }
    
    /// Get registration status for debugging
    func getRegistrationStatus() -> (isRegistered: Bool, hasToken: Bool, userID: String?, permissionStatus: UNAuthorizationStatus) {
        return (isRegistered, fcmToken != nil, currentUserID, permissionStatus)
    }
}

// MARK: - MessagingDelegate

extension FCMPushManager: MessagingDelegate {
    
    /// Called when FCM token is refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        
        Task { @MainActor in
            self.fcmToken = token
            self.lastTokenRefresh = Date()
            
            // Store token if user is authenticated
            if let userID = auth.currentUser?.uid {
                await storeFCMToken(token: token, userID: userID)
                self.isRegistered = true
            }
            
            print("📱 FCM PUSH MANAGER: 🔄 Token refreshed: \(token.prefix(20))...")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension FCMPushManager: UNUserNotificationCenterDelegate {
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        print("📱 FCM: 📨 Notification received in foreground")
        print("📱 FCM: Title: \(notification.request.content.title)")
        print("📱 FCM: Body: \(notification.request.content.body)")
        
        // Handle FCM data
        handleIncomingPushNotification(userInfo: userInfo)
        
        // Show notification even when app is in foreground with all options
        completionHandler([.alert, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 FCM: 👆 Notification tapped")
        
        // Handle notification tap action
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    /// Handle incoming push notification data
    private func handleIncomingPushNotification(userInfo: [AnyHashable: Any]) {
        pushNotificationCount += 1
        
        // Extract notification data
        let type = userInfo["type"] as? String ?? "general"
        let videoID = userInfo["videoID"] as? String
        let userID = userInfo["userID"] as? String
        
        // Post notification for other parts of the app to handle
        NotificationCenter.default.post(
            name: .pushNotificationReceived,
            object: nil,
            userInfo: [
                "type": type,
                "videoID": videoID as Any,
                "userID": userID as Any,
                "timestamp": Date(),
                "payload": userInfo
            ]
        )
        
        print("📱 FCM: ✅ Push notification processed: \(type)")
    }
    
    /// Handle notification tap action
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? "general"
        let videoID = userInfo["videoID"] as? String
        
        // Post notification for navigation handling
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: [
                "type": type,
                "videoID": videoID as Any,
                "timestamp": Date(),
                "payload": userInfo
            ]
        )
        
        print("📱 FCM: 🎯 Navigation triggered for: \(type)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushNotificationReceived = Notification.Name("pushNotificationReceived")
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
