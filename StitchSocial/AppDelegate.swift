//
//  AppDelegate.swift
//  CleanBeta
//
//  Created by James Garmon on 7/31/25.
//  COMPLETE: Firebase + FCM + Push Notifications + Re-Engagement Integration
//  ADDED: Background task scheduling for re-engagement checks
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    
    // MARK: - Background Task Identifiers
    
    private let reEngagementTaskID = "com.stitch.reengagement"
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Debug Firebase configuration
        print("🔧 FIREBASE: Checking configuration...")
        
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("✅ FIREBASE: GoogleService-Info.plist found at: \(path)")
            
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
        
        // Setup Background Tasks
        setupBackgroundTasks()
        
        // TEMP: Force backfill to run again (REMOVE AFTER ONE RUN)
        UserDefaults.standard.removeObject(forKey: "creatorNameBackfillComplete")
        print("🔄 BACKFILL: Forcing re-run (flag cleared)")
        
        // 🔥 ONE-TIME BACKFILL: Fix empty creatorName fields (only runs once)
        if !UserDefaults.standard.bool(forKey: "creatorNameBackfillComplete") {
            Task {
                // Wait for user authentication before running backfill
                var attempts = 0
                while Auth.auth().currentUser == nil && attempts < 10 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                    attempts += 1
                }
                
                if Auth.auth().currentUser != nil {
                    await backfillEmptyCreatorNames()
                } else {
                    print("⚠️ BACKFILL: Skipped - no authenticated user yet (will retry on next launch)")
                }
            }
        } else {
            print("✅ BACKFILL: Already completed - skipping")
        }
        
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
    
    // MARK: - Background Tasks Setup
    
    /// Setup background task handlers
    private func setupBackgroundTasks() {
        print("⏰ BACKGROUND TASKS: Setting up handlers...")
        
        // Register re-engagement background task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: reEngagementTaskID,
            using: nil
        ) { task in
            self.handleReEngagementTask(task: task as! BGAppRefreshTask)
        }
        
        print("✅ BACKGROUND TASKS: Registered re-engagement handler")
    }
    
    /// Handle re-engagement background task
    private func handleReEngagementTask(task: BGAppRefreshTask) {
        print("🔄 RE-ENGAGEMENT TASK: Starting background check...")
        
        // Schedule next task
        scheduleReEngagementCheck()
        
        // Create async task
        let taskWork = Task {
            guard let userID = Auth.auth().currentUser?.uid else {
                print("⚠️ RE-ENGAGEMENT TASK: No authenticated user")
                task.setTaskCompleted(success: true)
                return
            }
            
            do {
                // Create service instances
                let videoService = VideoService()
                let userService = UserService()
                let reEngagementService = ReEngagementService(
                    videoService: videoService,
                    userService: userService
                )
                
                // Run check
                try await reEngagementService.checkReEngagement(userID: userID)
                
                print("✅ RE-ENGAGEMENT TASK: Check completed successfully")
                task.setTaskCompleted(success: true)
                
            } catch {
                print("❌ RE-ENGAGEMENT TASK: Failed - \(error)")
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            print("⏰ RE-ENGAGEMENT TASK: Expired")
            taskWork.cancel()
        }
    }
    
    /// Schedule next re-engagement check
    func scheduleReEngagementCheck() {
        let request = BGAppRefreshTaskRequest(identifier: reEngagementTaskID)
        
        // Schedule for 6 hours from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ RE-ENGAGEMENT: Next check scheduled for 6 hours")
        } catch {
            print("❌ RE-ENGAGEMENT: Failed to schedule - \(error)")
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
        
        // Update last active time for re-engagement tracking
        if let userID = Auth.auth().currentUser?.uid {
            Task {
                await updateLastActiveTime(userID: userID)
            }
        }
    }
    
    /// Handle app entering background
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 APP DELEGATE: App entered background")
        
        // Schedule re-engagement check when entering background
        scheduleReEngagementCheck()
    }
    
    /// Handle app termination
    func applicationWillTerminate(_ application: UIApplication) {
        print("📱 APP DELEGATE: App will terminate")
    }
    
    // MARK: - Re-Engagement Tracking
    
    /// Update user's last active time in Firestore
    private func updateLastActiveTime(userID: String) async {
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            try await db.collection("users").document(userID).updateData([
                "lastActiveAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ RE-ENGAGEMENT: Updated lastActiveAt for user \(userID)")
            
        } catch {
            print("❌ RE-ENGAGEMENT: Failed to update lastActiveAt - \(error)")
        }
    }
    
    // MARK: - 🔥 ONE-TIME BACKFILL: Fix Empty Creator Names
    
    /// Backfill empty creatorName fields in existing videos
    private func backfillEmptyCreatorNames() async {
        let db = Firestore.firestore()
        
        print("🔍 BACKFILL: Searching for videos with incorrect creatorName...")
        
        do {
            let snapshot = try await db.collection("videos")
                .limit(to: 500)
                .getDocuments()
            
            print("📊 BACKFILL: Checking \(snapshot.documents.count) videos...")
            
            var fixedCount = 0
            var failedCount = 0
            var skippedCount = 0
            
            for doc in snapshot.documents {
                do {
                    let videoData = doc.data()
                    guard let creatorID = videoData["creatorID"] as? String else {
                        print("⚠️ BACKFILL: Skipping \(doc.documentID) - no creatorID")
                        failedCount += 1
                        continue
                    }
                    
                    let currentCreatorName = videoData["creatorName"] as? String ?? ""
                    
                    let userDoc = try await db.collection("users")
                        .document(creatorID)
                        .getDocument()
                    
                    guard userDoc.exists,
                          let userData = userDoc.data(),
                          let correctUsername = userData["username"] as? String,
                          !correctUsername.isEmpty else {
                        print("⚠️ BACKFILL: No username found for user \(creatorID)")
                        failedCount += 1
                        continue
                    }
                    
                    let needsUpdate = currentCreatorName.isEmpty ||
                                     currentCreatorName == "User" ||
                                     currentCreatorName != correctUsername
                    
                    if needsUpdate {
                        try await doc.reference.updateData(["creatorName": correctUsername])
                        fixedCount += 1
                        print("✅ BACKFILL: Fixed \(doc.documentID) → '\(currentCreatorName)' to '@\(correctUsername)'")
                    } else {
                        skippedCount += 1
                    }
                    
                } catch {
                    print("⚠️ BACKFILL: Error processing \(doc.documentID): \(error.localizedDescription)")
                    failedCount += 1
                }
            }
            
            print("🎉 BACKFILL COMPLETE!")
            print("   - Fixed: \(fixedCount) videos")
            print("   - Skipped (already correct): \(skippedCount) videos")
            if failedCount > 0 {
                print("   - Failed: \(failedCount) videos")
            }
            
            if fixedCount > 0 || (fixedCount == 0 && failedCount == 0) {
                UserDefaults.standard.set(true, forKey: "creatorNameBackfillComplete")
            }
            
        } catch {
            print("❌ BACKFILL ERROR: \(error.localizedDescription)")
        }
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
        
        // Store FCM token locally
        UserDefaults.standard.set(token, forKey: "fcm_token")
        
        // Store in Firebase if user authenticated
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
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("📱 FCM: No authenticated user to store token")
            return
        }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Store in userTokens collection
            try await db.collection("userTokens").document(currentUserID).setData([
                "fcmToken": token,
                "updatedAt": FieldValue.serverTimestamp(),
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ], merge: true)
            
            // Store in users collection
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
    
    /// Store FCM token after user authentication
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
        
        if let type = userInfo["type"] as? String {
            print("📱 NOTIFICATION: Type: \(type)")
        }
        
        // Show notification even when app is active
        completionHandler([.banner, .badge, .sound])
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
        case "video", "engagement", "hype", "cool", "reengagement_stitches", "reengagement_milestone":
            if let videoID = userInfo["videoID"] as? String {
                print("🎬 NOTIFICATION: Navigate to video \(videoID)")
                NotificationCenter.default.post(
                    name: .navigateToVideo,
                    object: nil,
                    userInfo: ["videoID": videoID]
                )
            }
            
        case "follow", "user", "reengagement_followers":
            if let userID = userInfo["userID"] as? String {
                print("👤 NOTIFICATION: Navigate to user profile \(userID)")
                NotificationCenter.default.post(
                    name: .navigateToProfile,
                    object: nil,
                    userInfo: ["userID": userID]
                )
            }
            
        case "thread", "reply":
            if let threadID = userInfo["threadID"] as? String {
                print("🧵 NOTIFICATION: Navigate to thread \(threadID)")
                NotificationCenter.default.post(
                    name: .navigateToThread,
                    object: nil,
                    userInfo: ["threadID": threadID]
                )
            }
            
        case "reengagement_tier":
            print("⬆️ NOTIFICATION: Navigate to profile (tier progress)")
            NotificationCenter.default.post(
                name: .navigateToProfile,
                object: nil,
                userInfo: ["showTierProgress": true]
            )
            
        default:
            print("📱 NOTIFICATION: General notification tapped")
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
    
    /// Manually trigger re-engagement check (for testing)
    func testReEngagementCheck() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            print("❌ TEST: No authenticated user")
            return
        }
        
        print("🧪 TEST: Triggering re-engagement check...")
        
        let videoService = VideoService()
        let userService = UserService()
        let reEngagementService = ReEngagementService(
            videoService: videoService,
            userService: userService
        )
        
        do {
            try await reEngagementService.checkReEngagement(userID: userID)
            print("✅ TEST: Re-engagement check completed")
        } catch {
            print("❌ TEST: Re-engagement check failed - \(error)")
        }
    }
}
