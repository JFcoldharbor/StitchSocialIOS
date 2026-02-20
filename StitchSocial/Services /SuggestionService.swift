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
import FirebaseFirestore

// MARK: - Mutual Follower Suggestion Model

struct UserSuggestion: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let profileImageURL: String?
    let tier: String
    let mutualCount: Int
    let mutualNames: [String]
    var isFollowed: Bool = false
}

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
    
    // MARK: - Mutual Follower State
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    @Published var mutualSuggestions: [UserSuggestion] = []
    @Published var isMutualLoading = false
    @Published var hasMutualLoaded = false
    
    // Session cache — avoids recomputing on every open
    // CACHING: 10 min TTL. Pre-computed path = 1 read. Client fallback = N+1 reads.
    private var mutualCachedAt: Date?
    private let mutualCacheTTL: TimeInterval = 600
    
    // MARK: - People You May Know (Mutual Followers)
    
    /// Load mutual follower suggestions. Tries pre-computed first (1 read), falls back to client-side.
    func loadMutualSuggestions(userID: String) async {
        // Return cache if fresh
        if let cachedAt = mutualCachedAt,
           Date().timeIntervalSince(cachedAt) < mutualCacheTTL,
           !mutualSuggestions.isEmpty {
            print("👥 SUGGESTIONS: Returning cached \(mutualSuggestions.count) mutual suggestions")
            return
        }
        
        isMutualLoading = true
        defer {
            isMutualLoading = false
            hasMutualLoaded = true
        }
        
        // Try pre-computed suggestions first (1 read from Cloud Function)
        if let precomputed = await loadPrecomputedSuggestions(userID: userID) {
            mutualSuggestions = precomputed
            mutualCachedAt = Date()
            print("👥 SUGGESTIONS: Loaded \(precomputed.count) pre-computed mutual suggestions")
            return
        }
        
        // Fallback: compute client-side
        let computed = await computeMutualFollowers(userID: userID)
        mutualSuggestions = computed
        mutualCachedAt = Date()
        print("👥 SUGGESTIONS: Computed \(computed.count) mutual suggestions client-side")
    }
    
    /// Read pre-computed suggestions from socialSignals subcollection — 1 doc read.
    /// Cloud Function writes: users/{uid}/socialSignals/suggested_users
    private func loadPrecomputedSuggestions(userID: String) async -> [UserSuggestion]? {
        do {
            let doc = try await db.collection("users")
                .document(userID)
                .collection("socialSignals")
                .document("suggested_users")
                .getDocument()
            
            guard doc.exists,
                  let data = doc.data(),
                  let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
                  Date().timeIntervalSince(updatedAt) < 86400,
                  let suggestionsData = data["suggestions"] as? [[String: Any]] else {
                return nil
            }
            
            return suggestionsData.compactMap { item -> UserSuggestion? in
                guard let uid = item["userID"] as? String else { return nil }
                return UserSuggestion(
                    id: uid,
                    username: item["username"] as? String ?? "",
                    displayName: item["displayName"] as? String ?? "",
                    profileImageURL: item["profileImageURL"] as? String,
                    tier: item["tier"] as? String ?? "rookie",
                    mutualCount: item["mutualCount"] as? Int ?? 0,
                    mutualNames: item["mutualNames"] as? [String] ?? []
                )
            }
        } catch {
            print("⚠️ SUGGESTIONS: Pre-computed read failed: \(error)")
            return nil
        }
    }
    
    /// Client-side mutual follower computation. Capped at 50 following reads.
    /// BATCHING: Reads 5 following lists concurrently, uses IN query for profile fetch (10 per call).
    private func computeMutualFollowers(userID: String) async -> [UserSuggestion] {
        do {
            // Get who I follow (reuse PrivacyService cache if available)
            let myFollowing: Set<String>
            if !PrivacyService.shared.cachedFollowingIDs.isEmpty {
                myFollowing = PrivacyService.shared.cachedFollowingIDs
            } else {
                let followingIDs = try await userService.getFollowingIDs(userID: userID)
                myFollowing = Set(followingIDs)
            }
            
            guard !myFollowing.isEmpty else { return [] }
            
            let sampled = Array(myFollowing.prefix(50))
            var candidateCounts: [String: Int] = [:]
            var candidateMutuals: [String: [String]] = [:]
            
            // Batch 5 at a time to limit concurrent reads
            for chunk in stride(from: 0, to: sampled.count, by: 5).map({ Array(sampled[$0..<min($0 + 5, sampled.count)]) }) {
                await withTaskGroup(of: (String, [String]).self) { group in
                    for followedUserID in chunk {
                        group.addTask { [db] in
                            do {
                                let snap = try await db.collection("users")
                                    .document(followedUserID)
                                    .collection("following")
                                    .limit(to: 100)
                                    .getDocuments()
                                return (followedUserID, snap.documents.map { $0.documentID })
                            } catch {
                                return (followedUserID, [])
                            }
                        }
                    }
                    
                    for await (mutualUserID, theirFollowing) in group {
                        let mutualUsername = await fetchUsernameForSuggestion(mutualUserID)
                        
                        for candidateID in theirFollowing {
                            guard candidateID != userID,
                                  !myFollowing.contains(candidateID) else { continue }
                            
                            candidateCounts[candidateID, default: 0] += 1
                            if (candidateMutuals[candidateID]?.count ?? 0) < 3 {
                                candidateMutuals[candidateID, default: []].append(mutualUsername)
                            }
                        }
                    }
                }
            }
            
            // Rank by mutual count, top 20
            let ranked = candidateCounts.sorted { $0.value > $1.value }.prefix(20)
            let topIDs = ranked.map { $0.key }
            let profiles = await batchFetchProfilesForSuggestion(userIDs: topIDs)
            
            return ranked.compactMap { (candidateID, mutualCount) -> UserSuggestion? in
                guard let profile = profiles[candidateID] else { return nil }
                return UserSuggestion(
                    id: candidateID,
                    username: profile["username"] as? String ?? "",
                    displayName: profile["displayName"] as? String ?? "",
                    profileImageURL: profile["profileImageURL"] as? String,
                    tier: profile["tier"] as? String ?? "rookie",
                    mutualCount: mutualCount,
                    mutualNames: candidateMutuals[candidateID] ?? []
                )
            }
        } catch {
            print("⚠️ SUGGESTIONS: Mutual compute failed: \(error)")
            return []
        }
    }
    
    private func fetchUsernameForSuggestion(_ userID: String) async -> String {
        do {
            let doc = try await db.collection("users").document(userID).getDocument()
            return doc.data()?["username"] as? String ?? "user"
        } catch {
            return "user"
        }
    }
    
    /// Batch fetch profiles using Firestore IN query (max 10 per call)
    private func batchFetchProfilesForSuggestion(userIDs: [String]) async -> [String: [String: Any]] {
        guard !userIDs.isEmpty else { return [:] }
        var results: [String: [String: Any]] = [:]
        
        let chunks = stride(from: 0, to: userIDs.count, by: 10).map {
            Array(userIDs[$0..<min($0 + 10, userIDs.count)])
        }
        
        for chunk in chunks {
            do {
                let snapshot = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                for doc in snapshot.documents {
                    results[doc.documentID] = doc.data()
                }
            } catch {
                print("⚠️ SUGGESTIONS: Batch profile fetch failed: \(error)")
            }
        }
        
        return results
    }
    
    // MARK: - Mutual Follow Action
    
    /// Follow from People You May Know — batch write + instant UI update
    func followSuggestedUser(_ suggestionID: String, currentUserID: String) async {
        if let index = mutualSuggestions.firstIndex(where: { $0.id == suggestionID }) {
            mutualSuggestions[index].isFollowed = true
        }
        
        let batch = db.batch()
        let followingRef = db.collection("users").document(currentUserID)
            .collection("following").document(suggestionID)
        let followerRef = db.collection("users").document(suggestionID)
            .collection("followers").document(currentUserID)
        
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followingRef)
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followerRef)
        batch.updateData(["followingCount": FieldValue.increment(Int64(1))],
                         forDocument: db.collection("users").document(currentUserID))
        batch.updateData(["followerCount": FieldValue.increment(Int64(1))],
                         forDocument: db.collection("users").document(suggestionID))
        
        do {
            try await batch.commit()
            PrivacyService.shared.invalidateFollowingCache()
            print("👥 SUGGESTIONS: Followed \(suggestionID)")
        } catch {
            print("⚠️ SUGGESTIONS: Follow failed: \(error)")
            if let index = mutualSuggestions.firstIndex(where: { $0.id == suggestionID }) {
                mutualSuggestions[index].isFollowed = false
            }
        }
    }
    
    // MARK: - Cleanup
    
    func clearMutualCache() {
        mutualSuggestions = []
        mutualCachedAt = nil
        hasMutualLoaded = false
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
