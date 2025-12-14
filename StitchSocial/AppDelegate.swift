//
//  AppDelegate.swift
//  CleanBeta
//
//  Created by James Garmon on 7/31/25.
//  COMPLETE: Firebase + FCM + Push Notifications + Re-Engagement Integration
//  UPDATED: Added Performance Monitoring and Realtime Database
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore
import FirebasePerformance  // NEW
import FirebaseDatabase     // NEW
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
        
        // Configure Firebase with new centralized config
        FirebaseConfig.shared.configure()
        
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
        
        // Track performance of background task
        let trace = PerformanceMonitoringService.shared.startTrace(
            name: "re_engagement_background",
            attributes: ["task_type": "background_refresh"]
        )
        
        // Schedule next task
        scheduleReEngagementCheck()
        
        // Create async task
        let taskWork = Task {
            guard let userID = Auth.auth().currentUser?.uid else {
                print("⚠️ RE-ENGAGEMENT TASK: No authenticated user")
                PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
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
                PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
                task.setTaskCompleted(success: true)
                
            } catch {
                print("❌ RE-ENGAGEMENT TASK: Failed - \(error)")
                PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            print("⏰ RE-ENGAGEMENT TASK: Expired")
            PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
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
    
    // MARK: - Application Lifecycle Events (NEW for Presence)
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("🟢 APP: Became active")
        
        // Start user presence tracking
        if Config.Features.enableUserPresence {
            RealtimeDataService.shared.startPresenceTracking()
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        print("🟡 APP: Will resign active")
        
        // Stop user presence tracking
        if Config.Features.enableUserPresence {
            RealtimeDataService.shared.stopPresenceTracking()
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
    
    // MARK: - Creator Name Backfill
    
    /// Backfill empty creatorName fields in videos
    private func backfillEmptyCreatorNames() async {
        print("🔄 BACKFILL: Starting creator name backfill...")
        
        let startTime = Date()
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Get all videos with empty or missing creatorName
            let snapshot = try await db.collection("videos")
                .whereField("creatorName", isEqualTo: "")
                .getDocuments()
            
            var fixedCount = 0
            var failedCount = 0
            
            print("🔄 BACKFILL: Found \(snapshot.documents.count) videos with empty creatorName")
            
            // Process each video
            for document in snapshot.documents {
                let data = document.data()
                guard let creatorID = data["creatorId"] as? String else {
                    print("⚠️ BACKFILL: Video \(document.documentID) has no creatorId")
                    failedCount += 1
                    continue
                }
                
                do {
                    // Fetch creator profile
                    let userDoc = try await db.collection("users").document(creatorID).getDocument()
                    
                    if let userData = userDoc.data(),
                       let displayName = userData["displayName"] as? String {
                        
                        // Update video with creator name
                        try await db.collection("videos").document(document.documentID).updateData([
                            "creatorName": displayName,
                            "backfilledAt": FieldValue.serverTimestamp()
                        ])
                        
                        fixedCount += 1
                        print("✅ BACKFILL: Fixed video \(document.documentID) -> \(displayName)")
                    } else {
                        print("⚠️ BACKFILL: Creator \(creatorID) has no displayName")
                        failedCount += 1
                    }
                    
                } catch {
                    print("❌ BACKFILL: Failed to process video \(document.documentID): \(error)")
                    failedCount += 1
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            print("🎉 BACKFILL COMPLETE:")
            print("   ✅ Fixed: \(fixedCount)")
            print("   ❌ Failed: \(failedCount)")
            print("   ⏱️ Duration: \(String(format: "%.2f", duration))s")
            
            // Track performance
            PerformanceMonitoringService.shared.trackMemoryOperation(
                operation: "creator_name_backfill",
                memoryUsed: Int64(fixedCount * 1024) // Rough estimate
            )
            
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
