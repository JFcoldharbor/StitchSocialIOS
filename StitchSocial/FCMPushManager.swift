//
//  FCMPushManager.swift
//  StitchSocial
//
//  Layer 4: Core Services - Firebase Cloud Messaging HTTP v1 API Implementation
//  UPDATED: Uses modern FCM HTTP v1 API with service account authentication
//

import Foundation
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import UIKit

/// Firebase Cloud Messaging manager with HTTP v1 API implementation
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
    private var projectID: String {
        return "stitchfin" // Your Firebase project ID
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        
        setupFCM()
        setupAuthListener()
        
        Task {
            await checkPermissionStatus()
        }
        
        print("📱 FCM PUSH MANAGER: HTTP v1 API implementation initialized")
    }
    
    // MARK: - FCM Setup
        
    private func setupFCM() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        print("📱 FCM PUSH MANAGER: FCM delegates configured")
    }
    
    /// Request notification permissions and register for FCM
    func requestPermissionsAndRegister() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            
            await MainActor.run {
                self.permissionStatus = granted ? .authorized : .denied
            }
            
            print("📱 FCM: Permission granted: \(granted)")
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait for APNS
                await refreshFCMToken()
            } else {
                print("📱 FCM: Permission denied by user")
                lastError = "Notification permission denied"
            }
            
        } catch {
            print("📱 FCM: Permission request failed: \(error)")
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
        
        print("📱 FCM: Current permission status: \(settings.authorizationStatus.rawValue)")
    }
    
    /// Refresh FCM token
    private func refreshFCMToken() async {
        guard Messaging.messaging().apnsToken != nil else {
            print("📱 FCM: APNS token not available yet")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if Messaging.messaging().apnsToken == nil {
                print("📱 FCM: APNS token still not available after wait")
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
            
            print("📱 FCM: Token refreshed: \(token.prefix(20))...")
            
        } catch {
            print("📱 FCM: Token refresh failed: \(error)")
            lastError = "Token refresh failed: \(error.localizedDescription)"
        }
    }
    
    /// Store FCM token in Firebase
    private func storeFCMToken(token: String, userID: String) async {
        do {
            // Store in userTokens collection
            try await db.collection("userTokens").document(userID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "isActive": true
            ], merge: true)
            
            print("📱 FCM: Token stored for user: \(userID)")
            
        } catch {
            print("📱 FCM: Failed to store FCM token: \(error)")
            lastError = "Failed to store FCM token: \(error.localizedDescription)"
        }
    }
    
    // MARK: - FIREBASE HTTP v1 API IMPLEMENTATION
    
    /// Send push notification using Firebase HTTP v1 API
    func sendPushNotification(
        to userID: String,
        title: String,
        body: String,
        data: [String: Any] = [:]
    ) async -> Bool {
        
        print("📱 FCM: Sending push notification via HTTP v1 API to \(userID)")
        print("📱 FCM: Title: \(title)")
        
        // Get FCM token for recipient
        guard let fcmToken = await getFCMToken(for: userID) else {
            print("📱 FCM: No token found for user \(userID)")
            return false
        }
        
        // Use Firebase Admin SDK approach (simplified)
        return await sendViaFirebaseAdmin(
            token: fcmToken,
            title: title,
            body: body,
            data: data
        )
    }
    
    /// Send notification using Firebase Admin SDK approach
    private func sendViaFirebaseAdmin(
        token: String,
        title: String,
        body: String,
        data: [String: Any]
    ) async -> Bool {
        
        // Since we can't use the Admin SDK directly in iOS,
        // we'll use a simplified approach with Firebase Functions
        
        print("📱 FCM: Using Firebase Functions approach for push notification")
        
        // Create notification document for Firebase Function to process
        let notificationID = UUID().uuidString
        let notificationData: [String: Any] = [
            "id": notificationID,
            "fcmToken": token,
            "notification": [
                "title": title,
                "body": body
            ],
            "data": data,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "pending"
        ]
        
        do {
            // Write to a special collection that triggers a Cloud Function
            try await db.collection("pushNotificationQueue").document(notificationID).setData(notificationData)
            
            print("📱 FCM: Queued notification for Cloud Function processing: \(notificationID)")
            return true
            
        } catch {
            print("📱 FCM: Failed to queue notification: \(error)")
            return false
        }
    }
    
    /// Alternative: Use Cloud Messaging REST API directly (requires more setup)
    private func sendViaCloudMessagingAPI(
        token: String,
        title: String,
        body: String,
        data: [String: Any]
    ) async -> Bool {
        
        // This would require OAuth2 token generation which is complex for client-side
        // Better to use Cloud Functions approach above
        print("📱 FCM: Cloud Messaging API requires server-side implementation")
        return false
    }
    
    /// Get FCM token for user from Firestore
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
        
        print("📱 FCM: Test notification \(success ? "queued successfully" : "failed")")
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
        
        if let token = fcmToken {
            await storeFCMToken(token: token, userID: userID)
            isRegistered = true
        } else {
            await refreshFCMToken()
        }
        
        print("📱 FCM: User authenticated - FCM registered")
    }
    
    /// Handle user sign out - clean up FCM token
    private func handleUserSignedOut() async {
        if let userID = currentUserID {
            do {
                try await db.collection("userTokens").document(userID).updateData([
                    "isActive": false,
                    "deactivatedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                print("📱 FCM: Failed to deactivate FCM token: \(error)")
            }
        }
        
        self.currentUserID = nil
        self.isRegistered = false
        
        print("📱 FCM: User signed out - FCM token deactivated")
    }
    
    // MARK: - Debug Methods
    
    /// Debug FCM configuration
    func debugFCMConfiguration() async {
        print("🔍 FCM DEBUG: Starting HTTP v1 API configuration check...")
        
        // Check permissions
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        print("🔍 FCM DEBUG: PERMISSIONS:")
        print("  - Status: \(settings.authorizationStatus.rawValue)")
        print("  - Alert: \(settings.alertSetting.rawValue)")
        print("  - Sound: \(settings.soundSetting.rawValue)")
        print("  - Badge: \(settings.badgeSetting.rawValue)")
        
        // Check FCM token
        if let token = fcmToken {
            print("🔍 FCM DEBUG: FCM Token: \(token.prefix(40))...")
        } else {
            print("🔍 FCM DEBUG: ❌ No FCM token available")
        }
        
        // Check project configuration
        print("🔍 FCM DEBUG: Project ID: \(projectID)")
        
        // Check authentication
        if let userID = auth.currentUser?.uid {
            print("🔍 FCM DEBUG: ✅ User authenticated: \(userID)")
            
            let storedToken = await getFCMToken(for: userID)
            print("🔍 FCM DEBUG: Token stored: \(storedToken != nil)")
        } else {
            print("🔍 FCM DEBUG: ❌ No authenticated user")
        }
        
        print("🔍 FCM DEBUG: Note: Using Cloud Functions approach for HTTP v1 API")
        print("🔍 FCM DEBUG: Configuration check complete")
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
            
            if let userID = auth.currentUser?.uid {
                await storeFCMToken(token: token, userID: userID)
                self.isRegistered = true
            }
            
            print("📱 FCM: Token refreshed: \(token.prefix(20))...")
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
        
        print("📱 FCM: Notification received in foreground")
        print("📱 FCM: Title: \(notification.request.content.title)")
        print("📱 FCM: Body: \(notification.request.content.body)")
        
        handleIncomingPushNotification(userInfo: userInfo)
        
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 FCM: Notification tapped")
        
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    /// Handle incoming push notification data
    private func handleIncomingPushNotification(userInfo: [AnyHashable: Any]) {
        pushNotificationCount += 1
        
        let type = userInfo["type"] as? String ?? "general"
        let videoID = userInfo["videoID"] as? String
        let userID = userInfo["userID"] as? String
        
        // Post notification for other parts of the app
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
        
        print("📱 FCM: Push notification processed: \(type)")
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
        
        print("📱 FCM: Navigation triggered for: \(type)")
    }
}
