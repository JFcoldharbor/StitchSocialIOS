//
//  DiscoveryView.swift
//  CleanBeta
//
//  Layer 8: Views - Content Discovery Interface
//  Dependencies: Layer 7 (ViewModels), Layer 4 (Services), Layer 1 (Foundation)
//  Features: Grid and swipe modes, Firebase integration, controlled video players, contextual overlay
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVFoundation
import AVKit
import Combine

// MARK: - Discovery Mode Toggle

enum DiscoveryMode: String, CaseIterable {
    case grid = "grid"
    case swipe = "swipe"
    
    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .swipe: return "Swipe"
        }
    }
    
    var icon: String {
        switch self {
        case .grid: return "rectangle.grid.2x2"
        case .swipe: return "square.stack"
        }
    }
}

// MARK: - Discovery Category

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

// MARK: - Supporting Components (MOVED FROM INSIDE FullscreenVideoView)

struct StatBadge: View {
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            Text(formatCount(count))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}

struct StatItem: View {
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            Text(formatCount(count))
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Global Audio Session Manager (Simplified)

class GlobalAudioSessionManager: ObservableObject {
    static let shared = GlobalAudioSessionManager()
    
    @Published var isConfigured = false
    private var hasAttemptedSetup = false
    
    private init() {}
    
    func configureGlobalAudioSession() {
        guard !hasAttemptedSetup else { return }
        hasAttemptedSetup = true
        
        DispatchQueue.main.async {
            self.isConfigured = true
            print("GLOBAL AUDIO: Using system default audio session")
        }
    }
    
    func resetAudioSession() {
        print("GLOBAL AUDIO: Session reset (no-op)")
    }
}

// MARK: - Video Player Coordinator (Max 3 Players)

@MainActor
class VideoPlayerCoordinator: ObservableObject {
    @Published var activeVideoID: String?
    
    private var currentPlayer: AVPlayer?
    private var nextPlayer: AVPlayer?
    private var preloadingPlayer: AVPlayer?
    
    func setActiveVideo(_ videoID: String, videoURL: String) {
        guard activeVideoID != videoID else { return }
        
        if !GlobalAudioSessionManager.shared.isConfigured {
            GlobalAudioSessionManager.shared.configureGlobalAudioSession()
        }
        
        currentPlayer?.pause()
        activeVideoID = videoID
        
        if let existing = findExistingPlayer(for: videoURL) {
            currentPlayer = existing
            currentPlayer?.play()
        } else {
            createCurrentPlayer(videoURL: videoURL)
        }
    }
    
    func killAllBackgroundPlayers() {
        nextPlayer?.pause()
        preloadingPlayer?.pause()
        nextPlayer = nil
        preloadingPlayer = nil
        
        GlobalAudioSessionManager.shared.resetAudioSession()
    }
    
    func isVideoActive(_ videoID: String) -> Bool {
        return activeVideoID == videoID
    }
    
    private func createCurrentPlayer(videoURL: String) {
        if let next = nextPlayer, playerMatches(next, url: videoURL) {
            currentPlayer = next
            nextPlayer = nil
            currentPlayer?.play()
            return
        }
        
        currentPlayer?.pause()
        currentPlayer = createPlayer(for: videoURL)
        currentPlayer?.play()
    }
    
    private func createPlayer(for videoURL: String) -> AVPlayer? {
        guard let url = URL(string: videoURL) else { return nil }
        
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        
        return player
    }
    
    private func findExistingPlayer(for videoURL: String) -> AVPlayer? {
        if let next = nextPlayer, playerMatches(next, url: videoURL) {
            let player = next
            nextPlayer = nil
            return player
        }
        
        if let preload = preloadingPlayer, playerMatches(preload, url: videoURL) {
            let player = preload
            preloadingPlayer = nil
            return player
        }
        
        return nil
    }
    
    private func playerMatches(_ player: AVPlayer, url: String) -> Bool {
        guard let currentURL = player.currentItem?.asset as? AVURLAsset else { return false }
        return currentURL.url.absoluteString == url
    }
}

// MARK: - Discovery ViewModel

@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var lastDocument: DocumentSnapshot?
    @Published var hasMore = true
    @Published var errorMessage: String?
    
    private let videoService = VideoService()
    private let searchService = SearchService()
    
    func loadContent() async {
        isLoading = true
        lastDocument = nil
        hasMore = true
        errorMessage = nil
        
        do {
            let result = try await videoService.getThreadsForHomeFeed(limit: 50)
            videos = result.items
            
            // Sort by engagement for discovery
            videos.sort {
                let engagement1 = $0.hypeCount + $0.viewCount
                let engagement2 = $1.hypeCount + $1.viewCount
                return engagement1 > engagement2
            }
            
            filteredVideos = videos
            lastDocument = result.lastDocument
            hasMore = result.hasMore
            
            print("DISCOVERY: Loaded \(videos.count) videos from Firebase")
            
        } catch {
            print("DISCOVERY ERROR: Failed to load content - \(error)")
            errorMessage = "Failed to load discovery content. Please try again."
            videos = []
            filteredVideos = []
            hasMore = false
        }
        
        isLoading = false
    }
    
    func refreshContent() async {
        await loadContent()
    }
    
    func loadMoreContent() async {
        guard hasMore, !isLoading else { return }
        
        isLoading = true
        
        do {
            let result = try await videoService.getThreadsForHomeFeed(
                limit: 20,
                lastDocument: lastDocument
            )
            
            videos.append(contentsOf: result.items)
            lastDocument = result.lastDocument
            hasMore = result.hasMore
            
            filterBy(category: currentCategory)
            
            print("DISCOVERY: Loaded \(result.items.count) more videos")
            
        } catch {
            print("DISCOVERY ERROR: Failed to load more content - \(error)")
            hasMore = false
        }
        
        isLoading = false
    }
    
    func searchContent(query: String) async {
        guard !query.isEmpty else {
            filteredVideos = videos
            return
        }
        
        isLoading = true
        
        do {
            let searchResults = try await searchService.searchVideos(query: query, limit: 30)
            filteredVideos = searchResults
            print("DISCOVERY: Found \(searchResults.count) search results")
        } catch {
            print("DISCOVERY ERROR: Search failed - \(error)")
            filteredVideos = videos.filter { video in
                video.title.localizedCaseInsensitiveContains(query) ||
                video.creatorName.localizedCaseInsensitiveContains(query)
            }
        }
        
        isLoading = false
    }
    
    func filterBy(category: DiscoveryCategory) {
        currentCategory = category
        
        switch category {
        case .all:
            filteredVideos = videos
        case .trending:
            filteredVideos = videos.filter {
                let engagementRate = Double($0.hypeCount) / max(Double($0.viewCount), 1.0)
                return engagementRate > 0.1 || $0.hypeCount > 100
            }
        case .recent:
            filteredVideos = videos.sorted { $0.createdAt > $1.createdAt }
        case .popular:
            filteredVideos = videos.sorted { $0.viewCount > $1.viewCount }
        case .following:
            // TODO: Filter by following when user relationship data is available
            filteredVideos = videos.filter { $0.viewCount > 1000 }
        }
        
        print("DISCOVERY: Filtered to \(filteredVideos.count) videos for category \(category.displayName)")
    }
}

// MARK: - Main Discovery View

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @StateObject private var videoPlayerCoordinator = VideoPlayerCoordinator()
    @EnvironmentObject private var authService: AuthService
    
    @State private var selectedCategory: DiscoveryCategory = .all
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var discoveryMode: DiscoveryMode = .grid
    @State private var showingFullscreen = false
    @State private var selectedVideo: CoreVideoMetadata?
    
    // Swipe mode state
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isSwipeInProgress = false
    
    private let swipeThreshold: CGFloat = 80
    
    var body: some View {
        ZStack {
            // Full screen gradient background
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
                // Header with Mode Toggle
                headerView
                
                // Category Tabs
                categorySelector
                
                // Content
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else if viewModel.filteredVideos.isEmpty {
                    emptyStateView
                } else {
                    switch discoveryMode {
                    case .grid:
                        gridView
                    case .swipe:
                        swipeView
                    }
                }
            }
        }
        .onAppear {
            GlobalAudioSessionManager.shared.configureGlobalAudioSession()
        }
        .task {
            await viewModel.loadContent()
        }
        .refreshable {
            await viewModel.refreshContent()
        }
        .searchable(text: $searchText, isPresented: $showingSearch)
        .onSubmit(of: .search) {
            Task {
                await viewModel.searchContent(query: searchText)
            }
        }
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let video = selectedVideo {
                FullscreenVideoView(video: video)
                    .onAppear {
                        videoPlayerCoordinator.killAllBackgroundPlayers()
                    }
            }
        }
        .onChange(of: showingFullscreen) { oldValue, newValue in
            print("DEBUG: showingFullscreen changed from \(oldValue) to \(newValue)")
        }
        .onDisappear {
            killAllBackgroundPlayers()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Discover")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            // Mode Toggle
            HStack(spacing: 12) {
                ForEach(DiscoveryMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            discoveryMode = mode
                        }
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.title2)
                            .foregroundColor(discoveryMode == mode ? .cyan : .white.opacity(0.7))
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
    
    // MARK: - Category Selector
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(DiscoveryCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        viewModel.filterBy(category: category)
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
                                .fill(selectedCategory == category ? .cyan : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(minWidth: 80)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Grid View (Thumbnails Only)
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.filteredVideos) { video in
                    VideoCard(
                        video: video,
                        onTap: {
                            selectedVideo = video
                            showingFullscreen = true
                        },
                        coordinator: videoPlayerCoordinator
                    )
                }
                
                // Load more indicator
                if viewModel.hasMore {
                    Button {
                        Task {
                            await viewModel.loadMoreContent()
                        }
                    } label: {
                        HStack {
                            ProgressView()
                                .tint(.cyan)
                                .scaleEffect(0.8)
                            
                            Text("Load More")
                                .font(.subheadline)
                                .foregroundColor(.cyan)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - Swipe View
    
    private var swipeView: some View {
        ZStack {
            if !viewModel.filteredVideos.isEmpty {
                ForEach(0..<min(3, viewModel.filteredVideos.count), id: \.self) { index in
                    let cardIndex = currentIndex + index
                    
                    if cardIndex < viewModel.filteredVideos.count {
                        SwipeCard(
                            video: viewModel.filteredVideos[cardIndex],
                            isTopCard: index == 0,
                            offset: index == 0 ? dragOffset : .zero,
                            onTap: {
                                selectedVideo = viewModel.filteredVideos[cardIndex]
                                showingFullscreen = true
                            },
                            coordinator: videoPlayerCoordinator
                        )
                        .zIndex(Double(3 - index))
                        .scaleEffect(1.0 - (Double(index) * 0.03))
                        .offset(y: CGFloat(index * 8))
                        .opacity(1.0 - (Double(index) * 0.1))
                        .gesture(
                            index == 0 ? DragGesture()
                                .onChanged { value in
                                    if !isSwipeInProgress {
                                        dragOffset = value.translation
                                    }
                                }
                                .onEnded { value in
                                    handleSwipeEnd(value)
                                } : nil
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func killAllBackgroundPlayers() {
        videoPlayerCoordinator.killAllBackgroundPlayers()
        selectedVideo = nil
        currentIndex = 0
        dragOffset = .zero
        isSwipeInProgress = false
    }
    
    private func handleSwipeEnd(_ value: DragGesture.Value) {
        let translation = value.translation
        let isSuccessfulSwipe = abs(translation.width) > swipeThreshold || abs(translation.height) > swipeThreshold
        
        if isSuccessfulSwipe {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                dragOffset = CGSize(width: translation.width > 0 ? 500 : -500, height: 0)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.moveToNextCard()
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
    }
    
    private func moveToNextCard() {
        let nextIndex = currentIndex + 1
        
        if nextIndex < viewModel.filteredVideos.count {
            currentIndex = nextIndex
            let nextVideo = viewModel.filteredVideos[nextIndex]
            videoPlayerCoordinator.setActiveVideo(nextVideo.id, videoURL: nextVideo.videoURL)
        } else {
            Task {
                await viewModel.loadMoreContent()
            }
        }
        
        dragOffset = .zero
        isSwipeInProgress = false
    }
    
    // MARK: - Grid Layout
    
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }
    
    // MARK: - State Views
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.cyan)
            
            Text("Loading videos from Firebase...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Connection Error")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                Task {
                    await viewModel.refreshContent()
                }
            }
            .foregroundColor(.cyan)
            .font(.headline)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))
            
            Text("No videos found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Try adjusting your filters or check back later")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Refresh") {
                Task {
                    await viewModel.refreshContent()
                }
            }
            .foregroundColor(.cyan)
            .font(.headline)
        }
    }
}

// MARK: - Video Card Component

struct VideoCard: View {
    let video: CoreVideoMetadata
    let onTap: () -> Void
    @ObservedObject var coordinator: VideoPlayerCoordinator
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
                .aspectRatio(9/16, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if coordinator.isVideoActive(video.id) {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.black)
                                .font(.system(size: 16))
                        )
                        .shadow(radius: 4)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(video.duration))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
                
                VStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Text(video.creatorName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            StatBadge(icon: "flame.fill", count: video.hypeCount, color: Color.red)
                            StatBadge(icon: "eye.fill", count: video.viewCount, color: Color.white.opacity(0.6))
                            
                            Spacer()
                            
                            if video.hypeCount > 100 {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Swipe Card Component

struct SwipeCard: View {
    let video: CoreVideoMetadata
    let isTopCard: Bool
    let offset: CGSize
    let onTap: () -> Void
    @ObservedObject var coordinator: VideoPlayerCoordinator
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black)
                .frame(width: 320, height: 580)
                .overlay(
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                )
            
            VStack {
                Spacer()
                videoInfoOverlay
            }
            
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
        }
        .offset(offset)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .onChange(of: isTopCard) { _, newValue in
            if newValue {
                coordinator.setActiveVideo(video.id, videoURL: video.videoURL)
            }
        }
    }
    
    private var videoInfoOverlay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Text("By: \(video.creatorName)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 16) {
                    StatItem(icon: "flame.fill", count: video.hypeCount, color: Color.red)
                    StatItem(icon: "eye.fill", count: video.viewCount, color: Color.white.opacity(0.7))
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Fullscreen Video View

struct FullscreenVideoView: View {
    let video: CoreVideoMetadata
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showingOverlay = true
    @State private var dragOffset: CGSize = .zero
    
    private let dismissThreshold: CGFloat = 100
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)
                
                // Edge-to-edge video player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        
                        Text("Loading video...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                }
                
                // Contextual overlay (when visible)
                if showingOverlay {
                    ContextualVideoOverlay(
                        video: video,
                        context: .discovery,
                        currentUserID: Auth.auth().currentUser?.uid,
                        threadVideo: nil,
                        isVisible: showingOverlay,
                        onAction: { action in
                            handleOverlayAction(action)
                        }
                    )
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                }
                
                // Tap gesture overlay for toggling UI
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingOverlay.toggle()
                        }
                    }
            }
            .offset(y: dragOffset.height)
            .gesture(
                // Swipe down to dismiss gesture
                DragGesture()
                    .onChanged { value in
                        // Only allow downward swipes
                        if value.translation.height > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            // Dismiss with animation
                            withAnimation(.easeOut(duration: 0.3)) {
                                dragOffset = CGSize(width: 0, height: geometry.size.height)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                dismiss()
                            }
                        } else {
                            // Snap back to original position
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .ignoresSafeArea(.all)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else {
            print("Invalid video URL for \(video.title)")
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        print("FULLSCREEN PLAYER: Started playing \(video.title)")
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
        print("FULLSCREEN PLAYER: Cleaned up player")
    }
    
    private func handleOverlayAction(_ action: ContextualOverlayAction) {
        switch action {
        case .profile(let userID):
            print("Open profile for user: \(userID)")
        case .thread(let threadID):
            print("Open thread: \(threadID)")
        case .engagement(let type):
            print("Engagement action: \(type.rawValue)")
        case .follow, .unfollow:
            print("Follow action")
        case .share:
            print("Share video: \(video.title)")
        case .reply:
            print("Reply to video: \(video.title)")
        case .stitch:
            print("Stitch video: \(video.title)")
        case .profileManagement:
            print("Profile management")
        case .more:
            print("More options")
        case .followToggle:
            print("Follow toggle action")
        case .profileSettings:
            print("Profile settings action")
        }
    }
}

// MARK: - Preview

#Preview {
    DiscoveryView()
        .environmentObject(AuthService())
}
