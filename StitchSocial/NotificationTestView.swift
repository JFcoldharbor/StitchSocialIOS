//
//  NotificationTestView.swift
//  StitchSocial
//
//  Notification testing interface - Updated for new NotificationService
//

import SwiftUI
import FirebaseAuth
import UserNotifications

struct NotificationTestView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var notificationService = NotificationService()
    
    @State private var testResult = "Ready to test notifications"
    @State private var isTesting = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var fcmToken = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    Text("Notification Tester")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Test push notifications and debug issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Status Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Status")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            StatusRow(
                                title: "Permission",
                                value: permissionString,
                                color: permissionColor
                            )
                            
                            StatusRow(
                                title: "FCM Token",
                                value: fcmToken.isEmpty ? "None" : "Available",
                                color: fcmToken.isEmpty ? .red : .green
                            )
                            
                            StatusRow(
                                title: "Auth User",
                                value: authService.currentUser != nil ? "Logged In" : "Not Logged In",
                                color: authService.currentUser != nil ? .green : .red
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Test Buttons
                    VStack(spacing: 12) {
                        Text("Test Functions")
                            .font(.headline)
                        
                        // Test 1: Check Token
                        Button(action: testCheckToken) {
                            HStack {
                                if isTesting {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text(isTesting ? "Testing..." : "Check FCM Token")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isTesting || authService.currentUser == nil)
                        
                        // Test 2: Send Test Push
                        Button(action: testSendPush) {
                            HStack {
                                if isTesting {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "bell.fill")
                                }
                                Text(isTesting ? "Testing..." : "Send Test Push")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isTesting || authService.currentUser == nil)
                        
                        // Test 3: Request Permission
                        Button(action: requestPermission) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("Request Permission")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        // Test 4: Refresh Status
                        Button(action: refreshStatus) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Status")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    // Result Display
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test Result")
                            .font(.headline)
                        
                        ScrollView {
                            Text(testResult)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(resultColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Notification Test")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshStatus()
            }
        }
    }
    
    // MARK: - Test Functions
    
    private func testCheckToken() {
        guard authService.currentUser != nil else {
            testResult = "Error: No authenticated user"
            return
        }
        
        isTesting = true
        testResult = "Checking FCM token status..."
        
        Task {
            do {
                let result = try await notificationService.checkToken()
                
                await MainActor.run {
                    let hasToken = result["hasToken"] as? Bool ?? false
                    let platform = result["tokenData"] as? [String: Any]
                    let platformStr = platform?["platform"] as? String ?? "unknown"
                    
                    testResult = """
                    ✅ Token Check Success
                    
                    Has Token: \(hasToken)
                    Platform: \(platformStr)
                    User ID: \(result["userId"] as? String ?? "unknown")
                    
                    Full Result:
                    \(result)
                    """
                    isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    testResult = "❌ Token check failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
    
    private func testSendPush() {
        guard authService.currentUser != nil else {
            testResult = "Error: No authenticated user"
            return
        }
        
        isTesting = true
        testResult = "Sending test push notification..."
        
        Task {
            do {
                try await notificationService.sendTestPush()
                
                await MainActor.run {
                    testResult = """
                    ✅ Test Push Sent!
                    
                    Check your device for the push notification.
                    It should appear in a few seconds.
                    
                    If you don't see it:
                    - Check notification permissions
                    - Ensure FCM token is registered
                    - Check Cloud Functions logs
                    """
                    isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    testResult = "❌ Test push failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
    
    private func requestPermission() {
        testResult = "Requesting notification permission..."
        
        Task {
            let center = UNUserNotificationCenter.current()
            
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                
                await MainActor.run {
                    if granted {
                        testResult = """
                        ✅ Permission Granted!
                        
                        Notifications are now enabled.
                        Refresh status to see updated permission.
                        """
                        permissionStatus = .authorized
                    } else {
                        testResult = """
                        ❌ Permission Denied
                        
                        Enable notifications in Settings:
                        Settings → Stitch Social → Notifications
                        """
                        permissionStatus = .denied
                    }
                }
                
            } catch {
                await MainActor.run {
                    testResult = "❌ Permission request failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func refreshStatus() {
        Task {
            // Update permission status
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            
            await MainActor.run {
                permissionStatus = settings.authorizationStatus
            }
            
            // Update FCM token
            if let token = FCMPushManager.shared.fcmToken {
                await MainActor.run {
                    fcmToken = token
                }
            } else {
                await MainActor.run {
                    fcmToken = ""
                }
            }
            
            await MainActor.run {
                testResult = "Status refreshed at \(Date().formatted(date: .omitted, time: .shortened))"
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var permissionString: String {
        switch permissionStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Asked"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    private var permissionColor: Color {
        switch permissionStatus {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        default: return .gray
        }
    }
    
    private var resultColor: Color {
        if testResult.contains("✅") || testResult.contains("Success") { return .green }
        if testResult.contains("❌") || testResult.contains("failed") { return .red }
        if testResult.contains("Testing") { return .orange }
        return .primary
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
