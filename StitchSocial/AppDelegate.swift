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
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
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
        
        // Add your notification processing logic here
        if let videoID = videoID {
            print("📱 APP DELEGATE: Video notification for: \(videoID)")
        }
        if let userID = userID {
            print("📱 APP DELEGATE: User notification for: \(userID)")
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
        
        // Store FCM token - you can integrate with your user service here
        Task {
            await storeFCMToken(token)
        }
    }
    
    /// Store FCM token for the current user
    private func storeFCMToken(_ token: String) async {
        // Add your token storage logic here
        // Example: Store in UserDefaults for now
        UserDefaults.standard.set(token, forKey: "fcm_token")
        print("📱 FCM: Token stored successfully")
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
        if let videoID = userInfo["videoID"] as? String {
            print("🎬 NOTIFICATION: Navigate to video \(videoID)")
            // TODO: Navigate to specific video
        } else if let userID = userInfo["userID"] as? String {
            print("👤 NOTIFICATION: Navigate to user profile \(userID)")
            // TODO: Navigate to user profile
        }
        
        completionHandler()
    }
}
