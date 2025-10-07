//
//  ProgressiveCoolButton.swift
//  StitchSocial
//
//  Layer 8: UI - Progressive Tapping Cool Button with 3D Effects and Floating Icons
//  Dependencies: EngagementManager (Layer 6), FloatingIconManager
//  Features: 3D depth, progressive tapping, TikTok-style floating snowflake animations
//

import SwiftUI
import Foundation

/// Progressive cool button with 3D effects and floating snowflake spawning
struct ProgressiveCoolButton: View {
    
    // MARK: - Properties
    let videoID: String
    let currentCoolCount: Int
    let currentUserID: String
    let userTier: UserTier
    
    @ObservedObject var engagementManager: EngagementManager
    @ObservedObject var iconManager: FloatingIconManager
    
    // MARK: - State
    @State private var isPressed = false
    @State private var buttonPosition: CGPoint = .zero
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var shimmerPhase: Double = 0
    @State private var showingTrollWarning = false
    
    // MARK: - Computed Properties
    private var engagementState: VideoEngagementState {
        engagementManager.getEngagementState(videoID: videoID, userID: currentUserID)
    }
    
    private var isInstantMode: Bool {
        EngagementCalculator.isInstantMode(totalEngagements: engagementState.totalEngagements)
    }
    
    private var tapProgress: Double {
        engagementState.coolProgress
    }
    
    // Use the existing EngagementManager property
    private var isProcessing: Bool {
        engagementManager.isProcessingEngagement
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // 3D Button Base
                coolButtonBase
                
                // Progress ring (always show if there's progress)
                if tapProgress > 0 {
                    coolProgressRing
                }
                
                // 3D Snowflake Icon
                snowflakeIcon
                
                // Tap counter (show if there are current taps)
                if engagementState.coolCurrentTaps > 0 {
                    coolTapCounter
                }
                
                // Cool count display (always shown)
                coolCountDisplay
                
                // Troll warning overlay
                if showingTrollWarning {
                    trollWarningOverlay
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .rotation3DEffect(
                .degrees(isPressed ? -5 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        buttonPosition = CGPoint(
                            x: geo.frame(in: .global).midX,
                            y: geo.frame(in: .global).midY
                        )
                    }
            }
        )
        .overlay(errorMessageOverlay)
        .onAppear {
            startShimmerAnimation()
        }
    }
    
    // MARK: - 3D Cool Button Components
    
    private var coolButtonBase: some View {
        ZStack {
            // Shadow layers for depth
            ForEach(0..<4, id: \.self) { layer in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(0.1),
                                Color.blue.opacity(0.2)
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
                    .opacity(0.3 - Double(layer) * 0.075)
            }
            
            // Main button background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.4),
                            Color.blue.opacity(0.3),
                            Color.black.opacity(0.8)
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
                                [.cyan, .blue, .white] : [.cyan.opacity(0.8), .blue.opacity(0.6), .white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isProcessing ? 2.0 : 1.5
                        )
                        .opacity(0.7 + sin(shimmerPhase) * 0.3)
                )
                .shadow(color: .cyan.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
    
    private var snowflakeIcon: some View {
        ZStack {
            // Shadow snowflakes for depth (always snowflake, never tornado)
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: "snowflake")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.black.opacity(0.4), .blue.opacity(0.3)],
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
            
            // Main snowflake icon with gradient (always snowflake, never tornado)
            Image(systemName: "snowflake")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .cyan, .blue, .black.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .cyan, radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                .rotationEffect(.degrees(shimmerPhase * 2))
        }
    }
    
    private var coolProgressRing: some View {
        Circle()
            .trim(from: 0, to: tapProgress)
            .stroke(
                LinearGradient(
                    colors: [.cyan, .blue, .white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 36, height: 36)
            .rotationEffect(.degrees(-90))
            .shadow(color: .cyan.opacity(0.6), radius: 2, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.3), value: tapProgress)
    }
    
    private var coolTapCounter: some View {
        VStack(spacing: 1) {
            Text("\(engagementState.coolCurrentTaps)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            
            Rectangle()
                .fill(Color.cyan.opacity(0.8))
                .frame(width: 8, height: 1)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
            
            Text("\(engagementState.coolRequiredTaps)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }
        .offset(y: -35)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: engagementState.coolCurrentTaps)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: engagementState.coolRequiredTaps)
    }
    
    private var coolCountDisplay: some View {
        Text("\(currentCoolCount)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            .offset(y: -35)
    }
    
    private var trollWarningOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                )
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }
        .scaleEffect(1.2)
        .transition(.scale.combined(with: .opacity))
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
    
    /// Handle tap interaction with floating snowflake spawning
    private func handleTap() {
        withAnimation(.spring(response: 0.1, dampingFraction: 0.6)) {
            isPressed = true
        }
        
        // Check for potential trolling behavior
        if shouldShowTrollWarning() {
            showTrollWarning()
            return
        }
        
        // Cool haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Spawn floating snowflake from button position
        let isFirstFounderTap = userTier == .founder && engagementState.totalEngagements == 0
        iconManager.spawnCoolIcon(
            from: buttonPosition,
            userTier: userTier,
            isFirstFounderTap: isFirstFounderTap
        )
        
        // Process engagement using existing manager
        Task {
            do {
                let success = try await engagementManager.processCool(
                    videoID: videoID,
                    userID: currentUserID,
                    userTier: userTier
                )
                
                await MainActor.run {
                    if success {
                        // Success haptic
                        let successImpact = UIImpactFeedbackGenerator(style: .light)
                        successImpact.impactOccurred()
                        
                        // Spawn additional celebration effects for special cases
                        if isFirstFounderTap {
                            // Extra ice explosion for founder first tap
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                iconManager.spawnMultipleIcons(
                                    from: buttonPosition,
                                    count: 3,
                                    iconType: .cool,
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
    
    /// Check if should show troll warning
    private func shouldShowTrollWarning() -> Bool {
        // Simple troll detection - rapid cool taps
        let recentTaps = engagementState.coolCurrentTaps
        let totalCools = engagementState.coolEngagements
        
        // Warn if user is spamming cool on their own content or excessive cooling
        return totalCools > 10 && recentTaps > 5
    }
    
    /// Show troll warning
    private func showTrollWarning() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingTrollWarning = true
        }
        
        let warningImpact = UINotificationFeedbackGenerator()
        warningImpact.notificationOccurred(.warning)
        
        showError("Excessive cooling detected - please engage thoughtfully")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingTrollWarning = false
            }
        }
    }
    
    /// Show error message
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showingError = false
        }
    }
    
    /// Start shimmer animation
    private func startShimmerAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            shimmerPhase += 0.15
        }
    }
}
