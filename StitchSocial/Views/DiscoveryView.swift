//
//  DiscoveryView with Progressive Loading
//  StitchSocial
//
//  TikTok-style infinite scroll with intelligent content batching
//

import SwiftUI
import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Discovery Mode & Category (ORIGINAL)

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
    case all = "all"
    case trending = "trending"
    case recent = "recent"
    case popular = "popular"
    case following = "following"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .trending: return "Trending"
        case .recent: return "Recent"
        case .popular: return "Popular"
        case .following: return "Following"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "rectangle.grid.2x2"
        case .trending: return "flame.fill"
        case .recent: return "clock.fill"
        case .popular: return "star.fill"
        case .following: return "person.2.fill"
        }
    }
}

// MARK: - Progressive Loading State

struct LoadingState {
    var isInitialLoading = false
    var isLoadingMore = false
    var hasMoreContent = true
    var loadingBatch = 0
    var totalLoaded = 0
    var lastLoadTime = Date()
}

// MARK: - Discovery ViewModel with Progressive Loading

@MainActor
class DiscoveryViewModel: ObservableObject {
    // Published properties
    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var loadingState = LoadingState()
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var errorMessage: String?
    
    // Progressive loading configuration
    let initialBatchSize = 40       // Increased from 20 to 40 for better grid experience
    let subsequentBatchSize = 20    // Increased from 10 to 20 for smoother loading
    private let triggerLoadThreshold = 10  // Load more when 10 videos remaining (more aggressive)
    private let maxCachedVideos = 300     // Increased cache for much better grid experience
    
    // Services and state
    private let videoService = VideoService()
    private var allAvailableVideos: [CoreVideoMetadata] = []
    private var lastDocument: DocumentSnapshot?
    
    // MARK: - Initial Loading
    
    func loadInitialContent() async {
        guard !loadingState.isInitialLoading else { return }
        
        loadingState.isInitialLoading = true
        defer { loadingState.isInitialLoading = false }
        
        do {
            print("🎯 DISCOVERY: Loading initial batch (\(initialBatchSize) videos)")
            
            // FIXED: Use fast parent-only loading
            let result = try await videoService.getDiscoveryParentThreadsOnly(limit: initialBatchSize)
            let loadedVideos = result.threads.map { $0.parentVideo }
            
            await MainActor.run {
                allAvailableVideos = loadedVideos
                lastDocument = result.lastDocument
                loadingState.hasMoreContent = result.hasMore
                loadingState.totalLoaded = loadedVideos.count
                loadingState.loadingBatch = 1
                
                // Apply category filter and light shuffle
                applyFilterAndShuffle()
                
                errorMessage = nil
                print("✅ DISCOVERY: Initial load complete - \(filteredVideos.count) videos ready")
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load discovery content"
                print("❌ DISCOVERY: Initial load failed: \(error)")
            }
        }
    }
    
    // MARK: - Progressive Loading
    
    func checkAndLoadMore(currentIndex: Int) async {
        // Check if we need to load more content
        let remainingCount = filteredVideos.count - currentIndex
        
        guard remainingCount <= triggerLoadThreshold,
              !loadingState.isLoadingMore,
              loadingState.hasMoreContent else {
            return
        }
        
        await loadMoreContent()
    }
    
    private func loadMoreContent() async {
        guard !loadingState.isLoadingMore else { return }
        
        loadingState.isLoadingMore = true
        defer { loadingState.isLoadingMore = false }
        
        do {
            print("🔥 DISCOVERY: Loading more content (batch \(loadingState.loadingBatch + 1))")
            
            // FIXED: Use fast parent-only loading
            let result = try await videoService.getDiscoveryParentThreadsOnly(
                limit: subsequentBatchSize,
                lastDocument: lastDocument
            )
            let newVideos = result.threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Add to available videos
                allAvailableVideos.append(contentsOf: newVideos)
                lastDocument = result.lastDocument
                loadingState.hasMoreContent = result.hasMore
                loadingState.totalLoaded += newVideos.count
                loadingState.loadingBatch += 1
                loadingState.lastLoadTime = Date()
                
                // Apply filter and add to current feed
                let newFilteredVideos = applyCurrentFilter(to: newVideos)
                let lightShuffledNew = lightShuffle(videos: newFilteredVideos)
                filteredVideos.append(contentsOf: lightShuffledNew)
                
                // Memory management - remove old videos if cache gets too large
                manageMemory()
                
                print("✅ DISCOVERY: Loaded \(newVideos.count) more videos (total: \(filteredVideos.count))")
            }
        } catch {
            print("❌ DISCOVERY: Failed to load more content: \(error)")
        }
    }
    
    // MARK: - Refresh Content
    
    func refreshContent() async {
        // Reset state
        allAvailableVideos = []
        lastDocument = nil
        loadingState = LoadingState()
        
        // Load fresh content
        await loadInitialContent()
    }
    
    // MARK: - Randomize Content
    
    func randomizeContent() {
        // Shuffle all available videos
        allAvailableVideos = allAvailableVideos.shuffled()
        
        // Re-apply current filter with shuffle
        applyFilterAndShuffle()
        
        print("🎲 DISCOVERY: Content randomized - \(filteredVideos.count) videos reshuffled")
    }
    
    private func manageMemory() {
        if filteredVideos.count > maxCachedVideos {
            let videosToRemove = filteredVideos.count - maxCachedVideos
            filteredVideos.removeFirst(videosToRemove)
            print("🧹 DISCOVERY: Removed \(videosToRemove) old videos for memory management")
        }
    }
    
    // MARK: - Filtering and Shuffling
    
    func filterBy(category: DiscoveryCategory) {
        currentCategory = category
        applyFilterAndShuffle()
    }
    
    private func applyFilterAndShuffle() {
        let filtered = applyCurrentFilter(to: allAvailableVideos)
        filteredVideos = lightShuffle(videos: filtered)
        print("🔄 DISCOVERY: Applied \(currentCategory.displayName) filter - \(filteredVideos.count) videos")
    }
    
    private func applyCurrentFilter(to videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        switch currentCategory {
        case .all:
            return videos
        case .trending:
            return videos.filter { $0.temperature == "hot" || $0.temperature == "blazing" }
        case .recent:
            return videos.sorted { $0.createdAt > $1.createdAt }
        case .popular:
            return videos.sorted { $0.hypeCount > $1.hypeCount }
        case .following:
            return videos // TODO: Filter by followed users
        }
    }
    
    // MARK: - Light Shuffle (Fast Performance)
    
    private func lightShuffle(videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        var shuffled = videos.shuffled()
        
        // Simple rule: prevent same creator back-to-back
        var result: [CoreVideoMetadata] = []
        var remaining = shuffled
        
        while !remaining.isEmpty {
            let lastCreatorID = result.last?.creatorID
            
            if let differentIndex = remaining.firstIndex(where: { $0.creatorID != lastCreatorID }) {
                result.append(remaining.remove(at: differentIndex))
            } else {
                result.append(remaining.removeFirst())
            }
        }
        
        return result
    }
    
    // MARK: - Engagement Updates
    
    func updateVideoEngagement(videoID: String, type: InteractionType) {
        // Update in both arrays efficiently
        updateVideoInArray(&allAvailableVideos, videoID: videoID, type: type)
        updateVideoInArray(&filteredVideos, videoID: videoID, type: type)
        print("📊 DISCOVERY: Updated \(type.rawValue) for video \(videoID)")
    }
    
    private func updateVideoInArray(_ array: inout [CoreVideoMetadata], videoID: String, type: InteractionType) {
        guard let index = array.firstIndex(where: { $0.id == videoID }) else { return }
        
        var updatedVideo = array[index]
        switch type {
        case .hype:
            updatedVideo = CoreVideoMetadata(
                id: updatedVideo.id,
                title: updatedVideo.title,
                videoURL: updatedVideo.videoURL,
                thumbnailURL: updatedVideo.thumbnailURL,
                creatorID: updatedVideo.creatorID,
                creatorName: updatedVideo.creatorName,
                createdAt: updatedVideo.createdAt,
                threadID: updatedVideo.threadID,
                replyToVideoID: updatedVideo.replyToVideoID,
                conversationDepth: updatedVideo.conversationDepth,
                viewCount: updatedVideo.viewCount,
                hypeCount: updatedVideo.hypeCount + 1,
                coolCount: updatedVideo.coolCount,
                replyCount: updatedVideo.replyCount,
                shareCount: updatedVideo.shareCount,
                temperature: updatedVideo.temperature,
                qualityScore: updatedVideo.qualityScore,
                engagementRatio: updatedVideo.engagementRatio,
                velocityScore: updatedVideo.velocityScore,
                trendingScore: updatedVideo.trendingScore,
                duration: updatedVideo.duration,
                aspectRatio: updatedVideo.aspectRatio,
                fileSize: updatedVideo.fileSize,
                discoverabilityScore: updatedVideo.discoverabilityScore,
                isPromoted: updatedVideo.isPromoted,
                lastEngagementAt: updatedVideo.lastEngagementAt
            )
        case .cool:
            updatedVideo = CoreVideoMetadata(
                id: updatedVideo.id,
                title: updatedVideo.title,
                videoURL: updatedVideo.videoURL,
                thumbnailURL: updatedVideo.thumbnailURL,
                creatorID: updatedVideo.creatorID,
                creatorName: updatedVideo.creatorName,
                createdAt: updatedVideo.createdAt,
                threadID: updatedVideo.threadID,
                replyToVideoID: updatedVideo.replyToVideoID,
                conversationDepth: updatedVideo.conversationDepth,
                viewCount: updatedVideo.viewCount,
                hypeCount: updatedVideo.hypeCount,
                coolCount: updatedVideo.coolCount + 1,
                replyCount: updatedVideo.replyCount,
                shareCount: updatedVideo.shareCount,
                temperature: updatedVideo.temperature,
                qualityScore: updatedVideo.qualityScore,
                engagementRatio: updatedVideo.engagementRatio,
                velocityScore: updatedVideo.velocityScore,
                trendingScore: updatedVideo.trendingScore,
                duration: updatedVideo.duration,
                aspectRatio: updatedVideo.aspectRatio,
                fileSize: updatedVideo.fileSize,
                discoverabilityScore: updatedVideo.discoverabilityScore,
                isPromoted: updatedVideo.isPromoted,
                lastEngagementAt: updatedVideo.lastEngagementAt
            )
        default:
            break
        }
        array[index] = updatedVideo
    }
}

// MARK: - Enhanced DiscoveryView with Progressive Loading

struct DiscoveryView: View {
    // MARK: - State
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject private var authService: AuthService
    @StateObject private var engagementManager = EngagementManager(
        videoService: VideoService(),
        userService: UserService()
    )
    
    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var discoveryMode: DiscoveryMode = .swipe
    @State private var currentSwipeIndex: Int = 0
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var isFullscreenMode = false
    @State private var showingSearch = false
    
    var body: some View {
        ZStack {
            if !isFullscreenMode {
                // Normal Discovery Interface
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
                        // Header with Loading Indicator
                        headerView
                        
                        // Category Selector
                        categorySelector
                        
                        // Content
                        if viewModel.loadingState.isInitialLoading {
                            initialLoadingView
                        } else if let errorMessage = viewModel.errorMessage {
                            errorView(errorMessage)
                        } else {
                            contentView
                        }
                    }
                }
            } else {
                // Fullscreen Mode
                if let video = selectedVideo {
                    FullscreenVideoView(video: video) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isFullscreenMode = false
                        }
                        selectedVideo = nil
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .navigationBarHidden(isFullscreenMode)
        .statusBarHidden(isFullscreenMode)
        .task {
            // Only load if we don't have content already (prevents reloading on tab switch)
            if viewModel.filteredVideos.isEmpty {
                await viewModel.loadInitialContent()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshDiscovery"))) { _ in
            Task {
                await viewModel.loadInitialContent()
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView()
        }
    }
    
    // MARK: - Header View with Loading Indicators
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discovery")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text("\(viewModel.filteredVideos.count) videos")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    if viewModel.loadingState.isLoadingMore {
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
                // Mode Toggle
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        discoveryMode = discoveryMode == DiscoveryMode.grid ? DiscoveryMode.swipe : DiscoveryMode.grid
                    }
                } label: {
                    Image(systemName: discoveryMode.icon)
                        .font(.title2)
                        .foregroundColor(discoveryMode == DiscoveryMode.swipe ? .cyan : .white.opacity(0.7))
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
    
    // MARK: - Category Selector
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(DiscoveryCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        viewModel.filterBy(category: category)
                        currentSwipeIndex = 0 // Reset to beginning when changing category
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.subheadline)
                                
                                Text(category.displayName)
                                    .font(.subheadline)
                                    .fontWeight(selectedCategory == category ? .semibold : .medium)
                            }
                            .foregroundColor(selectedCategory == category ? .cyan : .white.opacity(0.7))
                            
                            Rectangle()
                                .fill(selectedCategory == category ? .cyan : .clear)
                                .frame(height: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Content View with Progressive Loading
    
    @ViewBuilder
    private var contentView: some View {
        switch discoveryMode {
        case DiscoveryMode.swipe:
            DiscoverySwipeCards(
                videos: viewModel.filteredVideos,
                currentIndex: $currentSwipeIndex,
                onVideoTap: { video in
                    selectedVideo = video
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isFullscreenMode = true
                    }
                },
                onEngagement: { type, video in
                    handleEngagement(type, video: video)
                },
                onNavigateToProfile: { userID in
                    // Handle profile navigation
                },
                onNavigateToThread: { threadID in
                    // Handle thread navigation
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .onChange(of: currentSwipeIndex) { oldValue, newValue in
                print("🎯 DISCOVERY: Swipe \(oldValue) → \(newValue)")
                
                // Trigger progressive loading when user gets close to end
                Task {
                    await viewModel.checkAndLoadMore(currentIndex: newValue)
                }
            }
            
        case DiscoveryMode.grid:
            DiscoveryGridView(
                videos: viewModel.filteredVideos,
                onVideoTap: { video in
                    selectedVideo = video
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isFullscreenMode = true
                    }
                },
                onLoadMore: {
                    Task {
                        await viewModel.checkAndLoadMore(currentIndex: viewModel.filteredVideos.count - 5)
                    }
                },
                onRefresh: {
                    Task {
                        await viewModel.refreshContent()
                    }
                },
                isLoadingMore: viewModel.loadingState.isLoadingMore
            )
        }
    }
    
    // MARK: - Loading Views
    
    private var initialLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
            
            Text("Discovering amazing content...")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Text("Loading first \(viewModel.initialBatchSize) videos")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
        .background(Color.clear)
    }
    
    // MARK: - Helper Methods
    
    private func handleEngagement(_ type: InteractionType, video: CoreVideoMetadata) {
        print("🎯 DISCOVERY: Handling \(type.rawValue) engagement for video: \(video.title)")
        viewModel.updateVideoEngagement(videoID: video.id, type: type)
    }
}

#Preview {
    DiscoveryView()
        .environmentObject(AuthService())
}
