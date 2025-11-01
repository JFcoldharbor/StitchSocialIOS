//
//  TaggedUserChip.swift
//  StitchSocial
//
//  Created by James Garmon on 10/28/25.
//


//
//  TaggedUserChip.swift
//  StitchSocial
//
//  Layer 8: Views - Tagged User Display Component
//  Dependencies: UserService (Layer 4), BasicUserInfo (Layer 1)
//  Features: Display tagged user with profile image, removable
//

import SwiftUI

struct TaggedUserChip: View {
    
    // MARK: - Properties
    
    let userID: String
    let onRemove: () -> Void
    
    // MARK: - State
    
    @State private var user: BasicUserInfo?
    @State private var isLoading = true
    
    // MARK: - Services
    
    @StateObject private var userService = UserService()
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isLoading {
                loadingChip
            } else if let user = user {
                userChip(user: user)
            } else {
                errorChip
            }
        }
        .task {
            await loadUser()
        }
    }
    
    // MARK: - User Chip
    
    private func userChip(user: BasicUserInfo) -> some View {
        HStack(spacing: 8) {
            // Profile image
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            
            // Username
            HStack(spacing: 4) {
                Text("@\(user.username)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Loading Chip
    
    private var loadingChip: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            
            Text("Loading...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.6))
        .cornerRadius(20)
    }
    
    // MARK: - Error Chip
    
    private var errorChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
            
            Text("User not found")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.7))
        .cornerRadius(20)
    }
    
    // MARK: - Load User
    
    private func loadUser() async {
        do {
            let loadedUser = try await userService.getUser(id: userID)
            
            await MainActor.run {
                user = loadedUser
                isLoading = false
            }
            
        } catch {
            print("❌ TAGGED USER CHIP: Failed to load user \(userID) - \(error)")
            
            await MainActor.run {
                user = nil
                isLoading = false
            }
        }
    }
}

// MARK: - Simplified Version (If you already have user data)

struct TaggedUserChipSimple: View {
    let username: String
    let profileImageURL: String?
    let isVerified: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Profile image
            AsyncImage(url: URL(string: profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            
            // Username
            HStack(spacing: 4) {
                Text("@\(username)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TaggedUserChip(userID: "test_user_id") {
            print("Removed")
        }
        
        TaggedUserChipSimple(
            username: "jamesfortune",
            profileImageURL: nil,
            isVerified: true
        ) {
            print("Removed")
        }
    }
    .padding()
    .background(Color.black)
}