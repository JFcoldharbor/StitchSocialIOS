//
//  ThreadNavigationView.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Thread Navigation Container
//  Dependencies: ThreadNavigationCoordinator (Layer 6), VideoPlayerView, BoundedVideoContainer
//  Features: Context-aware navigation, gesture handling, smooth animations
//  Purpose: Shared navigation UI for HomeFeedView and ProfileView
//

import SwiftUI
import AVFoundation

// MARK: - ThreadNavigationView

struct ThreadNavigationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var coordinator: ThreadNavigationCoordinator
    let context: ThreadNavigationContext
    let onVideoLoop: ((String) -> Void)?
    let onEngagement: ((InteractionType, CoreVideoMetadata) -> Void)?
    
    // MARK: - Initial Data
    
    private let initialThreads: [ThreadData]
    
    // MARK: - State
    
    @State private var containerSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init(
        threads: [ThreadData],
        context: ThreadNavigationContext,
        videoService: VideoService,
        onVideoLoop: ((String) -> Void)? = nil,
        onEngagement: ((InteractionType, CoreVideoMetadata) -> Void)? = nil
    ) {
        self.initialThreads = threads
        self.context = context
        self.onVideoLoop = onVideoLoop
        self.onEngagement = onEngagement
        self._coordinator = StateObject(wrappedValue: ThreadNavigationCoordinator(
            videoService: videoService,
            context: context
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            navigationContainer(geometry: geometry)
                .onAppear {
                    setupNavigation(geometry: geometry)
                    // Set initial threads after view appears
                    coordinator.setThreads(initialThreads)
                }
                .onChange(of: geometry.size) { _, newSize in
                    updateContainerSize(newSize)
                }
        }
        .coordinateSpace(name: "threadNavigation")
    }
    
    // MARK: - Navigation Container
    
    private func navigationContainer(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background
            contextBackground
            
            // Thread containers with positioning
            if coordinator.isReshuffling {
                reshufflingOverlay
            } else {
                threadContainerGrid(geometry: geometry)
            }
            
            // Context-specific overlays
            contextOverlays
        }
        .clipped()
        .gesture(
            DragGesture(minimumDistance: coordinator.minimumDragDistance)
                .onChanged { value in
                    coordinator.handleDragChanged(value)
                }
                .onEnded { value in
                    coordinator.handleDragEnded(value)
                }
        )
    }
    
    // MARK: - Thread Container Grid
    
    private func threadContainerGrid(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(coordinator.threads.enumerated()), id: \.offset) { threadIndex, thread in
                threadContainer(
                    thread: thread,
                    threadIndex: threadIndex,
                    geometry: geometry
                )
            }
        }
        .offset(
            x: coordinator.navigationState.horizontalOffset +
               (coordinator.navigationState.isAnimating ? 0 : coordinator.navigationState.dragOffset.width),
            y: coordinator.navigationState.verticalOffset +
               (coordinator.navigationState.isAnimating ? 0 : coordinator.navigationState.dragOffset.height)
        )
        .animation(
            coordinator.navigationState.isAnimating ? coordinator.animationSpring : nil,
            value: coordinator.navigationState.verticalOffset
        )
        .animation(
            coordinator.navigationState.isAnimating ? coordinator.animationSpring : nil,
            value: coordinator.navigationState.horizontalOffset
        )
    }
    
    // MARK: - Individual Thread Container
    
    private func threadContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            // Parent video container
            parentVideoContainer(
                thread: thread,
                threadIndex: threadIndex,
                geometry: geometry
            )
            
            // Child video containers (horizontal layout)
            ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
                childVideoContainer(
                    childVideo: childVideo,
                    thread: thread,
                    threadIndex: threadIndex,
                    childIndex: childIndex,
                    geometry: geometry
                )
            }
        }
        .id("\(thread.id)-\(thread.childVideos.count)")
    }
    
    // MARK: - Video Container Components
    
    private func parentVideoContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        videoContainer(
            video: thread.parentVideo,
            thread: thread,
            isActive: isVideoActive(threadIndex: threadIndex, stitchIndex: 0),
            containerID: "\(thread.id)-parent"
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .position(
            x: geometry.size.width / 2,
            y: geometry.size.height / 2 + verticalPosition(for: threadIndex, geometry: geometry)
        )
    }
    
    private func childVideoContainer(
        childVideo: CoreVideoMetadata,
        thread: ThreadData,
        threadIndex: Int,
        childIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        videoContainer(
            video: childVideo,
            thread: thread,
            isActive: isVideoActive(threadIndex: threadIndex, stitchIndex: childIndex + 1),
            containerID: "\(thread.id)-child-\(childIndex)"
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .position(
            x: geometry.size.width / 2 + horizontalPosition(for: childIndex + 1, geometry: geometry),
            y: geometry.size.height / 2 + verticalPosition(for: threadIndex, geometry: geometry)
        )
    }
    
    // MARK: - FIXED: Video Container Factory - Use Compatible BoundedVideoContainer
    
    private func videoContainer(
        video: CoreVideoMetadata,
        thread: ThreadData,
        isActive: Bool,
        containerID: String
    ) -> some View {
        Group {
            switch context {
            case .homeFeed, .discovery:
                // FIXED: Use the original BoundedVideoContainer (5 parameters) to avoid compilation error
                BoundedVideoContainer(
                    video: video,
                    thread: thread,
                    isActive: isActive,
                    containerID: containerID,
                    onVideoLoop: { videoID in
                        coordinator.incrementVideoPlayCount(for: videoID)
                        onVideoLoop?(videoID)
                    }
                )
                
            case .profile, .fullscreen:
                // Use enhanced VideoPlayerView for profile/fullscreen
                VideoPlayerView(
                    video: video,
                    isActive: isActive,
                    onEngagement: { interactionType in
                        onEngagement?(interactionType, video)
                    }
                )
                .onAppear {
                    if isActive {
                        coordinator.incrementVideoPlayCount(for: video.id)
                        onVideoLoop?(video.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Context-Specific UI
    
    private var contextBackground: some View {
        Group {
            switch context {
            case .homeFeed, .discovery:
                Color.black.ignoresSafeArea()
            case .profile:
                Color.clear // Profile handles its own background
            case .fullscreen:
                Color.black.ignoresSafeArea()
            }
        }
    }
    
    private var contextOverlays: some View {
        Group {
            switch context {
            case .homeFeed:
                // Home feed specific overlays (bubbles, etc.)
                EmptyView()
                
            case .profile:
                // Profile navigation hints
                profileNavigationHints
                
            case .discovery:
                // Discovery specific overlays
                EmptyView()
                
            case .fullscreen:
                // Fullscreen controls
                EmptyView()
            }
        }
    }
    
    private var profileNavigationHints: some View {
        VStack {
            Spacer()
            
            if let currentThread = coordinator.getCurrentThread(),
               !currentThread.childVideos.isEmpty {
                HStack {
                    Spacer()
                    
                    FloatingBubbleNotification(
                        replyCount: currentThread.childVideos.count,
                        context: .profile,
                        onDismiss: {},
                        onAction: nil
                    )
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Reshuffling Overlay
    
    private var reshufflingOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "shuffle.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
                .rotationEffect(.degrees(coordinator.isReshuffling ? 360 : 0))
                .animation(
                    .linear(duration: 1).repeatForever(autoreverses: false),
                    value: coordinator.isReshuffling
                )
            
            Text("Reshuffling feed...")
                .foregroundColor(.white)
                .font(.headline)
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
    }
    
    // MARK: - Setup and State Management
    
    private func setupNavigation(geometry: GeometryProxy) {
        containerSize = geometry.size
        coordinator.setContainerSize(geometry.size)
        
        // Start auto-progression for appropriate contexts
        if context.autoProgressionEnabled {
            coordinator.startAutoProgression()
        }
    }
    
    private func updateContainerSize(_ newSize: CGSize) {
        containerSize = newSize
        coordinator.setContainerSize(newSize)
    }
    
    // MARK: - Position Calculations
    
    private func verticalPosition(for threadIndex: Int, geometry: GeometryProxy) -> CGFloat {
        switch context {
        case .homeFeed, .discovery:
            return CGFloat(threadIndex) * geometry.size.height
        case .profile, .fullscreen:
            return 0 // Single thread view
        }
    }
    
    private func horizontalPosition(for stitchIndex: Int, geometry: GeometryProxy) -> CGFloat {
        switch context {
        case .homeFeed, .profile, .fullscreen:
            return CGFloat(stitchIndex) * geometry.size.width
        case .discovery:
            return 0 // No horizontal navigation in discovery
        }
    }
    
    private func isVideoActive(threadIndex: Int, stitchIndex: Int) -> Bool {
        return threadIndex == coordinator.navigationState.currentThreadIndex &&
               stitchIndex == coordinator.navigationState.currentStitchIndex
    }
    
    // MARK: - Public Interface
    
    func updateThreads(_ threads: [ThreadData]) {
        coordinator.setThreads(threads)
    }
    
    func reset() {
        coordinator.reset()
    }
    
    func getCurrentVideo() -> CoreVideoMetadata? {
        return coordinator.getCurrentVideo()
    }
    
    func getCurrentThread() -> ThreadData? {
        return coordinator.getCurrentThread()
    }
    
    // Navigation control methods
    func moveToThread(_ index: Int) {
        coordinator.smoothMoveToThread(index)
    }
    
    func moveToStitch(_ index: Int) {
        coordinator.smoothMoveToStitch(index)
    }
}

// MARK: - ADDED: Compatible BoundedVideoContainer Stub for ThreadNavigationView

struct BoundedVideoContainer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // TODO: Implement actual video player
        // For now, this prevents compilation errors in ThreadNavigationView
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // TODO: Update video player state
        // Placeholder implementation to prevent compilation errors
    }
}

// MARK: - ThreadNavigationView Previews

#if DEBUG
struct ThreadNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        ThreadNavigationView(
            threads: [],
            context: .homeFeed,
            videoService: VideoService()
        )
        .previewDisplayName("Home Feed Navigation")
        
        ThreadNavigationView(
            threads: [],
            context: .profile,
            videoService: VideoService()
        )
        .previewDisplayName("Profile Navigation")
    }
}
#endif
