//
//  ProgressiveCoolButton.swift
//  StitchSocial
//
//  Layer 8: UI - Cool Button with 3D Effects and Floating Icons
//  UPDATED: No burst variant for cool - always +1 per tap
//  UPDATED: Self-engagement restriction - only founders can cool their own content
//

import SwiftUI
import Foundation

struct ProgressiveCoolButton: View {
    
    let videoID: String
    let creatorID: String
    let currentCoolCount: Int
    let currentUserID: String
    let userTier: UserTier
    
    @ObservedObject var engagementManager: EngagementManager
    @ObservedObject var iconManager: FloatingIconManager
    
    @State private var isPressed = false
    @State private var buttonPosition: CGPoint = .zero
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var shimmerPhase: Double = 0
    @State private var showingTrollWarning = false
    
    // MARK: - Computed
    
    private var engagementState: VideoEngagementState {
        engagementManager.getEngagementState(videoID: videoID, userID: currentUserID)
    }
    
    private var isProcessing: Bool { engagementManager.isProcessingEngagement }
    private var isSelfEngagement: Bool { currentUserID == creatorID }
    private var isFounderTier: Bool { userTier == .founder || userTier == .coFounder }
    private var shouldBlockSelfEngagement: Bool { isSelfEngagement && !isFounderTier }
    private var hasHitEngagementCap: Bool { engagementState.hasHitEngagementCap() }
    private var isDisabled: Bool { shouldBlockSelfEngagement || hasHitEngagementCap }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                coolButtonBase
                snowflakeIcon
                coolCountDisplay
                
                if shouldBlockSelfEngagement { selfEngagementOverlay }
                if showingTrollWarning { trollWarningOverlay }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .rotation3DEffect(.degrees(isPressed ? -5 : 0), axis: (x: 1, y: 0, z: 0))
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
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
        .onAppear { startShimmerAnimation() }
    }
    
    // MARK: - Button Components
    
    private var coolButtonBase: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { layer in
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.black.opacity(0.1), Color.blue.opacity(0.2)],
                        center: .center, startRadius: 0, endRadius: 25
                    ))
                    .frame(width: 42, height: 42)
                    .offset(x: CGFloat(layer) * 1.5, y: CGFloat(layer) * 1.5)
                    .opacity(0.3 - Double(layer) * 0.075)
            }
            
            Circle()
                .fill(RadialGradient(
                    colors: shouldBlockSelfEngagement
                        ? [Color.gray.opacity(0.4), Color.gray.opacity(0.3), Color.black.opacity(0.8)]
                        : hasHitEngagementCap
                        ? [Color.red.opacity(0.4), Color.blue.opacity(0.3), Color.black.opacity(0.8)]
                        : [Color.black.opacity(0.4), Color.blue.opacity(0.3), Color.black.opacity(0.8)],
                    center: .topLeading, startRadius: 0, endRadius: 30
                ))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: shouldBlockSelfEngagement ? [.gray, .gray.opacity(0.6)]
                                : hasHitEngagementCap ? [.red, .orange]
                                : isProcessing ? [.cyan, .blue, .white]
                                : [.cyan.opacity(0.8), .blue.opacity(0.6), .white.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: isProcessing ? 2.0 : 1.5
                    )
                    .opacity(0.7 + sin(shimmerPhase) * 0.3)
                )
                .shadow(color: shouldBlockSelfEngagement ? .gray.opacity(0.3) : .cyan.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
    
    private var snowflakeIcon: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: shouldBlockSelfEngagement || hasHitEngagementCap ? "snowflake.slash" : "snowflake")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [.black.opacity(0.4), .blue.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .offset(x: CGFloat(layer) * 1, y: CGFloat(layer) * 1)
                    .opacity(0.3 - Double(layer) * 0.1)
            }
            
            Image(systemName: shouldBlockSelfEngagement || hasHitEngagementCap ? "snowflake.slash" : "snowflake")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LinearGradient(
                    colors: shouldBlockSelfEngagement ? [.gray, .gray.opacity(0.7), .black.opacity(0.5)]
                        : hasHitEngagementCap ? [.red, .orange, .black.opacity(0.5)]
                        : [.white, .cyan, .blue, .black.opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: shouldBlockSelfEngagement ? .gray : hasHitEngagementCap ? .red : .cyan, radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                .rotationEffect(.degrees(shouldBlockSelfEngagement || hasHitEngagementCap ? 0 : shimmerPhase * 2))
        }
    }
    
    private var coolCountDisplay: some View {
        Text("\(currentCoolCount)")
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
    
    private var trollWarningOverlay: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.3)).frame(width: 50, height: 50)
                .overlay(Circle().stroke(Color.red, lineWidth: 2))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.red)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }.scaleEffect(1.2).transition(.scale.combined(with: .opacity))
    }
    
    private var cloutCapWarningOverlay: some View {
        EmptyView()
    }
    
    private var errorMessageOverlay: some View {
        EmptyView()
    }
    
    // MARK: - Actions
    
    /// Cool is always regular engagement - no burst variant
    private func handleTap() {
        print("🔵 COOL TAP - videoID: \(videoID), tier: \(userTier)")
        
        if shouldBlockSelfEngagement {
            showError("You can't cool your own content")
            triggerErrorHaptic()
            return
        }
        
        if hasHitEngagementCap {
            showEngagementCapWarning()
            return
        }
        
        withAnimation(.spring(response: 0.1, dampingFraction: 0.6)) {
            isPressed = true
        }
        
        if shouldShowTrollWarning() {
            showTrollWarning()
            return
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Cool always spawns single snowflake - no burst
        iconManager.spawnCoolIcon(
            from: buttonPosition,
            userTier: userTier,
            isFirstFounderTap: false
        )
        
        Task {
            do {
                let success = try await engagementManager.processCool(
                    videoID: videoID,
                    userID: currentUserID,
                    userTier: userTier,
                    creatorID: creatorID
                )
                
                await MainActor.run {
                    if success {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            } catch {
                await MainActor.run { showError(error.localizedDescription) }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { isPressed = false }
        }
    }
    
    private func shouldShowTrollWarning() -> Bool {
        return engagementState.coolEngagements > 10
    }
    
    private func showTrollWarning() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showingTrollWarning = true }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        showError("Excessive cooling detected - please engage thoughtfully")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) { showingTrollWarning = false }
        }
    }
    
    private func showEngagementCapWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { showingError = false }
    }
    
    private func triggerErrorHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    private func startShimmerAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            shimmerPhase += 0.15
        }
    }
}
