//
//  FollowManager.swift
//  StitchSocial
//
//  Created by James Garmon on 9/10/25.
//


//
//  FollowManager.swift
//  StitchSocial
//
//  Layer 4: Core Services - Centralized Follow/Unfollow Logic
//  Dependencies: UserService (Layer 4), Firebase Auth
//  Features: Optimistic UI updates, haptic feedback, error handling, loading states
//  Used by: All views that need follow functionality
//

import SwiftUI
import FirebaseAuth

/// Centralized manager for all follow/unfollow operations across the app
@MainActor
class FollowManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Follow states for all users: [userID: isFollowing]
    @Published var followingStates: [String: Bool] = [:]
    
    /// Loading states for users currently being followed/unfollowed
    @Published var loadingStates: Set<String> = []
    
    /// Last error that occurred during follow operations
    @Published var lastError: String?
    
    // MARK: - Dependencies
    
    private let userService = UserService()
    
    // MARK: - Completion Callbacks
    
    /// Callback for when follow state changes successfully
    var onFollowStateChanged: ((String, Bool) -> Void)?
    
    /// Callback for when follow operation fails
    var onFollowError: ((String, Error) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        print("🔗 FOLLOW MANAGER: Initialized")
    }
    
    // MARK: - Public Interface
    
    /// Toggle follow state for a user with optimistic UI updates and error handling
    func toggleFollow(for userID: String) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("❌ FOLLOW MANAGER: No current user ID")
            return
        }
        
        guard currentUserID != userID else {
            print("❌ FOLLOW MANAGER: Cannot follow yourself")
            return
        }
        
        // Start loading state
        loadingStates.insert(userID)
        
        // Get current state before optimistic update
        let wasFollowing = followingStates[userID] ?? false
        let newFollowingState = !wasFollowing
        
        // Optimistic UI update (immediate visual feedback)
        followingStates[userID] = newFollowingState
        
        // Haptic feedback for better UX
        triggerHapticFeedback()
        
        print("🔗 FOLLOW MANAGER: \(newFollowingState ? "Following" : "Unfollowing") user \(userID)")
        
        do {
            // Perform the actual follow/unfollow operation
            if newFollowingState {
                try await userService.followUser(followerID: currentUserID, followingID: userID)
                print("✅ FOLLOW MANAGER: Successfully followed user \(userID)")
            } else {
                try await userService.unfollowUser(followerID: currentUserID, followingID: userID)
                print("✅ FOLLOW MANAGER: Successfully unfollowed user \(userID)")
            }
            
            // Notify completion callback
            onFollowStateChanged?(userID, newFollowingState)
            
            // Clear any previous errors
            lastError = nil
            
        } catch {
            // Revert optimistic UI update on error
            followingStates[userID] = wasFollowing
            
            let errorMessage = "Failed to \(newFollowingState ? "follow" : "unfollow") user: \(error.localizedDescription)"
            lastError = errorMessage
            
            print("❌ FOLLOW MANAGER: \(errorMessage)")
            
            // Notify error callback
            onFollowError?(userID, error)
        }
        
        // Clear loading state
        loadingStates.remove(userID)
    }
    
    /// Check if currently following a user
    func isFollowing(_ userID: String) -> Bool {
        return followingStates[userID] ?? false
    }
    
    /// Check if a follow operation is in progress for a user
    func isLoading(_ userID: String) -> Bool {
        return loadingStates.contains(userID)
    }
    
    /// Load follow state for a specific user from the server
    func loadFollowState(for userID: String) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        do {
            let isFollowing = try await userService.isFollowing(followerID: currentUserID, followingID: userID)
            followingStates[userID] = isFollowing
            print("🔗 FOLLOW MANAGER: Loaded follow state for \(userID): \(isFollowing)")
        } catch {
            followingStates[userID] = false
            print("❌ FOLLOW MANAGER: Failed to load follow state for \(userID): \(error)")
        }
    }
    
    /// Load follow states for multiple users at once
    func loadFollowStates(for userIDs: [String]) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        await withTaskGroup(of: Void.self) { group in
            for userID in userIDs {
                group.addTask {
                    do {
                        let isFollowing = try await self.userService.isFollowing(followerID: currentUserID, followingID: userID)
                        await MainActor.run {
                            self.followingStates[userID] = isFollowing
                        }
                    } catch {
                        await MainActor.run {
                            self.followingStates[userID] = false
                        }
                    }
                }
            }
        }
        
        print("🔗 FOLLOW MANAGER: Loaded follow states for \(userIDs.count) users")
    }
    
    /// Refresh follow state for a user (force reload from server)
    func refreshFollowState(for userID: String) async {
        await loadFollowState(for: userID)
    }
    
    /// Clear all cached follow states
    func clearCache() {
        followingStates.removeAll()
        loadingStates.removeAll()
        lastError = nil
        print("🔗 FOLLOW MANAGER: Cache cleared")
    }
    
    /// Update follow state manually (useful for external updates)
    func updateFollowState(for userID: String, isFollowing: Bool) {
        followingStates[userID] = isFollowing
        print("🔗 FOLLOW MANAGER: Manually updated follow state for \(userID): \(isFollowing)")
    }
    
    // MARK: - Batch Operations
    
    /// Load follow states for users in a batch (more efficient for lists)
    func loadFollowStatesForUsers(_ users: [BasicUserInfo]) async {
        let userIDs = users.map { $0.id }
        await loadFollowStates(for: userIDs)
    }
    
    /// Get follow state for multiple users
    func getFollowStates(for userIDs: [String]) -> [String: Bool] {
        return userIDs.reduce(into: [String: Bool]()) { result, userID in
            result[userID] = followingStates[userID] ?? false
        }
    }
    
    // MARK: - Statistics
    
    /// Get total number of users being followed (from cache)
    var totalFollowing: Int {
        return followingStates.values.filter { $0 }.count
    }
    
    /// Get number of users currently being processed
    var pendingOperations: Int {
        return loadingStates.count
    }
    
    // MARK: - Private Helpers
    
    /// Trigger haptic feedback for follow/unfollow actions
    private func triggerHapticFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
    }
}

// MARK: - Convenience Extensions

extension FollowManager {
    
    /// Create a binding for a specific user's follow state
    func followBinding(for userID: String) -> Binding<Bool> {
        return Binding(
            get: { self.isFollowing(userID) },
            set: { _ in
                Task {
                    await self.toggleFollow(for: userID)
                }
            }
        )
    }
    
    /// Get follow button text for a user
    func followButtonText(for userID: String) -> String {
        if isLoading(userID) {
            return "Loading..."
        } else if isFollowing(userID) {
            return "Following"
        } else {
            return "Follow"
        }
    }
    
    /// Get follow button colors for a user
    func followButtonColors(for userID: String) -> (foreground: Color, background: Color) {
        if isFollowing(userID) {
            return (foreground: .black, background: .white)
        } else {
            return (foreground: .white, background: .cyan)
        }
    }
}

// MARK: - Debug Helpers

extension FollowManager {
    
    /// Print current state for debugging
    func debugPrintState() {
        print("🔗 FOLLOW MANAGER DEBUG:")
        print("   Following states: \(followingStates)")
        print("   Loading states: \(loadingStates)")
        print("   Total following: \(totalFollowing)")
        print("   Pending operations: \(pendingOperations)")
        print("   Last error: \(lastError ?? "none")")
    }
}