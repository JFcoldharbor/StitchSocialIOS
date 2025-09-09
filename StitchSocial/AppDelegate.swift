//
//  AppDelegate.swift
//  CleanBeta
//
//  Created by James Garmon on 7/31/25.
//  COMPLETE: Firebase + FCM + Push Notifications Integration
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Debug Firebase configuration
        print("🔧 FIREBASE: Checking configuration...")
        
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("✅ FIREBASE: GoogleService-Info.plist found at: \(path)")
            
            // Check if plist can be read
            if let plist = NSDictionary(contentsOfFile: path) {
                if let projectId = plist["PROJECT_ID"] as? String {
                    print("✅ FIREBASE: Project ID: \(projectId)")
                } else {
                    print("❌ FIREBASE: No PROJECT_ID in plist")
                }
            } else {
                print("❌ FIREBASE: Cannot read GoogleService-Info.plist")
            }
        } else {
            print("❌ FIREBASE: GoogleService-Info.plist NOT FOUND!")
            print("📋 FIREBASE: Download from Firebase Console and add to Xcode project")
        }
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Verify Firebase is configured
        if let app = FirebaseApp.app() {
            print("✅ FIREBASE: App configured successfully - \(app.name)")
        } else {
            print("❌ FIREBASE: App configuration failed")
        }
        
        // Setup Firebase Cloud Messaging
        setupFirebaseMessaging()
        
        print("✅ APP DELEGATE: Complete initialization finished")
        
        return true
    }
    
    // MARK: - Firebase Messaging Setup
    
    /// Setup Firebase Cloud Messaging
    private func setupFirebaseMessaging() {
        print("📱 APP DELEGATE: 🔧 Setting up Firebase Messaging...")
        
        // Set messaging delegate
        Messaging.messaging().delegate = self
        
        // Request notification permissions
        Task { @MainActor in
            await requestNotificationPermissions()
        }
        
        print("📱 APP DELEGATE: ✅ Firebase Messaging setup initiated")
    }
    
    /// Request notification permissions
    @MainActor
    private func requestNotificationPermissions() async {
        do {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            print("📱 APP DELEGATE: Notification permissions granted: \(granted)")
            
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
            
        } catch {
            print("📱 APP DELEGATE: ❌ Permission request failed: \(error)")
        }
    }
    
    // MARK: - APNS Token Handling
    
    /// Handle APNS token registration success
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 APP DELEGATE: ✅ APNS token received: \(tokenString.prefix(20))...")
        
        // Set APNS token for Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
    }
    
    /// Handle APNS token registration failure
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("📱 APP DELEGATE: ❌ Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - Background Notification Handling
    
    /// Handle remote notification received (background/terminated app)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📱 APP DELEGATE: 📨 Remote notification received in background")
        
        // Process notification data
        handleBackgroundNotification(userInfo: userInfo)
        
        completionHandler(.newData)
    }
    
    /// Handle background notification processing
    private func handleBackgroundNotification(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? "general"
        let videoID = userInfo["videoID"] as? String
        let userID = userInfo["userID"] as? String
        
        print("📱 APP DELEGATE: 📨 Processing notification - Type: \(type)")
        
        // Process notification based on type
        if let videoID = videoID {
            print("📱 APP DELEGATE: Video notification for: \(videoID)")
            // TODO: Pre-load video data for faster navigation
        }
        if let userID = userID {
            print("📱 APP DELEGATE: User notification for: \(userID)")
            // TODO: Pre-load user profile data
        }
        
        // Update badge count or trigger local updates
        updateAppBadge(from: userInfo)
    }
    
    /// Update app badge count from notification
    private func updateAppBadge(from userInfo: [AnyHashable: Any]) {
        if let badgeCount = userInfo["badge"] as? Int {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
        }
    }
    
    // MARK: - App Lifecycle
    
    /// Handle app becoming active
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Clear badge count
        application.applicationIconBadgeNumber = 0
        print("📱 APP DELEGATE: App became active - badge cleared")
    }
    
    /// Handle app entering background
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 APP DELEGATE: App entered background")
    }
    
    /// Handle app termination
    func applicationWillTerminate(_ application: UIApplication) {
        print("📱 APP DELEGATE: App will terminate")
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    
    /// Called when FCM token is refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("📱 FCM: No token received")
            return
        }
        
        print("📱 FCM: Token received: \(token.prefix(20))...")
        
        // Store FCM token locally and defer Firestore storage until user is authenticated
        UserDefaults.standard.set(token, forKey: "fcm_token")
        
        // Only attempt to store in Firebase if user is authenticated
        if Auth.auth().currentUser != nil {
            Task {
                await storeFCMToken(token)
            }
        } else {
            print("📱 FCM: No authenticated user - token stored locally only")
        }
    }
    
    /// Store FCM token for the current user in Firebase
    private func storeFCMToken(_ token: String) async {
        // Verify user is still authenticated
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("📱 FCM: No authenticated user to store token")
            return
        }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Store in userTokens collection for NotificationService compatibility
            try await db.collection("userTokens").document(currentUserID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ], merge: true)
            
            // Also store in users collection
            try await db.collection("users").document(currentUserID).updateData([
                "fcmToken": token,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
                "deviceInfo": [
                    "platform": "iOS",
                    "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    "deviceModel": UIDevice.current.model,
                    "systemVersion": UIDevice.current.systemVersion
                ]
            ])
            
            print("📱 FCM: Token stored in Firebase successfully")
            
        } catch {
            print("📱 FCM: Failed to store token in Firebase: \(error)")
        }
    }
    
    /// Store FCM token after user authentication (called from auth flow)
    func storeFCMTokenForAuthenticatedUser() async {
        if let token = UserDefaults.standard.string(forKey: "fcm_token") {
            await storeFCMToken(token)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📱 NOTIFICATION: Received while app in foreground")
        
        let userInfo = notification.request.content.userInfo
        
        // Log notification details
        if let type = userInfo["type"] as? String {
            print("📱 NOTIFICATION: Type: \(type)")
        }
        
        // Show notification even when app is active
        completionHandler([.alert, .badge, .sound])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 NOTIFICATION: User tapped notification")
        
        let userInfo = response.notification.request.content.userInfo
        
        // Handle navigation based on notification payload
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    /// Handle notification tap navigation
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? "general"
        
        switch type {
        case "video", "engagement", "hype", "cool":
            if let videoID = userInfo["videoID"] as? String {
                print("🎬 NOTIFICATION: Navigate to video \(videoID)")
                // TODO: Use deep linking to navigate to specific video
                NotificationCenter.default.post(
                    name: .navigateToVideo,
                    object: nil,
                    userInfo: ["videoID": videoID]
                )
            }
            
        case "follow", "user":
            if let userID = userInfo["userID"] as? String {
                print("👤 NOTIFICATION: Navigate to user profile \(userID)")
                // TODO: Use deep linking to navigate to user profile
                NotificationCenter.default.post(
                    name: .navigateToProfile,
                    object: nil,
                    userInfo: ["userID": userID]
                )
            }
            
        case "thread", "reply":
            if let threadID = userInfo["threadID"] as? String {
                print("🧵 NOTIFICATION: Navigate to thread \(threadID)")
                // TODO: Use deep linking to navigate to thread
                NotificationCenter.default.post(
                    name: .navigateToThread,
                    object: nil,
                    userInfo: ["threadID": threadID]
                )
            }
            
        default:
            print("📱 NOTIFICATION: General notification tapped")
            // Navigate to notifications tab
            NotificationCenter.default.post(
                name: .navigateToNotifications,
                object: nil
            )
        }
    }
}

// MARK: - Deep Linking Support

extension Notification.Name {
    static let navigateToVideo = Notification.Name("navigateToVideo")
    static let navigateToProfile = Notification.Name("navigateToProfile")
    static let navigateToThread = Notification.Name("navigateToThread")
    static let navigateToNotifications = Notification.Name("navigateToNotifications")
}

// MARK: - Testing & Debug Methods

extension AppDelegate {
    
    /// Get current FCM token (for debugging)
    func getCurrentFCMToken() -> String? {
        return UserDefaults.standard.string(forKey: "fcm_token")
    }
    
    /// Check notification permission status
    func checkNotificationPermissionStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    /// Log current notification settings
    func logNotificationSettings() async {
        let status = await checkNotificationPermissionStatus()
        let token = getCurrentFCMToken()
        
        print("📱 NOTIFICATION DEBUG:")
        print("  - Permission status: \(status)")
        print("  - FCM token available: \(token != nil)")
        print("  - Token: \(token?.prefix(20) ?? "None")...")
    }
}
