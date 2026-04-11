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

// MARK: - Reaction State

@MainActor
class ReactionState: ObservableObject {
    @Published var layout: ReactionLayout = .split5050
    @Published var isSwapped = false           // false = camera top, content bottom
    @Published var isRecording = false
    @Published var gsActive = false            // green screen on camera zone
    @Published var contentZone: ZoneContent = .solidColor(.black)
    @Published var showLayoutPicker = false
    @Published var showContentPicker = false
    @Published var errorMessage: String?

    let cameraManager: CinematicCameraManager

    init(cameraManager: CinematicCameraManager) {
        self.cameraManager = cameraManager
    }

    var cameraIsTop: Bool { !isSwapped }

    func startRecording() {
        guard cameraManager.isSessionRunning else {
            errorMessage = "Camera not ready"
            return
        }
        if gsActive { GreenScreenProcessor.shared.activate() }
        cameraManager.startRecording { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                if url != nil {
                    self.isRecording = true
                    print("🎬 REACTION: Recording started")
                } else {
                    self.errorMessage = "Failed to start recording"
                }
            }
        }
    }

    func stopRecording() {
        cameraManager.stopRecording()
        if gsActive { GreenScreenProcessor.shared.deactivate() }
        isRecording = false
        print("🎬 REACTION: Recording stopped")
    }

    func loadVideo(url: URL) {
        contentZone = .importedVideo(url)
    }

    func loadImage(_ image: UIImage) {
        contentZone = .importedImage(image)
    }

    func cleanup() {
        stopRecording()
        GreenScreenProcessor.shared.cleanup()
        print("🎬 REACTION: Cleanup")
    }
}

// MARK: - ReactionCameraView

struct ReactionCameraView: View {
    @StateObject private var state: ReactionState
    @ObservedObject var cameraManager: CinematicCameraManager

    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    @State private var videoPicker: PhotosPickerItem?
    @State private var imagePicker: PhotosPickerItem?

    init(
        cameraManager: CinematicCameraManager,
        onComplete: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _state = StateObject(wrappedValue: ReactionState(cameraManager: cameraManager))
        self.cameraManager = cameraManager
        self.onComplete = onComplete
        self.onCancel = onCancel
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
        ZStack {
            if state.gsActive {
                // Green screen composite via Metal
                GreenScreenPreviewView(processor: GreenScreenProcessor.shared)
                    .frame(width: size.width, height: size.height)
            } else {
                // Normal camera preview
                ReactionCameraPreviewView(cameraManager: cameraManager)
                    .frame(width: size.width, height: size.height)
            }

            // Camera zone controls (bottom-left)
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    // Flip camera
                    Button {
                        Task { await cameraManager.switchCamera() }
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }

                    // Green screen toggle
                    Button {
                        state.gsActive.toggle()
                        state.gsActive
                            ? GreenScreenProcessor.shared.activate()
                            : GreenScreenProcessor.shared.deactivate()
                    } label: {
                        Image(systemName: state.gsActive ? "person.crop.rectangle.fill" : "person.crop.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(state.gsActive ? .green : .white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(width: size.width, height: size.height)
        }
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

            case .importedVideo(let url):
                ContentVideoPlayer(url: url)
                    .frame(width: size.width, height: size.height)
                    .clipped()

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

            // Change content button
            if case .solidColor = state.contentZone {} else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { state.showContentPicker = true } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .padding(.trailing, 8).padding(.bottom, 8)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
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
            .disabled(state.isRecording)

            // Record button
            Button {
                state.isRecording ? state.stopRecording() : state.startRecording()
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

            // Placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
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
        print("🎬 REACTION PICKER: Loading — \(item.supportedContentTypes.map(\.identifier))")
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
                            print("🎬 REACTION PICKER: Video → \(dest.lastPathComponent) (\(data.count / 1024)KB)")
                            state.loadVideo(url: dest)
                        } catch {
                            print("🎬 REACTION PICKER ❌ Write failed — \(error)")
                            state.errorMessage = "Failed to load video"
                        }
                    } else {
                        guard let img = UIImage(data: data) else {
                            state.errorMessage = "Could not decode image"; return
                        }
                        print("🎬 REACTION PICKER: Image → \(img.size)")
                        state.loadImage(img)
                    }
                case .success(nil):
                    print("🎬 REACTION PICKER ❌ Data nil")
                    state.errorMessage = "Could not load content"
                case .failure(let e):
                    print("🎬 REACTION PICKER ❌ Failed — \(e)")
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
