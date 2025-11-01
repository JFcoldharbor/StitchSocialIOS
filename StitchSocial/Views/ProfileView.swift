//
//  ProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Optimized Profile Display with Fixed Video Grid and Refresh
//  Dependencies: ProfileViewModel (Layer 7), VideoThumbnailView, EditProfileView, ProfileVideoGrid
//  Features: Lightweight thumbnails, profile refresh, proper video playback, thumbnail caching, thread navigation
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel: ProfileViewModel
    private let userService: UserService
    
    // MARK: - State Variables (Updated for Stitchers)
    
    @State private var scrollOffset: CGFloat = 0
    @State private var showStickyTabBar = false
    @State private var showingFollowersList = false // Now shows Stitchers view
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingVideoPlayer = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var selectedVideoIndex = 0
    
    // MARK: - Video Deletion State
    
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoreVideoMetadata?
    @State private var isDeletingVideo = false
    
    // MARK: - Bio State
    
    @State private var isShowingFullBio = false
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService? = nil) {
        let videoSvc = videoService ?? VideoService()
        self.userService = userService
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userService: userService,
            videoService: videoSvc
        ))
    }

// MARK: - Thread Video Navigation View (PROPER PARENT→CHILD STRUCTURE)

struct ThreadVideoNavigationView: View {
    let thread: ThreadData
    let initialVideoIndex: Int
    let onClose: () -> Void
    let onEngagement: (InteractionType, CoreVideoMetadata) -> Void
    
    @State private var currentVideoIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimating: Bool = false
    @State private var isDragging: Bool = false
    
    private var totalVideos: Int {
        return 1 + thread.childVideos.count // parent + children
    }
    
    private var currentVideo: CoreVideoMetadata {
        if currentVideoIndex == 0 {
            return thread.parentVideo
        } else if currentVideoIndex - 1 < thread.childVideos.count {
            return thread.childVideos[currentVideoIndex - 1]
        } else {
            return thread.parentVideo // Fallback
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VideoPlayerView(
                video: currentVideo,
                isActive: true,
                onEngagement: { interactionType in
                    onEngagement(interactionType, currentVideo)
                }
            )
            .id(currentVideo.id) // Force view refresh when video changes
            .offset(x: dragOffset.width)
            .onTapGesture {
                if !isDragging {
                    onClose()
                }
            }
            
            // Thread navigation indicators
            if totalVideos > 1 {
                VStack {
                    HStack {
                        Spacer()
                        threadNavigationIndicators
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                    
                    Spacer()
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.top, 60)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    if !isAnimating {
                        isDragging = true
                        let horizontalTranslation = value.translation.width
                        let verticalTranslation = value.translation.height
                        
                        // Strong horizontal bias - must be 3x more horizontal than vertical
                        if abs(horizontalTranslation) > abs(verticalTranslation) * 3 {
                            dragOffset = CGSize(width: horizontalTranslation * 0.3, height: 0)
                            print("THREAD NAV: Dragging horizontally: \(horizontalTranslation)")
                        }
                    }
                }
                .onEnded { value in
                    print("THREAD NAV: Drag ended with translation: \(value.translation)")
                    handleSwipeEnd(value: value)
                }
        )
        .onAppear {
            currentVideoIndex = max(0, min(initialVideoIndex, totalVideos - 1))
            print("THREAD NAV: Opened thread \(thread.id) with \(totalVideos) videos at index \(currentVideoIndex)")
            print("THREAD NAV: Parent: \(thread.parentVideo.title)")
            print("THREAD NAV: Children: \(thread.childVideos.count)")
            print("THREAD NAV: Current video: \(currentVideo.title)")
        }
    }
    
    private var threadNavigationIndicators: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(totalVideos, 10), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == currentVideoIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == 0 ? 12 : 8, height: 6) // Parent is wider
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
    
    private func handleSwipeEnd(value: DragGesture.Value) {
        guard !isAnimating else {
            isDragging = false
            return
        }
        
        let threshold: CGFloat = 50
        let translation = value.translation.width
        let velocity = value.velocity.width
        
        print("THREAD NAV: HandleSwipeEnd - translation: \(translation), velocity: \(velocity)")
        print("THREAD NAV: Current index: \(currentVideoIndex), total videos: \(totalVideos)")
        
        isAnimating = true
        
        let shouldNavigate = abs(translation) > threshold || abs(velocity) > 800
        
        if shouldNavigate {
            if (translation > 0 || velocity > 800) && currentVideoIndex > 0 {
                // Swipe right - previous video in thread
                let newIndex = currentVideoIndex - 1
                currentVideoIndex = newIndex
                print("THREAD NAV: Changed to previous video - new index: \(newIndex)")
                print("THREAD NAV: New video: \(currentVideo.title)")
            } else if (translation < 0 || velocity < -800) && currentVideoIndex < totalVideos - 1 {
                // Swipe left - next video in thread
                let newIndex = currentVideoIndex + 1
                currentVideoIndex = newIndex
                print("THREAD NAV: Changed to next video - new index: \(newIndex)")
                print("THREAD NAV: New video: \(currentVideo.title)")
            } else {
                print("THREAD NAV: No navigation - at boundary or insufficient gesture")
            }
        } else {
            print("THREAD NAV: Gesture too small - threshold: \(threshold), translation: \(abs(translation))")
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = .zero
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAnimating = false
            isDragging = false
        }
    }
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
        .onAppear {
            // Start profile animations when user is loaded
            if let user = viewModel.currentUser {
                let hypeProgress = CGFloat(viewModel.calculateHypeProgress())
                viewModel.animationController.startEntranceSequence(hypeProgress: hypeProgress)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshProfile"))) { _ in
            Task {
                await viewModel.refreshProfile()
            }
        }
        .sheet(isPresented: $showingFollowersList) {
            stitchersSheet
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
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performVideoDelete() }
            }
        } message: {
            if let video = videoToDelete {
                Text("Are you sure you want to delete '\(video.title)'? This action cannot be undone.")
            }
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
    
    // MARK: - Optimized Profile Header
    
    private func optimizedProfileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
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
            
            // Section 2: Bio (Full Width)
            if shouldShowBio(user: user) {
                VStack(alignment: .leading, spacing: 8) {
                    bioSection(user: user)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            
            // Section 3: PROMINENT HYPE METER (Full Width)
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
    
    // MARK: - Enhanced Profile Image
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            // Progress ring background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)
            
            // Clout progress ring
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
    
    // MARK: - Bio Section
    
    private func bioSection(user: BasicUserInfo) -> some View {
        Group {
            if let bio = getBioForUser(user), !bio.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bio)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(isShowingFullBio ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if bio.count > 80 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isShowingFullBio.toggle()
                            }
                        }) {
                            Text(isShowingFullBio ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else if viewModel.isOwnProfile {
                Button(action: { showingEditProfile = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                        
                        Text("Add bio")
                            .font(.body)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Hype Meter Section (PROMINENT)
    
    private func hypeMeterSection(user: BasicUserInfo) -> some View {
        let hypeRating = calculateHypeRating(user: user)
        let progress = CGFloat(hypeRating / 100.0)
        
        return VStack(spacing: 8) {
            // Title and percentage
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Hype Rating")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(hypeRating))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Progress bar with shimmer
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 12)
                        .overlay(
                            // Shimmer effect
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.6), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .offset(x: viewModel.animationController.shimmerOffset)
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            print("🔥 HYPE METER SECTION APPEARED: Rating \(Int(hypeRating))%")
            viewModel.animationController.startEntranceSequence(hypeProgress: progress)
        }
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
    
    // MARK: - Stats Row
    
    private func statsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 30) {
            statItem(title: "Videos", value: "\(viewModel.userVideos.count)")
            
            Button(action: {
                Task {
                    await viewModel.loadFollowers()
                    await viewModel.loadFollowing()
                }
                showingFollowersList = true
            }) {
                statItem(title: "Stitchers", value: "\(viewModel.followersList.count)")
            }
            .buttonStyle(PlainButtonStyle())
            
            statItem(title: "Clout", value: viewModel.formatClout(user.clout))
        }
        .padding(.horizontal, 20)
    }
    
    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
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
                Button(action: { showingEditProfile = true }) {
                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
            } else {
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
                    
                    Text("(\(viewModel.getTabCount(for: index)))")
                        .font(.system(size: 10))
                        .foregroundColor(viewModel.selectedTab == index ?
                            .cyan.opacity(0.8) : .gray.opacity(0.6))
                }
                
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
    
    // MARK: - Video Grid Section (USING NEW ProfileVideoGrid COMPONENT)
    
    private var videoGridSection: some View {
        ProfileVideoGrid(
            videos: viewModel.filteredVideos(for: viewModel.selectedTab),
            selectedTab: viewModel.selectedTab,
            tabTitles: viewModel.tabTitles,
            isLoading: viewModel.isLoadingVideos,
            isCurrentUserProfile: viewModel.isOwnProfile,
            onVideoTap: { video, index, videos in
                openVideoWithThreadNavigation(video: video, index: index, videos: videos)
            },
            onVideoDelete: { video in
                Task { await deleteVideo(video) }
            }
        )
    }
    
    // MARK: - Thread Navigation Integration (FIXED THREAD STRUCTURE)
    
    private func openVideoWithThreadNavigation(video: CoreVideoMetadata, index: Int, videos: [CoreVideoMetadata]) {
        selectedVideo = video
        selectedVideoIndex = index
        showingVideoPlayer = true
        
        // Get the specific thread for this video
        Task {
            do {
                // If this video has a threadID, get the full thread
                if let threadID = video.threadID {
                    let threadChildren = try await viewModel.loadThreadChildren(threadID: threadID)
                    let fullThread = ThreadData(
                        id: threadID,
                        parentVideo: video,
                        childVideos: threadChildren
                    )
                    await MainActor.run {
                        currentThread = fullThread
                        currentVideoInThread = 0 // Start with parent
                    }
                } else {
                    // This video is standalone, create single-video thread
                    let standaloneThread = ThreadData(
                        id: video.id,
                        parentVideo: video,
                        childVideos: []
                    )
                    await MainActor.run {
                        currentThread = standaloneThread
                        currentVideoInThread = 0
                    }
                }
            } catch {
                print("Failed to load thread: \(error)")
                // Fallback to standalone
                await MainActor.run {
                    currentThread = ThreadData(
                        id: video.id,
                        parentVideo: video,
                        childVideos: []
                    )
                    currentVideoInThread = 0
                }
            }
        }
    }
    
    // MARK: - Thread Navigation State (CORRECTED)
    
    @State private var currentThread: ThreadData?
    @State private var currentVideoInThread: Int = 0
    
    // MARK: - Video Deletion
    
    private func deleteVideo(_ video: CoreVideoMetadata) async {
        let success = await viewModel.deleteVideo(video)
        if success {
            print("Video deleted successfully")
        }
    }
    
    // MARK: - Performance Optimization
    
    private func preloadAdjacentVideos() {
        let videos = viewModel.filteredVideos(for: viewModel.selectedTab)
        let indices = [
            max(0, selectedVideoIndex - 1),
            min(videos.count - 1, selectedVideoIndex + 1)
        ]
        
        for index in indices {
            if index < videos.count {
                let video = videos[index]
                // Preload video data
                Task {
                    _ = video.videoURL // Access for caching
                }
            }
        }
    }
    
    // MARK: - Full Screen Video Player with Thread Navigation (CORRECTED)
    
    private var fullScreenVideoPlayer: some View {
        Group {
            if let thread = currentThread {
                ThreadVideoNavigationView(
                    thread: thread,
                    initialVideoIndex: currentVideoInThread,
                    onClose: {
                        showingVideoPlayer = false
                    },
                    onEngagement: { interactionType, video in
                        handleGridEngagement(interactionType, video: video)
                    }
                )
            }
        }
    }
    
    // MARK: - Engagement Handling
    
    private func handleGridEngagement(_ interactionType: InteractionType, video: CoreVideoMetadata) {
        Task {
            // Handle engagement through viewModel if available
            print("Handling engagement: \(interactionType) for video: \(video.id)")
        }
    }
    
    // MARK: - Video Management
    
    private func performVideoDelete() async {
        guard let video = videoToDelete else { return }
        isDeletingVideo = true
        
        let success = await viewModel.deleteVideo(video)
        if success {
            print("Video deleted successfully: \(video.title)")
        }
        
        isDeletingVideo = false
        videoToDelete = nil
    }
    
    // MARK: - Sticky Tab Bar
    
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
    
    // MARK: - Sheet Views
    
    private var stitchersSheet: some View {
        NavigationView {
            ProfileStitchersListView(
                followersList: viewModel.followersList,
                followingList: viewModel.followingList,
                isLoadingFollowers: viewModel.isLoadingFollowers,
                isLoadingFollowing: viewModel.isLoadingFollowing
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
        .onAppear {
            Task {
                await viewModel.loadFollowers()
                await viewModel.loadFollowing()
            }
        }
    }

    private var settingsSheet: some View {
        SettingsView()
            .environmentObject(viewModel.authService)
    }

    private var editProfileSheet: some View {
        Group {
            if let user = viewModel.currentUser {
                NewEditProfileView(
                    userService: userService,
                    currentUser: user,
                    onSave: { updatedUser in
                        viewModel.currentUser = updatedUser
                        showingEditProfile = false
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func shouldShowBio(user: BasicUserInfo) -> Bool {
        return getBioForUser(user) != nil || viewModel.isOwnProfile
    }
    
    private func getBioForUser(_ user: BasicUserInfo) -> String? {
        if let bio = viewModel.getBioForUser(user) {
            return bio
        }
        
        if user.isVerified {
            return generateContextualBio(for: user)
        }
        
        if user.tier.isFounderTier {
            return generateSampleBio(for: user)
        }
        
        return nil
    }
    
    private func generateContextualBio(for user: BasicUserInfo) -> String? {
        let videoCount = viewModel.userVideos.count
        let followerCount = viewModel.followersList.count
        let clout = user.clout
        
        var bioComponents: [String] = []
        
        if clout > OptimizationConfig.User.defaultStartingClout * 5 {
            bioComponents.append("🌟 High performer")
        }
        
        if videoCount >= OptimizationConfig.Threading.maxChildrenPerThread {
            bioComponents.append("📹 Active creator")
        }
        
        if followerCount >= 100 {
            bioComponents.append("👥 Community leader")
        }
        
        if user.tier != .rookie {
            bioComponents.append("🚀 \(user.tier.displayName)")
        }
        
        if user.isVerified {
            bioComponents.append("✅ Verified")
        }
        
        let bio = bioComponents.joined(separator: " | ")
        return bio.count <= OptimizationConfig.User.maxBioLength ? bio : nil
    }
    
    private func generateSampleBio(for user: BasicUserInfo) -> String? {
        switch user.tier {
        case .founder:
            return "Building the future of social video 🚀 | Creator of Stitch Social"
        case .coFounder:
            return "Co-founder at Stitch Social | Passionate about connecting creators 🎬"
        case .topCreator:
            return "Top creator with \(viewModel.formatClout(user.clout)) clout | Making viral content daily ✨"
        case .partner:
            return "Official partner creator | \(viewModel.userVideos.count) threads and counting 🔥"
        default:
            return nil
        }
    }
    
    private func calculateHypeRating(user: BasicUserInfo) -> Double {
        let hypeRating = HypeRating(
            userID: user.id,
            baseRating: tierBaseRating(for: user.tier),
            startingBonus: getUserStartingBonus(for: user)
        )
        
        let userVideos = viewModel.userVideos
        let engagementScore: Double = {
            guard !userVideos.isEmpty else { return 0.0 }
            
            let totalHypes = userVideos.reduce(0) { $0 + $1.hypeCount }
            let totalCools = userVideos.reduce(0) { $0 + $1.coolCount }
            let totalViews = userVideos.reduce(0) { $0 + $1.viewCount }
            let totalReplies = userVideos.reduce(0) { $0 + $1.replyCount }
            
            let totalReactions = totalHypes + totalCools
            let engagementRatio = totalReactions > 0 ? Double(totalHypes) / Double(totalReactions) : 0.5
            let engagementPoints = engagementRatio * Double(InteractionType.hype.pointValue) * 1.5
            
            let viewEngagementRatio = totalViews > 0 ? Double(totalReactions) / Double(totalViews) : 0.0
            let viewPoints = min(10.0, viewEngagementRatio * 1000.0)
            
            let maxThreadChildren = Double(OptimizationConfig.Threading.maxChildrenPerThread)
            let replyBonus = min(5.0, Double(totalReplies) / maxThreadChildren * 5.0)
            
            return engagementPoints + viewPoints + replyBonus
        }()
        
        let activityScore: Double = {
            let recentVideos = userVideos.filter {
                Date().timeIntervalSince($0.createdAt) < OptimizationConfig.Threading.trendingWindowHours * 3600
            }
            return min(15.0, Double(recentVideos.count) * 2.5)
        }()
        
        let cloutBaseline = Double(OptimizationConfig.User.defaultStartingClout)
        let cloutBonus = min(10.0, Double(user.clout) / cloutBaseline * 10.0)
        
        let followerThreshold = Double(OptimizationConfig.Performance.maxBackgroundTasks)
        let socialBonus = min(8.0, Double(viewModel.followersList.count) / followerThreshold * 8.0)
        
        let verificationBonus: Double = user.isVerified ? 5.0 : 0.0
        
        let baseRating = hypeRating.effectiveRating
        let bonusPoints = engagementScore + activityScore + cloutBonus + socialBonus + verificationBonus
        let finalRating = (baseRating / 100.0 * 50.0) + bonusPoints
        
        let clampedRating = min(100.0, max(0.0, finalRating))
        
        print("🔥 HYPE METER: \(user.username) = \(Int(clampedRating))%")
        
        return clampedRating
    }
    
    private func tierBaseRating(for tier: UserTier) -> Double {
        let baseClout = Double(OptimizationConfig.User.defaultStartingClout)
        
        switch tier {
        case .founder, .coFounder: return baseClout * 0.063
        case .topCreator: return baseClout * 0.057
        case .partner: return baseClout * 0.050
        case .influencer: return baseClout * 0.043
        case .rising: return baseClout * 0.033
        case .rookie: return baseClout * 0.023
        default: return baseClout * 0.017
        }
    }
    
    private func getUserStartingBonus(for user: BasicUserInfo) -> UserStartingBonus {
        if user.isVerified {
            return .betaTester
        } else if user.tier.isFounderTier {
            return .earlyAdopter
        } else {
            return .newcomer
        }
    }
    
    private func getTierColors(_ tier: UserTier) -> [Color] {
        switch tier {
        case .founder, .coFounder: return [.yellow, .orange]
        case .topCreator: return [.blue, .purple]
        case .partner: return [.green, .mint]
        case .influencer: return [.pink, .purple]
        case .rising: return [.cyan, .blue]
        case .rookie: return [.gray, .white]
        default: return [.gray, .white]
        }
    }
    
    private func getTierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .founder, .coFounder: return "crown.fill"
        case .topCreator: return "star.fill"
        case .partner: return "handshake.fill"
        case .influencer: return "megaphone.fill"
        case .rising: return "arrow.up.circle.fill"
        case .rookie: return "person.circle.fill"
        default: return "person.circle"
        }
    }
    
    // MARK: - Helper Views
    
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
}

// MARK: - Supporting Views and Extensions

// ProfileStitchersListView - Renamed to avoid conflicts with CreatorProfileView
struct ProfileStitchersListView: View {
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
                                    ProfileUserRowView(user: user)
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
                                    ProfileUserRowView(user: user)
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

// ProfileUserRowView - Individual user row with interaction
struct ProfileUserRowView: View {
    let user: BasicUserInfo
    @State private var showingProfile = false
    
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
            
            // Follow/Unfollow button (if not current user)
            Button(action: {
                // TODO: Implement follow toggle
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.plus.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cyan)
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingProfile) {
            CreatorProfileView(userID: user.id)
                .navigationBarHidden(true)
        }
    }
}

// Extension to ProfileViewModel for thread navigation
extension ProfileViewModel {
    /// Load thread children for navigation
    func loadThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        // Create a temporary VideoService instance to access the method
        let tempVideoService = VideoService()
        return try await tempVideoService.getThreadChildren(threadID: threadID)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - UserListView (Helper)

struct UserListView: View {
    let title: String
    let users: [BasicUserInfo]
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                VStack {
                    Text("No \(title)")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(users, id: \.id) { user in
                    HStack {
                        AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(user.displayName)
                                .foregroundColor(.white)
                            Text("@\(user.username)")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }
                .listStyle(PlainListStyle())
            }
        }
        .background(Color.black)
    }
}

// MARK: - EditProfileView is imported from separate file
// EditProfileView.swift should be a separate file in the project
