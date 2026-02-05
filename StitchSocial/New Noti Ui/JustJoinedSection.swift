//
//  JustJoinedSection.swift
//  StitchSocial
//
//  Layer 8: Views - Just Joined Users Display Section
//  Dependencies: LeaderboardModels, SwiftUI
//  Features: Horizontal avatar display (non-interactive)
//

import SwiftUI

/// Horizontal scrolling section showing recently joined users (display only)
struct JustJoinedSection: View {
    
    let recentUsers: [RecentUser]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Section Header
            Text("Just Joined")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal)
            
            // Horizontal Scroll of Avatars
            if recentUsers.isEmpty {
                Text("No new users in the last 24 hours")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentUsers) { user in
                            UserAvatarDisplay(user: user)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Text("Tap card above to view all new users")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Avatar Display Component

private struct UserAvatarDisplay: View {
    
    let user: RecentUser
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            
            // Avatar Circle
            if let urlString = user.profileImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Text(user.username.prefix(1).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                }
            } else {
                // Fallback avatar
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Text(user.username.prefix(1).uppercased())
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
            }
            
            // Verified Badge
            if user.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.black))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        JustJoinedSection(
            recentUsers: [
                RecentUser(id: "1", username: "alice", displayName: "Alice", profileImageURL: nil, joinedAt: Date().addingTimeInterval(-3600), isVerified: true),
                RecentUser(id: "2", username: "bob", displayName: "Bob", profileImageURL: nil, joinedAt: Date().addingTimeInterval(-7200), isVerified: false)
            ]
        )
    }
}
