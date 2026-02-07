//
//  VideoReviewView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Review Screen
//  Dependencies: VideoEditState, LocalDraftManager, VideoExportService
//  Features: Trim, filter, caption editors with live preview
//

import SwiftUI
import AVKit

struct VideoReviewView: View {
    
    // MARK: - Properties
    
    @StateObject private var editState: VideoEditStateManager
    @StateObject private var draftManager = LocalDraftManager.shared
    @StateObject private var exportService = VideoExportService.shared
    
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    
    let onContinueToThread: (VideoEditState) -> Void
    let onCancel: () -> Void
    
    // MARK: - State
    
    @State private var selectedTab: EditTab = .trim
    @State private var isPlaying = false
    @State private var showingCancelAlert = false
    @State private var showingExportError = false
    
    // MARK: - Initialization
    
    init(
        initialState: VideoEditState,
        onContinueToThread: @escaping (VideoEditState) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _editState = StateObject(wrappedValue: VideoEditStateManager(initialState: initialState))
        self.onContinueToThread = onContinueToThread
        self.onCancel = onCancel
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Full-screen video preview (fills entire screen)
                ZStack {
                    videoPreview
                    
                    // Overlaid top toolbar
                    VStack {
                        topToolbar
                            .padding(.top, 50)
                        Spacer()
                    }
                    
                    // Overlaid edit tabs at bottom
                    VStack {
                        Spacer()
                        
                        // Edit content area (slides up over video)
                        editContentArea
                            .background(
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.8), Color.black],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 280)
                        
                        // Edit tabs
                        editTabBar
                        
                        // Bottom action bar
                        bottomActionBar
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert("Cancel Editing?", isPresented: $showingCancelAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                onCancel()
            }
        } message: {
            Text("Your edits will be lost if you haven't saved a draft.")
        }
        .alert("Export Error", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportService.exportError ?? "Failed to process video")
        }
        .onAppear {
            startAutoPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
        .task {
            // Auto-save draft periodically
            await startAutoSave()
        }
        .onChange(of: exportService.exportError) { _, newError in
            if newError != nil {
                showingExportError = true
            }
        }
    }
    
    // MARK: - Top Toolbar
    
    private var topToolbar: some View {
        HStack {
            Button {
                showingCancelAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
            }
            
            Spacer()
            
            Text("Edit Video")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            
            Spacer()
            
            Button {
                Task {
                    await saveDraft()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        GeometryReader { geometry in
            ZStack {
                // Fullscreen video player
                VideoPlayer(player: editState.player)
                    .disabled(true)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Tap to pause (like TikTok) - no visible indicator
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isPlaying {
                            editState.pause()
                            isPlaying = false
                        } else {
                            editState.play()
                            isPlaying = true
                        }
                    }
                
                // Processing overlay
                if editState.state.isProcessing {
                    processingOverlay
                }
            }
        }
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
            
            VStack(spacing: 16) {
                ProgressView(value: editState.state.processingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                    .frame(width: 200)
                
                Text("Processing...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("\(Int(editState.state.processingProgress * 100))%")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
            )
        }
    }
    
    // MARK: - Edit Tab Bar
    
    private var editTabBar: some View {
        HStack(spacing: 0) {
            ForEach(EditTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .cyan : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ?
                        Color.cyan.opacity(0.2) : Color.clear
                    )
                }
            }
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Edit Content Area
    
    private var editContentArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch selectedTab {
                case .trim:
                    VideoTrimmerView(editState: editState)
                    
                case .filters:
                    FilterPickerView(editState: editState)
                    
                case .captions:
                    CaptionEditorView(editState: editState)
                }
            }
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            // Duration display
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(formatDuration(editState.state.trimmedDuration))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            
            Spacer()
            
            // Continue button
            Button {
                Task {
                    await proceedToThread()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .cyan.opacity(0.4), radius: 12, x: 0, y: 4)
                )
            }
            .disabled(editState.state.isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Actions
    
    private func startAutoPlayback() {
        // Start playing immediately
        editState.play()
        isPlaying = true
        
        // Loop video playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: editState.player.currentItem,
            queue: .main
        ) { _ in
            editState.player.seek(to: .zero)
            editState.play()
        }
    }
    
    private func stopPlayback() {
        // Stop playing
        editState.pause()
        isPlaying = false
        
        // Remove observers
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: editState.player.currentItem
        )
        
        print("⏸️ VIDEO REVIEW: Stopped playback on disappear")
    }
    
    private func saveDraft() async {
        do {
            try await draftManager.saveDraft(editState.state)
            print("💾 REVIEW: Draft saved")
        } catch {
            print("❌ REVIEW: Failed to save draft: \(error)")
        }
    }
    
    private func proceedToThread() async {
        // CRITICAL: Validate trimmed duration against user's tier limit
        let videoService = VideoService()
        let userTier = authService.currentUser?.tier ?? .rookie
        let maxDuration = videoService.getMaxRecordingDuration(for: userTier)
        
        if editState.state.trimmedDuration > maxDuration {
            let maxFormatted = maxDuration >= 60
                ? String(format: "%d:%02d", Int(maxDuration) / 60, Int(maxDuration) % 60)
                : "\(Int(maxDuration))s"
            let currentFormatted = String(format: "%d:%02d", Int(editState.state.trimmedDuration) / 60, Int(editState.state.trimmedDuration) % 60)
            
            exportService.exportError = "Video is \(currentFormatted) but your max is \(maxFormatted). Use the trim tool to shorten it."
            showingExportError = true
            return
        }
        
        // If edits were made, start processing
        if editState.state.hasEdits && !editState.state.isProcessingComplete {
            editState.startProcessing()
            
            do {
                let result = try await exportService.exportVideo(editState: editState.state)
                editState.finishProcessing(videoURL: result.videoURL, thumbnailURL: result.thumbnailURL)
            } catch {
                print("❌ REVIEW: Export failed: \(error)")
                return
            }
        }
        
        // Proceed to thread view
        onContinueToThread(editState.state)
    }
    
    private func startAutoSave() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            await saveDraft()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Edit Tabs

enum EditTab: String, CaseIterable {
    case trim
    case filters
    case captions
    
    var title: String {
        switch self {
        case .trim: return "Trim"
        case .filters: return "Filters"
        case .captions: return "Captions"
        }
    }
    
    var icon: String {
        switch self {
        case .trim: return "scissors"
        case .filters: return "camera.filters"
        case .captions: return "text.bubble"
        }
    }
}

// MARK: - Video Edit State Manager

@MainActor
class VideoEditStateManager: ObservableObject {
    
    @Published var state: VideoEditState
    let player: AVPlayer
    
    private let autoCaptionService = AutoCaptionService.shared
    
    init(initialState: VideoEditState) {
        self.state = initialState
        self.player = AVPlayer(url: initialState.videoURL)
        
        // Load actual video properties and auto-generate captions
        Task {
            await loadVideoProperties()
            await autoGenerateCaptions()
        }
    }
    
    private func loadVideoProperties() async {
        let asset = AVAsset(url: state.videoURL)
        
        do {
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                
                // Update state with actual properties
                await MainActor.run {
                    // Create new state with correct properties
                    var updatedState = state
                    updatedState = VideoEditState(
                        videoURL: state.videoURL,
                        videoDuration: duration,
                        videoSize: size,
                        draftID: state.draftID
                    )
                    state = updatedState
                }
            }
        } catch {
            print("❌ VIDEO REVIEW: Failed to load video properties: \(error)")
        }
    }
    
    private func autoGenerateCaptions() async {
        // Only auto-generate if no captions exist
        guard state.captions.isEmpty else { return }
        
        do {
            let captions = try await autoCaptionService.generateCaptions(from: state.videoURL)
            
            await MainActor.run {
                // Add all auto-generated captions
                for caption in captions {
                    state.addCaption(caption)
                }
                
                print("✅ VIDEO REVIEW: Auto-generated \(captions.count) captions")
            }
        } catch CaptionError.noAudioTrack {
            print("ℹ️ VIDEO REVIEW: No audio track - skipping auto-captions")
        } catch CaptionError.authorizationDenied {
            print("⚠️ VIDEO REVIEW: Speech recognition not authorized - skipping auto-captions")
        } catch {
            print("⚠️ VIDEO REVIEW: Auto-caption failed: \(error)")
        }
    }
    
    func play() {
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func seekToStart() {
        let time = CMTime(seconds: state.trimStartTime, preferredTimescale: 600)
        player.seek(to: time)
    }
    
    func seekToEnd() {
        let time = CMTime(seconds: state.trimEndTime, preferredTimescale: 600)
        player.seek(to: time)
    }
    
    func startProcessing() {
        state.startProcessing()
    }
    
    func updateProgress(_ progress: Double) {
        state.updateProcessingProgress(progress)
    }
    
    func finishProcessing(videoURL: URL, thumbnailURL: URL) {
        state.finishProcessing(processedVideoURL: videoURL, thumbnailURL: thumbnailURL)
    }
}
