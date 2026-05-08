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
import AVFoundation

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
    
    @State private var isPlaying = false
    @State private var showingCancelAlert = false
    @State private var showingExportError = false
    @State private var selectedOverlayID: UUID? = nil
    @State private var editingOverlayID: UUID?  = nil
    @State private var activePanel: EditPanel? = nil
    @State private var showTextEditor = false
    
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

            // ── Full-screen video ──────────────────────────────────────
            videoPreview.ignoresSafeArea()

            // ── Live caption overlay (time-synced to playback) ─────────
            CaptionOverlayView(
                captions: editState.state.captions,
                currentTime: editState.currentPlaybackTime,
                enabled: editState.state.captionsEnabled,
                globalPosition: editState.state.globalCaptionPosition
            )

            // ── Text overlay canvas ────────────────────────────────────
            TextOverlayCanvasView(editState: editState, selectedOverlayID: $selectedOverlayID, editingOverlayID: $editingOverlayID)

            // ── Top bar ────────────────────────────────────────────────
            VStack {
                topBar
                    .padding(.top, 56)
                Spacer()
            }

            // ── Right-side tool rail ───────────────────────────────────
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Spacer()
                    toolRail
                        .padding(.bottom, 120)
                }
            }

            // ── Bottom: Next button ────────────────────────────────────
            VStack {
                Spacer()
                bottomBar
                    .padding(.bottom, 32)
            }

            // ── Panel sheets ───────────────────────────────────────────
            if let panel = activePanel {
                panelOverlay(panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Text editor floating toolbar ───────────────────────────
            // Pinned above the keyboard at screen level so the toolbar is
            // always reachable regardless of where the sticker sits.
            TextEditorOverlay(editState: editState, editingOverlayID: $editingOverlayID)

            // ── Processing overlay ─────────────────────────────────────
            if editState.state.isProcessing {
                processingOverlay
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
    
    // MARK: - Top Bar (minimal — just X and draft save)

    private var topBar: some View {
        HStack {
            Button { showingCancelAlert = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            Spacer()
            Button { Task { await saveDraft() } } label: {
                Text("Draft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Right Tool Rail (Instagram/TikTok style)

    private var toolRail: some View {
        VStack(spacing: 20) {
            ForEach(EditPanel.allCases, id: \.self) { panel in
                Button {
                    if panel == .text {
                        // Text: skip panel, immediately add centered sticker + enter edit
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            activePanel = nil
                        }
                        var new = TextOverlay(text: "", style: .boldPill)
                        new.font = .futura
                        new.normalizedX = 0.5
                        new.normalizedY = 0.3  // upper third — stays above keyboard
                        editState.addOverlay(new)
                        selectedOverlayID = new.id
                        editingOverlayID  = new.id
                        editState.pause(); isPlaying = false
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            activePanel = activePanel == panel ? nil : panel
                            if activePanel != nil { editState.pause(); isPlaying = false }
                        }
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        Text(panel.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                    .frame(width: 50)
                    .padding(.vertical, 4)
                    .background(
                        activePanel == panel
                            ? Capsule().fill(Color.white.opacity(0.2))
                            : Capsule().fill(Color.clear)
                    )
                }
            }
        }
        .padding(.trailing, 12)
    }

    // MARK: - Bottom Bar (Next button)

    private var bottomBar: some View {
        HStack {
            // Duration pill
            Text(formatDuration(editState.state.trimmedDuration))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.4)))

            Spacer()

            Button {
                Task { await proceedToThread() }
            } label: {
                HStack(spacing: 6) {
                    Text("Next")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .white.opacity(0.3), radius: 12)
                )
            }
            .disabled(editState.state.isProcessing || !editState.isPropertiesLoaded || !editState.captionsReady)
            .opacity((editState.isPropertiesLoaded && editState.captionsReady) ? 1 : 0.5)
            .overlay(alignment: .trailing) {
                if !editState.captionsReady && editState.isPropertiesLoaded {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .scaleEffect(0.7)
                        .offset(x: 36)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Panel Overlay

    @ViewBuilder
    private func panelOverlay(_ panel: EditPanel) -> some View {
        ZStack(alignment: .bottom) {
            // Dismiss tap area
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) { activePanel = nil }
                    editState.play(); isPlaying = true
                }

            VStack(spacing: 0) {
                // Drag handle
                Capsule().fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10).padding(.bottom, 6)

                switch panel {
                case .text:
                    TextOverlayPanelView(editState: editState, selectedOverlayID: $selectedOverlayID, editingOverlayID: $editingOverlayID)
                case .trim:
                    VideoTrimmerView(editState: editState)
                case .filters:
                    FilterPickerView(editState: editState)
                case .captions:
                    CaptionEditorView(editState: editState)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Video Preview

    private var videoPreview: some View {
        GeometryReader { geometry in
            ZStack {
                // Direct AVPlayerLayer — no AVKit wrapper, no .disabled interference
                AVPlayerLayerView(player: editState.player)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Tap to play/pause
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
    

    

    

    
    // MARK: - Actions
    
    private func startAutoPlayback() {
        print("🔍 PLAYBACK DEBUG 1: startAutoPlayback called")
        // Use .playAndRecord to coexist with camera session if it's still active.
        // .defaultToSpeaker routes audio to speaker instead of earpiece.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔍 PLAYBACK DEBUG 2: Audio session set ✅")
        } catch {
            print("🔍 PLAYBACK DEBUG 2: Audio session FAILED — \(error)")
        }
        print("🔍 PLAYBACK DEBUG 3: Player status = \(editState.player.status.rawValue), currentItem = \(editState.player.currentItem != nil)")
        editState.play()
        isPlaying = true
        print("🔍 PLAYBACK DEBUG 4: play() called, rate = \(editState.player.rate)")
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
        
        print("â¸ï¸ VIDEO REVIEW: Stopped playback on disappear")
    }
    
    private func saveDraft() async {
        do {
            try await draftManager.saveDraft(editState.state)
            print("ðŸ’¾ REVIEW: Draft saved")
        } catch {
            print("âŒ REVIEW: Failed to save draft: \(error)")
        }
    }
    
    private func proceedToThread() async {
        // Block until video properties are loaded (prevents race condition)
        guard editState.isPropertiesLoaded else {
            exportService.exportError = "Still loading video. Please wait a moment."
            showingExportError = true
            return
        }

        // Block until auto-caption generation has completed (success or failure).
        // Without this gate the export can fire with an empty captions array
        // while SFSpeechRecognizer is still running in the background, and the
        // captions never get baked into the MP4.
        guard editState.captionsReady else {
            exportService.exportError = "Generating captions… try again in a second."
            showingExportError = true
            return
        }
        
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
        
        // Always export when text overlays present — must be burned in
        let needsExport = editState.state.hasEdits && (
            !editState.state.isProcessingComplete || editState.state.hasTextOverlays
        )
        if needsExport {
            print("📤 REVIEW: Exporting — overlays=\(editState.state.textOverlays.count)")
            editState.startProcessing()
            do {
                let result = try await exportService.exportVideo(editState: editState.state)
                editState.finishProcessing(videoURL: result.videoURL, thumbnailURL: result.thumbnailURL)
            } catch {
                print("❌ REVIEW: Export failed: \(error)")
                exportService.exportError = error.localizedDescription
                showingExportError = true
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

// MARK: - AVPlayerLayerView
// Direct AVPlayerLayer rendering — avoids VideoPlayer wrapper issues.
// Re-attaches layer on every updateUIView so frame is always correct.

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PlayerView else { return }
        DispatchQueue.main.async {
            view.playerLayer.frame = view.bounds
        }
    }

    // UIView subclass that exposes its backing layer as AVPlayerLayer
    class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Edit Panel

enum EditPanel: String, CaseIterable {
    case text
    case trim
    case filters
    case captions

    var icon: String {
        switch self {
        case .text:     return "textformat"
        case .trim:     return "scissors"
        case .filters:  return "camera.filters"
        case .captions: return "text.bubble"
        }
    }

    var label: String {
        switch self {
        case .text:     return "Text"
        case .trim:     return "Trim"
        case .filters:  return "Filters"
        case .captions: return "Captions"
        }
    }
}

// MARK: - Video Edit State Manager

@MainActor
class VideoEditStateManager: ObservableObject {
    
    @Published var state: VideoEditState
    @Published var isPropertiesLoaded = false
    @Published var captionsReady = false
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var isPlaying = false
    let player: AVPlayer
    
    private let autoCaptionService = AutoCaptionService.shared
    private var timeObserver: Any?
    
    init(initialState: VideoEditState) {
        self.state = initialState
        print("🔍 PLAYER DEBUG 1: Creating AVPlayer for \(initialState.videoURL.lastPathComponent)")
        print("🔍 PLAYER DEBUG 2: File exists = \(FileManager.default.fileExists(atPath: initialState.videoURL.path))")
        self.player = AVPlayer(url: initialState.videoURL)
        print("🔍 PLAYER DEBUG 3: AVPlayer created, status = \(player.status.rawValue)")
        
        // Track playback position at 30fps for smooth playhead
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0/30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentPlaybackTime = time.seconds
                self.isPlaying = (self.player.rate > 0)
            }
        }
        print("🔍 PLAYER DEBUG 4: Time observer added")
        
        Task {
            await loadVideoProperties()
            await autoGenerateCaptions()
        }
    }
    
    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }
    
    private func loadVideoProperties() async {
        let asset = AVAsset(url: state.videoURL)
        
        do {
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            
            if let track = tracks.first {
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                
                // FIXED: Apply preferredTransform to get the actual displayed size
                // naturalSize returns the raw buffer dimensions (e.g. 1920x1080 for portrait iPhone video)
                // The transform rotates it to the correct orientation (e.g. 1080x1920)
                let transformedSize = naturalSize.applying(preferredTransform)
                let size = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
                
                print("📐 VIDEO REVIEW: naturalSize=\(naturalSize), corrected=\(size), duration=\(String(format: "%.1f", duration))s")
                
                // Update state with actual properties
                await MainActor.run {
                    var updatedState = state
                    updatedState = VideoEditState(
                        videoURL: state.videoURL,
                        videoDuration: duration,
                        videoSize: size,
                        draftID: state.draftID
                    )
                    state = updatedState
                    isPropertiesLoaded = true
                }
            }
        } catch {
            print("❌ VIDEO REVIEW: Failed to load video properties: \(error)")
        }
    }
    
    private func autoGenerateCaptions() async {
        // Only auto-generate if no captions exist
        guard state.captions.isEmpty else {
            await MainActor.run { captionsReady = true }
            return
        }

        // captionsReady stays false until this Task finishes (success OR failure).
        // The Next button reads this flag so the user can't fire export on an
        // empty captions array while the speech recognizer is still running.
        defer { Task { @MainActor in self.captionsReady = true } }

        do {
            let captions = try await autoCaptionService.generateCaptions(from: state.videoURL)
            
            await MainActor.run {
                // Add all auto-generated captions
                for caption in captions {
                    state.addCaption(caption)
                }
                
                print("âœ… VIDEO REVIEW: Auto-generated \(captions.count) captions")
            }
        } catch CaptionError.noAudioTrack {
            print("â„¹ï¸ VIDEO REVIEW: No audio track - skipping auto-captions")
        } catch CaptionError.authorizationDenied {
            print("âš ï¸ VIDEO REVIEW: Speech recognition not authorized - skipping auto-captions")
        } catch {
            print("âš ï¸ VIDEO REVIEW: Auto-caption failed: \(error)")
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

    // MARK: - Text Overlay CRUD

    func addOverlay(_ overlay: TextOverlay) {
        state.textOverlays.append(overlay)
        state.lastModified = Date()
    }

    func removeOverlay(id: UUID) {
        state.textOverlays.removeAll { $0.id == id }
        state.lastModified = Date()
    }

    func updateOverlay(id: UUID, update: (inout TextOverlay) -> Void) {
        guard let idx = state.textOverlays.firstIndex(where: { $0.id == id }) else { return }
        update(&state.textOverlays[idx])
        state.lastModified = Date()
    }
}
