//
//  SuggestionCardVideoItem.swift
//  StitchSocial
//
//  Suggestion card that acts as a video item in the feed
//  Swipe up/down like a normal video to navigate
//

import SwiftUI

struct SuggestionCardVideoItem: View {
    
    let suggestions: [BasicUserInfo]
    let onDismiss: () -> Void
    let onNavigateToProfile: (String) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.purple.opacity(0.9), Color.blue.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Spacer()
                    
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                        
                        Text("People You Might Like")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Current user card
                    if currentIndex < suggestions.count {
                        userCard(suggestions[currentIndex])
                            .offset(x: dragOffset)
                    }
                    
                    Spacer()
                    
                    // Progress indicators
                    progressIndicators
                    
                    // Swipe hint
                    Text("Swipe left/right for users • Swipe up/down for feed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.bottom, 40)
                }
                .offset(y: dragOffset)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Allow both directions during drag
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        handleSwipe(value)
                    }
            )
        }
    }
    
    // MARK: - User Card
    
    private func userCard(_ user: BasicUserInfo) -> some View {
        VStack(spacing: 16) {
            // Profile picture
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            
            // Username
            VStack(spacing: 4) {
                Text(user.username)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                if !user.displayName.isEmpty {
                    Text(user.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Tier badge
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                Text(user.tier.rawValue.capitalized)
                    .font(.caption.bold())
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(15)
            
            // Stats
            HStack(spacing: 30) {
                VStack(spacing: 2) {
                    Text("\(user.clout)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text("Clout")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    onNavigateToProfile(user.id)
                }) {
                    HStack {
                        Image(systemName: "person.circle")
                        Text("Profile")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
                }
                
                Button(action: {
                    Task {
                        await FollowManager.shared.toggleFollow(for: user.id)
                    }
                }) {
                    Text("Follow")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(20)
                }
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 30)
    }
    
    // MARK: - Progress Indicators
    
    private var progressIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<suggestions.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentIndex ? 24 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
    }
    
    // MARK: - Swipe Handling
    
    private func handleSwipe(_ value: DragGesture.Value) {
        withAnimation(.spring(response: 0.3)) {
            dragOffset = 0
        }
        
        let threshold: CGFloat = 50
        let absWidth = abs(value.translation.width)
        let absHeight = abs(value.translation.height)
        
        // Determine dominant direction
        if absWidth > absHeight {
            // HORIZONTAL SWIPE - Navigate between users
            if value.translation.width < -threshold {
                // Swiped left - next user
                nextUser()
            } else if value.translation.width > threshold {
                // Swiped right - previous user
                previousUser()
            }
        } else {
            // VERTICAL SWIPE - Exit to feed navigation
            if abs(value.translation.height) > threshold {
                // Any vertical swipe dismisses card to continue feed
                onDismiss()
            }
        }
    }
    
    private func nextUser() {
        if currentIndex < suggestions.count - 1 {
            withAnimation(.spring(response: 0.3)) {
                currentIndex += 1
            }
        } else {
            // Last user, dismiss to continue feed
            onDismiss()
        }
    }
    
    private func previousUser() {
        if currentIndex > 0 {
            withAnimation(.spring(response: 0.3)) {
                currentIndex -= 1
            }
        } else {
            // First user and swiped right, dismiss to continue feed
            onDismiss()
        }
    }
}
