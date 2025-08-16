//
//  RecordingView.swift - Updated with VideoCoordinator Progress Display
//  Shows detailed progress during post-processing workflow
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @StateObject private var controller: RecordingController
    @StateObject private var permissionsManager = CameraPermissionsManager()
    
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
            // Background
            Color.black.ignoresSafeArea()
            
            // Main content
            recordingContent
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🔍 DEBUG: RecordingView appeared")
            print("🔍 DEBUG: Permissions manager can record: \(permissionsManager.canRecord)")
            permissionsManager.checkPermissionStatus()
            
            // Start camera immediately if permissions already granted
            if permissionsManager.canRecord {
                Task {
                    await controller.startCameraSession()
                }
            }
        }
        .onDisappear {
            // Camera cleanup handled by controller
            Task {
                await controller.stopCameraSession()
            }
        }
    }
    
    // MARK: - Recording Content
    
    private var recordingContent: some View {
        Group {
            switch controller.currentPhase {
            case .ready, .recording, .stopping:
                cameraView
                
            case .aiProcessing:
                // UPDATED: Show VideoCoordinator progress instead of simple AI processing
                videoProcessingView
                
            case .complete:
                metadataView
                
            case .error(let message):
                ErrorView(message: message) {
                    controller.clearError()
                }
            }
        }
    }
    
    // MARK: - Camera View
    
    private var cameraView: some View {
        ZStack {
            // Camera preview
            CameraPreview(controller: controller)
                .ignoresSafeArea(.all)
            
            // Camera controls overlay
            VStack {
                // Top bar
                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Text(controller.recordingContext.displayTitle)
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Recording indicator
                    if controller.currentPhase.isRecording {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .foregroundColor(.red)
                                .font(.caption.bold())
                        }
                        .padding()
                    } else {
                        Color.clear.frame(width: 50, height: 30)
                    }
                }
                
                Spacer()
                
                // Recording button
                RecordingButton(controller: controller)
                    .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Video Processing View (UPDATED)
    
    private var videoProcessingView: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    StitchColors.primary.opacity(0.3),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Processing icon with animation
                ZStack {
                    Circle()
                        .stroke(StitchColors.primary.opacity(0.3), lineWidth: 4)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0.0, to: controller.coordinatorProgress)
                        .stroke(StitchColors.primary, lineWidth: 4)
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: controller.coordinatorProgress)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 30))
                        .foregroundColor(StitchColors.primary)
                        .scaleEffect(controller.coordinatorIsProcessing ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: controller.coordinatorIsProcessing)
                }
                
                VStack(spacing: 16) {
                    // Phase indicator
                    Text(controller.coordinatorCurrentPhase.displayName)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    // Current task
                    Text(controller.coordinatorCurrentTask)
                        .font(.body)
                        .foregroundColor(StitchColors.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    // Progress percentage
                    Text("\(Int(controller.coordinatorProgress * 100))%")
                        .font(.headline.bold())
                        .foregroundColor(StitchColors.primary)
                }
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: controller.coordinatorProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: StitchColors.primary))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .frame(maxWidth: 300)
                    
                    // Phase breakdown
                    HStack(spacing: 4) {
                        ForEach(["analyzing", "compressing", "uploading", "integrating"], id: \.self) { phaseKey in
                            Rectangle()
                                .fill(isCurrentOrPastPhase(phaseKey) ?
                                      StitchColors.primary : StitchColors.surface)
                                .frame(height: 4)
                                .animation(.easeInOut(duration: 0.3), value: controller.coordinatorCurrentPhase.displayName)
                        }
                    }
                    .frame(maxWidth: 300)
                }
                
                // Processing details
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "brain")
                        Text("AI Analysis")
                        Spacer()
                        if controller.coordinatorCurrentPhase.displayName == "AI Analysis" {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                                .scaleEffect(0.8)
                        } else if controller.coordinatorProgress > 0.3 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(StitchColors.textSecondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Compression")
                        Spacer()
                        if controller.coordinatorCurrentPhase.displayName == "Compression" {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                                .scaleEffect(0.8)
                        } else if controller.coordinatorProgress > 0.6 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(StitchColors.textSecondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Upload")
                        Spacer()
                        if controller.coordinatorCurrentPhase.displayName == "Upload" {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                                .scaleEffect(0.8)
                        } else if controller.coordinatorProgress > 0.85 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(StitchColors.textSecondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "link")
                        Text("Feed Integration")
                        Spacer()
                        if controller.coordinatorCurrentPhase.displayName == "Integration" {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                                .scaleEffect(0.8)
                        } else if controller.coordinatorProgress >= 1.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(StitchColors.textSecondary)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(StitchColors.textSecondary)
                .padding(.horizontal, 40)
                
                // Cancel button
                Button("Cancel") {
                    controller.handleAIAnalysisCancel()
                    onCancel()
                }
                .font(.body)
                .foregroundColor(StitchColors.textSecondary)
                .padding(.top, 20)
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Metadata View (Existing)
    
    private var metadataView: some View {
        VStack(spacing: 20) {
            Text("Video Processing Complete!")
                .font(.title.bold())
                .foregroundColor(.white)
            
            if let aiResult = controller.aiAnalysisResult {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Generated Content:")
                        .font(.headline)
                        .foregroundColor(StitchColors.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title: \(aiResult.title)")
                        Text("Description: \(aiResult.description)")
                        Text("Hashtags: \(aiResult.hashtags.joined(separator: ", "))")
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .padding()
                    .background(StitchColors.surface)
                    .cornerRadius(12)
                }
            }
            
            Button("Continue to Post") {
                // Handle continue to post
                print("Continue to post tapped")
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(StitchColors.primary)
            .cornerRadius(12)
            
            Button("Back to Recording") {
                controller.handleBackToRecording()
            }
            .font(.body)
            .foregroundColor(StitchColors.textSecondary)
        }
        .padding(.horizontal, 30)
    }
    
    // Helper function to check if phase is current or past
    private func isCurrentOrPastPhase(_ phaseKey: String) -> Bool {
        let currentPhase = controller.coordinatorCurrentPhase.displayName
        
        switch phaseKey {
        case "analyzing":
            return currentPhase == "AI Analysis" || controller.coordinatorProgress > 0.3
        case "compressing":
            return currentPhase == "Compression" || controller.coordinatorProgress > 0.6
        case "uploading":
            return currentPhase == "Upload" || controller.coordinatorProgress > 0.85
        case "integrating":
            return currentPhase == "Integration" || controller.coordinatorProgress >= 1.0
        default:
            return false
        }
    }
}

// MARK: - Recording Button

struct RecordingButton: View {
    @ObservedObject var controller: RecordingController
    @State private var liquidFillProgress: Double = 0.0
    @State private var recordingTimer: Timer?
    @State private var startTime: Date?
    
    private let maxRecordingDuration: TimeInterval = 30.0
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 80, height: 80)
            
            // Liquid fill effect
            if controller.currentPhase.isRecording {
                Circle()
                    .trim(from: 0, to: liquidFillProgress)
                    .stroke(StitchColors.primary, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: liquidFillProgress)
            }
            
            // Inner button
            Button {
                if controller.currentPhase.canStartRecording {
                    startRecording()
                } else if controller.currentPhase.isRecording {
                    stopRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(controller.currentPhase.isRecording ? StitchColors.primary : Color.white)
                        .frame(width: 60, height: 60)
                    
                    if controller.currentPhase.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    }
                }
            }
            .disabled(!controller.currentPhase.canStartRecording && !controller.currentPhase.isRecording)
            
            // Time remaining
            if controller.currentPhase.isRecording {
                VStack {
                    Spacer()
                    Text(formatTimeRemaining(getRemainingTime()))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.top, 100)
                }
            }
        }
    }
    
    private func startRecording() {
        startTime = Date()
        liquidFillProgress = 0.0
        controller.startRecording()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateProgress()
        }
    }
    
    private func getRemainingTime() -> TimeInterval {
        guard let startTime = startTime else { return maxRecordingDuration }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, maxRecordingDuration - elapsed)
    }
    
    private func updateProgress() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let timeRemaining = max(0, maxRecordingDuration - elapsed)
        
        liquidFillProgress = 1.0 - (timeRemaining / maxRecordingDuration)
        
        if timeRemaining <= 0 {
            stopRecording()
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        liquidFillProgress = 0.0
        controller.stopRecording()
    }
    
    private func formatTimeRemaining(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return "\(seconds)s"
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var controller: RecordingController
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        print("🔍 DEBUG: Creating CameraPreview UIView")
        let view = CameraPreviewUIView()
        
        let previewLayer = controller.cameraManager.previewLayer
        print("🔍 DEBUG: Preview layer created: \(previewLayer)")
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        
        print("🔍 DEBUG: Camera session running: \(controller.cameraManager.isSessionRunning)")
        
        // Add gestures
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinch))
        
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        DispatchQueue.main.async {
            uiView.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreview
        private var initialZoom: CGFloat = 1.0
        
        init(_ parent: CameraPreview) {
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

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.title.bold())
                .foregroundColor(.white)
            
            Text(message)
                .font(.body)
                .foregroundColor(StitchColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Button("Retry") {
                onRetry()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(StitchColors.primary)
            .cornerRadius(12)
        }
    }
}
