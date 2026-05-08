//
//  ReactionCameraView.swift
//  StitchSocial
//
//  Split-canvas reaction recorder.
//  - Two zones: Camera zone + Content zone
//  - Enter immediately — no video required upfront
//  - Layout picker: 50/50, 70/30, 30/70, PiP
//  - Swap button flips zone assignments
//  - Green screen toggle on camera zone
//  - Content zone: import video, image, or solid color
//  - Dual camera support (front/back per zone) via CinematicCameraManager
//
//  COMPOSITOR: After recording stops, ReactionCompositor merges the
//  camera recording + content zone into a single video matching the
//  selected layout. The merged URL is what reaches VideoReviewView.
//
//  CACHING NOTES:
//  - Content UIImage cached in ZoneContent enum, decoded to CGImage once
//    inside ReactionCompositor (not per-frame).
//  - Content video URL held by reference — AVAsset loaded once in compositor.
//  - Compositor cleanup called after handoff to release retained assets.

import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Layout

enum ReactionLayout: String, CaseIterable {
    case split5050  = "50/50"
    case split7030  = "70/30"
    case split3070  = "30/70"
    case pip        = "PiP"

    var icon: String {
        switch self {
        case .split5050: return "square.split.2x1"
        case .split7030: return "rectangle.topthird.inset.filled"
        case .split3070: return "rectangle.bottomthird.inset.filled"
        case .pip:       return "pip"
        }
    }

    // Returns (top fraction, bottom fraction) of screen height
    var split: (CGFloat, CGFloat) {
        switch self {
        case .split5050: return (0.5,  0.5)
        case .split7030: return (0.7,  0.3)
        case .split3070: return (0.3,  0.7)
        case .pip:       return (1.0,  1.0) // special handling
        }
    }
}

// MARK: - Zone Content

enum ZoneContent {
    case camera
    case importedVideo(URL)
    case importedImage(UIImage)
    case solidColor(Color)
}

// MARK: - Pause Timeline
//
// Tracks user-driven pauses on the source video during recording. The
// camera always rolls; pause windows are spans of camera-time during
// which the source video is frozen at a specific source-time. The
// compositor uses these to build the final content track with frozen
// frames in the pause windows.

struct PauseEvent: Equatable {
    var cameraStart: TimeInterval     // elapsed camera time when pause began
    var cameraEnd: TimeInterval?      // nil = still paused (will be closed at stop)
    var sourceFreezeTime: TimeInterval  // where the source was when paused
}

// MARK: - Reaction State

@MainActor
class ReactionState: ObservableObject {
    @Published var layout: ReactionLayout = .split5050
    @Published var isSwapped = false           // false = camera top, content bottom
    @Published var isRecording = false
    @Published var isCompositing = false       // NEW: shown during post-record merge
    @Published var gsActive = false            // green screen on camera zone
    @Published var contentZone: ZoneContent = .solidColor(.black)
    @Published var showLayoutPicker = false
    @Published var showContentPicker = false
    @Published var errorMessage: String?

    // Source playback (for .importedVideo content). Owned here so the
    // pause/play button + scrubber can drive it from anywhere in the view.
    @Published var sourcePlayer: AVPlayer?
    @Published var sourceDuration: TimeInterval = 0      // seconds; 0 until loaded
    @Published var sourceCurrentTime: TimeInterval = 0   // observed via periodic time observer
    @Published var isSourcePaused: Bool = false          // user-toggled during recording
    @Published var sourceStartOffset: TimeInterval = 0   // scrub-set start point
    /// Live mute toggle for the source player. Default false so the
    /// creator hears what they're reacting to. Toggle on if they don't
    /// have headphones and don't want speaker bleed in the camera mic.
    @Published var isSourceMuted: Bool = false

    // Pause timeline accumulated during recording. Cleared on each new
    // recording session.
    @Published var pauseEvents: [PauseEvent] = []

    private var sourceTimeObserver: Any?
    private var recordingStartDate: Date?

    let cameraManager: CinematicCameraManager

    init(cameraManager: CinematicCameraManager) {
        self.cameraManager = cameraManager
    }

    var cameraIsTop: Bool { !isSwapped }

    private var onComplete: ((URL) -> Void)?
    private var activeCompositor: ReactionCompositor?

    func startRecording(onComplete: @escaping (URL) -> Void) {
        self.onComplete = onComplete
        guard cameraManager.isSessionRunning else {
            errorMessage = "Camera not ready"; return
        }
        if gsActive { GreenScreenProcessor.shared.activate() }

        // Reset pause timeline. We set recordingStartDate optimistically
        // BEFORE kicking off the camera, then refine it from the camera's
        // recording-started callback for accuracy. This way pause events
        // are never dropped due to a nil start date if the user mashes
        // pause within the first frames.
        pauseEvents.removeAll()
        isSourcePaused = false
        recordingStartDate = Date()

        if let player = sourcePlayer {
            let start = CMTime(seconds: sourceStartOffset, preferredTimescale: 600)
            player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in player.play() }
            }
        }

        cameraManager.startRecording { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                if let url {
                    // Camera file written — now composite with content zone
                    self.isRecording = false
                    self.closeOpenPauseEvent()  // ensure no half-open events leak into the compositor
                    self.sourcePlayer?.pause()
                    #if DEBUG
                    print("🎬 REACTION: Camera done — \(url.lastPathComponent)")
                    #endif
                    await self.compositeAndDeliver(cameraURL: url)
                } else {
                    self.isRecording = true
                    // Refine to the actual camera-start moment for tighter
                    // pause-window alignment than the optimistic date above.
                    self.recordingStartDate = Date()
                    #if DEBUG
                    print("🎬 REACTION: Recording started")
                    #endif
                }
            }
        }
    }

    // MARK: - Source Player Control

    /// Called from the picker/loadVideo path. Tears down any previous
    /// player + observer and builds a fresh one bound to this URL.
    private func attachSourcePlayer(url: URL) {
        // Tear down old observer + player first so we don't leak.
        if let observer = sourceTimeObserver, let oldPlayer = sourcePlayer {
            oldPlayer.removeTimeObserver(observer)
        }
        sourceTimeObserver = nil
        sourcePlayer?.pause()

        let player = AVPlayer(url: url)
        // Default to UNMUTED so creators can hear the clip they're reacting to.
        // The export still has the source audio on its own track (ducked under
        // the camera audio in the audio mix) so even if the mic picks up some
        // bleed from the speaker, the final mix is dominated by the clean track.
        // Wear headphones to eliminate bleed entirely. User can mute live via
        // the speaker toggle in the content zone.
        player.isMuted = isSourceMuted
        sourcePlayer = player
        sourceCurrentTime = 0
        sourceStartOffset = 0
        isSourcePaused = false

        // Observe playback time at ~30fps so the scrubber + pause-time
        // freeze logic see fresh values.
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: 600)
        sourceTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.sourceCurrentTime = time.seconds
        }

        // Load duration async.
        Task { @MainActor in
            do {
                let dur = try await AVURLAsset(url: url).load(.duration).seconds
                self.sourceDuration = dur.isFinite ? dur : 0
            } catch {
                self.sourceDuration = 0
            }
        }

        // Auto-loop in editing mode (before recording starts) so the
        // user can preview the whole video. During recording the
        // single-pass behavior takes over via the recording flow.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !self.isRecording {
                player.seek(to: .zero)
                player.play()
            }
        }

        player.play()
    }

    /// Toggles live preview audio for the source player. The export's
    /// source audio track is independent — muting here only affects what
    /// the creator hears live; the exported video still gets the mixed-in
    /// source audio.
    func toggleSourceMute() {
        isSourceMuted.toggle()
        sourcePlayer?.isMuted = isSourceMuted
    }

    /// Called by the scrubber. Only valid before recording starts.
    func seekSource(to seconds: TimeInterval) {
        guard !isRecording else { return }
        let clamped = max(0, min(seconds, sourceDuration))
        sourceStartOffset = clamped
        let t = CMTime(seconds: clamped, preferredTimescale: 600)
        sourcePlayer?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Called by the in-record pause/play button.
    func toggleSourcePause() {
        guard isRecording, let player = sourcePlayer, recordingStartDate != nil else { return }
        if isSourcePaused {
            resumeSource()
        } else {
            pauseSource()
        }
    }

    private func pauseSource() {
        guard let player = sourcePlayer, let start = recordingStartDate else { return }
        let cameraTime = Date().timeIntervalSince(start)
        let sourceTime = player.currentTime().seconds
        pauseEvents.append(PauseEvent(
            cameraStart: cameraTime,
            cameraEnd: nil,
            sourceFreezeTime: sourceTime.isFinite ? sourceTime : 0
        ))
        player.pause()
        isSourcePaused = true
        #if DEBUG
        print("🎬 REACTION: Pause @ camera=\(String(format: "%.2f", cameraTime))s, source=\(String(format: "%.2f", sourceTime))s")
        #endif
    }

    private func resumeSource() {
        guard let player = sourcePlayer, let start = recordingStartDate else { return }
        let cameraTime = Date().timeIntervalSince(start)
        if let last = pauseEvents.indices.last, pauseEvents[last].cameraEnd == nil {
            pauseEvents[last].cameraEnd = cameraTime
        }
        player.play()
        isSourcePaused = false
        #if DEBUG
        print("🎬 REACTION: Resume @ camera=\(String(format: "%.2f", cameraTime))s")
        #endif
    }

    /// Closes any open PauseEvent at the current camera time. Called when
    /// recording stops so the compositor never sees an unbounded pause.
    private func closeOpenPauseEvent() {
        guard let start = recordingStartDate else { return }
        let cameraTime = Date().timeIntervalSince(start)
        if let last = pauseEvents.indices.last, pauseEvents[last].cameraEnd == nil {
            pauseEvents[last].cameraEnd = cameraTime
        }
    }

    /// Runs ReactionCompositor to merge camera + content, then delivers.
    private func compositeAndDeliver(cameraURL: URL) async {
        isCompositing = true

        // Snapshot current state for compositor (layout/swap can't change mid-export)
        let compositor = ReactionCompositor(
            cameraURL: cameraURL,
            contentZone: contentZone,
            layout: layout,
            cameraIsTop: cameraIsTop,
            sourceStartOffset: sourceStartOffset,
            pauseEvents: pauseEvents
        )
        activeCompositor = compositor

        do {
            let mergedURL = try await compositor.composite()
            #if DEBUG
            print("🎬 REACTION: Composite done — \(mergedURL.lastPathComponent)")
            #endif
            isCompositing = false
            onComplete?(mergedURL)
            onComplete = nil
        } catch {
            #if DEBUG
            print("🎬 REACTION: Composite failed — \(error.localizedDescription)")
            #endif
            isCompositing = false
            errorMessage = "Failed to merge reaction video"
            // Fallback: deliver raw camera file so user isn't stuck
            onComplete?(cameraURL)
            onComplete = nil
        }

        compositor.cleanup()
        activeCompositor = nil
    }

    func stopRecording() {
        cameraManager.stopRecording()
        if gsActive { GreenScreenProcessor.shared.deactivate() }
        #if DEBUG
        print("🎬 REACTION: Stop requested — waiting for file...")
        #endif
    }

    func loadVideo(url: URL) {
        contentZone = .importedVideo(url)
        attachSourcePlayer(url: url)
    }

    func loadImage(_ image: UIImage) {
        contentZone = .importedImage(image)
    }

    func cleanup() {
        stopRecording()
        activeCompositor?.cleanup()
        activeCompositor = nil
        // Tear down source player + observer.
        if let observer = sourceTimeObserver, let player = sourcePlayer {
            player.removeTimeObserver(observer)
        }
        sourceTimeObserver = nil
        sourcePlayer?.pause()
        sourcePlayer = nil
        GreenScreenProcessor.shared.cleanup()
        #if DEBUG
        print("🎬 REACTION: Cleanup")
        #endif
    }
}

// MARK: - ReactionCameraView

struct ReactionCameraView: View {
    @StateObject private var state: ReactionState
    @ObservedObject var cameraManager: CinematicCameraManager

    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    /// Pre-fills the content zone with this video. Set when entering reaction
    /// mode from a stitch/reply context — the parent video the user tapped
    /// "Stitch" on becomes the default source so they don't have to import it
    /// from the gallery.
    let initialSourceURL: URL?

    @State private var videoPicker: PhotosPickerItem?
    @State private var imagePicker: PhotosPickerItem?
    @State private var didApplyInitialSource = false

    init(
        cameraManager: CinematicCameraManager,
        onComplete: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        initialSourceURL: URL? = nil
    ) {
        _state = StateObject(wrappedValue: ReactionState(cameraManager: cameraManager))
        self.cameraManager = cameraManager
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.initialSourceURL = initialSourceURL
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // ── Split canvas ───────────────────────────────────────
                splitCanvas(geo: geo)

                // ── Top bar ────────────────────────────────────────────
                VStack {
                    topBar
                        .padding(.top, 56)
                    Spacer()
                }

                // ── Bottom controls ────────────────────────────────────
                VStack {
                    Spacer()
                    bottomControls
                        .padding(.bottom, 40)
                }

                // ── Layout picker overlay ──────────────────────────────
                if state.showLayoutPicker {
                    layoutPickerOverlay
                }

                // ── Compositing overlay ────────────────────────────────
                if state.isCompositing {
                    compositingOverlay
                }

                // ── Error banner ───────────────────────────────────────
                if let err = state.errorMessage {
                    VStack {
                        errorBanner(err)
                        Spacer()
                    }
                    .padding(.top, 120)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Auto-fill the content zone with the source video when the
            // user is reacting to a specific clip (stitch/reply flow).
            // Guarded by didApplyInitialSource so picker swaps later are
            // honored — we don't keep slamming the original back in.
            if !didApplyInitialSource, let url = initialSourceURL {
                didApplyInitialSource = true
                state.loadVideo(url: url)
                #if DEBUG
                print("🎬 REACTION: Auto-filled source from stitch context — \(url.lastPathComponent)")
                #endif
            }
        }
        .onDisappear { state.cleanup() }
        // Single picker — handles both video and image as backdrop
        .photosPicker(
            isPresented: $state.showContentPicker,
            selection: $videoPicker,
            matching: .any(of: [.videos, .images])
        )
        .onChange(of: videoPicker) { _, item in
            guard let item else { return }
            loadContentItem(item)
        }
    }

    // MARK: - Split Canvas

    @ViewBuilder
    private func splitCanvas(geo: GeometryProxy) -> some View {
        let size = geo.size
        if state.layout == .pip {
            pipLayout(geo: geo)
        } else {
            let (topFrac, _) = state.layout.split
            let topH = size.height * topFrac
            let botH = size.height - topH

            VStack(spacing: 0) {
                // Top zone
                zoneView(isCameraZone: state.cameraIsTop, size: CGSize(width: size.width, height: topH))
                    .frame(width: size.width, height: topH)

                // Divider with swap button
                ZStack {
                    Rectangle().fill(Color.black).frame(height: 3)
                    swapButton
                }
                .frame(height: 3)
                .zIndex(10)

                // Bottom zone
                zoneView(isCameraZone: !state.cameraIsTop, size: CGSize(width: size.width, height: botH))
                    .frame(width: size.width, height: botH)
            }
        }
    }

    // MARK: - PiP Layout

    @ViewBuilder
    private func pipLayout(geo: GeometryProxy) -> some View {
        // Content fills screen, camera is small draggable bubble
        zoneView(isCameraZone: false, size: geo.size)
            .ignoresSafeArea()

        // Camera PiP bubble (top-right by default)
        VStack {
            HStack {
                Spacer()
                cameraZoneView(size: CGSize(width: 110, height: 150))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .padding(.trailing, 16)
                    .padding(.top, 110)
            }
            Spacer()
        }

        swapButton
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }

    // MARK: - Zone View

    @ViewBuilder
    private func zoneView(isCameraZone: Bool, size: CGSize) -> some View {
        if isCameraZone {
            cameraZoneView(size: size)
        } else {
            contentZoneView(size: size)
        }
    }

    // MARK: - Camera Zone

    @ViewBuilder
    private func cameraZoneView(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Preview layer
            if state.gsActive {
                GreenScreenPreviewView(processor: GreenScreenProcessor.shared)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            } else {
                ReactionCameraPreviewView(cameraManager: cameraManager)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            // Controls — on top, always hittable
            HStack(spacing: 10) {
                // Flip camera
                Button {
                    Task { await cameraManager.switchCamera() }
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }

                // Green screen toggle
                Button {
                    let mgr = state
                    mgr.gsActive.toggle()
                    mgr.gsActive
                        ? GreenScreenProcessor.shared.activate()
                        : GreenScreenProcessor.shared.deactivate()
                } label: {
                    Image(systemName: state.gsActive
                          ? "person.crop.rectangle.fill"
                          : "person.crop.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(state.gsActive ? .green : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(
                            state.gsActive
                                ? Color.green.opacity(0.25)
                                : Color.black.opacity(0.6)
                        ))
                }
            }
            .padding(.leading, 10)
            .padding(.bottom, 10)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Content Zone

    @ViewBuilder
    private func contentZoneView(size: CGSize) -> some View {
        ZStack {
            switch state.contentZone {
            case .solidColor(let c):
                c.ignoresSafeArea()
                // Import prompt
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Tap to add video or image")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .onTapGesture { state.showContentPicker = true }

            case .importedVideo:
                // Source video preview hosts state.sourcePlayer (owned by
                // ReactionState so the scrubber + pause button can drive it).
                ZStack {
                    ReactionSourcePlayerView(player: state.sourcePlayer)
                        .frame(width: size.width, height: size.height)
                        .clipped()

                    if state.isRecording {
                        // During recording: only the pause/play button is
                        // active; the scrubber locks (timing matters now).
                        sourcePauseButton
                    } else {
                        // Pre-record: scrubber lets user pick a start point.
                        // Bottom padding clears the record button row at the
                        // bottom of the screen so the two don't overlap when
                        // the content zone is the bottom half (or PiP).
                        VStack {
                            Spacer()
                            sourceScrubber(width: size.width)
                                .padding(.bottom, bottomControlsClearance)
                        }
                    }
                }

            case .importedImage(let img):
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

            case .camera:
                ReactionCameraPreviewView(cameraManager: cameraManager)
                    .frame(width: size.width, height: size.height)
            }

            // Bottom-right cluster: source mute toggle (video only) +
            // change-content button (any imported content).
            if case .solidColor = state.contentZone {} else {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Spacer()

                        // Mute toggle — only relevant for video sources.
                        if case .importedVideo = state.contentZone {
                            Button { state.toggleSourceMute() } label: {
                                Image(systemName: state.isSourceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(state.isSourceMuted ? .red : .white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                        }

                        Button { state.showContentPicker = true } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, bottomControlsClearance)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Source Scrubber (pre-record)

    @ViewBuilder
    private func sourceScrubber(width: CGFloat) -> some View {
        // Only show when there's a duration to scrub against. Slider value
        // binds to sourceStartOffset; while scrubbing, AVPlayer seeks so
        // the user sees the frame they're picking as their start point.
        if state.sourceDuration > 0.5 {
            VStack(spacing: 4) {
                HStack {
                    Text(timeLabel(state.sourceStartOffset))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text(timeLabel(state.sourceDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                Slider(
                    value: Binding(
                        get: { state.sourceStartOffset },
                        set: { state.seekSource(to: $0) }
                    ),
                    in: 0...max(state.sourceDuration, 0.1)
                )
                .tint(.white)
                Text("Drag to set reaction start")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Source Pause/Play (during record)

    private var sourcePauseButton: some View {
        VStack {
            Spacer()
            Button {
                state.toggleSourcePause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 56, height: 56)
                    Image(systemName: state.isSourcePaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            // Same clearance as the scrubber so the button doesn't sit
            // on top of the record button when content fills the bottom.
            .padding(.bottom, bottomControlsClearance)
        }
    }

    /// Bottom padding for in-zone controls (scrubber, pause button) so
    /// they never collide with the screen-level record button row.
    /// 40pt outer padding + 72pt button + a comfort margin.
    private var bottomControlsClearance: CGFloat { 130 }

    private func timeLabel(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Swap Button

    private var swapButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                state.isSwapped.toggle()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.7))
                    .shadow(color: .black.opacity(0.4), radius: 4))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }

            Spacer()

            // Layout picker button
            Button {
                withAnimation { state.showLayoutPicker.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.layout.icon)
                        .font(.system(size: 13))
                    Text(state.layout.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.4)))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Content picker
            Button { state.showContentPicker = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                    Text("Import")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .disabled(state.isRecording || state.isCompositing)

            // Record button
            Button {
                state.isRecording ? state.stopRecording() : state.startRecording(onComplete: onComplete)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    if state.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    }
                }
            }
            .disabled(state.isCompositing)

            // Placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Compositing Overlay

    private var compositingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
                Text("Merging reaction…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .transition(.opacity)
    }

    // MARK: - Layout Picker Overlay

    private var layoutPickerOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { state.showLayoutPicker = false } }

            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4).padding(.top, 10).padding(.bottom, 8)

                Text("Layout")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.bottom, 12)

                HStack(spacing: 16) {
                    ForEach(ReactionLayout.allCases, id: \.rawValue) { layout in
                        Button {
                            state.layout = layout
                            withAnimation { state.showLayoutPicker = false }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: layout.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(state.layout == layout ? .black : .white)
                                    .frame(width: 56, height: 56)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(state.layout == layout ? Color.white : Color.white.opacity(0.15)))
                                Text(layout.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    // MARK: - Error Banner

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.red.opacity(0.85).cornerRadius(10))
            .onTapGesture { state.errorMessage = nil }
    }

    // MARK: - Content Loading

    private func loadContentItem(_ item: PhotosPickerItem) {
        #if DEBUG
        print("🎬 REACTION PICKER: Loading — \(item.supportedContentTypes.map(\.identifier))")
        #endif
        let isVideo = item.supportedContentTypes.contains(where: {
            $0.conforms(to: .audiovisualContent) || $0.conforms(to: .movie)
        })
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data?):
                    if isVideo {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mp4"
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent("reaction_bg_\(UUID().uuidString).\(ext)")
                        do {
                            try data.write(to: dest)
                            #if DEBUG
                            print("🎬 REACTION PICKER: Video → \(dest.lastPathComponent) (\(data.count / 1024)KB)")
                            #endif
                            state.loadVideo(url: dest)
                        } catch {
                            #if DEBUG
                            print("🎬 REACTION PICKER ❌ Write failed — \(error)")
                            #endif
                            state.errorMessage = "Failed to load video"
                        }
                    } else {
                        guard let img = UIImage(data: data) else {
                            state.errorMessage = "Could not decode image"; return
                        }
                        #if DEBUG
                        print("🎬 REACTION PICKER: Image → \(img.size)")
                        #endif
                        state.loadImage(img)
                    }
                case .success(nil):
                    #if DEBUG
                    print("🎬 REACTION PICKER ❌ Data nil")
                    #endif
                    state.errorMessage = "Could not load content"
                case .failure(let e):
                    #if DEBUG
                    print("🎬 REACTION PICKER ❌ Failed — \(e)")
                    #endif
                    state.errorMessage = "Failed to load content"
                }
            }
        }
    }
}

// MARK: - Camera Preview (reaction context)

struct ReactionCameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CinematicCameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        attachPreviewLayer(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            // Re-attach if layer got orphaned (e.g. after returning from another view)
            let layer = cameraManager.previewLayer
            if layer.superlayer != uiView.layer {
                layer.removeFromSuperlayer()
                layer.frame = uiView.bounds
                uiView.layer.insertSublayer(layer, at: 0)
            } else {
                layer.frame = uiView.bounds
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Detach preview layer so the next owner (SimpleCameraPreview) can attach it cleanly
        uiView.layer.sublayers?
            .compactMap { $0 as? AVCaptureVideoPreviewLayer }
            .forEach { $0.removeFromSuperlayer() }
    }

    private func attachPreviewLayer(to view: UIView) {
        let layer = cameraManager.previewLayer
        layer.removeFromSuperlayer()  // detach from any previous owner
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
    }
}

// MARK: - Reaction Source Player View
//
// Displays the AVPlayer owned by ReactionState. Unlike ContentVideoPlayer
// below, this does NOT create or manage its own player — it just hosts
// whatever player the state is holding, so the scrubber and pause button
// can drive playback from outside.

struct ReactionSourcePlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> UIView {
        let view = HostingView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? HostingView else { return }
        DispatchQueue.main.async {
            view.playerLayer.player = player
            view.playerLayer.frame = view.bounds
        }
    }

    final class HostingView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Content Video Player (looping)

struct ContentVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let player = AVPlayer(url: url)
        player.isMuted = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        player.play()
        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { _ in player.seek(to: .zero); player.play() }
        context.coordinator.player = player
        context.coordinator.layer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.layer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var player: AVPlayer?
        var layer: AVPlayerLayer?
    }
}
