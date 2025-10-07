//
//  FloatingBubbleNotification.swift
//  StitchSocial
//
//  Layer 8: Views - Smart Reply Awareness Notification (COMPACT VERSION)
//  Dependencies: SwiftUI, UIKit (haptics)
//  Features: Small, subtle notifications for parent videos with replies
//

// MARK: - SWIPE NOTIFICATION DESIGN - NO AUTO-NAVIGATION
//
// UPDATED APPROACH: Show swipe instructions instead of auto-moving
// - Shows "Swipe → for X replies" message
// - NO countdown timer that auto-navigates
// - NO automatic movement to child videos
// - Users must manually swipe horizontally to see replies
// - Appears at 70% through parent videos with replies
// - Auto-hides after 4 seconds
// - Compact, readable design
//
// NAVIGATION DIRECTIONS:
// - VERTICAL = Thread to Thread (parent to parent)
// - HORIZONTAL = Parent to Child (within same thread)
//
// USER BEHAVIOR:
// 1. Parent video plays
// 2. At 70%, notification shows "Swipe → for 3 replies"
// 3. User sees notification, manually swipes right
// 4. App navigates horizontally to first child video
// 5. User can continue swiping through replies

import SwiftUI

// MARK: - Compact Reply Configuration

struct ReplyNotificationConfig {
    let videoDuration: TimeInterval
    let hasReplies: Bool
    let replyCount: Int
    let currentStitchIndex: Int
    
    /// Only show on parent videos (index 0) with replies - SHOWS SWIPE INSTRUCTION
    var shouldShow: Bool {
        return currentStitchIndex == 0 && hasReplies && replyCount > 0
    }
    
    /// Calculate when to show notification (70% through parent video for more time to read)
    var showTriggerTime: TimeInterval {
        return videoDuration * 0.7
    }
    
    /// Compact countdown duration (always 3 seconds for simplicity)
    var countdownDuration: Int {
        return 3
    }
}

// MARK: - Compact Reply Notification

struct FloatingBubbleNotification: View {
    
    // MARK: - Properties
    
    let config: ReplyNotificationConfig
    let currentVideoPosition: TimeInterval
    let onViewReplies: () -> Void
    let onDismiss: () -> Void
    
    // MARK: - State
    
    @State private var isVisible = false
    @State private var countdownValue: Int = 3
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer?
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    @State private var showingSwipeMessage = false
    
    // MARK: - Computed Properties
    
    private var shouldStartCountdown: Bool {
        return currentVideoPosition >= config.showTriggerTime && config.shouldShow
    }
    
    private var countdownColor: Color {
        switch countdownValue {
        case 3: return .cyan
        case 2: return .yellow
        case 1: return .orange
        case 0: return .green
        default: return .white
        }
    }
    
    private var replyMessage: String {
        if !showingSwipeMessage {
            return "Incoming stitch"
        } else if config.replyCount == 1 {
            return "Swipe → for reply"
        } else {
            return "Swipe → for \(config.replyCount) replies"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        // COMPLETELY NON-BLOCKING: Notification as pure overlay
        if isVisible {
            compactBubbleContent
                .scaleEffect(scale)
                .opacity(opacity)
                .position(
                    x: UIScreen.main.bounds.width * 0.82,
                    y: UIScreen.main.bounds.height * 0.22
                )
                .allowsHitTesting(false)  // Critical: Never block touches
                .animation(.spring(response: 0.3), value: showingSwipeMessage)
                .onAppear {
                    // Start notification sequence when visible
                    if config.shouldShow {
                        startSwipeNotification()
                    }
                }
        }
    }
    
    // MARK: - Compact Bubble Content
    
    private var compactBubbleContent: some View {
        HStack(spacing: 6) {
            // Reply icon with gradient
            Image(systemName: showingSwipeMessage ? "bubble.left.fill" : "scissors")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: showingSwipeMessage ? [.cyan, .blue] : [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Dynamic message
            Text(replyMessage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
            
            // Arrow icon (only show for swipe message)
            if showingSwipeMessage {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.8),
                            Color.purple.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: showingSwipeMessage ? [.cyan, .purple, .pink] : [.orange, .pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: showingSwipeMessage ? .cyan.opacity(0.3) : .orange.opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Logic Methods
    
    private func handleVideoPositionChange(_ position: TimeInterval) {
        if shouldStartCountdown && !isCountingDown {
            startSwipeNotification()
        }
    }
    
    private func startSwipeNotification() {
        guard !isCountingDown else { return }
        guard config.shouldShow else { return }
        
        isCountingDown = true
        showingSwipeMessage = false
        
        // Phase 1: Show "Incoming stitch" message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isVisible = true
            scale = 1.0
            opacity = 1.0
        }
        
        // Phase 2: After 1.5 seconds, change to swipe message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingSwipeMessage = true
            }
        }
        
        // Phase 3: Auto-hide after 5 seconds total (1.5s incoming + 3.5s swipe)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if isVisible {
                hideNotification()
            }
        }
    }
    
    private func hideNotification() {
        withAnimation(.easeOut(duration: 0.3)) {
            opacity = 0.0
            scale = 0.9
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isVisible = false
            cleanup()
        }
    }
    
    private func finishCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        
        // FIXED: No auto-navigation - just show swipe instruction
        // User must manually swipe to see replies
        hideNotification()
    }
    
    private func handleTap() {
        // FIXED: Manual tap shows swipe hint, no auto-navigation
        cleanup()
        
        // Vibrant haptic feedback for colorful app
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Optional: Add a subtle animation to show it was tapped
        withAnimation(.spring(response: 0.2)) {
            scale = 1.1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2)) {
                scale = 1.0
            }
        }
    }
    
    private func cleanup() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        isVisible = false
        showingSwipeMessage = false
    }
}

// MARK: - Factory Methods

extension FloatingBubbleNotification {
    
    /// Create notification for parent video with replies - FIXED NAVIGATION
    static func parentVideoWithReplies(
        videoDuration: TimeInterval,
        currentPosition: TimeInterval,
        replyCount: Int,
        currentStitchIndex: Int,
        onViewReplies: @escaping () -> Void, // SHOULD CALL: coordinator.smoothMoveToStitch(1)
        onDismiss: @escaping () -> Void
    ) -> FloatingBubbleNotification {
        let config = ReplyNotificationConfig(
            videoDuration: videoDuration,
            hasReplies: replyCount > 0,
            replyCount: replyCount,
            currentStitchIndex: currentStitchIndex
        )
        
        return FloatingBubbleNotification(
            config: config,
            currentVideoPosition: currentPosition,
            onViewReplies: onViewReplies,
            onDismiss: onDismiss
        )
    }
    
    /// Create notification from thread data
    static func fromThreadData(
        currentThread: ThreadData,
        currentStitchIndex: Int,
        currentVideoPosition: TimeInterval,
        onViewReplies: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> FloatingBubbleNotification {
        
        let parentVideo = currentThread.parentVideo
        
        return FloatingBubbleNotification.parentVideoWithReplies(
            videoDuration: parentVideo.duration,
            currentPosition: currentVideoPosition,
            replyCount: currentThread.childVideos.count,
            currentStitchIndex: currentStitchIndex,
            onViewReplies: onViewReplies,
            onDismiss: onDismiss
        )
    }
}

// MARK: - Backward Compatibility

extension FloatingBubbleNotification {
    
    static func shortVideo(
        duration: TimeInterval,
        currentPosition: TimeInterval,
        nextStitchTitle: String?,
        nextStitchCreator: String?,
        onStitchRevealed: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> FloatingBubbleNotification {
        
        let config = ReplyNotificationConfig(
            videoDuration: duration,
            hasReplies: nextStitchTitle != nil,
            replyCount: 1,
            currentStitchIndex: 0
        )
        
        return FloatingBubbleNotification(
            config: config,
            currentVideoPosition: currentPosition,
            onViewReplies: onStitchRevealed,
            onDismiss: onDismiss
        )
    }
    
    static func mediumVideo(
        duration: TimeInterval,
        currentPosition: TimeInterval,
        nextStitchTitle: String?,
        nextStitchCreator: String?,
        onStitchRevealed: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> FloatingBubbleNotification {
        
        let config = ReplyNotificationConfig(
            videoDuration: duration,
            hasReplies: nextStitchTitle != nil,
            replyCount: 1,
            currentStitchIndex: 0
        )
        
        return FloatingBubbleNotification(
            config: config,
            currentVideoPosition: currentPosition,
            onViewReplies: onStitchRevealed,
            onDismiss: onDismiss
        )
    }
    
    static func longVideo(
        duration: TimeInterval,
        currentPosition: TimeInterval,
        nextStitchTitle: String?,
        nextStitchCreator: String?,
        onStitchRevealed: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> FloatingBubbleNotification {
        
        let config = ReplyNotificationConfig(
            videoDuration: duration,
            hasReplies: nextStitchTitle != nil,
            replyCount: 1,
            currentStitchIndex: 0
        )
        
        return FloatingBubbleNotification(
            config: config,
            currentVideoPosition: currentPosition,
            onViewReplies: onStitchRevealed,
            onDismiss: onDismiss
        )
    }
}

// MARK: - Preview Provider

struct FloatingBubbleNotification_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            FloatingBubbleNotification.parentVideoWithReplies(
                videoDuration: 30.0,
                currentPosition: 25.0,
                replyCount: 3,
                currentStitchIndex: 0,
                onViewReplies: { print("View replies tapped!") },
                onDismiss: { print("Dismissed!") }
            )
        }
        .previewDisplayName("Parent Video with 3 Replies")
    }
}
