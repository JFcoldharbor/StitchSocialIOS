//
//  SuggestionService.swift
//  StitchSocial
//
//  Layer 4: Services - User Suggestion Service (Uses SearchService)
//  Dependencies: SearchService, FollowManager
//  Features: Smart display logic, frequency control, tracks shown users
//  FIXED: Prevents showing same users repeatedly
//

import Foundation
import FirebaseAuth

/// Service for managing when and how to show user suggestions
@MainActor
class SuggestionService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let searchService: SearchService
    private let followManager: FollowManager
    private let userService: UserService
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    
    // ✅ FIX: Track shown users to prevent repeats
    private var shownUserIDs: Set<String> = []
    private let maxShownBeforeReset = 50 // After showing 50 users, allow repeats
    
    // MARK: - Configuration
    
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(
        searchService: SearchService? = nil,
        followManager: FollowManager? = nil,
        userService: UserService? = nil
    ) {
        self.searchService = searchService ?? SearchService()
        self.followManager = followManager ?? FollowManager.shared
        self.userService = userService ?? UserService()
        
        print("💡 SUGGESTION SERVICE: Initialized with user tracking")
    }
    
    // MARK: - Main Methods
    
    /// Get suggested users (filters out already shown and already following)
    func getSuggestions(limit: Int = 10) async throws -> [BasicUserInfo] {
        isLoading = true
        defer { isLoading = false }
        
        print("💡 SUGGESTION: Getting suggestions (shown: \(shownUserIDs.count))")
        
        // Get current user to filter out people they follow
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("❌ SUGGESTION: No auth user")
            return []
        }
        
        // Request MORE than needed to account for filtering
        let fetchLimit = limit * 3
        
        // Use SearchService's getSuggestedUsers method
        let allSuggestions = try await searchService.getSuggestedUsers(limit: fetchLimit)
        
        print("💡 SUGGESTION: Got \(allSuggestions.count) raw suggestions")
        
        // ✅ FIX: Filter out already shown AND already following
        let followingIDs = try await userService.getFollowingIDs(userID: currentUserID)
        
        let filteredSuggestions = allSuggestions.filter { user in
            let notShown = !shownUserIDs.contains(user.id)
            let notFollowing = !followingIDs.contains(user.id)
            let notSelf = user.id != currentUserID
            
            return notShown && notFollowing && notSelf
        }
        
        print("💡 SUGGESTION: Filtered to \(filteredSuggestions.count) new suggestions")
        
        // Take only what we need
        let finalSuggestions = Array(filteredSuggestions.prefix(limit))
        
        // Track shown users
        for user in finalSuggestions {
            shownUserIDs.insert(user.id)
        }
        
        // ✅ FIX: Reset tracking if we've shown too many
        if shownUserIDs.count > maxShownBeforeReset {
            print("💡 SUGGESTION: Resetting shown users (had \(shownUserIDs.count))")
            shownUserIDs.removeAll()
        }
        
        lastRefreshTime = Date()
        
        print("💡 SUGGESTION: Returning \(finalSuggestions.count) unique suggestions")
        return finalSuggestions
    }
    
    /// Refresh suggestions manually (clears shown tracking)
    func refreshSuggestions(limit: Int = 10) async throws -> [BasicUserInfo] {
        print("💡 SUGGESTION: Manual refresh - clearing shown users")
        
        // ✅ FIX: Clear shown users on manual refresh for truly new content
        shownUserIDs.removeAll()
        lastRefreshTime = nil
        
        return try await getSuggestions(limit: limit)
    }
    
    /// Check if should show suggestion card based on user state and position
    func shouldShowSuggestionCard(
        userID: String,
        currentVideoIndex: Int
    ) async -> Bool {
        
        do {
            let followingCount = try await getFollowingCount(userID: userID)
            
            if followingCount == 0 {
                // New user: Show every 5 videos
                return currentVideoIndex > 0 && currentVideoIndex % 5 == 0
            } else if followingCount <= 10 {
                // Expanding: Show every 10 videos
                return currentVideoIndex > 0 && currentVideoIndex % 10 == 0
            } else {
                // Established: Show every 15 videos
                return currentVideoIndex > 0 && currentVideoIndex % 15 == 0
            }
        } catch {
            print("❌ SUGGESTION: Error checking show condition: \(error)")
            return false
        }
    }
    
    /// Get user's following count
    private func getFollowingCount(userID: String) async throws -> Int {
        // Get following IDs from UserService
        do {
            let followingIDs = try await userService.getFollowingIDs(userID: userID)
            return followingIDs.count
        } catch {
            print("❌ SUGGESTION: Error getting following count: \(error)")
            return 0
        }
    }
    
    /// Reset shown user tracking (for testing)
    func resetShownUsers() {
        shownUserIDs.removeAll()
        print("💡 SUGGESTION: Manually reset shown users")
    }
    
    /// Get stats for debugging
    func getStats() -> (shown: Int, maxBeforeReset: Int) {
        return (shownUserIDs.count, maxShownBeforeReset)
    }
}
