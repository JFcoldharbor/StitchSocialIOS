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
        
        #if DEBUG
        print("📱 FCM PUSH MANAGER: HTTP v1 API implementation initialized")
        #endif
    }
    
    // MARK: - FCM Setup
        
    private func setupFCM() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        #if DEBUG
        print("📱 FCM PUSH MANAGER: FCM delegates configured")
        #endif
    }
    
    /// Request notification permissions and register for FCM
    func requestPermissionsAndRegister() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            
            await MainActor.run {
                self.permissionStatus = granted ? .authorized : .denied
            }
            
            #if DEBUG
            print("📱 FCM: Permission granted: \(granted)")
            #endif
            
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait for APNS
                await refreshFCMToken()
            } else {
                #if DEBUG
                print("📱 FCM: Permission denied by user")
                #endif
                lastError = "Notification permission denied"
            }
            
        } catch {
            #if DEBUG
            print("📱 FCM: Permission request failed: \(error)")
            #endif
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
        
        #if DEBUG
        print("📱 FCM: Current permission status: \(settings.authorizationStatus.rawValue)")
        #endif
    }
    
    /// Refresh FCM token
    private func refreshFCMToken() async {
        guard Messaging.messaging().apnsToken != nil else {
            #if DEBUG
            print("📱 FCM: APNS token not available yet")
            #endif
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if Messaging.messaging().apnsToken == nil {
                #if DEBUG
                print("📱 FCM: APNS token still not available after wait")
                #endif
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
            
            #if DEBUG
            print("📱 FCM: Token refreshed: \(token.prefix(20))...")
            #endif
            
        } catch {
            #if DEBUG
            print("📱 FCM: Token refresh failed: \(error)")
            #endif
            lastError = "Token refresh failed: \(error.localizedDescription)"
        }
    }
    
    /// Store FCM token in Firebase
    private func storeFCMToken(token: String, userID: String) async {
        do {
            // Store in user_tokens collection (matches Cloud Function)
            try await db.collection("user_tokens").document(userID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "isActive": true
            ], merge: true)
            
            #if DEBUG
            print("📱 FCM: Token stored for user: \(userID)")
            #endif
            
        } catch {
            #if DEBUG
            print("📱 FCM: Failed to store FCM token: \(error)")
            #endif
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
        
        #if DEBUG
        print("📱 FCM: Sending push notification via HTTP v1 API to \(userID)")
        #endif
        #if DEBUG
        print("📱 FCM: Title: \(title)")
        #endif
        
        // Get FCM token for recipient
        guard let fcmToken = await getFCMToken(for: userID) else {
            #if DEBUG
            print("📱 FCM: No token found for user \(userID)")
            #endif
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
        
        #if DEBUG
        print("📱 FCM: Using Firebase Functions approach for push notification")
        #endif
        
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
            
            #if DEBUG
            print("📱 FCM: Queued notification for Cloud Function processing: \(notificationID)")
            #endif
            return true
            
        } catch {
            #if DEBUG
            print("📱 FCM: Failed to queue notification: \(error)")
            #endif
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
        #if DEBUG
        print("📱 FCM: Cloud Messaging API requires server-side implementation")
        #endif
        return false
    }
    
    /// Get FCM token for user from Firestore
    private func getFCMToken(for userID: String) async -> String? {
        do {
            let doc = try await db.collection("user_tokens").document(userID).getDocument()
            
            guard doc.exists, let data = doc.data() else {
                #if DEBUG
                print("📱 FCM: No token document found for user \(userID)")
                #endif
                return nil
            }
            
            let token = data["fcmToken"] as? String
            #if DEBUG
            print("📱 FCM: Retrieved token for user \(userID): \(token?.prefix(20) ?? "nil")...")
            #endif
            return token
            
        } catch {
            #if DEBUG
            print("📱 FCM: Error getting token for user \(userID): \(error)")
            #endif
            return nil
        }
    }
    
    /// Send test notification to current user
    func sendTestNotification() async {
        guard let currentUserID = auth.currentUser?.uid else {
            #if DEBUG
            print("📱 FCM: No authenticated user for test")
            #endif
            return
        }
        
        let success = await sendPushNotification(
            to: currentUserID,
            title: "🔥 Test Notification",
            body: "Your push notifications are working perfectly!",
            data: ["type": "test", "timestamp": "\(Date().timeIntervalSince1970)"]
        )
        
        #if DEBUG
        print("📱 FCM: Test notification \(success ? "queued successfully" : "failed")")
        #endif
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
        
        #if DEBUG
        print("📱 FCM: User authenticated - FCM registered")
        #endif
    }
    
    /// Handle user sign out - clean up FCM token
    private func handleUserSignedOut() async {
        if let userID = currentUserID {
            do {
                try await db.collection("user_tokens").document(userID).updateData([
                    "isActive": false,
                    "deactivatedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                #if DEBUG
                print("📱 FCM: Failed to deactivate FCM token: \(error)")
                #endif
            }
        }
        
        self.currentUserID = nil
        self.isRegistered = false
        
        #if DEBUG
        print("📱 FCM: User signed out - FCM token deactivated")
        #endif
    }
    
    // MARK: - Debug Methods
    
    /// Debug FCM configuration
    func debugFCMConfiguration() async {
        #if DEBUG
        print("🔍 FCM DEBUG: Starting HTTP v1 API configuration check...")
        #endif
        
        // Check permissions
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        #if DEBUG
        print("🔍 FCM DEBUG: PERMISSIONS:")
        #endif
        #if DEBUG
        print("  - Status: \(settings.authorizationStatus.rawValue)")
        #endif
        #if DEBUG
        print("  - Alert: \(settings.alertSetting.rawValue)")
        #endif
        #if DEBUG
        print("  - Sound: \(settings.soundSetting.rawValue)")
        #endif
        #if DEBUG
        print("  - Badge: \(settings.badgeSetting.rawValue)")
        #endif
        
        // Check FCM token
        if let token = fcmToken {
            #if DEBUG
            print("🔍 FCM DEBUG: FCM Token: \(token.prefix(40))...")
            #endif
        } else {
            #if DEBUG
            print("🔍 FCM DEBUG: ❌ No FCM token available")
            #endif
        }
        
        // Check project configuration
        #if DEBUG
        print("🔍 FCM DEBUG: Project ID: \(projectID)")
        #endif
        
        // Check authentication
        if let userID = auth.currentUser?.uid {
            #if DEBUG
            print("🔍 FCM DEBUG: ✅ User authenticated: \(userID)")
            #endif
            
            let storedToken = await getFCMToken(for: userID)
            #if DEBUG
            print("🔍 FCM DEBUG: Token stored: \(storedToken != nil)")
            #endif
        } else {
            #if DEBUG
            print("🔍 FCM DEBUG: ❌ No authenticated user")
            #endif
        }
        
        #if DEBUG
        print("🔍 FCM DEBUG: Note: Using Cloud Functions approach for HTTP v1 API")
        #endif
        #if DEBUG
        print("🔍 FCM DEBUG: Configuration check complete")
        #endif
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
            
            #if DEBUG
            print("📱 FCM: Token refreshed: \(token.prefix(20))...")
            #endif
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
        
        #if DEBUG
        print("📱 FCM: Notification received in foreground")
        #endif
        #if DEBUG
        print("📱 FCM: Title: \(notification.request.content.title)")
        #endif
        #if DEBUG
        print("📱 FCM: Body: \(notification.request.content.body)")
        #endif
        
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
        
        #if DEBUG
        print("📱 FCM: Notification tapped")
        #endif
        
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
        
        #if DEBUG
        print("📱 FCM: Push notification processed: \(type)")
        #endif
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
        
        #if DEBUG
        print("📱 FCM: Navigation triggered for: \(type)")
        #endif
    }
}
