import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications
import FirebaseMessaging

@main
struct StitchSocialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // REMOVE .onAppear - AppDelegate handles everything
        }
    }
}

// REMOVE all the notification extensions - they're already in AppDelegate+FCM.swift
