//
//  CustomDippedTabBar.swift
//  CleanBeta
//
//  Layer 8: Views - Custom Dipped Tab Bar
//  Dependencies: Layer 1 (Foundation)
//  Custom tab bar with dipped center for create button
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

/// Custom tab bar with dipped center for create button
/// Matches CleanStitch design with smooth animations and haptic feedback
/// Clean architecture with proper tab management and state handling
struct CustomDippedTabBar: View {
    
    // MARK: - Properties
    
    @Binding var selectedTab: MainAppTab
    let onTabSelected: (MainAppTab) -> Void
    let onCreateTapped: () -> Void
    
    // MARK: - Private State
    
    @State private var tabBarHeight: CGFloat = 33 // Container 20% smaller (54 * 0.8)
    @State private var tabBarOffset: CGFloat = 0
    @State private var createButtonScale: CGFloat = 1.10
    
    // MARK: - Tab Bar Configuration
    
    private let tabBarCornerRadius: CGFloat = 11 // Container proportionally smaller (14 * 0.8)
    private let dippedRadius: CGFloat = 0 // Container proportionally smaller (24 * 0.8)
    private let createButtonSize: CGFloat = 68 // Keep create button same size
    private let tabItemSize: CGFloat = 30 // Container proportionally smaller
    
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
            .padding(.horizontal, 5) // Container proportionally smaller (11 * 0.8)
            .frame(height: tabBarHeight)
            
            // Floating create button
            createButton
        }
        .frame(height: tabBarHeight)
        .offset(y: tabBarOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarOffset)
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
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.1)
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
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(DippedTabBarShape(dippedRadius: dippedRadius))
            
            // Outer border with subtle glow
            DippedTabBarShape(dippedRadius: dippedRadius)
                .stroke(
                    Color.white.opacity(0.15),
                    lineWidth: 0.5
                )
        }
        .shadow(
            color: Color.black.opacity(0.3),
            radius: 16, // Reduced from 20
            x: 0,
            y: 8 // Reduced from 10
        )
        .shadow(
            color: StitchColors.primary.opacity(0.2),
            radius: 24, // Reduced from 30
            x: 0,
            y: 4 // Reduced from 5
        )
    }
    
    // MARK: - Create Button
    
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
                                    StitchColors.primary.opacity(0.8),
                                    StitchColors.secondary.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.4 // Reduced from 3
                        )
                        .frame(width: createButtonSize + 10, height: createButtonSize + 10) // Reduced from +6
                        .blur(radius: 1.6) // Reduced from 2
                    
                    // Glassmorphism background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
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
                                            StitchColors.primary.opacity(0.9),
                                            StitchColors.secondary.opacity(1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 0.8) // Reduced from 1
                        )
                        .overlay(
                            // Glass border
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8),
                                            Color.white.opacity(0.3),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1 // Reduced from 2
                                )
                        )
                        .frame(width: createButtonSize, height: createButtonSize)
                    
                    // Plus icon with enhanced styling
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold)) // Create button icon bigger (21 * 1.15)
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.8), radius: 2.8) // Proportionally bigger
                        .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5) // Proportionally bigger
                }
            }
            .scaleEffect(createButtonScale)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: createButtonScale)
            .shadow(
                color: StitchColors.primary.opacity(0.6),
                radius: 16, // Reduced from 20
                x: 0,
                y: 6 // Reduced from 8
            )
            .shadow(
                color: Color.black.opacity(0.4),
                radius: 12, // Reduced from 15
                x: 0,
                y: 25 // Reduced from 10
            )
            .offset(y: -10) // Reduced from -12
            
            Spacer()
                .frame(height: 26) // Reduced from 30
        }
    }
    
    // MARK: - Create Button Space
    
    private var createButtonSpace: some View {
        Spacer()
            .frame(width: createButtonSize + 22) // Reduced from +20
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
            tabBarOffset = 2
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
            createButtonScale = 0.85
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

// MARK: - Tab Bar Item

struct TabBarItem: View {
    let tab: MainAppTab
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) { // Keep spacing larger for readability
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 16, weight: .medium)) // Keep icons larger for visibility
                    .foregroundColor(isSelected ? .white : StitchColors.textSecondary)
                
                Text(tab.title)
                    .font(.system(size: 8, weight: .medium)) // Keep text readable
                    .foregroundColor(isSelected ? .white : StitchColors.textSecondary)
            }
            .padding(.horizontal, 10) // Keep padding larger for touch targets
            .padding(.vertical, 6) // Keep padding larger for touch targets
            .background(
                Group {
                    if isSelected {
                        // Glassmorphism background for selected tab
                        RoundedRectangle(cornerRadius: 8) // Container proportionally smaller (10 * 0.8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                // Inner glow
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                StitchColors.primary.opacity(0.3),
                                                StitchColors.secondary.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .blur(radius: 0.8) // Reduced from 1
                            )
                            .overlay(
                                // Glass border
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1),
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8 // Reduced from 1
                                    )
                            )
                            .shadow(
                                color: StitchColors.primary.opacity(0.3),
                                radius: 6, // Reduced from 8
                                x: 0,
                                y: 1.6 // Reduced from 2
                            )
                    } else if isPressed {
                        // Subtle press effect
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .background(.ultraThinMaterial)
                    }
                }
            )
        }
        .frame(minWidth: 50) // Keep touch targets larger for usability
        .scaleEffect(isPressed ? 0.95 : 1.0)
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

// MARK: - Dipped Tab Bar Shape

struct DippedTabBarShape: Shape {
    let dippedRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let cornerRadius: CGFloat = 9 // Container proportionally smaller (11 * 0.8)
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let dippedWidth = dippedRadius * 2.5
        
        // Start from top-left
        path.move(to: CGPoint(x: cornerRadius, y: 0))
        
        // Top edge to dip start
        path.addLine(to: CGPoint(x: centerX - dippedWidth/2, y: 0))
        
        // Create the dip for center button
        path.addQuadCurve(
            to: CGPoint(x: centerX + dippedWidth/2, y: 0),
            control: CGPoint(x: centerX, y: dippedRadius)
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
