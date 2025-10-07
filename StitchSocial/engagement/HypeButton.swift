//
//  ProgressiveHypeButton.swift
//  StitchSocial
//
//  Layer 8: UI - Progressive Tapping Hype Button with 3D Effects and Floating Icons
//  Dependencies: EngagementManager (Layer 6), FloatingIconManager
//  Features: 3D depth, progressive tapping, TikTok-style floating flame animations
//

import SwiftUI
import Foundation

/// Progressive hype button with 3D effects and floating flame spawning
struct ProgressiveHypeButton: View {
    
    // MARK: - Properties
    let videoID: String
    let currentHypeCount: Int
    let currentUserID: String
    let userTier: UserTier
    
    @ObservedObject var engagementManager: EngagementManager
    @ObservedObject var iconManager: FloatingIconManager
    
    // MARK: - State
    @State private var isPressed = false
    @State private var buttonPosition: CGPoint = .zero
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pulsePhase: Double = 0
    
    // MARK: - Computed Properties
    private var engagementState: VideoEngagementState {
        engagementManager.getEngagementState(videoID: videoID, userID: currentUserID)
    }
    
    private var isInstantMode: Bool {
        EngagementCalculator.isInstantMode(totalEngagements: engagementState.totalEngagements)
    }
    
    private var tapProgress: Double {
        engagementState.hypeProgress
    }
    
    // Use the existing EngagementManager property
    private var isProcessing: Bool {
        engagementManager.isProcessingEngagement
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // 3D Button Base with depth
                buttonBase
                
                // Progress ring (always show if there's progress)
                if tapProgress > 0 {
                    progressRing
                }
                
                // 3D Flame Icon with depth
                flameIcon
                
                // Tap counter (show if there are current taps)
                if engagementState.hypeCurrentTaps > 0 {
                    tapCounter
                }
                
                // Hype count display (always shown)
                hypeCountDisplay
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .rotation3DEffect(
                .degrees(isPressed ? 5 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        // Capture button position for floating icons
                        buttonPosition = CGPoint(
                            x: geo.frame(in: .global).midX,
                            y: geo.frame(in: .global).midY
                        )
                    }
            }
        )
        .overlay(errorMessageOverlay)
        .onAppear {
            startPulseAnimation()
        }
    }
    
    // MARK: - 3D Button Components
    
    private var buttonBase: some View {
        ZStack {
            // Shadow layers for depth
            ForEach(0..<4, id: \.self) { layer in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(0.1),
                                Color.black.opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 25
                        )
                    )
                    .frame(width: 42, height: 42)
                    .offset(
                        x: CGFloat(layer) * 1.5,
                        y: CGFloat(layer) * 1.5
                    )
                    .opacity(0.4 - Double(layer) * 0.1)
            }
            
            // Main button background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.4),
                            Color.black.opacity(0.7),
                            Color.black.opacity(0.9)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isProcessing ?
                                [.orange, .red, .yellow] : [.orange.opacity(0.6), .red.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isProcessing ? 2.0 : 1.5
                        )
                        .opacity(0.8 + sin(pulsePhase) * 0.2)
                )
                .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
    
    private var flameIcon: some View {
        ZStack {
            // Shadow flames for depth (always flame, never bolt)
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .black.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(
                        x: CGFloat(layer) * 1,
                        y: CGFloat(layer) * 1
                    )
                    .opacity(0.3 - Double(layer) * 0.1)
            }
            
            // Main flame icon with gradient (always flame, never bolt)
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange, .red, .black.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .orange, radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)
                .scaleEffect(1.0 + sin(pulsePhase * 2) * 0.1)
        }
    }
    
    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: tapProgress)
            .stroke(
                LinearGradient(
                    colors: [.orange, .red, .yellow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 36, height: 36)
            .rotationEffect(.degrees(-90))
            .shadow(color: .orange.opacity(0.6), radius: 2, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.3), value: tapProgress)
    }
    
    private var tapCounter: some View {
        VStack(spacing: 1) {
            Text("\(engagementState.hypeCurrentTaps)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 8, height: 1)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
            
            Text("\(engagementState.hypeRequiredTaps)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }
        .offset(y: -35)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: engagementState.hypeCurrentTaps)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: engagementState.hypeRequiredTaps)
    }
    
    private var hypeCountDisplay: some View {
        Text("\(currentHypeCount)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            .offset(y: -35)
    }
    
    private var errorMessageOverlay: some View {
        Group {
            if showingError {
                VStack {
                    Spacer()
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                        .transition(.scale.combined(with: .opacity))
                        .offset(y: 60)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingError)
    }
    
    // MARK: - Actions
    
    /// Handle tap interaction with floating flame spawning
    private func handleTap() {
        withAnimation(.spring(response: 0.1, dampingFraction: 0.6)) {
            isPressed = true
        }
        
        // Check if user can engage
        let status = engagementManager.getHypeRatingStatus()
        guard status.canEngage else {
            showError("Hype rating too low - wait for regeneration")
            triggerErrorHaptic()
            return
        }
        
        // Heavy haptic for engaging interaction
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Spawn floating flame from button position
        let isFirstFounderTap = userTier == .founder && engagementState.totalEngagements == 0
        iconManager.spawnHypeIcon(
            from: buttonPosition,
            userTier: userTier,
            isFirstFounderTap: isFirstFounderTap
        )
        
        // Process engagement using existing manager
        Task {
            do {
                let success = try await engagementManager.processHype(
                    videoID: videoID,
                    userID: currentUserID,
                    userTier: userTier
                )
                
                await MainActor.run {
                    if success {
                        // Success haptic
                        let successImpact = UIImpactFeedbackGenerator(style: .rigid)
                        successImpact.impactOccurred()
                        
                        // Spawn additional celebration effects for special cases
                        if isFirstFounderTap {
                            // Extra explosion for founder first tap
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                iconManager.spawnMultipleIcons(
                                    from: buttonPosition,
                                    count: 3,
                                    iconType: .hype,
                                    animationType: .founderExplosion,
                                    userTier: userTier
                                )
                            }
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    showError(error.localizedDescription)
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isPressed = false
            }
        }
    }
    
    /// Show error message
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showingError = false
        }
    }
    
    /// Trigger error haptic
    private func triggerErrorHaptic() {
        let errorImpact = UINotificationFeedbackGenerator()
        errorImpact.notificationOccurred(.error)
    }
    
    /// Start pulse animation
    private func startPulseAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            pulsePhase += 0.2
        }
    }
}
