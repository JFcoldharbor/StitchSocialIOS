//
//  SuggestionService.swift
//  StitchSocial
//
//  Layer 4: Services - User Suggestion Service (Uses SearchService)
//  Dependencies: SearchService, FollowManager
//  Features: Smart display logic, frequency control
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
        
        print("💡 SUGGESTION SERVICE: Initialized")
    }
    
    // MARK: - Main Methods
    
    /// Get suggested users (delegates to SearchService)
    func getSuggestions(limit: Int = 10) async throws -> [BasicUserInfo] {
        isLoading = true
        defer { isLoading = false }
        
        print("💡 SUGGESTION: Getting suggestions from SearchService")
        
        // Use SearchService's getSuggestedUsers method
        let suggestions = try await searchService.getSuggestedUsers(limit: limit)
        
        lastRefreshTime = Date()
        
        print("💡 SUGGESTION: Got \(suggestions.count) suggestions")
        return suggestions
    }
    
    /// Refresh suggestions manually
    func refreshSuggestions(limit: Int = 10) async throws -> [BasicUserInfo] {
        print("💡 SUGGESTION: Manual refresh requested")
        lastRefreshTime = nil // Clear cache
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
}
