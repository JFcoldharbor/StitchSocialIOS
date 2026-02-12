//
//  ProfileVideoGrid.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Profile Video Grid with Thread Navigation
//  Dependencies: VideoThumbnailView, CoreVideoMetadata
//  Features: 3-column grid, pinned videos, pagination, video deletion
//
//  OPTIMIZATION: Preloading capped to 3 concurrent videos (was 9).
//    Each AVPlayer preload costs ~5-15MB. 9 simultaneous = 90-135MB spike.
//    Now staggers with TaskGroup maxConcurrency pattern.
//  BATCHING: Pagination fires at count-3 (was count-5) to reduce early fetches.
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
    
    let pinnedVideos: [CoreVideoMetadata]
    let onPinVideo: ((CoreVideoMetadata) -> Void)?
    let onUnpinVideo: ((CoreVideoMetadata) -> Void)?
    let canPinMore: Bool
    let isVideoPinned: ((CoreVideoMetadata) -> Bool)?
    
    let onLoadMore: (() -> Void)?
    let hasMoreVideos: Bool
    let isLoadingMore: Bool
    
    private var preloadingService: VideoPreloadingService {
        VideoPreloadingService.shared
    }
    
    @State private var hasPreloadedInitialVideos = false
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoreVideoMetadata?
    @State private var isDeletingVideo = false
    
    // MARK: - Body
    
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
        .onAppear { preloadInitialVideos() }
        .onChange(of: selectedTab) { _, _ in preloadTabVideos() }
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { videoToDelete = nil }
            Button("Delete", role: .destructive) {
                if let video = videoToDelete { deleteVideo(video) }
            }
        } message: {
            Text("This video will be permanently deleted. This action cannot be undone.")
        }
    }
    
    // MARK: - Content
    
    private var videoContentView: some View {
        VStack(spacing: 0) {
            if selectedTab == 0 && !pinnedVideos.isEmpty {
                pinnedVideosSection
            }
            if videos.isEmpty {
                emptyVideosView
            } else {
                videoGrid
            }
        }
    }
    
    // MARK: - Pinned Section
    
    private var pinnedVideosSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .padding(.top, 8)
            
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                spacing: 1
            ) {
                ForEach(Array(pinnedVideos.enumerated()), id: \.element.id) { index, video in
                    pinnedVideoItem(video: video, index: index)
                }
            }
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
                .padding(.top, 2)
        }
    }
    
    private func pinnedVideoItem(video: CoreVideoMetadata, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            VideoThumbnailView(video: video, showEngagementBadge: true) {
                let combinedVideos = pinnedVideos + videos
                onVideoTap(video, index, combinedVideos)
            }
            
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
    
    private func pinnedVideoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            Button(action: {}) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(action: { onUnpinVideo?(video) }) {
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
            
            if hasMoreVideos {
                paginationTriggerView
            }
        }
        .padding(.horizontal, 0)
        .padding(.bottom, 100)
    }
    
    // MARK: - Grid Item
    
    private func videoGridItem(video: CoreVideoMetadata, index: Int) -> some View {
        VideoThumbnailView(video: video, showEngagementBadge: true) {
            let adjustedIndex = pinnedVideos.count + index
            let combinedVideos = pinnedVideos + videos
            onVideoTap(video, adjustedIndex, combinedVideos)
            
            Task { await preloadAdjacentVideos(currentIndex: index) }
        }
        .contextMenu {
            if isCurrentUserProfile {
                videoContextMenu(video: video)
            }
        }
        .overlay {
            if isDeletingVideo && videoToDelete?.id == video.id {
                Color.black.opacity(0.7)
                    .overlay(ProgressView().tint(.white).scaleEffect(1.2))
            }
        }
        .onAppear {
            // Pagination trigger — fire at count-3 (tighter than count-5)
            if index >= videos.count - 3 && hasMoreVideos && !isLoadingMore {
                onLoadMore?()
            }
        }
    }
    
    // MARK: - Context Menu
    
    private func videoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            Button(action: {}) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if video.conversationDepth == 0 {
                Divider()
                if let isPinned = isVideoPinned, isPinned(video) {
                    Button(action: { onUnpinVideo?(video) }) {
                        Label("Unpin from Profile", systemImage: "pin.slash")
                    }
                } else if canPinMore {
                    Button(action: { onPinVideo?(video) }) {
                        Label("Pin to Profile", systemImage: "pin")
                    }
                } else {
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
    
    // MARK: - Pagination
    
    private var paginationTriggerView: some View {
        Group {
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().tint(.white).padding()
                    Spacer()
                }
                .frame(height: 60)
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear { onLoadMore?() }
            }
        }
    }
    
    // MARK: - Loading / Empty
    
    private var loadingVideosView: some View {
        VStack(spacing: 20) {
            ProgressView().tint(.white)
            Text("Loading Videos...")
                .foregroundColor(.gray)
        }
        .frame(height: 200)
    }
    
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
    
    // MARK: - Deletion
    
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
    
    // MARK: - Preloading (CAPPED at 3 concurrent)
    //
    // WHY: Each AVPlayer preload allocates 5-15MB of buffers.
    // Old code preloaded 6 initial + triggered 9 onAppear = up to 90MB spike.
    // Now: 3 pinned (high) + 3 initial (high) staggered sequentially.
    
    private func preloadInitialVideos() {
        guard !hasPreloadedInitialVideos, !videos.isEmpty else { return }
        hasPreloadedInitialVideos = true
        
        Task {
            // Pinned first — max 3
            for video in pinnedVideos.prefix(3) {
                await preloadingService.preloadVideo(video, priority: .high)
            }
            
            // First row only — 3 videos, sequential to avoid network spike
            for video in videos.prefix(3) {
                await preloadingService.preloadVideo(video, priority: .high)
            }
        }
    }
    
    private func preloadTabVideos() {
        Task {
            for video in videos.prefix(3) {
                await preloadingService.preloadVideo(video, priority: .normal)
            }
        }
    }
    
    private func preloadAdjacentVideos(currentIndex: Int) async {
        // Only preload next 1 and previous 1 (was next 2 + prev 1)
        var adjacent: [CoreVideoMetadata] = []
        if currentIndex > 0 { adjacent.append(videos[currentIndex - 1]) }
        if currentIndex + 1 < videos.count { adjacent.append(videos[currentIndex + 1]) }
        
        for video in adjacent {
            await preloadingService.preloadVideo(video, priority: .normal)
        }
    }
}

// MARK: - Convenience Initializers

extension ProfileVideoGrid {
    
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
        self.pinnedVideos = []
        self.onPinVideo = nil
        self.onUnpinVideo = nil
        self.canPinMore = false
        self.isVideoPinned = nil
        self.onLoadMore = nil
        self.hasMoreVideos = false
        self.isLoadingMore = false
    }
    
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
        self.pinnedVideos = pinnedVideos
        self.onPinVideo = onPinVideo
        self.onUnpinVideo = onUnpinVideo
        self.canPinMore = canPinMore
        self.isVideoPinned = isVideoPinned
        self.onLoadMore = onLoadMore
        self.hasMoreVideos = hasMoreVideos
        self.isLoadingMore = isLoadingMore
    }
    
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
        self.pinnedVideos = pinnedVideos
        self.onPinVideo = nil
        self.onUnpinVideo = nil
        self.canPinMore = false
        self.isVideoPinned = nil
        self.onLoadMore = onLoadMore
        self.hasMoreVideos = hasMoreVideos
        self.isLoadingMore = isLoadingMore
    }
}
