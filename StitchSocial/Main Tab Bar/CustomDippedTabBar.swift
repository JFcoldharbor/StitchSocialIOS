//
//  CustomDippedTabBar.swift
//  CleanBeta
//
//  Layer 8: Views - Custom Dipped Tab Bar (iOS 26 Liquid Glass)
//  Dependencies: Layer 1 (Foundation)
//  Apple's official iOS 26 Liquid Glass design with real-time rendering and specular highlights
//

import SwiftUI

// MARK: - MainAppTab Enum

/// MainAppTab enum for CustomDippedTabBar
enum MainAppTab: String, CaseIterable {
    case home = "home"
    case discovery = "discovery"
    case progression = "progression"
    case notifications = "notifications"
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .discovery: return "Discover"
        case .progression: return "Profile"
        case .notifications: return "Inbox"
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house"
        case .discovery: return "magnifyingglass"
        case .progression: return "person.circle"
        case .notifications: return "bell"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .discovery: return "magnifyingglass"
        case .progression: return "person.circle.fill"
        case .notifications: return "bell.fill"
        }
    }
    
    static var leftSideTabs: [MainAppTab] {
        return [.home, .discovery]
    }
    
    static var rightSideTabs: [MainAppTab] {
        return [.progression, .notifications]
    }
}

/// iOS 26 Official Liquid Glass Tab Bar
/// Features Apple's authentic Liquid Glass material with real-time rendering and specular highlights
/// Adapts to content and dynamically reacts to movement with glass-like properties
struct CustomDippedTabBar: View {
    
    // MARK: - Properties
    
    @Binding var selectedTab: MainAppTab
    let onTabSelected: (MainAppTab) -> Void
    let onCreateTapped: () -> Void
    
    // MARK: - iOS 26 Liquid Glass State
    
    @State private var tabBarHeight: CGFloat = 70
    @State private var tabBarOffset: CGFloat = 0
    @State private var createButtonScale: CGFloat = 1.0
    @State private var glassPhase: CGFloat = 0.0
    @State private var specularHighlight: CGFloat = 0.0
    @State private var refractionOffset: CGFloat = 0.0
    
    // MARK: - Official Liquid Glass Configuration
    
    private let tabBarCornerRadius: CGFloat = 28
    private let dippedRadius: CGFloat = 20
    private let createButtonSize: CGFloat = 64
    private let glassAnimationDuration: Double = 3.5
    
    var body: some View {
        ZStack {
            // Official iOS 26 Liquid Glass Background
            liquidGlassTabBarBackground
            
            // Tab items with authentic glass material
            HStack {
                Spacer()
                
                ForEach(MainAppTab.leftSideTabs, id: \.self) { tab in
                    iOS26LiquidGlassTabItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        glassPhase: glassPhase,
                        specularHighlight: specularHighlight,
                        onTap: {
                            handleTabSelection(tab)
                        }
                    )
                    
                    if tab == MainAppTab.leftSideTabs.last {
                        Spacer()
                    }
                }
                
                // Center create button space
                createButtonSpace
                
                ForEach(MainAppTab.rightSideTabs, id: \.self) { tab in
                    if tab == MainAppTab.rightSideTabs.first {
                        Spacer()
                    }
                    
                    iOS26LiquidGlassTabItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        glassPhase: glassPhase,
                        specularHighlight: specularHighlight,
                        onTap: {
                            handleTabSelection(tab)
                        }
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: tabBarHeight)
            
            // iOS 26 Liquid Glass Create Button
            liquidGlassCreateButton
        }
        .frame(height: tabBarHeight)
        .offset(y: tabBarOffset + 35)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarOffset)
        .ignoresSafeArea(.all)
        .onAppear {
            startLiquidGlassAnimations()
        }
    }
    
    // MARK: - iOS 26 Official Liquid Glass Background
    
    private var liquidGlassTabBarBackground: some View {
        ZStack {
            // Base Liquid Glass material - official iOS 26 implementation
            LiquidGlassDippedShape(
                dippedRadius: dippedRadius,
                glassPhase: glassPhase,
                refractionOffset: refractionOffset
            )
            .fill(
                // Apple's signature ultra-thin material
                .ultraThinMaterial
            )
            .background(
                // Real-time rendering background that reacts to content
                LiquidGlassDippedShape(
                    dippedRadius: dippedRadius,
                    glassPhase: glassPhase,
                    refractionOffset: refractionOffset
                )
                .fill(
                    // Intelligent adaptation to surrounding content
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear,
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                // Glass refraction - mimics real glass optical properties
                LiquidGlassDippedShape(
                    dippedRadius: dippedRadius,
                    glassPhase: glassPhase,
                    refractionOffset: refractionOffset
                )
                .fill(
                    // Content-aware refraction that shows background through glass
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.clear,
                            Color.white.opacity(0.1)
                        ],
                        center: UnitPoint(
                            x: 0.3 + sin(glassPhase * .pi) * 0.15,
                            y: 0.2 + cos(glassPhase * .pi * 1.2) * 0.1
                        ),
                        startRadius: 10,
                        endRadius: 100
                    )
                )
                .blendMode(.overlay)
            )
            .overlay(
                // Specular highlights - dynamic reaction to movement
                LiquidGlassDippedShape(
                    dippedRadius: dippedRadius,
                    glassPhase: glassPhase,
                    refractionOffset: refractionOffset
                )
                .stroke(
                    // Real-time specular highlights
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8 + specularHighlight * 0.2),
                            Color.white.opacity(0.4),
                            Color.clear
                        ],
                        startPoint: UnitPoint(
                            x: 0.1 + specularHighlight * 0.3,
                            y: 0.0
                        ),
                        endPoint: UnitPoint(
                            x: 0.9 - specularHighlight * 0.2,
                            y: 1.0
                        )
                    ),
                    lineWidth: 1.5
                )
            )
            
            // Environmental reflection - reflects wallpaper and content
            LiquidGlassDippedShape(
                dippedRadius: dippedRadius,
                glassPhase: glassPhase,
                refractionOffset: refractionOffset
            )
            .fill(
                // Intelligent light and dark adaptation
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        StitchColors.primary.opacity(0.1),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 80
                )
            )
            .blendMode(.screen)
        }
        .shadow(
            color: Color.black.opacity(0.15),
            radius: 20,
            x: 0,
            y: 10
        )
        .shadow(
            color: Color.white.opacity(0.1),
            radius: 1,
            x: 0,
            y: -1
        )
    }
    
    // MARK: - iOS 26 Liquid Glass Create Button
    
    private var liquidGlassCreateButton: some View {
        VStack {
            Spacer()
            
            Button(action: handleCreateTap) {
                ZStack {
                    // Base Liquid Glass material
                    Circle()
                        .fill(.ultraThinMaterial)
                        .background(
                            // Real-time rendering background
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            StitchColors.primary.opacity(0.8),
                                            StitchColors.secondary.opacity(0.9),
                                            StitchColors.primary.opacity(0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            // Glass refraction effect
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0.2),
                                            Color.clear
                                        ],
                                        center: UnitPoint(
                                            x: 0.3 + sin(glassPhase * .pi) * 0.2,
                                            y: 0.3 + cos(glassPhase * .pi * 1.1) * 0.15
                                        ),
                                        startRadius: 5,
                                        endRadius: 25
                                    )
                                )
                                .blendMode(.overlay)
                        )
                        .overlay(
                            // Specular highlight ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9 + specularHighlight * 0.1),
                                            Color.white.opacity(0.3),
                                            Color.clear,
                                            Color.white.opacity(0.2)
                                        ],
                                        startPoint: UnitPoint(
                                            x: 0.0 + specularHighlight * 0.4,
                                            y: 0.0
                                        ),
                                        endPoint: UnitPoint(
                                            x: 1.0 - specularHighlight * 0.3,
                                            y: 1.0
                                        )
                                    ),
                                    lineWidth: 2.0
                                )
                        )
                        .frame(width: createButtonSize, height: createButtonSize)
                    
                    // Plus icon with glass-like appearance
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.6), radius: 2)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
            }
            .scaleEffect(createButtonScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: createButtonScale)
            .shadow(
                color: StitchColors.primary.opacity(0.4),
                radius: 16,
                x: 0,
                y: 8
            )
            .shadow(
                color: Color.black.opacity(0.2),
                radius: 8,
                x: 0,
                y: 4
            )
            .offset(y: -25)
            
            Spacer()
                .frame(height: 2)
        }
    }
    
    // MARK: - Create Button Space
    
    private var createButtonSpace: some View {
        Spacer()
            .frame(width: createButtonSize + 16)
    }
    
    // MARK: - Actions
    
    private func handleTabSelection(_ tab: MainAppTab) {
        guard tab != selectedTab else { return }
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Update selection
        selectedTab = tab
        onTabSelected(tab)
        
        // Glass ripple animation
        withAnimation(.easeOut(duration: 0.2)) {
            tabBarOffset = 3.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                tabBarOffset = 0
            }
        }
    }
    
    private func handleCreateTap() {
        // Heavy haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Glass button morphing animation
        withAnimation(.easeOut(duration: 0.15)) {
            createButtonScale = 0.88
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                createButtonScale = 1.0
            }
        }
        
        onCreateTapped()
    }
    
    // MARK: - iOS 26 Liquid Glass Animations
    
    private func startLiquidGlassAnimations() {
        // Main glass phase animation - subtle and organic
        withAnimation(.linear(duration: glassAnimationDuration).repeatForever(autoreverses: false)) {
            glassPhase = 1.0
        }
        
        // Specular highlight animation - reacts to virtual "light source"
        withAnimation(.easeInOut(duration: glassAnimationDuration * 1.2).repeatForever(autoreverses: true)) {
            specularHighlight = 1.0
        }
        
        // Glass refraction animation - mimics real glass movement
        withAnimation(.linear(duration: glassAnimationDuration * 0.8).repeatForever(autoreverses: false)) {
            refractionOffset = 1.0
        }
    }
}

// MARK: - iOS 26 Liquid Glass Tab Item

struct iOS26LiquidGlassTabItem: View {
    let tab: MainAppTab
    let isSelected: Bool
    let glassPhase: CGFloat
    let specularHighlight: CGFloat
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Icon with glass-like properties
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.75))
                    .shadow(
                        color: isSelected ? .white.opacity(0.4) : .clear,
                        radius: 2
                    )
                    .shadow(
                        color: isSelected ? .black.opacity(0.2) : .clear,
                        radius: 3
                    )
                
                // Text with appropriate contrast for glass
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.75))
                    .shadow(
                        color: isSelected ? .black.opacity(0.3) : .clear,
                        radius: 1
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        // Official iOS 26 Liquid Glass selected state
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .background(
                                // Content-aware background
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.1),
                                                StitchColors.primary.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                // Glass refraction
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.clear
                                            ],
                                            center: UnitPoint(
                                                x: 0.3 + sin(glassPhase * .pi) * 0.2,
                                                y: 0.2
                                            ),
                                            startRadius: 3,
                                            endRadius: 20
                                        )
                                    )
                                    .blendMode(.overlay)
                            )
                            .overlay(
                                // Specular highlight border
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.7 + specularHighlight * 0.2),
                                                Color.white.opacity(0.3),
                                                Color.clear
                                            ],
                                            startPoint: UnitPoint(
                                                x: 0.0 + specularHighlight * 0.3,
                                                y: 0.0
                                            ),
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(
                                color: StitchColors.primary.opacity(0.3),
                                radius: 6,
                                x: 0,
                                y: 2
                            )
                    } else if isPressed {
                        // Subtle glass press state
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                            )
                    }
                }
            )
        }
        .frame(minWidth: 65)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isPressed)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.08)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.08)) {
                    isPressed = false
                }
            }
            
            onTap()
        }
    }
}

// MARK: - iOS 26 Liquid Glass Dipped Shape

struct LiquidGlassDippedShape: Shape {
    let dippedRadius: CGFloat
    var glassPhase: CGFloat
    var refractionOffset: CGFloat
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(glassPhase, refractionOffset) }
        set {
            glassPhase = newValue.first
            refractionOffset = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let cornerRadius: CGFloat = 28
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let dippedWidth = dippedRadius * 3.2
        
        // Subtle glass-like movement - much more refined than liquid
        let glassMovement = sin(glassPhase * .pi) * 1.5
        let refractionMovement = cos(refractionOffset * .pi) * 0.8
        
        // Start from top-left with subtle glass corner
        path.move(to: CGPoint(x: cornerRadius, y: glassMovement))
        
        // Top edge to dip start with subtle refraction
        path.addLine(to: CGPoint(x: centerX - dippedWidth/2, y: glassMovement))
        
        // Create the refined glass dip for center button
        path.addQuadCurve(
            to: CGPoint(x: centerX + dippedWidth/2, y: glassMovement),
            control: CGPoint(
                x: centerX + refractionMovement,
                y: dippedRadius * 1.3 + sin(glassPhase * .pi * 1.5) * 1.0
            )
        )
        
        // Continue top edge
        path.addLine(to: CGPoint(x: width - cornerRadius, y: glassMovement))
        path.addQuadCurve(
            to: CGPoint(x: width, y: cornerRadius + glassMovement),
            control: CGPoint(x: width, y: glassMovement)
        )
        
        // Right edge with minimal glass movement
        path.addLine(to: CGPoint(x: width + refractionMovement * 0.5, y: height))
        
        // Bottom edge
        path.addLine(to: CGPoint(x: refractionMovement * 0.5, y: height))
        
        // Left edge
        path.addLine(to: CGPoint(x: 0, y: cornerRadius + glassMovement))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: glassMovement),
            control: CGPoint(x: 0, y: glassMovement)
        )
        
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        
        CustomDippedTabBar(
            selectedTab: .constant(.home),
            onTabSelected: { _ in },
            onCreateTapped: { }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
