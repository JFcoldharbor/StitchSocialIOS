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
    
    // MARK: - Services
    
    @StateObject private var videoService = VideoService()
    
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
    
    /// Backward compatible initializer matching old CollectionPlayerViewModel pattern
    init(
        viewModel: CollectionPlayerViewModel,
        coordinator: CollectionCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.collection = viewModel.collection
        self.startingIndex = 0
        self.onDismiss = onDismiss
        self._currentSegmentIndex = State(initialValue: 0)
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
                    
                    // Simple engagement overlay (not ContextualVideoOverlay to avoid kill notifications)
                    if let segment = currentSegment {
                        simpleEngagementOverlay(for: segment)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            print("📚 COLLECTION PLAYER VIEW: onAppear called for collection \(collection.id)")
            print("📚 COLLECTION PLAYER VIEW: Collection title: \(collection.title)")
            print("📚 COLLECTION PLAYER VIEW: Segment count in collection: \(collection.segmentCount)")
            loadSegments()
        }
        .sheet(isPresented: $showingThreadView) {
            if let segment = currentSegment {
                ThreadDetailSheet(video: segment)
            }
        }
    }
    
    // MARK: - Simple Engagement Overlay (No kill notifications)
    
    private func simpleEngagementOverlay(for segment: CoreVideoMetadata) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                // Right side buttons
                VStack(spacing: 20) {
                    // Thread/Comments button
                    Button {
                        showingThreadView = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 28))
                            Text("\(segment.replyCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    
                    // Hype placeholder
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28))
                        Text("\(segment.hypeCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    
                    // Cool placeholder
                    VStack(spacing: 4) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 28))
                        Text("\(segment.coolCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Load Segments
    
    private func loadSegments() {
        print("📚 COLLECTION PLAYER: loadSegments() called")
        print("📚 COLLECTION PLAYER: Collection ID: \(collection.id)")
        
        Task {
            do {
                print("📚 COLLECTION PLAYER: Starting async load for \(collection.id)")
                let loadedSegments = try await videoService.getVideosByCollection(collectionID: collection.id)
                
                print("📚 COLLECTION PLAYER: Got \(loadedSegments.count) segments from service")
                
                // Sort by segment number
                let sortedSegments = loadedSegments.sorted {
                    ($0.segmentNumber ?? 0) < ($1.segmentNumber ?? 0)
                }
                
                await MainActor.run {
                    self.segments = sortedSegments
                    self.isLoading = false
                    print("📚 COLLECTION PLAYER: Set \(sortedSegments.count) segments, isLoading = false")
                    
                    if let first = sortedSegments.first {
                        print("📚 COLLECTION PLAYER: First segment URL: \(first.videoURL)")
                    }
                }
            } catch {
                print("❌ COLLECTION PLAYER: Error loading segments: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    print("❌ COLLECTION PLAYER: Set error message: \(error.localizedDescription)")
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
                if abs(index - currentSegmentIndex) <= 1 { // Only render adjacent segments
                    segmentView(segment: segment, index: index, geometry: geometry)
                        .id("\(segment.id)_\(index == currentSegmentIndex)")  // Force rebuild on active change
                }
            }
        }
        .gesture(horizontalDragGesture(geometry: geometry))
    }
    
    private func segmentView(segment: CoreVideoMetadata, index: Int, geometry: GeometryProxy) -> some View {
        let offset = calculateHorizontalOffset(for: index, geometry: geometry)
        let isActive = index == currentSegmentIndex && !isAnimating && !isLoading
        
        print("📺 SEGMENT VIEW: Creating view for segment \(index + 1), isActive: \(isActive), videoURL: \(segment.videoURL.prefix(50))...")
        
        return ZStack {
            // Use inline player instead of VideoPlayerComponent
            CollectionSegmentPlayer(
                video: segment,
                isActive: isActive
            )
            
            // Debug indicator
            #if DEBUG
            VStack {
                Spacer()
                HStack {
                    Text("Seg \(index + 1) | Active: \(isActive ? "YES" : "NO")")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(isActive ? .green : .red)
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.bottom, 120)
            }
            #endif
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
    
    var body: some View {
        NavigationStack {
            // Thread view for this segment's replies
            VStack {
                Text("Replies to: \(video.segmentDisplayTitle)")
                    .font(.headline)
                    .padding()
                
                Text("Thread view coming soon...")
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Collection Segment Player (Self-contained AVPlayer)

/// Simple video player for collection segments
struct CollectionSegmentPlayer: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    
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
        .onChange(of: isActive) { _, newValue in
            print("🎬 SEGMENT PLAYER: isActive changed to \(newValue) for \(video.id.prefix(8))")
            if newValue {
                player?.seek(to: .zero)
                player?.play()
                print("▶️ SEGMENT PLAYER: Playing \(video.id.prefix(8))")
            } else {
                player?.pause()
                print("⏸️ SEGMENT PLAYER: Paused \(video.id.prefix(8))")
            }
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else {
            print("❌ SEGMENT PLAYER: Invalid URL: \(video.videoURL)")
            hasError = true
            errorMessage = "Invalid video URL"
            isLoading = false
            return
        }
        
        print("🎬 SEGMENT PLAYER: Setting up player for URL: \(url)")
        
        let playerItem = AVPlayerItem(url: url)
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
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            if isActive {
                newPlayer.play()
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
