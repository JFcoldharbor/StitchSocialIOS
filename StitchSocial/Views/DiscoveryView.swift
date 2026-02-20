//
//  DiscoveryView.swift (UPDATED)
//  StitchSocial
//
//  Enhanced with deep time-based randomization
//  Shows varied content from all time periods, not just newest
//  FIXED: Fullscreen handling now uses .fullScreenCover(item:) to prevent video stopping
//  FIXED: Observes AnnouncementService to stop video playback when announcement shows
//  FIXED: loadMoreContent APPENDS to end without reshuffling seen content
//

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - Discovery ViewModel with Deep Randomization

@MainActor
class DiscoveryViewModel: ObservableObject {
    // Published properties
    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var errorMessage: String?
    
    // Collection state for podcast/film lanes
    @Published var discoveryCollections: [VideoCollection] = []
    @Published var isLoadingCollections = false
    
    /// Collections interleaved into the swipe feed — maps video.id to VideoCollection
    var collectionCardMap: [String: VideoCollection] = [:]
    
    // MARK: - Hashtag State
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var isLoadingHashtags = false
    @Published var selectedHashtag: TrendingHashtag?
    @Published var hashtagVideos: [CoreVideoMetadata] = []
    
    // Services
    private let discoveryService = DiscoveryService()
    private let hashtagService = HashtagService()
    
    // MARK: - Load Initial Content with Deep Randomization
    
    func loadInitialContent() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â DISCOVERY: Loading deep randomized content")
            
            // Load videos and collections in parallel
            async let threadsTask = discoveryService.getDeepRandomizedDiscovery(limit: 40)
            async let collectionsTask = discoveryService.getAllCollectionsDiscovery(limit: 6)
            
            let threads = try await threadsTask
            let swipeCollections = (try? await collectionsTask) ?? []
            let loadedVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                
                if validVideos.count < loadedVideos.count {
                    print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â DISCOVERY: Filtered out \(loadedVideos.count - validVideos.count) videos with empty IDs")
                }
                
                videos = validVideos
                applyFilterAndShuffle()
                interleaveCollections(swipeCollections)
                errorMessage = nil
                
                print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ DISCOVERY: Loaded \(filteredVideos.count) randomized videos")
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load discovery content"
                print("ÃƒÂ¢Ã‚ÂÃ…â€™ DISCOVERY: Load failed: \(error)")
            }
        }
    }
    
    // MARK: - Load Trending Hashtags
    
    func loadTrendingHashtags() async {
        isLoadingHashtags = true
        await hashtagService.loadTrendingHashtags(limit: 10)
        trendingHashtags = hashtagService.trendingHashtags
        isLoadingHashtags = false
    }
    
    func selectHashtag(_ hashtag: TrendingHashtag) async {
        selectedHashtag = hashtag
        isLoading = true
        
        do {
            let result = try await hashtagService.getVideosForHashtag(hashtag.tag, limit: 40)
            hashtagVideos = result.videos
            filteredVideos = result.videos
        } catch {
            print("❌ DISCOVERY: Failed to load hashtag videos: \(error)")
        }
        
        isLoading = false
    }
    
    func clearHashtagFilter() {
        selectedHashtag = nil
        hashtagVideos = []
        applyFilterAndShuffle()
    }
    
    // MARK: - Load More (APPEND to end, NO reshuffle)
    
    func loadMoreContent() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¥ DISCOVERY: Loading more content (appending to end)")
            
            // Load another batch
            let threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 30)
            let newVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = newVideos.filter { !$0.id.isEmpty }
                
                // FIXED: Just append to END - don't reshuffle!
                videos.append(contentsOf: validVideos)
                filteredVideos.append(contentsOf: validVideos)
                
                print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ DISCOVERY: Appended \(validVideos.count) videos to end, total: \(filteredVideos.count)")
            }
        } catch {
            print("ÃƒÂ¢Ã‚ÂÃ…â€™ DISCOVERY: Failed to load more: \(error)")
        }
    }
    
    // MARK: - Refresh Content (full reset + reshuffle)
    
    func refreshContent() async {
        videos = []
        filteredVideos = []
        await loadInitialContent()
    }
    
    // MARK: - Randomize Content (explicit reshuffle)
    
    func randomizeContent() {
        // Ultra-shuffle existing videos
        videos = videos.shuffled()
        applyFilterAndShuffle()
        
        print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â² DISCOVERY: Content randomized - \(filteredVideos.count) videos reshuffled")
    }
    
    // MARK: - Category Filtering
    
    func filterBy(category: DiscoveryCategory) async {
        currentCategory = category
        
        // Non-video categories handled by the view
        guard category.isVideoCategory else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let threads: [ThreadData]
            
            switch category {
            case .all:
                threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 40)
                
            case .trending:
                threads = try await discoveryService.getTrendingDiscovery(limit: 40)
                
            case .recent:
                threads = try await discoveryService.getRecentDiscovery(limit: 40)
                
            case .following:
                threads = try await discoveryService.getFollowingFeed(limit: 40)
                
            case .hotHashtags:
                threads = try await discoveryService.getHotHashtagDiscovery(limit: 40)
                
            case .heatCheck:
                threads = try await discoveryService.getHeatCheckDiscovery(limit: 40)
                
            case .undiscovered:
                threads = try await discoveryService.getUndiscoveredDiscovery(limit: 40)
                
            case .longestThreads:
                threads = try await discoveryService.getLongestThreadsDiscovery(limit: 40)
                
            case .spinOffs:
                threads = try await discoveryService.getSpinOffDiscovery(limit: 40)
                
            case .rollTheDice:
                let allThreads = try await discoveryService.getDeepRandomizedDiscovery(limit: 60)
                threads = allThreads.shuffled()
                
            case .communities, .collections, .pymk, .podcasts, .films:
                return
            }
            
            let loadedVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                videos = validVideos
                applyFilterAndShuffle()
                
                print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  DISCOVERY: Applied \(category.displayName) filter - \(filteredVideos.count) videos")
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load \(category.displayName) content"
                print("ÃƒÂ¢Ã‚ÂÃ…â€™ DISCOVERY: Category load failed: \(error)")
            }
        }
    }
    
    // MARK: - Collection Loading (Podcasts, Films)
    
    func loadCollections(for category: DiscoveryCategory) async {
        isLoadingCollections = true
        defer { isLoadingCollections = false }
        
        do {
            switch category {
            case .collections:
                discoveryCollections = try await discoveryService.getAllCollectionsDiscovery(limit: 30)
            case .podcasts:
                discoveryCollections = try await discoveryService.getPodcastDiscovery(limit: 20)
            case .films:
                discoveryCollections = try await discoveryService.getFilmsDiscovery(limit: 20)
            default:
                break
            }
        } catch {
            discoveryCollections = []
        }
    }
    
    // MARK: - Filtering and Shuffling
    
    private func applyFilterAndShuffle() {
        let blockedIDs = DiscoveryEngagementTracker.shared.blockedCreatorIDs()
        let allowedVideos = blockedIDs.isEmpty ? videos : videos.filter { !blockedIDs.contains($0.creatorID) }
        filteredVideos = diversifyShuffle(videos: allowedVideos)
    }
    
    /// Insert collection placeholder cards into filteredVideos every ~7 items.
    /// Creates synthetic CoreVideoMetadata entries mapped via collectionCardMap.
    func interleaveCollections(_ collections: [VideoCollection]) {
        guard !collections.isEmpty else { return }
        collectionCardMap.removeAll()
        
        var insertOffset = 0
        for (i, collection) in collections.enumerated() {
            let placeholderID = "collection_card_\(collection.id)"
            
            // Build a synthetic video the swipe card can render
            let placeholder = CoreVideoMetadata(
                id: placeholderID,
                title: collection.title,
                description: "\(collection.segmentCount) parts",
                videoURL: "",
                thumbnailURL: collection.coverImageURL ?? "",
                creatorID: collection.creatorID,
                creatorName: collection.creatorName,
                createdAt: collection.publishedAt ?? collection.createdAt,
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: collection.totalViews,
                hypeCount: collection.totalHypes,
                coolCount: collection.totalCools,
                replyCount: collection.totalReplies,
                shareCount: collection.totalShares,
                temperature: "neutral",
                qualityScore: 50,
                engagementRatio: 0,
                velocityScore: 0,
                trendingScore: 0,
                duration: collection.totalDuration,
                aspectRatio: 9.0/16.0,
                fileSize: 0,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil,
                collectionID: collection.id,
                isCollectionSegment: true
            )
            
            collectionCardMap[placeholderID] = collection
            
            // Insert every ~7 cards
            let insertIndex = min((i + 1) * 7 + insertOffset, filteredVideos.count)
            filteredVideos.insert(placeholder, at: insertIndex)
            insertOffset += 1
        }
        
        print("📚 DISCOVERY: Interleaved \(collections.count) collection cards")
    }
    
    /// Shuffle with maximum creator variety
    private func diversifyShuffle(videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        guard videos.count > 1 else { return videos }
        
        // Group by creator
        var creatorBuckets: [String: [CoreVideoMetadata]] = [:]
        for video in videos {
            creatorBuckets[video.creatorID, default: []].append(video)
        }
        
        // Shuffle each creator's videos
        var shuffledBuckets = creatorBuckets.mapValues { $0.shuffled() }
        
        // Interleave to maximize variety
        var result: [CoreVideoMetadata] = []
        var recentCreators: [String] = []
        let maxRecentTracking = 5
        
        while !shuffledBuckets.isEmpty {
            let availableCreators = shuffledBuckets.keys.filter { !recentCreators.contains($0) }
            
            let chosenCreatorID: String
            if !availableCreators.isEmpty {
                chosenCreatorID = availableCreators.randomElement()!
            } else {
                chosenCreatorID = shuffledBuckets.keys.randomElement()!
                recentCreators.removeAll()
            }
            
            if var creatorVideos = shuffledBuckets[chosenCreatorID], !creatorVideos.isEmpty {
                let video = creatorVideos.removeFirst()
                result.append(video)
                
                recentCreators.append(chosenCreatorID)
                if recentCreators.count > maxRecentTracking {
                    recentCreators.removeFirst()
                }
                
                if creatorVideos.isEmpty {
                    shuffledBuckets.removeValue(forKey: chosenCreatorID)
                } else {
                    shuffledBuckets[chosenCreatorID] = creatorVideos
                }
            }
        }
        
        return result
    }
}

// MARK: - Discovery Mode & Category

enum DiscoveryMode: String, CaseIterable {
    case swipe = "swipe"
    case grid = "grid"
    
    var displayName: String {
        switch self {
        case .swipe: return "Swipe"
        case .grid: return "Grid"
        }
    }
    
    var icon: String {
        switch self {
        case .swipe: return "square.stack"
        case .grid: return "rectangle.grid.2x2"
        }
    }
}

enum DiscoveryCategory: String, CaseIterable {
    case communities = "communities"
    case collections = "collections"
    case all = "all"
    case trending = "trending"
    case pymk = "pymk"
    case hotHashtags = "hotHashtags"
    case recent = "recent"
    case heatCheck = "heatCheck"
    case following = "following"
    case undiscovered = "undiscovered"
    case longestThreads = "longestThreads"
    case spinOffs = "spinOffs"
    case podcasts = "podcasts"
    case films = "films"
    case rollTheDice = "rollTheDice"
    
    var displayName: String {
        switch self {
        case .communities: return "Communities"
        case .collections: return "Collections"
        case .following: return "Following"
        case .trending: return "Trending"
        case .pymk: return "PYMK"
        case .hotHashtags: return "Hot Hashtags"
        case .all: return "All"
        case .recent: return "New"
        case .heatCheck: return "Heat Check"
        case .undiscovered: return "Undiscovered"
        case .longestThreads: return "Threads"
        case .spinOffs: return "Spin-Offs"
        case .podcasts: return "Podcasts"
        case .films: return "Films"
        case .rollTheDice: return "Roll the Dice"
        }
    }
    
    var icon: String {
        switch self {
        case .communities: return "person.3.fill"
        case .collections: return "rectangle.stack.fill"
        case .following: return "heart.fill"
        case .trending: return "flame.fill"
        case .pymk: return "person.badge.plus"
        case .hotHashtags: return "number"
        case .all: return "square.grid.2x2"
        case .recent: return "sparkles"
        case .heatCheck: return "thermometer.high"
        case .undiscovered: return "binoculars.fill"
        case .longestThreads: return "bubble.left.and.bubble.right.fill"
        case .spinOffs: return "arrow.triangle.branch"
        case .podcasts: return "mic.fill"
        case .films: return "film"
        case .rollTheDice: return "dice.fill"
        }
    }
    
    /// Whether this category shows single video content (vs special views)
    var isVideoCategory: Bool {
        switch self {
        case .communities, .collections, .pymk, .podcasts, .films: return false
        default: return true
        }
    }
    
    /// Whether this category shows collection content
    var isCollectionCategory: Bool {
        return self == .podcasts || self == .films || self == .collections
    }
}

// MARK: - Video Presentation Wrapper (for item-based fullScreenCover)

struct DiscoveryVideoPresentation: Identifiable, Equatable {
    let id: String
    let video: CoreVideoMetadata
    
    static func == (lhs: DiscoveryVideoPresentation, rhs: DiscoveryVideoPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashtag Presentation Wrapper

struct DiscoveryHashtagPresentation: Identifiable {
    let id: String
    let hashtag: TrendingHashtag
}

// MARK: - Enhanced DiscoveryView

struct DiscoveryView: View {
    // MARK: - State
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - Services for Profile Navigation
    
    private let userService = UserService()
    private let videoService = VideoService()
    
    // NEW: Observe announcement service to pause videos when announcement shows
    @ObservedObject private var announcementService = AnnouncementService.shared
    
    // MARK: - Community Services
    @ObservedObject private var communityService = CommunityService.shared
    
    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var discoveryMode: DiscoveryMode = .swipe
    @State private var currentSwipeIndex: Int = 0
    @State private var showingSearch = false
    
    // MARK: - Community State
    @State private var showingCommunityDetail = false
    @State private var selectedCommunityItem: CommunityListItem?
    @State private var hasUnreadCommunities = false
    
    // MARK: - Profile Navigation State
    
    @State private var selectedUserForProfile: String?
    @State private var showingProfileView = false
    
    // FIXED: Use item-based presentation instead of boolean
    @State private var videoPresentation: DiscoveryVideoPresentation?
    @EnvironmentObject var muteManager: MuteContextManager
    
    // Hashtag navigation
    @State private var selectedHashtagPresentation: DiscoveryHashtagPresentation?
    
    // MARK: - PYMK State
    @State private var showingPYMK = false
    
    // Collection player state
    @State private var showingCollectionPlayer = false
    @State private var selectedCollection: VideoCollection?
    
    var body: some View {
        ZStack {
            // Background Gradient
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
            
            VStack(spacing: 0) {
                // Compact toolbar — shuffle, view mode, search
                discoveryToolbar
                
                // Category Selector (tabs ARE the header)
                categorySelector
                
                // Trending Hashtags (show when Hot Hashtags or Trending selected)
                if selectedCategory == .trending || selectedCategory == .hotHashtags {
                    trendingHashtagsSection
                }
                
                // Active hashtag filter indicator
                if selectedCategory.isVideoCategory, let hashtag = viewModel.selectedHashtag {
                    hashtagFilterBar(hashtag)
                }
                
                // Content
                if selectedCategory == .communities {
                    // MARK: - Community Content
                    if let userID = authService.currentUserID {
                        CommunityListView(userID: userID)
                    }
                } else if selectedCategory == .pymk {
                    // MARK: - People You May Know
                    if let userID = authService.currentUserID {
                        PeopleYouMayKnowView(userID: userID)
                    }
                } else if selectedCategory.isCollectionCategory {
                    // MARK: - Collection Lanes (Podcasts, Films)
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
        .task {
            await DiscoveryEngagementTracker.shared.loadPreferences()
            
            if viewModel.filteredVideos.isEmpty {
                await viewModel.loadInitialContent()
            }
            await viewModel.loadTrendingHashtags()
            
            // Check for unread communities (lightweight — uses cached list)
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
        // FIXED: Use item-based fullScreenCover to prevent video stopping
        // Use .fullscreen context to get FULL overlay (not minimal .discovery overlay)
        .fullScreenCover(item: $videoPresentation) { presentation in
            FullscreenVideoView(
                video: presentation.video,
                overlayContext: .fullscreen,
                onDismiss: {
                    print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â± DISCOVERY: Dismissing fullscreen")
                    videoPresentation = nil
                }
            )
        }
        // NEW: React to announcement state changes
        .onChange(of: announcementService.isShowingAnnouncement) { _, isShowing in
            if isShowing {
                print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¢ DISCOVERY: Announcement showing - pausing videos")
            } else {
                print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¢ DISCOVERY: Announcement dismissed - can resume videos")
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
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discovery")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text(selectedCategory == .communities
                         ? "\(communityService.myCommunities.count) channels"
                         : "\(viewModel.filteredVideos.count) videos")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    if viewModel.isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            Text("Loading...")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // Randomize button (video categories only)
                if selectedCategory.isVideoCategory {
                    Button {
                        viewModel.randomizeContent()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    
                    // Mode Toggle
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            discoveryMode = discoveryMode == .grid ? .swipe : .grid
                        }
                    } label: {
                        Image(systemName: discoveryMode.icon)
                            .font(.title2)
                            .foregroundColor(discoveryMode == .swipe ? .cyan : .white.opacity(0.7))
                    }
                }
                
                Button {
                    showingSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    // MARK: - Discovery Toolbar
    
    private var discoveryToolbar: some View {
        HStack {
            // Loading indicator
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
                Text(selectedCategory == .communities
                     ? "\(communityService.myCommunities.count) channels"
                     : "\(viewModel.filteredVideos.count) videos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            HStack(spacing: 18) {
                // Shuffle (video categories only)
                if selectedCategory.isVideoCategory {
                    Button {
                        viewModel.randomizeContent()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                    
                    // Grid / Swipe toggle
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
                
                // Search
                Button {
                    showingSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
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
                            Task {
                                await viewModel.filterBy(category: category)
                            }
                            currentSwipeIndex = 0
                        } else if category == .communities {
                            Task {
                                if let userID = authService.currentUserID {
                                    _ = try? await communityService.fetchMyCommunities(userID: userID)
                                }
                            }
                        } else if category.isCollectionCategory {
                            Task {
                                await viewModel.loadCollections(for: category)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: category == .communities ? 14 : 11, weight: .semibold))
                            
                            Text(category.displayName)
                                .font(.system(size: 13, weight: selectedCategory == category ? .bold : .medium))
                            
                            // Notification dot for communities
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
                                    selectedCategory == category
                                        ? tabStroke(category)
                                        : Color.clear,
                                    lineWidth: 1
                                )
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
            case .pymk: return .cyan
            case .rollTheDice: return .yellow
            case .heatCheck: return .orange
            case .podcasts: return .purple
            case .films: return .indigo
            default: return .white
            }
        }
        return .white.opacity(0.5)
    }
    
    private func tabBackground(_ category: DiscoveryCategory) -> Color {
        switch category {
        case .communities: return Color.pink.opacity(0.15)
        case .pymk: return Color.cyan.opacity(0.15)
        case .rollTheDice: return Color.yellow.opacity(0.15)
        case .heatCheck: return Color.orange.opacity(0.15)
        case .podcasts: return Color.purple.opacity(0.15)
        case .films: return Color.indigo.opacity(0.15)
        default: return Color.white.opacity(0.12)
        }
    }
    
    private func tabStroke(_ category: DiscoveryCategory) -> Color {
        switch category {
        case .communities: return Color.pink.opacity(0.4)
        case .pymk: return Color.cyan.opacity(0.4)
        case .rollTheDice: return Color.yellow.opacity(0.4)
        case .heatCheck: return Color.orange.opacity(0.4)
        case .podcasts: return Color.purple.opacity(0.4)
        case .films: return Color.indigo.opacity(0.4)
        default: return Color.white.opacity(0.2)
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
                            DiscoveryHashtagChip(
                                hashtag: hashtag,
                                isSelected: false
                            ) {
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
                HStack {
                    Text(hashtag.velocityTier.emoji)
                    Text("Viewing \(hashtag.displayTag)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("• \(viewModel.hashtagVideos.count) videos")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Button {
                viewModel.clearHashtagFilter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.pink.opacity(0.15))
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        // NEW: Don't render video content at all when announcement is showing
        // This ensures no background video playback
        if announcementService.isShowingAnnouncement {
            // Show placeholder while announcement is displayed
            Color.clear
        } else {
            switch discoveryMode {
            case .swipe:
                ZStack(alignment: .top) {
                    DiscoverySwipeCards(
                        videos: viewModel.filteredVideos,
                        currentIndex: $currentSwipeIndex,
                        onVideoTap: { video in
                            // Check if this is a collection card
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
                        isFullscreenActive: videoPresentation != nil || showingSearch || selectedHashtagPresentation != nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: currentSwipeIndex) { _, newValue in
                        // Load more when getting close to end
                        if newValue >= viewModel.filteredVideos.count - 10 {
                            Task {
                                await viewModel.loadMoreContent()
                            }
                        }
                    }
                    
                    // Swipe Instructions
                    swipeInstructionsIndicator
                        .padding(.top, 20)
                }
                
            case .grid:
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
                    onLoadMore: {
                        Task {
                            await viewModel.loadMoreContent()
                        }
                    },
                    onRefresh: {
                        Task {
                            await viewModel.refreshContent()
                        }
                    },
                    isLoadingMore: viewModel.isLoading
                )
            }
        }
    }
    
    // MARK: - Swipe Instructions
    
    private var swipeInstructionsIndicator: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Next")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.8))
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))
            
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
    
    // MARK: - Collection Lane View (Podcasts, Films)
    
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
                // 2-column grid for Collections tab
                collectionsGridView
            } else {
                // List style for Podcasts / Films
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.discoveryCollections) { collection in
                            CollectionRowView(
                                collection: collection,
                                style: .card,
                                onTap: {
                                    selectedCollection = collection
                                    showingCollectionPlayer = true
                                },
                                onCreatorTap: { }
                            )
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
            // Cover image
            ZStack(alignment: .bottomTrailing) {
                if let coverURL = collection.coverImageURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(9/16, contentMode: .fill)
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
                
                // Segment count badge
                HStack(spacing: 3) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 9))
                    Text("\(collection.segmentCount)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(6)
            }
            
            // Title
            Text(collection.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            
            // Creator
            Text(collection.creatorName)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }
    
    // MARK: - Loading View

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
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            
            Text("Oops!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Try Again") {
                Task {
                    await viewModel.loadInitialContent()
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 15)
            .background(Color.cyan)
            .foregroundColor(.black)
            .cornerRadius(25)
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(hashtag.velocityTier.emoji)
                    .font(.system(size: 12))
                
                Text(hashtag.displayTag)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .black : .white)
                
                Text("\(hashtag.videoCount)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .black.opacity(0.7) : .gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.pink)
                    : AnyShapeStyle(LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
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
