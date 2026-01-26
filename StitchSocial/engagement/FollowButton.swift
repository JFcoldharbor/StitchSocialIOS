//
//  FollowButton.swift
//  StitchSocial
//
//  Created by James Garmon on 12/6/25.
//


//
//  FollowButton.swift
//  StitchSocial
//
//  Reusable follow/following button component
//

import SwiftUI

/// Reusable follow button with follow/following states
struct FollowButton: View {
    
    let userID: String
    let isFollowing: Bool
    let onToggle: () async -> Void
    
    /// Optional: Hide button (e.g., on own content)
    var isHidden: Bool = false
    
    /// Style variants
    enum Style {
        case standard   // Purple/gray pill
        case compact    // Smaller version
        case outline    // Border only
    }
    
    var style: Style = .standard
    
    var body: some View {
        Button {
            Task {
                await onToggle()
            }
        } label: {
            buttonContent
        }
        .buttonStyle(ScaleButtonStyle())
        .opacity(isHidden ? 0 : 1)
        .disabled(isHidden)
    }
    
    @ViewBuilder
    private var buttonContent: some View {
        switch style {
        case .standard:
            standardButton
        case .compact:
            compactButton
        case .outline:
            outlineButton
        }
    }
    
    // MARK: - Standard Style
    
    private var standardButton: some View {
        HStack(spacing: 4) {
            Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                .font(.system(size: 12, weight: .semibold))
            
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isFollowing ? Color.gray.opacity(0.4) : Color.purple)
        )
        .overlay(
            Capsule()
                .stroke(isFollowing ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Compact Style
    
    private var compactButton: some View {
        HStack(spacing: 3) {
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 10, weight: .bold))
            
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isFollowing ? Color.gray.opacity(0.4) : Color.purple)
        )
    }
    
    // MARK: - Outline Style
    
    private var outlineButton: some View {
        HStack(spacing: 4) {
            Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                .font(.system(size: 12, weight: .semibold))
            
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(isFollowing ? .gray : .purple)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .stroke(isFollowing ? Color.gray : Color.purple, lineWidth: 1.5)
        )
    }
}

// MARK: - Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
            // Standard - Not Following
            FollowButton(
                userID: "test",
                isFollowing: false,
                onToggle: { print("Toggle") }
            )
            
            // Standard - Following
            FollowButton(
                userID: "test",
                isFollowing: true,
                onToggle: { print("Toggle") }
            )
            
            // Compact - Not Following
            FollowButton(
                userID: "test",
                isFollowing: false,
                onToggle: { print("Toggle") },
                style: .compact
            )
            
            // Compact - Following
            FollowButton(
                userID: "test",
                isFollowing: true,
                onToggle: { print("Toggle") },
                style: .compact
            )
            
            // Outline - Not Following
            FollowButton(
                userID: "test",
                isFollowing: false,
                onToggle: { print("Toggle") },
                style: .outline
            )
            
            // Outline - Following
            FollowButton(
                userID: "test",
                isFollowing: true,
                onToggle: { print("Toggle") },
                style: .outline
            )
        }
    }
}
