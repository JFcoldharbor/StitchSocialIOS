//
//  FollowManager.swift
//  StitchSocial
//
//  Layer 4: Core Services - Centralized Follow/Unfollow Logic with Auto-Follow Protection
//  Dependencies: UserService (Layer 4), NotificationService (Layer 4), Firebase Auth, SpecialUserEntry
//  Features: Optimistic UI updates, haptic feedback, error handling, loading states, unfollow protection, follow notifications
//  Used by: All views that need follow functionality
//  UPDATED: Added NotificationService integration for follow notifications
//

import SwiftUI
import FirebaseAuth

/// Centralized manager for all follow/unfollow operations across the app with James Fortune protection
@MainActor
class FollowManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FollowManager()
    
    // MARK: - Published State
    
    /// Follow states for all users: [userID: isFollowing]
    @Published var followingStates: [String: Bool] = [:]
    
    /// Loading states for users currently being followed/unfollowed
    @Published var loadingStates: Set<String> = []
    
    /// Last error that occurred during follow operations
    @Published var lastError: String?
    
    // MARK: - Dependencies
    
    private let userService = UserService()
    private let notificationService = NotificationService()
    
    // MARK: - Completion Callbacks
    
    /// Callback for when follow state changes successfully
    var onFollowStateChanged: ((String, Bool) -> Void)?
    
    /// Callback for when follow operation fails
    var onFollowError: ((String, Error) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        print("ðŸ”— FOLLOW MANAGER: Singleton initialized with auto-follow protection + notifications")
    }
    
    // MARK: - Public Interface
    
    /// Toggle follow state for a user with optimistic UI updates, error handling, and unfollow protection
    func toggleFollow(for userID: String) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("âŒ FOLLOW MANAGER: No current user ID")
            return
        }
        
        guard currentUserID != userID else {
            print("âŒ FOLLOW MANAGER: Cannot follow yourself")
            return
        }
        
        // Prevent duplicate requests
        guard !loadingStates.contains(userID) else {
            print("â³ FOLLOW MANAGER: Already processing request for \(userID)")
            return
        }
        
        // Start loading state
        loadingStates.insert(userID)
        
        // Get current state before optimistic update
        let wasFollowing = followingStates[userID] ?? false
        let newFollowingState = !wasFollowing
        
        print("ðŸ”— FOLLOW MANAGER: Toggle follow for \(userID)")
        print("   Current state: \(wasFollowing) â†’ New state: \(newFollowingState)")
        
        // CHECK FOR UNFOLLOW PROTECTION (James Fortune only)
        if wasFollowing && !newFollowingState {
            let isProtected = await isProtectedFromUnfollow(userID)
            if isProtected {
                print("ðŸ”’ FOLLOW MANAGER: Cannot unfollow protected account \(userID)")
                lastError = "This official account cannot be unfollowed"
                loadingStates.remove(userID)
                
                // Trigger haptic feedback for blocked action
                triggerHapticFeedback()
                
                return
            }
        }
        
        // Optimistic UI update (immediate visual feedback)
        followingStates[userID] = newFollowingState
        objectWillChange.send() // Force immediate UI update
        
        // Haptic feedback for better UX
        triggerHapticFeedback()
        
        print("ðŸ”— FOLLOW MANAGER: Optimistic state set to: \(newFollowingState)")
        
        do {
            // Perform the actual follow/unfollow operation
            if newFollowingState {
                try await userService.followUser(followerID: currentUserID, followingID: userID)
                print("âœ… FOLLOW MANAGER: Successfully followed user \(userID)")
                
                // SEND FOLLOW NOTIFICATION
                do {
                    try await notificationService.sendFollowNotification(to: userID)
                    print("FOLLOW MANAGER: Follow notification sent to \(userID)")
                } catch {
                    print("FOLLOW MANAGER: Failed to send follow notification: \(error)")
                }
                
            } else {
                try await userService.unfollowUser(followerID: currentUserID, followingID: userID)
                print("âœ… FOLLOW MANAGER: Successfully unfollowed user \(userID)")
                // No notification on unfollow
            }
            
            // Notify completion callback
            onFollowStateChanged?(userID, newFollowingState)
            
            // CRITICAL FIX: Broadcast follow state change to all views
            NotificationCenter.default.post(name: .followStateChanged, object: userID)
            
            // CRITICAL FIX: Immediately refresh follow state to ensure UI consistency
            await refreshFollowState(for: userID)
            
            print("âœ… FOLLOW MANAGER: Follow state updated - \(userID) is now \(newFollowingState ? "FOLLOWED" : "UNFOLLOWED")")
            print("ðŸ“¢ FOLLOW MANAGER: Broadcasted follow state change for \(userID)")
            
            // REFRESH FOLLOWER COUNTS AFTER SUCCESSFUL FOLLOW/UNFOLLOW
            Task {
                do {
                    try await userService.refreshFollowerCounts(userID: currentUserID)
                    try await userService.refreshFollowerCounts(userID: userID)
                    print("âœ… FOLLOW MANAGER: Refreshed follower counts after follow action")
                } catch {
                    print("âš ï¸ FOLLOW MANAGER: Failed to refresh counts: \(error)")
                }
            }
            
            // Clear any previous errors
            lastError = nil
            
        } catch {
            // Revert optimistic UI update on error
            followingStates[userID] = wasFollowing
            objectWillChange.send() // Force UI revert
            
            let errorMessage = "Failed to \(newFollowingState ? "follow" : "unfollow") user: \(error.localizedDescription)"
            lastError = errorMessage
            
            print("âŒ FOLLOW MANAGER: \(errorMessage)")
            
            // Notify error callback
            onFollowError?(userID, error)
            
            // Verify actual state from Firebase after error
            await refreshFollowState(for: userID)
        }
        
        // Clear loading state and force final UI update
        loadingStates.remove(userID)
        objectWillChange.send()
        
        print("ðŸ FOLLOW MANAGER: Toggle complete for \(userID). Final state: \(followingStates[userID] ?? false)")
    }
    
    // MARK: - Unfollow Protection for Special Users
    
    /// Check if user is protected from unfollowing (James Fortune only)
    private func isProtectedFromUnfollow(_ userID: String) async -> Bool {
        do {
            print("ðŸ”’ FOLLOW MANAGER: Checking unfollow protection for user \(userID)")
            
            // Get user email to check against protected accounts
            let userEmail = try await userService.getUserEmail(userID: userID)
            let isProtected = SpecialUsersConfig.isProtectedFromUnfollow(userEmail ?? "")
            
            if isProtected {
                print("ðŸ”’ FOLLOW MANAGER: User \(userID) (\(userEmail ?? "unknown")) IS PROTECTED from unfollowing")
            } else {
                print("âœ… FOLLOW MANAGER: User \(userID) (\(userEmail ?? "unknown")) can be unfollowed")
            }
            
            return isProtected
            
        } catch {
            print("âš ï¸ FOLLOW MANAGER: Could not check protection status for \(userID): \(error)")
            // If we can't check, allow the unfollow (fail open)
            return false
        }
    }
    
    /// Public method to check if a user is protected from unfollowing
    func isUserProtectedFromUnfollow(_ userID: String) async -> Bool {
        return await isProtectedFromUnfollow(userID)
    }
    
    // MARK: - State Management
    
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
            await MainActor.run {
                followingStates[userID] = isFollowing
                print("ðŸ”— FOLLOW MANAGER: Loaded follow state for \(userID): \(isFollowing)")
            }
        } catch {
            await MainActor.run {
                followingStates[userID] = false
                print("âŒ FOLLOW MANAGER: Failed to load follow state for \(userID): \(error)")
            }
        }
    }
    
    /// Load follow states for multiple users at once
    func loadFollowStates(for userIDs: [String]) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        print("ðŸ”„ FOLLOW MANAGER: Loading follow states for \(userIDs.count) users from Firebase...")
        
        await withTaskGroup(of: Void.self) { group in
            for userID in userIDs {
                group.addTask {
                    do {
                        let isFollowing = try await self.userService.isFollowing(followerID: currentUserID, followingID: userID)
                        await MainActor.run {
                            self.followingStates[userID] = isFollowing
                            print("ðŸ”— FOLLOW MANAGER: User \(userID) - Following: \(isFollowing)")
                        }
                    } catch {
                        await MainActor.run {
                            self.followingStates[userID] = false
                            print("âŒ FOLLOW MANAGER: Failed to load state for \(userID): \(error)")
                        }
                    }
                }
            }
        }
        
        print("âœ… FOLLOW MANAGER: Finished loading follow states for \(userIDs.count) users")
        
        // Force UI refresh after loading states
        await MainActor.run {
            self.objectWillChange.send()
        }
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
        print("ðŸ”— FOLLOW MANAGER: Cache cleared")
    }
    
    /// Update follow state manually (useful for external updates)
    func updateFollowState(for userID: String, isFollowing: Bool) {
        followingStates[userID] = isFollowing
        print("ðŸ”— FOLLOW MANAGER: Manually updated follow state for \(userID): \(isFollowing)")
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
    
    /// Refresh follow states for multiple users (batch refresh)
    func refreshFollowStates(for userIDs: [String]) async {
        print("ðŸ”„ FOLLOW MANAGER: Refreshing follow states for \(userIDs.count) users")
        
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("âŒ FOLLOW MANAGER: No current user for refresh")
            return
        }
        
        do {
            // Get fresh following data for current user
            let (_, following) = try await userService.getFreshFollowData(userID: currentUserID)
            
            // Update local follow states based on fresh data
            await MainActor.run {
                for userID in userIDs {
                    let isFollowing = following.contains(userID)
                    followingStates[userID] = isFollowing
                    print("ðŸ”„ FOLLOW MANAGER: Updated state for \(userID): \(isFollowing)")
                }
            }
            
            print("âœ… FOLLOW MANAGER: Refreshed follow states for \(userIDs.count) users")
            
        } catch {
            print("âš ï¸ FOLLOW MANAGER: Failed to refresh follow states: \(error)")
        }
    }
    
    /// Force refresh all cached follow states
    func refreshAllFollowStates() async {
        print("ðŸ”„ FOLLOW MANAGER: Refreshing ALL cached follow states")
        
        let userIDsToRefresh = Array(followingStates.keys)
        await refreshFollowStates(for: userIDsToRefresh)
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
    
    /// Check if user can be unfollowed (not protected)
    func canUnfollow(_ userID: String) async -> Bool {
        if !isFollowing(userID) {
            return true // Not following, so no need to unfollow
        }
        
        return !(await isProtectedFromUnfollow(userID))
    }
}

// MARK: - Debug Helpers

extension FollowManager {
    
    /// Print current state for debugging
    func debugPrintState() {
        print("ðŸ”— FOLLOW MANAGER DEBUG:")
        print("   Following states: \(followingStates)")
        print("   Loading states: \(loadingStates)")
        print("   Total following: \(totalFollowing)")
        print("   Pending operations: \(pendingOperations)")
        print("   Last error: \(lastError ?? "none")")
    }
    
    /// Test follow manager functionality
    func helloWorldTest() {
        print("ðŸ”— FOLLOW MANAGER: Hello World - Ready for complete follow management!")
        print("ðŸ”— Features: Follow/Unfollow, Optimistic UI, James Fortune protection, Batch operations, Notifications")
        print("ðŸ”— Status: UserService integration, NotificationService integration, Haptic feedback, Error handling, State management")
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let followStateChanged = Notification.Name("followStateChanged")
} 
