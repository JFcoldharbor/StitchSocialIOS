//
//  CustomDippedTabBar.swift
//  CleanBeta
//
//  Layer 8: Views - Custom Dipped Tab Bar (Compact Version)
//  Dependencies: Layer 1 (Foundation)
//  Custom tab bar with dipped center for create button - 50% smaller with enhanced icons
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

/// Custom tab bar with dipped center for create button - COMPACT VERSION
/// 50% smaller with enhanced icon visibility and detail
struct CustomDippedTabBar: View {
    
    // MARK: - Properties
    
    @Binding var selectedTab: MainAppTab
    let onTabSelected: (MainAppTab) -> Void
    let onCreateTapped: () -> Void
    
    // MARK: - Private State
    
    @State private var tabBarHeight: CGFloat = 70 // Increased from 33 for better proportions
    @State private var tabBarOffset: CGFloat = 0
    @State private var createButtonScale: CGFloat = 1.0
    
    // MARK: - COMPACT Tab Bar Configuration
    
    private let tabBarCornerRadius: CGFloat = 18 // Slightly larger for better look
    private let dippedRadius: CGFloat = 16 // Small dip for create button
    private let createButtonSize: CGFloat = 56 // Smaller create button
    private let tabItemSize: CGFloat = 40 // Larger icons for visibility
    
    var body: some View {
        ZStack {
            // Tab bar background with dipped center
            tabBarBackground
            
            // Tab items
            HStack {
                // Left side tabs
                Spacer()
                
                ForEach(MainAppTab.leftSideTabs, id: \.self) { tab in
                    TabBarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
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
                
                // Right side tabs
                ForEach(MainAppTab.rightSideTabs, id: \.self) { tab in
                    if tab == MainAppTab.rightSideTabs.first {
                        Spacer()
                    }
                    
                    TabBarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        onTap: {
                            handleTabSelection(tab)
                        }
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: tabBarHeight)
            
            // Floating create button
            createButton
        }
        .frame(height: tabBarHeight)
        .offset(y: tabBarOffset + 35) // Push much further down beyond screen edge
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarOffset)
        .ignoresSafeArea(.all) // Flush to bottom, ignore safe area
    }
    
    // MARK: - Tab Bar Background
    
    private var tabBarBackground: some View {
        ZStack {
            // Main tab bar shape with dip
            DippedTabBarShape(dippedRadius: dippedRadius)
                .fill(
                    // Glassmorphism background
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    // Blur effect base
                    .ultraThinMaterial,
                    in: DippedTabBarShape(dippedRadius: dippedRadius)
                )
                .overlay(
                    // Inner glow
                    DippedTabBarShape(dippedRadius: dippedRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .clipShape(DippedTabBarShape(dippedRadius: dippedRadius))
            
            // Outer border with subtle glow
            DippedTabBarShape(dippedRadius: dippedRadius)
                .stroke(
                    Color.white.opacity(0.2),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 12,
            x: 0,
            y: 6
        )
        .shadow(
            color: StitchColors.primary.opacity(0.15),
            radius: 18,
            x: 0,
            y: 3
        )
    }
    
    // MARK: - Create Button (COMPACT)
    
    private var createButton: some View {
        VStack {
            Spacer()
            
            Button(action: handleCreateTap) {
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    StitchColors.primary.opacity(0.9),
                                    StitchColors.secondary.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: createButtonSize + 8, height: createButtonSize + 8)
                        .blur(radius: 1.2)
                    
                    // Glassmorphism background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                        .overlay(
                            // Inner gradient
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            StitchColors.primary.opacity(0.95),
                                            StitchColors.secondary.opacity(1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 0.6)
                        )
                        .overlay(
                            // Glass border
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.4),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .frame(width: createButtonSize, height: createButtonSize)
                    
                    // Plus icon with enhanced styling
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .shadow(color: StitchColors.primary.opacity(0.7), radius: 4)
                }
            }
            .scaleEffect(createButtonScale)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: createButtonScale)
            .shadow(
                color: StitchColors.primary.opacity(0.7),
                radius: 14,
                x: 0,
                y: 5
            )
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 10,
                x: 0,
                y: 8
            )
            .offset(y: -25) // Push create button up more to stay visible
            
            Spacer()
                .frame(height: 2) // Very minimal spacer
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
        
        // Animation feedback
        withAnimation(.easeInOut(duration: 0.1)) {
            tabBarOffset = 1.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                tabBarOffset = 0
            }
        }
    }
    
    private func handleCreateTap() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Button animation
        withAnimation(.easeInOut(duration: 0.1)) {
            createButtonScale = 0.88
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                createButtonScale = 1.0
            }
        }
        
        // Trigger recording modal
        onCreateTapped()
    }
}

// MARK: - Enhanced Tab Bar Item

struct TabBarItem: View {
    let tab: MainAppTab
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Enhanced icon with better visibility
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 22, weight: .medium)) // Much larger icons
                    .foregroundColor(isSelected ? .white : StitchColors.textSecondary)
                    .shadow(
                        color: isSelected ? .white.opacity(0.3) : .clear,
                        radius: 2
                    )
                
                // Larger, more readable text
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white : StitchColors.textSecondary)
                    .shadow(
                        color: isSelected ? .black.opacity(0.3) : .clear,
                        radius: 1
                    )
            }
            .padding(.horizontal, 8) // Reduced padding
            .padding(.vertical, 4) // Reduced padding
            .background(
                Group {
                    if isSelected {
                        // Enhanced glassmorphism background for selected tab
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                // Inner glow
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                StitchColors.primary.opacity(0.4),
                                                StitchColors.secondary.opacity(0.25)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .blur(radius: 1)
                            )
                            .overlay(
                                // Enhanced glass border
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.2),
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(
                                color: StitchColors.primary.opacity(0.4),
                                radius: 8,
                                x: 0,
                                y: 2
                            )
                    } else if isPressed {
                        // Enhanced subtle press effect
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                            )
                    }
                }
            )
        }
        .frame(minWidth: 65) // Larger touch targets
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            // Add press animation
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
            
            onTap()
        }
    }
}

// MARK: - Enhanced Dipped Tab Bar Shape

struct DippedTabBarShape: Shape {
    let dippedRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let cornerRadius: CGFloat = 18
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let dippedWidth = dippedRadius * 2.8
        
        // Start from top-left
        path.move(to: CGPoint(x: cornerRadius, y: 0))
        
        // Top edge to dip start
        path.addLine(to: CGPoint(x: centerX - dippedWidth/2, y: 0))
        
        // Create the dip for center button (more pronounced)
        path.addQuadCurve(
            to: CGPoint(x: centerX + dippedWidth/2, y: 0),
            control: CGPoint(x: centerX, y: dippedRadius * 1.2)
        )
        
        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: width - cornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: width, y: cornerRadius),
            control: CGPoint(x: width, y: 0)
        )
        
        // Right edge
        path.addLine(to: CGPoint(x: width, y: height))
        
        // Bottom edge
        path.addLine(to: CGPoint(x: 0, y: height))
        
        // Left edge
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
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
