//
//  FloatingIconEffect.swift
//  StitchSocial
//
//  Layer 8: UI - TikTok Live Style Floating Icon Animation System
//  Dependencies: SwiftUI, Foundation
//  Features: Floating flames, snowflakes, and other icons with 3D depth effects
//

import SwiftUI
import Foundation

// MARK: - Individual Floating Icon
struct FloatingIcon: View {
    let id = UUID()
    let startPosition: CGPoint
    let iconType: FloatingIconType
    let animationType: IconAnimationType
    let tier: UserTier
    
    @State private var position: CGPoint
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var rotationY: Double = 0
    @State private var isAnimating = false
    
    private let animationDuration: Double = 3.0
    private let floatDistance: CGFloat = 400
    
    init(startPosition: CGPoint, iconType: FloatingIconType, animationType: IconAnimationType, tier: UserTier) {
        self.startPosition = startPosition
        self.iconType = iconType
        self.animationType = animationType
        self.tier = tier
        self._position = State(initialValue: startPosition)
    }
    
    var body: some View {
        ZStack {
            // 3D Icon with depth effects
            iconWithDepth
            
            // Tier badge for high-tier users
            if shouldShowTierBadge {
                tierBadge
            }
            
            // Special explosion effects
            if animationType == .founderExplosion {
                explosionEffect
            }
        }
        .position(position)
        .opacity(opacity)
        .onAppear {
            startAnimation()
        }
    }
    
    // MARK: - 3D Icon with Depth
    
    private var iconWithDepth: some View {
        ZStack {
            // Shadow layers for depth
            ForEach(0..<3, id: \.self) { layer in
                Image(systemName: iconSymbol)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(shadowGradient(layer: layer))
                    .scaleEffect(scale * (1.0 - Double(layer) * 0.05))
                    .offset(
                        x: CGFloat(layer) * 2,
                        y: CGFloat(layer) * 2
                    )
                    .opacity(0.3 - Double(layer) * 0.1)
            }
            
            // Main icon with gradient and glow
            Image(systemName: iconSymbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(mainGradient)
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(rotationY),
                    axis: (x: 0, y: 1, z: 0)
                )
                .rotationEffect(.degrees(rotation))
                .shadow(color: glowColor, radius: 8, x: 0, y: 0)
                .shadow(color: shadowColor, radius: 4, x: 2, y: 2)
        }
    }
    
    // MARK: - Visual Properties
    
    private var iconSymbol: String {
        switch iconType {
        case .hype:
            switch animationType {
            case .founderExplosion: return "crown.fill"
            case .tierBoost: return "star.fill"
            case .milestone: return "bolt.fill"
            case .standard: return "flame.fill"
            }
        case .cool:
            switch animationType {
            case .founderExplosion: return "diamond.fill"
            case .tierBoost: return "snowflake"
            case .milestone: return "tornado"
            case .standard: return "snowflake"
            }
        }
    }
    
    private var iconSize: CGFloat {
        switch animationType {
        case .founderExplosion: return 32
        case .tierBoost: return 28
        case .milestone: return 24
        case .standard: return 22
        }
    }
    
    private var mainGradient: LinearGradient {
        switch iconType {
        case .hype:
            switch animationType {
            case .founderExplosion:
                return LinearGradient(
                    colors: [.yellow, .orange, .red, .purple, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .tierBoost:
                return LinearGradient(
                    colors: tierColors + [.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .milestone:
                return LinearGradient(
                    colors: [.cyan, .blue, .purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .standard:
                return LinearGradient(
                    colors: [.yellow, .orange, .red, .black.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
        case .cool:
            switch animationType {
            case .founderExplosion:
                return LinearGradient(
                    colors: [.white, .cyan, .blue, .purple, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .tierBoost:
                return LinearGradient(
                    colors: [.white, .cyan] + tierColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .milestone:
                return LinearGradient(
                    colors: [.white, .cyan, .blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .standard:
                return LinearGradient(
                    colors: [.white, .cyan, .blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private func shadowGradient(layer: Int) -> LinearGradient {
        // Create darker versions of the main gradient colors
        let baseColors: [Color]
        switch iconType {
        case .hype:
            baseColors = [.black.opacity(0.8), .black.opacity(0.6)]
        case .cool:
            baseColors = [.black.opacity(0.6), .blue.opacity(0.4)]
        }
        
        return LinearGradient(
            colors: baseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var tierColors: [Color] {
        switch tier {
        case .founder: return [.purple, .yellow, .orange]
        case .topCreator: return [.blue, .cyan, .white]
        case .legendary: return [.red, .orange, .yellow]
        case .partner: return [.green, .mint, .cyan]
        case .elite: return [.purple, .pink, .red]
        case .influencer: return [.orange, .red, .pink]
        case .veteran: return [.blue, .cyan, .mint]
        case .rising: return [.green, .yellow, .orange]
        case .rookie: return [.orange, .red, .yellow]
        @unknown default: return [.gray, .white]
        }
    }
    
    private var glowColor: Color {
        switch iconType {
        case .hype:
            switch animationType {
            case .founderExplosion: return .purple
            case .tierBoost: return tierColors.first ?? .orange
            case .milestone: return .cyan
            case .standard: return .orange
            }
        case .cool:
            switch animationType {
            case .founderExplosion: return .cyan
            case .tierBoost: return .white
            case .milestone: return .blue
            case .standard: return .cyan
            }
        }
    }
    
    private var shadowColor: Color {
        switch iconType {
        case .hype: return .black.opacity(0.6)
        case .cool: return .blue.opacity(0.4)
        }
    }
    
    private var shouldShowTierBadge: Bool {
        return [.founder, .topCreator, .legendary].contains(tier)
    }
    
    private var tierBadge: some View {
        Text(tier.shortName)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: tierColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
            )
            .offset(y: -20)
    }
    
    private var explosionEffect: some View {
        ZStack {
            // Explosion particles with 3D depth
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                iconType == .hype ? .yellow : .white,
                                iconType == .hype ? .orange : .cyan,
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 8, height: 8)
                    .offset(
                        x: cos(Double(index) * .pi / 6) * 30,
                        y: sin(Double(index) * .pi / 6) * 30
                    )
                    .scaleEffect(isAnimating ? 3.0 : 0.1)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .shadow(color: glowColor, radius: 4, x: 0, y: 0)
            }
            
            // Ring explosion
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [glowColor, glowColor.opacity(0.5), .clear],
                        startPoint: .center,
                        endPoint: .trailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 4.0 : 0.1)
                .opacity(isAnimating ? 0.0 : 0.8)
        }
    }
    
    // MARK: - Animation
    
    private func startAnimation() {
        // Random horizontal drift with physics
        let horizontalDrift = CGFloat.random(in: -60...60)
        let verticalVariation = CGFloat.random(in: -20...20)
        let endPosition = CGPoint(
            x: startPosition.x + horizontalDrift,
            y: startPosition.y - floatDistance + verticalVariation
        )
        
        // Main floating animation with easing
        withAnimation(.easeOut(duration: animationDuration)) {
            position = endPosition
            opacity = 0.0
        }
        
        // Scale animation (pop in, then shrink out)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            scale = 1.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: animationDuration - 0.4)) {
                scale = 0.6
            }
        }
        
        // 3D rotation animation
        withAnimation(.linear(duration: animationDuration)) {
            rotation = iconType == .hype ? 360 : -360
        }
        
        // Y-axis rotation for 3D flip effect
        withAnimation(.easeInOut(duration: 1.5).repeatCount(2, autoreverses: true)) {
            rotationY = 180
        }
        
        // Special effects for explosions
        if animationType == .founderExplosion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.2)) {
                    isAnimating = true
                }
            }
        }
    }
}

// MARK: - Icon Types
enum FloatingIconType {
    case hype    // Flames and fire-related icons
    case cool    // Snowflakes and ice-related icons
}

// MARK: - Animation Types
enum IconAnimationType {
    case standard        // Normal engagement
    case founderExplosion // Founder user special effect
    case tierBoost       // High-tier user effect
    case milestone       // Milestone reached effect
}

// MARK: - Floating Icon Manager
class FloatingIconManager: ObservableObject {
    @Published var activeIcons: [FloatingIcon] = []
    private var cleanupTimer: Timer?
    
    init() {
        // Clean up expired icons every 2 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.cleanupExpiredIcons()
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Spawn an icon from button position
    func spawnIcon(
        from buttonPosition: CGPoint,
        iconType: FloatingIconType,
        animationType: IconAnimationType,
        userTier: UserTier
    ) {
        let icon = FloatingIcon(
            startPosition: buttonPosition,
            iconType: iconType,
            animationType: animationType,
            tier: userTier
        )
        
        DispatchQueue.main.async {
            self.activeIcons.append(icon)
        }
        
        // Auto-remove after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            self.removeIcon(icon)
        }
    }
    
    /// Spawn multiple icons for special effects
    func spawnMultipleIcons(
        from buttonPosition: CGPoint,
        count: Int,
        iconType: FloatingIconType,
        animationType: IconAnimationType,
        userTier: UserTier
    ) {
        for i in 0..<count {
            // Staggered spawning with position variation
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                let offsetPosition = CGPoint(
                    x: buttonPosition.x + CGFloat.random(in: -15...15),
                    y: buttonPosition.y + CGFloat.random(in: -8...8)
                )
                
                self.spawnIcon(
                    from: offsetPosition,
                    iconType: iconType,
                    animationType: animationType,
                    userTier: userTier
                )
            }
        }
    }
    
    /// Spawn icon for hype engagement
    func spawnHypeIcon(from position: CGPoint, userTier: UserTier, isFirstFounderTap: Bool = false) {
        let animationType: IconAnimationType
        let count: Int
        
        if isFirstFounderTap {
            animationType = .founderExplosion
            count = 5 // Explosion of flames
        } else if [.founder, .topCreator, .legendary].contains(userTier) {
            animationType = .tierBoost
            count = 3
        } else {
            animationType = .standard
            count = 1
        }
        
        if count > 1 {
            spawnMultipleIcons(
                from: position,
                count: count,
                iconType: .hype,
                animationType: animationType,
                userTier: userTier
            )
        } else {
            spawnIcon(
                from: position,
                iconType: .hype,
                animationType: animationType,
                userTier: userTier
            )
        }
    }
    
    /// Spawn icon for cool engagement
    func spawnCoolIcon(from position: CGPoint, userTier: UserTier, isFirstFounderTap: Bool = false) {
        let animationType: IconAnimationType
        let count: Int
        
        if isFirstFounderTap {
            animationType = .founderExplosion
            count = 5 // Explosion of snowflakes
        } else if [.founder, .topCreator, .legendary].contains(userTier) {
            animationType = .tierBoost
            count = 3
        } else {
            animationType = .standard
            count = 1
        }
        
        if count > 1 {
            spawnMultipleIcons(
                from: position,
                count: count,
                iconType: .cool,
                animationType: animationType,
                userTier: userTier
            )
        } else {
            spawnIcon(
                from: position,
                iconType: .cool,
                animationType: animationType,
                userTier: userTier
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func removeIcon(_ icon: FloatingIcon) {
        DispatchQueue.main.async {
            self.activeIcons.removeAll { $0.id == icon.id }
        }
    }
    
    private func cleanupExpiredIcons() {
        // Remove excess icons if too many accumulate
        if activeIcons.count > 75 {
            let toRemove = activeIcons.count - 75
            activeIcons.removeFirst(toRemove)
        }
    }
}

// MARK: - Floating Icon Overlay View
struct FloatingIconOverlay: View {
    @ObservedObject var iconManager: FloatingIconManager
    
    var body: some View {
        ZStack {
            ForEach(iconManager.activeIcons, id: \.id) { icon in
                icon
            }
        }
        .allowsHitTesting(false) // Don't block touches
    }
}

// MARK: - UserTier Extension
extension UserTier {
    var shortName: String {
        switch self {
        case .founder: return "FND"
        case .topCreator: return "TOP"
        case .legendary: return "LEG"
        case .partner: return "PAR"
        case .elite: return "ELT"
        case .influencer: return "INF"
        case .veteran: return "VET"
        case .rising: return "RSG"
        case .rookie: return "ROK"
        @unknown default: return "UNK"
        }
    }
}
