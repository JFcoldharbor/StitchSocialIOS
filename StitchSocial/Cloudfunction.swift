//
//  CloudFunction.swift
//  StitchSocial
//
//  Standalone Cloud Function testing utilities
//  No dependencies on other views to avoid access level issues
//

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

struct StandaloneCloudFunctionTestView: View {
    @State private var testResult = "Ready to test Cloud Functions directly"
    @State private var isTesting = false
    @State private var currentUserID = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🔧 Cloud Function Direct Test")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Test Cloud Functions bypassing Firestore triggers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // User Status
                HStack {
                    Text("User ID:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(currentUserID.isEmpty ? "Not signed in" : currentUserID)
                        .font(.caption)
                        .foregroundColor(currentUserID.isEmpty ? .red : .green)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Test Result Display
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Results")
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
                    .frame(height: 150)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Test Buttons
                VStack(spacing: 12) {
                    Text("Direct Cloud Function Tests")
                        .font(.headline)
                    
                    Button(action: testSendNotificationFunction) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bell.fill")
                            }
                            Text(isTesting ? "Testing..." : "Test sendTestNotification")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTesting || currentUserID.isEmpty)
                    
                    Button(action: testDatabaseConnection) {
                        HStack {
                            Image(systemName: "database.fill")
                            Text("Test Database Connection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTesting)
                    
                    Button(action: refreshUserStatus) {
                        HStack {
                            Image(systemName: "person.fill")
                            Text("Refresh User Status")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Cloud Function Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            refreshUserStatus()
        }
    }
    
    private var resultColor: Color {
        if testResult.contains("Success") || testResult.contains("✅") { return .green }
        if testResult.contains("Failed") || testResult.contains("❌") || testResult.contains("Error") { return .red }
        if testResult.contains("Testing") || testResult.contains("⏳") { return .orange }
        return .primary
    }
    
    private func refreshUserStatus() {
        if let user = Auth.auth().currentUser {
            currentUserID = user.uid
            testResult = "✅ User authenticated: \(user.uid)\n\nReady to test Cloud Functions!"
        } else {
            currentUserID = ""
            testResult = "❌ No authenticated user found. Please sign in first."
        }
    }
    
    private func testSendNotificationFunction() {
        guard !currentUserID.isEmpty else {
            testResult = "❌ Error: No authenticated user. Please sign in first."
            return
        }
        
        isTesting = true
        testResult = "⏳ Testing sendTestNotification Cloud Function...\n\nThis calls the function directly, bypassing Firestore triggers."
        
        Task {
            do {
                let functions = Functions.functions()
                let testFunction = functions.httpsCallable("sendTestNotification")
                
                let result = try await testFunction.call([
                    "recipientID": currentUserID,
                    "title": "🔧 Direct Cloud Function Test",
                    "body": "This notification came directly from the Cloud Function!"
                ])
                
                await MainActor.run {
                    if let data = result.data as? [String: Any] {
                        let success = data["success"] as? Bool ?? false
                        let message = data["message"] as? String ?? "No message"
                        let messageId = data["messageId"] as? String ?? "No ID"
                        
                        testResult = """
                        ✅ Cloud Function Test SUCCESS!
                        
                        Response Details:
                        • Success: \(success)
                        • Message: \(message)
                        • FCM Message ID: \(messageId)
                        
                        If you received a push notification, your entire system is working correctly!
                        
                        This confirms:
                        1. ✅ Cloud Function is deployed
                        2. ✅ Can read your FCM token
                        3. ✅ Can send push notifications
                        4. ✅ APNS/FCM integration works
                        
                        If the Firestore trigger isn't working, it's a separate issue.
                        """
                    } else {
                        testResult = "⚠️ Cloud Function responded but unexpected format:\n\(result.data)"
                    }
                    isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    testResult = """
                    ❌ Cloud Function Test FAILED
                    
                    Error: \(error.localizedDescription)
                    
                    This could mean:
                    1. ❌ Function not deployed correctly
                    2. ❌ Function has code errors
                    3. ❌ Database permission issues
                    4. ❌ FCM token not found
                    5. ❌ Network connectivity problems
                    
                    Check Firebase Console → Functions → Logs for more details.
                    """
                    isTesting = false
                }
            }
        }
    }
    
    private func testDatabaseConnection() {
        isTesting = true
        testResult = "⏳ Testing database connection and permissions..."
        
        Task {
            do {
                let functions = Functions.functions()
                let debugFunction = functions.httpsCallable("debugDatabaseConnection")
                
                let result = try await debugFunction.call([:])
                
                await MainActor.run {
                    if let data = result.data as? [String: Any] {
                        let success = data["success"] as? Bool ?? false
                        let database = data["database"] as? String ?? "unknown"
                        let notificationsCount = data["notificationsCount"] as? Int ?? 0
                        let userTokensCount = data["userTokensCount"] as? Int ?? 0
                        
                        testResult = """
                        ✅ Database Connection SUCCESS!
                        
                        Connection Details:
                        • Database: \(database)
                        • Notifications Collection: \(notificationsCount) documents
                        • User Tokens Collection: \(userTokensCount) documents
                        • Connection Status: \(success ? "Working" : "Failed")
                        
                        This confirms the Cloud Function can access your 'stitchfin' database properly.
                        """
                    } else {
                        testResult = "⚠️ Database test completed but unexpected response:\n\(result.data)"
                    }
                    isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    testResult = """
                    ❌ Database Connection FAILED
                    
                    Error: \(error.localizedDescription)
                    
                    This suggests:
                    1. ❌ Cloud Function can't access database
                    2. ❌ Wrong database configuration
                    3. ❌ Permission issues
                    4. ❌ Function not deployed with database access
                    """
                    isTesting = false
                }
            }
        }
    }
}

// Simple button to launch the test view
struct CloudFunctionTestLauncher: View {
    @State private var showingTest = false
    
    var body: some View {
        Button("🔧 Test Cloud Functions") {
            showingTest = true
        }
        .sheet(isPresented: $showingTest) {
            StandaloneCloudFunctionTestView()
        }
    }
}
