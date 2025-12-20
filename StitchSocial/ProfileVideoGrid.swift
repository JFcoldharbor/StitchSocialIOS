//
//  ProfileVideoGrid.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Profile Video Grid with Thread Navigation
//  Dependencies: VideoThumbnailView, VideoCoordinator (Layer 6), CoreVideoMetadata
//  Features: 3-column grid, thread navigation, video deletion, loading states, pinned videos, pagination
//  UPDATED: Added pinned videos section and infinite scroll pagination
//

import SwiftUI

struct ProfileVideoGrid: View {
    
    // MARK: - Props
    
    let videos: [CoreVideoMetadata]
    let selectedTab: Int
    let tabTitles: [String]
    let isLoading: Bool
    let onVideoTap: (CoreVideoMetadata, Int, [CoreVideoMetadata]) -> Void
    let onVideoDelete: ((CoreVideoMetadata) -> Void)?
    let isCurrentUserProfile: Bool
    
    // MARK: - Pinned Videos Props (NEW)
    
    let pinnedVideos: [CoreVideoMetadata]
    let onPinVideo: ((CoreVideoMetadata) -> Void)?
    let onUnpinVideo: ((CoreVideoMetadata) -> Void)?
    let canPinMore: Bool
    let isVideoPinned: ((CoreVideoMetadata) -> Bool)?
    
    // MARK: - Pagination Props (NEW)
    
    let onLoadMore: (() -> Void)?
    let hasMoreVideos: Bool
    let isLoadingMore: Bool
    
    // MARK: - Preloading Dependencies (FIXED: Use singleton)
    
    private var preloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var hasPreloadedInitialVideos = false
    
    // MARK: - State
    
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoreVideoMetadata?
    @State private var isDeletingVideo = false
    
    var body: some View {
        Group {
            if isLoading {
                loadingVideosView
            } else if videos.isEmpty && pinnedVideos.isEmpty {
                emptyVideosView
            } else {
                videoContentView
            }
        }
        .id(selectedTab)
        .onAppear {
            preloadInitialVideos()
        }
        .onChange(of: selectedTab) { _, _ in
            preloadTabVideos()
        }
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                videoToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let video = videoToDelete {
                    deleteVideo(video)
                }
            }
        } message: {
            Text("This video will be permanently deleted. This action cannot be undone.")
        }
    }
    
    // MARK: - Video Content View (Pinned + Grid)
    
    private var videoContentView: some View {
        VStack(spacing: 0) {
            // Pinned Videos Section (only show on Threads tab or if we want it always visible)
            if selectedTab == 0 && !pinnedVideos.isEmpty {
                pinnedVideosSection
            }
            
            // Regular Video Grid
            if videos.isEmpty {
                emptyVideosView
            } else {
                videoGrid
            }
        }
    }
    
    // MARK: - Pinned Videos Section (NEW)
    
    private var pinnedVideosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                
                Text("Pinned")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Pinned Videos Row
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                spacing: 1
            ) {
                ForEach(Array(pinnedVideos.enumerated()), id: \.element.id) { index, video in
                    pinnedVideoItem(video: video, index: index)
                }
            }
            .padding(.horizontal, 0)
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Pinned Video Item
    
    private func pinnedVideoItem(video: CoreVideoMetadata, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            VideoThumbnailView(
                video: video,
                showEngagementBadge: true
            ) {
                // Create combined list for navigation (pinned first, then regular)
                let combinedVideos = pinnedVideos + videos
                onVideoTap(video, index, combinedVideos)
            }
            
            // Pin indicator overlay
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.orange)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                )
                .padding(6)
        }
        .contextMenu {
            if isCurrentUserProfile {
                pinnedVideoContextMenu(video: video)
            }
        }
    }
    
    // MARK: - Pinned Video Context Menu
    
    private func pinnedVideoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            Button(action: {
                // Share functionality
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            // Unpin option
            Button(action: {
                onUnpinVideo?(video)
            }) {
                Label("Unpin from Profile", systemImage: "pin.slash")
            }
            
            if onVideoDelete != nil {
                Divider()
                
                Button(role: .destructive, action: {
                    videoToDelete = video
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Video Grid
    
    private var videoGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
            spacing: 1
        ) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                videoGridItem(video: video, index: index)
            }
            
            // Pagination trigger and loading indicator
            if hasMoreVideos {
                paginationTriggerView
            }
        }
        .padding(.horizontal, 0)
        .padding(.bottom, 100)
    }
    
    // MARK: - Pagination Trigger View (NEW)
    
    private var paginationTriggerView: some View {
        Group {
            if isLoadingMore {
                // Loading indicator
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .padding()
                    Spacer()
                }
                .frame(height: 60)
            } else {
                // Invisible trigger view
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        print("📜 PAGINATION: Trigger view appeared")
                        onLoadMore?()
                    }
            }
        }
    }
    
    // MARK: - Video Grid Item
    
    private func videoGridItem(video: CoreVideoMetadata, index: Int) -> some View {
        VideoThumbnailView(
            video: video,
            showEngagementBadge: true
        ) {
            // CRITICAL: Call tap handler IMMEDIATELY - don't block on preloading
            // Adjust index to account for pinned videos in navigation
            let adjustedIndex = pinnedVideos.count + index
            let combinedVideos = pinnedVideos + videos
            onVideoTap(video, adjustedIndex, combinedVideos)
            
            // Preload adjacent videos AFTER navigation starts (non-blocking)
            Task {
                await preloadAdjacentVideos(currentIndex: index)
            }
        }
        .contextMenu {
            if isCurrentUserProfile {
                videoContextMenu(video: video)
            }
        }
        .overlay {
            if isDeletingVideo && videoToDelete?.id == video.id {
                Color.black.opacity(0.7)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    )
            }
        }
        .onAppear {
            // Preload when video becomes visible in grid
            if index < 9 { // First 9 visible videos (3x3 grid)
                preloadVideoIfNeeded(video)
            }
            
            // Trigger pagination when near end
            if index >= videos.count - 5 && hasMoreVideos && !isLoadingMore {
                print("📜 PAGINATION: Near end of list (index \(index) of \(videos.count))")
                onLoadMore?()
            }
        }
    }
    
    // MARK: - Context Menu (UPDATED with Pin/Unpin)
    
    private func videoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            Button(action: {
                // Share functionality could be added here
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            // Pin/Unpin options (threads only)
            if video.conversationDepth == 0 {
                Divider()
                
                if let isPinned = isVideoPinned, isPinned(video) {
                    Button(action: {
                        onUnpinVideo?(video)
                    }) {
                        Label("Unpin from Profile", systemImage: "pin.slash")
                    }
                } else if canPinMore {
                    Button(action: {
                        onPinVideo?(video)
                    }) {
                        Label("Pin to Profile", systemImage: "pin")
                    }
                } else {
                    // Show disabled state when max pins reached
                    Button(action: {}) {
                        Label("Pin Limit Reached (3)", systemImage: "pin.slash")
                    }
                    .disabled(true)
                }
            }
            
            if onVideoDelete != nil {
                Divider()
                
                Button(role: .destructive, action: {
                    videoToDelete = video
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Loading State
    
    private var loadingVideosView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
            Text("Loading Videos...")
                .foregroundColor(.gray)
        }
        .frame(height: 200)
    }
    
    // MARK: - Empty State
    
    private var emptyVideosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("No \(tabTitles.indices.contains(selectedTab) ? tabTitles[selectedTab] : "Videos")")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(height: 400)
    }
    
    // MARK: - Video Deletion
    
    private func deleteVideo(_ video: CoreVideoMetadata) {
        guard let onVideoDelete = onVideoDelete else { return }
        
        isDeletingVideo = true
        
        Task {
            await MainActor.run {
                onVideoDelete(video)
                isDeletingVideo = false
                videoToDelete = nil
            }
        }
    }
    
    // MARK: - Video Preloading System
    
    /// Preload first batch of videos when grid appears
    private func preloadInitialVideos() {
        guard !hasPreloadedInitialVideos, !videos.isEmpty else { return }
        
        hasPreloadedInitialVideos = true
        
        Task {
            // Preload pinned videos first with highest priority
            for video in pinnedVideos {
                await preloadingService.preloadVideo(video, priority: .high)
            }
            
            // Preload first 6 videos (2 rows) with high priority
            let initialVideos = Array(videos.prefix(6))
            
            print("🎬 GRID PRELOAD: Starting initial preload of \(initialVideos.count) videos")
            
            await withTaskGroup(of: Void.self) { group in
                for (index, video) in initialVideos.enumerated() {
                    group.addTask {
                        let priority: PreloadPriority = index < 3 ? .high : .normal
                        await self.preloadingService.preloadVideo(video, priority: priority)
                    }
                }
            }
            
            print("🎬 GRID PRELOAD: Initial preload completed")
        }
    }
    
    /// Preload videos when tab changes
    private func preloadTabVideos() {
        Task {
            // Preload first 3 videos of new tab
            let tabVideos = Array(videos.prefix(3))
            
            for video in tabVideos {
                await preloadingService.preloadVideo(video, priority: .normal)
            }
            
            print("🎬 GRID PRELOAD: Tab switched, preloaded \(tabVideos.count) videos")
        }
    }
    
    /// Preload individual video if not already cached
    private func preloadVideoIfNeeded(_ video: CoreVideoMetadata) {
        Task {
            // Check if already has player
            if preloadingService.getPlayer(for: video) == nil {
                await preloadingService.preloadVideo(video, priority: .low)
                print("🎬 GRID PRELOAD: Lazy loaded video \(video.id)")
            }
        }
    }
    
    /// Preload adjacent videos after navigation (non-blocking)
    private func preloadAdjacentVideos(currentIndex: Int) async {
        var adjacentVideos: [CoreVideoMetadata] = []
        
        // Previous video
        if currentIndex > 0 {
            adjacentVideos.append(videos[currentIndex - 1])
        }
        
        // Next 2 videos
        for i in 1...2 {
            let nextIndex = currentIndex + i
            if nextIndex < videos.count {
                adjacentVideos.append(videos[nextIndex])
            }
        }
        
        // Preload with normal priority
        for video in adjacentVideos {
            await preloadingService.preloadVideo(video, priority: .normal)
        }
        
        print("🎬 GRID PRELOAD: Adjacent preload completed for index \(currentIndex)")
    }
}

// MARK: - Convenience Initializers

extension ProfileVideoGrid {
    
    /// Simplified initializer for read-only grids (no deletion, no pinning)
    init(
        videos: [CoreVideoMetadata],
        selectedTab: Int = 0,
        tabTitles: [String] = ["Videos"],
        isLoading: Bool = false,
        onVideoTap: @escaping (CoreVideoMetadata, Int, [CoreVideoMetadata]) -> Void
    ) {
        self.videos = videos
        self.selectedTab = selectedTab
        self.tabTitles = tabTitles
        self.isLoading = isLoading
        self.onVideoTap = onVideoTap
        self.onVideoDelete = nil
        self.isCurrentUserProfile = false
        
        // Pinned defaults
        self.pinnedVideos = []
        self.onPinVideo = nil
        self.onUnpinVideo = nil
        self.canPinMore = false
        self.isVideoPinned = nil
        
        // Pagination defaults
        self.onLoadMore = nil
        self.hasMoreVideos = false
        self.isLoadingMore = false
    }
    
    /// Full initializer for editable grids (with deletion and pinning)
    init(
        videos: [CoreVideoMetadata],
        selectedTab: Int,
        tabTitles: [String],
        isLoading: Bool,
        isCurrentUserProfile: Bool,
        pinnedVideos: [CoreVideoMetadata] = [],
        canPinMore: Bool = false,
        hasMoreVideos: Bool = false,
        isLoadingMore: Bool = false,
        onVideoTap: @escaping (CoreVideoMetadata, Int, [CoreVideoMetadata]) -> Void,
        onVideoDelete: @escaping (CoreVideoMetadata) -> Void,
        onPinVideo: ((CoreVideoMetadata) -> Void)? = nil,
        onUnpinVideo: ((CoreVideoMetadata) -> Void)? = nil,
        isVideoPinned: ((CoreVideoMetadata) -> Bool)? = nil,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.videos = videos
        self.selectedTab = selectedTab
        self.tabTitles = tabTitles
        self.isLoading = isLoading
        self.onVideoTap = onVideoTap
        self.onVideoDelete = onVideoDelete
        self.isCurrentUserProfile = isCurrentUserProfile
        
        // Pinned props
        self.pinnedVideos = pinnedVideos
        self.onPinVideo = onPinVideo
        self.onUnpinVideo = onUnpinVideo
        self.canPinMore = canPinMore
        self.isVideoPinned = isVideoPinned
        
        // Pagination props
        self.onLoadMore = onLoadMore
        self.hasMoreVideos = hasMoreVideos
        self.isLoadingMore = isLoadingMore
    }
    
    /// Initializer for viewing other profiles (with pinned, no editing)
    init(
        videos: [CoreVideoMetadata],
        pinnedVideos: [CoreVideoMetadata],
        selectedTab: Int,
        tabTitles: [String],
        isLoading: Bool,
        hasMoreVideos: Bool = false,
        isLoadingMore: Bool = false,
        onVideoTap: @escaping (CoreVideoMetadata, Int, [CoreVideoMetadata]) -> Void,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.videos = videos
        self.selectedTab = selectedTab
        self.tabTitles = tabTitles
        self.isLoading = isLoading
        self.onVideoTap = onVideoTap
        self.onVideoDelete = nil
        self.isCurrentUserProfile = false
        
        // Pinned props (view only)
        self.pinnedVideos = pinnedVideos
        self.onPinVideo = nil
        self.onUnpinVideo = nil
        self.canPinMore = false
        self.isVideoPinned = nil
        
        // Pagination props
        self.onLoadMore = onLoadMore
        self.hasMoreVideos = hasMoreVideos
        self.isLoadingMore = isLoadingMore
    }
}
