//
//  RecordingView.swift
//  StitchSocial
//
//  Layer 7: Recording Interface
//
//  ARCHITECTURE:
//  - @ObservedObject controller (owned by presentation wrapper, not self)
//  - Gallery picker: sheet → onDismiss → nav push with .zoom transition
//  - Camera lifecycle: start on appear, stop on complete phase
//  - Audio session: set AFTER camera starts, restore AFTER camera stops
//  - NavigationStack onDisappear guarded — only cleans up when truly leaving
//  - No deprecated APIs, no Timer, no audio session conflicts
//
//  THREADING: All UI on MainActor, camera ops awaited properly
//

import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Navigation Destination

enum RecordingNavigationDestination: Hashable {
    case threadComposer(VideoEditState)
    case galleryReview(URL)

    static func == (lhs: RecordingNavigationDestination, rhs: RecordingNavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.threadComposer(let a), .threadComposer(let b)): return a.draftID == b.draftID
        case (.galleryReview(let a), .galleryReview(let b)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .threadComposer(let s): hasher.combine("composer"); hasher.combine(s.draftID)
        case .galleryReview(let u): hasher.combine("gallery"); hasher.combine(u.absoluteString)
        }
    }
}

// MARK: - Camera Mode

enum CameraMode: String, CaseIterable {
    case normal       = "Normal"
    case teleprompter = "Script"
    case greenScreen  = "BG"
    case reaction     = "React"

    var icon: String {
        switch self {
        case .normal:       return "camera.fill"
        case .teleprompter: return "text.alignleft"
        case .greenScreen:  return "person.crop.rectangle.fill"
        case .reaction:     return "play.rectangle.on.rectangle.fill"
        }
    }
}

// MARK: - Recording View

struct RecordingView: View {
    @ObservedObject var controller: RecordingController
    @StateObject private var teleprompterState = TeleprompterState()

    @State private var showGalleryPicker = false
    @State private var navigationPath: [RecordingNavigationDestination] = []
    @Namespace private var galleryZoom
    @State private var currentRecordingSource = "inApp"
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var lastZoomFactor: CGFloat = 1.0
    @State private var cameraMode: CameraMode = .normal
    @State private var showReactionCamera = false
    @State private var greenScreenActive = false
    @State private var galleryVideoURL: URL?
    @State private var galleryEditState: VideoEditState?

    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void

    init(
        controller: RecordingController,
        onVideoCreated: @escaping (CoreVideoMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.controller = controller
        self.onVideoCreated = onVideoCreated
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                switch controller.currentPhase {
                case .ready, .recording, .stopping:
                    cameraInterface

                case .aiProcessing:
                    processingInterface

                case .complete:
                    if let videoURL = controller.recordedVideoURL {
                        videoReviewView(url: videoURL)
                    }

                case .error(let message):
                    errorInterface(message)
                }
            }
            .navigationDestination(for: RecordingNavigationDestination.self) { destination in
                switch destination {
                case .threadComposer(let editState):
                    ThreadComposer(
                        recordedVideoURL: editState.finalVideoURL,
                        recordingContext: controller.recordingContext,
                        aiResult: controller.aiAnalysisResult,
                        recordingSource: currentRecordingSource,
                        trimStartTime: editState.hasTrim ? editState.trimStartTime : nil,
                        trimEndTime: editState.hasTrim ? editState.trimEndTime : nil,
                        userTier: controller.currentUserTier,
                        onVideoCreated: { metadata in
                            navigationPath.removeAll()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onVideoCreated(metadata)
                            }
                        },
                        onCancel: {
                            navigationPath.removeAll()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onCancel()
                            }
                        }
                    )

                case .galleryReview:
                    if let editState = galleryEditState {
                        VideoReviewView(
                            initialState: editState,
                            onContinueToThread: { finalState in
                                navigationPath.append(.threadComposer(finalState))
                            },
                            onCancel: {
                                galleryVideoURL = nil
                                galleryEditState = nil
                                navigationPath.removeAll()
                            }
                        )
                        .navigationTransition(.zoom(sourceID: "galleryButton", in: galleryZoom))
                        .navigationBarHidden(true)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { setupCamera() }
        .onDisappear {
            // Only cleanup when truly leaving — not when nav pushes
            guard navigationPath.isEmpty else { return }
            cleanupCamera()
        }
        .onChange(of: controller.currentPhase) { _, newPhase in
            // Stop camera when entering review — preview not needed
            if case .complete = newPhase {
                Task { await controller.stopCameraSession() }
            }
        }
        .onChange(of: cameraMode) { _, newMode in handleModeChange(newMode) }
        .fullScreenCover(isPresented: $showReactionCamera) {
            // initialSourceURL is non-nil only when entering reaction mode
            // from a stitch/reply context — the parent video the user
            // tapped Stitch on is auto-loaded as the content zone.
            ReactionCameraView(
                cameraManager: controller.cameraManager,
                onComplete: { exportedURL in
                    showReactionCamera = false
                    Task { await controller.processSelectedVideo(exportedURL) }
                },
                onCancel: { showReactionCamera = false },
                initialSourceURL: controller.recordingContext.sourceVideoURL
            )
        }
        .sheet(isPresented: $showGalleryPicker, onDismiss: {
            // Navigate AFTER sheet is fully dismissed — prevents parent recreation
            guard let url = galleryVideoURL else {
                print("📱 PICKER onDismiss: galleryVideoURL nil — no navigation")
                return
            }
            print("📱 PICKER onDismiss: pushing .galleryReview for \(url.lastPathComponent)")
            galleryEditState = VideoEditState(
                videoURL: url, videoDuration: 60.0,
                videoSize: CGSize(width: 1080, height: 1920)
            )
            navigationPath.append(.galleryReview(url))
        }) {
            FastVideoPicker { url in
                currentRecordingSource = "cameraRoll"
                galleryVideoURL = url
                showGalleryPicker = false
            }
        }
    }

    // MARK: - Video Review (recorded video)

    @ViewBuilder
    private func videoReviewView(url: URL) -> some View {
        VideoReviewView(
            initialState: VideoEditState(
                videoURL: url, videoDuration: 60.0,
                videoSize: CGSize(width: 1080, height: 1920)
            ),
            onContinueToThread: { editState in
                navigationPath.append(.threadComposer(editState))
            },
            onCancel: { onCancel() }
        )
    }

    // MARK: - Camera Interface

    private var cameraInterface: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 700

            ZStack {
                // Camera preview
                ZStack {
                    SimpleCameraPreview(controller: controller)
                    if cameraMode == .greenScreen && greenScreenActive {
                        GreenScreenPreviewView(processor: GreenScreenProcessor.shared)
                    }
                }
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { v in
                            let delta = -v.translation.height / 200
                            currentZoomFactor = min(max(lastZoomFactor + delta, 1.0), 5.0)
                            controller.setZoomFactor(currentZoomFactor)
                        }
                        .onEnded { _ in lastZoomFactor = currentZoomFactor }
                )

                // Teleprompter
                if cameraMode == .teleprompter {
                    TeleprompterView(state: teleprompterState, cameraManager: controller.cameraManager)
                }

                // Top bar
                VStack {
                    topBar(isCompact: isCompact)
                        .padding(.top, max(geo.safeAreaInsets.top, 50) + 4)
                    Spacer()
                }

                // Bottom controls
                VStack {
                    Spacer()
                    mainControls(geo, isCompact: isCompact)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar

    private func topBar(isCompact: Bool) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Exit
                Button { handleExit() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)))
                }
                .disabled(controller.currentPhase.isRecording)
                .opacity(controller.currentPhase.isRecording ? 0.5 : 1.0)

                Spacer()
                LensSwitcherView(cameraManager: controller.cameraManager)
                Spacer()

                // Torch
                Button { controller.cameraManager.toggleTorch() } label: {
                    Image(systemName: controller.cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(controller.cameraManager.isTorchOn ? .yellow : .white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)))
                }
                .disabled(controller.currentPhase.isRecording)
            }
            .padding(.horizontal, 20)

            // Mode picker (hidden while recording)
            if !controller.currentPhase.isRecording {
                modePicker.padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(CameraMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { cameraMode = mode }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon).font(.system(size: 11, weight: .medium))
                        Text(mode.rawValue).font(.system(size: 12, weight: cameraMode == mode ? .bold : .medium))
                    }
                    .foregroundColor(cameraMode == mode ? .black : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(cameraMode == mode ? Color.white : Color.white.opacity(0.15)))
                }
            }
        }
    }

    // MARK: - Main Controls

    private func mainControls(_ geo: GeometryProxy, isCompact: Bool) -> some View {
        let btnSize: CGFloat = isCompact ? 42 : 50
        let iconSize: CGFloat = isCompact ? 20 : 24

        return VStack(spacing: isCompact ? 8 : 12) {
            // Duration
            if !controller.segments.isEmpty || controller.currentPhase.isRecording {
                durationDisplay
            }

            // Flip + Torch row
            HStack(spacing: 20) {
                circleButton(icon: "camera.rotate.fill", size: 40) {
                    Task { await controller.cameraManager.switchCamera() }
                }
                .disabled(controller.currentPhase.isRecording)
                .opacity(controller.currentPhase.isRecording ? 0.5 : 1.0)

                circleButton(
                    icon: controller.cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    size: 40,
                    tint: controller.cameraManager.isTorchOn ? .yellow : .white
                ) {
                    controller.cameraManager.toggleTorch()
                }
                .disabled(controller.currentPhase.isRecording)
            }

            // Record row: Gallery / Record / Finish
            HStack(spacing: isCompact ? 28 : 40) {
                // LEFT: Gallery or Delete
                if controller.segments.isEmpty {
                    circleButton(icon: "photo.fill", size: btnSize, iconSize: iconSize) {
                        showGalleryPicker = true
                    }
                    .matchedTransitionSource(id: "galleryButton", in: galleryZoom)
                    .disabled(controller.currentPhase.isRecording)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    circleButton(icon: "arrow.uturn.backward", size: btnSize, iconSize: iconSize) {
                        controller.deleteNewestSegment()
                    }
                    .disabled(!controller.canDelete)
                    .opacity(controller.canDelete ? 1.0 : 0.3)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // CENTER: Record
                CinematicRecordingButton(
                    isRecording: Binding(
                        get: { controller.currentPhase.isRecording },
                        set: { _ in }
                    ),
                    totalDuration: controller.totalDuration + controller.currentSegmentDuration,
                    tierLimit: controller.userTierLimit,
                    onPressStart: {
                        currentRecordingSource = "inApp"
                        controller.startSegment()
                    },
                    onPressEnd: { controller.stopSegment() },
                    compactMode: isCompact
                )

                Spacer().frame(maxWidth: 24)

                // RIGHT: Finish or spacer
                if !controller.segments.isEmpty {
                    circleButton(icon: "checkmark", size: btnSize, iconSize: iconSize) {
                        Task { await controller.finishRecording() }
                    }
                    .disabled(!controller.canFinish)
                    .opacity(controller.canFinish ? 1.0 : 0.3)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Color.clear.frame(width: btnSize, height: btnSize)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.segments.count)
            .padding(.horizontal, isCompact ? 24 : 40)
            .padding(.bottom, max(isCompact ? 24 : 40, geo.safeAreaInsets.bottom + (isCompact ? 12 : 20)))
        }
    }

    // MARK: - Duration Display

    private var durationDisplay: some View {
        let current = controller.totalDuration + controller.currentSegmentDuration
        let progress = controller.userTierLimit > 0 ? current / controller.userTierLimit : 0

        return Text(fmt(current) + " / " + fmt(controller.userTierLimit))
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(progress >= 0.9 ? .red : progress >= 0.8 ? .yellow : .white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    // MARK: - Processing Interface

    private var processingInterface: some View {
        VStack(spacing: 24) {
            ProgressView().scaleEffect(1.5).tint(.white)
            Text("Processing your video...").font(.headline).foregroundColor(.white)
            ProgressView(value: 0.5)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Interface

    private func errorInterface(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50)).foregroundColor(.red)
            Text("Recording Error").font(.headline).foregroundColor(.white)
            Text(message).font(.subheadline).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            HStack(spacing: 16) {
                Button("Try Again") { controller.clearError() }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.blue).foregroundColor(.white).cornerRadius(8)

                Button("Cancel") { onCancel() }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.gray.opacity(0.3)).foregroundColor(.white).cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reusable Circle Button

    private func circleButton(
        icon: String, size: CGFloat, iconSize: CGFloat = 18,
        tint: Color = .white, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                )
        }
    }

    // MARK: - Actions

    private func handleExit() {
        if controller.currentPhase.isRecording { controller.stopSegment() }
        controller.stopRecordingTimer()

        Task { @MainActor in
            await controller.stopCameraSession()
            await restorePlaybackAudioSession()
            controller.segments.removeAll()
            controller.recordedVideoURL = nil
            controller.aiAnalysisResult = nil
            onCancel()
        }
    }

    private func handleModeChange(_ mode: CameraMode) {
        teleprompterState.stopScrolling()
        if greenScreenActive {
            GreenScreenProcessor.shared.deactivate()
            greenScreenActive = false
        }
        if mode == .reaction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showReactionCamera = true }
        }
    }

    // MARK: - Camera Lifecycle

    private func setupCamera() {
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        Task {
            await controller.startCameraSession()
            // Audio AFTER camera — prevents FigAudioSession -19224
            setupRecordingAudioSession()
        }
    }

    private func cleanupCamera() {
        Task {
            await controller.stopCameraSession()
            await restorePlaybackAudioSession()
        }
    }

    // MARK: - Audio Session

    private func setupRecordingAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio session setup failed: \(error)")
        }
    }

    private func restorePlaybackAudioSession() async {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio session restore failed: \(error)")
        }
    }

    // MARK: - Context Helpers

    private func getContextName() -> String {
        switch controller.recordingContext {
        case .newThread: return "New Thread"
        case .stitchToThread: return "Stitching"
        case .replyToVideo: return "Reply"
        case .continueThread: return "Continue"
        case .spinOffFrom: return "Spin-off"
        }
    }

    private func getContextColor() -> Color {
        switch controller.recordingContext {
        case .newThread: return .blue
        case .stitchToThread: return .green
        case .replyToVideo: return .orange
        case .continueThread: return .purple
        case .spinOffFrom: return .orange
        }
    }

    private func fmt(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

// MARK: - Fast Video Picker

struct FastVideoPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        // .compatible (not .current) so PHPicker downloads the full video
        // for iCloud-only assets. .current would hand back a small proxy
        // URL that AVAsset can't open, leaving VideoReviewView blank.
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // CRITICAL: do NOT dismiss the picker here. loadFileRepresentation
            // below is async — if we dismiss now, the SwiftUI sheet's onDismiss
            // closure fires before galleryVideoURL is set and the .galleryReview
            // navigation never happens.
            //
            // Cancel case (empty results) is the only path that dismisses
            // immediately, since there's no async work pending.

            guard let result = results.first else {
                picker.dismiss(animated: true)
                return
            }
            let provider = result.itemProvider

            let uti = UTType.movie.identifier
            if provider.hasItemConformingToTypeIdentifier(uti) {
                loadFile(from: provider, uti: uti, picker: picker)
            } else {
                let uti2 = UTType.audiovisualContent.identifier
                guard provider.hasItemConformingToTypeIdentifier(uti2) else {
                    picker.dismiss(animated: true)
                    return
                }
                loadFile(from: provider, uti: uti2, picker: picker)
            }
        }

        private func loadFile(from provider: NSItemProvider, uti: String, picker: PHPickerViewController) {
            provider.loadFileRepresentation(forTypeIdentifier: uti) { [weak self] url, error in
                guard let url, error == nil else {
                    print("📱 PICKER: Load failed — \(error?.localizedDescription ?? "no url")")
                    DispatchQueue.main.async { picker.dismiss(animated: true) }
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gallery_\(UUID().uuidString).\(url.pathExtension)")
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    print("📱 PICKER: Copied to \(dest.lastPathComponent)")
                    // Success path: call onPick on main, which sets
                    // galleryVideoURL AND flips showGalleryPicker = false.
                    // The binding flip dismisses the SwiftUI sheet — do NOT
                    // also call picker.dismiss(animated:), that goes through
                    // UIKit's modal chain and can dismiss the parent
                    // fullScreenCover too, kicking the user back to discover.
                    DispatchQueue.main.async {
                        self?.onPick(dest)
                    }
                } catch {
                    print("📱 PICKER: Copy failed — \(error)")
                    DispatchQueue.main.async { picker.dismiss(animated: true) }
                }
            }
        }
    }
}

// MARK: - Camera Preview

struct SimpleCameraPreview: UIViewRepresentable {
    @ObservedObject var controller: RecordingController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let layer = controller.cameraManager.previewLayer
        layer.removeFromSuperlayer()
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            let layer = controller.cameraManager.previewLayer
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
        uiView.layer.sublayers?
            .compactMap { $0 as? AVCaptureVideoPreviewLayer }
            .forEach { $0.removeFromSuperlayer() }
    }
}

// MARK: - Video Selection Errors

enum VideoSelectionError: LocalizedError {
    case noData, failedToLoadData, failedToSaveData, unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noData: return "No video data found"
        case .failedToLoadData: return "Failed to load video"
        case .failedToSaveData: return "Failed to save video"
        case .unsupportedFormat: return "Unsupported format"
        }
    }
}
