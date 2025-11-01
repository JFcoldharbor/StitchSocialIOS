//
//  ThreadNavigationView.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Thread Navigation Container
//  Dependencies: ThreadNavigationCoordinator (Layer 6), VideoPlayerView, BoundedVideoContainer
//  Features: Context-aware navigation, gesture handling, smooth animations, context-aware kill notifications
//  Purpose: Shared navigation UI for HomeFeedView and ProfileView
//  FIXED: BoundedVideoContainer now accepts context parameter for kill notification immunity
//

import SwiftUI
import AVFoundation
import ObjectiveC

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
            ZStack {
                // Context-specific background
                contextBackground
                
                // Main content container
                threadNavigationContainer(geometry: geometry)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { coordinator.handleDragChanged($0) }
                            .onEnded { coordinator.handleDragEnded($0) }
                    )
                
                // Context-specific overlays
                contextOverlays
            }
            .onAppear {
                containerSize = geometry.size
                coordinator.setThreads(initialThreads)
            }
            .onChange(of: geometry.size) { newSize in
                containerSize = newSize
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    // MARK: - Thread Navigation Container
    
    private func threadNavigationContainer(geometry: GeometryProxy) -> some View {
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
    
    // MARK: - Video Container Factory (FIXED)
    
    private func videoContainer(
        video: CoreVideoMetadata,
        thread: ThreadData,
        isActive: Bool,
        containerID: String
    ) -> some View {
        Group {
            if context.useBoundedContainers {
                // ✅ FIXED: Pass context parameter
                MyBoundedVideoContainer(
                    video: video,
                    thread: thread,
                    isActive: isActive,
                    containerID: containerID,
                    onVideoLoop: { videoID in
                        onVideoLoop?(videoID)
                    },
                    context: .profileGrid  // ✅ Profile thumbnails use profileGrid context
                )
            } else {
                VideoPlayerView(
                    video: video,
                    isActive: isActive,
                    onEngagement: { interactionType in
                        onEngagement?(interactionType, video)
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isVideoActive(threadIndex: Int, stitchIndex: Int) -> Bool {
        return threadIndex == coordinator.navigationState.currentThreadIndex &&
               stitchIndex == coordinator.navigationState.currentStitchIndex &&
               !coordinator.navigationState.isAnimating
    }
    
    private func verticalPosition(for threadIndex: Int, geometry: GeometryProxy) -> CGFloat {
        let offset = CGFloat(threadIndex - coordinator.navigationState.currentThreadIndex)
        return offset * geometry.size.height
    }
    
    private func horizontalPosition(for stitchIndex: Int, geometry: GeometryProxy) -> CGFloat {
        let offset = CGFloat(stitchIndex - coordinator.navigationState.currentStitchIndex)
        return offset * geometry.size.width
    }
    
    // MARK: - Background Configurations
    
    private var contextBackground: some View {
        Group {
            switch context {
            case .homeFeed:
                Color.black.ignoresSafeArea()
                
            case .discovery:
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
            case .profile:
                Color.black.opacity(0.95).ignoresSafeArea()
                
            case .fullscreen:
                Color.black.ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Context-Specific Overlays
    
    private var contextOverlays: some View {
        VStack {
            switch context {
            case .homeFeed:
                Spacer()
            case .discovery:
                Spacer()
            case .profile:
                Spacer()
            case .fullscreen:
                Spacer()
            }
        }
    }
}

// MARK: - ThreadNavigationView Public Interface

extension ThreadNavigationView {
    
    func getCurrentVideo() -> CoreVideoMetadata? {
        return coordinator.getCurrentVideo()
    }
    
    func getCurrentThread() -> ThreadData? {
        return coordinator.getCurrentThread()
    }
    
    func moveToThread(_ index: Int) {
        coordinator.smoothMoveToThread(index)
    }
    
    func moveToStitch(_ index: Int) {
        coordinator.smoothMoveToStitch(index)
    }
}

// MARK: - Thread Navigation Context Extension

extension ThreadNavigationContext {
    var useBoundedContainers: Bool {
        switch self {
        case .homeFeed, .discovery:
            return false
        case .profile, .fullscreen:
            return true
        }
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
