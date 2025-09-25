//
//  FloatingBubbleNotification.swift
//  CleanBeta
//
//  Layer 8: Views - Universal Floating Bubble Notification for Thread Navigation
//  Dependencies: SwiftUI, UIKit (haptics)
//  Features: Universal thread navigation hints, context-aware messaging, configurable timing
//

import SwiftUI

// MARK: - Navigation Context

enum NavigationContext {
    case discovery
    case homeFeed
    case profile
    case fullscreen
    case thread
    
    var swipeDirection: String {
        switch self {
        case .discovery, .fullscreen: return "left"
        case .homeFeed: return "right"
        case .profile, .thread: return "left"
        }
    }
    
    var actionText: String {
        switch self {
        case .discovery: return "Swipe \(swipeDirection)"
        case .homeFeed: return "Swipe \(swipeDirection)"
        case .profile: return "Tap to explore"
        case .fullscreen: return "Swipe \(swipeDirection)"
        case .thread: return "Swipe \(swipeDirection)"
        }
    }
}

// MARK: - Bubble Configuration

struct BubbleConfig {
    let showDelay: TimeInterval
    let visibilityDuration: TimeInterval
    let reminderDelay: TimeInterval
    let position: BubblePosition
    let style: BubbleStyle
    
    static let discovery = BubbleConfig(
        showDelay: 20.0,
        visibilityDuration: 3.0,
        reminderDelay: 5.0,
        position: .topRight,
        style: .standard
    )
    
    static let homeFeed = BubbleConfig(
        showDelay: 15.0,
        visibilityDuration: 2.5,
        reminderDelay: 4.0,
        position: .topRight,
        style: .minimal
    )
    
    static let profile = BubbleConfig(
        showDelay: 0.0, // Immediate
        visibilityDuration: 2.0,
        reminderDelay: 3.0,
        position: .bottomRight,
        style: .minimal
    )
    
    static let fullscreen = BubbleConfig(
        showDelay: 10.0,
        visibilityDuration: 4.0,
        reminderDelay: 6.0,
        position: .topRight,
        style: .prominent
    )
    
    static let thread = BubbleConfig(
        showDelay: 8.0,
        visibilityDuration: 3.0,
        reminderDelay: 5.0,
        position: .topRight,
        style: .standard
    )
}

enum BubblePosition {
    case topRight, topLeft, bottomRight, bottomLeft, center
}

enum BubbleStyle {
    case minimal, standard, prominent
}

// MARK: - Universal Floating Bubble

struct FloatingBubbleNotification: View {
    // MARK: - Props
    let replyCount: Int
    let context: NavigationContext
    let config: BubbleConfig
    let onDismiss: () -> Void
    let onAction: (() -> Void)?
    
    // MARK: - Convenience Initializers
    init(
        replyCount: Int,
        context: NavigationContext,
        onDismiss: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) {
        self.replyCount = replyCount
        self.context = context
        self.onDismiss = onDismiss
        self.onAction = onAction
        
        // Set config based on context
        switch context {
        case .discovery: self.config = .discovery
        case .homeFeed: self.config = .homeFeed
        case .profile: self.config = .profile
        case .fullscreen: self.config = .fullscreen
        case .thread: self.config = .thread
        }
    }
    
    init(
        replyCount: Int,
        context: NavigationContext,
        config: BubbleConfig,
        onDismiss: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) {
        self.replyCount = replyCount
        self.context = context
        self.config = config
        self.onDismiss = onDismiss
        self.onAction = onAction
    }
    
    // MARK: - State
    @State private var isVisible = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    @State private var offset: CGFloat = -20
    @State private var breathingScale: CGFloat = 1.0
    @State private var showTimer: Timer?
    @State private var dismissTimer: Timer?
    @State private var reminderTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isVisible {
                    bubbleContent
                        .scaleEffect(scale * breathingScale)
                        .opacity(opacity)
                        .offset(
                            x: offsetX(for: geometry.size),
                            y: offsetY(for: geometry.size)
                        )
                }
            }
        }
        .allowsHitTesting(isVisible)
        .onAppear {
            scheduleAppearance()
        }
        .onDisappear {
            cancelTimers()
        }
    }
    
    // MARK: - Bubble Content
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch config.style {
        case .minimal:
            minimalBubble
        case .standard:
            standardBubble
        case .prominent:
            prominentBubble
        }
    }
    
    // MARK: - Bubble Styles
    
    private var minimalBubble: some View {
        HStack(spacing: 6) {
            Text("\(replyCount)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)
            
            Image(systemName: directionIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .stroke(Color.cyan.opacity(0.6), lineWidth: 1)
        )
        .onTapGesture {
            handleTap()
        }
    }
    
    private var standardBubble: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("\(replyCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Text(replyCount == 1 ? "reply" : "replies")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("💭")
                    .font(.system(size: 14))
            }
            
            HStack(spacing: 4) {
                Text(context.actionText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Image(systemName: directionIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .onTapGesture {
            handleTap()
        }
    }
    
    private var prominentBubble: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
                
                Text("\(replyCount) new")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 4) {
                Text(context.actionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Image(systemName: directionIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.cyan)
            }
        }
        .padding(16)
        .background(prominentBackground)
        .onTapGesture {
            handleTap()
        }
    }
    
    // MARK: - Background Styles
    
    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.purple.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.6),
                                Color.purple.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.cyan.opacity(0.3),
                radius: 8,
                x: 0,
                y: 4
            )
    }
    
    private var prominentBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                RadialGradient(
                    colors: [
                        Color.purple.opacity(0.8),
                        Color.black.opacity(0.9)
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 50
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
            )
            .shadow(color: Color.cyan.opacity(0.5), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Computed Properties
    
    private var directionIcon: String {
        switch context.swipeDirection {
        case "left": return "arrow.left"
        case "right": return "arrow.right"
        case "up": return "arrow.up"
        case "down": return "arrow.down"
        default: return "arrow.left"
        }
    }
    
    // MARK: - Positioning
    
    private func offsetX(for size: CGSize) -> CGFloat {
        switch config.position {
        case .topRight, .bottomRight:
            return size.width * 0.4 - offset
        case .topLeft, .bottomLeft:
            return -size.width * 0.4 + offset
        case .center:
            return 0
        }
    }
    
    private func offsetY(for size: CGSize) -> CGFloat {
        switch config.position {
        case .topRight, .topLeft:
            return -size.height * 0.35 + offset
        case .bottomRight, .bottomLeft:
            return size.height * 0.35 - offset
        case .center:
            return 0
        }
    }
    
    // MARK: - Animation Methods
    
    private func scheduleAppearance() {
        // Schedule show with delay
        showTimer = Timer.scheduledTimer(withTimeInterval: config.showDelay, repeats: false) { _ in
            showBubble()
        }
    }
    
    private func showBubble() {
        guard !isVisible else { return }
        
        // Haptic feedback
        triggerHapticFeedback(.light)
        
        // Entrance animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            isVisible = true
            scale = 1.0
            opacity = 1.0
            offset = 0
        }
        
        // Start breathing animation
        startBreathingAnimation()
        
        // Schedule auto-dismiss
        dismissTimer = Timer.scheduledTimer(withTimeInterval: config.visibilityDuration, repeats: false) { _ in
            dismissBubble()
        }
        
        // Schedule reminder pulse
        reminderTimer = Timer.scheduledTimer(withTimeInterval: config.reminderDelay, repeats: false) { _ in
            pulseReminder()
        }
    }
    
    private func dismissBubble() {
        guard isVisible else { return }
        
        cancelTimers()
        
        withAnimation(.easeOut(duration: 0.3)) {
            isVisible = false
            scale = 0.8
            opacity = 0.0
            offset = -20
        }
        
        // Call dismiss callback after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
    
    private func handleTap() {
        // Execute action if provided
        onAction?()
        
        // Dismiss bubble
        dismissBubble()
    }
    
    private func startBreathingAnimation() {
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            breathingScale = 1.05
        }
    }
    
    private func pulseReminder() {
        guard isVisible else { return }
        
        // Haptic feedback for reminder
        triggerHapticFeedback(.medium)
        
        // Quick pulse animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            breathingScale = 1.15
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) {
            breathingScale = 1.0
        }
    }
    
    private func cancelTimers() {
        showTimer?.invalidate()
        dismissTimer?.invalidate()
        reminderTimer?.invalidate()
        showTimer = nil
        dismissTimer = nil
        reminderTimer = nil
    }
    
    // MARK: - Haptic Feedback
    
    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - Public API Extensions

extension FloatingBubbleNotification {
    
    /// Show bubble immediately without delay
    static func immediate(
        replyCount: Int,
        context: NavigationContext,
        onDismiss: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) -> FloatingBubbleNotification {
        var config = BubbleConfig.discovery
        config = BubbleConfig(
            showDelay: 0.0,
            visibilityDuration: config.visibilityDuration,
            reminderDelay: config.reminderDelay,
            position: config.position,
            style: config.style
        )
        
        return FloatingBubbleNotification(
            replyCount: replyCount,
            context: context,
            config: config,
            onDismiss: onDismiss,
            onAction: onAction
        )
    }
    
    /// Show bubble with custom timing
    static func custom(
        replyCount: Int,
        context: NavigationContext,
        showAfter delay: TimeInterval,
        visibleFor duration: TimeInterval,
        style: BubbleStyle = .standard,
        position: BubblePosition = .topRight,
        onDismiss: @escaping () -> Void,
        onAction: (() -> Void)? = nil
    ) -> FloatingBubbleNotification {
        let config = BubbleConfig(
            showDelay: delay,
            visibilityDuration: duration,
            reminderDelay: delay + duration * 0.6,
            position: position,
            style: style
        )
        
        return FloatingBubbleNotification(
            replyCount: replyCount,
            context: context,
            config: config,
            onDismiss: onDismiss,
            onAction: onAction
        )
    }
}

// MARK: - Preview Provider

struct FloatingBubbleNotification_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Discovery context
            ZStack {
                Color.black.ignoresSafeArea()
                FloatingBubbleNotification(
                    replyCount: 3,
                    context: .discovery,
                    onDismiss: { print("Discovery bubble dismissed") }
                )
            }
            .previewDisplayName("Discovery")
            
            // Home feed context
            ZStack {
                Color.black.ignoresSafeArea()
                FloatingBubbleNotification(
                    replyCount: 1,
                    context: .homeFeed,
                    onDismiss: { print("Home feed bubble dismissed") }
                )
            }
            .previewDisplayName("Home Feed")
            
            // Fullscreen context
            ZStack {
                Color.black.ignoresSafeArea()
                FloatingBubbleNotification(
                    replyCount: 5,
                    context: .fullscreen,
                    onDismiss: { print("Fullscreen bubble dismissed") }
                )
            }
            .previewDisplayName("Fullscreen")
        }
    }
}
