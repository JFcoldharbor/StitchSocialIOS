//
//  SuggestedUsersCard.swift
//  StitchSocial
//
//  Layer 8: Views - Suggested Users Discovery Card
//  Dependencies: SuggestionService, FollowManager, BasicUserInfo
//  Features: Swipeable user cards, follow/skip actions, refresh capability
//

import SwiftUI

// MARK: - Main Suggested Users Card

struct SuggestedUsersCard: View {
    
    // MARK: - Properties
    
    let suggestions: [BasicUserInfo]
    let onDismiss: () -> Void
    let onRefresh: () async -> Void
    let onNavigateToProfile: (String) -> Void
    
    @StateObject private var followManager = FollowManager.shared
    @State private var currentIndex = 0
    @State private var offset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var followedUsers = Set<String>()
    @State private var skippedUsers = Set<String>()
    @State private var showingCompleteMessage = false
    
    // MARK: - Animation Properties
    
    @State private var cardScale: CGFloat = 1.0
    @State private var backgroundOpacity: Double = 0.0
    @State private var titleOffset: CGFloat = -20
    
    private let swipeThreshold: CGFloat = 100
    
    // MARK: - Computed Properties
    
    private var currentSuggestion: BasicUserInfo? {
        guard currentIndex < suggestions.count else { return nil }
        return suggestions[currentIndex]
    }
    
    private var remainingCount: Int {
        suggestions.count - currentIndex
    }
    
    private var isFollowing: Bool {
        guard let currentUser = currentSuggestion else { return false }
        return followManager.isFollowing(currentUser.id)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .opacity(backgroundOpacity)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                    .offset(y: titleOffset)
                
                Spacer()
                
                // Card stack
                if showingCompleteMessage {
                    completionMessage
                } else if let suggestion = currentSuggestion {
                    ZStack {
                        // Background cards for depth
                        ForEach(0..<min(3, remainingCount), id: \.self) { index in
                            if currentIndex + index < suggestions.count {
                                backgroundCard(for: index)
                            }
                        }
                        
                        // Main card
                        mainCard(suggestion: suggestion)
                            .offset(x: offset)
                            .rotationEffect(.degrees(Double(offset / 20)))
                            .scaleEffect(cardScale)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = value.translation.width
                                    }
                                    .onEnded { value in
                                        handleSwipeEnd(value: value)
                                    }
                            )
                    }
                }
                
                Spacer()
                
                // Action buttons
                if !showingCompleteMessage {
                    actionButtons
                }
                
                // Close button
                closeButton
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                backgroundOpacity = 1.0
                titleOffset = 0
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Discover Creators")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("\(remainingCount) suggestions remaining")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            // Refresh button
            Button(action: { Task { await handleRefresh() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Refresh Suggestions")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.purple.opacity(0.15))
                )
            }
            .disabled(isRefreshing)
            .opacity(isRefreshing ? 0.5 : 1.0)
        }
    }
    
    // MARK: - Main Card
    
    private func mainCard(suggestion: BasicUserInfo) -> some View {
        VStack(spacing: 0) {
            // Profile Image
            ZStack {
                AsyncImage(url: URL(string: suggestion.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    LinearGradient(
                        colors: [Color.purple.opacity(0.4), Color.pink.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.5))
                    )
                }
                .frame(height: 400)
                .clipped()
                
                // Swipe indicators
                if abs(offset) > 50 {
                    swipeIndicator
                }
            }
            
            // User info section
            userInfoSection(suggestion: suggestion)
        }
        .background(Color(white: 0.1))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 30)
    }
    
    // MARK: - User Info Section
    
    private func userInfoSection(suggestion: BasicUserInfo) -> some View {
        VStack(spacing: 16) {
            // Name and verification
            HStack(spacing: 8) {
                Text(suggestion.displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                
                if suggestion.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.cyan, .cyan.opacity(0.3))
                }
                
                Spacer()
            }
            
            // Username
            HStack {
                Text("@\(suggestion.username)")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            
            // Tier badge
            HStack(spacing: 8) {
                Circle()
                    .fill(tierColor(suggestion.tier))
                    .frame(width: 10, height: 10)
                
                Text(suggestion.tier.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tierColor(suggestion.tier))
                
                Spacer()
            }
            
            // View Profile button
            Button(action: { onNavigateToProfile(suggestion.id) }) {
                HStack {
                    Text("View Profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(24)
    }
    
    // MARK: - Background Cards
    
    private func backgroundCard(for index: Int) -> some View {
        let scale = 1.0 - (CGFloat(index) * 0.05)
        let yOffset = CGFloat(index) * 15
        
        return RoundedRectangle(cornerRadius: 24)
            .fill(Color(white: 0.1).opacity(0.8 - Double(index) * 0.2))
            .frame(height: 500)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .padding(.horizontal, 30)
    }
    
    // MARK: - Swipe Indicator
    
    private var swipeIndicator: some View {
        Group {
            if offset > 50 {
                // Follow indicator
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    Text("FOLLOW")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(20)
                .background(Color.green.opacity(0.2))
                .cornerRadius(16)
                .rotationEffect(.degrees(-20))
                .offset(x: -100, y: -150)
            } else if offset < -50 {
                // Skip indicator
                VStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("SKIP")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(20)
                .background(Color.red.opacity(0.2))
                .cornerRadius(16)
                .rotationEffect(.degrees(20))
                .offset(x: 100, y: -150)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 40) {
            // Skip button
            Button(action: { handleSkip() }) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: 70, height: 70)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.red)
                }
            }
            
            // Follow button
            Button(action: { Task { await handleFollow() } }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: .purple.opacity(0.5), radius: 15, x: 0, y: 5)
                    
                    Image(systemName: isFollowing ? "checkmark" : "heart.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .disabled(isFollowing)
            .opacity(isFollowing ? 0.5 : 1.0)
        }
    }
    
    // MARK: - Close Button
    
    private var closeButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Text("Close")
                    .font(.system(size: 16, weight: .semibold))
                
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(white: 0.15))
            .cornerRadius(20)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Completion Message
    
    private var completionMessage: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .pink.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("All Done!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("You've reviewed all suggestions")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                
                if followedUsers.count > 0 {
                    Text("Followed \(followedUsers.count) creators")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(12)
                }
            }
            
            Button(action: { Task { await handleRefresh() } }) {
                Text("Get More Suggestions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Actions
    
    private func handleSwipeEnd(value: DragGesture.Value) {
        let width = value.translation.width
        
        if abs(width) > swipeThreshold {
            if width > 0 {
                // Swiped right - follow
                Task { await handleFollow() }
            } else {
                // Swiped left - skip
                handleSkip()
            }
            
            // Animate card away
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = width > 0 ? 500 : -500
                cardScale = 0.8
            }
            
            // Move to next card
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                moveToNextCard()
            }
        } else {
            // Return to center
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = 0
            }
        }
    }
    
    private func handleFollow() async {
        guard let suggestion = currentSuggestion,
              let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        do {
            await followManager.toggleFollow(for: suggestion.id)
            followedUsers.insert(suggestion.id)
            
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            
            // Animate card away
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = 500
                cardScale = 0.8
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                moveToNextCard()
            }
        } catch {
            print("❌ SUGGESTION: Follow failed: \(error)")
        }
    }
    
    private func handleSkip() {
        guard let suggestion = currentSuggestion else { return }
        
        skippedUsers.insert(suggestion.id)
        
        // Animate card away
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            offset = -500
            cardScale = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            moveToNextCard()
        }
    }
    
    private func moveToNextCard() {
        currentIndex += 1
        
        if currentIndex >= suggestions.count {
            // All suggestions reviewed
            withAnimation {
                showingCompleteMessage = true
            }
        } else {
            // Reset card state
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = 0
                cardScale = 1.0
            }
        }
    }
    
    private func handleRefresh() async {
        isRefreshing = true
        await onRefresh()
        
        // Reset state
        withAnimation {
            currentIndex = 0
            showingCompleteMessage = false
            followedUsers.removeAll()
            skippedUsers.removeAll()
        }
        
        isRefreshing = false
    }
    
    // MARK: - Helper Functions
    
    private func tierColor(_ tier: UserTier) -> Color {
        switch tier {
        case .founder, .coFounder: return .cyan
        case .topCreator: return .yellow
        case .legendary: return .red
        case .partner: return .pink
        case .elite: return .orange
        case .ambassador: return .indigo
        case .influencer: return .purple
        case .veteran: return .blue
        case .rising: return .green
        case .rookie: return .gray
        }
    }
}

// MARK: - Compact Suggestion Card (For Feed)

struct CompactSuggestionCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.2), .pink.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Text
                VStack(spacing: 8) {
                    Text("Discover Creators")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Find people to follow")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                // CTA
                HStack(spacing: 8) {
                    Text("Explore")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

import FirebaseAuth

#Preview {
    let mockSuggestions = [
        BasicUserInfo(
            id: "user1",
            username: "creator1",
            displayName: "Amazing Creator",
            tier: .influencer,
            clout: 5000,
            isVerified: true,
            profileImageURL: nil,
            createdAt: Date()
        ),
        BasicUserInfo(
            id: "user2",
            username: "artist2",
            displayName: "Cool Artist",
            tier: .veteran,
            clout: 2500,
            isVerified: false,
            profileImageURL: nil,
            createdAt: Date()
        )
    ]
    
    SuggestedUsersCard(
        suggestions: mockSuggestions,
        onDismiss: { print("Dismissed") },
        onRefresh: { print("Refresh") },
        onNavigateToProfile: { print("Navigate to \($0)") }
    )
}
