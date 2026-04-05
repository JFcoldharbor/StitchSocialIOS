//
//  CollectionPlayerView.swift
//  StitchSocial
//
//  Layer 6: Views - Collection Playback using FullscreenVideoView
//  Dependencies: FullscreenVideoView, CoreVideoMetadata, VideoCollection, ContextualVideoOverlay
//  Features: HORIZONTAL swipe between segments, ContextualVideoOverlay for engagement
//  UPDATED: Horizontal navigation + full engagement overlay support
//

import SwiftUI
import AVFoundation
import FirebaseAuth
import Combine

/// Collection player that displays segments with HORIZONTAL swipe navigation
/// Uses ContextualVideoOverlay for hype/cool engagement and thread comments
struct CollectionPlayerView: View {
    
    // MARK: - Properties
    
    let collection: VideoCollection
    let startingIndex: Int
    let onDismiss: () -> Void
    
    // MARK: - State
    
    @State private var segments: [CoreVideoMetadata] = []
    @State private var currentSegmentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showingThreadView: Bool = false
    @State private var showOverlay: Bool = true
    @State private var overlayHideTask: Task<Void, Never>? = nil
    
    // MARK: - Services
    
    @StateObject private var videoService = VideoService()
    @StateObject private var authService = AuthService()
    @StateObject private var playerCoordinator = SegmentPlayerCoordinator()
    
    // MARK: - Constants
    
    private let swipeThreshold: CGFloat = 100
    
    // MARK: - Initialization
    
    /// Primary initializer - loads segments automatically
    init(
        collection: VideoCollection,
        startingIndex: Int = 0,
        onDismiss: @escaping () -> Void
    ) {
        self.collection = collection
        self.startingIndex = startingIndex
        self.onDismiss = onDismiss
        self._currentSegmentIndex = State(initialValue: startingIndex)
    }
    
    // MARK: - Computed Properties
    
    private var currentSegment: CoreVideoMetadata? {
        guard currentSegmentIndex >= 0 && currentSegmentIndex < segments.count else { return nil }
        return segments[currentSegmentIndex]
    }
    
    private var hasNextSegment: Bool {
        currentSegmentIndex < segments.count - 1
    }
    
    private var hasPreviousSegment: Bool {
        currentSegmentIndex > 0
    }
    
    // MARK: - Body
    
    var body: some View {
        let _ = print("📚 COLLECTION PLAYER VIEW: body computed, collection: \(collection.title), segments loaded: \(segments.count)")
        
        return GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if segments.isEmpty {
                    emptyStateView
                } else {
                    // Video player with HORIZONTAL swipe
                    segmentPlayerView(geometry: geometry)
                    
                    // Collection-specific top bar (segment indicators)
                    collectionTopBar
                    
                    // Full engagement overlay — auto-hides after 5s, reappears on tap
                    if let segment = currentSegment {
                        ContextualVideoOverlay(
                            video: segment,
                            context: .collection,
                            currentUserID: authService.currentUserID,
                            isVisible: true,
                            onAction: { action in
                                handleOverlayAction(action, for: segment)
                            }
                        )
                        .opacity(showOverlay ? 1 : 0)
                        .animation(.easeOut(duration: 0.4), value: showOverlay)
                        .allowsHitTesting(showOverlay)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            loadSegments()
            showOverlayBriefly()
        }
        .sheet(isPresented: $showingThreadView) {
            if let segment = currentSegment {
                ThreadDetailSheet(video: segment)
            }
        }
        .onReceive(playerCoordinator.segmentEndSubject) { _ in
            guard currentSegmentIndex < segments.count - 1 else { return }
            currentSegmentIndex += 1
            // Preload segment after next
            let nextNext = currentSegmentIndex + 1
            if nextNext < segments.count {
                Task { await VideoDiskCache.shared.cacheVideo(from: segments[nextNext].videoURL) }
            }
        }
        .onReceive(playerCoordinator.segmentStartSubject) { _ in
            guard currentSegmentIndex > 0 else { return }
            currentSegmentIndex -= 1
        }
    }
    
    // MARK: - Overlay Action Handler
    
    private func handleOverlayAction(_ action: ContextualOverlayAction, for segment: CoreVideoMetadata) {
        switch action {
        case .thread(let threadID):
            showingThreadView = true
        case .reply:
            showingThreadView = true
        case .profile(let userID):
            // Navigate to profile — handled by overlay internally
            break
        case .share:
            // Share handled by overlay
            break
        default:
            break
        }
    }
    
    // MARK: - Overlay Visibility
    
    private func showOverlayBriefly() {
        showOverlay = true
        overlayHideTask?.cancel()
        overlayHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) { showOverlay = false }
            }
        }
    }
    
    // MARK: - Load Segments
    
    private func loadSegments() {
        Task {
            do {
                let loadedSegments = try await videoService.getVideosByCollection(collectionID: collection.id)
                let sortedSegments = loadedSegments.sorted {
                    ($0.segmentNumber ?? 0) < ($1.segmentNumber ?? 0)
                }
                
                await MainActor.run {
                    self.segments = sortedSegments
                    self.isLoading = false
                }
                
                // Preload next 2 segment videos to disk cache
                let urls = sortedSegments.prefix(3).map { $0.videoURL }.filter { !$0.isEmpty }
                Task { await VideoDiskCache.shared.prefetchVideos(urls) }
                
                // Preload AVPlayer for first + next segment
                if let first = sortedSegments.first {
                    let upcoming = Array(sortedSegments.dropFirst().prefix(1))
                    Task { await VideoPreloadingService.shared.preloadVideos(current: first, upcoming: upcoming) }
                }
                
                // Show overlay briefly on open
                showOverlayBriefly()
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Loading collection...")
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Failed to load")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Retry") {
                    isLoading = true
                    errorMessage = nil
                    loadSegments()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.cyan)
                .foregroundColor(.black)
                .cornerRadius(8)
                
                Button("Close") {
                    onDismiss()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    // MARK: - Segment Player View (HORIZONTAL)
    
    private func segmentPlayerView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Show videos stacked for HORIZONTAL swipe effect
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                if abs(index - currentSegmentIndex) <= 1 {
                    segmentView(segment: segment, index: index, geometry: geometry)
                }
            }
        }
        // Drag gesture runs simultaneously so it doesn't block taps
        .simultaneousGesture(horizontalDragGesture(geometry: geometry))
        // Single tap — pause/play + show overlay
        .onTapGesture {
            playerCoordinator.togglePlayback()
            showOverlayBriefly()
        }
        .gesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    let x = value.location.x
                    let w = geometry.size.width
                    if x < w * 0.30 {
                        playerCoordinator.seekRelative(-10)
                        print("⏪ DOUBLE TAP: Seek -10s")
                    } else if x > w * 0.70 {
                        playerCoordinator.seekRelative(10)
                        print("⏩ DOUBLE TAP: Seek +10s")
                    }
                }
        )
    }
    
    private func segmentView(segment: CoreVideoMetadata, index: Int, geometry: GeometryProxy) -> some View {
        let offset = calculateHorizontalOffset(for: index, geometry: geometry)
        // isActive = only current index — never toggle during re-renders from isAnimating/isLoading
        let isActive = index == currentSegmentIndex
        
        return ZStack {
            CollectionSegmentPlayer(
                video: segment,
                isActive: isActive,
                coordinator: playerCoordinator
            )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .offset(x: offset)
        .zIndex(index == currentSegmentIndex ? 1 : 0)
    }
    
    private func calculateHorizontalOffset(for index: Int, geometry: GeometryProxy) -> CGFloat {
        let baseOffset = CGFloat(index - currentSegmentIndex) * geometry.size.width
        
        if index == currentSegmentIndex {
            return dragOffset
        } else if index == currentSegmentIndex + 1 {
            // Next segment (to the right)
            return baseOffset + dragOffset
        } else if index == currentSegmentIndex - 1 {
            // Previous segment (to the left)
            return baseOffset + dragOffset
        }
        
        return baseOffset
    }
    
    // MARK: - Horizontal Drag Gesture
    
    private func horizontalDragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimating else { return }
                
                let translation = value.translation.width // HORIZONTAL
                
                // Allow drag if there's content in that direction
                if translation < 0 && hasNextSegment {
                    // Swiping left to go to next
                    dragOffset = translation
                } else if translation > 0 && hasPreviousSegment {
                    // Swiping right to go to previous
                    dragOffset = translation
                } else {
                    // Resistance at edges
                    dragOffset = translation * 0.3
                }
            }
            .onEnded { value in
                guard !isAnimating else { return }
                
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width - translation
                
                // Determine if we should change segments
                // Swipe LEFT (negative) = go to NEXT
                // Swipe RIGHT (positive) = go to PREVIOUS
                let shouldAdvance = (translation < -swipeThreshold || velocity < -500) && hasNextSegment
                let shouldGoBack = (translation > swipeThreshold || velocity > 500) && hasPreviousSegment
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAnimating = true
                    
                    if shouldAdvance {
                        currentSegmentIndex += 1
                        print("➡️ COLLECTION PLAYER: Advanced to segment \(currentSegmentIndex + 1)")
                    } else if shouldGoBack {
                        currentSegmentIndex -= 1
                        print("⬅️ COLLECTION PLAYER: Back to segment \(currentSegmentIndex + 1)")
                    }
                    
                    dragOffset = 0
                }
                
                // Reset animation flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isAnimating = false
                }
            }
    }
    
    // MARK: - Collection Top Bar (Segment Indicators)
    
    private var collectionTopBar: some View {
        VStack {
            HStack {
                // Close button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                
                Spacer()
                
                // Segment indicator pills (Instagram Stories style)
                if !segments.isEmpty {
                    segmentProgressIndicator
                }
                
                Spacer()
                
                // Placeholder for symmetry
                Color.clear
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            
            Spacer()
        }
    }
    
    private var segmentProgressIndicator: some View {
        VStack(spacing: 8) {
            // Progress bars (like Instagram Stories)
            HStack(spacing: 4) {
                ForEach(0..<segments.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentSegmentIndex ? Color.white : Color.white.opacity(0.3))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.2), value: currentSegmentIndex)
                }
            }
            .frame(maxWidth: 200)
            
            // Collection title and part indicator
            VStack(spacing: 2) {
                Text(collection.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("Part \(currentSegmentIndex + 1) of \(segments.count)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No segments available")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("This collection has no playable content")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Button("Close") {
                onDismiss()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.2))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
}

// MARK: - Thread Detail Sheet

struct ThreadDetailSheet: View {
    let video: CoreVideoMetadata
    @Environment(\.dismiss) private var dismiss
    @StateObject private var videoService = VideoService()
    @StateObject private var userService = UserService()
    
    private var muteManager = MuteContextManager.shared
    
    init(video: CoreVideoMetadata) {
        self.video = video
    }
    
    var body: some View {
        NavigationStack {
            ThreadView(
                threadID: video.threadID ?? video.id,
                videoService: videoService,
                userService: userService,
                targetVideoID: video.id
            )
            .environmentObject(muteManager)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Segment Player Coordinator

/// Shared coordinator using Combine subjects — does NOT re-render CollectionPlayerView.
/// PassthroughSubject fires events without triggering @Published parent re-renders.
class SegmentPlayerCoordinator: ObservableObject {
    
    struct SeekCommand {
        let seconds: Double
    }
    
    // Subjects — fire events without causing parent view re-renders
    let seekSubject       = PassthroughSubject<SeekCommand, Never>()
    let playbackSubject   = PassthroughSubject<Void, Never>()
    let segmentEndSubject = PassthroughSubject<Void, Never>()
    let segmentStartSubject = PassthroughSubject<Void, Never>()
    
    func seekRelative(_ delta: Double) {
        seekSubject.send(SeekCommand(seconds: delta))
    }
    
    func togglePlayback() {
        playbackSubject.send()
    }
    
    func didReachEnd() {
        segmentEndSubject.send()
    }
    
    func didReachStart() {
        segmentStartSubject.send()
    }
}

// MARK: - Collection Segment Player (Self-contained AVPlayer)

/// Simple video player for collection segments
struct CollectionSegmentPlayer: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    let coordinator: SegmentPlayerCoordinator
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                CollectionVideoPlayerView(player: player)
                    .ignoresSafeArea()
            }
            
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
            
            if hasError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMessage ?? "Failed to load video")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            print("🎬 SEGMENT PLAYER: onAppear for \(video.id.prefix(8)), isActive: \(isActive)")
            setupPlayer()
        }
        .onDisappear {
            print("🎬 SEGMENT PLAYER: onDisappear for \(video.id.prefix(8))")
            player?.pause()
            player = nil
        }
        .onChange(of: isActive) { oldValue, newValue in
            // Only act on genuine transitions, not spurious re-renders
            guard oldValue != newValue else { return }
            if newValue {
                player?.seek(to: .zero)
                player?.play()
                print("▶️ SEGMENT PLAYER: Playing \(video.id.prefix(8))")
            } else {
                player?.pause()
                print("⏸️ SEGMENT PLAYER: Paused \(video.id.prefix(8))")
            }
        }
        .onReceive(coordinator.seekSubject) { command in
            guard isActive, let player = player else { return }
            let current = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            guard duration > 0 else { return }
            let target = current + command.seconds
            if target >= duration - 0.5 {
                coordinator.didReachEnd()
            } else if target < 0 {
                coordinator.didReachStart()
            } else {
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                           toleranceBefore: .zero, toleranceAfter: .zero)
                print("⏩ SEGMENT PLAYER: Seeked \(command.seconds > 0 ? "+" : "")\(Int(command.seconds))s → \(String(format: "%.1f", target))s")
            }
        }
        .onReceive(coordinator.playbackSubject) { _ in
            guard isActive, let player = player else { return }
            if player.rate == 0 { player.play() } else { player.pause() }
        }
    }
    
    private func setupPlayer() {
        guard !video.videoURL.isEmpty else {
            print("❌ SEGMENT PLAYER: Empty video URL")
            hasError = true
            errorMessage = "No video URL"
            isLoading = false
            return
        }
        
        // Check disk cache first — instant local playback
        let playbackURL: URL
        if let cachedURL = VideoDiskCache.shared.getCachedURL(for: video.videoURL) {
            playbackURL = cachedURL
            print("💾 SEGMENT PLAYER: Playing from disk cache — \(video.id.prefix(8))")
        } else if let remoteURL = URL(string: video.videoURL) {
            playbackURL = remoteURL
            print("🌐 SEGMENT PLAYER: Streaming from network — \(video.id.prefix(8))")
            // Cache in background for next play
            Task { await VideoDiskCache.shared.cacheVideo(from: video.videoURL) }
        } else {
            print("❌ SEGMENT PLAYER: Invalid URL: \(video.videoURL)")
            hasError = true
            errorMessage = "Invalid video URL"
            isLoading = false
            return
        }
        
        let playerItem = AVPlayerItem(url: playbackURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        
        // Observe when ready to play
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    print("✅ SEGMENT PLAYER: Ready to play \(video.id.prefix(8))")
                    isLoading = false
                    if isActive {
                        newPlayer.play()
                        print("▶️ SEGMENT PLAYER: Auto-playing \(video.id.prefix(8))")
                    }
                case .failed:
                    print("❌ SEGMENT PLAYER: Failed to load \(video.id.prefix(8))")
                    hasError = true
                    errorMessage = playerItem.error?.localizedDescription ?? "Unknown error"
                    isLoading = false
                default:
                    break
                }
            }
            .store(in: &CollectionSegmentPlayer.cancellables)
        
        // When segment ends — advance to next segment via coordinator
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            if isActive {
                coordinator.didReachEnd()
                print("⏭️ SEGMENT PLAYER: Reached end, signaling advance for \(video.id.prefix(8))")
            }
        }
        
        self.player = newPlayer
    }
    
    // Static storage for Combine cancellables
    private static var cancellables = Set<AnyCancellable>()
}

// MARK: - Collection Video Player UIViewRepresentable

struct CollectionVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> CollectionPlayerUIView {
        let view = CollectionPlayerUIView()
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: CollectionPlayerUIView, context: Context) {
        uiView.player = player
    }
}

class CollectionPlayerUIView: UIView {
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Preview

#if DEBUG
struct CollectionPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Collection Player Preview")
    }
}
#endif
