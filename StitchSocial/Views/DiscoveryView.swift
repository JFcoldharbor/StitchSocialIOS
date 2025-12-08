//
//  DiscoveryView with Progressive Loading
//  StitchSocial
//
//  TikTok-style infinite scroll with intelligent content batching
//  FIXED: Removed engagement from swipe cards - browse only
//  ADDED: Video preloading for instant fullscreen playback
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
    
    // MARK: - Initial Loading - ✅ MIXED RECENT + OLD CONTENT
    
    func loadInitialContent() async {
        guard !loadingState.isInitialLoading else { return }
        
        loadingState.isInitialLoading = true
        defer { loadingState.isInitialLoading = false }
        
        do {
            print("🎯 DISCOVERY: Loading mixed content (recent 24hrs + random old)")
            
            // Load MORE videos than needed to ensure variety
            let fetchLimit = initialBatchSize * 3 // Get 120 videos
            let result = try await videoService.getDiscoveryParentThreadsOnly(limit: fetchLimit)
            let loadedVideos = result.threads.map { $0.parentVideo }
            
            await MainActor.run {
                // ✅ SPLIT: 30% recent (last 24hrs), 70% random older
                let now = Date()
                let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
                
                // ✅ CRITICAL: Filter out videos with empty IDs before processing
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                
                if validVideos.count < loadedVideos.count {
                    print("⚠️ DISCOVERY: Filtered out \(loadedVideos.count - validVideos.count) videos with empty IDs")
                }
                
                // Separate recent vs old
                let recentVideos = validVideos.filter { $0.createdAt >= twentyFourHoursAgo }
                let olderVideos = validVideos.filter { $0.createdAt < twentyFourHoursAgo }
                
                print("📊 DISCOVERY: Found \(recentVideos.count) recent, \(olderVideos.count) older")
                
                // Calculate mix ratios
                let recentCount = min(Int(Double(initialBatchSize) * 0.3), recentVideos.count)
                let olderCount = initialBatchSize - recentCount
                
                // Take samples and shuffle
                let selectedRecent = Array(recentVideos.shuffled().prefix(recentCount))
                let selectedOlder = Array(olderVideos.shuffled().prefix(olderCount))
                
                // Combine and shuffle again for maximum randomness
                allAvailableVideos = (selectedRecent + selectedOlder).shuffled()
                
                lastDocument = result.lastDocument
                loadingState.hasMoreContent = result.hasMore
                loadingState.totalLoaded = allAvailableVideos.count
                loadingState.loadingBatch = 1
                
                // Apply category filter and shuffle
                applyFilterAndShuffle()
                
                errorMessage = nil
                print("✅ DISCOVERY: Loaded \(filteredVideos.count) videos (recent + resurfaced old)")
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
            
            // Load extra to ensure mix
            let fetchLimit = subsequentBatchSize * 3 // Get 60 videos
            let result = try await videoService.getDiscoveryParentThreadsOnly(
                limit: fetchLimit,
                lastDocument: lastDocument
            )
            let newVideos = result.threads.map { $0.parentVideo }
            
            await MainActor.run {
                // ✅ SAME LOGIC: 30% recent, 70% old
                let now = Date()
                let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
                
                // ✅ CRITICAL: Filter out videos with empty IDs
                let validVideos = newVideos.filter { !$0.id.isEmpty }
                
                if validVideos.count < newVideos.count {
                    print("⚠️ DISCOVERY: Filtered out \(newVideos.count - validVideos.count) videos with empty IDs")
                }
                
                let recentVideos = validVideos.filter { $0.createdAt >= twentyFourHoursAgo }
                let olderVideos = validVideos.filter { $0.createdAt < twentyFourHoursAgo }
                
                let recentCount = min(Int(Double(subsequentBatchSize) * 0.3), recentVideos.count)
                let olderCount = subsequentBatchSize - recentCount
                
                let selectedRecent = Array(recentVideos.shuffled().prefix(recentCount))
                let selectedOlder = Array(olderVideos.shuffled().prefix(olderCount))
                
                let shuffledNew = (selectedRecent + selectedOlder).shuffled()
                allAvailableVideos.append(contentsOf: shuffledNew)
                
                lastDocument = result.lastDocument
                loadingState.hasMoreContent = result.hasMore
                loadingState.totalLoaded += shuffledNew.count
                loadingState.loadingBatch += 1
                loadingState.lastLoadTime = Date()
                
                // Apply filter and add to feed
                let newFilteredVideos = applyCurrentFilter(to: shuffledNew)
                let diversifiedNew = diversifyShuffle(videos: newFilteredVideos)
                filteredVideos.append(contentsOf: diversifiedNew)
                
                manageMemory()
                
                print("✅ DISCOVERY: Loaded \(shuffledNew.count) more videos (recent + old)")
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
        filteredVideos = diversifyShuffle(videos: filtered)
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
    
    // MARK: - MAXIMUM RANDOMIZATION - True Discovery
    
    private func diversifyShuffle(videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        guard videos.count > 1 else { return videos }
        
        // Group by creator
        var creatorBuckets: [String: [CoreVideoMetadata]] = [:]
        for video in videos {
            creatorBuckets[video.creatorID, default: []].append(video)
        }
        
        // Shuffle each creator's videos
        var shuffledBuckets = creatorBuckets.mapValues { $0.shuffled() }
        
        // Build result with MAXIMUM variety
        var result: [CoreVideoMetadata] = []
        var recentCreators: [String] = [] // Track last 5 creators
        let maxRecentTracking = 5
        
        while !shuffledBuckets.isEmpty {
            // Find creators NOT in recent list
            let availableCreators = shuffledBuckets.keys.filter { !recentCreators.contains($0) }
            
            let chosenCreatorID: String
            if !availableCreators.isEmpty {
                // Pick random from available creators
                chosenCreatorID = availableCreators.randomElement()!
            } else {
                // All creators used recently - pick random from any
                chosenCreatorID = shuffledBuckets.keys.randomElement()!
                recentCreators.removeAll() // Reset tracking
            }
            
            // Take one video from chosen creator
            if var creatorVideos = shuffledBuckets[chosenCreatorID], !creatorVideos.isEmpty {
                let video = creatorVideos.removeFirst()
                result.append(video)
                
                // Update recent creators tracking
                recentCreators.append(chosenCreatorID)
                if recentCreators.count > maxRecentTracking {
                    recentCreators.removeFirst()
                }
                
                // Update or remove bucket
                if creatorVideos.isEmpty {
                    shuffledBuckets.removeValue(forKey: chosenCreatorID)
                } else {
                    shuffledBuckets[chosenCreatorID] = creatorVideos
                }
            }
        }
        
        print("🎲 DISCOVERY: Ultra-randomized \(result.count) videos with max variety")
        return result
    }
}

// MARK: - Enhanced DiscoveryView with Progressive Loading

struct DiscoveryView: View {
    // MARK: - State
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - Preloading Service (NEW)
    private var preloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var discoveryMode: DiscoveryMode = .swipe
    @State private var currentSwipeIndex: Int = 0
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var isFullscreenMode = false
    @State private var showingSearch = false
    
    // Track last preloaded index to avoid duplicate preloads
    @State private var lastPreloadedIndex: Int = -1
    
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
                // Fullscreen Mode (engagement enabled here)
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
                
                // Preload first video after content loads
                await preloadVideosAroundIndex(0)
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
    
    // MARK: - Video Preloading (NEW)
    
    /// Preload videos around the current index for instant fullscreen playback
    private func preloadVideosAroundIndex(_ index: Int) async {
        guard !viewModel.filteredVideos.isEmpty else { return }
        guard index != lastPreloadedIndex else { return } // Avoid duplicate preloads
        
        lastPreloadedIndex = index
        
        let videos = viewModel.filteredVideos
        var videosToPreload: [CoreVideoMetadata] = []
        
        // Current video (high priority)
        if index >= 0 && index < videos.count {
            videosToPreload.append(videos[index])
        }
        
        // Next video
        if index + 1 < videos.count {
            videosToPreload.append(videos[index + 1])
        }
        
        // Previous video (in case they swipe back)
        if index - 1 >= 0 {
            videosToPreload.append(videos[index - 1])
        }
        
        // Preload with appropriate priorities
        for (i, video) in videosToPreload.enumerated() {
            let priority: PreloadPriority = i == 0 ? .high : .normal
            await preloadingService.preloadVideo(video, priority: priority)
        }
        
        print("🎬 DISCOVERY PRELOAD: Preloaded \(videosToPreload.count) videos around index \(index)")
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
                        lastPreloadedIndex = -1 // Reset preload tracking
                        
                        // Preload first video of new category
                        Task {
                            await preloadVideosAroundIndex(0)
                        }
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
    
    // MARK: - Content View with Progressive Loading + Preloading
    
    @ViewBuilder
    private var contentView: some View {
        switch discoveryMode {
        case DiscoveryMode.swipe:
            ZStack(alignment: .top) {
                DiscoverySwipeCards(
                    videos: viewModel.filteredVideos,
                    currentIndex: $currentSwipeIndex,
                    onVideoTap: { video in
                        // CRITICAL: Pause all discovery players before entering fullscreen
                        preloadingService.pauseAllPlayback()
                        
                        selectedVideo = video
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isFullscreenMode = true
                        }
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
                    
                    // Preload videos around new position for instant fullscreen
                    Task {
                        await preloadVideosAroundIndex(newValue)
                    }
                }
                .onChange(of: isFullscreenMode) { _, isFullscreen in
                    if !isFullscreen {
                        // Exiting fullscreen - resume card playback after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // Card will auto-play on reappear via onAppear
                        }
                    }
                }
                
                // Swipe Instructions Indicator
                swipeInstructionsIndicator
                    .padding(.top, 20)
            }
            
        case DiscoveryMode.grid:
            DiscoveryGridView(
                videos: viewModel.filteredVideos,
                onVideoTap: { video in
                    // For grid, preload before entering fullscreen
                    Task {
                        await preloadingService.preloadVideo(video, priority: .high)
                    }
                    
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
    
    // MARK: - ✅ NEW: Swipe Instructions Indicator
    
    private var swipeInstructionsIndicator: some View {
        HStack(spacing: 20) {
            // Left swipe instruction
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
            
            // Right swipe instruction
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
            
            // Tap instruction
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
}

#Preview {
    DiscoveryView()
        .environmentObject(AuthService())
}
