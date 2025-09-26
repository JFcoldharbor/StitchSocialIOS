import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications
import FirebaseMessaging

@main
struct StitchSocialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Shared NotificationService for entire app
    @StateObject private var notificationService = NotificationService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationService)
                .overlay(
                    // Toast notification overlay above all content
                    ToastNotificationOverlay(notificationService: notificationService)
                        .allowsHitTesting(false) // Don't block touches to main content
                )
                .onAppear {
                    // Start notification listener if user already authenticated
                    if let currentUserID = Auth.auth().currentUser?.uid {
                        print("🔔 APP STARTUP: Starting notification listener for user \(currentUserID)")
                        notificationService.startNotificationListener(for: currentUserID)
                    } else {
                        print("🔔 APP STARTUP: No authenticated user found")
                    }
                }
        }
    }
}
