//
//  RecordingView.swift - COMPLETE COMPILATION AND CRASH FIXES
//  StitchSocial
//
//  Fixed: Exit button crash, notification names, proper async cleanup
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
                // Camera preview
                SimpleCameraPreview(controller: controller)
                    .clipped()
                
                // Top Bar
                VStack {
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top + 10)
                    Spacer()
                }
                
                // Main Controls (Bottom)
                VStack {
                    Spacer()
                    mainControls(geometry)
                }
            }
        }
    }
    
    // MARK: - Top Bar with Exit Button
    
    private var topBar: some View {
        HStack {
            // Exit Button
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
            
            // Context Badge (Center)
            contextBadge
            
            Spacer()
            
            // Recording Indicator (Right)
            if controller.currentPhase.isRecording {
                recordingIndicator
            } else {
                // Placeholder to maintain balance
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 60, height: 32)
            }
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
    
    private func mainControls(_ geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Gallery Button
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
            .disabled(controller.currentPhase.isRecording || isProcessingSelectedVideo)
            
            Spacer()
            
            // Recording Button
            CinematicRecordingButton(
                isRecording: Binding(
                    get: { controller.currentPhase.isRecording },
                    set: { _ in }
                ),
                videoCoordinator: .constant(nil),
                onButtonTap: {
                    handleRecordingButtonTap()
                }
            )
            
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
        .padding(.bottom, max(40, geometry.safeAreaInsets.bottom + 20))
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
        // FIXED: Proper cleanup to prevent retain cycles and crashes
        
        // Stop recording first if active
        if controller.currentPhase.isRecording {
            controller.stopRecording()
        }
        
        // Use controller's method to stop timer (since timer is private)
        controller.stopRecordingTimer()
        
        // Kill all background activity and videos before exiting
        BackgroundActivityManager.shared.killAllBackgroundActivity(reason: "Recording exit")
        
        // Send additional kill notifications for immediate effect
        NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
        
        // Do camera cleanup without waiting
        Task { @MainActor in
            await controller.stopCameraSession()
            
            // CRITICAL: Restore audio session before dismissal
            await restorePlaybackAudioSession()
            
            // Ensure all strong references are cleared
            controller.recordedVideoURL = nil
            controller.aiAnalysisResult = nil
            
            // Safe dismissal after cleanup
            onCancel()
        }
    }
    
    private func handleRecordingButtonTap() {
        if controller.currentPhase == .ready {
            controller.startRecording()
        } else if controller.currentPhase == .recording {
            controller.stopRecording()
        }
    }
    
    // MARK: - Photo Selection Handling
    
    private func handlePhotoSelection() {
        guard let selectedItem = selectedPhotoItem else { return }
        
        isProcessingSelectedVideo = true
        
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
        }
    }
    
    // MARK: - Camera Lifecycle
    
    private func setupCamera() {
        // FIXED: Use the correct notification name that exists in the project
        NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
        
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

// MARK: - Notification Extension (FIXED - Provide both names for compatibility)

extension Notification.Name {
    static let MyRealkillAllVideoPlayers = Notification.Name("killAllVideoPlayers")
    static let killAllVideoPlayers = Notification.Name("killAllVideoPlayers")  // For ContextualVideoOverlay compatibility
}
