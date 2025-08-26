//
//  CinematicRecordingButton.swift
//  CleanBeta
//
//  Layer 8: Views - Professional Recording Button (Tab Bar Style)
//  Mimics CustomDippedTabBar create button with liquid fill timer
//  Features: Glassmorphism, haptic feedback, cinematic animations
//

import SwiftUI

struct CinematicRecordingButton: View {
    @ObservedObject var controller: RecordingController
    @State private var liquidFillProgress: Double = 0.0
    @State private var recordingTimer: Timer?
    @State private var startTime: Date?
    @State private var buttonScale: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.3
    
    // MARK: - Configuration (Matching Tab Bar Create Button)
    
    private let buttonSize: CGFloat = 75 // Slightly larger than tab bar (62 -> 75)
    private let maxRecordingDuration: TimeInterval = 30.0
    
    var body: some View {
        ZStack {
            // MARK: - Outer Glow Ring (Tab Bar Style)
            
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            StitchColors.primary.opacity(glowIntensity),
                            StitchColors.secondary.opacity(glowIntensity * 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: buttonSize + 8, height: buttonSize + 8)
                .blur(radius: 2)
                .scaleEffect(pulseScale)
                .animation(
                    controller.currentPhase.isRecording ?
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                    .easeInOut(duration: 0.3),
                    value: pulseScale
                )
            
            // MARK: - Liquid Fill Timer Background
            
            if controller.currentPhase.isRecording {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                StitchColors.primary.opacity(0.2),
                                StitchColors.secondary.opacity(0.3),
                                StitchColors.primary.opacity(0.2)
                            ],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        )
                    )
                    .frame(width: buttonSize + 4, height: buttonSize + 4)
                    .rotationEffect(.degrees(liquidFillProgress * 360))
                    .animation(.linear(duration: 0.1), value: liquidFillProgress)
            }
            
            // MARK: - Main Button (Tab Bar Glassmorphism Style)
            
            Button(action: handleButtonTap) {
                ZStack {
                    // Glassmorphism background (exact tab bar style)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                        .overlay(
                            // Inner gradient (tab bar style)
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            StitchColors.primary.opacity(0.9),
                                            StitchColors.secondary.opacity(1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 0.8)
                        )
                        .overlay(
                            // Glass border (tab bar style)
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8),
                                            Color.white.opacity(0.3),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.6
                                )
                        )
                        .frame(width: buttonSize, height: buttonSize)
                    
                    // MARK: - Liquid Fill Timer (Inside Button)
                    
                    if controller.currentPhase.isRecording {
                        Circle()
                            .trim(from: 0, to: liquidFillProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.6)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 4
                            )
                            .frame(width: buttonSize - 12, height: buttonSize - 12)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: liquidFillProgress)
                    }
                    
                    // MARK: - Button Icon (Context-Aware)
                    
                    Group {
                        if controller.currentPhase.isRecording {
                            // Stop icon (rounded square)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        } else if controller.currentPhase == .ready {
                            // Context-aware icon
                            Image(systemName: getContextIcon())
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            // Processing states
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        }
                    }
                    .shadow(color: .white.opacity(0.8), radius: 2.8)
                    .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
                }
            }
            .scaleEffect(buttonScale)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: buttonScale)
            .disabled(!canInteract)
            
            // MARK: - Recording Timer Display
            
            if controller.currentPhase.isRecording {
                VStack {
                    Spacer()
                    
                    Text(formatTimeRemaining(getRemainingTime()))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .offset(y: 45) // Position below button
                        .transition(.opacity.combined(with: .scale))
                }
            }
            
            // MARK: - Quality Indicator
            
            if !controller.currentPhase.isRecording {
                VStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(getQualityColor())
                            .frame(width: 8, height: 8)
                        
                        Text(getQualityText())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                    .offset(y: -50) // Position above button
                    
                    Spacer()
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.currentPhase)
        .onAppear {
            setupButtonAnimations()
        }
        .onDisappear {
            cleanupTimer()
        }
        .onChange(of: controller.currentPhase) { phase in
            handlePhaseChange(phase)
        }
    }
    
    // MARK: - Button Actions
    
    private func handleButtonTap() {
        // Haptic feedback (matching tab bar)
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Button animation (matching tab bar)
        withAnimation(.easeInOut(duration: 0.1)) {
            buttonScale = 0.85
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                buttonScale = 1.0
            }
        }
        
        // Execute recording action
        if controller.currentPhase.canStartRecording {
            startRecording()
        } else if controller.currentPhase.isRecording {
            stopRecording()
        }
    }
    
    private func startRecording() {
        startTime = Date()
        liquidFillProgress = 0.0
        controller.startRecording()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateProgress()
        }
        
        print("CINEMATIC BUTTON: Recording started")
    }
    
    private func stopRecording() {
        cleanupTimer()
        controller.stopRecording()
        print("CINEMATIC BUTTON: Recording stopped")
    }
    
    // MARK: - Liquid Fill Timer Logic
    
    private func updateProgress() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / maxRecordingDuration)
        
        liquidFillProgress = progress
        
        // Auto-stop at max duration
        if elapsed >= maxRecordingDuration {
            stopRecording()
        }
    }
    
    private func getRemainingTime() -> TimeInterval {
        guard let startTime = startTime else { return maxRecordingDuration }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, maxRecordingDuration - elapsed)
    }
    
    private func formatTimeRemaining(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return "\(seconds)s"
    }
    
    // MARK: - Context-Aware Icons
    
    private func getContextIcon() -> String {
        switch controller.recordingContext {
        case .newThread:
            return "plus.circle.fill"
        case .stitchToThread:
            return "link"
        case .replyToVideo:
            return "arrowshape.turn.up.left.fill"
        case .continueThread:
            return "arrow.right.circle.fill"
        }
    }
    
    // MARK: - Quality Indicators (FIXED)
    
    private func getQualityColor() -> Color {
        // StreamlinedCameraManager doesn't have recordingQuality - use default
        return .green // Default to professional quality color
    }
    
    private func getQualityText() -> String {
        // StreamlinedCameraManager doesn't have recordingQuality - use default
        return "HD" // Default quality text
    }
    
    // MARK: - Animation Management
    
    private func setupButtonAnimations() {
        // Subtle breathing animation when ready
        if controller.currentPhase == .ready {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
    
    private func handlePhaseChange(_ phase: RecordingPhase) {
        switch phase {
        case .ready:
            setupButtonAnimations()
            
        case .recording:
            // Start pulsing glow
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
                glowIntensity = 0.8
            }
            
        case .stopping:
            // Stop animations
            withAnimation(.easeInOut(duration: 0.3)) {
                pulseScale = 1.0
                glowIntensity = 0.3
            }
            
        case .aiProcessing:
            // Processing glow
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.7
            }
            
        case .complete:
            // Success glow
            withAnimation(.easeInOut(duration: 0.5)) {
                glowIntensity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    glowIntensity = 0.3
                }
            }
            
        case .error(_):
            // Error pulse
            withAnimation(.easeInOut(duration: 0.2).repeatCount(3, autoreverses: true)) {
                buttonScale = 1.1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    buttonScale = 1.0
                    glowIntensity = 0.3
                }
            }
        }
    }
    
    private func cleanupTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        liquidFillProgress = 0.0
        startTime = nil
    }
    
    // MARK: - Computed Properties
    
    private var canInteract: Bool {
        switch controller.currentPhase {
        case .ready, .recording:
            return true
        default:
            return false
        }
    }
    
    private var isProcessing: Bool {
        switch controller.currentPhase {
        case .stopping, .aiProcessing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Enhanced Recording Button (Full Tab Bar Replication)

struct EnhancedCinematicButton: View {
    @ObservedObject var controller: RecordingController
    @State private var liquidFillProgress: Double = 0.0
    @State private var recordingTimer: Timer?
    @State private var startTime: Date?
    @State private var createButtonScale: CGFloat = 1.0
    @State private var glowAnimation: Bool = false
    
    // MARK: - Exact Tab Bar Dimensions
    
    private let createButtonSize: CGFloat = 75 // Slightly larger for recording
    private let maxRecordingDuration: TimeInterval = 30.0
    
    var body: some View {
        ZStack {
            // EXACT TAB BAR OUTER GLOW (Scaled Up)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            StitchColors.primary.opacity(0.8),
                            StitchColors.secondary.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: createButtonSize + 6, height: createButtonSize + 6)
                .blur(radius: 2)
                .scaleEffect(glowAnimation ? 1.1 : 1.0)
                .animation(
                    controller.currentPhase.isRecording ?
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                    .easeInOut(duration: 0.3),
                    value: glowAnimation
                )
            
            // LIQUID FILL TIMER (Circular Progress)
            if controller.currentPhase.isRecording {
                Circle()
                    .trim(from: 0, to: liquidFillProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                StitchColors.primary.opacity(0.8),
                                Color.white.opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 5
                    )
                    .frame(width: createButtonSize - 8, height: createButtonSize - 8)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: liquidFillProgress)
                    .shadow(color: StitchColors.primary.opacity(0.6), radius: 4)
            }
            
            // EXACT TAB BAR BUTTON DESIGN
            Button(action: handleRecordingTap) {
                ZStack {
                    // Glassmorphism background (EXACT tab bar replication)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                        .overlay(
                            // Inner gradient (EXACT tab bar style)
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            StitchColors.primary.opacity(0.9),
                                            StitchColors.secondary.opacity(1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 0.8)
                        )
                        .overlay(
                            // Glass border (EXACT tab bar style)
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8),
                                            Color.white.opacity(0.3),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.6
                                )
                        )
                        .frame(width: createButtonSize, height: createButtonSize)
                    
                    // DYNAMIC ICON (Context + State Aware)
                    getButtonIcon()
                        .shadow(color: .white.opacity(0.8), radius: 2.8)
                        .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
                }
            }
            .scaleEffect(createButtonScale)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: createButtonScale)
            .disabled(!canInteract)
            
            // RECORDING STATS OVERLAY (FIXED)
            if controller.currentPhase.isRecording {
                recordingStatsOverlay
            }
        }
        .shadow(
            color: StitchColors.primary.opacity(0.6),
            radius: 20,
            x: 0,
            y: 8
        )
        .shadow(
            color: Color.black.opacity(0.4),
            radius: 15,
            x: 0,
            y: 10
        )
        .onAppear {
            startGlowAnimation()
        }
        .onDisappear {
            cleanupAll()
        }
    }
    
    // MARK: - Dynamic Button Icon
    
    @ViewBuilder
    private func getButtonIcon() -> some View {
        Group {
            if controller.currentPhase.isRecording {
                // Recording: Stop icon
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .transition(.scale.combined(with: .opacity))
                
            } else if controller.currentPhase == .ready {
                // Ready: Context-aware icon
                Image(systemName: getContextualIcon())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
                
            } else if isProcessing {
                // Processing: Animated progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0, to: controller.coordinatorProgress)
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: controller.coordinatorProgress)
                }
                .transition(.scale.combined(with: .opacity))
                
            } else {
                // Error/Other: Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private func getContextualIcon() -> String {
        switch controller.recordingContext {
        case .newThread:
            return "plus"
        case .stitchToThread:
            return "link"
        case .replyToVideo:
            return "arrowshape.turn.up.left.fill"
        case .continueThread:
            return "arrow.right"
        }
    }
    
    // MARK: - Recording Stats Overlay (FIXED)
    
    private var recordingStatsOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 16) {
                // Duration
                Label(formatTimeRemaining(getRemainingTime()), systemImage: "clock.fill")
                
                // Quality
                Label(getQualityText(), systemImage: "video.fill")
                
                // HDR indicator (FIXED - Use Available Properties)
                if controller.cameraManager.isSessionRunning {
                    Label("REC", systemImage: "record.circle.fill")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .offset(y: 60)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Animation Management
    
    private func startGlowAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowAnimation = true
        }
    }
    
    private func cleanupAll() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        liquidFillProgress = 0.0
        startTime = nil
        glowAnimation = false
    }
    
    // MARK: - Recording Management
    
    private func handleRecordingTap() {
        // EXACT tab bar haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // EXACT tab bar button animation
        withAnimation(.easeInOut(duration: 0.1)) {
            createButtonScale = 0.85
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                createButtonScale = 1.0
            }
        }
        
        // Execute action based on state
        if controller.currentPhase.canStartRecording {
            startCinematicRecording()
        } else if controller.currentPhase.isRecording {
            stopCinematicRecording()
        }
    }
    
    private func startCinematicRecording() {
        startTime = Date()
        liquidFillProgress = 0.0
        controller.startRecording()
        
        // Start liquid fill timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            updateLiquidFill()
        }
        
        print("CINEMATIC RECORDING: Professional recording started")
    }
    
    private func stopCinematicRecording() {
        cleanupAll()
        controller.stopRecording()
        print("CINEMATIC RECORDING: Professional recording stopped")
    }
    
    private func updateLiquidFill() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / maxRecordingDuration)
        
        liquidFillProgress = progress
        
        // Auto-stop at max duration with smooth transition
        if elapsed >= maxRecordingDuration {
            withAnimation(.easeInOut(duration: 0.3)) {
                stopCinematicRecording()
            }
        }
    }
    
    // MARK: - Helper Methods (FIXED)
    
    private func getRemainingTime() -> TimeInterval {
        guard let startTime = startTime else { return maxRecordingDuration }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, maxRecordingDuration - elapsed)
    }
    
    private func formatTimeRemaining(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return "\(seconds)s"
    }
    
    private func getQualityText() -> String {
        // StreamlinedCameraManager doesn't have recordingQuality - use default
        return "HD" // Default quality text
    }
    
    // MARK: - Enhanced Button Helper Methods
    
    private func MygetRemainingTime() -> TimeInterval {
        guard let startTime = startTime else { return maxRecordingDuration }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, maxRecordingDuration - elapsed)
    }
    
    private func TheformatTimeRemaining(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return "\(seconds)s"
    }
    
    // MARK: - Computed Properties
    
    private var canInteract: Bool {
        controller.currentPhase.canStartRecording || controller.currentPhase.isRecording
    }
    
    private var isProcessing: Bool {
        switch controller.currentPhase {
        case .stopping, .aiProcessing:
            return true
        default:
            return false
        }
    }
}
