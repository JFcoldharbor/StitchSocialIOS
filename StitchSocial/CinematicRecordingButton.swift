//
//  CinematicRecordingButton.swift
//  StitchSocial
//
//  Layer 8: Views - Professional Recording Button with Cinematic Controls
//  Dependencies: VideoCoordinator (Layer 6), CinematicCameraManager (Layer 4)
//

import SwiftUI
import AVFoundation

struct CinematicRecordingButton: View {
    
    // MARK: - Dependencies
    @StateObject private var controller = VideoCoordinator(
        videoService: VideoService(),
        aiAnalyzer: AIVideoAnalyzer(),
        videoProcessor: VideoProcessingService(),
        uploadService: VideoUploadService(),
        cachingService: nil
    )
    
    // MARK: - Recording Context
    let recordingContext: String
    let onVideoCreated: (URL?) -> Void
    let onCancel: () -> Void
    
    // MARK: - State
    @State private var buttonScale: CGFloat = 1.0
    @State private var pulseAnimation: Bool = false
    @State private var showingControls: Bool = false
    @State private var lastTapTime: Date = Date()
    
    // MARK: - Constants
    private let buttonSize: CGFloat = 80
    private let pulseSize: CGFloat = 120
    private let animationDuration: Double = 0.15
    
    var body: some View {
        ZStack {
            // Background pulse for recording state
            if controller.currentPhase == .analyzing {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: pulseSize, height: pulseSize)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.3 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }
            
            // Main recording button
            Button(action: handleButtonTap) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(buttonColor, lineWidth: 4)
                        .frame(width: buttonSize, height: buttonSize)
                    
                    // Inner button
                    Circle()
                        .fill(buttonFillColor)
                        .frame(width: buttonSize - 12, height: buttonSize - 12)
                        .overlay(buttonIcon)
                }
            }
            .scaleEffect(buttonScale)
            .disabled(!buttonEnabled)
            
            // Progress indicator for processing states
            if showProgressIndicator {
                Circle()
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 3)
                    .frame(width: buttonSize + 8, height: buttonSize + 8)
                    .overlay(
                        Circle()
                            .trim(from: 0, to: progressValue)
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: progressValue)
                    )
            }
            
            // Recording timer
            if controller.currentPhase == .analyzing {
                VStack {
                    Spacer()
                    
                    Text(formatRecordingTime(0))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .opacity(0.9)
                        )
                        .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            setupController()
        }
        .onChange(of: controller.currentPhase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
    }
    
    // MARK: - Setup
    
    private func setupController() {
        // Start pulse animation if needed
        if controller.currentPhase == .analyzing {
            pulseAnimation = true
        }
    }
    
    // MARK: - Button Logic
    
    private func handleButtonTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
        lastTapTime = now
        
        // Prevent rapid tapping
        guard timeSinceLastTap > 0.3 else { return }
        
        // Add haptic feedback
        hapticFeedback()
        
        switch controller.currentPhase {
        case .ready:
            startRecording()
        case .analyzing:
            stopRecording()
        default:
            // Other states are not interactive
            break
        }
    }
    
    private func startRecording() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            buttonScale = 0.9
        }
        
        // Simulate recording start
        pulseAnimation = true
        withAnimation(.easeInOut(duration: animationDuration)) {
            buttonScale = 1.0
        }
        
        // Call completion after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onVideoCreated(URL(fileURLWithPath: "/tmp/test.mov"))
        }
    }
    
    private func stopRecording() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            buttonScale = 1.1
        }
        
        pulseAnimation = false
        withAnimation(.easeInOut(duration: animationDuration)) {
            buttonScale = 1.0
        }
        
        onCancel()
    }
    
    // MARK: - Phase Change Handling
    
    private func handlePhaseChange(_ newPhase: VideoCreationPhase) {
        switch newPhase {
        case .analyzing:
            pulseAnimation = true
        case .compressing, .uploading:
            pulseAnimation = false
        case .complete:
            // Recording completed successfully
            break
        case .error:
            // Handle error state
            print("Recording error")
            pulseAnimation = false
        default:
            pulseAnimation = false
        }
    }
    
    // MARK: - UI Computed Properties
    
    private var buttonColor: Color {
        switch controller.currentPhase {
        case .ready:
            return .white
        case .analyzing:
            return .red
        case .compressing, .uploading:
            return .cyan
        case .complete:
            return .green
        case .error:
            return .orange
        default:
            return .gray
        }
    }
    
    private var buttonFillColor: Color {
        switch controller.currentPhase {
        case .ready:
            return .clear
        case .analyzing:
            return .red
        case .compressing, .uploading:
            return .cyan.opacity(0.3)
        case .complete:
            return .green.opacity(0.3)
        case .error:
            return .orange.opacity(0.3)
        default:
            return .gray.opacity(0.3)
        }
    }
    
    private var buttonIcon: some View {
        Group {
            switch controller.currentPhase {
            case .ready:
                EmptyView()
            case .analyzing:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
            case .compressing, .uploading:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            case .complete:
                Image(systemName: "checkmark")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .bold))
            case .error:
                Image(systemName: "exclamationmark")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .bold))
            default:
                EmptyView()
            }
        }
    }
    
    private var buttonEnabled: Bool {
        switch controller.currentPhase {
        case .ready, .analyzing:
            return true
        default:
            return false
        }
    }
    
    private var showProgressIndicator: Bool {
        switch controller.currentPhase {
        case .compressing, .uploading:
            return true
        default:
            return false
        }
    }
    
    private var progressValue: CGFloat {
        // Use controller's progress if available
        return CGFloat(controller.overallProgress)
    }
    
    // MARK: - Utility Methods
    
    private func hapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func formatRecordingTime(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

struct CinematicRecordingButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            CinematicRecordingButton(
                recordingContext: "newThread",
                onVideoCreated: { _ in },
                onCancel: { }
            )
        }
    }
}
