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
        #if DEBUG
        print("🔧 FIREBASE: Checking configuration...")
        #endif
        
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            #if DEBUG
            print("✅ FIREBASE: GoogleService-Info.plist found at: \(path)")
            #endif
            
            if let plist = NSDictionary(contentsOfFile: path) {
                if let projectId = plist["PROJECT_ID"] as? String {
                    #if DEBUG
                    print("✅ FIREBASE: Project ID: \(projectId)")
                    #endif
                } else {
                    #if DEBUG
                    print("❌ FIREBASE: No PROJECT_ID in plist")
                    #endif
                }
            } else {
                #if DEBUG
                print("❌ FIREBASE: Cannot read GoogleService-Info.plist")
                #endif
            }
        } else {
            #if DEBUG
            print("❌ FIREBASE: GoogleService-Info.plist NOT FOUND!")
            #endif
            #if DEBUG
            print("📋 FIREBASE: Download from Firebase Console and add to Xcode project")
            #endif
        }
        
        // Configure Firebase with new centralized config
        FirebaseConfig.shared.configure()
        
        // Verify Firebase is configured
        if let app = FirebaseApp.app() {
            #if DEBUG
            print("✅ FIREBASE: App configured successfully - \(app.name)")
            #endif
        } else {
            #if DEBUG
            print("❌ FIREBASE: App configuration failed")
            #endif
        }
        
        // Setup Firebase Cloud Messaging
        setupFirebaseMessaging()
        
        // Setup Background Tasks
        setupBackgroundTasks()
        
        // Setup memory warning observer — clears collage warm cache to free AVAssets
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            #if DEBUG
            print("⚠️ APP: Memory warning — clearing collage warm cache")
            #endif
            ThreadCollageService.clearWarmCache()
        }
        
        // TEMP: Force backfill to run again (REMOVE AFTER ONE RUN)
        UserDefaults.standard.removeObject(forKey: "creatorNameBackfillComplete")
        #if DEBUG
        print("🔄 BACKFILL: Forcing re-run (flag cleared)")
        #endif
        
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
                    #if DEBUG
                    print("⚠️ BACKFILL: Skipped - no authenticated user yet (will retry on next launch)")
                    #endif
                }
            }
        } else {
            #if DEBUG
            print("✅ BACKFILL: Already completed - skipping")
            #endif
        }
        
        #if DEBUG
        print("✅ APP DELEGATE: Complete initialization finished")
        #endif
        
        return true
    }
    
    // MARK: - Firebase Messaging Setup
    
    /// Setup Firebase Cloud Messaging
    private func setupFirebaseMessaging() {
        #if DEBUG
        print("📱 APP DELEGATE: 🔧 Setting up Firebase Messaging...")
        #endif
        
        // Set messaging delegate
        Messaging.messaging().delegate = self
        
        // Request notification permissions
        Task { @MainActor in
            await requestNotificationPermissions()
        }
        
        #if DEBUG
        print("📱 APP DELEGATE: ✅ Firebase Messaging setup initiated")
        #endif
    }
    
    /// Request notification permissions
    @MainActor
    private func requestNotificationPermissions() async {
        do {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            #if DEBUG
            print("📱 APP DELEGATE: Notification permissions granted: \(granted)")
            #endif
            
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
            
        } catch {
            #if DEBUG
            print("📱 APP DELEGATE: ❌ Permission request failed: \(error)")
            #endif
        }
    }
    
    // MARK: - Background Tasks Setup
    
    /// Setup background task handlers
    private func setupBackgroundTasks() {
        #if DEBUG
        print("⏰ BACKGROUND TASKS: Setting up handlers...")
        #endif
        
        // Register re-engagement background task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: reEngagementTaskID,
            using: nil
        ) { task in
            self.handleReEngagementTask(task: task as! BGAppRefreshTask)
        }
        
        #if DEBUG
        print("✅ BACKGROUND TASKS: Registered re-engagement handler")
        #endif
    }
    
    /// Handle re-engagement background task
    private func handleReEngagementTask(task: BGAppRefreshTask) {
        #if DEBUG
        print("🔄 RE-ENGAGEMENT TASK: Starting background check...")
        #endif
        
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
                #if DEBUG
                print("⚠️ RE-ENGAGEMENT TASK: No authenticated user")
                #endif
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
                
                #if DEBUG
                print("✅ RE-ENGAGEMENT TASK: Check completed successfully")
                #endif
                PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
                task.setTaskCompleted(success: true)
                
            } catch {
                #if DEBUG
                print("❌ RE-ENGAGEMENT TASK: Failed - \(error)")
                #endif
                PerformanceMonitoringService.shared.stopTrace(name: "re_engagement_background")
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            #if DEBUG
            print("⏰ RE-ENGAGEMENT TASK: Expired")
            #endif
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
            #if DEBUG
            print("✅ RE-ENGAGEMENT: Next check scheduled for 6 hours")
            #endif
        } catch {
            #if DEBUG
            print("❌ RE-ENGAGEMENT: Failed to schedule - \(error)")
            #endif
        }
    }
    
    // MARK: - Application Lifecycle Events (NEW for Presence)
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        #if DEBUG
        print("🟢 APP: Became active")
        #endif
        
        // Start user presence tracking
        if Config.Features.enableUserPresence {
            RealtimeDataService.shared.startPresenceTracking()
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        #if DEBUG
        print("🟡 APP: Will resign active")
        #endif
        
        // Clear collage warm cache — no need to hold AVAssets in background
        ThreadCollageService.clearWarmCache()
        
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
        #if DEBUG
        print("📱 APP DELEGATE: ✅ APNS token received: \(tokenString.prefix(20))...")
        #endif
        
        // Set APNS token for Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
    }
    
    /// Handle APNS token registration failure
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("📱 APP DELEGATE: ❌ Failed to register for remote notifications: \(error)")
        #endif
    }
    
    // MARK: - Creator Name Backfill
    
    /// Backfill empty creatorName fields in videos
    private func backfillEmptyCreatorNames() async {
        #if DEBUG
        print("🔄 BACKFILL: Starting creator name backfill...")
        #endif
        
        let startTime = Date()
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Get all videos with empty or missing creatorName
            let snapshot = try await db.collection("videos")
                .whereField("creatorName", isEqualTo: "")
                .getDocuments()
            
            var fixedCount = 0
            var failedCount = 0
            
            #if DEBUG
            print("🔄 BACKFILL: Found \(snapshot.documents.count) videos with empty creatorName")
            #endif
            
            // Process each video
            for document in snapshot.documents {
                let data = document.data()
                guard let creatorID = data["creatorId"] as? String else {
                    #if DEBUG
                    print("⚠️ BACKFILL: Video \(document.documentID) has no creatorId")
                    #endif
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
                        #if DEBUG
                        print("✅ BACKFILL: Fixed video \(document.documentID) -> \(displayName)")
                        #endif
                    } else {
                        #if DEBUG
                        print("⚠️ BACKFILL: Creator \(creatorID) has no displayName")
                        #endif
                        failedCount += 1
                    }
                    
                } catch {
                    #if DEBUG
                    print("❌ BACKFILL: Failed to process video \(document.documentID): \(error)")
                    #endif
                    failedCount += 1
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            #if DEBUG
            print("🎉 BACKFILL COMPLETE:")
            #endif
            #if DEBUG
            print("   ✅ Fixed: \(fixedCount)")
            #endif
            #if DEBUG
            print("   ❌ Failed: \(failedCount)")
            #endif
            #if DEBUG
            print("   ⏱️ Duration: \(String(format: "%.2f", duration))s")
            #endif
            
            // Track performance
            PerformanceMonitoringService.shared.trackMemoryOperation(
                operation: "creator_name_backfill",
                memoryUsed: Int64(fixedCount * 1024) // Rough estimate
            )
            
            if fixedCount > 0 || (fixedCount == 0 && failedCount == 0) {
                UserDefaults.standard.set(true, forKey: "creatorNameBackfillComplete")
            }
            
        } catch {
            #if DEBUG
            print("❌ BACKFILL ERROR: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    
    /// Called when FCM token is refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            #if DEBUG
            print("📱 FCM: No token received")
            #endif
            return
        }
        
        #if DEBUG
        print("📱 FCM: Token received: \(token.prefix(20))...")
        #endif
        
        // Store FCM token locally
        UserDefaults.standard.set(token, forKey: "fcm_token")
        
        // Store in Firebase if user authenticated
        if Auth.auth().currentUser != nil {
            Task {
                await storeFCMToken(token)
            }
        } else {
            #if DEBUG
            print("📱 FCM: No authenticated user - token stored locally only")
            #endif
        }
    }
    
    /// Store FCM token for the current user in Firebase
    private func storeFCMToken(_ token: String) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("📱 FCM: No authenticated user to store token")
            #endif
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
            
            #if DEBUG
            print("📱 FCM: Token stored in Firebase successfully")
            #endif
            
        } catch {
            #if DEBUG
            print("📱 FCM: Failed to store token in Firebase: \(error)")
            #endif
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
        #if DEBUG
        print("📱 NOTIFICATION: Received while app in foreground")
        #endif
        
        let userInfo = notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String {
            #if DEBUG
            print("📱 NOTIFICATION: Type: \(type)")
            #endif
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
        #if DEBUG
        print("👆 NOTIFICATION: User tapped notification")
        #endif
        
        let userInfo = response.notification.request.content.userInfo
        
        // Handle navigation based on notification payload
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    /// Handle notification tap navigation
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? "general"
        
        switch type {
        // All video-related notifications → thread view with target video
        case "video", "engagement", "hype", "cool", "reengagement_stitches",
             "reengagement_milestone", "stitch", "thread", "reply", "newVideo", "mention",
             "tip":
            let videoID = userInfo["videoID"] as? String
            let threadID = userInfo["threadID"] as? String ?? videoID

            if let tid = threadID {
                #if DEBUG
                print("🧵 NOTIFICATION: Navigate to thread \(tid), target: \(videoID ?? "root")")
                #endif
                NotificationCenter.default.post(
                    name: .navigateToThread,
                    object: nil,
                    userInfo: [
                        "threadID": tid,
                        "targetVideoID": videoID ?? tid
                    ]
                )
            } else {
                #if DEBUG
                print("📱 NOTIFICATION: No thread/video ID, opening notifications")
                #endif
                NotificationCenter.default.post(name: .navigateToNotifications, object: nil)
            }
            
        case "follow", "user", "reengagement_followers", "subscription":
            if let userID = userInfo["userID"] as? String ?? userInfo["senderID"] as? String {
                #if DEBUG
                print("👤 NOTIFICATION: Navigate to user profile \(userID)")
                #endif
                NotificationCenter.default.post(
                    name: .navigateToProfile,
                    object: nil,
                    userInfo: ["userID": userID]
                )
            }
            
        case "reengagement_tier":
            #if DEBUG
            print("⬆️ NOTIFICATION: Navigate to profile (tier progress)")
            #endif
            NotificationCenter.default.post(
                name: .navigateToProfile,
                object: nil,
                userInfo: ["showTierProgress": true]
            )
            
        default:
            #if DEBUG
            print("📱 NOTIFICATION: General notification tapped")
            #endif
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
        
        #if DEBUG
        print("📱 NOTIFICATION DEBUG:")
        #endif
        #if DEBUG
        print("  - Permission status: \(status)")
        #endif
        #if DEBUG
        print("  - FCM token available: \(token != nil)")
        #endif
        #if DEBUG
        print("  - Token: \(token?.prefix(20) ?? "None")...")
        #endif
    }
    
    /// Manually trigger re-engagement check (for testing)
    func testReEngagementCheck() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("❌ TEST: No authenticated user")
            #endif
            return
        }
        
        #if DEBUG
        print("🧪 TEST: Triggering re-engagement check...")
        #endif
        
        let videoService = VideoService()
        let userService = UserService()
        let reEngagementService = ReEngagementService(
            videoService: videoService,
            userService: userService
        )
        
        do {
            try await reEngagementService.checkReEngagement(userID: userID)
            #if DEBUG
            print("✅ TEST: Re-engagement check completed")
            #endif
        } catch {
            #if DEBUG
            print("❌ TEST: Re-engagement check failed - \(error)")
            #endif
        }
    }
}
