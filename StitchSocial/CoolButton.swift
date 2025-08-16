//
//  ProgressiveCoolButton.swift
//  StitchSocial
//
//  Cool button with anti-trolling protection and single-tap mechanics
//  Integrates with EngagementCoordinator for consistent engagement tracking
//

import SwiftUI

struct ProgressiveCoolButton: View {
    let videoID: String
    let currentCoolCount: Int
    let currentHypeCount: Int
    let onCoolTap: () -> Void
    
    // Engagement Coordinator Integration
    @ObservedObject var engagementCoordinator: EngagementCoordinator
    
    @State private var isPressed = false
    @State private var liquidPhase: CGFloat = 0
    @State private var showingWarning = false
    @State private var userCoolTaps: Int = 0 // Track user's cool taps for anti-trolling
    
    // Anti-trolling thresholds
    private let warningThreshold = 80
    private let blockingThreshold = 100
    
    private var isProcessing: Bool {
        engagementCoordinator.isProcessingTap[videoID] ?? false
    }
    
    private var isWarningLevel: Bool {
        userCoolTaps >= warningThreshold
    }
    
    private var isBlocked: Bool {
        userCoolTaps >= blockingThreshold
    }
    
    // 20:1 ratio progress for hype reduction
    private var reductionProgress: CGFloat {
        CGFloat(userCoolTaps % 20) / 20.0
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 42, height: 42)
                
                // Cool liquid meter (shows 20:1 ratio progress)
                CoolLiquidMeter(
                    reductionProgress: reductionProgress,
                    coolCount: currentCoolCount,
                    phase: liquidPhase,
                    isWarning: isWarningLevel
                )
                .frame(width: 42, height: 42)
                .mask(Circle())
                
                // Dynamic border based on state
                Circle()
                    .stroke(borderGradient, lineWidth: borderWidth)
                    .frame(width: 42, height: 42)
                
                // Snowflake icon
                Image(systemName: "snowflake")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(iconScale)
                
                // Anti-trolling warning indicator
                if isWarningLevel {
                    warningIndicator
                }
                
                // Blocked state overlay
                if isBlocked {
                    blockedOverlay
                }
            }
            .scaleEffect(buttonScale)
            .disabled(isProcessing || isBlocked)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            startLiquidAnimation()
            loadUserCoolTaps()
        }
    }
    
    private func handleTap() {
        guard !isProcessing && !isBlocked else { return }
        
        // Increment user cool tap count
        userCoolTaps += 1
        
        // Check for warning state
        if userCoolTaps >= warningThreshold && userCoolTaps < blockingThreshold {
            showWarning()
        }
        
        // Check for blocking state
        if userCoolTaps >= blockingThreshold {
            showBlocked()
            return
        }
        
        // Button press animation
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            isPressed = true
        }
        
        // Call cool action
        onCoolTap()
        
        // Reset press state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = false
            }
        }
        
        // Haptic feedback based on state
        triggerHapticFeedback()
        
        // Save user cool tap count
        saveUserCoolTaps()
    }
    
    // MARK: - Visual Components
    
    private var warningIndicator: some View {
        VStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
            
            Text("WARNING")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.red)
        }
        .offset(y: -35)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var blockedOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 42, height: 42)
            
            VStack(spacing: 1) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text("BLOCKED")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Dynamic Styling
    
    private var borderGradient: LinearGradient {
        if isBlocked {
            return LinearGradient(
                colors: [Color.red, Color.red.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isWarningLevel {
            return LinearGradient(
                colors: [Color.orange, Color.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.0, green: 0.7, blue: 1.0),
                    Color(red: 0.4, green: 0.8, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderWidth: CGFloat {
        if isBlocked {
            return 3.0
        } else if isWarningLevel {
            return 2.5
        } else if isProcessing {
            return 2.0
        } else {
            return 1.5
        }
    }
    
    private var iconScale: CGFloat {
        if isBlocked {
            return 0.7
        } else if isPressed {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private var buttonScale: CGFloat {
        if isPressed {
            return 0.95
        } else {
            return 1.0
        }
    }
    
    // MARK: - Animations
    
    private func startLiquidAnimation() {
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            liquidPhase = 1.0
        }
    }
    
    private func showWarning() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingWarning = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showingWarning = false
            }
        }
    }
    
    private func showBlocked() {
        // Show blocked state permanently until reset
        print("🚫 COOL: User blocked from cooling due to excessive tapping")
    }
    
    private func triggerHapticFeedback() {
        if isBlocked {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.error)
        } else if isWarningLevel {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        } else {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }
    
    // MARK: - Persistence
    
    private func loadUserCoolTaps() {
        // Load from UserDefaults or other persistence
        userCoolTaps = UserDefaults.standard.integer(forKey: "coolTaps_\(videoID)")
    }
    
    private func saveUserCoolTaps() {
        UserDefaults.standard.set(userCoolTaps, forKey: "coolTaps_\(videoID)")
    }
    
    // Reset function for testing or admin use
    func resetCoolTaps() {
        userCoolTaps = 0
        saveUserCoolTaps()
    }
}

// MARK: - Cool Liquid Meter

struct CoolLiquidMeter: View {
    let reductionProgress: CGFloat // 0.0-1.0 for 20:1 ratio progress
    let coolCount: Int
    let phase: CGFloat
    let isWarning: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                CoolLiquidShape(
                    fillPercentage: reductionProgress,
                    phase: phase
                )
                .fill(liquidGradient)
            }
        }
    }
    
    private var liquidGradient: LinearGradient {
        if isWarning {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.3, blue: 0.0),
                    Color(red: 1.0, green: 0.5, blue: 0.2)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.0, green: 0.5, blue: 1.0),
                    Color(red: 0.3, green: 0.7, blue: 1.0),
                    Color(red: 0.5, green: 0.9, blue: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }
}

// MARK: - Cool Liquid Shape

struct CoolLiquidShape: Shape {
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
        
        // Smaller, gentler waves for cool effect
        let waveHeight: CGFloat = 2.0
        let wavelength = width / 3
        
        for x in stride(from: 0, through: width, by: 2) {
            let relativeX = x / wavelength
            let y = fillHeight + sin((relativeX + phase) * .pi * 2) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}
