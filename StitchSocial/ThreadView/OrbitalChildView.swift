//
//  OrbitalChildView.swift
//  StitchSocial
//
//  Layer 8: Views - Individual Child Response Circles in Orbital Layout
//  Dependencies: ChildThreadData (from OrbitalLayoutCalculator)
//  Features: Tap selection, visual states, engagement indicators, stepchild counts
//  ARCHITECTURE COMPLIANT: Pure UI component, no business logic
//

import SwiftUI

/// Individual child response circle in the orbital interface
struct OrbitalChildView: View {
    
    // MARK: - Properties
    
    let childData: ChildThreadData?
    let position: OrbitalPosition
    let isSelected: Bool
    let onTap: ((ChildThreadData) -> Void)?
    
    // MARK: - State
    
    @State private var isPressed = false
    @State private var pulseAnimation = false
    @State private var rotationAnimation = 0.0
    
    // MARK: - Computed Properties
    
    private var circleSize: CGFloat {
        position.visualState.circleSize
    }
    
    private var borderColor: Color {
        switch position.visualState.borderColor {
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .cyan
        }
    }
    
    private var shouldShowBadge: Bool {
        position.visualState.showsBadge
    }
    
    private var stepchildIndicator: String {
        if position.stepchildCount == 0 {
            return ""
        } else if position.stepchildCount <= 5 {
            return "•"
        } else if position.stepchildCount <= 10 {
            return "\(position.stepchildCount)"
        } else {
            return "⚠️"
        }
    }
    
    private var stepchildIndicatorColor: Color {
        if position.stepchildCount <= 5 {
            return .orange
        } else if position.stepchildCount <= 10 {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Main circle
            mainCircleView
            
            // Selection ring
            if isSelected {
                selectionRingView
            }
            
            // Stepchild indicator
            if position.stepchildCount > 0 {
                stepchildIndicatorView
            }
            
            // Max interactions badge
            if shouldShowBadge {
                maxInteractionsBadgeView
            }
            
            // Creator name label (appears on hover/selection)
            if isSelected {
                creatorNameLabel
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0) { pressing in
            isPressed = pressing
        } perform: {
            // Long press action
            handleLongPress()
        }
        .onAppear {
            setupAnimations()
        }
    }
    
    // MARK: - Main Circle View
    
    private var mainCircleView: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: getGradientColors(),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: circleSize
                )
            )
            .frame(width: circleSize, height: circleSize)
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: 2)
                    .frame(width: circleSize, height: circleSize)
            )
            .overlay(
                // Creator initial or icon
                Text(getCreatorInitial())
                    .font(.system(size: circleSize * 0.4, weight: .bold))
                    .foregroundColor(.white)
            )
            .shadow(
                color: borderColor.opacity(0.4),
                radius: pulseAnimation ? 8 : 4,
                x: 0,
                y: 0
            )
            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
            .animation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true),
                value: pulseAnimation
            )
    }
    
    // MARK: - Selection Ring View
    
    private var selectionRingView: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [.purple, .blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 3
            )
            .frame(width: circleSize + 12, height: circleSize + 12)
            .rotationEffect(.degrees(rotationAnimation))
            .animation(
                .linear(duration: 3.0)
                .repeatForever(autoreverses: false),
                value: rotationAnimation
            )
    }
    
    // MARK: - Stepchild Indicator View
    
    private var stepchildIndicatorView: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                if position.stepchildCount <= 5 {
                    // Small dots for low count
                    HStack(spacing: 2) {
                        ForEach(0..<min(position.stepchildCount, 5), id: \.self) { _ in
                            Circle()
                                .fill(stepchildIndicatorColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.bottom, -4)
                    .padding(.trailing, -4)
                } else {
                    // Count in circle for higher counts
                    Text(stepchildIndicator)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(stepchildIndicatorColor)
                                .frame(width: 16, height: 16)
                        )
                        .padding(.bottom, -8)
                        .padding(.trailing, -8)
                }
            }
        }
        .frame(width: circleSize, height: circleSize)
    }
    
    // MARK: - Max Interactions Badge
    
    private var maxInteractionsBadgeView: some View {
        VStack {
            HStack {
                Spacer()
                
                Text("FULL")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                    )
                    .padding(.top, -8)
                    .padding(.trailing, -8)
            }
            
            Spacer()
        }
        .frame(width: circleSize, height: circleSize)
    }
    
    // MARK: - Creator Name Label
    
    private var creatorNameLabel: some View {
        VStack {
            Text(childData?.creatorName ?? "Unknown")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.8))
                )
                .padding(.top, circleSize + 8)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Functions
    
    private func getGradientColors() -> [Color] {
        switch position.visualState {
        case .normal:
            return [.cyan.opacity(0.3), .blue.opacity(0.6)]
        case .highEngagement:
            return [.yellow.opacity(0.3), .orange.opacity(0.6)]
        case .highActivity:
            return [.orange.opacity(0.3), .red.opacity(0.6)]
        case .maxInteractions:
            return [.red.opacity(0.3), .red.opacity(0.8)]
        }
    }
    
    private func getCreatorInitial() -> String {
        guard let childData = childData else { return "?" }
        return String(childData.creatorName.prefix(1)).uppercased()
    }
    
    private func setupAnimations() {
        // Start pulse animation with random delay
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
            pulseAnimation = true
        }
        
        // Start rotation animation for selected state
        if isSelected {
            rotationAnimation = 360
        }
    }
    
    private func handleTap() {
        guard let childData = childData else { return }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Call the tap handler
        onTap?(childData)
    }
    
    private func handleLongPress() {
        guard let childData = childData else { return }
        
        // Stronger haptic feedback for long press
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Could show additional options or info
        print("Long pressed child: \(childData.creatorName)")
    }
}

// MARK: - Interaction State View Modifier

extension OrbitalChildView {
    
    /// Show interaction count overlay
    private var interactionCountOverlay: some View {
        VStack {
            HStack {
                Text("\(position.interactionCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple.opacity(0.8))
                    )
                    .padding(.top, -6)
                    .padding(.leading, -6)
                
                Spacer()
            }
            
            Spacer()
        }
        .frame(width: circleSize, height: circleSize)
        .opacity(isSelected ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            // Normal state
            OrbitalChildView(
                childData: ChildThreadData(from: CoreVideoMetadata.sampleChild1),
                position: OrbitalPosition(
                    childID: "1",
                    position: .zero,
                    radius: 100,
                    angle: 0,
                    ringType: .inner,
                    visualState: .normal,
                    stepchildCount: 3,
                    interactionCount: 8
                ),
                isSelected: false,
                onTap: { _ in }
            )
            
            // High engagement state
            OrbitalChildView(
                childData: ChildThreadData(from: CoreVideoMetadata.sampleChild2),
                position: OrbitalPosition(
                    childID: "2",
                    position: .zero,
                    radius: 150,
                    angle: 1.57,
                    ringType: .middle,
                    visualState: .highEngagement,
                    stepchildCount: 7,
                    interactionCount: 18
                ),
                isSelected: true,
                onTap: { _ in }
            )
            
            // Max interactions state
            OrbitalChildView(
                childData: ChildThreadData(from: CoreVideoMetadata.sampleChild3),
                position: OrbitalPosition(
                    childID: "3",
                    position: .zero,
                    radius: 200,
                    angle: 3.14,
                    ringType: .outer,
                    visualState: .maxInteractions,
                    stepchildCount: 10,
                    interactionCount: 20
                ),
                isSelected: false,
                onTap: { _ in }
            )
        }
    }
}

// MARK: - Sample Data for Preview

extension CoreVideoMetadata {
    static let sampleChild1 = CoreVideoMetadata.childReply(
        to: "thread-1",
        title: "Sample Child 1",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-1",
        creatorName: "Alice",
        duration: 15.0,
        fileSize: 1024
    )
    
    static let sampleChild2 = CoreVideoMetadata.childReply(
        to: "thread-1",
        title: "Sample Child 2",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-2",
        creatorName: "Bob",
        duration: 20.0,
        fileSize: 2048
    ).withUpdatedEngagement(hypeCount: 15, coolCount: 3)
    
    static let sampleChild3 = CoreVideoMetadata.childReply(
        to: "thread-1",
        title: "Sample Child 3",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-3",
        creatorName: "Charlie",
        duration: 18.0,
        fileSize: 1536
    ).withUpdatedEngagement(hypeCount: 18, coolCount: 2, replyCount: 10)
}
