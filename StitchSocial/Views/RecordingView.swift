//
//  RecordingView.swift
//  StitchSocial
//
//  Layer 8: Views - Instagram/TikTok Style Recording Interface
//  COMPLETE FIX: Background video stopping + Camera flip + Image picker + Compilation errors fixed
//

import SwiftUI
import AVFoundation
import PhotosUI

struct RecordingView: View {
    @StateObject private var controller: RecordingController
    @StateObject private var permissionsManager = CameraPermissionsManager()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingSelectedVideo = false
    
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
        ZStack {
            Color.black.ignoresSafeArea()
            
            switch controller.currentPhase {
            case .ready, .recording, .stopping:
                cameraInterface
                
            case .aiProcessing:
                processingInterface
                
            case .complete:
                if let videoURL = controller.recordedVideoURL {
                    ThreadComposer(
                        recordedVideoURL: videoURL,
                        recordingContext: controller.recordingContext,
                        aiResult: controller.aiAnalysisResult,
                        onVideoCreated: onVideoCreated,
                        onCancel: onCancel
                    )
                }
                
            case .error(let message):
                errorInterface(message)
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
            ZStack {
                // Camera Preview
                ProfessionalCameraPreview(controller: controller)
                    .clipped()
                
                // Context Badge (Top Center)
                VStack {
                    contextBadge
                        .padding(.top, 60)
                    Spacer()
                }
                
                // Recording Indicator (Top Right)
                if controller.currentPhase.isRecording {
                    VStack {
                        HStack {
                            Spacer()
                            recordingIndicator
                                .padding(.top, 60)
                                .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                }
                
                // Main Controls (Bottom)
                VStack {
                    Spacer()
                    mainControls(geometry)
                }
            }
        }
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
    
    private func mainControls(_ geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Gallery Button
            Button {
                // Trigger photo picker
            } label: {
                PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("Gallery")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
            .disabled(controller.currentPhase.isRecording || isProcessingSelectedVideo)
            
            Spacer()
            
            // Record Button
            Button {
                if controller.currentPhase == .ready {
                    controller.startRecording()
                } else if controller.currentPhase == .recording {
                    controller.stopRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(controller.currentPhase.isRecording ? Color.red : Color.red)
                        .frame(width: controller.currentPhase.isRecording ? 40 : 70, height: controller.currentPhase.isRecording ? 40 : 70)
                        .cornerRadius(controller.currentPhase.isRecording ? 8 : 35)
                        .animation(.easeInOut(duration: 0.2), value: controller.currentPhase.isRecording)
                }
            }
            .disabled(!controller.currentPhase.canStartRecording && !controller.currentPhase.isRecording)
            
            Spacer()
            
            // Camera Flip Button
            Button {
                Task {
                    await controller.cameraManager.switchCamera()
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Flip")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
            .disabled(controller.currentPhase.isRecording || isProcessingSelectedVideo)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
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
    
    // MARK: - Photo Selection Handling
    
    private func handlePhotoSelection() {
        guard let selectedItem = selectedPhotoItem else { return }
        
        isProcessingSelectedVideo = true
        
        selectedItem.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data?):
                    // Save to temporary file and process
                    let tempURL = URL.temporaryDirectory.appendingPathComponent("selected_video.mov")
                    
                    do {
                        try data.write(to: tempURL)
                        
                        // Validate video
                        Task {
                            await validateAndProcessSelectedVideo(tempURL)
                        }
                        
                    } catch {
                        handleVideoSelectionError(.failedToLoadData)
                    }
                    
                case .success(nil):
                    handleVideoSelectionError(.failedToLoadData)
                    
                case .failure:
                    handleVideoSelectionError(.notAVideoFile)
                }
                
                selectedPhotoItem = nil
                isProcessingSelectedVideo = false
            }
        }
    }
    
    private func validateAndProcessSelectedVideo(_ url: URL) async {
        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // Check duration (max 30 seconds)
            guard durationSeconds <= 30 else {
                handleVideoSelectionError(.videoTooLong)
                return
            }
            
            // Check if it has video tracks
            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { track in
                track.mediaType == .video
            }
            
            guard !videoTracks.isEmpty else {
                handleVideoSelectionError(.notAVideoFile)
                return
            }
            
            // Process the selected video
            await controller.processSelectedVideo(url)
            
        } catch {
            handleVideoSelectionError(.unsupportedFormat)
        }
    }
    
    private func handleVideoSelectionError(_ error: VideoSelectionError) {
        let errorMessage = (error as? VideoSelectionError)?.localizedDescription ??
                          "Failed to process selected video"
        controller.currentPhase = .error(errorMessage)
        
        print("❌ RECORDING VIEW: Video selection failed - \(error.localizedDescription)")
    }
    
    // MARK: - Setup and Cleanup
    
    private func setupCamera() {
        // Stop all background activity for camera priority
        stopBackgroundActivity()
        
        if permissionsManager.canRecord {
            Task {
                await controller.startCameraSession()
                print("📷 RECORDING VIEW: Camera session started")
            }
        } else {
            print("❌ RECORDING VIEW: Camera permissions not granted")
        }
    }
    
    private func cleanupCamera() {
        Task {
            await controller.stopCameraSession()
            print("📷 RECORDING VIEW: Camera session stopped")
        }
        
        // Resume background activity when leaving
        resumeBackgroundActivity()
    }
    
    // MARK: - Background Activity Management
    
    private func stopBackgroundActivity() {
        // Stop all background video players via notifications
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        print("🎬 RECORDING: Sent signal to stop all background video players")
        
        // Disable auto-refresh timers
        NotificationCenter.default.post(name: .pauseBackgroundRefresh, object: nil)
        
        // Reduce animation frame rates
        UIView.setAnimationsEnabled(false)
        
        // Stop location services if not critical
        NotificationCenter.default.post(name: .pauseLocationServices, object: nil)
        
        // Suspend non-critical network requests
        URLSession.shared.configuration.timeoutIntervalForRequest = 5.0
        
        print("📱 RECORDING: Background activity paused for camera priority")
    }
    
    private func resumeBackgroundActivity() {
        // Re-enable auto-refresh timers
        NotificationCenter.default.post(name: .resumeBackgroundRefresh, object: nil)
        
        // Restore animation frame rates
        UIView.setAnimationsEnabled(true)
        
        // Resume location services
        NotificationCenter.default.post(name: .resumeLocationServices, object: nil)
        
        // Restore network timeouts
        URLSession.shared.configuration.timeoutIntervalForRequest = 30.0
        
        print("📱 RECORDING: Background activity resumed")
    }
    
    // MARK: - Context Helpers
    
    private func getContextName() -> String {
        switch controller.recordingContext {
        case .newThread: return "Thread"
        case .stitchToThread: return "Stitch"
        case .replyToVideo: return "Reply"
        case .continueThread: return "Continue"
        }
    }
    
    private func getContextColor() -> Color {
        switch controller.recordingContext {
        case .newThread: return StitchColors.primary
        case .stitchToThread: return .orange
        case .replyToVideo: return .blue
        case .continueThread: return .green
        }
    }
}

// MARK: - Video Selection Error Handling

enum VideoSelectionError: LocalizedError {
    case failedToLoadData
    case notAVideoFile
    case videoTooLong
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .failedToLoadData:
            return "Failed to load selected video"
        case .notAVideoFile:
            return "Selected file is not a valid video"
        case .videoTooLong:
            return "Video is too long (max 30 seconds)"
        case .unsupportedFormat:
            return "Video format not supported"
        }
    }
}

// MARK: - Professional Camera Preview

struct ProfessionalCameraPreview: UIViewRepresentable {
    @ObservedObject var controller: RecordingController
    
    func makeUIView(context: Context) -> ProfessionalPreviewUIView {
        let view = ProfessionalPreviewUIView()
        
        let previewLayer = controller.cameraManager.previewLayer
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        
        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinch))
        
        // Allow simultaneous gestures
        tapGesture.delegate = context.coordinator
        pinchGesture.delegate = context.coordinator
        
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: ProfessionalPreviewUIView, context: Context) {
        DispatchQueue.main.async {
            uiView.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: ProfessionalCameraPreview
        private var initialZoom: CGFloat = 1.0
        
        init(_ parent: ProfessionalCameraPreview) {
            self.parent = parent
        }
        
        // Allow simultaneous gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            
            let point = gesture.location(in: gesture.view)
            
            // Visual feedback for tap
            if let view = gesture.view {
                showFocusIndicator(at: point, in: view)
            }
            
            Task { @MainActor in
                await parent.controller.cameraManager.focusAt(point: point, in: gesture.view!)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialZoom = parent.controller.cameraManager.currentZoomFactor
            case .changed:
                let newZoom = initialZoom * gesture.scale
                Task { @MainActor in
                    await parent.controller.cameraManager.setZoom(newZoom)
                }
            default:
                break
            }
        }
        
        private func showFocusIndicator(at point: CGPoint, in view: UIView) {
            // Add focus indicator animation
            let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
            focusView.center = point
            focusView.backgroundColor = UIColor.clear
            focusView.layer.borderColor = UIColor.yellow.cgColor
            focusView.layer.borderWidth = 2
            focusView.layer.cornerRadius = 40
            
            view.addSubview(focusView)
            
            UIView.animate(withDuration: 0.3, animations: {
                focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                UIView.animate(withDuration: 0.5, animations: {
                    focusView.alpha = 0
                }) { _ in
                    focusView.removeFromSuperview()
                }
            }
        }
    }
}

// MARK: - Professional Preview UIView

class ProfessionalPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let killAllVideoPlayers = Notification.Name("killAllVideoPlayers")
    static let pauseBackgroundRefresh = Notification.Name("pauseBackgroundRefresh")
    static let resumeBackgroundRefresh = Notification.Name("resumeBackgroundRefresh")
    static let pauseLocationServices = Notification.Name("pauseLocationServices")
    static let resumeLocationServices = Notification.Name("resumeLocationServices")
}
