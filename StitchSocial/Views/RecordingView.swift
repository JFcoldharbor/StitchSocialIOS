//
//  RecordingView.swift
//  CleanBeta
//
//  Layer 8: Views - Instagram/TikTok Style Recording Interface
//  COMPLETE FIX: Background video stopping + Camera flip + Image picker
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
        ZStack {
            // Full screen camera preview
            ProfessionalCameraPreview(controller: controller)
                .ignoresSafeArea()
            
            // Processing overlay for selected video
            if isProcessingSelectedVideo {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Processing selected video...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // Top overlay
            VStack {
                HStack {
                    contextBadge
                    
                    Spacer()
                    
                    if controller.currentPhase.isRecording {
                        recordingIndicator
                    }
                    
                    Spacer()
                    
                    closeButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
            }
            
            // Bottom controls - absolute positioning at screen bottom
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: 0) {
                    // Left: Gallery/Image picker - FIXED
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.stack.fill")
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
                    .disabled(controller.currentPhase.isRecording || isProcessingSelectedVideo)
                    
                    Spacer()
                    
                    // Center: Recording button
                    CinematicRecordingButton(controller: controller)
                        .disabled(isProcessingSelectedVideo)
                    
                    Spacer()
                    
                    // Right: Camera flip - FIXED with proper async handling
                    Button {
                        flipCamera()
                    } label: {
                        VStack(spacing: 4) {
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
                .position(x: geometry.size.width / 2, y: geometry.size.height - 100)
            }
        }
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
                .scaleEffect(controller.currentPhase.isRecording ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: controller.currentPhase.isRecording)
            
            Text("REC")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
    }
    
    private var closeButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
        }
    }
    
    // MARK: - Processing Interface
    
    private var processingInterface: some View {
        ZStack {
            // Background gradient
            backgroundGradient
            
            // Content
            processingContent
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.black, StitchColors.primary.opacity(0.2), Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var processingContent: some View {
        VStack(spacing: 30) {
            // AI Processing animation
            processingAnimation
            
            VStack(spacing: 12) {
                Text("AI is analyzing your video...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Processing your video...")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var processingAnimation: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(StitchColors.primary.opacity(0.6), lineWidth: 2)
                    .frame(width: 80 + CGFloat(index * 30), height: 80 + CGFloat(index * 30))
                    .scaleEffect(1.0)
                    .animation(
                        .easeInOut(duration: 1.5 + Double(index) * 0.3)
                        .repeatForever(autoreverses: true),
                        value: controller.currentPhase
                    )
            }
            
            Circle()
                .fill(StitchColors.primary)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.title)
                        .foregroundColor(.white)
                )
        }
    }
    
    private func errorInterface(_ message: String) -> some View {
        ZStack {
            StitchColors.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Recording Error")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button("Try Again") {
                    controller.clearError()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(StitchColors.primary)
                )
                
                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline)
                .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Camera Controls - FIXED
    
    private func flipCamera() {
        // Provide immediate visual feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        Task {
            print("🔄 RECORDING VIEW: Flipping camera...")
            
            // Use the cinematic camera manager if available, otherwise fall back to streamlined
            if let cinematicManager = controller.cameraManager as? CinematicCameraManager {
                await cinematicManager.switchCamera()
                print("🔄 RECORDING VIEW: Used CinematicCameraManager to flip camera")
            } else {
                await controller.cameraManager.switchCamera()
                print("🔄 RECORDING VIEW: Used StreamlinedCameraManager to flip camera")
            }
        }
    }
    
    // MARK: - Photo Selection Handling - FIXED
    
    private func handlePhotoSelection() {
        guard let selectedItem = selectedPhotoItem else { return }
        
        isProcessingSelectedVideo = true
        print("📱 RECORDING VIEW: Processing selected video from gallery...")
        
        Task {
            do {
                // Load the video data
                guard let videoData = try await selectedItem.loadTransferable(type: Data.self) else {
                    throw VideoSelectionError.failedToLoadData
                }
                
                // Create temporary file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("selected_video_\(UUID().uuidString).mov")
                
                // Write data to temporary file
                try videoData.write(to: tempURL)
                
                // Validate it's a video file
                let asset = AVAsset(url: tempURL)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                
                guard !tracks.isEmpty else {
                    throw VideoSelectionError.notAVideoFile
                }
                
                // Get duration to validate
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                
                // Check duration limits (e.g., 30 seconds max)
                guard durationSeconds <= 30.0 else {
                    throw VideoSelectionError.videoTooLong
                }
                
                print("📱 RECORDING VIEW: Selected video validated - Duration: \(String(format: "%.1fs", durationSeconds))")
                
                // Process the selected video through the recording pipeline
                await MainActor.run {
                    controller.recordedVideoURL = tempURL
                    controller.currentPhase = .aiProcessing
                    controller.recordingPhase = .aiProcessing
                    isProcessingSelectedVideo = false
                    selectedPhotoItem = nil
                    
                    print("📱 RECORDING VIEW: Selected video sent to processing pipeline")
                }
                
            } catch {
                await MainActor.run {
                    isProcessingSelectedVideo = false
                    selectedPhotoItem = nil
                    
                    // Show error to user
                    let errorMessage = (error as? VideoSelectionError)?.localizedDescription ??
                                     "Failed to process selected video"
                    controller.currentPhase = .error(errorMessage)
                    
                    print("❌ RECORDING VIEW: Video selection failed - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Setup and Cleanup
    
    private func setupCamera() {
        // Stop all background activity for camera priority - FIXED
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
    
    // MARK: - Background Activity Management - COMPLETE FIX
    
    private func stopBackgroundActivity() {
        // CRITICAL FIX: Stop all background video players via notifications
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

// MARK: - Professional Camera Preview (Enhanced)

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
                print("📷 PREVIEW: Focus set at \(point)")
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            Task { @MainActor in
                switch gesture.state {
                case .began:
                    initialZoom = parent.controller.cameraManager.currentZoomFactor
                    
                case .changed:
                    let newZoom = initialZoom * gesture.scale
                    await parent.controller.cameraManager.setZoom(newZoom)
                    
                case .ended, .cancelled:
                    print("📷 PREVIEW: Zoom gesture ended at \(parent.controller.cameraManager.currentZoomFactor)x")
                    
                default:
                    break
                }
            }
        }
        
        private func showFocusIndicator(at point: CGPoint, in view: UIView) {
            // Remove any existing focus indicators
            view.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
            
            // Create focus indicator
            let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
            focusView.center = point
            focusView.tag = 999
            focusView.layer.borderColor = UIColor.white.cgColor
            focusView.layer.borderWidth = 2
            focusView.layer.cornerRadius = 40
            focusView.backgroundColor = UIColor.clear
            focusView.alpha = 0
            
            view.addSubview(focusView)
            
            // Animate focus indicator
            UIView.animate(withDuration: 0.2, animations: {
                focusView.alpha = 1
                focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                    focusView.alpha = 0
                    focusView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }) { _ in
                    focusView.removeFromSuperview()
                }
            }
        }
    }
}

class ProfessionalPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Background Activity Notifications

extension Notification.Name {
    static let pauseBackgroundRefresh = Notification.Name("pauseBackgroundRefresh")
    static let resumeBackgroundRefresh = Notification.Name("resumeBackgroundRefresh")
    static let pauseLocationServices = Notification.Name("pauseLocationServices")
    static let resumeLocationServices = Notification.Name("resumeLocationServices")
    static let killAllVideoPlayers = Notification.Name("killAllVideoPlayers") // NEW
}
