//
//  CreatorProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - External User Profile Display (View-Only)
//  Dependencies: UserService, FollowManager, VideoService (Layer 4-7)
//  Features: Follow/unfollow, share, report, IDENTICAL layout to ProfileView
//  VISUAL PARITY: Hype meter, badges, verification, same layout as ProfileView
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CreatorProfileView: View {
    
    // MARK: - Properties
    
    let userID: String
    
    // MARK: - Dependencies
    
    @StateObject private var followManager = FollowManager()
    private let userService = UserService()
    private let videoService = VideoService()
    
    // MARK: - State
    
    @State private var user: BasicUserInfo?
    @State private var userVideos: [CoreVideoMetadata] = []
    @State private var followersList: [BasicUserInfo] = []
    @State private var followingList: [BasicUserInfo] = []
    @State private var isLoading = true
    @State private var isLoadingFollowers = false
    @State private var isLoadingFollowing = false
    @State private var errorMessage: String?
    
    // MARK: - Video Player State
    
    @State private var showingVideoPlayer = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var selectedVideoIndex = 0
    @State private var isLoadingVideos = false
    
    // MARK: - UI State
    
    @State private var scrollOffset: CGFloat = 0
    @State private var showStickyTabBar = false
    @State private var selectedTab = 0
    @State private var showingShareSheet = false
    @State private var showingReportSheet = false
    @State private var showingFollowersList = false
    @State private var isShowingFullBio = false
    
    // MARK: - Animation State (Matching ProfileView)
    
    @State private var shimmerOffset: CGFloat = 0
    @State private var hypeProgress: CGFloat = 0
    
    // MARK: - Dismiss
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let user = user {
                    profileContent(user: user)
                } else {
                    errorView
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await loadUserProfile()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let user = user {
                shareSheet(for: user)
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            if let user = user {
                reportSheet(for: user)
            }
        }
        .sheet(isPresented: $showingFollowersList) {
            followersListSheet
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let selectedVideo = selectedVideo {
                FullscreenVideoView(
                    video: selectedVideo,
                    onDismiss: {
                        showingVideoPlayer = false
                    }
                )
            }
        }
    }
    
    // MARK: - Loading and Error Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            
            Text("Loading profile...")
                .foregroundColor(.gray)
                .padding(.top, 10)
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(errorMessage ?? "This profile could not be loaded.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Try Again") {
                Task {
                    await loadUserProfile()
                }
            }
            .foregroundColor(.cyan)
            .padding(.top, 10)
        }
    }
    
    // MARK: - Profile Content
    
    private func profileContent(user: BasicUserInfo) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    optimizedProfileHeader(user: user)
                    tabBarSection
                    videoGridSection
                }
                .background(scrollTracker)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(CreatorScrollOffsetPreferenceKey.self) { value in
                handleScrollChange(value)
            }
            .overlay(alignment: .top) {
                if showStickyTabBar {
                    stickyTabBar
                }
            }
        }
    }
    
    // MARK: - Optimized Profile Header (IDENTICAL to ProfileView)
    
    private func optimizedProfileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
            // Top Navigation
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                
                Spacer()
                
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                
                Button(action: { showingReportSheet = true }) {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Section 1: Profile Image & Basic Info
            HStack(spacing: 16) {
                enhancedProfileImage(user: user)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Name and verification
                    HStack(spacing: 8) {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.red) // RED VERIFIED BADGE
                        }
                    }
                    
                    // Username
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Tier badge
                    tierBadge(user: user)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Section 2: Bio (Full Width) - MATCHING ProfileView
            if shouldShowBio(user: user) {
                VStack(alignment: .leading, spacing: 8) {
                    bioSection(user: user)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            
            // Section 3: PROMINENT HYPE METER (Full Width) - MATCHING ProfileView
            VStack(spacing: 12) {
                hypeMeterSection(user: user)
            }
            .padding(.horizontal, 20)
            
            // Section 4: Stats Row
            statsRow(user: user)
            
            // Section 5: Action Buttons
            actionButtonsRow(user: user)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Enhanced Profile Image (IDENTICAL to ProfileView)
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            // Main profile image with tier-colored border
            AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: tierColors(for: user.tier),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
        }
    }
    
    // MARK: - Tier Badge (IDENTICAL to ProfileView)
    
    private func tierBadge(user: BasicUserInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tierIcon(for: user.tier))
                .font(.caption)
                .foregroundColor(tierColors(for: user.tier)[0])
            
            Text(user.tier.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(tierColors(for: user.tier)[0])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tierColors(for: user.tier)[0].opacity(0.15))
        )
    }
    
    // MARK: - Bio Section (IDENTICAL to ProfileView)
    
    private func shouldShowBio(user: BasicUserInfo) -> Bool {
        return !getBioText(user: user).isEmpty
    }
    
    private func bioSection(user: BasicUserInfo) -> some View {
        let bioText = getBioText(user: user)
        let shouldTruncate = bioText.count > 100
        
        return VStack(alignment: .leading, spacing: 8) {
            if shouldTruncate && !isShowingFullBio {
                Text(String(bioText.prefix(100)) + "...")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(3)
                
                Button("Show more") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingFullBio = true
                    }
                }
                .font(.caption)
                .foregroundColor(.cyan)
            } else {
                Text(bioText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                if shouldTruncate && isShowingFullBio {
                    Button("Show less") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isShowingFullBio = false
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                }
            }
        }
    }
    
    // MARK: - Hype Meter Section (IDENTICAL to ProfileView)
    
    private func hypeMeterSection(user: BasicUserInfo) -> some View {
        VStack(spacing: 12) {
            // Hype meter header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    Text("Hype Meter")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(calculateHypeLevel(user: user)))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            
            // Animated hype meter bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 12)
                    
                    // Animated fill with shimmer effect
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * (hypeProgress / 100.0),
                            height: 12
                        )
                        .overlay(
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.3), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .offset(x: shimmerOffset)
                                .clipped()
                        )
                        .animation(.easeInOut(duration: 1.0), value: hypeProgress)
                }
            }
            .frame(height: 12)
            .onAppear {
                // Animate hype meter on appear
                withAnimation(.easeInOut(duration: 1.5)) {
                    hypeProgress = calculateHypeLevel(user: user)
                }
                
                // Start shimmer animation
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    shimmerOffset = 200
                }
            }
        }
    }
    
    // MARK: - Stats Row
    
    private func statsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 40) {
            CreatorStatView(title: "Threads", count: userVideos.count)
            
            Button(action: {
                Task {
                    await loadFollowers()
                    await loadFollowing()
                }
                showingFollowersList = true
            }) {
                CreatorStatView(title: "Stitchers", count: followersList.count + followingList.count)
            }
            .buttonStyle(PlainButtonStyle())
            
            CreatorStatView(title: "Clout", count: user.clout)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Action Buttons Row
    
    private func actionButtonsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 12) {
            // Follow/Following button
            Button(action: {
                Task {
                    await followManager.toggleFollow(for: user.id)
                }
            }) {
                HStack(spacing: 8) {
                    if followManager.isLoading(user.id) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(followManager.isFollowing(user.id) ? .black : .white)
                    } else {
                        Image(systemName: followManager.isFollowing(user.id) ? "person.check.fill" : "person.plus.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(followManager.isFollowing(user.id) ? "Following" : "Follow")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(followManager.isFollowing(user.id) ? .gray : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(followManager.isFollowing(user.id) ? Color.gray.opacity(0.3) : Color.cyan)
                )
            }
            .disabled(followManager.isLoading(user.id))
            
            // Subscribe button
            Button(action: {
                // TODO: Implement subscription
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Subscribe")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.gray, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Bar Section
    
    private var tabBarSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CreatorTabButton(
                    title: "Threads",
                    count: userVideos.count,
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }
                
                CreatorTabButton(
                    title: "Stitches",
                    count: getThreadCount(),
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }
            .background(Color.black)
            
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .padding(.top, 20)
    }
    
    // MARK: - Sticky Tab Bar
    
    private var stickyTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CreatorTabButton(
                    title: "Threads",
                    count: userVideos.count,
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }
                
                CreatorTabButton(
                    title: "Stitches",
                    count: getThreadCount(),
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }
            .background(Color.black)
            
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(Color.black)
    }
    
    // MARK: - Video Grid Section
    
    private var videoGridSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(Array(filteredVideos().enumerated()), id: \.element.id) { index, video in
                VideoThumbnailView(
                    video: video,
                    showEngagementBadge: true
                ) {
                    selectedVideo = video
                    selectedVideoIndex = index
                    showingVideoPlayer = true
                }
                .aspectRatio(9/16, contentMode: .fill)
                .clipped()
            }
        }
        .padding(.top, 20)
        .overlay(
            // Loading indicator for videos
            Group {
                if isLoadingVideos && userVideos.isEmpty {
                    VStack {
                        ProgressView()
                            .tint(.white)
                        Text("Loading videos...")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    .padding(.top, 40)
                }
            }
        )
    }
    
    // MARK: - Load Functions
    
    private func loadUserProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load user profile
            if let userProfile = try await userService.getUser(id: userID) {
                await MainActor.run {
                    self.user = userProfile
                }
                
                // Load user videos
                let videosResult = try await videoService.getUserVideos(userID: userID)
                await MainActor.run {
                    self.userVideos = videosResult.items
                    self.isLoading = false
                }
                
                // Load follow status
                await followManager.loadFollowState(for: userID)
                
                // Load initial follower/following counts
                await loadFollowers()
                await loadFollowing()
                
            } else {
                await MainActor.run {
                    self.errorMessage = "User not found"
                    self.isLoading = false
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func loadFollowers() async {
        guard !isLoadingFollowers else { return }
        
        await MainActor.run {
            isLoadingFollowers = true
        }
        
        do {
            // Get follower IDs using UserService
            let followerIDs = try await userService.getFollowerIDs(userID: userID)
            
            // Convert IDs to BasicUserInfo objects
            let followers = try await userService.getUsers(ids: followerIDs)
            
            await MainActor.run {
                self.followersList = followers
                self.isLoadingFollowers = false
            }
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowers = false
            }
            print("Error loading followers: \(error)")
        }
    }
    
    private func loadFollowing() async {
        guard !isLoadingFollowing else { return }
        
        await MainActor.run {
            isLoadingFollowing = true
        }
        
        do {
            // Get following IDs using UserService
            let followingIDs = try await userService.getFollowingIDs(userID: userID)
            
            // Convert IDs to BasicUserInfo objects
            let following = try await userService.getUsers(ids: followingIDs)
            
            await MainActor.run {
                self.followingList = following
                self.isLoadingFollowing = false
            }
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowing = false
            }
            print("Error loading following: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    private func getBioText(user: BasicUserInfo) -> String {
        return user.bio ?? "Welcome to my profile! Check out my latest videos and join the conversation."
    }
    
    private func tierBaseRating(for tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 10.0
        case .rising: return 25.0
        case .veteran: return 40.0
        case .influencer: return 55.0
        case .ambassador: return 62.5
        case .elite: return 70.0
        case .partner: return 80.0
        case .legendary: return 90.0
        case .topCreator: return 95.0
        case .founder, .coFounder: return 100.0
        }
    }
    
    private func filteredVideos() -> [CoreVideoMetadata] {
        if selectedTab == 0 {
            // All threads
            return userVideos
        } else {
            // Thread starter videos only (now called "Stitches")
            return userVideos.filter { $0.replyToVideoID == nil }
        }
    }
    
    private func getThreadCount() -> Int {
        return userVideos.filter { $0.replyToVideoID == nil }.count
    }
    
    private func handleScrollChange(_ offset: CGFloat) {
        scrollOffset = offset
        
        // Show sticky tab bar when scrolled past header
        let shouldShowSticky = offset > 200
        if shouldShowSticky != showStickyTabBar {
            showStickyTabBar = shouldShowSticky
        }
    }
    
    private func tierColors(for tier: UserTier) -> [Color] {
        switch tier {
        case .rookie: return [.green, .mint]
        case .rising: return [.blue, .cyan]
        case .veteran: return [.purple, .pink]
        case .influencer: return [.orange, .yellow]
        case .ambassador: return [.indigo, .blue]
        case .elite: return [.red, .orange]
        case .partner: return [.yellow, .orange]
        case .legendary: return [.red, .purple]
        case .topCreator: return [Color(red: 1.0, green: 0.84, blue: 0.0), .yellow]
        case .founder: return [.red, .orange]
        case .coFounder: return [Color(red: 1.0, green: 0.84, blue: 0.0), .orange]
        }
    }
    
    private func tierIcon(for tier: UserTier) -> String {
        switch tier {
        case .rookie: return "leaf.fill"
        case .rising: return "arrow.up.circle.fill"
        case .veteran: return "star.fill"
        case .influencer: return "flame.fill"
        case .ambassador: return "shield.fill"
        case .elite: return "crown.fill"
        case .partner: return "handshake.fill"
        case .legendary: return "trophy.fill"
        case .topCreator: return "diamond.fill"
        case .founder: return "diamond.fill"
        case .coFounder: return "diamond.fill"
        }
    }
    
    private func calculateHypeLevel(user: BasicUserInfo) -> CGFloat {
        let baseRating = tierBaseRating(for: user.tier)
        let cloutBonus = min(Double(user.clout) * 0.001, 20.0)
        let verificationBonus = user.isVerified ? 10.0 : 0.0
        
        return CGFloat(min(baseRating + cloutBonus + verificationBonus, 100.0))
    }
    
    // MARK: - Scroll Tracker
    
    private var scrollTracker: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CreatorScrollOffsetPreferenceKey.self,
                value: geometry.frame(in: .named("scroll")).minY
            )
        }
    }
    
    // MARK: - Sheet Views
    
    private func shareSheet(for user: BasicUserInfo) -> some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Share Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text("Share @\(user.username)'s profile with others")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                // Share options would go here
                Button("Copy Link") {
                    // TODO: Implement copy profile link
                    showingShareSheet = false
                }
                .foregroundColor(.cyan)
                .padding()
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingShareSheet = false }
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func reportSheet(for user: BasicUserInfo) -> some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Report @\(user.username)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text("What's the issue with this profile?")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 12) {
                    CreatorReportOptionButton(title: "Inappropriate Content", icon: "exclamationmark.triangle.fill")
                    CreatorReportOptionButton(title: "Spam or Fake Account", icon: "person.fill.xmark")
                    CreatorReportOptionButton(title: "Harassment or Bullying", icon: "hand.raised.fill")
                    CreatorReportOptionButton(title: "Impersonation", icon: "person.2.fill")
                    CreatorReportOptionButton(title: "Other", icon: "ellipsis.circle.fill")
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showingReportSheet = false }
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var followersListSheet: some View {
        NavigationView {
            StitchersListView(
                followersList: followersList,
                followingList: followingList,
                isLoadingFollowers: isLoadingFollowers,
                isLoadingFollowing: isLoadingFollowing
            )
            .navigationTitle("Stitchers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFollowersList = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Back")
                                .font(.caption)
                        }
                        .foregroundColor(.cyan)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StitchersListView: View {
    let followersList: [BasicUserInfo]
    let followingList: [BasicUserInfo]
    let isLoadingFollowers: Bool
    let isLoadingFollowing: Bool
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Followers")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTab == 0 ? .white : .gray)
                            
                            Text("(\(followersList.count))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Rectangle()
                            .fill(selectedTab == 0 ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Button(action: { selectedTab = 1 }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Following")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTab == 1 ? .white : .gray)
                            
                            Text("(\(followingList.count))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Rectangle()
                            .fill(selectedTab == 1 ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.black)
            .padding(.top, 10)
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Content
            ZStack {
                Color.black.ignoresSafeArea()
                
                if selectedTab == 0 {
                    // Followers tab
                    if isLoadingFollowers {
                        ProgressView()
                            .tint(.white)
                    } else if followersList.isEmpty {
                        VStack {
                            Text("No Followers")
                                .foregroundColor(.white)
                        }
                    } else {
                        ScrollView {
                            LazyVStack {
                                ForEach(followersList, id: \.id) { user in
                                    CreatorUserRowView(user: user)
                                }
                            }
                            .padding()
                        }
                    }
                } else {
                    // Following tab
                    if isLoadingFollowing {
                        ProgressView()
                            .tint(.white)
                    } else if followingList.isEmpty {
                        VStack {
                            Text("Not Following Anyone")
                                .foregroundColor(.white)
                        }
                    } else {
                        ScrollView {
                            LazyVStack {
                                ForEach(followingList, id: \.id) { user in
                                    CreatorUserRowView(user: user)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }
}

struct CreatorStatView: View {
    let title: String
    let count: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text(formatCount(count))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return String(count)
        }
    }
}

struct CreatorTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .gray)
                    
                    Text("(\(count))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Rectangle()
                    .fill(isSelected ? Color.cyan : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CreatorUserRowView: View {
    let user: BasicUserInfo
    @StateObject private var followManager = FollowManager()
    @State private var showingProfile = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            Button(action: { showingProfile = true }) {
                AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showingProfile = true }) {
                VStack(alignment: .leading) {
                    Text(user.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Follow/Unfollow button
            Button(action: {
                Task {
                    await followManager.toggleFollow(for: user.id)
                }
            }) {
                HStack(spacing: 6) {
                    if followManager.isLoading(user.id) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(followManager.isFollowing(user.id) ? .gray : .cyan)
                    } else {
                        Image(systemName: followManager.isFollowing(user.id) ? "person.check.fill" : "person.plus.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text(followManager.isFollowing(user.id) ? "Following" : "Follow")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(followManager.isFollowing(user.id) ? .gray : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(followManager.isFollowing(user.id) ? Color.gray.opacity(0.3) : Color.cyan)
                )
            }
            .disabled(followManager.isLoading(user.id))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear {
            Task {
                await followManager.loadFollowState(for: user.id)
            }
        }
        .sheet(isPresented: $showingProfile) {
            CreatorProfileView(userID: user.id)
                .navigationBarHidden(true)
        }
    }
}

struct CreatorReportOptionButton: View {
    let title: String
    let icon: String
    
    var body: some View {
        Button(action: {
            // TODO: Handle report option selection
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(width: 30)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preference Key for Scroll Tracking

struct CreatorScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Supporting Types

struct CreatorBadgeInfo: Identifiable {
    let id = UUID()
    let imageURL: String
    let title: String
    let description: String
}
