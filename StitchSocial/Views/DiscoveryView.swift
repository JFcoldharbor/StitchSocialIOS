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
    
    // Services
    private let discoveryService = DiscoveryService()
    
    // MARK: - Load Initial Content with Deep Randomization
    
    func loadInitialContent() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("ðŸ” DISCOVERY: Loading deep randomized content")
            
            // Use deep randomized discovery
            let threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 40)
            let loadedVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                
                if validVideos.count < loadedVideos.count {
                    print("âš ï¸ DISCOVERY: Filtered out \(loadedVideos.count - validVideos.count) videos with empty IDs")
                }
                
                videos = validVideos
                // Shuffle on INITIAL load only
                applyFilterAndShuffle()
                errorMessage = nil
                
                print("âœ… DISCOVERY: Loaded \(filteredVideos.count) randomized videos")
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load discovery content"
                print("âŒ DISCOVERY: Load failed: \(error)")
            }
        }
    }
    
    // MARK: - Load More (APPEND to end, NO reshuffle)
    
    func loadMoreContent() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("ðŸ“¥ DISCOVERY: Loading more content (appending to end)")
            
            // Load another batch
            let threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 30)
            let newVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = newVideos.filter { !$0.id.isEmpty }
                
                // FIXED: Just append to END - don't reshuffle!
                videos.append(contentsOf: validVideos)
                filteredVideos.append(contentsOf: validVideos)
                
                print("âœ… DISCOVERY: Appended \(validVideos.count) videos to end, total: \(filteredVideos.count)")
            }
        } catch {
            print("âŒ DISCOVERY: Failed to load more: \(error)")
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
        
        print("ðŸŽ² DISCOVERY: Content randomized - \(filteredVideos.count) videos reshuffled")
    }
    
    // MARK: - Category Filtering
    
    func filterBy(category: DiscoveryCategory) async {
        currentCategory = category
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let threads: [ThreadData]
            
            switch category {
            case .all:
                // Deep randomized discovery
                threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 40)
                
            case .trending:
                // Trending content (last 7 days, high engagement)
                threads = try await discoveryService.getTrendingDiscovery(limit: 40)
                
            case .recent:
                // Only very recent (last 24 hours)
                threads = try await discoveryService.getRecentDiscovery(limit: 40)
                
            case .popular:
                // All-time popular content
                threads = try await discoveryService.getPopularDiscovery(limit: 40)
                
            case .following:
                // TODO: Implement following filter
                threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 40)
            }
            
            let loadedVideos = threads.map { $0.parentVideo }
            
            await MainActor.run {
                // Filter out videos with empty IDs
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                videos = validVideos
                applyFilterAndShuffle()
                
                print("ðŸ“Š DISCOVERY: Applied \(category.displayName) filter - \(filteredVideos.count) videos")
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load \(category.displayName) content"
                print("âŒ DISCOVERY: Category load failed: \(error)")
            }
        }
    }
    
    // MARK: - Filtering and Shuffling
    
    private func applyFilterAndShuffle() {
        filteredVideos = diversifyShuffle(videos: videos)
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

// MARK: - Video Presentation Wrapper (for item-based fullScreenCover)

struct DiscoveryVideoPresentation: Identifiable, Equatable {
    let id: String
    let video: CoreVideoMetadata
    
    static func == (lhs: DiscoveryVideoPresentation, rhs: DiscoveryVideoPresentation) -> Bool {
        lhs.id == rhs.id
    }
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
    
    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var discoveryMode: DiscoveryMode = .swipe
    @State private var currentSwipeIndex: Int = 0
    @State private var showingSearch = false
    
    // MARK: - Profile Navigation State
    
    @State private var selectedUserForProfile: String?
    @State private var showingProfileView = false
    
    // FIXED: Use item-based presentation instead of boolean
    @State private var videoPresentation: DiscoveryVideoPresentation?
    @EnvironmentObject var muteManager: MuteContextManager
    
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
                // Header
                headerView
                
                // Category Selector
                categorySelector
                
                // Content
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else {
                    contentView
                }
            }
        }
        .task {
            if viewModel.filteredVideos.isEmpty {
                await viewModel.loadInitialContent()
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView()
        }
        // FIXED: Use item-based fullScreenCover to prevent video stopping
        // Use .fullscreen context to get FULL overlay (not minimal .discovery overlay)
        .fullScreenCover(item: $videoPresentation) { presentation in
            FullscreenVideoView(
                video: presentation.video,
                overlayContext: .fullscreen,
                onDismiss: {
                    print("ðŸ“± DISCOVERY: Dismissing fullscreen")
                    videoPresentation = nil
                }
            )
        }
        // NEW: React to announcement state changes
        .onChange(of: announcementService.isShowingAnnouncement) { _, isShowing in
            if isShowing {
                print("ðŸ“¢ DISCOVERY: Announcement showing - pausing videos")
            } else {
                print("ðŸ“¢ DISCOVERY: Announcement dismissed - can resume videos")
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
                    Text("\(viewModel.filteredVideos.count) videos")
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
                // Randomize button
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
                        Task {
                            await viewModel.filterBy(category: category)
                        }
                        currentSwipeIndex = 0
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
                            // FIXED: Use item-based presentation
                            videoPresentation = DiscoveryVideoPresentation(
                                id: video.id,
                                video: video
                            )
                        },
                        onNavigateToProfile: { userID in
                            selectedUserForProfile = userID
                            showingProfileView = true
                        },
                        onNavigateToThread: { _ in }
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
                        // FIXED: Use item-based presentation
                        videoPresentation = DiscoveryVideoPresentation(
                            id: video.id,
                            video: video
                        )
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

#Preview {
    DiscoveryView()
        .environmentObject(AuthService())
}
