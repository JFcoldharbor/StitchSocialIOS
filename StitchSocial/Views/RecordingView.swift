//
//  RecordingView.swift - COMPLETE COMPILATION AND CRASH FIXES
//  StitchSocial
//
//  Fixed: Exit button crash, notification names, proper async cleanup
//

import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Navigation Destination

enum RecordingNavigationDestination: Hashable {
    case threadComposer(VideoEditState)
    
    static func == (lhs: RecordingNavigationDestination, rhs: RecordingNavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.threadComposer(let lhsState), .threadComposer(let rhsState)):
            return lhsState.draftID == rhsState.draftID
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .threadComposer(let state):
            hasher.combine(state.draftID)
        }
    }
}

struct RecordingView: View {
    @StateObject private var controller: RecordingController
    @StateObject private var permissionsManager = CameraPermissionsManager()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingSelectedVideo = false
    @State private var navigationPath: [RecordingNavigationDestination] = []
    @State private var isTorchOn = false  // Flashlight state
    @State private var currentRecordingSource: String = "inApp"  // Tracks if video is live or from camera roll
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var lastZoomFactor: CGFloat = 1.0
    @State private var dragStartY: CGFloat = 0
    
    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void
    
    init(
        recordingContext: RecordingContext,
        onVideoCreated: @escaping (CoreVideoMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._controller = StateObject(wrappedValue: RecordingController(recordingContext: recordingContext))
        self.onVideoCreated = onVideoCreated
        self.onCancel = onCancel
    }
    
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
                        // NEW FLOW: Go to review screen first
                        VideoReviewView(
                            initialState: VideoEditState(
                                videoURL: videoURL,
                                videoDuration: 60.0, // Placeholder, will be loaded in review
                                videoSize: CGSize(width: 1080, height: 1920)
                            ),
                            onContinueToThread: { editState in
                                // After review, navigate to ThreadComposer
                                navigationPath.append(.threadComposer(editState))
                            },
                            onCancel: onCancel
                        )
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
                            // FIXED: Pop nav stack FIRST, then notify parent
                            // Without this, fullScreenCover won't dismiss because
                            // NavigationStack still has .threadComposer in its path
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
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            cleanupCamera()
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            if newValue != nil {
                handlePhotoSelection()
            }
        }
    }
    
    // MARK: - Camera Interface
    
    private var cameraInterface: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 700
            
            ZStack {
                // Camera preview with slide-to-zoom (drag up = zoom in, drag down = zoom out)
                SimpleCameraPreview(controller: controller)
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                // Negative translation = dragging up = zoom in
                                let dragDelta = -value.translation.height / 200
                                let newZoom = lastZoomFactor + dragDelta
                                currentZoomFactor = min(max(newZoom, 1.0), 5.0)
                                controller.setZoomFactor(currentZoomFactor)
                            }
                            .onEnded { _ in
                                lastZoomFactor = currentZoomFactor
                            }
                    )
                
                // Top Bar - use safeAreaInsets from geometry but ensure minimum offset for notch
                VStack {
                    topBar(isCompact: isCompact)
                        .padding(.top, max(geometry.safeAreaInsets.top, 50) + 4)
                    Spacer()
                }
                
                // Main Controls (Bottom)
                VStack {
                    Spacer()
                    mainControls(geometry, isCompact: isCompact)
                }
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Top Bar with Exit Button
    
    private func topBar(isCompact: Bool) -> some View {
        HStack {
            // Exit Button (Left)
            Button {
                handleExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .disabled(controller.currentPhase.isRecording)
            .opacity(controller.currentPhase.isRecording ? 0.5 : 1.0)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Processing Interface
    
    private var processingInterface: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Processing your video...")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Processing video content...")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
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
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Recording Error")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            HStack(spacing: 16) {
                Button("Try Again") {
                    controller.clearError()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button("Cancel") {
                    onCancel()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Main Controls
    
    private func mainControls(_ geometry: GeometryProxy, isCompact: Bool) -> some View {
        let sideBtnSize: CGFloat = isCompact ? 42 : 50
        let sideBtnIcon: CGFloat = isCompact ? 20 : 24
        
        return VStack(spacing: isCompact ? 8 : 12) {
            // Duration display
            if !controller.segments.isEmpty || controller.currentPhase.isRecording {
                durationDisplay
            }
            
            // Flip + Flashlight row (above record button)
            HStack(spacing: 20) {
                Button {
                    Task {
                        await controller.cameraManager.switchCamera()
                    }
                } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .disabled(controller.currentPhase.isRecording)
                .opacity(controller.currentPhase.isRecording ? 0.5 : 1.0)
                
                Button {
                    isTorchOn.toggle()
                } label: {
                    Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .disabled(controller.currentPhase.isRecording)
                .opacity(controller.currentPhase.isRecording ? 0.5 : 1.0)
            }
            
            HStack(spacing: isCompact ? 28 : 40) {
                // LEFT BUTTON - Dynamic (Gallery or Delete)
                if controller.segments.isEmpty {
                    // IDLE STATE: Show Gallery
                    PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: sideBtnIcon, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: sideBtnSize, height: sideBtnSize)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(controller.currentPhase.isRecording || isProcessingSelectedVideo)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // RECORDING STATE: Show Delete
                    Button(action: {
                        controller.deleteNewestSegment()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: sideBtnIcon, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: sideBtnSize, height: sideBtnSize)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(!controller.canDelete)
                    .opacity(controller.canDelete ? 1.0 : 0.3)
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // CENTER: Record Button (Always Present)
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
                    onPressEnd: {
                        controller.stopSegment()
                    },
                    compactMode: isCompact
                )
                
                Spacer().frame(maxWidth: 24)
                
                // RIGHT BUTTON - Dynamic (Empty or Finished)
                if !controller.segments.isEmpty {
                    // RECORDING STATE: Show Finished
                    Button(action: {
                        Task {
                            await controller.finishRecording()
                        }
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: sideBtnIcon, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: sideBtnSize, height: sideBtnSize)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(!controller.canFinish)
                    .opacity(controller.canFinish ? 1.0 : 0.3)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Empty spacer to maintain layout
                    Color.clear
                        .frame(width: sideBtnSize, height: sideBtnSize)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.segments.count)
            .padding(.horizontal, isCompact ? 24 : 40)
            .padding(.bottom, max(isCompact ? 24 : 40, geometry.safeAreaInsets.bottom + (isCompact ? 12 : 20)))
        }
    }
    
    // MARK: - Duration Display
    
    private var durationDisplay: some View {
        let currentDuration = controller.totalDuration + controller.currentSegmentDuration
        let progress = controller.userTierLimit > 0 ? currentDuration / controller.userTierLimit : 0
        
        return Text(formatDuration(currentDuration) + " / " + formatDuration(controller.userTierLimit))
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(progress >= 0.9 ? .red : (progress >= 0.8 ? .yellow : .white))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.5))
            )
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - UI Components
    
    private var contextBadge: some View {
        Text(getContextName())
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().stroke(getContextColor(), lineWidth: 1)
                    )
            )
    }
    
    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(controller.currentPhase.isRecording ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: controller.currentPhase.isRecording)
            
            Text("REC")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.8))
        )
    }
    
    // MARK: - Actions
    
    private func handleExit() {
        // Stop recording first if active
        if controller.currentPhase.isRecording {
            controller.stopSegment()
        }
        
        // Use controller's method to stop timer
        controller.stopRecordingTimer()
        
        // Do camera cleanup
        Task { @MainActor in
            await controller.stopCameraSession()
            
            // Restore audio session before dismissal
            await restorePlaybackAudioSession()
            
            // Clear segments and references
            controller.segments.removeAll()
            controller.recordedVideoURL = nil
            controller.aiAnalysisResult = nil
            
            // Dismiss
            onCancel()
        }
    }
    
    // MARK: - Photo Selection Handling
    
    private func handlePhotoSelection() {
        guard let selectedItem = selectedPhotoItem else { return }
        
        isProcessingSelectedVideo = true
        currentRecordingSource = "cameraRoll"  // Mark as camera roll upload
        
        selectedItem.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data?):
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("selected_video.mov")
                    
                    do {
                        try data.write(to: tempURL)
                        
                        Task {
                            await self.controller.processSelectedVideo(tempURL)
                        }
                    } catch {
                        self.handleVideoSelectionError(.failedToSaveData)
                    }
                    
                case .success(nil):
                    self.handleVideoSelectionError(.noData)
                    
                case .failure(_):
                    self.handleVideoSelectionError(.failedToLoadData)
                }
            }
        }
    }
    
    private func handleVideoSelectionError(_ error: VideoSelectionError) {
        isProcessingSelectedVideo = false
        selectedPhotoItem = nil
        
        // Show error alert
        controller.currentPhase = .error(error.localizedDescription)
    }
    
    // MARK: - Context Helpers
    
    private func getContextName() -> String {
        switch controller.recordingContext {
        case .newThread:
            return "New Thread"
        case .stitchToThread:
            return "Stitching"
        case .replyToVideo:
            return "Reply"
        case .continueThread:
            return "Continue"
        case .spinOffFrom:
            return "Spin-off"
        }
    }
    
    private func getContextColor() -> Color {
        switch controller.recordingContext {
        case .newThread:
            return .blue
        case .stitchToThread:
            return .green
        case .replyToVideo:
            return .orange
        case .continueThread:
            return .purple
        case .spinOffFrom:
            return .orange
        }
    }
    
    // MARK: - Camera Lifecycle
    
    private func setupCamera() {
        // Kill feed videos before starting camera
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        
        // Set up recording audio session
        setupRecordingAudioSession()
        
        Task {
            await controller.startCameraSession()
        }
    }
    
    private func cleanupCamera() {
        Task {
            await controller.stopCameraSession()
            
            // CRITICAL: Restore playback audio session
            await restorePlaybackAudioSession()
        }
    }
    
    // MARK: - Audio Session Management
    
    private func setupRecordingAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup recording audio session: \(error)")
        }
    }
    
    private func restorePlaybackAudioSession() async {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to restore playback audio session: \(error)")
        }
    }
    
    // MARK: - Review Flow Helpers
}

// MARK: - Simple Camera Preview Component

struct SimpleCameraPreview: UIViewRepresentable {
    @ObservedObject var controller: RecordingController
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let previewLayer = controller.cameraManager.previewLayer
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Video Selection Error Types

enum VideoSelectionError: LocalizedError {
    case noData
    case failedToLoadData
    case failedToSaveData
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .noData:
            return "No video data found"
        case .failedToLoadData:
            return "Failed to load video from gallery"
        case .failedToSaveData:
            return "Failed to save video data"
        case .unsupportedFormat:
            return "Unsupported video format"
        }
    }
}
