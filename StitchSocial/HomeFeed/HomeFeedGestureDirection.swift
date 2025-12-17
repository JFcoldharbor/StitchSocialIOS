//
//  HomeFeedGestureHandler.swift
//  StitchSocial
//
//  Layer 8: Views - Pure Gesture Handling for HomeFeed
//  Dependencies: SwiftUI
//  Features: Butter-smooth drag detection, direction locking, no dead zones
//

import SwiftUI

// MARK: - Gesture Direction

enum HomeFeedGestureDirection {
    case none
    case vertical
    case horizontal
}

// MARK: - Gesture Result

enum HomeFeedGestureResult {
    case none
    case verticalUp
    case verticalDown
    case horizontalLeft
    case horizontalRight
}

// MARK: - Gesture State

struct HomeFeedGestureState {
    var dragOffset: CGSize = .zero
    var direction: HomeFeedGestureDirection = .none
    var isActive: Bool = false
}

// MARK: - Gesture Handler

class HomeFeedGestureHandler: ObservableObject {
    
    // MARK: - Published State
    
    @Published var gestureState = HomeFeedGestureState()
    
    // MARK: - Private State
    
    private var direction: HomeFeedGestureDirection = .none
    
    // MARK: - Configuration
    
    private let directionLockThreshold: CGFloat = 3  // Instant direction detection
    private let directionLockRatio: CGFloat = 1.3     // 30% more in one direction = lock
    private let commitThreshold: CGFloat = 40         // Distance to commit swipe
    private let velocityBoost: CGFloat = 0.2          // How much velocity affects commit
    
    // MARK: - Callbacks
    
    var onSwipeCommitted: ((HomeFeedGestureResult) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    
    // MARK: - Can Swipe Horizontal Check
    
    var canSwipeHorizontal: (() -> Bool)?
    
    // MARK: - Drag Handlers
    
    func handleDragChanged(translation: CGSize) {
        // Notify drag started (only once)
        if !gestureState.isActive {
            gestureState.isActive = true
            onDragStarted?()
        }
        
        let absWidth = abs(translation.width)
        let absHeight = abs(translation.height)
        
        // INSTANT direction detection - no dead zone
        if direction == .none && (absWidth > directionLockThreshold || absHeight > directionLockThreshold) {
            if absWidth > absHeight * directionLockRatio {
                direction = .horizontal
            } else if absHeight > absWidth * directionLockRatio {
                direction = .vertical
            }
        }
        
        // Apply direction-locked drag with FULL 1:1 feedback - no resistance!
        if direction == .horizontal {
            // Check if horizontal swipe is allowed
            if canSwipeHorizontal?() == true {
                gestureState.dragOffset = CGSize(width: translation.width, height: 0)
            } else {
                // No children, use vertical
                gestureState.dragOffset = CGSize(width: 0, height: translation.height)
            }
        } else if direction == .vertical {
            gestureState.dragOffset = CGSize(width: 0, height: translation.height)
        } else {
            // Before direction lock, show FULL feedback based on dominant direction
            // This eliminates the "dead zone" sticky feeling
            if absWidth > absHeight {
                if canSwipeHorizontal?() == true {
                    gestureState.dragOffset = CGSize(width: translation.width, height: 0)
                } else {
                    gestureState.dragOffset = CGSize(width: 0, height: translation.height)
                }
            } else {
                gestureState.dragOffset = CGSize(width: 0, height: translation.height)
            }
        }
        
        gestureState.direction = direction
    }
    
    func handleDragEnded(translation: CGSize, velocity: CGSize) {
        defer {
            // INSTANT reset - no animation conflicts
            gestureState.dragOffset = .zero
            gestureState.isActive = false
            gestureState.direction = .none
            direction = .none
            onDragEnded?()
        }
        
        // Calculate effective distance with velocity boost
        let absWidth = abs(translation.width)
        let absHeight = abs(translation.height)
        
        let effectiveWidth = absWidth + abs(velocity.width) * velocityBoost
        let effectiveHeight = absHeight + abs(velocity.height) * velocityBoost
        
        // Determine swipe result based on direction and threshold
        let result: HomeFeedGestureResult
        
        if direction == .horizontal && effectiveWidth > commitThreshold {
            result = translation.width < 0 ? .horizontalLeft : .horizontalRight
        } else if direction == .vertical && effectiveHeight > commitThreshold {
            result = translation.height < 0 ? .verticalUp : .verticalDown
        } else {
            result = .none
        }
        
        // Notify result
        onSwipeCommitted?(result)
    }
    
    // MARK: - Reset
    
    func reset() {
        gestureState = HomeFeedGestureState()
        direction = .none
    }
}
