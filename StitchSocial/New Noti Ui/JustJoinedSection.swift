//
//  JustJoinedSection.swift
//  StitchSocial
//
//  Created by James Garmon on 11/1/25.
//


//
//  JustJoinedSection.swift
//  StitchSocial
//
//  Layer 8: Views - Just Joined Users Horizontal Scroll Section
//  Dependencies: LeaderboardModels, SwiftUI
//  Features: Horizontal avatar scroll, profile navigation
//

import SwiftUI

/// Horizontal scrolling section showing recently joined users
struct JustJoinedSection: View {
    
    let recentUsers: [RecentUser]
    
    @State private var selectedUserID: String?  // 🔧 For profile navigation
    @State private var showingProfile = false  // 🔧 For profile sheet
    
    // 🔧 Services for ProfileView
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    
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
                            UserAvatarButton(
                                user: user,
                                onTap: {
                                    selectedUserID = user.id  // 🔧 Set user ID
                                    showingProfile = true      // 🔧 Show profile
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingProfile) {
            if let userID = selectedUserID {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService,
                    viewingUserID: userID  // 🔧 FIXED: Pass viewingUserID for user profile
                )
            }
        }
    }
}

// MARK: - Avatar Button Component

private struct UserAvatarButton: View {
    
    let user: RecentUser
    let onTap: () -> Void  // 🔧 Changed to no-parameter closure
    
    var body: some View {
        Button(action: onTap) {
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
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        JustJoinedSection(
            recentUsers: [
                RecentUser(
                    id: "1",
                    username: "alice",
                    displayName: "Alice Wonder",
                    profileImageURL: nil,
                    joinedAt: Date().addingTimeInterval(-3600),
                    isVerified: true
                ),
                RecentUser(
                    id: "2",
                    username: "bob",
                    displayName: "Bob Builder",
                    profileImageURL: nil,
                    joinedAt: Date().addingTimeInterval(-7200),
                    isVerified: false
                ),
                RecentUser(
                    id: "3",
                    username: "charlie",
                    displayName: "Charlie Chaplin",
                    profileImageURL: nil,
                    joinedAt: Date().addingTimeInterval(-10800),
                    isVerified: false
                )
            ]
        )
    }
}
