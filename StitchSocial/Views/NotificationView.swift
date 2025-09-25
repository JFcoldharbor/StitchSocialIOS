//
//  NotificationView.swift
//  StitchSocial
//
//  Layer 8: Views - Complete Notification Interface
//  Dependencies: NotificationViewModel (Layer 7), NotificationService (Layer 4)
//  FIXED: All compilation errors resolved, clean SwiftUI implementation
//

import SwiftUI
import FirebaseAuth

struct NotificationView: View {
    
    // MARK: - Dependencies (No Circular Reference)
    
    @StateObject private var viewModel: NotificationViewModel
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - UI State
    
    @State private var selectedTab: StitchNotificationTab = .all
    @State private var showingError = false
    @State private var isRefreshing = false
    
    // MARK: - Initialization (Dependency Injection)
    
    init(notificationService: NotificationService? = nil) {
        // Use dependency injection to avoid circular reference
        self._viewModel = StateObject(wrappedValue: NotificationViewModel(
            notificationService: notificationService ?? NotificationService()
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Main content
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Tab selector
                    tabSelector
                    
                    // Content
                    contentView
                }
                
                // Toast overlay
                toastOverlay
            }
        }
        .task {
            await loadInitialNotifications()
        }
        .refreshable {
            await refreshNotifications()
        }
        .alert("Error", isPresented: $showingError) {
            Button("Retry") {
                Task { await viewModel.loadNotifications() }
            }
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
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
            
            // Mark all read button
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
        .padding(.top, 10)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(StitchNotificationTab.allCases, id: \.self) { tab in
                Button {
                    selectTab(tab)
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.displayName)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .white : .gray)
                        
                        let count = getTabCount(for: tab)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? .black : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? .white : .gray.opacity(0.3))
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.purple : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ZStack {
            if viewModel.isLoading && viewModel.filteredNotifications.isEmpty {
                loadingView
            } else if viewModel.filteredNotifications.isEmpty {
                emptyStateView
            } else {
                notificationList
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
            
            Text("Loading notifications...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.purple)
            
            VStack(spacing: 8) {
                Text(getEmptyStateTitle())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(getEmptyStateMessage())
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Notification List
    
    private var notificationList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredNotifications) { notification in
                    NotificationRowView(notification: notification) {
                        handleNotificationTap(notification)
                    }
                }
                
                // Load more trigger
                if viewModel.hasMoreNotifications && !viewModel.isLoading {
                    Button("Load More") {
                        Task { await viewModel.loadMoreNotifications() }
                    }
                    .foregroundColor(.purple)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - Toast Overlay
    
    private var toastOverlay: some View {
        VStack(spacing: 8) {
            // Toast notifications would go here when service is fully implemented
            EmptyView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialNotifications() async {
        await viewModel.loadNotifications()
    }
    
    private func refreshNotifications() async {
        await viewModel.refreshNotifications()
    }
    
    private func selectTab(_ tab: StitchNotificationTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        viewModel.filterNotifications(by: tab)
    }
    
    private func getTabCount(for tab: StitchNotificationTab) -> Int {
        switch tab {
        case .all:
            return viewModel.notifications.count
        case .hypes:
            return viewModel.notifications.filter { notification in
                notification.type == .hype || notification.type == .cool
            }.count
        case .follows:
            return viewModel.notifications.filter { $0.type == .follow }.count
        case .replies:
            return viewModel.notifications.filter { notification in
                notification.type == .reply || notification.type == .mention
            }.count
        }
    }
    
    private func handleNotificationTap(_ notification: NotificationDisplayData) {
        Task {
            if !notification.isRead {
                await viewModel.markAsRead(notification.id)
            }
            // Navigate to notification source would go here
        }
    }
    
    // Empty state helpers
    private func getEmptyStateIcon() -> String {
        switch selectedTab {
        case .all: return "bell.slash"
        case .hypes: return "heart.slash"
        case .follows: return "person.slash"
        case .replies: return "bubble.left.slash"
        }
    }
    
    private func getEmptyStateTitle() -> String {
        switch selectedTab {
        case .all: return "No Notifications"
        case .hypes: return "No Hypes Yet"
        case .follows: return "No New Followers"
        case .replies: return "No Replies"
        }
    }
    
    private func getEmptyStateMessage() -> String {
        switch selectedTab {
        case .all: return "Create some videos and engage with the community to start receiving notifications."
        case .hypes: return "Share your videos and they'll start getting hyped!"
        case .follows: return "Keep creating content to attract new followers."
        case .replies: return "Start conversations with your videos to get replies."
        }
    }
}

// MARK: - Supporting Views

struct NotificationRowView: View {
    let notification: NotificationDisplayData
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(notification.type.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: notification.type.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(notification.type.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(notification.message)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    
                    Text(formatRelativeTime(notification.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(notification.isRead ? Color.clear : notification.type.color.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(notification.isRead ? 0.7 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {
            // Handle press state - no parameters needed
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Extensions

extension NotificationDisplayData {
    var type: NotificationType {
        switch self.notificationType {
        case .hype: return .hype
        case .cool: return .cool
        case .follow: return .follow
        case .reply: return .reply
        case .mention: return .mention
        default: return .hype
        }
    }
}

// MARK: - StitchNotificationTab for UI

enum StitchNotificationTab: String, CaseIterable {
    case all = "all"
    case hypes = "hypes"
    case follows = "follows"
    case replies = "replies"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .hypes: return "Hypes"
        case .follows: return "Follows"
        case .replies: return "Replies"
        }
    }
}

// MARK: - NotificationType for UI

enum NotificationType: String, CaseIterable {
    case hype = "hype"
    case cool = "cool"
    case follow = "follow"
    case reply = "reply"
    case mention = "mention"
    
    var color: Color {
        switch self {
        case .hype: return .red
        case .cool: return .blue
        case .follow: return .green
        case .reply: return .purple
        case .mention: return .orange
        }
    }
    
    var iconName: String {
        switch self {
        case .hype: return "heart.fill"
        case .cool: return "hand.thumbsdown.fill"
        case .follow: return "person.badge.plus.fill"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        }
    }
}
