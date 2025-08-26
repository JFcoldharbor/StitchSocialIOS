//
//  RecordingView.swift
//  CleanBeta
//
//  Layer 8: Views - Instagram/TikTok Style Recording Interface
//  Standard social media camera layout with bottom controls
//

import SwiftUI
import AVFoundation
import PhotosUI

struct RecordingView: View {
    @StateObject private var controller: RecordingController
    @StateObject private var permissionsManager = CameraPermissionsManager()
    @State private var selectedPhotoItem: PhotosPickerItem?
    
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
        .onChange(of: selectedPhotoItem) { item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    await handleSelectedVideo(data)
                }
            }
        }
    }
    
    // MARK: - Camera Interface
    
    private var cameraInterface: some View {
        ZStack {
            // Full screen camera preview - FIXED: Use ProfessionalCameraPreview
            ProfessionalCameraPreview(controller: controller)
                .ignoresSafeArea()
            
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
                    PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    
                    Spacer()
                    
                    // Center: Recording button
                    CinematicRecordingButton(controller: controller)
                    
                    Spacer()
                    
                    // Right: Camera flip - FIXED
                    Button {
                        Task {
                            await controller.cameraManager.switchCamera()
                        }
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(.horizontal, 50)
                .position(x: geometry.size.width / 2, y: geometry.size.height - 80)
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
                .scaleEffect(1.2)
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
    
    // MARK: - Setup and Cleanup
    
    private func setupCamera() {
        // Stop all background activity for camera priority
        stopBackgroundActivity()
        
        if permissionsManager.canRecord {
            Task {
                await controller.startCameraSession()
            }
        }
    }
    
    private func cleanupCamera() {
        Task {
            await controller.stopCameraSession()
        }
        
        // Resume background activity when leaving
        resumeBackgroundActivity()
    }
    
    // MARK: - Background Activity Management - FIXED
    
    private func stopBackgroundActivity() {
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
    
    // MARK: - Gallery Video Handling - FIXED
    
    private func handleSelectedVideo(_ data: Data) async {
        // Handle selected video from gallery
        do {
            let tempURL = URL.temporaryDirectory.appendingPathComponent("selected_video.mp4")
            try data.write(to: tempURL)
            
            // Process selected video through the same pipeline
            controller.recordedVideoURL = tempURL
            
            print("📱 RECORDING: Selected video from gallery")
        } catch {
            print("❌ RECORDING: Failed to handle selected video: \(error)")
        }
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

// MARK: - Professional Camera Preview (Fixed Implementation)

struct ProfessionalCameraPreview: UIViewRepresentable {
    @ObservedObject var controller: RecordingController
    
    func makeUIView(context: Context) -> ProfessionalPreviewUIView {
        let view = ProfessionalPreviewUIView()
        
        let previewLayer = controller.cameraManager.previewLayer
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinch))
        
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
    
    class Coordinator: NSObject {
        let parent: ProfessionalCameraPreview
        private var initialZoom: CGFloat = 1.0
        
        init(_ parent: ProfessionalCameraPreview) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            Task { @MainActor in
                await parent.controller.cameraManager.focusAt(point: point, in: gesture.view!)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            Task { @MainActor in
                if gesture.state == .began {
                    initialZoom = parent.controller.cameraManager.currentZoomFactor
                } else if gesture.state == .changed {
                    let newZoom = initialZoom * gesture.scale
                    await parent.controller.cameraManager.setZoom(newZoom)
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
}
