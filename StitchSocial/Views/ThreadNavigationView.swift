//
//  ThreadNavigationView.swift
//  StitchSocial
//
//  Layer 8: Views - Reusable Thread Navigation Container
//  🎨 REDESIGNED: Premium visual styling with glass morphism, dynamic gradients,
//     animated thread indicators, and modern iOS aesthetics
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
    @State private var ambientPhase: CGFloat = 0
    @State private var showIndicators: Bool = true
    @State private var indicatorOpacity: Double = 1.0
    
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
                // Layer 1: Dynamic ambient background
                ambientBackground
                
                // Layer 2: Main content container
                threadNavigationContainer(geometry: geometry)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                coordinator.handleDragChanged(value)
                                withAnimation(.easeOut(duration: 0.2)) {
                                    indicatorOpacity = 0.3
                                }
                            }
                            .onEnded { value in
                                coordinator.handleDragEnded(value)
                                withAnimation(.easeIn(duration: 0.4).delay(0.3)) {
                                    indicatorOpacity = 1.0
                                }
                            }
                    )
                
                // Layer 3: Edge vignette for depth
                edgeVignette
                
                // Layer 4: Thread navigation indicators
                navigationOverlay(geometry: geometry)
                
                // Layer 5: Context-specific chrome
                contextChrome(geometry: geometry)
            }
            .onAppear {
                containerSize = geometry.size
                coordinator.setThreads(initialThreads)
                startAmbientAnimation()
            }
            .onChange(of: geometry.size) { newSize in
                containerSize = newSize
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Ambient Animation
    
    private func startAmbientAnimation() {
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ambientPhase = 360
        }
    }
    
    // MARK: - Ambient Background
    
    private var ambientBackground: some View {
        ZStack {
            // Base
            Color.black
            
            // Animated gradient orbs (subtle, behind video)
            GeometryReader { geo in
                ZStack {
                    // Primary orb - follows thread context
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    contextAccentColor.opacity(0.15),
                                    contextAccentColor.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.6
                            )
                        )
                        .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                        .offset(
                            x: cos(ambientPhase * .pi / 180) * 50,
                            y: sin(ambientPhase * .pi / 180) * 30 - geo.size.height * 0.3
                        )
                        .blur(radius: 60)
                    
                    // Secondary orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    secondaryAccentColor.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width, height: geo.size.width)
                        .offset(
                            x: sin(ambientPhase * .pi / 180) * 40,
                            y: geo.size.height * 0.3
                        )
                        .blur(radius: 80)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Edge Vignette
    
    private var edgeVignette: some View {
        ZStack {
            // Top vignette (stronger for status bar area)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.3),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 200)
            .frame(maxHeight: .infinity, alignment: .top)
            
            // Bottom vignette
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.6)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 250)
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            // Subtle side vignettes
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.3), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 30)
                
                Spacer()
                
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 30)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
    
    // MARK: - Navigation Overlay
    
    private func navigationOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Vertical thread indicator (right side)
            if coordinator.threads.count > 1 {
                verticalThreadIndicator
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            
            // Horizontal stitch indicator (bottom)
            if let currentThread = coordinator.getCurrentThread(),
               currentThread.childVideos.count > 0 {
                horizontalStitchIndicator(thread: currentThread)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 100)
            }
        }
        .opacity(indicatorOpacity)
        .animation(.easeInOut(duration: 0.3), value: indicatorOpacity)
    }
    
    // MARK: - Vertical Thread Indicator
    
    private var verticalThreadIndicator: some View {
        VStack(spacing: 6) {
            ForEach(0..<min(coordinator.threads.count, 7), id: \.self) { index in
                let isActive = index == coordinator.navigationState.currentThreadIndex
                let distance = abs(index - coordinator.navigationState.currentThreadIndex)
                
                Capsule()
                    .fill(isActive ? contextAccentColor : Color.white.opacity(0.4))
                    .frame(width: isActive ? 4 : 3, height: isActive ? 24 : 12)
                    .opacity(distance > 3 ? 0.3 : 1.0)
                    .shadow(color: isActive ? contextAccentColor.opacity(0.6) : .clear, radius: 4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
            }
            
            // Overflow indicator
            if coordinator.threads.count > 7 {
                Text("+\(coordinator.threads.count - 7)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.5))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
    }
    
    // MARK: - Horizontal Stitch Indicator
    
    private func horizontalStitchIndicator(thread: ThreadData) -> some View {
        let totalStitches = thread.childVideos.count + 1 // +1 for parent
        let currentIndex = coordinator.navigationState.currentStitchIndex
        
        return HStack(spacing: 4) {
            ForEach(0..<totalStitches, id: \.self) { index in
                let isActive = index == currentIndex
                
                if isActive {
                    // Active indicator with progress feel
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [contextAccentColor, contextAccentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 20, height: 3)
                        .shadow(color: contextAccentColor.opacity(0.5), radius: 4)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.6))
                .shadow(color: .black.opacity(0.2), radius: 6)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
    }
    
    // MARK: - Context Chrome
    
    private func contextChrome(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top chrome
            topChrome(geometry: geometry)
            
            Spacer()
            
            // Bottom chrome (context-specific)
            bottomChrome(geometry: geometry)
        }
    }
    
    // MARK: - Top Chrome
    
    private func topChrome(geometry: GeometryProxy) -> some View {
        HStack {
            // Context badge
            if context == .discovery {
                discoveryBadge
            }
            
            Spacer()
            
            // Thread info pill
            if let thread = coordinator.getCurrentThread() {
                threadInfoPill(thread: thread)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, geometry.safeAreaInsets.top + 8)
    }
    
    // MARK: - Discovery Badge
    
    private var discoveryBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
            Text("Discover")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.purple, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.purple.opacity(0.4), radius: 8, y: 2)
        )
    }
    
    // MARK: - Thread Info Pill
    
    private func threadInfoPill(thread: ThreadData) -> some View {
        HStack(spacing: 8) {
            // Stitch count
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(thread.childVideos.count + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(contextAccentColor)
            
            // Divider
            if thread.childVideos.count > 0 {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3, height: 3)
                
                // Position indicator
                Text("\(coordinator.navigationState.currentStitchIndex + 1)/\(thread.childVideos.count + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4)
        )
    }
    
    // MARK: - Bottom Chrome
    
    private func bottomChrome(geometry: GeometryProxy) -> some View {
        Group {
            switch context {
            case .discovery:
                // Swipe hint for discovery
                swipeHint
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Swipe Hint
    
    private var swipeHint: some View {
        HStack(spacing: 20) {
            // Vertical swipe
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                Text("threads")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.5))
            
            // Horizontal swipe
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                Text("stitches")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
        .opacity(coordinator.threads.isEmpty ? 0 : 1)
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
    
    // MARK: - Video Container Factory
    
    private func videoContainer(
        video: CoreVideoMetadata,
        thread: ThreadData,
        isActive: Bool,
        containerID: String
    ) -> some View {
        Group {
            if context.useBoundedContainers {
                MyBoundedVideoContainer(
                    video: video,
                    thread: thread,
                    isActive: isActive,
                    containerID: containerID,
                    onVideoLoop: { videoID in
                        onVideoLoop?(videoID)
                    },
                    context: .profileGrid
                )
            } else {
                VideoPlayerComponent(
                    video: video,
                    isActive: isActive
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
    
    // MARK: - Context-Aware Colors
    
    private var contextAccentColor: Color {
        switch context {
        case .homeFeed:
            return Color.cyan
        case .discovery:
            return Color.purple
        case .profile:
            return Color.orange
        case .fullscreen:
            return Color.white
        }
    }
    
    private var secondaryAccentColor: Color {
        switch context {
        case .homeFeed:
            return Color.blue
        case .discovery:
            return Color.pink
        case .profile:
            return Color.red
        case .fullscreen:
            return Color.gray
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

// MARK: - Preview

#if DEBUG
struct ThreadNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        ThreadNavigationView(
            threads: [],
            context: .discovery,
            videoService: VideoService()
        )
        .previewDisplayName("Discovery - Styled")
    }
}
#endif
