//
//  ProfileAnimations.swift
//  StitchSocial
//
//  Created by James Garmon on 8/18/25.
//


//
//  ProfileAnimations.swift
//  CleanBeta
//
//  Layer 8: Views - Animation System for Profile Components
//  Dependencies: SwiftUI Foundation
//  Features: Coordinated animation timings for Instagram-style profile
//

import SwiftUI

/// Centralized animation system for profile view components
struct ProfileAnimations {
    
    // MARK: - Profile Header Animations
    
    /// Profile image entrance with spring effect
    static let profileImageSpring = Animation.spring(
        response: 0.8, 
        dampingFraction: 0.6
    ).delay(0.1)
    
    /// Badge collection fade-in animation
    static let badgeFadeIn = Animation.easeInOut(duration: 0.8).delay(0.3)
    
    /// Hype bar fill animation with delay
    static let hypeBarFill = Animation.easeInOut(duration: 1.5).delay(0.8)
    
    /// Progress ring animation for clout display
    static let progressRing = Animation.easeInOut(duration: 2.0).delay(0.5)
    
    /// Action buttons entrance animation
    static let buttonsEntrance = Animation.spring(
        response: 0.6, 
        dampingFraction: 0.7
    ).delay(1.2)
    
    // MARK: - Interactive Animations
    
    /// Shimmer effect for progress bars
    static let shimmerEffect = Animation.linear(duration: 2.0)
        .repeatForever(autoreverses: false)
    
    /// Liquid wave animation for clout display
    static let liquidWave = Animation.linear(duration: 2.0)
        .repeatForever(autoreverses: false)
    
    /// Tab switching animation
    static let tabSwitch = Animation.spring(
        response: 0.3, 
        dampingFraction: 0.7
    )
    
    /// Scroll-based sticky animations
    static let stickyAppearance = Animation.easeInOut(duration: 0.3)
    
    // MARK: - Content Animations
    
    /// Video grid appearance
    static let gridAppearance = Animation.easeInOut(duration: 0.6).delay(0.2)
    
    /// Loading state transitions
    static let loadingTransition = Animation.easeInOut(duration: 0.4)
    
    /// Profile data updates
    static let dataUpdate = Animation.easeInOut(duration: 0.5)
    
    // MARK: - Micro-Animations
    
    /// Button press feedback
    static let buttonPress = Animation.easeInOut(duration: 0.15)
    
    /// Badge tap interaction
    static let badgeTap = Animation.spring(
        response: 0.4, 
        dampingFraction: 0.6
    )
    
    /// Profile image tap
    static let imageTap = Animation.spring(
        response: 0.5, 
        dampingFraction: 0.7
    )
}

/// Animation timing constants for consistent behavior
struct ProfileTimings {
    
    // MARK: - Entrance Sequence
    
    /// Initial load sequence timing
    static let entranceSequence: [TimeInterval] = [0.1, 0.3, 0.5, 0.8, 1.2]
    
    /// Staggered content loading delays
    static let contentStagger: TimeInterval = 0.1
    
    /// Profile header complete animation duration
    static let headerComplete: TimeInterval = 2.0
    
    // MARK: - Interactive Timings
    
    /// Tab switch response time
    static let tabResponse: TimeInterval = 0.3
    
    /// Scroll animation duration
    static let scrollResponse: TimeInterval = 0.2
    
    /// Sheet presentation timing
    static let sheetPresentation: TimeInterval = 0.4
    
    // MARK: - Continuous Effects
    
    /// Shimmer cycle duration
    static let shimmerCycle: TimeInterval = 2.0
    
    /// Liquid wave cycle
    static let liquidCycle: TimeInterval = 2.0
    
    /// Progress ring completion
    static let progressComplete: TimeInterval = 2.5
}

/// Animation state management for profile components
@MainActor
class ProfileAnimationController: ObservableObject {
    
    // MARK: - Animation States
    
    @Published var profileImageScale: CGFloat = 0.8
    @Published var badgeOpacity: Double = 0.0
    @Published var hypeBarProgress: CGFloat = 0.0
    @Published var progressRingProgress: CGFloat = 0.0
    @Published var buttonsScale: CGFloat = 0.9
    @Published var cloutLiquidLevel: CGFloat = 0.0
    @Published var shimmerOffset: CGFloat = -200
    @Published var liquidWaveOffset: CGFloat = 0.0
    
    // MARK: - Control Flags
    
    @Published var hasStartedEntrance = false
    @Published var isEntranceComplete = false
    
    // MARK: - Animation Triggers
    
    /// Start the complete profile entrance sequence
    func startEntranceSequence(hypeProgress: CGFloat) {
        guard !hasStartedEntrance else { return }
        hasStartedEntrance = true
        
        // Profile image animation
        withAnimation(ProfileAnimations.profileImageSpring) {
            profileImageScale = 1.0
        }
        
        // Badge fade-in
        withAnimation(ProfileAnimations.badgeFadeIn) {
            badgeOpacity = 1.0
        }
        
        // Hype bar fill
        withAnimation(ProfileAnimations.hypeBarFill) {
            hypeBarProgress = hypeProgress
        }
        
        // Progress ring
        withAnimation(ProfileAnimations.progressRing) {
            progressRingProgress = hypeProgress
        }
        
        // Action buttons
        withAnimation(ProfileAnimations.buttonsEntrance) {
            buttonsScale = 1.0
        }
        
        // Liquid level
        withAnimation(.easeInOut(duration: 2.0).delay(0.5)) {
            cloutLiquidLevel = min(0.8, hypeProgress)
        }
        
        // Start continuous animations
        startContinuousAnimations()
        
        // Mark entrance as complete
        DispatchQueue.main.asyncAfter(deadline: .now() + ProfileTimings.headerComplete) {
            self.isEntranceComplete = true
        }
    }
    
    /// Start continuous background animations
    private func startContinuousAnimations() {
        // Shimmer animation
        Timer.scheduledTimer(withTimeInterval: ProfileTimings.shimmerCycle, repeats: true) { _ in
            self.shimmerOffset = -200
            withAnimation(ProfileAnimations.shimmerEffect) {
                self.shimmerOffset = 300
            }
        }
        
        // Liquid wave animation
        withAnimation(ProfileAnimations.liquidWave) {
            liquidWaveOffset = 20
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                self.liquidWaveOffset += 2
                if self.liquidWaveOffset > 200 {
                    self.liquidWaveOffset = -200
                }
            }
        }
    }
    
    /// Reset all animations to initial state
    func resetAnimations() {
        hasStartedEntrance = false
        isEntranceComplete = false
        profileImageScale = 0.8
        badgeOpacity = 0.0
        hypeBarProgress = 0.0
        progressRingProgress = 0.0
        buttonsScale = 0.9
        cloutLiquidLevel = 0.0
        shimmerOffset = -200
        liquidWaveOffset = 0.0
    }
    
    /// Trigger button press animation
    func animateButtonPress() {
        withAnimation(ProfileAnimations.buttonPress) {
            // Button animation logic would go here
        }
    }
    
    /// Trigger badge interaction
    func animateBadgeTap() {
        withAnimation(ProfileAnimations.badgeTap) {
            // Badge tap animation logic would go here
        }
    }
}