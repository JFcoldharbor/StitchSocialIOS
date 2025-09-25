//
//  ProgressiveHypeButton.swift
//  StitchSocial
//
//  Progressive tapping button integrated with EngagementManager
//  Tracks multi-tap sequences with founder mechanics and clout thresholds
//

import SwiftUI

struct ProgressiveHypeButton: View {
    let videoID: String
    let currentHypeCount: Int
    let currentCoolCount: Int
    let currentUserID: String
    let userTier: UserTier
    let onEngagementResult: (EngagementResult) -> Void
    
    // EngagementManager Integration
    @ObservedObject var engagementManager: EngagementManager
    
    @State private var isPressed = false
    @State private var liquidPhase: CGFloat = 0
    @State private var showingProgress = false
    @State private var showingMessage = false
    @State private var resultMessage = ""
    @State private var isProcessing = false
    
    // Computed properties from EngagementManager via EngagementCoordinator
    private var currentTaps: Int {
        engagementManager.engagementCoordinator.currentTaps[videoID] ?? 0
    }
    
    private var requiredTaps: Int {
        engagementManager.engagementCoordinator.requiredTaps[videoID] ?? (userTier == .founder ? 1 : 2)
    }
    
    private var tapProgress: Double {
        engagementManager.engagementCoordinator.tapProgress[videoID] ?? 0.0
    }
    
    // FIXED: Access founderFirstTaps directly since hasFounderUsedFirstTap is private
    private var isFounderFirstTap: Bool {
        if userTier != .founder { return false }
        return !(engagementManager.founderFirstTaps[videoID]?.contains(currentUserID) ?? false)
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 42, height: 42)
                
                // Progressive liquid fill (shows tap progress for regular users, special for founders)
                if userTier == .founder {
                    FounderHypeMeter(
                        isFirstTap: isFounderFirstTap,
                        phase: liquidPhase
                    )
                    .frame(width: 42, height: 42)
                    .mask(Circle())
                } else {
                    ProgressiveLiquidMeter(
                        progressPercentage: tapProgress,
                        hypeCount: currentHypeCount,
                        phase: liquidPhase
                    )
                    .frame(width: 42, height: 42)
                    .mask(Circle())
                }
                
                // Dynamic border based on progress and tier
                Circle()
                    .stroke(borderGradient, lineWidth: borderWidth)
                    .frame(width: 42, height: 42)
                
                // Flame icon with dynamic scaling
                Image(systemName: flameIcon)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(iconScale)
                
                // Tap progress indicator for regular users
                if !userTier.isFounderTier && showingProgress && currentTaps > 0 {
                    progressIndicator
                }
                
                // Founder special indicator
                if userTier == .founder && isFounderFirstTap {
                    founderIndicator
                }
                
                // Processing overlay
                if isProcessing {
                    processingOverlay
                }
            }
            .scaleEffect(buttonScale)
            .disabled(isProcessing)
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(resultMessageOverlay)
        .onAppear {
            startLiquidAnimation()
        }
        .onChange(of: isProcessing) { processing in
            if !processing && showingProgress {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showingProgress = false
                    }
                }
            }
        }
    }
    
    // MARK: - Tap Handling
    
    private func handleTap() {
        guard !isProcessing else { return }
        
        // Visual feedback
        withAnimation(.easeInOut(duration: 0.1)) {
            isPressed = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
        
        // Set processing state
        isProcessing = true
        
        // Haptic feedback
        triggerHapticFeedback()
        
        // Process engagement through EngagementManager
        Task {
            do {
                let result = try await engagementManager.processEngagement(
                    videoID: videoID,
                    engagementType: .hype,
                    userID: currentUserID,
                    userTier: userTier
                )
                
                await MainActor.run {
                    handleEngagementResult(result)
                }
                
            } catch {
                await MainActor.run {
                    print("❌ HYPE BUTTON: Engagement failed - \(error)")
                    isProcessing = false
                    showMessage("Failed to process hype")
                }
            }
        }
    }
    
    private func handleEngagementResult(_ result: EngagementResult) {
        isProcessing = false
        
        // Show result message
        showMessage(result.message)
        
        // Trigger animation based on result type
        switch result.animationType {
        case .founderExplosion:
            triggerFounderExplosion()
        case .standardHype:
            triggerStandardHypeAnimation()
        case .none:
            break
        default:
            break
        }
        
        // Trigger appropriate haptic
        if result.isFounderFirstTap {
            triggerFounderHaptic()
        } else if result.cloutAwarded > 0 {
            triggerSuccessHaptic()
        }
        
        // Notify parent of result
        onEngagementResult(result)
    }
    
    // MARK: - Visual Components
    
    private var progressIndicator: some View {
        VStack(spacing: 1) {
            Text("\(currentTaps)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            
            Text("\(requiredTaps)")
                .font(.system(size: 6, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .offset(y: -35)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var founderIndicator: some View {
        VStack(spacing: 2) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.yellow)
            
            Text("BOOST")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.yellow)
        }
        .offset(y: -35)
        .scaleEffect(1.0 + sin(liquidPhase * CGFloat.pi * 4.0) * 0.1)
    }
    
    private var processingOverlay: some View {
        Circle()
            .fill(Color.black.opacity(0.5))
            .frame(width: 42, height: 42)
            .overlay(
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            )
    }
    
    private var resultMessageOverlay: some View {
        Group {
            if showingMessage {
                messageOverlay
            }
        }
    }
    
    private var messageOverlay: some View {
        Text(resultMessage)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.8))
            )
            .offset(y: -60)
            .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Dynamic Styling
    
    private var borderGradient: LinearGradient {
        if userTier == .founder {
            return LinearGradient(
                colors: [
                    Color.yellow,
                    Color.orange,
                    Color.red
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if tapProgress > 0.75 {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.3, blue: 0.0),
                    Color(red: 1.0, green: 0.5, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if tapProgress > 0.25 {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.6, blue: 0.0),
                    Color(red: 1.0, green: 0.8, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.7, blue: 0.0),
                    Color(red: 1.0, green: 0.9, blue: 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderWidth: CGFloat {
        if userTier == .founder {
            return 3.0
        } else if tapProgress > 0.5 {
            return 2.5
        } else if isProcessing {
            return 2.0
        } else {
            return 1.5
        }
    }
    
    private var flameIcon: String {
        if userTier == .founder {
            return isFounderFirstTap ? "crown.fill" : "flame.fill"
        } else {
            return "flame.fill"
        }
    }
    
    private var iconSize: CGFloat {
        userTier == .founder ? 18 : 20
    }
    
    private var iconScale: CGFloat {
        if userTier == .founder && isFounderFirstTap {
            return 1.0 + sin(liquidPhase * CGFloat.pi * 6.0) * 0.15
        } else if isPressed {
            return 0.8
        } else if tapProgress > 0.75 {
            return 1.1
        } else {
            return 1.0
        }
    }
    
    private var buttonScale: CGFloat {
        if isPressed {
            return 0.95
        } else if userTier == .founder && isFounderFirstTap {
            return 1.0 + sin(liquidPhase * CGFloat.pi * 3.0) * 0.05
        } else {
            return 1.0
        }
    }
    
    // MARK: - Animations
    
    private func startLiquidAnimation() {
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            liquidPhase = 1.0
        }
    }
    
    private func triggerFounderExplosion() {
        // Special founder explosion effect
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            showingProgress = true
        }
        
        // Create particle effect (would need custom particle system)
        print("🎆 FOUNDER EXPLOSION: Massive hype boost effect!")
        
        // Extended display time for founder effects
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.8)) {
                showingProgress = false
            }
        }
    }
    
    private func triggerStandardHypeAnimation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showingProgress = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showingProgress = false
            }
        }
    }
    
    private func showMessage(_ message: String) {
        resultMessage = message
        withAnimation(.easeInOut(duration: 0.3)) {
            showingMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showingMessage = false
            }
        }
    }
    
    private func triggerHapticFeedback() {
        if userTier == .founder {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        } else {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }
    
    private func triggerFounderHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        
        // Double haptic for founder boost
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            notification.notificationOccurred(.success)
        }
    }
    
    private func triggerSuccessHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
}

// MARK: - Founder Hype Meter

struct FounderHypeMeter: View {
    let isFirstTap: Bool
    let phase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.yellow.opacity(0.3),
                                Color.orange.opacity(0.5),
                                Color.red.opacity(0.3)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                
                if isFirstTap {
                    // Special first tap effect - pulsing energy
                    FounderEnergyShape(phase: phase)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.yellow,
                                    Color.orange,
                                    Color.red,
                                    Color.purple
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .opacity(0.8 + sin(phase * CGFloat.pi * 8.0) * 0.2)
                } else {
                    // Regular founder effect
                    ProgressiveLiquidShape(
                        fillPercentage: 0.7,
                        phase: phase
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange,
                                Color.red
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Founder Energy Shape

struct FounderEnergyShape: Shape {
    var phase: CGFloat
    
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let centerY = height / 2
        
        // Create energy burst pattern
        let spikes = 12
        let outerRadius = min(width, height) / 2.0
        let innerRadius = outerRadius * 0.6
        
        for i in 0..<spikes {
            let angle = (CGFloat(i) / CGFloat(spikes)) * 2.0 * CGFloat.pi + phase
            let isSpike = i % 2 == 0
            let radius = isSpike ? outerRadius : innerRadius
            
            let x = centerX + cos(angle) * radius
            let y = centerY + sin(angle) * radius
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Progressive Liquid Meter

struct ProgressiveLiquidMeter: View {
    let progressPercentage: Double
    let hypeCount: Int
    let phase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base background
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                // Liquid fill based on progress
                ProgressiveLiquidShape(
                    fillPercentage: CGFloat(progressPercentage),
                    phase: phase
                )
                .fill(liquidGradient)
            }
        }
    }
    
    private var liquidGradient: LinearGradient {
        let intensity = min(1.0, Double(hypeCount) / 100.0) // Color intensity based on total hypes
        
        if progressPercentage > 0.75 {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.3 + intensity * 0.2, blue: 0.0),
                    Color(red: 1.0, green: 0.5 + intensity * 0.3, blue: 0.1)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        } else if progressPercentage > 0.25 {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.4 + intensity * 0.2, blue: 0.0),
                    Color(red: 1.0, green: 0.6 + intensity * 0.3, blue: 0.1)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.6 + intensity * 0.2, blue: 0.0),
                    Color(red: 1.0, green: 0.8 + intensity * 0.2, blue: 0.2)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }
}

// MARK: - Progressive Liquid Shape

struct ProgressiveLiquidShape: Shape {
    var fillPercentage: CGFloat
    var phase: CGFloat
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(fillPercentage, phase) }
        set {
            fillPercentage = newValue.first
            phase = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let fillHeight = height * (1.0 - fillPercentage)
        
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: fillHeight))
        
        // Dynamic waves based on fill percentage
        let waveHeight: CGFloat = fillPercentage > 0.5 ? 4.0 : 2.0
        let wavelength = width / 2.0
        
        for x in stride(from: 0, through: width, by: 2) {
            let relativeX = x / wavelength
            let y = fillHeight + sin((relativeX + phase) * CGFloat.pi * 2.0) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}
