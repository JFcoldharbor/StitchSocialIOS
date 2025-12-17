//
//  SuggestedUsersFullscreenCard.swift
//  StitchSocial
//
//  Fullscreen suggestion card that integrates seamlessly into HomeFeed
//  Works like a video - swipe up/down to dismiss
//

import SwiftUI

// MARK: - Fullscreen Suggested Users Card

struct SuggestedUsersFullscreenCard: View {
    
    let suggestions: [BasicUserInfo]
    let onDismiss: () -> Void
    let onRefresh: () async -> Void
    let onNavigateToProfile: (String) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isRefreshing: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                        .padding(.top, 50)
                    
                    Spacer()
                    
                    // Current user card
                    if currentIndex < suggestions.count {
                        userCard(suggestions[currentIndex], geometry: geometry)
                            .offset(y: dragOffset)
                    }
                    
                    Spacer()
                    
                    // Progress indicators
                    progressIndicators
                        .padding(.bottom, 40)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        handleSwipe(value, geometry: geometry)
                    }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.white)
            
            Text("People You Might Like")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("Swipe up or down to skip • Tap to view profile")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - User Card
    
    private func userCard(_ user: BasicUserInfo, geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            profileImageView(user)
            usernameView(user)
            tierBadgeView(user)
            statsView(user)
            actionButtonsView(user)
        }
        .frame(width: geometry.size.width * 0.85)
        .padding(.vertical, 40)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 20)
    }
    
    private func profileImageView(_ user: BasicUserInfo) -> some View {
        AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                )
        }
        .frame(width: 150, height: 150)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 4))
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
    
    private func usernameView(_ user: BasicUserInfo) -> some View {
        VStack(spacing: 4) {
            Text(user.username)
                .font(.title.bold())
                .foregroundColor(.white)
            
            if !user.displayName.isEmpty {
                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    private func tierBadgeView(_ user: BasicUserInfo) -> some View {
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
    }
    
    private func statsView(_ user: BasicUserInfo) -> some View {
        HStack(spacing: 40) {
            statView(count: user.clout, label: "Clout")
        }
        .padding(.top, 10)
    }
    
    private func actionButtonsView(_ user: BasicUserInfo) -> some View {
        HStack(spacing: 16) {
            Button(action: {
                onNavigateToProfile(user.id)
            }) {
                HStack {
                    Image(systemName: "person.circle")
                    Text("View Profile")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(25)
            }
            
            // Simple follow button
            Button(action: {
                Task {
                    // Toggle follow state
                    await FollowManager.shared.toggleFollow(for: user.id)
                }
            }) {
                Text("Follow")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(25)
            }
        }
        .padding(.top, 10)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(Color.white.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
    
    private func statView(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Progress Indicators
    
    private var progressIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<suggestions.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentIndex ? 30 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleSwipe(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let threshold: CGFloat = 100
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
        }
        
        if abs(value.translation.height) > threshold {
            // Swiped up or down - go to next or dismiss
            if value.translation.height < 0 {
                // Swiped up - next user
                nextUser()
            } else {
                // Swiped down - previous or dismiss
                previousUser()
            }
        }
    }
    
    private func nextUser() {
        if currentIndex < suggestions.count - 1 {
            withAnimation(.spring(response: 0.3)) {
                currentIndex += 1
            }
        } else {
            // Last user, dismiss
            onDismiss()
        }
    }
    
    private func previousUser() {
        if currentIndex > 0 {
            withAnimation(.spring(response: 0.3)) {
                currentIndex -= 1
            }
        } else {
            // First user and swiped down, dismiss
            onDismiss()
        }
    }
}

// MARK: - Preview

struct SuggestedUsersFullscreenCard_Previews: PreviewProvider {
    static var previews: some View {
        SuggestedUsersFullscreenCard(
            suggestions: [
                BasicUserInfo(
                    id: "1",
                    username: "johndoe",
                    displayName: "John Doe",
                    bio: "Content creator",
                    tier: .ambassador,
                    clout: 1234,
                    isVerified: false,
                    isPrivate: false,
                    profileImageURL: nil,
                    createdAt: Date()
                ),
                BasicUserInfo(
                    id: "2",
                    username: "janedoe",
                    displayName: "Jane Doe",
                    bio: "Designer",
                    tier: .ambassador,
                    clout: 5678,
                    isVerified: false,
                    isPrivate: false,
                    profileImageURL: nil,
                    createdAt: Date()
                )
            ],
            onDismiss: {},
            onRefresh: {},
            onNavigateToProfile: { _ in }
        )
    }
}
