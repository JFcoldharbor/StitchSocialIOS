//
//  DiscoveryView.swift
//  StitchSocial
//
//  Layer 8: Views - Content Discovery Interface with Fullscreen Transition
//  Dependencies: DiscoverySwipeCards, FullscreenVideoView
//  Features: Mode toggle, category filtering, seamless fullscreen transition
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth

// MARK: - Discovery Mode

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

// MARK: - Discovery ViewModel

@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var errorMessage: String?
    
    private let videoService = VideoService()
    
    func loadContent() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await videoService.getAllThreadsWithChildren(limit: 50)
            videos = result.threads.map { $0.parentVideo }
            filteredVideos = videos
            errorMessage = nil
            print("DISCOVERY VM: Loaded \(videos.count) videos")
        } catch {
            errorMessage = "Failed to load discovery content"
            videos = []
            filteredVideos = []
            print("DISCOVERY VM: Failed to load content: \(error)")
        }
    }
    
    func filterBy(category: DiscoveryCategory) {
        currentCategory = category
        
        switch category {
        case .all:
            filteredVideos = videos
        case .trending:
            filteredVideos = videos.filter { $0.temperature == "hot" || $0.temperature == "blazing" }
        case .recent:
            filteredVideos = videos.sorted { $0.createdAt > $1.createdAt }
        case .popular:
            filteredVideos = videos.sorted { $0.hypeCount > $1.hypeCount }
        case .following:
            filteredVideos = videos
        }
        
        print("DISCOVERY VM: Filtered to \(filteredVideos.count) videos for \(category.displayName)")
    }
    
    func updateVideoEngagement(videoID: String, type: InteractionType) {
        // Update both main videos and filtered videos
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            var updatedVideo = videos[index]
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
            case .share:
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
                    coolCount: updatedVideo.coolCount,
                    replyCount: updatedVideo.replyCount,
                    shareCount: updatedVideo.shareCount + 1,
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
            case .view:
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
                    viewCount: updatedVideo.viewCount + 1,
                    hypeCount: updatedVideo.hypeCount,
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
            case .reply:
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
                    coolCount: updatedVideo.coolCount,
                    replyCount: updatedVideo.replyCount + 1,
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
            }
            videos[index] = updatedVideo
        }
        
        // Apply same logic to filteredVideos
        if let filteredIndex = filteredVideos.firstIndex(where: { $0.id == videoID }) {
            var updatedVideo = filteredVideos[filteredIndex]
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
            case .share:
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
                    coolCount: updatedVideo.coolCount,
                    replyCount: updatedVideo.replyCount,
                    shareCount: updatedVideo.shareCount + 1,
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
            case .view:
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
                    viewCount: updatedVideo.viewCount + 1,
                    hypeCount: updatedVideo.hypeCount,
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
            case .reply:
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
                    coolCount: updatedVideo.coolCount,
                    replyCount: updatedVideo.replyCount + 1,
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
            }
            filteredVideos[filteredIndex] = updatedVideo
        }
        
        print("DISCOVERY VM: Updated \(type.rawValue) for video \(videoID)")
    }
}

// MARK: - Main Discovery View

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject private var authService: AuthService
    @StateObject private var engagementCoordinator = EngagementCoordinator(
        videoService: VideoService(),
        notificationService: NotificationService()
    )
    
    // MARK: - State
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
            } else {
                // Fullscreen Mode
                if let video = selectedVideo {
                    FullscreenVideoView(video: video) {
                        // Dismiss callback
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isFullscreenMode = false
                        }
                        selectedVideo = nil
                        print("FULLSCREEN: Dismissed back to discovery")
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .navigationBarHidden(isFullscreenMode)
        .statusBarHidden(isFullscreenMode)
        .task {
            print("DISCOVERY: Starting loadContent task")
            await viewModel.loadContent()
            print("DISCOVERY: Loaded \(viewModel.filteredVideos.count) videos")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshDiscovery"))) { _ in
            Task {
                await viewModel.loadContent()
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView()
        }
        .onAppear {
            print("DISCOVERY DEBUG: Videos count = \(viewModel.videos.count)")
            print("DISCOVERY DEBUG: Filtered count = \(viewModel.filteredVideos.count)")
            if let firstVideo = viewModel.filteredVideos.first {
                print("DISCOVERY DEBUG: First video = \(firstVideo.title)")
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
                
                Text("\(viewModel.filteredVideos.count) videos")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
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
                
                // DEBUG: Direct fullscreen test
                Button {
                    if let firstVideo = viewModel.filteredVideos.first {
                        print("DEBUG: Direct fullscreen test with video: \(firstVideo.title)")
                        selectedVideo = firstVideo
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isFullscreenMode = true
                        }
                    } else {
                        print("DEBUG: No videos available for test")
                    }
                } label: {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
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
                ForEach(DiscoveryCategory.allCases, id: \.rawValue) { category in
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
        switch discoveryMode {
        case .swipe:
            DiscoverySwipeCards(
                videos: viewModel.filteredVideos,
                currentIndex: $currentSwipeIndex,
                onVideoTap: { video in
                    print("DISCOVERY: onVideoTap called for video: \(video.title)")
                    selectedVideo = video
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isFullscreenMode = true
                    }
                    print("DISCOVERY: Transitioning to fullscreen mode")
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
                print("DISCOVERY: Swipe index changed from \(oldValue) to \(newValue)")
                if newValue < viewModel.filteredVideos.count {
                    print("DISCOVERY: Now showing video: \(viewModel.filteredVideos[newValue].title)")
                }
            }
            
        case .grid:
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2), spacing: 2) {
                    ForEach(viewModel.filteredVideos, id: \.id) { video in
                        Button {
                            print("DISCOVERY GRID: Button tapped for video: \(video.title)")
                            selectedVideo = video
                            withAnimation(.easeInOut(duration: 0.4)) {
                                isFullscreenMode = true
                            }
                            print("DISCOVERY GRID: Transitioning to fullscreen mode")
                        } label: {
                            AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                print("GRID MODE: Grid view appeared with \(viewModel.filteredVideos.count) videos")
            }
        }
    }
    
    // MARK: - Loading and Error Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(1.5)
            
            Text("Discovering amazing content...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Discovery Error")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await viewModel.loadContent()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func handleEngagement(_ type: InteractionType, video: CoreVideoMetadata) {
        Task {
            do {
                // Process engagement with coordinator
                try await engagementCoordinator.processEngagement(
                    videoID: video.id,
                    engagementType: type,
                    userID: authService.currentUserID ?? "",
                    userTier: .rookie
                )
                
                // Update local video data immediately for UI responsiveness
                viewModel.updateVideoEngagement(videoID: video.id, type: type)
                
                print("DISCOVERY: Successfully processed \(type.rawValue) for video: \(video.title)")
                
            } catch {
                print("DISCOVERY: Engagement failed: \(error)")
            }
        }
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.cyan)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
