//
//  ProgressiveHypeButton.swift
//  StitchSocial
//
//  Progressive tapping button integrated with EngagementCoordinator
//  Tracks multi-tap sequences and shows real-time progress
//

import SwiftUI

struct ProgressiveHypeButton: View {
    let videoID: String
    let currentHypeCount: Int
    let onProgressiveTap: () -> Void
    
    // Engagement Coordinator Integration
    @ObservedObject var engagementCoordinator: EngagementCoordinator
    
    @State private var isPressed = false
    @State private var liquidPhase: CGFloat = 0
    @State private var showingProgress = false
    
    // Computed properties from EngagementCoordinator
    private var currentTaps: Int {
        engagementCoordinator.currentTaps[videoID] ?? 0
    }
    
    private var requiredTaps: Int {
        engagementCoordinator.requiredTaps[videoID] ?? 2
    }
    
    private var tapProgress: Double {
        engagementCoordinator.tapProgress[videoID] ?? 0.0
    }
    
    private var isProcessing: Bool {
        engagementCoordinator.isProcessingTap[videoID] ?? false
    }
    
    private var currentMilestone: TapMilestone? {
        engagementCoordinator.showingMilestone[videoID]
    }
    
    private var currentAnimation: AnimationType? {
        engagementCoordinator.activeAnimations[videoID]
    }
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 42, height: 42)
                
                // Progressive liquid fill (shows tap progress, not hype count)
                ProgressiveLiquidMeter(
                    progressPercentage: tapProgress,
                    hypeCount: currentHypeCount,
                    phase: liquidPhase
                )
                .frame(width: 42, height: 42)
                .mask(Circle())
                
                // Dynamic border based on progress
                Circle()
                    .stroke(borderGradient, lineWidth: borderWidth)
                    .frame(width: 42, height: 42)
                
                // Flame icon with dynamic scaling
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(iconScale)
                
                // Tap progress indicator
                if showingProgress && currentTaps > 0 {
                    progressIndicator
                }
                
                // Milestone celebration overlay
                if let milestone = currentMilestone {
                    milestoneOverlay(milestone)
                }
            }
            .scaleEffect(buttonScale)
            .disabled(isProcessing)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            startLiquidAnimation()
        }
        .onChange(of: currentAnimation) { animation in
            handleAnimationChange(animation)
        }
    }
    
    private func handleTap() {
        guard !isProcessing else { return }
        
        // Show progress indicator
        withAnimation(.easeOut(duration: 0.1)) {
            showingProgress = true
        }
        
        // Button press animation
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            isPressed = true
        }
        
        // Call progressive tap handler
        onProgressiveTap()
        
        // Reset press state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = false
            }
        }
        
        // Hide progress indicator after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingProgress = false
            }
        }
        
        // Haptic feedback based on progress
        triggerHapticFeedback()
    }
    
    // MARK: - Visual Components
    
    private var progressIndicator: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .opacity(tapProgress)
            
            Text("\(currentTaps)/\(requiredTaps)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.7))
                        .padding(-2)
                )
        }
        .offset(y: -35)
        .transition(.scale.combined(with: .opacity))
    }
    
    private func milestoneOverlay(_ milestone: TapMilestone) -> some View {
        VStack {
            Text(milestone.emoji)
                .font(.title)
                .scaleEffect(1.3)
            
            Text(milestone.title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.orange)
        }
        .offset(y: -50)
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Dynamic Styling
    
    private var borderGradient: LinearGradient {
        if tapProgress > 0.75 {
            return LinearGradient(
                colors: [Color.orange, Color.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if tapProgress > 0.25 {
            return LinearGradient(
                colors: [Color.yellow, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderWidth: CGFloat {
        if isProcessing {
            return 3.0
        } else if tapProgress > 0.5 {
            return 2.5
        } else if tapProgress > 0 {
            return 2.0
        } else {
            return 1.5
        }
    }
    
    private var iconScale: CGFloat {
        if currentAnimation == .tapComplete {
            return 1.3
        } else if currentAnimation == .tapMilestone {
            return 1.2
        } else if isPressed {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private var buttonScale: CGFloat {
        if currentAnimation == .tapComplete {
            return 1.1
        } else if isPressed {
            return 0.95
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
    
    private func handleAnimationChange(_ animation: AnimationType?) {
        switch animation {
        case .tapMilestone:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                // Milestone animation handled by iconScale
            }
        case .tapComplete:
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                // Completion animation handled by scaling
            }
        case .tapProgress:
            withAnimation(.easeInOut(duration: 0.3)) {
                // Progress animation
            }
        default:
            break
        }
    }
    
    private func triggerHapticFeedback() {
        if tapProgress >= 1.0 {
            // Completion haptic
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        } else if currentMilestone != nil {
            // Milestone haptic
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } else {
            // Regular tap haptic
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }
}

// MARK: - Progressive Liquid Meter

struct ProgressiveLiquidMeter: View {
    let progressPercentage: Double // 0.0-1.0 for tap progress
    let hypeCount: Int // Total hypes for color variation
    let phase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                ProgressiveLiquidShape(
                    fillPercentage: CGFloat(progressPercentage),
                    phase: phase
                )
                .fill(liquidGradient)
            }
        }
    }
    
    private var liquidGradient: LinearGradient {
        let intensity = min(1.0, Double(hypeCount) / 50.0) // Color intensity based on total hypes
        
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
                    Color(red: 1.0, green: 0.6 + intensity * 0.2, blue: 0.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.5, blue: 0.0),
                    Color(red: 1.0, green: 0.7, blue: 0.1)
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
        
        // Dynamic wave properties based on fill percentage
        let waveHeight: CGFloat = fillPercentage > 0.5 ? 4.0 : 3.0
        let wavelength = fillPercentage > 0.75 ? width / 1.5 : width / 2
        
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

// MARK: - Supporting Types

extension TapMilestone {
    var emoji: String {
        switch self {
        case .quarter: return "🔥"
        case .half: return "🔥🔥"
        case .threeQuarters: return "🔥🔥🔥"
        case .complete: return "✨"
        }
    }
    
    var title: String {
        switch self {
        case .quarter: return "25%"
        case .half: return "50%"
        case .threeQuarters: return "75%"
        case .complete: return "HYPE!"
        }
    }
}
