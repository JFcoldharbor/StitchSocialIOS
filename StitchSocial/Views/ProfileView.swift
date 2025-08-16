//
//  ProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Complete Profile Display with VideoPlayerView Integration
//  Dependencies: ProfileViewModel (Layer 7) ONLY
//  Features: Instagram-style layout, VideoPlayerView grid, contextual overlays, engagement handling
//  ARCHITECTURE COMPLIANT: No business logic, no service calls
//

import SwiftUI

struct ProfileView: View {
    
    // MARK: - Single Dependency (Layer 7)
    
    @StateObject private var viewModel: ProfileViewModel
    
    // MARK: - UI State Only
    
    @State private var scrollOffset: CGFloat = 0
    @State private var showStickyTabBar = false
    @State private var showingFollowingList = false
    @State private var showingFollowersList = false
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingVideoPlayer = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var selectedVideoIndex = 0
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService? = nil) {
        let videoSvc = videoService ?? VideoService()
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userService: userService,
            videoService: videoSvc
        ))
    }
    
    // MARK: - Main Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else if let user = viewModel.currentUser {
                profileContent(user: user)
            } else {
                noUserView
            }
        }
        .task {
            await viewModel.loadProfile()
        }
        .sheet(isPresented: $showingFollowingList) {
            followingSheet
        }
        .sheet(isPresented: $showingFollowersList) {
            followersSheet
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showingEditProfile) {
            editProfileSheet
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            fullScreenVideoPlayer
        }
    }
    
    // MARK: - Main Profile Content
    
    private func profileContent(user: BasicUserInfo) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    profileHeader(user: user)
                    tabBarSection
                    videoGridSection
                }
                .background(scrollTracker)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                handleScrollChange(value)
            }
            .overlay(alignment: .top) {
                if showStickyTabBar {
                    stickyTabBar
                }
            }
        }
    }
    
    // MARK: - Profile Header
    
    private func profileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
            // Row 1: Profile Image & Basic Info
            HStack(spacing: 20) {
                enhancedProfileImage(user: user)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Bio from viewModel if available
                    if let bio = viewModel.getBioForUser(user), !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(3)
                    }
                    
                    // Tier badge
                    tierBadge(user: user)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Row 2: Stats
            statsRow(user: user)
            
            // Row 3: Action Buttons
            actionButtonsRow(user: user)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Profile Image
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            // Progress ring background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)
            
            // Clout progress ring - using viewModel calculation
            Circle()
                .trim(from: 0, to: viewModel.calculateHypeProgress())
                .stroke(
                    LinearGradient(
                        colors: getTierColors(user.tier),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))
            
            // Profile image
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
        }
    }
    
    // MARK: - Stats Row
    
    private func statsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 40) {
            statItem(title: "Videos", value: "\(viewModel.userVideos.count)")
            
            Button(action: { showingFollowersList = true }) {
                statItem(title: "Followers", value: "\(viewModel.followersList.count)")
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showingFollowingList = true }) {
                statItem(title: "Following", value: "\(viewModel.followingList.count)")
            }
            .buttonStyle(PlainButtonStyle())
            
            statItem(title: "Clout", value: viewModel.formatClout(user.clout))
        }
        .padding(.horizontal, 20)
    }
    
    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 12) {
            if viewModel.isOwnProfile {
                // Edit Profile Button
                Button(action: { showingEditProfile = true }) {
                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
                
                // Settings Button
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
            } else {
                // Follow/Following Button
                Button(action: {
                    Task { await viewModel.toggleFollow() }
                }) {
                    Text(viewModel.isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.isFollowing ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(viewModel.isFollowing ? Color.white : Color.cyan)
                        .cornerRadius(8)
                }
                
                // Message Button
                Button(action: { /* Future implementation */ }) {
                    Text("Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tier Badge
    
    private func tierBadge(user: BasicUserInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: getTierIcon(user.tier))
                .font(.caption)
                .foregroundColor(getTierColors(user.tier).first ?? .white)
            
            Text(user.tier.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: getTierColors(user.tier),
                startPoint: .leading,
                endPoint: .trailing
            ).opacity(0.3)
        )
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    // MARK: - Tab Bar Section
    
    private var tabBarSection: some View {
        HStack(spacing: 0) {
            ForEach(0..<viewModel.tabTitles.count, id: \.self) { index in
                tabBarItem(index: index)
            }
        }
        .background(Color.black)
        .padding(.top, 20)
    }
    
    private func tabBarItem(index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.selectedTab = index
            }
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.tabIcons[index])
                        .font(.caption)
                        .foregroundColor(viewModel.selectedTab == index ?
                            .cyan.opacity(0.8) : .gray.opacity(0.6))
                    
                    Text(viewModel.tabTitles[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.selectedTab == index ? .cyan : .gray)
                    
                    Text("(\(viewModel.getTabCount(index)))")
                        .font(.system(size: 10))
                        .foregroundColor(viewModel.selectedTab == index ?
                            .cyan.opacity(0.8) : .gray.opacity(0.6))
                }
                .foregroundColor(viewModel.selectedTab == index ? .cyan : .gray)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(viewModel.selectedTab == index ? Color.cyan : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Video Grid Section
    
    private var videoGridSection: some View {
        Group {
            if viewModel.isLoadingVideos {
                loadingVideosView
            } else if viewModel.filteredVideos(for: viewModel.selectedTab).isEmpty {
                emptyVideosView
            } else {
                videoGrid
            }
        }
        .id(viewModel.selectedTab)
    }
    
    private var videoGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
            spacing: 0
        ) {
            ForEach(Array(viewModel.filteredVideos(for: viewModel.selectedTab).enumerated()), id: \.element.id) { index, video in
                videoGridItem(video: video, index: index)
            }
        }
        .padding(.horizontal, 0)
        .padding(.bottom, 100)
    }
    
    // MARK: - Video Grid Item - Enhanced with VideoPlayerView and Contextual Overlay
    
    private func videoGridItem(video: CoreVideoMetadata, index: Int) -> some View {
        GeometryReader { geometry in
            ZStack {
                // VideoPlayerView with contextual overlay support
                VideoPlayerView(
                    video: video,
                    isActive: false, // Grid mode - minimal overlay
                    onEngagement: { interactionType in
                        handleGridEngagement(interactionType, video: video)
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.width)
                .clipped()
                
                // Tap overlay to open fullscreen
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openVideo(video: video, index: index)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contextMenu {
            videoContextMenu(video: video)
        }
    }
    
    // MARK: - Video Context Menu
    
    private func videoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            Button("Delete Video") {
                Task {
                    let success = await viewModel.deleteVideo(video)
                    if success {
                        print("Video deleted successfully")
                    }
                }
            }
            
            Button("Share") {
                shareVideo(video)
            }
        }
    }
    
    // MARK: - Enhanced Engagement Handling
    
    private func handleGridEngagement(_ interactionType: InteractionType, video: CoreVideoMetadata) {
        Task { @MainActor in
            switch interactionType {
            case .hype:
                // Use VideoService directly since ProfileViewModel doesn't have hypeVideo
                print("Hype video: \(video.title)")
                triggerHapticFeedback(.light)
                
            case .reply:
                // Open replies for this video
                openVideoReplies(video)
                
            case .share:
                shareVideo(video)
                
            case .cool:
                // Use VideoService directly since ProfileViewModel doesn't have coolVideo
                print("Cool video: \(video.title)")
                triggerHapticFeedback(.soft)
                
            case .view:
                // Handle view engagement
                print("View engagement for video: \(video.title)")
            }
        }
        
        print("GRID ENGAGEMENT: \(interactionType.rawValue) on '\(video.title)'")
    }
    
    private func openVideoReplies(_ video: CoreVideoMetadata) {
        // Future implementation: Navigate to replies view
        print("Opening replies for video: \(video.title)")
    }
    
    private func shareVideo(_ video: CoreVideoMetadata) {
        // Future implementation: Share sheet
        print("Sharing video: \(video.title)")
    }
    
    // MARK: - Helper Methods for Tier Colors and Icons
    
    private func getTierColors(_ tier: UserTier) -> [Color] {
        switch tier {
        case .founder, .coFounder:
            return [.yellow, .orange]
        case .topCreator:
            return [.blue, .purple]
        case .partner:
            return [.green, .mint]
        case .influencer:
            return [.pink, .purple]
        case .rising:
            return [.cyan, .blue]
        case .rookie:
            return [.gray, .white]
        default:
            return [.gray, .white]
        }
    }
    
    private func getTierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .founder, .coFounder:
            return "crown.fill"
        case .topCreator:
            return "star.fill"
        case .partner:
            return "handshake.fill"
        case .influencer:
            return "megaphone.fill"
        case .rising:
            return "arrow.up.circle.fill"
        case .rookie:
            return "person.circle.fill"
        default:
            return "person.circle"
        }
    }
    
    // MARK: - Loading and Error Views
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            
            Text("Loading Profile...")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(error)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                Task { await viewModel.loadProfile() }
            }
            .font(.headline)
            .foregroundColor(.black)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    private var noUserView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No User Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private var loadingVideosView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
            
            Text("Loading Videos...")
                .foregroundColor(.gray)
        }
        .frame(height: 200)
    }
    
    private var emptyVideosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("No \(viewModel.tabTitles[viewModel.selectedTab])")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(height: 400)
    }
    
    private var stickyTabBar: some View {
        VStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 44)
            
            tabBarSection
                .background(Color.black.opacity(0.9))
                .background(.ultraThinMaterial)
            
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - Full Screen Video Player
    
    private var fullScreenVideoPlayer: some View {
        Group {
            if selectedVideoIndex < viewModel.filteredVideos(for: viewModel.selectedTab).count {
                let video = viewModel.filteredVideos(for: viewModel.selectedTab)[selectedVideoIndex]
                VideoPlayerView(
                    video: video,
                    isActive: true, // Active in fullscreen
                    onEngagement: { interactionType in
                        Task {
                            await handleFullScreenEngagement(interactionType, video: video)
                        }
                    }
                )
                .overlay(alignment: .topLeading) {
                    Button(action: { showingVideoPlayer = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.top, 50)
                    .padding(.leading, 20)
                }
                .ignoresSafeArea(.all)
            }
        }
    }
    
    private func handleFullScreenEngagement(_ interactionType: InteractionType, video: CoreVideoMetadata) async {
        switch interactionType {
        case .hype:
            print("Fullscreen hype video: \(video.title)")
            triggerHapticFeedback(.light)
            
        case .reply:
            openVideoReplies(video)
            
        case .share:
            shareVideo(video)
            
        case .cool:
            print("Fullscreen cool video: \(video.title)")
            triggerHapticFeedback(.soft)
            
        case .view:
            print("Fullscreen view engagement for video: \(video.title)")
        }
    }
    
    // MARK: - Sheet Views
    
    private var followingSheet: some View {
        NavigationView {
            UserListView(
                title: "Following",
                users: viewModel.followingList,
                isLoading: viewModel.isLoadingFollowing
            )
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowingList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadFollowing() }
        }
    }
    
    private var followersSheet: some View {
        NavigationView {
            UserListView(
                title: "Followers",
                users: viewModel.followersList,
                isLoading: viewModel.isLoadingFollowers
            )
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowersList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadFollowers() }
        }
    }
    
    private var settingsSheet: some View {
        NavigationView {
            VStack {
                Text("Settings")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingSettings = false }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
    
    private var editProfileSheet: some View {
        NavigationView {
            VStack {
                Text("Edit Profile")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingEditProfile = false }
                        .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { showingEditProfile = false }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var scrollTracker: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self,
                           value: geometry.frame(in: .named("scroll")).minY)
        }
    }
    
    private func handleScrollChange(_ offset: CGFloat) {
        let shouldShow = -offset > 300
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showStickyTabBar = shouldShow
        }
    }
    
    private func openVideo(video: CoreVideoMetadata, index: Int) {
        selectedVideo = video
        selectedVideoIndex = index
        showingVideoPlayer = true
    }
    
    // MARK: - Haptic Feedback
    
    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
}

// MARK: - Supporting Components

struct UserListView: View {
    let title: String
    let users: [BasicUserInfo]
    let isLoading: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if users.isEmpty {
                VStack {
                    Text("No \(title)")
                        .foregroundColor(.white)
                }
            } else {
                ScrollView {
                    LazyVStack {
                        ForEach(users, id: \.id) { user in
                            UserRowView(user: user)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct UserRowView: View {
    let user: BasicUserInfo
    
    var body: some View {
        HStack {
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
