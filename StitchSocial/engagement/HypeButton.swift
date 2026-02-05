//
//  ProgressiveHypeButton.swift
//  StitchSocial
//
//  Layer 8: UI - Progressive Tapping Hype Button with 3D Effects and Floating Icons
//  Dependencies: EngagementManager (Layer 6), FloatingIconManager
//  Features: 3D depth, progressive tapping, TikTok-style floating flame animations
//  UPDATED: Self-engagement restriction - only founders can hype their own content
//

import SwiftUI
import Foundation

/// Progressive hype button with 3D effects and floating flame spawning
struct ProgressiveHypeButton: View {
    
    // MARK: - Properties
    let videoID: String
    let creatorID: String  // NEW: Video creator's ID for self-engagement check
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
    @State private var showingCloutCapWarning = false
    
    // MARK: - Computed Properties
    private var engagementState: VideoEngagementState {
        engagementManager.getEngagementState(videoID: videoID, userID: currentUserID)
    }
    
    private var isProcessing: Bool {
        engagementManager.isProcessingEngagement
    }
    
    // MARK: - Self-Engagement Check (NEW)
    
    /// Check if user is trying to engage with their own content
    private var isSelfEngagement: Bool {
        currentUserID == creatorID
    }
    
    /// Check if user is a founder tier (allowed to self-engage)
    private var isFounderTier: Bool {
        userTier == .founder || userTier == .coFounder
    }
    
    /// Whether self-engagement should be blocked
    private var shouldBlockSelfEngagement: Bool {
        isSelfEngagement && !isFounderTier
    }
    
    // Clout cap tracking
    private var hasHitCloutCap: Bool {
        engagementState.hasHitCloutCap(for: userTier)
    }
    
    private var hasHitEngagementCap: Bool {
        engagementState.hasHitEngagementCap()
    }
    
    private var isNearCloutCap: Bool {
        let remaining = engagementState.getRemainingCloutAllowance(for: userTier)
        let max = EngagementConfig.getMaxCloutPerUserPerVideo(for: userTier)
        return Double(remaining) / Double(max) < 0.2 // Less than 20% remaining
    }
    
    // NEW: Visual hype multiplier for this tier
    private var visualHypeMultiplier: Int {
        EngagementConfig.getVisualHypeMultiplier(for: userTier)
    }
    
    /// Whether button should be disabled
    private var isDisabled: Bool {
        shouldBlockSelfEngagement || hasHitCloutCap || hasHitEngagementCap
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // 3D Button Base with depth
                buttonBase
                
                // 3D Flame Icon with depth
                flameIcon
                
                // Hype count display (always shown)
                hypeCountDisplay
                
                // NEW: Self-engagement indicator
                if shouldBlockSelfEngagement {
                    selfEngagementOverlay
                }
                
                // NEW: Clout cap warning overlay
                if showingCloutCapWarning {
                    cloutCapWarningOverlay
                }
                
                // NEW: Near cap indicator
                if isNearCloutCap && !hasHitCloutCap && !shouldBlockSelfEngagement {
                    nearCapIndicator
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .rotation3DEffect(
                .degrees(isPressed ? 5 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
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
            
            // Main button background with cap/self-engagement indicator color
            Circle()
                .fill(
                    RadialGradient(
                        colors: shouldBlockSelfEngagement ? [
                            Color.gray.opacity(0.4),
                            Color.black.opacity(0.7),
                            Color.black.opacity(0.9)
                        ] : hasHitCloutCap ? [
                            Color.red.opacity(0.4),
                            Color.black.opacity(0.7),
                            Color.black.opacity(0.9)
                        ] : [
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
                                colors: shouldBlockSelfEngagement ?
                                [.gray, .gray.opacity(0.6)] :
                                hasHitCloutCap ?
                                [.red, .orange] :
                                isProcessing ?
                                [.orange, .red, .yellow] : [.orange.opacity(0.6), .red.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isProcessing ? 2.0 : 1.5
                        )
                        .opacity(0.8 + sin(pulsePhase) * 0.2)
                )
                .shadow(color: shouldBlockSelfEngagement ? .gray.opacity(0.3) : .orange.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
    
    private var flameIcon: some View {
        ZStack {
            // Shadow flames for depth (always flame)
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: shouldBlockSelfEngagement ? "flame.slash.fill" : hasHitCloutCap ? "flame.slash.fill" : "flame.fill")
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
            
            // Main flame icon with gradient
            Image(systemName: shouldBlockSelfEngagement ? "flame.slash.fill" : hasHitCloutCap ? "flame.slash.fill" : "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: shouldBlockSelfEngagement ?
                        [.gray, .gray.opacity(0.7), .black.opacity(0.5)] :
                        hasHitCloutCap ?
                        [.red, .orange, .black.opacity(0.5)] :
                        [.yellow, .orange, .red, .black.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: shouldBlockSelfEngagement ? .gray : hasHitCloutCap ? .red : .orange, radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)
                .scaleEffect(shouldBlockSelfEngagement || hasHitCloutCap ? 1.0 : (1.0 + sin(pulsePhase * 2) * 0.1))
        }
    }
    
    private var hypeCountDisplay: some View {
        Text("\(currentHypeCount)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            .offset(y: -35)
    }
    
    // NEW: Self-engagement overlay
    private var selfEngagementOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: 2)
                )
            
            Image(systemName: "person.fill.xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.gray)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }
        .scaleEffect(1.1)
    }
    
    // NEW: Near cap indicator
    private var nearCapIndicator: some View {
        Circle()
            .stroke(Color.orange, lineWidth: 2)
            .frame(width: 48, height: 48)
            .opacity(0.6 + sin(pulsePhase * 3) * 0.3)
    }
    
    // NEW: Clout cap warning overlay
    private var cloutCapWarningOverlay: some View {
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
    
    /// Handle tap interaction with floating flame spawning
    private func handleTap() {
        print("🔴 HYPE TAP FIRED - videoID: \(videoID), disabled: \(isDisabled), selfBlock: \(shouldBlockSelfEngagement), cloutCap: \(hasHitCloutCap), engCap: \(hasHitEngagementCap), creatorID: \(creatorID), currentUserID: \(currentUserID), tier: \(userTier)")
        
        // NEW: Check self-engagement first
        if shouldBlockSelfEngagement {
            showError("You can't hype your own content")
            triggerErrorHaptic()
            return
        }
        
        // Check caps first
        if hasHitCloutCap {
            showCloutCapWarning()
            return
        }
        
        if hasHitEngagementCap {
            showError("Maximum engagements reached for this video")
            triggerErrorHaptic()
            return
        }
        
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
        
        // Determine if this is first engagement for special effects
        let isFirstEngagement = engagementState.hypeEngagements == 0
        let isPremiumTier = EngagementConfig.hasFirstTapBonus(tier: userTier)
        
        // Spawn floating flame from button position (with tier-based multiplier)
        if isFirstEngagement && isPremiumTier {
            // Premium tier first tap - spawn multiple flames
            iconManager.spawnMultipleIcons(
                from: buttonPosition,
                count: min(visualHypeMultiplier / 4, 5), // Scale particle count with multiplier
                iconType: .hype,
                animationType: .founderExplosion,
                userTier: userTier
            )
        } else {
            // Regular tap
            iconManager.spawnHypeIcon(
                from: buttonPosition,
                userTier: userTier,
                isFirstFounderTap: false
            )
        }
        
        // Process engagement using existing manager
        Task {
            do {
                let success = try await engagementManager.processHype(
                    videoID: videoID,
                    userID: currentUserID,
                    userTier: userTier,
                    creatorID: creatorID  // NEW: Pass creator ID for server-side validation
                )
                
                await MainActor.run {
                    if success {
                        // Success haptic
                        let successImpact = UIImpactFeedbackGenerator(style: .rigid)
                        successImpact.impactOccurred()
                        
                        // Check if near cap after this engagement
                        if isNearCloutCap {
                            showCloutNearCapNotice()
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
    
    /// Show clout cap warning
    private func showCloutCapWarning() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingCloutCapWarning = true
        }
        
        let warningImpact = UINotificationFeedbackGenerator()
        warningImpact.notificationOccurred(.warning)
        
        let maxClout = EngagementConfig.getMaxCloutPerUserPerVideo(for: userTier)
        showError("You've given max clout (\(maxClout)) to this video!")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingCloutCapWarning = false
            }
        }
    }
    
    /// Show near cap notice
    private func showCloutNearCapNotice() {
        let remaining = engagementState.getRemainingCloutAllowance(for: userTier)
        showError("Only \(remaining) clout remaining for this video")
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
