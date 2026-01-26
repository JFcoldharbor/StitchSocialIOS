//
//  JustJoinedView.swift
//  StitchSocial
//
//  Created by James Garmon on 1/23/26.
//


//
//  JustJoinedView.swift
//  StitchSocial
//
//  Full screen view for browsing newly joined users
//  Features: User grid/list, follow actions, profile navigation
//

import SwiftUI

struct JustJoinedView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var discoveryService = DiscoveryService()
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @ObservedObject var followManager = FollowManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var users: [RecentUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedUserID: String?
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading && users.isEmpty {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if users.isEmpty {
                    emptyView
                } else {
                    userGrid
                }
            }
            .navigationTitle("Just Joined")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
        }
        .task {
            await loadUsers()
        }
        .sheet(item: Binding(
            get: { selectedUserID.map { ProfilePresentation(id: $0) } },
            set: { selectedUserID = $0?.id }
        )) { presentation in
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService,
                viewingUserID: presentation.id
            )
        }
    }
    
    // MARK: - User Grid
    
    private var userGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(users) { user in
                    UserCard(
                        user: user,
                        onTap: { selectedUserID = user.id },
                        onFollow: { await toggleFollow(for: user.id) }
                    )
                    .environmentObject(followManager)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Loading & Error States
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.purple)
                .scaleEffect(1.5)
            
            Text("Loading new users...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task { await loadUsers() }
            }
            .foregroundColor(.purple)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No new users yet")
                .font(.system(size: 16))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        
        do {
            users = try await discoveryService.getRecentUsers(limit: 50)
            
            // Load follow states
            let userIDs = users.map { $0.id }
            await followManager.loadFollowStates(for: userIDs)
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func toggleFollow(for userID: String) async {
        await followManager.toggleFollow(for: userID)
    }
    
    // MARK: - Supporting Types
    
    struct ProfilePresentation: Identifiable {
        let id: String
    }
}

// MARK: - User Card Component

struct UserCard: View {
    
    let user: RecentUser
    let onTap: () -> Void
    let onFollow: () async -> Void
    
    @EnvironmentObject var followManager: FollowManager
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Avatar
                AsyncImage(url: URL(string: user.profileImageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    @unknown default:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                )
                
                // Username
                Text(user.username)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Joined time
                Text("Joined \(timeAgo(from: user.joinedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                // Follow button
                followButton
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var followButton: some View {
        Button(action: { Task { await onFollow() } }) {
            HStack(spacing: 4) {
                if followManager.isLoading(user.id) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: followManager.isFollowing(user.id) ? "checkmark" : "person.badge.plus")
                        .font(.system(size: 10))
                    Text(followManager.isFollowing(user.id) ? "Following" : "Follow")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(followManager.isFollowing(user.id) ? Color.gray.opacity(0.3) : Color.purple)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(followManager.isLoading(user.id))
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)
        
        if days == 0 {
            return "today"
        } else if days == 1 {
            return "yesterday"
        } else if days < 7 {
            return "\(days)d ago"
        } else {
            let weeks = days / 7
            return "\(weeks)w ago"
        }
    }
}

// MARK: - Preview

#Preview {
    JustJoinedView()
}
