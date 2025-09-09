//
//  MultidirectionalSwipeGesture.swift
//  StitchSocial
//
//  Layer 8: Views - Ultra-Responsive Gesture Handler
//  Dependencies: SwiftUI
//  Features: <50ms response, prediction, butter-smooth animations
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
    let responseMultiplier: Double // New: amplifies small movements
    
    static let ultraResponsive = GestureConfig(
        minimumDistance: 3,         // Detect immediately
        directionThreshold: 8,      // Lock direction instantly
        activationThreshold: 25,    // Minimal movement for feedback
        commitThreshold: 45,        // Lower commit threshold
        velocityThreshold: 250,     // Lower velocity threshold
        buttonProtectionZones: [
            CGRect(x: 0.8, y: 0.2, width: 0.2, height: 0.6) // Right side protection
        ],
        enableDirectionLocking: true,
        enableHaptics: true,
        enableVisualFeedback: true,
        enablePrediction: true,
        sensitivity: 2.2,           // Higher sensitivity
        responseMultiplier: 1.6     // Amplify small movements
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
        responseMultiplier: 1.4
    )
}

// MARK: - Ultra-Responsive Gesture Implementation

struct MultidirectionalSwipeGesture {
    let config: GestureConfig
    let onSwipe: (GestureResult) -> Void
    let onFeedback: ((VisualFeedback) -> Void)?
    
    @State private var currentDirection: GestureDirection = .none
    @State private var dragOffset: CGSize = .zero
    @State private var isGestureActive = false
    @State private var hasProvidedHaptic = false
    @State private var gestureStartTime: CFAbsoluteTime = 0
    @State private var velocityHistory: [CGVector] = []
    @State private var lastTranslation: CGSize = .zero
    @State private var frameCount: Int = 0
    
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

// MARK: - Ultra-Smooth Gesture Implementation

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
    
    private func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy) {
        // Performance: Skip if in protected zone
        if isInProtectedZone(startLocation: value.startLocation, geometry: geometry) {
            return
        }
        
        // Track gesture start time for velocity calculations
        if gestureStartTime == 0 {
            gestureStartTime = CFAbsoluteTimeGetCurrent()
            frameCount = 0
        }
        
        frameCount += 1
        
        let translation = value.translation
        
        // Apply sensitivity and response multiplier for ultra-responsiveness
        let amplifiedTranslation = CGSize(
            width: translation.width * config.sensitivity * config.responseMultiplier,
            height: translation.height * config.sensitivity * config.responseMultiplier
        )
        
        dragOffset = amplifiedTranslation
        
        // Calculate real-time velocity
        let velocity = calculateVelocity(
            current: translation,
            previous: lastTranslation,
            timeDelta: 1.0/60.0 // Assume 60fps
        )
        
        // Update velocity history for smoothing
        updateVelocityHistory(velocity)
        
        // Ultra-fast direction detection
        if currentDirection == .none {
            detectDirectionFast(translation: amplifiedTranslation, velocity: velocity)
        }
        
        // Instant activation detection
        let wasActive = isGestureActive
        isGestureActive = shouldActivateGesture(translation: amplifiedTranslation, velocity: velocity)
        
        // Immediate haptic feedback
        if config.enableHaptics && isGestureActive && !wasActive && !hasProvidedHaptic {
            lightHaptic()
            hasProvidedHaptic = true
        }
        
        // Real-time visual feedback with prediction
        if config.enableVisualFeedback {
            let progress = calculateProgress(translation: amplifiedTranslation, velocity: velocity)
            let shouldCommit = shouldCommitGesture(translation: amplifiedTranslation, velocity: velocity)
            let predictedDirection = config.enablePrediction ? predictSwipeDirection(
                translation: amplifiedTranslation,
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
        
        lastTranslation = translation
    }
    
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        defer {
            // Ultra-smooth reset
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                resetGestureState()
            }
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
        
        // Determine swipe result with velocity consideration
        let result = determineSwipeResult(translation: amplifiedTranslation, velocity: velocity)
        
        // Log performance metrics
        let gestureTime = CFAbsoluteTimeGetCurrent() - gestureStartTime
        let avgFrameTime = gestureTime / Double(frameCount)
        
        if result != .none {
            // Success haptic
            if config.enableHaptics {
                successHaptic()
            }
            
            print("⚡ ULTRA GESTURE: \(result.description) - \(String(format: "%.1f", gestureTime * 1000))ms, \(String(format: "%.1f", avgFrameTime * 1000))ms/frame")
            onSwipe(result)
        } else {
            // Cancelled haptic
            if config.enableHaptics && isGestureActive {
                cancelHaptic()
            }
        }
    }
    
    // MARK: - Ultra-Fast Direction Detection
    
    private func detectDirectionFast(translation: CGSize, velocity: CGVector) {
        let horizontalMovement = abs(translation.width)
        let verticalMovement = abs(translation.height)
        let horizontalVelocity = abs(velocity.dx)
        let verticalVelocity = abs(velocity.dy)
        
        // Use both movement and velocity for instant detection
        let horizontalScore = horizontalMovement + (horizontalVelocity * 0.1)
        let verticalScore = verticalMovement + (verticalVelocity * 0.1)
        
        if verticalScore > config.directionThreshold && verticalScore > horizontalScore * 0.6 {
            currentDirection = .vertical
        } else if horizontalScore > config.directionThreshold && horizontalScore > verticalScore * 0.6 {
            currentDirection = .horizontal
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
        if velocityHistory.count > 5 { // Keep last 5 frames for smoothing
            velocityHistory.removeFirst()
        }
    }
    
    private func getSmoothedVelocity() -> CGVector {
        guard !velocityHistory.isEmpty else { return CGVector.zero }
        
        let avgDx = velocityHistory.map { $0.dx }.reduce(0, +) / Double(velocityHistory.count)
        let avgDy = velocityHistory.map { $0.dy }.reduce(0, +) / Double(velocityHistory.count)
        
        return CGVector(dx: avgDx, dy: avgDy)
    }
    
    // MARK: - Enhanced Gesture Logic
    
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
    
    private func calculateProgress(translation: CGSize, velocity: CGVector) -> Double {
        let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
        let speed = sqrt(pow(velocity.dx, 2) + pow(velocity.dy, 2))
        
        // Combine distance and velocity for responsive progress
        let distanceProgress = min(1.0, distance / (config.commitThreshold * 1.2))
        let velocityProgress = min(1.0, speed / (config.velocityThreshold * 2.0))
        
        return max(distanceProgress, velocityProgress * 0.7)
    }
    
    // MARK: - Gesture Prediction
    
    private func predictSwipeDirection(translation: CGSize, velocity: CGVector) -> GestureResult? {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        let horizontalVelocity = abs(velocity.dx)
        let verticalVelocity = abs(velocity.dy)
        
        // Predict based on current trajectory
        let horizontalScore = horizontalDistance + (horizontalVelocity * 0.05)
        let verticalScore = verticalDistance + (verticalVelocity * 0.05)
        
        if horizontalScore > verticalScore && horizontalScore > config.activationThreshold * 0.5 {
            return translation.width < 0 ? .horizontalLeft : .horizontalRight
        } else if verticalScore > config.activationThreshold * 0.5 {
            return translation.height < 0 ? .verticalUp : .verticalDown
        }
        
        return nil
    }
    
    private func determineSwipeResult(translation: CGSize, velocity: CGVector) -> GestureResult {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        let horizontalVelocity = abs(velocity.dx)
        let verticalVelocity = abs(velocity.dy)
        
        // Lower thresholds for ultra-responsiveness
        let meetsDistanceThreshold = horizontalDistance > config.commitThreshold || verticalDistance > config.commitThreshold
        let meetsVelocityThreshold = horizontalVelocity > config.velocityThreshold || verticalVelocity > config.velocityThreshold
        
        guard meetsDistanceThreshold || meetsVelocityThreshold else {
            return .none
        }
        
        // Use locked direction for consistent behavior
        if config.enableDirectionLocking && currentDirection != .none {
            switch currentDirection {
            case .vertical:
                return translation.height < 0 ? .verticalUp : .verticalDown
            case .horizontal:
                return translation.width < 0 ? .horizontalLeft : .horizontalRight
            case .none:
                break
            }
        }
        
        // Fallback: determine by movement + velocity
        let horizontalScore = horizontalDistance + (horizontalVelocity * 0.1)
        let verticalScore = verticalDistance + (verticalVelocity * 0.1)
        
        if verticalScore > horizontalScore {
            return translation.height < 0 ? .verticalUp : .verticalDown
        } else {
            return translation.width < 0 ? .horizontalLeft : .horizontalRight
        }
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
        frameCount = 0
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
                .animation(.easeOut(duration: 0.15), value: currentFeedback.isActive)
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
                
                // Direction indicators with prediction
                HStack {
                    if currentFeedback.dragOffset.width > 0 || currentFeedback.predictedDirection == .horizontalRight {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 18, weight: .medium))
                    }
                    Spacer()
                    if currentFeedback.dragOffset.width < 0 || currentFeedback.predictedDirection == .horizontalLeft {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .padding(.horizontal, 30)
                
                VStack {
                    if currentFeedback.dragOffset.height > 0 || currentFeedback.predictedDirection == .verticalDown {
                        Image(systemName: "chevron.up")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 18, weight: .medium))
                    }
                    Spacer()
                    if currentFeedback.dragOffset.height < 0 || currentFeedback.predictedDirection == .verticalUp {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .padding(.vertical, 40)
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
