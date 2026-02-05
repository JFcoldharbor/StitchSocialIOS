//
//  StitchersListView.swift
//  StitchSocial
//
//  Layer 8: Views - Standalone Stitchers/Following/Followers/Blocked Management
//  Dependencies: FollowManager, UserService, AuthService
//  Features: Paginated lists, search, follow/unfollow, block/unblock, remove follower
//

import SwiftUI

// MARK: - Main View

struct StitchersListView: View {
    
    // MARK: - Dependencies
    
    let profileUserID: String
    let profileUsername: String
    let isOwnProfile: Bool
    let authService: AuthService
    let userService: UserService
    let videoService: VideoService
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StitchersViewModel
    
    // MARK: - State
    
    @State private var selectedTab: StitchersTab = .followers
    @State private var searchText = ""
    @State private var showingProfile: BasicUserInfo?
    
    // MARK: - Initialization
    
    init(
        profileUserID: String,
        profileUsername: String,
        isOwnProfile: Bool,
        authService: AuthService,
        userService: UserService,
        videoService: VideoService
    ) {
        self.profileUserID = profileUserID
        self.profileUsername = profileUsername
        self.isOwnProfile = isOwnProfile
        self.authService = authService
        self.userService = userService
        self.videoService = videoService
        self._viewModel = StateObject(wrappedValue: StitchersViewModel(
            userID: profileUserID,
            userService: userService
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Bar
                    tabBar
                    
                    // Search Bar (own profile only)
                    if isOwnProfile {
                        searchBar
                    }
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        followersTab
                            .tag(StitchersTab.followers)
                        
                        followingTab
                            .tag(StitchersTab.following)
                        
                        if isOwnProfile {
                            blockedTab
                                .tag(StitchersTab.blocked)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("@\(profileUsername)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .task {
                await viewModel.loadInitialData()
            }
            .sheet(item: $showingProfile) { user in
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService,
                    viewingUserID: user.id
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .followers, title: "Followers", count: viewModel.totalFollowers)
            tabButton(tab: .following, title: "Following", count: viewModel.totalFollowing)
            
            if isOwnProfile {
                tabButton(tab: .blocked, title: "Blocked", count: viewModel.blockedUsers.count)
            }
        }
        .padding(.top, 8)
        .background(Color.black)
    }
    
    private func tabButton(tab: StitchersTab, title: String, count: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .gray)
                    
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedTab == tab ? .cyan : .gray.opacity(0.7))
                }
                
                Rectangle()
                    .fill(selectedTab == tab ? Color.cyan : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            TextField("Search", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Followers Tab
    
    private var followersTab: some View {
        Group {
            if viewModel.isLoadingFollowers && viewModel.followers.isEmpty {
                loadingView
            } else if filteredFollowers.isEmpty {
                emptyView(
                    icon: "person.2",
                    title: searchText.isEmpty ? "No Followers Yet" : "No Results",
                    subtitle: searchText.isEmpty ? "When people follow \(isOwnProfile ? "you" : "@\(profileUsername)"), they'll appear here." : "Try a different search term"
                )
            } else {
                userList(
                    users: filteredFollowers,
                    listType: .followers,
                    isLoadingMore: viewModel.isLoadingMoreFollowers,
                    hasMore: viewModel.hasMoreFollowers,
                    onLoadMore: { Task { await viewModel.loadMoreFollowers() } }
                )
            }
        }
    }
    
    // MARK: - Following Tab
    
    private var followingTab: some View {
        Group {
            if viewModel.isLoadingFollowing && viewModel.following.isEmpty {
                loadingView
            } else if filteredFollowing.isEmpty {
                emptyView(
                    icon: "person.badge.plus",
                    title: searchText.isEmpty ? "Not Following Anyone" : "No Results",
                    subtitle: searchText.isEmpty ? "\(isOwnProfile ? "You're" : "@\(profileUsername) is") not following anyone yet." : "Try a different search term"
                )
            } else {
                userList(
                    users: filteredFollowing,
                    listType: .following,
                    isLoadingMore: viewModel.isLoadingMoreFollowing,
                    hasMore: viewModel.hasMoreFollowing,
                    onLoadMore: { Task { await viewModel.loadMoreFollowing() } }
                )
            }
        }
    }
    
    // MARK: - Blocked Tab
    
    private var blockedTab: some View {
        Group {
            if viewModel.isLoadingBlocked && viewModel.blockedUsers.isEmpty {
                loadingView
            } else if filteredBlocked.isEmpty {
                emptyView(
                    icon: "hand.raised.slash",
                    title: searchText.isEmpty ? "No Blocked Users" : "No Results",
                    subtitle: searchText.isEmpty ? "Users you block won't be able to see your content or interact with you." : "Try a different search term"
                )
            } else {
                userList(
                    users: filteredBlocked,
                    listType: .blocked,
                    isLoadingMore: false,
                    hasMore: false,
                    onLoadMore: {}
                )
            }
        }
    }
    
    // MARK: - User List
    
    private func userList(
        users: [BasicUserInfo],
        listType: StitchersTab,
        isLoadingMore: Bool,
        hasMore: Bool,
        onLoadMore: @escaping () -> Void
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    StitcherUserRow(
                        user: user,
                        listType: listType,
                        isOwnProfile: isOwnProfile,
                        onTap: { showingProfile = user },
                        onFollow: { Task { await viewModel.toggleFollow(for: user.id) } },
                        onBlock: { Task { await viewModel.toggleBlock(for: user.id) } },
                        onRemoveFollower: { Task { await viewModel.removeFollower(user.id) } }
                    )
                    .onAppear {
                        if index >= users.count - 5 && hasMore && !isLoadingMore {
                            onLoadMore()
                        }
                    }
                    
                    if index < users.count - 1 {
                        Divider()
                            .background(Color.gray.opacity(0.2))
                            .padding(.leading, 76)
                    }
                }
                
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.cyan)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty View
    
    private func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Filtered Lists
    
    private var filteredFollowers: [BasicUserInfo] {
        guard !searchText.isEmpty else { return viewModel.followers }
        let query = searchText.lowercased()
        return viewModel.followers.filter {
            $0.username.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
    }
    
    private var filteredFollowing: [BasicUserInfo] {
        guard !searchText.isEmpty else { return viewModel.following }
        let query = searchText.lowercased()
        return viewModel.following.filter {
            $0.username.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
    }
    
    private var filteredBlocked: [BasicUserInfo] {
        guard !searchText.isEmpty else { return viewModel.blockedUsers }
        let query = searchText.lowercased()
        return viewModel.blockedUsers.filter {
            $0.username.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
    }
}

// MARK: - Tab Enum

enum StitchersTab: Int, CaseIterable {
    case followers = 0
    case following = 1
    case blocked = 2
}

// MARK: - User Row

struct StitcherUserRow: View {
    
    let user: BasicUserInfo
    let listType: StitchersTab
    let isOwnProfile: Bool
    let onTap: () -> Void
    let onFollow: () -> Void
    let onBlock: () -> Void
    let onRemoveFollower: () -> Void
    
    @ObservedObject private var followManager = FollowManager.shared
    @State private var showingOptions = false
    
    private var isFollowing: Bool {
        followManager.isFollowing(user.id)
    }
    
    private var isLoading: Bool {
        followManager.isLoading(user.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Button(action: onTap) {
                avatarView
            }
            .buttonStyle(PlainButtonStyle())
            
            // User Info
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.cyan)
                        }
                        
                        tierBadge
                    }
                    
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Action Button
            actionButton
            
            // More Options (own profile only)
            if isOwnProfile && listType != .blocked {
                moreButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
        .contentShape(Rectangle())
        .confirmationDialog("Options", isPresented: $showingOptions) {
            optionsDialogContent
        }
    }
    
    // MARK: - Avatar
    
    private var avatarView: some View {
        AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(tierBorderColor, lineWidth: 2)
            )
    }
    
    // MARK: - Tier Badge
    
    @ViewBuilder
    private var tierBadge: some View {
        if user.tier != .rookie {
            Text(user.tier.displayName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(tierBadgeColor)
                )
        }
    }
    
    private var tierBorderColor: Color {
        switch user.tier {
        case .legendary, .coFounder, .founder: return .yellow
        case .elite, .partner: return .purple
        case .ambassador, .topCreator: return .cyan
        case .influencer, .veteran: return .blue
        default: return .gray.opacity(0.3)
        }
    }
    
    private var tierBadgeColor: Color {
        switch user.tier {
        case .legendary, .coFounder, .founder: return .yellow
        case .elite, .partner: return .purple
        case .ambassador, .topCreator: return .cyan
        case .influencer, .veteran: return .blue
        default: return .gray
        }
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private var actionButton: some View {
        switch listType {
        case .blocked:
            // Unblock button
            Button(action: onBlock) {
                Text("Unblock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.8))
                    )
            }
            
        default:
            // Follow/Following button
            Button(action: onFollow) {
                HStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(isFollowing ? .black : .white)
                    } else {
                        if isFollowing {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundColor(isFollowing ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFollowing ? Color.white : Color.cyan)
                )
            }
            .disabled(isLoading)
        }
    }
    
    // MARK: - More Button
    
    private var moreButton: some View {
        Button(action: { showingOptions = true }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
        }
    }
    
    // MARK: - Options Dialog
    
    @ViewBuilder
    private var optionsDialogContent: some View {
        if listType == .followers {
            Button("Remove Follower", role: .destructive) {
                onRemoveFollower()
            }
        }
        
        Button("Block @\(user.username)", role: .destructive) {
            onBlock()
        }
        
        Button("Cancel", role: .cancel) {}
    }
}

// MARK: - ViewModel

@MainActor
class StitchersViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let userID: String
    private let userService: UserService
    private let followManager = FollowManager.shared
    
    // MARK: - Published State
    
    @Published var followers: [BasicUserInfo] = []
    @Published var following: [BasicUserInfo] = []
    @Published var blockedUsers: [BasicUserInfo] = []
    
    @Published var isLoadingFollowers = false
    @Published var isLoadingFollowing = false
    @Published var isLoadingBlocked = false
    
    @Published var isLoadingMoreFollowers = false
    @Published var isLoadingMoreFollowing = false
    
    @Published var hasMoreFollowers = true
    @Published var hasMoreFollowing = true
    
    @Published var totalFollowers = 0
    @Published var totalFollowing = 0
    
    // MARK: - Pagination State
    
    private var allFollowerIDs: [String] = []
    private var allFollowingIDs: [String] = []
    private var loadedFollowerCount = 0
    private var loadedFollowingCount = 0
    private let batchSize = 30
    
    // MARK: - Initialization
    
    init(userID: String, userService: UserService) {
        self.userID = userID
        self.userService = userService
    }
    
    // MARK: - Load Initial Data
    
    func loadInitialData() async {
        async let followersTask: () = loadFollowers()
        async let followingTask: () = loadFollowing()
        async let blockedTask: () = loadBlockedUsers()
        
        _ = await (followersTask, followingTask, blockedTask)
        
        // Load follow states for all users
        let allUserIDs = (followers + following).map { $0.id }
        await followManager.loadFollowStates(for: allUserIDs)
    }
    
    // MARK: - Load Followers
    
    private func loadFollowers() async {
        isLoadingFollowers = true
        
        do {
            let followerIDs = try await userService.getFollowerIDs(userID: userID)
            allFollowerIDs = followerIDs
            totalFollowers = followerIDs.count
            loadedFollowerCount = 0
            
            let firstBatchIDs = Array(followerIDs.prefix(batchSize))
            let users = try await userService.getUsers(ids: firstBatchIDs)
            
            followers = users
            loadedFollowerCount = users.count
            hasMoreFollowers = followerIDs.count > loadedFollowerCount
            
        } catch {
            print("❌ STITCHERS: Failed to load followers: \(error)")
        }
        
        isLoadingFollowers = false
    }
    
    func loadMoreFollowers() async {
        guard !isLoadingMoreFollowers, hasMoreFollowers else { return }
        
        isLoadingMoreFollowers = true
        
        do {
            let startIndex = loadedFollowerCount
            let endIndex = min(startIndex + batchSize, allFollowerIDs.count)
            let nextBatchIDs = Array(allFollowerIDs[startIndex..<endIndex])
            
            let moreUsers = try await userService.getUsers(ids: nextBatchIDs)
            
            followers.append(contentsOf: moreUsers)
            loadedFollowerCount += moreUsers.count
            hasMoreFollowers = loadedFollowerCount < allFollowerIDs.count
            
            // Load follow states for new users
            await followManager.loadFollowStates(for: moreUsers.map { $0.id })
            
        } catch {
            print("❌ STITCHERS: Failed to load more followers: \(error)")
        }
        
        isLoadingMoreFollowers = false
    }
    
    // MARK: - Load Following
    
    private func loadFollowing() async {
        isLoadingFollowing = true
        
        do {
            let followingIDs = try await userService.getFollowingIDs(userID: userID)
            allFollowingIDs = followingIDs
            totalFollowing = followingIDs.count
            loadedFollowingCount = 0
            
            let firstBatchIDs = Array(followingIDs.prefix(batchSize))
            let users = try await userService.getUsers(ids: firstBatchIDs)
            
            following = users
            loadedFollowingCount = users.count
            hasMoreFollowing = followingIDs.count > loadedFollowingCount
            
        } catch {
            print("❌ STITCHERS: Failed to load following: \(error)")
        }
        
        isLoadingFollowing = false
    }
    
    func loadMoreFollowing() async {
        guard !isLoadingMoreFollowing, hasMoreFollowing else { return }
        
        isLoadingMoreFollowing = true
        
        do {
            let startIndex = loadedFollowingCount
            let endIndex = min(startIndex + batchSize, allFollowingIDs.count)
            let nextBatchIDs = Array(allFollowingIDs[startIndex..<endIndex])
            
            let moreUsers = try await userService.getUsers(ids: nextBatchIDs)
            
            following.append(contentsOf: moreUsers)
            loadedFollowingCount += moreUsers.count
            hasMoreFollowing = loadedFollowingCount < allFollowingIDs.count
            
            // Load follow states for new users
            await followManager.loadFollowStates(for: moreUsers.map { $0.id })
            
        } catch {
            print("❌ STITCHERS: Failed to load more following: \(error)")
        }
        
        isLoadingMoreFollowing = false
    }
    
    // MARK: - Load Blocked Users
    
    private func loadBlockedUsers() async {
        isLoadingBlocked = true
        
        // TODO: Implement when UserService.getBlockedUserIDs is available
        // do {
        //     let blockedIDs = try await userService.getBlockedUserIDs(userID: userID)
        //     let users = try await userService.getUsers(ids: blockedIDs)
        //     blockedUsers = users
        // } catch {
        //     print("❌ STITCHERS: Failed to load blocked users: \(error)")
        // }
        
        blockedUsers = []
        isLoadingBlocked = false
    }
    
    // MARK: - Actions
    
    func toggleFollow(for targetUserID: String) async {
        await followManager.toggleFollow(for: targetUserID)
    }
    
    func toggleBlock(for targetUserID: String) async {
        // TODO: Implement when UserService block methods are available
        // do {
        //     if blockedUsers.contains(where: { $0.id == targetUserID }) {
        //         try await userService.unblockUser(blockerID: userID, blockedID: targetUserID)
        //         blockedUsers.removeAll { $0.id == targetUserID }
        //     } else {
        //         try await userService.blockUser(blockerID: userID, blockedID: targetUserID)
        //         if let user = try await userService.getUser(id: targetUserID) {
        //             blockedUsers.append(user)
        //         }
        //         followers.removeAll { $0.id == targetUserID }
        //         following.removeAll { $0.id == targetUserID }
        //     }
        // } catch {
        //     print("❌ STITCHERS: Failed to toggle block: \(error)")
        // }
        print("⚠️ STITCHERS: Block functionality not yet implemented")
    }
    
    func removeFollower(_ followerID: String) async {
        // TODO: Implement when UserService.removeFollower is available
        // do {
        //     try await userService.removeFollower(userID: userID, followerID: followerID)
        //     followers.removeAll { $0.id == followerID }
        //     totalFollowers = max(0, totalFollowers - 1)
        // } catch {
        //     print("❌ STITCHERS: Failed to remove follower: \(error)")
        // }
        print("⚠️ STITCHERS: Remove follower functionality not yet implemented")
    }
}

// MARK: - BasicUserInfo Extension for Identifiable Sheet

extension BasicUserInfo: Identifiable {}

