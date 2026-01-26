//
//  MultidirectionalSwipeGesture.swift
//  StitchSocial
//
//  Layer 8: Views - Ultra-Responsive Gesture Handler
//  Dependencies: SwiftUI
//  Features: <50ms response, prediction, butter-smooth animations
//  PHASE 3: Improved debouncing, cleaner state management, better conflict resolution
//

import SwiftUI

// MARK: - Gesture Direction Types

enum GestureDirection {
    case none
    case vertical
    case horizontal
}

enum GestureResult {
    case none
    case verticalUp
    case verticalDown
    case horizontalLeft
    case horizontalRight
}

// MARK: - Visual Feedback Types

struct VisualFeedback {
    let dragOffset: CGSize
    let progress: Double // 0.0 to 1.0
    let direction: GestureDirection
    let isActive: Bool
    let shouldCommit: Bool
    let velocity: CGVector
    let predictedDirection: GestureResult?
}

// MARK: - Ultra-Responsive Gesture Configuration

struct GestureConfig {
    let minimumDistance: CGFloat
    let directionThreshold: CGFloat
    let activationThreshold: CGFloat
    let commitThreshold: CGFloat
    let velocityThreshold: CGFloat
    let buttonProtectionZones: [CGRect]
    let enableDirectionLocking: Bool
    let enableHaptics: Bool
    let enableVisualFeedback: Bool
    let enablePrediction: Bool
    let sensitivity: Double
    let responseMultiplier: Double
    
    // PHASE 3: Debouncing configuration
    let debounceInterval: TimeInterval
    let maxGesturesPerSecond: Int
    
    static let ultraResponsive = GestureConfig(
        minimumDistance: 3,
        directionThreshold: 8,
        activationThreshold: 25,
        commitThreshold: 45,
        velocityThreshold: 250,
        buttonProtectionZones: [
            CGRect(x: 0.8, y: 0.2, width: 0.2, height: 0.6) // Right side protection
        ],
        enableDirectionLocking: true,
        enableHaptics: true,
        enableVisualFeedback: true,
        enablePrediction: true,
        sensitivity: 2.2,
        responseMultiplier: 1.6,
        debounceInterval: 0.15,  // PHASE 3: 150ms between gestures
        maxGesturesPerSecond: 5  // PHASE 3: Max 5 swipes/second
    )
    
    static let butterSmooth = ultraResponsive
    static let homeFeed = ultraResponsive
    
    static let discovery = GestureConfig(
        minimumDistance: 5,
        directionThreshold: 12,
        activationThreshold: 30,
        commitThreshold: 50,
        velocityThreshold: 300,
        buttonProtectionZones: [],
        enableDirectionLocking: true,
        enableHaptics: true,
        enableVisualFeedback: true,
        enablePrediction: true,
        sensitivity: 1.8,
        responseMultiplier: 1.4,
        debounceInterval: 0.15,
        maxGesturesPerSecond: 5
    )
}

// MARK: - Ultra-Responsive Gesture Implementation

struct MultidirectionalSwipeGesture {
    let config: GestureConfig
    let onSwipe: (GestureResult) -> Void
    let onFeedback: ((VisualFeedback) -> Void)?
    
    // MARK: - State Management (PHASE 3: Simplified)
    @State private var currentDirection: GestureDirection = .none
    @State private var dragOffset: CGSize = .zero
    @State private var isGestureActive = false
    @State private var hasProvidedHaptic = false
    @State private var gestureStartTime: CFAbsoluteTime = 0
    @State private var velocityHistory: [CGVector] = []
    @State private var lastTranslation: CGSize = .zero
    
    // PHASE 3: Debouncing state
    @State private var lastGestureTime: CFAbsoluteTime = 0
    @State private var gestureCount: Int = 0
    @State private var gestureWindowStart: CFAbsoluteTime = 0
    @State private var isDebouncing = false
    
    init(
        config: GestureConfig = .ultraResponsive,
        onSwipe: @escaping (GestureResult) -> Void,
        onFeedback: ((VisualFeedback) -> Void)? = nil
    ) {
        self.config = config
        self.onSwipe = onSwipe
        self.onFeedback = onFeedback
    }
}

// MARK: - Gesture Implementation

extension MultidirectionalSwipeGesture {
    
    func gesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: config.minimumDistance)
            .onChanged { value in
                handleDragChanged(value: value, geometry: geometry)
            }
            .onEnded { value in
                handleDragEnded(value: value, geometry: geometry)
            }
    }
    
    // MARK: - Drag Changed Handler
    
    private func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy) {
        // PHASE 3: Skip if debouncing
        guard !isDebouncing else { return }
        
        // Performance: Skip if in protected zone
        if isInProtectedZone(startLocation: value.startLocation, geometry: geometry) {
            return
        }
        
        // Track gesture start time
        if gestureStartTime == 0 {
            gestureStartTime = CFAbsoluteTimeGetCurrent()
        }
        
        let translation = value.translation
        
        // Pre-multiplied constant: 2.2 * 1.6 = 3.52
        let amplifiedTranslation = CGSize(
            width: translation.width * 3.52,
            height: translation.height * 3.52
        )
        
        dragOffset = amplifiedTranslation
        
        // Calculate real-time velocity
        let velocity = calculateVelocity(
            current: translation,
            previous: lastTranslation,
            timeDelta: 1.0/60.0
        )
        
        // Update velocity history (keep last 5 samples)
        updateVelocityHistory(velocity)
        
        // Ultra-fast direction detection
        if currentDirection == .none {
            detectDirectionFast(translation: amplifiedTranslation, velocity: velocity)
        }
        
        // Activation detection
        let wasActive = isGestureActive
        isGestureActive = shouldActivateGesture(translation: amplifiedTranslation, velocity: velocity)
        
        // Immediate haptic feedback (only once per gesture)
        if config.enableHaptics && isGestureActive && !wasActive && !hasProvidedHaptic {
            lightHaptic()
            hasProvidedHaptic = true
        }
        
        // Real-time visual feedback
        if config.enableVisualFeedback {
            provideFeedback(translation: amplifiedTranslation, velocity: velocity)
        }
        
        lastTranslation = translation
    }
    
    // MARK: - Drag Ended Handler (PHASE 3: Improved debouncing)
    
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        defer {
            // Ultra-smooth reset
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                resetGestureState()
            }
        }
        
        // PHASE 3: Check debounce before processing
        let currentTime = CFAbsoluteTimeGetCurrent()
        if currentTime - lastGestureTime < config.debounceInterval {
            print("⏸️ GESTURE: Debounced - too fast")
            return
        }
        
        // PHASE 3: Rate limiting - check gestures per second
        if !checkRateLimit(currentTime: currentTime) {
            print("⏸️ GESTURE: Rate limited - too many gestures")
            return
        }
        
        // Skip if in protected zone
        if isInProtectedZone(startLocation: value.startLocation, geometry: geometry) {
            return
        }
        
        let translation = value.translation
        let velocity = getSmoothedVelocity()
        let amplifiedTranslation = CGSize(
            width: translation.width * config.sensitivity * config.responseMultiplier,
            height: translation.height * config.sensitivity * config.responseMultiplier
        )
        
        // Determine swipe result
        let result = determineSwipeResult(translation: amplifiedTranslation, velocity: velocity)
        
        if result != .none {
            // PHASE 3: Update debounce tracking
            lastGestureTime = currentTime
            isDebouncing = true
            
            // Success haptic
            if config.enableHaptics {
                successHaptic()
            }
            
            // Trigger callback
            onSwipe(result)
            
            // PHASE 3: Clear debounce after interval
            DispatchQueue.main.asyncAfter(deadline: .now() + config.debounceInterval) {
                isDebouncing = false
            }
            
            print("✅ GESTURE: \(result.description)")
        } else {
            // Cancelled - soft haptic
            if config.enableHaptics && isGestureActive {
                cancelHaptic()
            }
        }
    }
    
    // MARK: - PHASE 3: Rate Limiting
    
    private func checkRateLimit(currentTime: CFAbsoluteTime) -> Bool {
        // Reset window if more than 1 second has passed
        if currentTime - gestureWindowStart > 1.0 {
            gestureWindowStart = currentTime
            gestureCount = 0
        }
        
        // Increment counter
        gestureCount += 1
        
        // Check if exceeded limit
        if gestureCount > config.maxGesturesPerSecond {
            return false
        }
        
        return true
    }
    
    // MARK: - Feedback Provider (PHASE 3: Cleaned up)
    
    private func provideFeedback(translation: CGSize, velocity: CGVector) {
        let progress = calculateProgress(translation: translation, velocity: velocity)
        let shouldCommit = shouldCommitGesture(translation: translation, velocity: velocity)
        let predictedDirection = config.enablePrediction ? predictSwipeDirection(
            translation: translation,
            velocity: velocity
        ) : nil
        
        let feedback = VisualFeedback(
            dragOffset: dragOffset,
            progress: progress,
            direction: currentDirection,
            isActive: isGestureActive,
            shouldCommit: shouldCommit,
            velocity: velocity,
            predictedDirection: predictedDirection
        )
        
        onFeedback?(feedback)
    }
    
    // MARK: - Direction Detection (PHASE 3: Optimized)
    
    private func detectDirectionFast(translation: CGSize, velocity: CGVector) {
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        
        // Wait for minimum threshold
        guard max(absX, absY) > config.directionThreshold else { return }
        
        // Strong horizontal bias detection
        if absX > absY * 1.3 {
            currentDirection = .horizontal
            print("🔒 GESTURE: Locked horizontal")
        }
        // Strong vertical bias detection
        else if absY > absX * 1.3 {
            currentDirection = .vertical
            print("🔒 GESTURE: Locked vertical")
        }
        // Use velocity as tiebreaker
        else {
            let absVx = abs(velocity.dx)
            let absVy = abs(velocity.dy)
            
            if absVx > absVy {
                currentDirection = .horizontal
                print("🔒 GESTURE: Locked horizontal (velocity)")
            } else {
                currentDirection = .vertical
                print("🔒 GESTURE: Locked vertical (velocity)")
            }
        }
    }
    
    // MARK: - Activation & Commit Logic
    
    private func shouldActivateGesture(translation: CGSize, velocity: CGVector) -> Bool {
        let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
        let speed = sqrt(pow(velocity.dx, 2) + pow(velocity.dy, 2))
        
        return distance > config.activationThreshold || speed > config.velocityThreshold * 0.5
    }
    
    private func shouldCommitGesture(translation: CGSize, velocity: CGVector) -> Bool {
        let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
        let speed = sqrt(pow(velocity.dx, 2) + pow(velocity.dy, 2))
        
        return distance > config.commitThreshold || speed > config.velocityThreshold
    }
    
    // MARK: - Swipe Result Determination (PHASE 3: Clearer logic)
    
    private func determineSwipeResult(translation: CGSize, velocity: CGVector) -> GestureResult {
        // Must be activated first
        guard isGestureActive else { return .none }
        
        // Must meet commit criteria
        guard shouldCommitGesture(translation: translation, velocity: velocity) else {
            return .none
        }
        
        // Determine direction based on locked direction
        switch currentDirection {
        case .horizontal:
            return translation.width > 0 ? .horizontalRight : .horizontalLeft
            
        case .vertical:
            return translation.height > 0 ? .verticalDown : .verticalUp
            
        case .none:
            return .none
        }
    }
    
    // MARK: - Progress Calculation
    
    private func calculateProgress(translation: CGSize, velocity: CGVector) -> Double {
        let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
        let progress = min(1.0, distance / (config.commitThreshold * 1.5))
        return max(0.0, progress)
    }
    
    // MARK: - Prediction (PHASE 3: Simplified)
    
    private func predictSwipeDirection(translation: CGSize, velocity: CGVector) -> GestureResult? {
        let speed = sqrt(pow(velocity.dx, 2) + pow(velocity.dy, 2))
        
        // Only predict if moving fast
        guard speed > config.velocityThreshold * 0.7 else { return nil }
        
        // Predict based on velocity direction
        if abs(velocity.dx) > abs(velocity.dy) {
            return velocity.dx > 0 ? .horizontalRight : .horizontalLeft
        } else {
            return velocity.dy > 0 ? .verticalDown : .verticalUp
        }
    }
    
    // MARK: - Velocity Calculations
    
    private func calculateVelocity(current: CGSize, previous: CGSize, timeDelta: TimeInterval) -> CGVector {
        let dx = (current.width - previous.width) / timeDelta
        let dy = (current.height - previous.height) / timeDelta
        return CGVector(dx: dx, dy: dy)
    }
    
    private func updateVelocityHistory(_ velocity: CGVector) {
        velocityHistory.append(velocity)
        
        // Keep only last 5 samples for smoothing
        if velocityHistory.count > 5 {
            velocityHistory.removeFirst()
        }
    }
    
    private func getSmoothedVelocity() -> CGVector {
        guard !velocityHistory.isEmpty else { return .zero }
        
        // Average last few samples
        let avgDx = velocityHistory.map(\.dx).reduce(0, +) / Double(velocityHistory.count)
        let avgDy = velocityHistory.map(\.dy).reduce(0, +) / Double(velocityHistory.count)
        
        return CGVector(dx: avgDx, dy: avgDy)
    }
    
    // MARK: - Helper Functions
    
    private func isInProtectedZone(startLocation: CGPoint, geometry: GeometryProxy) -> Bool {
        let normalizedPoint = CGPoint(
            x: startLocation.x / geometry.size.width,
            y: startLocation.y / geometry.size.height
        )
        
        return config.buttonProtectionZones.contains { zone in
            zone.contains(normalizedPoint)
        }
    }
    
    private func resetGestureState() {
        currentDirection = .none
        dragOffset = .zero
        isGestureActive = false
        hasProvidedHaptic = false
        gestureStartTime = 0
        velocityHistory.removeAll()
        lastTranslation = .zero
        // Note: Don't reset debounce tracking here
    }
    
    // MARK: - Haptic Feedback
    
    private func lightHaptic() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred(intensity: 0.6)
    }
    
    private func successHaptic() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred(intensity: 0.8)
    }
    
    private func cancelHaptic() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred(intensity: 0.3)
    }
}

// MARK: - Ultra-Responsive ViewModifier

struct MultidirectionalSwipeModifier: ViewModifier {
    let config: GestureConfig
    let onSwipe: (GestureResult) -> Void
    let showVisualFeedback: Bool
    @Binding var dragOffset: CGSize
    
    @State private var currentFeedback = VisualFeedback(
        dragOffset: .zero,
        progress: 0.0,
        direction: .none,
        isActive: false,
        shouldCommit: false,
        velocity: .zero,
        predictedDirection: nil
    )
    @State private var isScrolling = false
    @State private var scrollOffset: CGSize = .zero
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .overlay(
                    visualFeedbackOverlay
                        .allowsHitTesting(false)
                )
                .offset(
                    x: isScrolling ? currentFeedback.dragOffset.width * 0.2 : scrollOffset.width,
                    y: isScrolling ? currentFeedback.dragOffset.height * 0.2 : scrollOffset.height
                )
                .scaleEffect(showVisualFeedback && currentFeedback.shouldCommit ? 0.97 : 1.0)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: scrollOffset)
                .gesture(
                    MultidirectionalSwipeGesture(
                        config: config,
                        onSwipe: { result in
                            handleSwipeWithAnimation(result, geometry: geometry)
                        },
                        onFeedback: { feedback in
                            currentFeedback = feedback
                            isScrolling = feedback.isActive
                            $dragOffset.wrappedValue = feedback.dragOffset
                            
                            if !feedback.isActive {
                                // Ultra-smooth reset
                                withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.9)) {
                                    scrollOffset = .zero
                                }
                            }
                        }
                    ).gesture(in: geometry)
                )
        }
    }
    
    private func handleSwipeWithAnimation(_ result: GestureResult, geometry: GeometryProxy) {
        // Ultra-fast exit animation
        let exitOffset: CGSize
        switch result {
        case .verticalUp:
            exitOffset = CGSize(width: 0, height: -geometry.size.height * 0.7)
        case .verticalDown:
            exitOffset = CGSize(width: 0, height: geometry.size.height * 0.7)
        case .horizontalLeft:
            exitOffset = CGSize(width: -geometry.size.width * 0.7, height: 0)
        case .horizontalRight:
            exitOffset = CGSize(width: geometry.size.width * 0.7, height: 0)
        case .none:
            exitOffset = .zero
        }
        
        if result != .none {
            // Quick exit animation
            withAnimation(.easeOut(duration: 0.2)) {
                scrollOffset = exitOffset
            }
            
            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                scrollOffset = .zero
                onSwipe(result)
            }
        }
    }
    
    @ViewBuilder
    private var visualFeedbackOverlay: some View {
        if showVisualFeedback && currentFeedback.isActive {
            ZStack {
                // Subtle gradient feedback
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: currentFeedback.direction == .horizontal ? .leading : .top,
                    endPoint: currentFeedback.direction == .horizontal ? .trailing : .bottom
                )
                
                // Directional hints - only show when active
                if currentFeedback.direction == .horizontal {
                    HStack {
                        if currentFeedback.dragOffset.width > 0 {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                        if currentFeedback.dragOffset.width < 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 30)
                } else {
                    VStack {
                        if currentFeedback.dragOffset.height > 0 {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                        if currentFeedback.dragOffset.height < 0 {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 40)
                }
            }
            .opacity(currentFeedback.progress * 0.9)
            .scaleEffect(0.9 + (currentFeedback.progress * 0.1))
            .animation(.easeOut(duration: 0.1), value: currentFeedback.progress)
        }
    }
}

// MARK: - Convenience Extension

extension View {
    func multidirectionalSwipe(
        config: GestureConfig = .ultraResponsive,
        showVisualFeedback: Bool = true,
        dragOffset: Binding<CGSize>,
        onSwipe: @escaping (GestureResult) -> Void
    ) -> some View {
        self.modifier(
            MultidirectionalSwipeModifier(
                config: config,
                onSwipe: onSwipe,
                showVisualFeedback: showVisualFeedback,
                dragOffset: dragOffset
            )
        )
    }
}

// MARK: - Debug Helpers

extension GestureResult {
    var description: String {
        switch self {
        case .none: return "none"
        case .verticalUp: return "⬆️ vertical up"
        case .verticalDown: return "⬇️ vertical down"
        case .horizontalLeft: return "⬅️ horizontal left"
        case .horizontalRight: return "➡️ horizontal right"
        }
    }
}

extension GestureDirection {
    var description: String {
        switch self {
        case .none: return "none"
        case .vertical: return "🔄 vertical"
        case .horizontal: return "🔄 horizontal"
        }
    }
}
