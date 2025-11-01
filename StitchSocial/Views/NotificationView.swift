//
//  NotificationView.swift
//  StitchSocial
//
//  Complete notification view with video navigation support
//  UPDATED: Fixed all deprecated NotificationService method calls
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging
import UserNotifications

struct NotificationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel: NotificationViewModel
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - UI State
    
    @State private var selectedTab: StitchNotificationTab = .all
    @State private var showingError = false
    @State private var isRefreshing = false
    @State private var showingNotificationTest = false
    
    // MARK: - Initialization
    
    init(notificationService: NotificationService? = nil) {
        self._viewModel = StateObject(wrappedValue: NotificationViewModel(
            notificationService: notificationService ?? NotificationService()
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        headerView
                            .padding(.top, 20)
                        
                        tabSelector
                            .padding(.top, 16)
                        
                        contentView
                            .padding(.top, 24)
                    }
                }
                .refreshable {
                    await refreshNotifications()
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadInitialNotifications()
        }
        .alert("Error", isPresented: $showingError) {
            Button("Retry") {
                Task { await viewModel.loadNotifications() }
            }
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
        .sheet(isPresented: $showingNotificationTest) {
            EmbeddedNotificationTestView()
                .environmentObject(authService)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                if viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount) unread")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            Button {
                showingNotificationTest = true
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                    )
            }
            
            Button {
                Task { await viewModel.markAllAsRead() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark All Read")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.purple.opacity(0.8))
                )
            }
            .disabled(viewModel.unreadCount == 0 || viewModel.isLoading)
            .opacity(viewModel.unreadCount == 0 ? 0.5 : 1.0)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StitchNotificationTab.allCases, id: \.self) { tab in
                    Button {
                        selectTab(tab)
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.displayName)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundColor(selectedTab == tab ? .white : .gray)
                            
                            if tab == .unread && viewModel.unreadCount > 0 {
                                Text("\(viewModel.unreadCount)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedTab == tab ? Color.purple.opacity(0.3) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedTab == tab ? Color.purple : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading && viewModel.allNotifications.isEmpty {
                loadingView
            } else if viewModel.filteredNotifications.isEmpty {
                emptyStateView
            } else {
                notificationList
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.purple)
            
            Text("Loading notifications...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(height: 300)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No notifications")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(getEmptyStateMessage())
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(height: 300)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Notification List
    
    private var notificationList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredNotifications) { notification in
                NotificationRowView(
                    notification: notification,
                    onTap: { await handleNotificationTap(notification) },
                    onMarkAsRead: { await viewModel.markAsRead(notification.id) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            
            if viewModel.hasMoreNotifications {
                ProgressView()
                    .padding()
                    .onAppear {
                        Task { await viewModel.loadMoreNotifications() }
                    }
            }
            
            Color.clear
                .frame(height: 100)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Methods
    
    private func selectTab(_ tab: StitchNotificationTab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
            viewModel.selectTab(tab)
        }
    }
    
    private func getEmptyStateIcon() -> String {
        switch selectedTab {
        case .all: return "bell.slash"
        case .unread: return "checkmark.circle"
        case .hypes: return "flame.fill"
        case .follows: return "person.badge.plus"
        case .replies: return "bubble.left.and.bubble.right"
        case .system: return "info.circle"
        }
    }
    
    private func getEmptyStateMessage() -> String {
        switch selectedTab {
        case .all:
            return "You're all caught up! Check back later for new activity."
        case .unread:
            return "You've read all your notifications. Great job staying on top of things!"
        case .hypes:
            return "Share some videos to start getting hype from the community!"
        case .follows:
            return "Keep creating content and followers will discover you!"
        case .replies:
            return "Start conversations by replying to videos you like."
        case .system:
            return "System notifications and updates will appear here."
        }
    }
    
    private func loadInitialNotifications() async {
        await viewModel.loadNotifications()
    }
    
    private func refreshNotifications() async {
        await viewModel.refreshNotifications()
    }
    
    private func handleNotificationTap(_ notification: NotificationDisplayData) async {
        await viewModel.markAsRead(notification.id)
        
        // Video navigation removed for now - payload not available in display data
        // TODO: Implement video navigation when needed
        print("📱 Notification tapped: \(notification.id)")
    }
}

// MARK: - Embedded Test View (FIXED)

struct EmbeddedNotificationTestView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var notificationService = NotificationService()
    @State private var testResult = "Ready to test notifications"
    @State private var isTesting = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var fcmToken = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Notification Tester")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Test push notifications and debug issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Status")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            NotificationStatusRow(
                                title: "Permission",
                                value: permissionString,
                                color: permissionColor
                            )
                            
                            NotificationStatusRow(
                                title: "FCM Token",
                                value: fcmToken.isEmpty ? "None" : "Available",
                                color: fcmToken.isEmpty ? .red : .green
                            )
                            
                            NotificationStatusRow(
                                title: "Auth User",
                                value: authService.currentUser != nil ? "Logged In" : "Not Logged In",
                                color: authService.currentUser != nil ? .green : .red
                            )
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test Result")
                            .font(.headline)
                        
                        ScrollView {
                            Text(testResult)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(resultColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 100)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    VStack(spacing: 12) {
                        // FIXED: Use new method names
                        Button(action: testCheckToken) {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                Text("Test Check Token")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isTesting)
                        
                        Button(action: testSendPush) {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Send Test Push")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isTesting)
                        
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
                        .disabled(permissionStatus == .authorized)
                        
                        Button(action: refreshStatus) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Status")
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
            }
            .navigationTitle("Notification Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            refreshStatus()
        }
    }
    
    // MARK: - Test Methods (FIXED)
    
    private func testCheckToken() {
        guard authService.currentUser != nil else {
            testResult = "Error: No authenticated user"
            return
        }
        
        isTesting = true
        testResult = "Testing checkToken function..."
        
        Task {
            do {
                let result = try await notificationService.checkToken()
                
                let hasToken = result["hasToken"] as? Bool ?? false
                
                await MainActor.run {
                    testResult = "✅ Token check succeeded!\nHas Token: \(hasToken)\nFull result: \(result)"
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
                    testResult = "✅ Test push sent! Check your device for the notification."
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Task { @MainActor in
                if granted {
                    testResult = "✅ Notification permission granted"
                    UIApplication.shared.registerForRemoteNotifications()
                } else if let error = error {
                    testResult = "❌ Permission error: \(error.localizedDescription)"
                } else {
                    testResult = "❌ Notification permission denied"
                }
                refreshStatus()
            }
        }
    }
    
    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                permissionStatus = settings.authorizationStatus
            }
        }
        
        if let token = Messaging.messaging().fcmToken {
            fcmToken = token
        }
    }
    
    private var permissionString: String {
        switch permissionStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
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
        if testResult.contains("✅") || testResult.contains("succeeded") { return .green }
        if testResult.contains("❌") || testResult.contains("failed") { return .red }
        if testResult.contains("Testing") { return .orange }
        return .primary
    }
}

// MARK: - Supporting Views

struct NotificationRowView: View {
    let notification: NotificationDisplayData
    let onTap: () async -> Void
    let onMarkAsRead: () async -> Void
    
    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: notification.notificationType.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(notification.notificationType.color)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(notification.notificationType.color.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(notification.message)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    
                    Text(timeAgo(from: notification.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.7))
                }
                
                Spacer()
                
                if !notification.isRead {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(notification.isRead ? Color.gray.opacity(0.1) : Color.purple.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct NotificationStatusRow: View {
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

enum StitchNotificationTab: String, CaseIterable {
    case all = "all"
    case unread = "unread"
    case hypes = "hypes"
    case follows = "follows"
    case replies = "replies"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .hypes: return "Hypes"
        case .follows: return "Follows"
        case .replies: return "Replies"
        case .system: return "System"
        }
    }
}
