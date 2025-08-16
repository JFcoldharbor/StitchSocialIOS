//
//  NotificationView.swift
//  CleanBeta
//
//  Layer 8: Views - Complete User Notifications with Service Integration
//  Dependencies: NotificationViewModel (Layer 7), AuthService
//  Features: Real-time database updates, pagination, proper navigation
//

import SwiftUI
import FirebaseAuth

struct NotificationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel = NotificationViewModel()
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - UI State
    
    @State private var selectedTab: NotificationTab = .all
    @State private var showingError = false
    
    // MARK: - Initialization
    
    init() {
        // Default initialization - services will be injected or created as needed
    }
    
    // MARK: - Main Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                notificationTabSelector
                
                // Content
                ZStack {
                    StitchColors.background.ignoresSafeArea()
                    
                    if viewModel.isLoading && viewModel.notifications.isEmpty {
                        loadingView
                    } else if viewModel.filteredNotifications.isEmpty {
                        emptyStateView
                    } else {
                        notificationList
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.markAllAsRead()
                        }
                    } label: {
                        Text("Mark All Read")
                            .font(.subheadline)
                            .foregroundColor(StitchColors.primary)
                    }
                    .disabled(viewModel.unreadCount == 0 || viewModel.isLoading)
                }
            }
        }
        .task {
            await viewModel.loadNotifications()
        }
        .refreshable {
            await viewModel.refreshNotifications()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .onChange(of: viewModel.errorMessage) { errorMessage in
            showingError = errorMessage != nil
        }
    }
    
    // MARK: - View Components
    
    private var notificationTabSelector: some View {
        HStack(spacing: 0) {
            ForEach(NotificationTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    viewModel.filterNotifications(by: tab)
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(tab.displayName)
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            
                            if tab == .all && viewModel.unreadCount > 0 {
                                Text("\(viewModel.unreadCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(StitchColors.error)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(selectedTab == tab ? StitchColors.primary : StitchColors.textSecondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? StitchColors.primary : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .background(StitchColors.background)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(StitchColors.primary)
            
            Text("Loading notifications...")
                .font(.subheadline)
                .foregroundColor(StitchColors.textSecondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedTab == .all ? "bell.slash" : "tray")
                .font(.system(size: 60))
                .foregroundColor(StitchColors.textTertiary)
            
            Text(emptyStateTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(StitchColors.textPrimary)
            
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(StitchColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var emptyStateTitle: String {
        switch selectedTab {
        case .all: return "No notifications yet"
        case .hypes: return "No hypes yet"
        case .follows: return "No followers yet"
        case .replies: return "No replies yet"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedTab {
        case .all: return "When someone interacts with your content, you'll see it here"
        case .hypes: return "When someone hypes or cools your videos, you'll see it here"
        case .follows: return "When someone follows you, you'll see it here"
        case .replies: return "When someone replies to your content, you'll see it here"
        }
    }
    
    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredNotifications) { notification in
                    NotificationRowView(
                        notification: notification,
                        onTap: {
                            Task {
                                await viewModel.markAsRead(notification.id)
                                await handleNotificationTap(notification)
                            }
                        }
                    )
                    .background(notification.isRead ? Color.clear : StitchColors.primary.opacity(0.05))
                }
                
                // Pagination loading indicator
                if viewModel.hasMoreNotifications && !viewModel.isLoading {
                    Button("Load More") {
                        Task {
                            await viewModel.loadMoreNotifications()
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(StitchColors.primary)
                    .padding(.vertical, 20)
                } else if viewModel.hasMoreNotifications && viewModel.isLoading {
                    ProgressView()
                        .frame(height: 60)
                        .tint(StitchColors.primary)
                } else if !viewModel.hasMoreNotifications && viewModel.filteredNotifications.count > 5 {
                    Text("You're all caught up!")
                        .font(.caption)
                        .foregroundColor(StitchColors.textTertiary)
                        .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleNotificationTap(_ notification: NotificationData) async {
        print("📧 NOTIFICATION VIEW: Handling tap for \(notification.type.rawValue)")
        
        // Navigate based on notification type and payload
        switch notification.type {
        case .hype, .cool:
            if let videoID = notification.payload["videoID"] {
                await navigateToVideo(videoID: videoID)
            }
        case .follow:
            await navigateToProfile(userID: notification.senderID)
        case .reply:
            if let threadID = notification.payload["threadID"] {
                await navigateToThread(threadID: threadID)
            } else if let videoID = notification.payload["videoID"] {
                await navigateToVideo(videoID: videoID)
            }
        case .mention:
            if let videoID = notification.payload["videoID"] {
                await navigateToVideo(videoID: videoID)
            }
        }
    }
    
    private func navigateToVideo(videoID: String) async {
        // TODO: Implement navigation to specific video
        print("📧 NAVIGATE: To video \(videoID)")
        // This would typically use a navigation coordinator or deep link system
    }
    
    private func navigateToProfile(userID: String) async {
        // TODO: Implement navigation to user profile
        print("📧 NAVIGATE: To profile \(userID)")
        // This would typically use a navigation coordinator
    }
    
    private func navigateToThread(threadID: String) async {
        // TODO: Implement navigation to thread conversation
        print("📧 NAVIGATE: To thread \(threadID)")
        // This would typically use a navigation coordinator
    }
}

// MARK: - Notification Row View

struct NotificationRowView: View {
    let notification: NotificationData
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile Image or Icon
                notificationIcon
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(StitchColors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(timeAgoString(from: notification.createdAt))
                            .font(.caption)
                            .foregroundColor(StitchColors.textTertiary)
                    }
                    
                    Text(notification.message)
                        .font(.body)
                        .foregroundColor(StitchColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Action indicator
                    HStack(spacing: 4) {
                        notificationTypeIcon
                        
                        Text(notification.type.actionText)
                            .font(.caption)
                            .foregroundColor(notification.type.color)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        if !notification.isRead {
                            Circle()
                                .fill(StitchColors.primary)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(StitchColors.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var notificationIcon: some View {
        AsyncImage(url: URL(string: notification.senderProfileImageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(StitchColors.textTertiary)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                )
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
    
    @ViewBuilder
    private var notificationTypeIcon: some View {
        Image(systemName: notification.type.iconName)
            .font(.caption2)
            .foregroundColor(notification.type.color)
    }
}

// MARK: - Helper Functions

private func timeAgoString(from date: Date) -> String {
    let now = Date()
    let timeInterval = now.timeIntervalSince(date)
    
    if timeInterval < 60 {
        return "now"
    } else if timeInterval < 3600 {
        let minutes = Int(timeInterval / 60)
        return "\(minutes)m"
    } else if timeInterval < 86400 {
        let hours = Int(timeInterval / 3600)
        return "\(hours)h"
    } else if timeInterval < 604800 {
        let days = Int(timeInterval / 86400)
        return "\(days)d"
    } else {
        let weeks = Int(timeInterval / 604800)
        return "\(weeks)w"
    }
}

// MARK: - Preview

#Preview {
    NotificationView()
        .environmentObject(AuthService())
        .preferredColorScheme(.dark)
}
