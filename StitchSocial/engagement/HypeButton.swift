//
//  ProgressiveHypeButton.swift
//  StitchSocial
//
//  Layer 8: UI - Hype Button with Long Press Burst
//  UPDATED: Regular tap = +1 hype, reduced clout | Long press = full tier burst multiplier
//

import SwiftUI
import Foundation

struct ProgressiveHypeButton: View {
    
    let videoID: String
    let creatorID: String
    let currentHypeCount: Int
    let currentUserID: String
    let userTier: UserTier
    
    @ObservedObject var engagementManager: EngagementManager
    @ObservedObject var iconManager: FloatingIconManager
    
    @State private var isPressed = false
    @State private var buttonPosition: CGPoint = .zero
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pulsePhase: Double = 0
    @State private var showingBurstIndicator = false
    
    // MARK: - Computed
    
    private var engagementState: VideoEngagementState {
        engagementManager.getEngagementState(videoID: videoID, userID: currentUserID)
    }
    
    private var isProcessing: Bool { engagementManager.isProcessingEngagement }
    private var isSelfEngagement: Bool { currentUserID == creatorID }
    private var isFounderTier: Bool { userTier == .founder || userTier == .coFounder }
    private var shouldBlockSelfEngagement: Bool { isSelfEngagement && !isFounderTier }
    private var hasHitEngagementCap: Bool { engagementState.hasHitEngagementCap() }
    private var isBurstEligible: Bool { EngagementConfig.isBurstEligible(tier: userTier) }
    private var burstMultiplier: Int { EngagementConfig.getVisualHypeMultiplier(for: userTier, isBurst: true) }
    private var isDisabled: Bool { shouldBlockSelfEngagement || hasHitEngagementCap }
    
    var body: some View {
        ZStack {
            buttonBase
            flameIcon
            hypeCountDisplay
            
            if shouldBlockSelfEngagement { selfEngagementOverlay }
            if showingBurstIndicator && isBurstEligible { burstChargeOverlay }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .rotation3DEffect(.degrees(isPressed ? 5 : 0), axis: (x: 1, y: 0, z: 0))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .opacity(isDisabled ? 0.5 : 1.0)
        // 🆕 Regular tap = standard engagement
        .onTapGesture {
            handleTap(isBurst: false)
        }
        // 🆕 Long press = burst engagement (premium tiers get full multiplier)
        .onLongPressGesture(
            minimumDuration: EngagementConfig.longPressDuration,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = pressing
                    showingBurstIndicator = pressing && isBurstEligible && !isDisabled
                }
            },
            perform: {
                handleTap(isBurst: true)
            }
        )
        .disabled(isDisabled)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    buttonPosition = CGPoint(
                        x: geo.frame(in: .global).midX,
                        y: geo.frame(in: .global).midY
                    )
                }
            }
        )
        .overlay(errorMessageOverlay)
        .onAppear { startPulseAnimation() }
    }
    
    // MARK: - Button Components
    
    private var buttonBase: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { layer in
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.black.opacity(0.1), Color.black.opacity(0.3)],
                        center: .center, startRadius: 0, endRadius: 25
                    ))
                    .frame(width: 42, height: 42)
                    .offset(x: CGFloat(layer) * 1.5, y: CGFloat(layer) * 1.5)
                    .opacity(0.4 - Double(layer) * 0.1)
            }
            
            Circle()
                .fill(RadialGradient(
                    colors: shouldBlockSelfEngagement
                        ? [Color.gray.opacity(0.4), Color.black.opacity(0.7), Color.black.opacity(0.9)]
                        : [Color.black.opacity(0.4), Color.black.opacity(0.7), Color.black.opacity(0.9)],
                    center: .topLeading, startRadius: 0, endRadius: 30
                ))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: shouldBlockSelfEngagement ? [.gray, .gray.opacity(0.6)]
                                : showingBurstIndicator ? [.yellow, .orange, .red]
                                : isProcessing ? [.orange, .red, .yellow]
                                : [.orange.opacity(0.6), .red.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: showingBurstIndicator ? 3.0 : isProcessing ? 2.0 : 1.5
                    )
                    .opacity(0.8 + sin(pulsePhase) * 0.2)
                )
                .shadow(
                    color: shouldBlockSelfEngagement ? .gray.opacity(0.3)
                        : showingBurstIndicator ? .yellow.opacity(0.6)
                        : .orange.opacity(0.3),
                    radius: 4, x: 0, y: 2
                )
        }
    }
    
    private var flameIcon: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: shouldBlockSelfEngagement ? "flame.slash.fill" : "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [.black.opacity(0.6), .black.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .offset(x: CGFloat(layer) * 1, y: CGFloat(layer) * 1)
                    .opacity(0.3 - Double(layer) * 0.1)
            }
            
            Image(systemName: shouldBlockSelfEngagement ? "flame.slash.fill" : "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LinearGradient(
                    colors: shouldBlockSelfEngagement ? [.gray, .gray.opacity(0.7), .black.opacity(0.5)]
                        : showingBurstIndicator ? [.white, .yellow, .orange, .red]
                        : [.yellow, .orange, .red, .black.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: shouldBlockSelfEngagement ? .gray : showingBurstIndicator ? .yellow : .orange, radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)
                .scaleEffect(shouldBlockSelfEngagement ? 1.0 : showingBurstIndicator ? 1.3 : (1.0 + sin(pulsePhase * 2) * 0.1))
        }
    }
    
    private var hypeCountDisplay: some View {
        Text("\(currentHypeCount)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            .offset(y: -35)
    }
    
    private var selfEngagementOverlay: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50)
                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
            Image(systemName: "person.fill.xmark")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }.scaleEffect(1.1)
    }
    
    
    // 🆕 Burst charge indicator - glowing ring while long pressing
    private var burstChargeOverlay: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.yellow, .orange, .red, .orange, .yellow],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(pulsePhase * 20))
            
            Text("BURST")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.yellow)
                .offset(y: 30)
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    private var errorMessageOverlay: some View {
        EmptyView()
    }
    
    // MARK: - Actions
    
    /// 🆕 Unified tap handler - isBurst determines regular vs burst engagement
    private func handleTap(isBurst: Bool) {
        let mode = isBurst ? "BURST" : "regular"
        print("🔴 HYPE TAP (\(mode)) - videoID: \(videoID), tier: \(userTier)")
        
        showingBurstIndicator = false
        
        if shouldBlockSelfEngagement {
            showError("You can't hype your own content")
            triggerErrorHaptic()
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
        
        let status = engagementManager.getHypeRatingStatus()
        guard status.canEngage else {
            showError("Hype rating too low - wait for regeneration")
            triggerErrorHaptic()
            return
        }
        
        // Haptic: heavy for burst, medium for regular
        let impact = UIImpactFeedbackGenerator(style: isBurst ? .heavy : .medium)
        impact.impactOccurred()
        
        let isFirstEngagement = engagementState.hypeEngagements == 0
        
        // 🆕 Spawn particles based on engagement type
        if isBurst && isBurstEligible {
            // Burst: spawn multiple flames (scaled to tier)
            iconManager.spawnMultipleIcons(
                from: buttonPosition,
                count: min(burstMultiplier / 4, 5),
                iconType: .hype,
                animationType: .founderExplosion,
                userTier: userTier
            )
        } else {
            // Regular tap: single flame
            iconManager.spawnHypeIcon(
                from: buttonPosition,
                userTier: userTier,
                isFirstFounderTap: false
            )
        }
        
        // 🆕 Process engagement with burst flag
        Task {
            do {
                let success = try await engagementManager.processHype(
                    videoID: videoID,
                    userID: currentUserID,
                    userTier: userTier,
                    creatorID: creatorID,
                    isBurst: isBurst
                )
                
                await MainActor.run {
                    if success {
                        let successImpact = UIImpactFeedbackGenerator(style: isBurst ? .rigid : .light)
                        successImpact.impactOccurred()
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
    
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showingError = false }
    }
    
    private func triggerErrorHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    private func startPulseAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            pulsePhase += 0.2
        }
    }
}
