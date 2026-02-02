//
//  ProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Optimized Profile Display with Fixed Video Grid and FullscreenVideoView
//  Dependencies: ProfileViewModel (Layer 7), VideoThumbnailView, EditProfileView, ProfileVideoGrid, FullscreenVideoView
//  Features: Lightweight thumbnails, profile refresh, proper video playback with vertical navigation
//  FIXED: Removed .onAppear/.onDisappear modifiers that were breaking fullScreenCover
//  UPDATED: Added Collections Row between header and tabs
//  UPDATED: Added pinned videos support and infinite scroll pagination
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel: ProfileViewModel
    private let authService: AuthService
    private let userService: UserService
    private let videoService: VideoService
    private let viewingUserID: String?
    @Environment(\.dismiss) var dismiss
    
    
    // MARK: - State Variables
    
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0  // 🔧 For swipe down to dismiss
    @State private var showStickyTabBar = false
    @State private var showingFollowersList = false
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingAdOpportunities = false
    
    // MARK: - Video Player State
    
    /// Wrapper for video presentation to work with item-based fullScreenCover
    struct VideoPresentation: Identifiable, Equatable {
        let id: String
        let video: CoreVideoMetadata
        let context: OverlayContext
        
        static func == (lhs: VideoPresentation, rhs: VideoPresentation) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @State private var videoPresentation: VideoPresentation?
    
    // MARK: - Video Deletion State
    
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoreVideoMetadata?
    @State private var isDeletingVideo = false
    
    // MARK: - Bio State
    
    @State private var isShowingFullBio = false
    
    // MARK: - Collections State
    
    @State private var userCollections: [VideoCollection] = []
    @State private var userDrafts: [CollectionDraft] = []
    @State private var isLoadingCollections = false
    @State private var showingCollectionComposer = false
    @State private var showingCollectionPlayer = false
    @State private var selectedCollection: VideoCollection?
    @EnvironmentObject var muteManager: MuteContextManager
    @State private var selectedDraft: CollectionDraft?
    @State private var showingAllCollections = false
    @State private var collectionError: String?
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService? = nil, viewingUserID: String? = nil) {
        let videoSvc = videoService ?? VideoService()
        self.authService = authService
        self.userService = userService
        self.videoService = videoSvc
        self.viewingUserID = viewingUserID
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userService: userService,
            videoService: videoSvc,
            viewingUserID: viewingUserID
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
            
            // Close button for viewing other user's profile
            if viewingUserID != nil {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .offset(y: max(0, dragOffset))  // 🔧 Allow dragging down only
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow swipe down when viewing other user
                    if viewingUserID != nil {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // Dismiss if swiped down more than 100 points
                    if viewingUserID != nil && value.translation.height > 100 {
                        dismiss()
                    } else {
                        // Snap back
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task(id: viewingUserID) {
            await viewModel.loadProfile()
            await loadCollections()
        }
.onAppear {
            if let user = viewModel.currentUser {
                let hypeProgress = CGFloat(viewModel.calculateHypeProgress())
                viewModel.animationController.startEntranceSequence(hypeProgress: hypeProgress)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshProfile"))) { _ in
            Task {
                await viewModel.refreshProfile()
                await loadCollections()
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
        // Ad Opportunities Sheet
        .sheet(isPresented: $showingAdOpportunities) {
            if let user = viewModel.currentUser {
                AdOpportunitiesView(user: user)
                    .preferredColorScheme(.dark)
            }
        }
        // FIXED: Use item-based fullScreenCover to avoid race condition
        .fullScreenCover(item: $videoPresentation) { presentation in
            FullscreenVideoView(
                video: presentation.video,
                overlayContext: presentation.context,
                onDismiss: {
                    print("📱 PROFILE: Dismissing fullscreen")
                    NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                    videoPresentation = nil
                }
            )
        }
        // Collection Composer Sheet
        .sheet(isPresented: $showingCollectionComposer) {
            if let user = viewModel.currentUser {
                NavigationStack {
                    CollectionComposerSheet(
                        user: user,
                        existingDraft: selectedDraft,
                        onDismiss: {
                            showingCollectionComposer = false
                            selectedDraft = nil
                            Task { await loadCollections() }
                        }
                    )
                }
                .preferredColorScheme(.dark)
            }
        }
        // Collection Player
        .fullScreenCover(isPresented: $showingCollectionPlayer) {
            if let collection = selectedCollection, let user = viewModel.currentUser {
                CollectionPlayerView(
                    viewModel: CollectionPlayerViewModel(collection: collection, userID: user.id),
                    coordinator: CollectionCoordinator(userID: user.id, username: user.username),
                    onDismiss: {
                        showingCollectionPlayer = false
                        selectedCollection = nil
                    }
                )
            }
        }
        // All Collections Sheet
        .sheet(isPresented: $showingAllCollections) {
            if let user = viewModel.currentUser {
                NavigationStack {
                    ProfileCollectionsTab(
                        profileUserID: user.id,
                        isOwnProfile: viewModel.isOwnProfile,
                        coordinator: CollectionCoordinator(userID: user.id, username: user.username)
                    )
                    .navigationTitle("Collections")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showingAllCollections = false
                                Task { await loadCollections() }
                            }
                            .foregroundColor(.cyan)
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
        .onChange(of: videoPresentation) { oldValue, newValue in
            print("🔍 DEBUG: videoPresentation changed to \(newValue?.id ?? "nil")")
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
        // Collection Error Alert
        .alert("Collections", isPresented: Binding(
            get: { collectionError != nil },
            set: { if !$0 { collectionError = nil } }
        )) {
            Button("OK") { collectionError = nil }
        } message: {
            Text(collectionError ?? "")
        }
    }

    // MARK: - Profile Content

    private func profileContent(user: BasicUserInfo) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    optimizedProfileHeader(user: user)
                    collectionsRow
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
    
    // MARK: - Collections Row
    
    @ViewBuilder
    private var collectionsRow: some View {
        if let user = viewModel.currentUser {
            ProfileCollectionsRow(
                collections: userCollections,
                drafts: viewModel.isOwnProfile ? userDrafts : [],
                isOwnProfile: viewModel.isOwnProfile,
                isEligible: user.tier.isAmbassadorOrHigher,
                onAddTap: {
                    if userDrafts.count >= 10 {
                        collectionError = "You've reached the maximum of 10 drafts. Please delete some drafts first."
                    } else {
                        selectedDraft = nil
                        showingCollectionComposer = true
                    }
                },
                onCollectionTap: { collection in
                    selectedCollection = collection
                    showingCollectionPlayer = true
                },
                onDraftTap: { draft in
                    selectedDraft = draft
                    showingCollectionComposer = true
                },
                onDraftDelete: { draft in
                    deleteDraft(draft)
                },
                onSeeAllTap: {
                    showingAllCollections = true
                }
            )
        }
    }
    
    // MARK: - Draft Deletion
    
    private func deleteDraft(_ draft: CollectionDraft) {
        Task {
            do {
                let collectionService = CollectionService()
                try await collectionService.deleteDraft(draftID: draft.id)
                
                // Remove from local array
                userDrafts.removeAll { $0.id == draft.id }
                
                print("🗑️ PROFILE: Deleted draft \(draft.id)")
            } catch {
                collectionError = "Failed to delete draft: \(error.localizedDescription)"
                print("❌ PROFILE: Failed to delete draft: \(error)")
            }
        }
    }
    
    // MARK: - Collections Loading
    
    private func loadCollections() async {
        guard let userID = viewModel.currentUser?.id else { return }
        
        isLoadingCollections = true
        
        do {
            let collectionService = CollectionService()
            userCollections = try await collectionService.getUserCollections(userID: userID)
            
            if viewModel.isOwnProfile {
                userDrafts = try await collectionService.loadUserDrafts(creatorID: userID)
            }
            
            print("📚 PROFILE: Loaded \(userCollections.count) collections, \(userDrafts.count) drafts")
        } catch {
            print("❌ PROFILE: Failed to load collections: \(error)")
        }
        
        isLoadingCollections = false
    }
    
    // MARK: - Optimized Profile Header
    
    private func optimizedProfileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                enhancedProfileImage(user: user)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    tierBadge(user: user)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            if shouldShowBio(user: user) {
                VStack(alignment: .leading, spacing: 8) {
                    bioSection(user: user)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            
            VStack(spacing: 12) {
                hypeMeterSection(user: user)
            }
            .padding(.horizontal, 20)
            
            statsRow(user: user)
            actionButtonsRow(user: user)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Enhanced Profile Image
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)
            
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
    
    // MARK: - Hype Meter Section
    
    private func hypeMeterSection(user: BasicUserInfo) -> some View {
        let hypeRating = calculateHypeRating(user: user)
        let progress = CGFloat(hypeRating / 100.0)
        
        return VStack(spacing: 8) {
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
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
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
            statItem(title: "Videos", value: "\(viewModel.userVideos.count + viewModel.pinnedVideos.count)")
            
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
                
                // Ad Opportunities Button (Influencer+ only)
                if AdRevenueShare.canAccessAds(tier: user.tier) {
                    Button(action: { showingAdOpportunities = true }) {
                        ZStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                    }
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
                    Text("Subscribe")
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
    
    // MARK: - Video Grid Section (UPDATED with Pinning & Pagination)
    
    private var videoGridSection: some View {
        ProfileVideoGrid(
            videos: viewModel.filteredVideos(for: viewModel.selectedTab),
            selectedTab: viewModel.selectedTab,
            tabTitles: viewModel.tabTitles,
            isLoading: viewModel.isLoadingVideos,
            isCurrentUserProfile: viewModel.isOwnProfile,
            pinnedVideos: viewModel.pinnedVideos,
            canPinMore: viewModel.pinnedVideoIDs.count < ProfileViewModel.maxPinnedVideos,
            hasMoreVideos: viewModel.hasMoreVideos,
            isLoadingMore: viewModel.isLoadingMoreVideos,
            onVideoTap: { video, index, videos in
                openVideoInFullscreen(video: video)
            },
            onVideoDelete: { video in
                Task { await deleteVideo(video) }
            },
            onPinVideo: { video in
                Task {
                    let success = await viewModel.pinVideo(video)
                    if success {
                        print("📌 PROFILE: Pinned video \(video.id)")
                    }
                }
            },
            onUnpinVideo: { video in
                Task {
                    let success = await viewModel.unpinVideo(video)
                    if success {
                        print("📌 PROFILE: Unpinned video \(video.id)")
                    }
                }
            },
            isVideoPinned: { video in
                viewModel.isVideoPinned(video)
            },
            onLoadMore: {
                Task {
                    await viewModel.loadMoreVideos()
                }
            }
        )
    }
    
    // MARK: - Video Navigation (FIXED - Item-based presentation)
    
    private func openVideoInFullscreen(video: CoreVideoMetadata) {
        print("📱 PROFILE: Tapped video \(video.id.prefix(8))")
        
        // Kill all players first
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        
        // Present with small delay for cleanup, using item-based presentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.videoPresentation = VideoPresentation(
                id: video.id,
                video: video,
                context: viewModel.isOwnProfile ? .profileOwn : .profileOther
            )
        }
    }
    
    // MARK: - Video Deletion
    
    private func deleteVideo(_ video: CoreVideoMetadata) async {
        let success = await viewModel.deleteVideo(video)
        if success {
            print("Video deleted successfully")
        }
    }
    
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
                isLoadingFollowing: viewModel.isLoadingFollowing,
                authService: authService,
                userService: userService,
                videoService: videoService
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

// MARK: - Collection Composer Sheet Helper

struct CollectionComposerSheet: View {
    let user: BasicUserInfo
    let existingDraft: CollectionDraft?
    let onDismiss: () -> Void
    
    @StateObject private var viewModel: CollectionComposerViewModel
    @StateObject private var coordinator: CollectionCoordinator
    @State private var isCreating = false
    @State private var error: String?
    
    init(user: BasicUserInfo, existingDraft: CollectionDraft?, onDismiss: @escaping () -> Void) {
        self.user = user
        self.existingDraft = existingDraft
        self.onDismiss = onDismiss
        
        let coord = CollectionCoordinator(userID: user.id, username: user.username)
        _coordinator = StateObject(wrappedValue: coord)
        
        if let draft = existingDraft {
            _viewModel = StateObject(wrappedValue: CollectionComposerViewModel(draft: draft, username: user.username))
        } else {
            _viewModel = StateObject(wrappedValue: CollectionComposerViewModel(userID: user.id, username: user.username))
        }
    }
    
    var body: some View {
        Group {
            if isCreating {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Creating collection...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Dismiss") { onDismiss() }
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if viewModel.draftID != nil || existingDraft != nil {
                CollectionComposerView(
                    viewModel: viewModel,
                    coordinator: coordinator,
                    onDismiss: onDismiss
                )
            } else {
                Color.black
            }
        }
        .task {
            if existingDraft == nil && viewModel.draftID == nil {
                isCreating = true
                await viewModel.createNewDraft()
                isCreating = false
                
                if let err = viewModel.errorMessage {
                    error = err
                }
            }
        }
    }
}

// MARK: - UserTier Extension

extension UserTier {
    var isAmbassadorOrHigher: Bool {
        switch self {
        case .ambassador, .elite, .partner, .legendary, .topCreator, .founder, .coFounder:
            return true
        case .rookie, .rising, .veteran, .influencer:
            return false
        }
    }
}

// MARK: - Supporting Views

extension ProfileView {
    struct ProfileStitchersListView: View {
        let followersList: [BasicUserInfo]
        let followingList: [BasicUserInfo]
        let isLoadingFollowers: Bool
        let isLoadingFollowing: Bool
        let authService: AuthService
        let userService: UserService
        let videoService: VideoService
        
        @State private var selectedTab = 0
        @ObservedObject private var followManager = FollowManager.shared
        
        var body: some View {
            VStack(spacing: 0) {
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
                
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if selectedTab == 0 {
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
                                        ProfileUserRowView(
                                            user: user,
                                            authService: authService,
                                            userService: userService,
                                            videoService: videoService
                                        )
                                    }
                                }
                                .padding()
                            }
                        }
                    } else {
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
                                        ProfileUserRowView(
                                            user: user,
                                            authService: authService,
                                            userService: userService,
                                            videoService: videoService
                                        )
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Batch load follow states for all users
                Task {
                    let allUserIDs = (followersList + followingList).map { $0.id }
                    await followManager.loadFollowStates(for: allUserIDs)
                }
            }
        }
    }
    
    struct ProfileUserRowView: View {
        let user: BasicUserInfo
        let authService: AuthService
        let userService: UserService
        let videoService: VideoService
        @State private var showingProfile = false
        @ObservedObject private var followManager = FollowManager.shared
        
        private var isCurrentUser: Bool {
            user.id == authService.currentUserID
        }
        
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
                
                // Don't show follow button for current user
                if !isCurrentUser {
                    followButton
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onAppear {
                Task {
                    await followManager.loadFollowState(for: user.id)
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService,
                    viewingUserID: user.id
                )
                    .navigationBarHidden(true)
            }
        }
        
        @ViewBuilder
        private var followButton: some View {
            let isFollowing = followManager.isFollowing(user.id)
            let isLoading = followManager.isLoading(user.id)
            
            Button(action: {
                Task {
                    await followManager.toggleFollow(for: user.id)
                }
            }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(isFollowing ? .black : .white)
                    } else {
                        Image(systemName: isFollowing ? "checkmark" : "person.plus.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text(isLoading ? "" : (isFollowing ? "Following" : "Follow"))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isFollowing ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isFollowing ? Color.white : Color.cyan)
                )
            }
            .disabled(isLoading)
        }
    }
    
    struct ScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
