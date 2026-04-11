//
//  DiscoveryView.swift
//  StitchSocial
//
//  Enhanced with weighted algorithm + TTL cache integration
//  FIXED: Fullscreen handling uses .fullScreenCover(item:)
//  FIXED: Observes AnnouncementService to stop video playback
//  FIXED: loadMoreContent APPENDS to end without reshuffling
//  NEW: refreshContent invalidates service caches before re-fetching
//  NEW: Category switches hit TTL cache (0 Firestore reads within 5 min)
//  UPDATED: DiscoveryViewModel extracted to DiscoveryViewModel.swift
//  UPDATED: PreferenceKey frame reporters added for SpotlightOnboardingView
//
//  ONBOARDING FRAME REPORTERS:
//  Each spotlight target reports its real CGRect via a PreferenceKey.
//  ContentView reads these via .onPreferenceChange and passes them into
//  SpotlightOnboardingView. Zero cost — GeometryReader only runs on layout.
//    - OnboardingSwipeCardFrameKey    → swipe card area
//    - OnboardingCommunitiesPillFrameKey → "Communities" pill in category bar
//    - OnboardingSearchIconFrameKey   → magnifyingglass button in toolbar
//  Thread/Stitch/Fullscreen button frames are reported from
//  FullscreenVideoView + ContextualVideoOverlay (wired in those files).
//

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - DiscoveryView

struct DiscoveryView: View {

    // MARK: - State

    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Services

    private let userService = UserService()
    private let videoService = VideoService()

    @ObservedObject private var announcementService = AnnouncementService.shared
    @ObservedObject private var communityService    = CommunityService.shared

    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var discoveryMode:    DiscoveryMode     = .swipe
    // swipeIndex lives in ViewModel — survives tab switches without resetting position
    @State private var showingSearch = false

    // MARK: - Community State

    @State private var showingCommunityDetail = false
    @State private var selectedCommunityItem: CommunityListItem?
    @State private var hasUnreadCommunities = false

    // MARK: - Profile Navigation

    @State private var selectedUserForProfile: String?
    @State private var showingProfileView = false

    // Item-based fullscreen presentation
    @State private var videoPresentation: DiscoveryVideoPresentation?
    @EnvironmentObject var muteManager: MuteContextManager

    // Hashtag navigation
    @State private var selectedHashtagPresentation: DiscoveryHashtagPresentation?

    // MARK: - PYMK State

    @State private var showingPYMK = false

    // Collection player state
    @State private var showingCollectionPlayer = false
    @State private var selectedCollection: VideoCollection?
    
    // Show detail state
    @State private var showingShowDetail = false
    @State private var selectedShowId: String?
    @State private var selectedShowEpisodes: [VideoCollection] = []

    // MARK: - Extracted Body Helpers
    // Split out to avoid compiler type-check timeout on body

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color.purple.opacity(0.3),
                Color.pink.opacity(0.2),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            discoveryToolbar
            categorySelector

            if selectedCategory == .trending || selectedCategory == .hotHashtags {
                trendingHashtagsSection
            }

            if selectedCategory.isVideoCategory, let hashtag = viewModel.selectedHashtag {
                hashtagFilterBar(hashtag)
            }

            if selectedCategory == .communities {
                if let userID = authService.currentUserID {
                    CommunityListView(userID: userID)
                }
            } else if selectedCategory == .pymk {
                if let userID = authService.currentUserID {
                    PeopleYouMayKnowView(userID: userID)
                }
            } else if selectedCategory.isCollectionCategory {
                collectionLaneView
            } else if viewModel.isLoading && viewModel.videos.isEmpty {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(errorMessage)
            } else {
                contentView
            }
        }
    }

    var body: some View {
        ZStack {
            backgroundGradient
            mainContent
        }
        .task {
            await DiscoveryEngagementTracker.shared.loadPreferences()

            if viewModel.filteredVideos.isEmpty {
                await viewModel.loadInitialContent()
            }
            await viewModel.loadTrendingHashtags()

            if let userID = authService.currentUserID {
                if let communities = try? await communityService.fetchMyCommunities(userID: userID) {
                    hasUnreadCommunities = communities.contains { $0.unreadCount > 0 || $0.isCreatorLive }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSearch) {
            SearchView()
        }
        .sheet(item: $selectedHashtagPresentation) { presentation in
            HashtagView(initialHashtag: presentation.hashtag)
        }
        .fullScreenCover(item: $videoPresentation) { presentation in
            FullscreenVideoView(
                video: presentation.video,
                overlayContext: .fullscreen,
                onDismiss: {
                    print("📱 DISCOVERY: Dismissing fullscreen")
                    videoPresentation = nil
                }
            )
        }
        .onChange(of: announcementService.isShowingAnnouncement) { _, isShowing in
            if isShowing {
                print("📢 DISCOVERY: Announcement showing — pausing videos")
            } else {
                print("📢 DISCOVERY: Announcement dismissed — can resume videos")
            }
        }
        // MARK: - Onboarding Triggers
        // swipeCards/swipeToSeed handled via handleSwipeIndexChanged (seed-locking logic).
        // tapFullscreen handled in FullscreenVideoView.onAppear.
        // threadButton/stitchButton handled in ContextualVideoOverlay + ThreadView.
        .onChange(of: viewModel.swipeIndex) { _, newIndex in
            OnboardingState.shared.handleSwipeIndexChanged(to: newIndex)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.handleForeground()
                Task { await viewModel.loadInitialContent() }
            }
        }
        .sheet(isPresented: $showingProfileView) {
            if let userID = selectedUserForProfile {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService
                )
            }
        }
        .fullScreenCover(isPresented: $showingCollectionPlayer) {
            if let collection = selectedCollection {
                CollectionPlayerView(
                    collection: collection,
                    onDismiss: {
                        showingCollectionPlayer = false
                        selectedCollection = nil
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingShowDetail) {
            if let showId = selectedShowId {
                ShowDetailView(
                    showId: showId,
                    initialEpisodes: selectedShowEpisodes,
                    onDismiss: {
                        showingShowDetail = false
                        selectedShowId = nil
                        selectedShowEpisodes = []
                    },
                    onPlayEpisode: { episode in
                        showingShowDetail = false
                        selectedCollection = episode
                        showingCollectionPlayer = true
                    }
                )
            }
        }
    }

    // MARK: - Discovery Toolbar

    private var discoveryToolbar: some View {
        HStack {
            if viewModel.isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    Text("Loading...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan)
                }
            } else {
                if selectedCategory == .communities {
                    Text("\(communityService.myCommunities.count) channels")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            HStack(spacing: 18) {
                if selectedCategory.isVideoCategory {
                    Button {
                        viewModel.reshuffleAndRestart()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.cyan)
                    }

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            discoveryMode = discoveryMode == .grid ? .swipe : .grid
                        }
                    } label: {
                        Image(systemName: discoveryMode.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(discoveryMode == .swipe ? .cyan : .white.opacity(0.6))
                    }
                }

                // ONBOARDING: search icon frame reported via PreferenceKey
                Button {
                    showingSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .overlay(searchIconFrameReporter.allowsHitTesting(false))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Category Selector

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiscoveryCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        if category.isVideoCategory {
                            // .all tab: cursor feed already handles this — just reset index
                            // Other tabs: use filterBy for their specific queries
                            if category != .all {
                                Task { await viewModel.filterBy(category: category) }
                            }
                            viewModel.swipeIndex = 0
                        } else if category == .communities {
                            Task {
                                if let userID = authService.currentUserID {
                                    _ = try? await communityService.fetchMyCommunities(userID: userID)
                                }
                            }
                        } else if category.isCollectionCategory {
                            Task { await viewModel.loadCollections(for: category) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: category == .communities ? 14 : 11, weight: .semibold))

                            Text(category.displayName)
                                .font(.system(size: 13, weight: selectedCategory == category ? .bold : .medium))

                            if category == .communities && hasUnreadCommunities && selectedCategory != .communities {
                                Circle()
                                    .fill(Color.pink)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundColor(tabForeground(category))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedCategory == category
                                ? tabBackground(category)
                                : Color.white.opacity(0.06)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedCategory == category ? tabStroke(category) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            Group {
                                if category == .communities {
                                    communitiesPillFrameReporter
                                }
                            }
                            .allowsHitTesting(false)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func tabForeground(_ category: DiscoveryCategory) -> Color {
        if selectedCategory == category {
            switch category {
            case .communities: return .pink
            case .pymk:        return .cyan
            case .rollTheDice: return .yellow
            case .heatCheck:   return .orange
            case .podcasts:    return .purple
            case .films:       return .indigo
            default:           return .white
            }
        }
        return .white.opacity(0.5)
    }

    private func tabBackground(_ category: DiscoveryCategory) -> Color {
        switch category {
        case .communities: return Color.pink.opacity(0.15)
        case .pymk:        return Color.cyan.opacity(0.15)
        case .rollTheDice: return Color.yellow.opacity(0.15)
        case .heatCheck:   return Color.orange.opacity(0.15)
        case .podcasts:    return Color.purple.opacity(0.15)
        case .films:       return Color.indigo.opacity(0.15)
        default:           return Color.white.opacity(0.12)
        }
    }

    private func tabStroke(_ category: DiscoveryCategory) -> Color {
        switch category {
        case .communities: return Color.pink.opacity(0.4)
        case .pymk:        return Color.cyan.opacity(0.4)
        case .rollTheDice: return Color.yellow.opacity(0.4)
        case .heatCheck:   return Color.orange.opacity(0.4)
        case .podcasts:    return Color.purple.opacity(0.4)
        case .films:       return Color.indigo.opacity(0.4)
        default:           return Color.white.opacity(0.2)
        }
    }

    // MARK: - Trending Hashtags Section

    private var trendingHashtagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoadingHashtags {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                    Text("Loading trends...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
            } else if !viewModel.trendingHashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.trendingHashtags) { hashtag in
                            DiscoveryHashtagChip(hashtag: hashtag, isSelected: false) {
                                selectedHashtagPresentation = DiscoveryHashtagPresentation(
                                    id: hashtag.id,
                                    hashtag: hashtag
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    private func hashtagFilterBar(_ hashtag: TrendingHashtag) -> some View {
        HStack {
            Button {
                selectedHashtagPresentation = DiscoveryHashtagPresentation(
                    id: hashtag.id,
                    hashtag: hashtag
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .semibold))
                    Text(hashtag.tag)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.pink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.pink.opacity(0.15))
                .clipShape(Capsule())
            }

            Spacer()

            Button {
                viewModel.clearHashtagFilter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if announcementService.isShowingAnnouncement {
            Color.clear
        } else if discoveryMode == .swipe {
            swipeContentView
        } else {
            gridContentView
        }
    }

    @ViewBuilder
    private var swipeContentView: some View {
        ZStack(alignment: .top) {
            DiscoverySwipeCards(
                videos: viewModel.filteredVideos,
                currentIndex: $viewModel.swipeIndex,
                onVideoTap: { video in
                    if let collection = viewModel.collectionCardMap[video.id] {
                        selectedCollection = collection
                        showingCollectionPlayer = true
                    } else {
                        videoPresentation = DiscoveryVideoPresentation(
                            id: video.id,
                            video: video
                        )
                    }
                },
                onNavigateToProfile: { userID in
                    selectedUserForProfile = userID
                    showingProfileView = true
                },
                onNavigateToThread: { _ in },
                isFullscreenActive: videoPresentation != nil || showingSearch || selectedHashtagPresentation != nil,
                collectionCardMap: viewModel.collectionCardMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(swipeCardFrameReporter)
            .onChange(of: viewModel.swipeIndex) { _, newValue in
                // When user reaches last video — shuffle and restart
                if newValue >= viewModel.filteredVideos.count - 1 && !viewModel.filteredVideos.isEmpty {
                    viewModel.reshuffleAndRestart()
                }
            }

            swipeInstructionsIndicator
                .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var gridContentView: some View {
        DiscoveryGridView(
            videos: viewModel.filteredVideos,
            onVideoTap: { video in
                if let collection = viewModel.collectionCardMap[video.id] {
                    selectedCollection = collection
                    showingCollectionPlayer = true
                } else {
                    videoPresentation = DiscoveryVideoPresentation(
                        id: video.id,
                        video: video
                    )
                }
            },
            onLoadMore: { viewModel.reshuffleAndRestart() },
            onRefresh:  { Task { await viewModel.refreshContent() } },
            isLoadingMore: viewModel.isLoading
        )
    }

    // MARK: - Swipe Instructions Indicator

    private var swipeInstructionsIndicator: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Next")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))

            Divider().frame(height: 16).background(Color.white.opacity(0.3))

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))

            Divider().frame(height: 16).background(Color.white.opacity(0.3))

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Fullscreen")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Collection Lane View

    private var collectionLaneView: some View {
        Group {
            if viewModel.isLoadingCollections && viewModel.discoveryCollections.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    Text("Loading \(selectedCategory.displayName.lowercased())...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.discoveryCollections.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: selectedCategory.icon)
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No \(selectedCategory.displayName.lowercased()) yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Be the first to upload one!")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedCategory == .collections {
                collectionsGridView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.discoveryCollections) { collection in
                            Button {
                                selectedCollection = collection
                                showingCollectionPlayer = true
                            } label: {
                                HStack(spacing: 12) {
                                    // Thumbnail
                                    ZStack {
                                        if let coverURL = collection.coverImageURL, let url = URL(string: coverURL) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color.white.opacity(0.08))
                                            }
                                        } else {
                                            Rectangle().fill(Color.white.opacity(0.08))
                                                .overlay(Image(systemName: "rectangle.stack.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.gray.opacity(0.4)))
                                        }
                                    }
                                    .frame(width: 90, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    // Info
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(collection.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text(collection.creatorName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        HStack(spacing: 4) {
                                            Image(systemName: "play.rectangle.fill").font(.system(size: 9))
                                            Text("\(collection.segmentCount) parts").font(.system(size: 11))
                                        }
                                        .foregroundColor(.cyan.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task {
            await viewModel.loadCollections(for: selectedCategory)
        }
    }

    // MARK: - Collections Grid (2-column)

    private var collectionsGridView: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.discoveryCollections) { collection in
                    Button {
                        selectedCollection = collection
                        showingCollectionPlayer = true
                    } label: {
                        collectionGridCard(collection)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Spacer(minLength: 80)
        }
    }

    private func collectionGridCard(_ collection: VideoCollection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let coverURL = collection.coverImageURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(9/16, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Image(systemName: "rectangle.stack.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.gray.opacity(0.4))
                            )
                    }
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(10)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 220)
                        .overlay(
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.gray.opacity(0.4))
                        )
                        .cornerRadius(10)
                }

                HStack(spacing: 3) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 9))
                    Text("\(collection.segmentCount)").font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(6)
            }

            Text(collection.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)

            Text(collection.creatorName)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }

    // MARK: - Loading / Error Views

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
            Text("Discovering amazing content...")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            Text("Finding videos from all time periods")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            Text("Oops!")
                .font(.title).fontWeight(.bold).foregroundColor(.white)
            Text(message)
                .font(.body).foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Try Again") {
                Task { await viewModel.loadInitialContent() }
            }
            .padding(.horizontal, 40).padding(.vertical, 15)
            .background(Color.cyan).foregroundColor(.black)
            .cornerRadius(25).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Onboarding Frame Reporters
    // Extracted into properties so the compiler can type-check them independently.

    private var swipeCardFrameReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: OnboardingSwipeCardFrameKey.self,
                value: geo.frame(in: .global)
            )
        }
    }

    private var communitiesPillFrameReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: OnboardingCommunitiesPillFrameKey.self,
                value: geo.frame(in: .global)
            )
        }
    }

    private var searchIconFrameReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: OnboardingSearchIconFrameKey.self,
                value: geo.frame(in: .global)
            )
        }
    }
}

// MARK: - Discovery Hashtag Chip

struct DiscoveryHashtagChip: View {
    let hashtag: TrendingHashtag
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(hashtag.velocityTier.emoji).font(.system(size: 12))
                Text(hashtag.displayTag)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .black : .white)
                Text("\(hashtag.videoCount)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .black.opacity(0.7) : .gray)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.pink)
                    : AnyShapeStyle(LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.pink : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DiscoveryView()
        .environmentObject(AuthService())
}

// MARK: - Discovery Mode

enum DiscoveryMode: String, CaseIterable {
    case swipe = "swipe"
    case grid  = "grid"

    var displayName: String {
        switch self { case .swipe: return "Swipe"; case .grid: return "Grid" }
    }
    var icon: String {
        switch self { case .swipe: return "square.stack"; case .grid: return "rectangle.grid.2x2" }
    }
}

// MARK: - Discovery Category

enum DiscoveryCategory: String, CaseIterable {
    case communities    = "communities"
    case collections    = "collections"
    case all            = "all"
    case trending       = "trending"
    case pymk           = "pymk"
    case hotHashtags    = "hotHashtags"
    case recent         = "recent"
    case heatCheck      = "heatCheck"
    case following      = "following"
    case undiscovered   = "undiscovered"
    case longestThreads = "longestThreads"
    case spinOffs       = "spinOffs"
    case podcasts       = "podcasts"
    case films          = "films"
    case rollTheDice    = "rollTheDice"

    var displayName: String {
        switch self {
        case .communities:    return "Communities"
        case .collections:    return "Collections"
        case .following:      return "Following"
        case .trending:       return "Trending"
        case .pymk:           return "PYMK"
        case .hotHashtags:    return "Hot Hashtags"
        case .all:            return "All"
        case .recent:         return "New"
        case .heatCheck:      return "Heat Check"
        case .undiscovered:   return "Undiscovered"
        case .longestThreads: return "Threads"
        case .spinOffs:       return "Spin-Offs"
        case .podcasts:       return "Podcasts"
        case .films:          return "Films"
        case .rollTheDice:    return "Roll the Dice"
        }
    }

    var icon: String {
        switch self {
        case .communities:    return "person.3.fill"
        case .collections:    return "rectangle.stack.fill"
        case .following:      return "heart.fill"
        case .trending:       return "flame.fill"
        case .pymk:           return "person.badge.plus"
        case .hotHashtags:    return "number"
        case .all:            return "square.grid.2x2"
        case .recent:         return "sparkles"
        case .heatCheck:      return "thermometer.high"
        case .undiscovered:   return "binoculars.fill"
        case .longestThreads: return "bubble.left.and.bubble.right.fill"
        case .spinOffs:       return "arrow.triangle.branch"
        case .podcasts:       return "mic.fill"
        case .films:          return "film"
        case .rollTheDice:    return "dice.fill"
        }
    }

    var isVideoCategory: Bool {
        switch self {
        case .communities, .collections, .pymk, .podcasts, .films: return false
        default: return true
        }
    }

    var isCollectionCategory: Bool {
        return self == .podcasts || self == .films || self == .collections
    }
}

// MARK: - Presentation Wrappers

struct DiscoveryVideoPresentation: Identifiable, Equatable {
    let id: String
    let video: CoreVideoMetadata
    static func == (lhs: DiscoveryVideoPresentation, rhs: DiscoveryVideoPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

struct DiscoveryHashtagPresentation: Identifiable {
    let id: String
    let hashtag: TrendingHashtag
}
