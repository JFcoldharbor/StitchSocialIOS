//
//  NotificationView.swift
//  StitchSocial
//
//  Complete notification view with auto-scrolling discovery
//  UPDATED: Added sender profile pictures with navigation to NotificationRowView
//  FIXED: Profile avatar on left, notification icon top-right, increased row height
//  UPDATED: Fixed navigation to pass threadID and targetVideoID for proper video scrolling
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging
import UserNotifications

// MARK: - StitchNotificationTab Enum

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

// MARK: - NotificationView

struct NotificationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel: NotificationViewModel
    @StateObject private var discoveryService = DiscoveryService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @ObservedObject var followManager = FollowManager.shared
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - UI State
    
    @State private var selectedTab: StitchNotificationTab = .all
    @State private var showingError = false
    @State private var isRefreshing = false
    
    // MARK: - Discovery State
    
    @State private var recentUsers: [RecentUser] = []
    @State private var leaderboardVideos: [LeaderboardVideo] = []
    @State private var isLoadingDiscovery = false
    
    // MARK: - Navigation State
    
    /// Wrapper for profile presentation to work with item-based sheet
    struct ProfilePresentation: Identifiable {
        let id: String  // userID
        var userID: String { id }
    }
    
    /// Wrapper for video thread presentation to avoid race conditions
    struct VideoThreadPresentation: Identifiable {
        let id: String
        let threadID: String
        let targetVideoID: String?
        
        init(threadID: String, targetVideoID: String? = nil) {
            self.id = threadID
            self.threadID = threadID
            self.targetVideoID = targetVideoID
        }
    }
    @State private var videoThreadPresentation: VideoThreadPresentation?
    
    @State private var profilePresentation: ProfilePresentation?
    @State private var selectedVideoID: String?
    @State private var selectedThreadID: String?  // ðŸ†• ADDED
    @State private var targetVideoID: String?      // ðŸ†• ADDED
    @State private var showingVideoThread = false
    @State private var showingJustJoined = false
    @State private var showingTopVideos = false
    
    // MARK: - Auto-scroll State
    
    @State private var currentAvatarIndex = 0
    @State private var timer: Timer?
    
    // MARK: - Computed Properties
    
    private var currentUserID: String {
        authService.currentUser?.id ?? ""
    }
    
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
                        
                        discoverySection
                            .padding(.top, 24)
                            .padding(.horizontal, 20)
                        
                        contentView
                            .padding(.top, 32)
                    }
                }
                .refreshable {
                    await refreshAllData()
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadAllData()
            startAutoScroll()
        }
        .onDisappear {
            stopAutoScroll()
        }
        // FIXED: Use item-based sheet presentation to avoid race condition
        // The userID is guaranteed to be non-nil when the sheet presents
        .sheet(item: $profilePresentation) { presentation in
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService
            )
        }
        .fullScreenCover(item: $videoThreadPresentation) { presentation in
            ThreadView(
                threadID: presentation.threadID,
                videoService: VideoService(),
                userService: UserService(),
                targetVideoID: presentation.targetVideoID
            )
        }
        .sheet(isPresented: $showingJustJoined) {
            JustJoinedView()
        }
        .sheet(isPresented: $showingTopVideos) {
            TopVideosView()
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
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func tabButton(for tab: StitchNotificationTab) -> some View {
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
                    .fill(selectedTab == tab ? Color.purple.opacity(0.8) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Discovery Section
    
    private var discoverySection: some View {
        VStack(spacing: 12) {
            justJoinedSection
            topVideosSection
        }
    }
    
    private var justJoinedSection: some View {
        Button(action: {
            showingJustJoined = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Just Joined")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Text("New")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.8))
                            )
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                
                if recentUsers.isEmpty {
                    emptyDiscoveryCard(message: "No new users")
                } else {
                    AutoScrollAvatarStack(
                        users: recentUsers,
                        currentIndex: $currentAvatarIndex,
                        onUserTap: { userID in
                            profilePresentation = ProfilePresentation(id: userID)
                        }
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var topVideosSection: some View {
        Button(action: {
            showingTopVideos = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top Videos")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                
                if leaderboardVideos.isEmpty {
                    emptyDiscoveryCard(message: "No trending videos")
                } else {
                    CompactLeaderboard(
                        videos: leaderboardVideos,
                        onVideoTap: { videoID in
                            videoThreadPresentation = VideoThreadPresentation(
                                threadID: videoID,
                                targetVideoID: videoID
                            )
                        }
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func emptyDiscoveryCard(message: String) -> some View {
        VStack {
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.filteredNotifications.isEmpty {
                loadingView
            } else if viewModel.filteredNotifications.isEmpty {
                emptyStateView
            } else {
                notificationsList
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.purple)
                .scaleEffect(1.2)
            
            Text("Loading notifications...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(getEmptyStateMessage())
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
    
    private var notificationsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredNotifications) { notification in
                NotificationRowView(
                    notification: notification,
                    currentUserID: currentUserID,
                    onTap: { await handleNotificationTap(notification) },
                    onMarkAsRead: { await viewModel.markAsRead(notification.id) },
                    onProfileTap: { userID in
                        profilePresentation = ProfilePresentation(id: userID)
                    }
                )
                .environmentObject(followManager)
            }
            
            if viewModel.hasMoreNotifications {
                Button {
                    Task { await viewModel.loadMoreNotifications() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.purple)
                                .scaleEffect(0.8)
                        }
                        Text("Load More")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.purple)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Auto-scroll Logic
    
    private func startAutoScroll() {
        guard !recentUsers.isEmpty else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentAvatarIndex = (currentAvatarIndex + 1) % max(1, recentUsers.count)
            }
        }
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
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
        case .all: return "You're all caught up! Check back later for new activity."
        case .unread: return "You've read all your notifications."
        case .hypes: return "Share videos to get hype from the community!"
        case .follows: return "Keep creating content!"
        case .replies: return "Start conversations by replying to videos."
        case .system: return "System notifications will appear here."
        }
    }
    
    // MARK: - Data Loading
    
    private func loadAllData() async {
        await loadInitialNotifications()
        await loadDiscoveryData()
        await loadFollowStatesForNotifications()
    }
    
    private func loadInitialNotifications() async {
        await viewModel.loadNotifications()
    }
    
    private func loadFollowStatesForNotifications() async {
        // Load follow states for all notification senders
        let senderIDs = viewModel.filteredNotifications.map { $0.senderID }
        if !senderIDs.isEmpty {
            await followManager.loadFollowStates(for: senderIDs)
            print("âœ… NOTIFICATION VIEW: Loaded follow states for \(senderIDs.count) senders")
        }
    }
    
    private func loadDiscoveryData() async {
        isLoadingDiscovery = true
        
        do {
            async let usersTask = discoveryService.getRecentUsers(limit: 20)
            async let leaderboardTask = discoveryService.getHypeLeaderboard(limit: 10)
            
            let (users, videos) = try await (usersTask, leaderboardTask)
            
            await MainActor.run {
                recentUsers = users
                leaderboardVideos = videos
                print("âœ… DISCOVERY: Loaded \(users.count) users, \(videos.count) videos")
            }
            
        } catch {
            print("âŒ DISCOVERY: Failed to load - \(error)")
        }
        
        isLoadingDiscovery = false
    }
    
    private func refreshAllData() async {
        await refreshNotifications()
        await loadDiscoveryData()
        await loadFollowStatesForNotifications()
    }
    
    private func refreshNotifications() async {
        await viewModel.refreshNotifications()
    }
    
    // ðŸ†• UPDATED: Extract both threadID and targetVideoID from payload
    private func handleNotificationTap(_ notification: NotificationDisplayData) async {
        await viewModel.markAsRead(notification.id)
        
        // For follow notifications, navigate to the sender's profile instead
        if notification.notificationType == .follow {
            profilePresentation = ProfilePresentation(id: notification.senderID)
            print("ðŸ“± Navigation to profile: \(notification.senderID)")
            return
        }
        
        // For other notifications, try to navigate to video
        if let rawNotification = viewModel.allNotifications.first(where: { $0.id == notification.id }),
           let videoID = rawNotification.payload["videoID"] as? String, !videoID.isEmpty {
            
            // Extract threadID if available, otherwise use videoID as threadID
            let threadID = (rawNotification.payload["threadID"] as? String) ?? videoID
            
            videoThreadPresentation = VideoThreadPresentation(
                threadID: threadID,
                targetVideoID: videoID
            )
            
            
            print("ðŸ“± Navigation to thread: \(threadID), target video: \(videoID)")
        } else {
            print("âš ï¸ No videoID in notification payload for type: \(notification.notificationType.rawValue)")
        }
    }
}

// MARK: - Notification Row View

struct NotificationRowView: View {
    let notification: NotificationDisplayData
    let currentUserID: String
    let onTap: () async -> Void
    let onMarkAsRead: () async -> Void
    let onProfileTap: (String) -> Void
    
    @EnvironmentObject var followManager: FollowManager
    
    var body: some View {
        Button(action: { Task { await onTap() } }) {
            rowContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // LEFT: Profile Picture (tap to view profile)
            Button(action: { onProfileTap(notification.senderID) }) {
                profileAvatar
            }
            .buttonStyle(PlainButtonStyle())
            
            // MIDDLE: Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    notificationText
                    Spacer()
                    notificationIcon
                }
                
                trailingContent
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(rowBackground)
    }
    
    private var profileAvatar: some View {
        Group {
            if let profileImageURL = notification.payload["profileImageURL"] as? String,
               !profileImageURL.isEmpty {
                AsyncThumbnailView.avatar(url: profileImageURL)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .onAppear {
                        print("ðŸ–¼ï¸ PROFILE IMAGE: Loading from URL - \(profileImageURL)")
                    }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .onAppear {
                        print("âš ï¸ PROFILE IMAGE: Missing in payload - \(notification.payload)")
                        print("âš ï¸ Notification ID: \(notification.id)")
                        print("âš ï¸ Sender ID: \(notification.senderID)")
                    }
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var notificationIcon: some View {
        Image(systemName: notification.notificationType.iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(notification.notificationType.color)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(notification.notificationType.color.opacity(0.1))
            )
    }
    
    private var notificationText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notification.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(notification.message)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(2)
            
            Text(timeAgo(from: notification.createdAt))
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 8) {
            if shouldShowFollowButton {
                followBackButton
            }
            
            if !notification.isRead {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private var shouldShowFollowButton: Bool {
        notification.notificationType == .follow &&
        !currentUserID.isEmpty &&
        notification.senderID != currentUserID &&
        !followManager.isFollowing(notification.senderID)
    }
    
    private var followBackButton: some View {
        Button(action: {
            Task {
                await followManager.toggleFollow(for: notification.senderID)
                // Small delay to ensure state updates
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }) {
            HStack(spacing: 4) {
                if followManager.isLoading(notification.senderID) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 10))
                    Text("Follow Back")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cyan)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(followManager.isLoading(notification.senderID))
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(notification.isRead ? Color.gray.opacity(0.1) : Color.purple.opacity(0.1))
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

// MARK: - Auto-Scrolling Avatar Stack

struct AutoScrollAvatarStack: View {
    let users: [RecentUser]
    @Binding var currentIndex: Int
    let onUserTap: (String) -> Void
    
    private let visibleCount = 2  // Reduced from 3 to fit better
    
    private var visibleUsers: [RecentUser] {
        guard !users.isEmpty else { return [] }
        
        var visible: [RecentUser] = []
        for i in 0..<min(visibleCount, users.count) {
            let index = (currentIndex + i) % users.count
            visible.append(users[index])
        }
        return visible
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(visibleUsers.enumerated()), id: \.element.id) { index, user in
                userRow(for: user, at: index)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func userRow(for user: RecentUser, at index: Int) -> some View {
        Button(action: { onUserTap(user.id) }) {
            HStack(spacing: 10) {
                userAvatar(for: user)
                userInfo(for: user)
                Spacer()
            }
            .frame(height: 44)  // Fixed row height
            .opacity(index == 0 ? 1.0 : 0.6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func userAvatar(for user: RecentUser) -> some View {
        AsyncImage(url: URL(string: user.profileImageURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure, .empty:
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    )
            @unknown default:
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }
    
    private func userInfo(for user: RecentUser) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.username)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("Joined \(formatJoinedDate(user.joinedAt))")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatJoinedDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)
        
        if days == 0 {
            return "today"
        } else if days == 1 {
            return "yesterday"
        } else {
            return "\(days)d ago"
        }
    }
}

// MARK: - Compact Leaderboard

struct CompactLeaderboard: View {
    let videos: [LeaderboardVideo]
    let onVideoTap: (String) -> Void
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(Array(videos.prefix(5).enumerated()), id: \.element.id) { index, video in
                    videoRow(for: video, at: index)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }
    
    private func videoRow(for video: LeaderboardVideo, at index: Int) -> some View {
        Button(action: { onVideoTap(video.id) }) {
            HStack(spacing: 10) {
                rankBadge(for: index)
                videoInfo(for: video)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func rankBadge(for index: Int) -> some View {
        ZStack {
            Circle()
                .fill(rankColor(index))
                .frame(width: 28, height: 28)
            
            Text("#\(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func videoInfo(for video: LeaderboardVideo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.creatorName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                Text("\(formatCount(video.hypeCount))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .yellow
        case 1: return .gray
        case 2: return .orange
        default: return .purple.opacity(0.5)
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
