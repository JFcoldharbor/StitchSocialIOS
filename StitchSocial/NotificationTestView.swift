//
//  NotificationTestView.swift
//  StitchSocial
//
//  Complete push notification test utility with all features
//  Add this to your app for testing push notifications
//

import SwiftUI
import FirebaseAuth
import UserNotifications

struct NotificationTestView: View {
    @EnvironmentObject var notificationService: NotificationService
    @State private var testResult = "Ready to test push notifications"
    @State private var isTesting = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var fcmToken = "Loading..."
    @State private var showingTokenSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    Text("🔔 Push Notification Test")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Test all notification functionality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Status Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("📊 Current Status")
                            .font(.headline)
                        Spacer()
                    }
                    
                    StatusRow(title: "Permission", value: permissionStatusText, color: permissionColor)
                    StatusRow(title: "FCM Token", value: fcmToken.isEmpty ? "None" : "✅ Available", color: fcmToken.isEmpty ? .red : .green)
                    StatusRow(title: "User Auth", value: authStatusText, color: authColor)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Test Result Display
                VStack(alignment: .leading, spacing: 8) {
                    Text("📝 Test Results")
                        .font(.headline)
                    
                    ScrollView {
                        Text(testResult)
                            .foregroundColor(resultColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                    }
                    .frame(height: 100)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Test Buttons
                VStack(spacing: 12) {
                    Text("🧪 Test Actions")
                        .font(.headline)
                    
                    // Push Notification Test
                    Button(action: testPushNotification) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isTesting ? "Sending..." : "Test Push Notification")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTesting || Auth.auth().currentUser == nil)
                    
                    // In-App Toast Test
                    Button(action: testInAppNotification) {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("Test In-App Toast")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    // Permission Check
                    Button(action: refreshStatus) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Status")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    // Request Permissions
                    if permissionStatus != .authorized {
                        Button(action: requestPermissions) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("Request Permissions")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    // View FCM Token
                    Button(action: { showingTokenSheet = true }) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text("View FCM Token")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Notification Test")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshStatus()
        }
        .sheet(isPresented: $showingTokenSheet) {
            FCMTokenView(token: fcmToken)
        }
    }
    
    // MARK: - Computed Properties
    
    private var permissionStatusText: String {
        switch permissionStatus {
        case .authorized: return "✅ Authorized"
        case .denied: return "❌ Denied"
        case .notDetermined: return "⚠️ Not Asked"
        case .provisional: return "✅ Provisional"
        case .ephemeral: return "✅ Ephemeral"
        @unknown default: return "❓ Unknown"
        }
    }
    
    private var permissionColor: Color {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }
    
    private var authStatusText: String {
        Auth.auth().currentUser != nil ? "✅ Signed In" : "❌ Not Signed In"
    }
    
    private var authColor: Color {
        Auth.auth().currentUser != nil ? .green : .red
    }
    
    private var resultColor: Color {
        if testResult.contains("✅") { return .green }
        if testResult.contains("❌") { return .red }
        if testResult.contains("⚠️") { return .orange }
        return .primary
    }
    
    // MARK: - Test Actions
    
    private func testPushNotification() {
        guard let currentUser = Auth.auth().currentUser else {
            testResult = "❌ Error: No authenticated user\nPlease sign in first to test push notifications."
            return
        }
        
        isTesting = true
        testResult = "📤 Sending test notification...\nThis will create a notification document in Firebase, which should trigger your Cloud Function to send a push notification."
        
        Task {
            do {
                // Test creating a notification - this should trigger push via Cloud Function
                try await notificationService.createNotification(
                    recipientID: currentUser.uid,
                    senderID: "test_system",
                    type: .system,
                    title: "🔔 Test Notification",
                    message: "Your push notifications are working perfectly!",
                    payload: [
                        "test": "true",
                        "timestamp": "\(Date().timeIntervalSince1970)",
                        "source": "NotificationTestView"
                    ]
                )
                
                await MainActor.run {
                    testResult = "✅ Test notification created successfully!\n\n📱 Check your device in 3-5 seconds for the push notification.\n\n🔍 What happened:\n1. Created notification document in Firebase\n2. Cloud Function detected the new document\n3. Cloud Function sent push notification\n4. Your device should receive it"
                    isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    testResult = "❌ Test failed: \(error.localizedDescription)\n\n🔍 This could mean:\n1. Cloud Function not deployed\n2. FCM token not stored\n3. Network connectivity issue\n4. Firebase configuration problem"
                    isTesting = false
                }
            }
        }
    }
    
    private func testInAppNotification() {
        // Test in-app toast notification
        let toast = NotificationToast(
            type: .system,
            title: "🎉 Toast Test",
            message: "In-app notifications are working perfectly!",
            senderUsername: "Test System",
            payload: ["test": "toast"]
        )
        
        notificationService.pendingToasts.append(toast)
        
        // Auto-dismiss after 4 seconds
        Task {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            notificationService.dismissToast(toastID: toast.id)
        }
        
        testResult = "✅ In-app toast notification displayed!\n\nThis confirms that:\n1. NotificationService is working\n2. Toast system is functional\n3. UI integration is correct"
    }
    
    private func refreshStatus() {
        // Check notification permissions
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            
            await MainActor.run {
                permissionStatus = settings.authorizationStatus
            }
        }
        
        // Get FCM token
        Task {
            if let token = await FCMPushManager.shared.getCurrentFCMToken() {
                await MainActor.run {
                    fcmToken = token
                }
            } else {
                await MainActor.run {
                    fcmToken = ""
                }
            }
        }
        
        testResult = "🔄 Status refreshed\n\nCurrent state:\n• Permission: \(permissionStatusText)\n• FCM Token: \(fcmToken.isEmpty ? "Missing" : "Available")\n• Authentication: \(authStatusText)"
    }
    
    private func requestPermissions() {
        Task {
            await FCMPushManager.shared.requestPermissionsAndRegister()
            await refreshStatus()
        }
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
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
    }
}

struct FCMTokenView: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🔑 FCM Token")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This token identifies your device for push notifications:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                ScrollView {
                    Text(token)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                
                Button("Copy Token") {
                    UIPasteboard.general.string = token
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationTitle("FCM Token")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

// MARK: - Extensions

extension FCMPushManager {
    func getCurrentFCMToken() async -> String? {
        // Return the current FCM token if available
        return fcmToken
    }
}

// MARK: - Preview

#Preview {
    NotificationTestView()
        .environmentObject(NotificationService())
}