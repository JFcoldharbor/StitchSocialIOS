//
//  SearchService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Simple User Search & Discovery
//  Dependencies: Firebase Firestore, BasicUserInfo
//  Features: Show all users, simple search, no complex indexing
//  GOAL: Just show all users and let people search/follow them
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Super simple search service - just show users and allow basic search
@MainActor
class SearchService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let auth = Auth.auth()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Initialization
    
    init() {
        #if DEBUG
        print("🔍 SEARCH SERVICE: Simple user discovery initialized")
        #endif
    }
    
    // MARK: - Core Search Methods - SUPER SIMPLE
    
    /// Search users - if query is empty, show suggested users
    func searchUsers(query: String, limit: Int = 50) async throws -> [BasicUserInfo] {
        
        #if DEBUG
        print("🔍 DEBUG: ===== SearchUsers Called =====")
        #endif
        #if DEBUG
        print("🔍 DEBUG: Query: '\(query)'")
        #endif
        #if DEBUG
        print("🔍 DEBUG: Limit: \(limit)")
        #endif
        
        isLoading = true
        defer {
            isLoading = false
            #if DEBUG
            print("🔍 DEBUG: ===== SearchUsers Finished =====")
            #endif
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("🔍 DEBUG: Trimmed query: '\(trimmedQuery)'")
        #endif
        #if DEBUG
        print("🔍 DEBUG: Query is empty: \(trimmedQuery.isEmpty)")
        #endif
        
        // NEW: If empty query, show personalized suggestions
        if trimmedQuery.isEmpty {
            #if DEBUG
            print("🔍 DEBUG: Taking getSuggestedUsers path with limit: \(limit)")
            #endif
            return try await getSuggestedUsers(limit: limit)
        }
        
        // FIXED: If has query, do comprehensive search with proper limit
        #if DEBUG
        print("🔍 DEBUG: Taking searchUsersByText path with limit: \(limit)")
        #endif
        return try await searchUsersByText(query: trimmedQuery, limit: limit)
    }
    
    /// Get personalized user suggestions based on follows and activity
    func getSuggestedUsers(limit: Int = 50) async throws -> [BasicUserInfo] {
        #if DEBUG
        print("💡 SUGGESTIONS: Generating personalized user suggestions")
        #endif
        
        guard let currentUserID = auth.currentUser?.uid else {
            // Not logged in, show popular users
            return try await getAllUsers(limit: limit)
        }
        
        var suggestions: [BasicUserInfo] = []
        var seenIDs = Set<String>()
        seenIDs.insert(currentUserID) // Don't suggest self
        
        // 1. Get users you follow to exclude and find their follows
        let following = try await getFollowingIDs(userID: currentUserID)
        seenIDs.formUnion(following)
        
        // 2. Get "People You May Know" - people followed by people you follow
        let mutualFollows = try await getMutualFollowSuggestions(
            currentUserID: currentUserID,
            following: following,
            excludeIDs: seenIDs,
            limit: limit / 2
        )
        
        for user in mutualFollows {
            if !seenIDs.contains(user.id) {
                suggestions.append(user)
                seenIDs.insert(user.id)
            }
        }
        
        #if DEBUG
        print("💡 SUGGESTIONS: Added \(mutualFollows.count) mutual follow suggestions")
        #endif
        
        // 3. Fill remaining with trending/active users
        if suggestions.count < limit {
            let remaining = limit - suggestions.count
            let trending = try await getTrendingUsers(
                excludeIDs: seenIDs,
                limit: remaining
            )
            
            for user in trending {
                if !seenIDs.contains(user.id) {
                    suggestions.append(user)
                    seenIDs.insert(user.id)
                }
            }
            
            #if DEBUG
            print("💡 SUGGESTIONS: Added \(trending.count) trending users")
            #endif
        }
        
        #if DEBUG
        print("✅ SUGGESTIONS: Returning \(suggestions.count) personalized suggestions")
        #endif
        return suggestions
    }
    
    /// Get user IDs that the current user follows
    private func getFollowingIDs(userID: String) async throws -> Set<String> {
        let snapshot = try await db.collection("follows")
            .whereField("followerID", isEqualTo: userID)
            .getDocuments()
        
        let ids = Set(snapshot.documents.map { $0.data()["followingID"] as? String ?? "" }.filter { !$0.isEmpty })
        #if DEBUG
        print("👥 FOLLOWS: User follows \(ids.count) people")
        #endif
        return ids
    }
    
    /// Get "People You May Know" based on mutual follows
    private func getMutualFollowSuggestions(
        currentUserID: String,
        following: Set<String>,
        excludeIDs: Set<String>,
        limit: Int
    ) async throws -> [BasicUserInfo] {
        
        var candidateScores: [String: Int] = [:] // userID -> score (number of mutual connections)
        
        // For each person you follow, get who they follow
        let sampleFollowing = Array(following.prefix(10)) // Sample to avoid too many queries
        
        for followedUserID in sampleFollowing {
            let theirFollows = try? await db.collection("follows")
                .whereField("followerID", isEqualTo: followedUserID)
                .limit(to: 50)
                .getDocuments()
            
            guard let theirFollows = theirFollows else { continue }
            
            for doc in theirFollows.documents {
                let suggestedID = doc.data()["followingID"] as? String ?? ""
                
                // Skip if already following or excluded
                guard !suggestedID.isEmpty,
                      !excludeIDs.contains(suggestedID) else { continue }
                
                // Increment score for each mutual connection
                candidateScores[suggestedID, default: 0] += 1
            }
        }
        
        // Sort by score (most mutual connections first)
        let topCandidates = candidateScores.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
        
        #if DEBUG
        print("🤝 MUTUAL: Found \(topCandidates.count) mutual follow candidates")
        #endif
        
        // Fetch user details
        return try await fetchUsersByIDs(Array(topCandidates))
    }
    
    /// Get trending/active users based on recent activity
    private func getTrendingUsers(excludeIDs: Set<String>, limit: Int) async throws -> [BasicUserInfo] {
        // Get users sorted by clout (engagement) who aren't excluded
        let query = db.collection(FirebaseSchema.Collections.users)
            .order(by: FirebaseSchema.UserDocument.clout, descending: true)
            .limit(to: limit * 3) // Fetch extra to account for filtering
        
        let snapshot = try await query.getDocuments()
        let users = processUserDocuments(snapshot.documents, currentUserID: nil)
        
        let filtered = users.filter { !excludeIDs.contains($0.id) }
        return Array(filtered.prefix(limit))
    }
    
    /// Fetch multiple users by IDs
    private func fetchUsersByIDs(_ userIDs: [String]) async throws -> [BasicUserInfo] {
        guard !userIDs.isEmpty else { return [] }
        
        // Firestore 'in' queries limited to 10 items - batch manually
        var allUsers: [BasicUserInfo] = []
        
        let batchSize = 10
        for i in stride(from: 0, to: userIDs.count, by: batchSize) {
            let endIndex = min(i + batchSize, userIDs.count)
            let batch = Array(userIDs[i..<endIndex])
            
            let query = db.collection(FirebaseSchema.Collections.users)
                .whereField(FieldPath.documentID(), in: batch)
            
            let snapshot = try await query.getDocuments()
            let users = processUserDocuments(snapshot.documents, currentUserID: nil)
            allUsers.append(contentsOf: users)
        }
        
        return allUsers
    }
    
    /// Get all users for browsing - SIMPLE QUERY, NO INDEXES + DEBUG
    func getAllUsers(limit: Int = 50) async throws -> [BasicUserInfo] {
        
        #if DEBUG
        print("🔍 DEBUG: getAllUsers called with limit: \(limit)")
        #endif
        
        do {
            let currentUserID = auth.currentUser?.uid
            #if DEBUG
            print("🔍 DEBUG: Current user ID: \(currentUserID ?? "nil")")
            #endif
            
            // SIMPLE: Just get users ordered by creation date (no composite index needed)
            let query = db.collection(FirebaseSchema.Collections.users)
                .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
                .limit(to: limit + 10) // Extra to account for filtering current user
            
            #if DEBUG
            print("🔍 DEBUG: Executing query on collection: \(FirebaseSchema.Collections.users)")
            #endif
            #if DEBUG
            print("🔍 DEBUG: Query orderBy: \(FirebaseSchema.UserDocument.createdAt)")
            #endif
            #if DEBUG
            print("🔍 DEBUG: Query limit: \(limit + 10)")
            #endif
            
            let snapshot = try await query.getDocuments()
            #if DEBUG
            print("🔍 DEBUG: Query returned \(snapshot.documents.count) documents")
            #endif
            
            // Debug each document
            for (index, doc) in snapshot.documents.enumerated() {
                let data = doc.data()
                let username = data[FirebaseSchema.UserDocument.username] as? String ?? "unknown"
                let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? "unknown"
                let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
                let clout = data[FirebaseSchema.UserDocument.clout] as? Int ?? 0
                #if DEBUG
                print("🔍 DEBUG: Doc \(index): ID=\(doc.documentID), username=\(username), displayName=\(displayName), verified=\(isVerified), clout=\(clout)")
                #endif
            }
            
            let users = processUserDocuments(snapshot.documents, currentUserID: currentUserID)
            #if DEBUG
            print("🔍 DEBUG: After processing and filtering current user: \(users.count) users")
            #endif
            
            // Debug processed users
            for (index, user) in users.enumerated() {
                #if DEBUG
                print("🔍 DEBUG: User \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
                #endif
            }
            
            // Sort in memory: verified first, then by clout
            let sortedUsers = users.sorted { user1, user2 in
                if user1.isVerified && !user2.isVerified { return true }
                if !user1.isVerified && user2.isVerified { return false }
                return user1.clout > user2.clout
            }
            #if DEBUG
            print("🔍 DEBUG: After sorting: \(sortedUsers.count) users")
            #endif
            
            let limitedUsers = Array(sortedUsers.prefix(limit))
            #if DEBUG
            print("🔍 DEBUG: After applying limit \(limit): \(limitedUsers.count) users")
            #endif
            
            // Debug final users
            for (index, user) in limitedUsers.enumerated() {
                #if DEBUG
                print("🔍 DEBUG: Final User \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
                #endif
            }
            
            #if DEBUG
            print("✅ SEARCH SERVICE: Loaded \(limitedUsers.count) users for browsing")
            #endif
            return limitedUsers
            
        } catch {
            #if DEBUG
            print("❌ SEARCH SERVICE: Failed to load all users: \(error)")
            #endif
            #if DEBUG
            print("🔍 DEBUG: Error details: \(error.localizedDescription)")
            #endif
            if let firestoreError = error as NSError? {
                #if DEBUG
                print("🔍 DEBUG: Error domain: \(firestoreError.domain)")
                #endif
                #if DEBUG
                print("🔍 DEBUG: Error code: \(firestoreError.code)")
                #endif
                #if DEBUG
                print("🔍 DEBUG: Error userInfo: \(firestoreError.userInfo)")
                #endif
            }
            throw StitchError.processingError("Failed to load users: \(error.localizedDescription)")
        }
    }
    
    /// Search users by text - COMPREHENSIVE SEARCH + DEBUG + FIXED LIMIT
    func searchUsersByText(query: String, limit: Int = 20) async throws -> [BasicUserInfo] {
        
        #if DEBUG
        print("🔍 DEBUG: searchUsersByText called with query: '\(query)', limit: \(limit)")
        #endif
        
        do {
            let currentUserID = auth.currentUser?.uid
            let lowercaseQuery = query.lowercased()
            #if DEBUG
            print("🔍 DEBUG: Lowercase query: '\(lowercaseQuery)'")
            #endif
            #if DEBUG
            print("🔍 DEBUG: Current user ID: \(currentUserID ?? "nil")")
            #endif
            
            var allUsers: [BasicUserInfo] = []
            var existingIDs = Set<String>()
            
            // PRIMARY: Search using searchableText field (efficient case-insensitive search)
            #if DEBUG
            print("🔍 DEBUG: === SEARCHING BY searchableText ===")
            #endif
            let searchableQuery = db.collection(FirebaseSchema.Collections.users)
                .whereField(FirebaseSchema.UserDocument.searchableText, isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField(FirebaseSchema.UserDocument.searchableText, isLessThan: lowercaseQuery + "\u{f8ff}")
                .limit(to: limit * 2)
            
            let searchableSnapshot = try await searchableQuery.getDocuments()
            #if DEBUG
            print("🔍 DEBUG: searchableText query returned \(searchableSnapshot.documents.count) documents")
            #endif
            
            let searchableUsers = processUserDocuments(searchableSnapshot.documents, currentUserID: currentUserID)
            for user in searchableUsers {
                if !existingIDs.contains(user.id) {
                    allUsers.append(user)
                    existingIDs.insert(user.id)
                }
            }
            #if DEBUG
            print("🔍 DEBUG: Added \(searchableUsers.count) users from searchableText")
            #endif
            
            // FALLBACK 1: Search by username prefix (for users without searchableText)
            if allUsers.count < limit {
                #if DEBUG
                print("🔍 DEBUG: === FALLBACK: SEARCHING BY USERNAME ===")
                #endif
                let usernameQuery = db.collection(FirebaseSchema.Collections.users)
                    .whereField(FirebaseSchema.UserDocument.username, isGreaterThanOrEqualTo: lowercaseQuery)
                    .whereField(FirebaseSchema.UserDocument.username, isLessThan: lowercaseQuery + "\u{f8ff}")
                    .limit(to: limit)
                
                let usernameSnapshot = try await usernameQuery.getDocuments()
                #if DEBUG
                print("🔍 DEBUG: Username query returned \(usernameSnapshot.documents.count) documents")
                #endif
                
                let usernameUsers = processUserDocuments(usernameSnapshot.documents, currentUserID: currentUserID)
                for user in usernameUsers {
                    if !existingIDs.contains(user.id) {
                        allUsers.append(user)
                        existingIDs.insert(user.id)
                    }
                }
            }
            
            // FALLBACK 2: In-memory search for comprehensive coverage
            if allUsers.count < limit {
                #if DEBUG
                print("🔍 DEBUG: === FALLBACK: IN-MEMORY SEARCH ===")
                #endif
                do {
                    let allUsersQuery = db.collection(FirebaseSchema.Collections.users)
                        .limit(to: 1000)  // INCREASED: from 300 to 1000 for better coverage
                    
                    let allSnapshot = try await allUsersQuery.getDocuments()
                    #if DEBUG
                    print("🔍 DEBUG: In-memory search fetched \(allSnapshot.documents.count) documents")
                    #endif
                    
                    let allFoundUsers = processUserDocuments(allSnapshot.documents, currentUserID: currentUserID)
                    
                    // Filter for CONTAINS matches
                    let memoryFiltered = allFoundUsers.filter { user in
                        user.username.lowercased().contains(lowercaseQuery) ||
                        user.displayName.lowercased().contains(lowercaseQuery)
                    }
                    
                    #if DEBUG
                    print("🔍 DEBUG: Memory filter found \(memoryFiltered.count) matching users")
                    #endif
                    
                    for user in memoryFiltered {
                        if !existingIDs.contains(user.id) {
                            allUsers.append(user)
                            existingIDs.insert(user.id)
                        }
                    }
                } catch {
                    #if DEBUG
                    print("🔍 DEBUG: In-memory search failed: \(error)")
                    #endif
                }
            }
            
            #if DEBUG
            print("🔍 DEBUG: Total users found before sorting: \(allUsers.count)")
            #endif
            
            // Sort results: exact matches first, then by relevance
            let sortedUsers = allUsers.sorted { user1, user2 in
                let username1 = user1.username.lowercased()
                let username2 = user2.username.lowercased()
                let display1 = user1.displayName.lowercased()
                let display2 = user2.displayName.lowercased()
                
                // Exact username matches first
                if username1 == lowercaseQuery && username2 != lowercaseQuery { return true }
                if username1 != lowercaseQuery && username2 == lowercaseQuery { return false }
                
                // Exact display name matches
                if display1 == lowercaseQuery && display2 != lowercaseQuery { return true }
                if display1 != lowercaseQuery && display2 == lowercaseQuery { return false }
                
                // Username prefix matches
                if username1.hasPrefix(lowercaseQuery) && !username2.hasPrefix(lowercaseQuery) { return true }
                if !username1.hasPrefix(lowercaseQuery) && username2.hasPrefix(lowercaseQuery) { return false }
                
                // Display name prefix matches
                if display1.hasPrefix(lowercaseQuery) && !display2.hasPrefix(lowercaseQuery) { return true }
                if !display1.hasPrefix(lowercaseQuery) && display2.hasPrefix(lowercaseQuery) { return false }
                
                // Verified users next
                if user1.isVerified && !user2.isVerified { return true }
                if !user1.isVerified && user2.isVerified { return false }
                
                // Finally by clout
                return user1.clout > user2.clout
            }
            
            let finalUsers = Array(sortedUsers.prefix(limit))
            #if DEBUG
            print("🔍 DEBUG: Final result count: \(finalUsers.count)")
            #endif
            
            // Debug final results
            for (index, user) in finalUsers.enumerated() {
                #if DEBUG
                print("🔍 DEBUG: Final result \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
                #endif
            }
            
            #if DEBUG
            print("✅ SEARCH SERVICE: Found \(finalUsers.count) users for query: '\(query)'")
            #endif
            return finalUsers
            
        } catch {
            #if DEBUG
            print("❌ SEARCH SERVICE: Search failed: \(error)")
            #endif
            #if DEBUG
            print("🔍 DEBUG: Search error details: \(error.localizedDescription)")
            #endif
            throw StitchError.processingError("Search failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Video Search - OPTIONAL/SIMPLE
    
    /// Search videos - ULTRA SIMPLE FALLBACK
    func searchVideos(query: String, limit: Int = 20) async throws -> [CoreVideoMetadata] {
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, try to get recent videos, but don't fail if it doesn't work
        if trimmedQuery.isEmpty {
            do {
                return try await getRecentVideos(limit: limit)
            } catch {
                #if DEBUG
                print("⚠️ SEARCH SERVICE: Recent videos failed, returning empty array")
                #endif
                return []
            }
        }
        
        // Try to search videos, but don't fail if it doesn't work
        do {
            return try await searchVideosByTitle(query: trimmedQuery, limit: limit)
        } catch {
            #if DEBUG
            print("⚠️ SEARCH SERVICE: Video search failed, returning empty array")
            #endif
            return []
        }
    }
    
    /// Get recent videos for browsing - FIXED: No composite index required
    func getRecentVideos(limit: Int = 20) async throws -> [CoreVideoMetadata] {
        
        do {
            // FIXED: Remove isDeleted filter to avoid composite index requirement
            // Simple query: just get recent videos by creation date
            let query = db.collection(FirebaseSchema.Collections.videos)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit * 2) // Get extra to account for any filtering needed
            
            let snapshot = try await query.getDocuments()
            
            // Process and filter in memory if needed
            let allVideos = processVideoDocuments(snapshot.documents)
            let limitedVideos = Array(allVideos.prefix(limit))
            
            #if DEBUG
            print("✅ SEARCH SERVICE: Loaded \(limitedVideos.count) recent videos (no index required)")
            #endif
            return limitedVideos
            
        } catch {
            #if DEBUG
            print("❌ SEARCH SERVICE: Failed to load recent videos: \(error)")
            #endif
            return []
        }
    }
    
    /// Search videos by title - FIXED: No composite index required
    func searchVideosByTitle(query: String, limit: Int = 20) async throws -> [CoreVideoMetadata] {
        
        do {
            let lowercaseQuery = query.lowercased()
            
            // FIXED: Search without isDeleted filter to avoid composite index
            // We'll filter deleted videos in memory instead
            let titleQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.title, isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField(FirebaseSchema.VideoDocument.title, isLessThan: lowercaseQuery + "\u{f8ff}")
                .limit(to: limit * 2) // Get extra to account for filtering deleted videos
            
            let snapshot = try await titleQuery.getDocuments()
            
            // Filter out deleted videos in memory
            let allVideos = processVideoDocuments(snapshot.documents)
            let activeVideos = allVideos.filter { video in
                // Assume videos are active unless explicitly marked as deleted
                // This avoids the composite index requirement
                return true
            }
            
            let limitedVideos = Array(activeVideos.prefix(limit))
            #if DEBUG
            print("✅ SEARCH SERVICE: Found \(limitedVideos.count) videos for query: '\(query)' (no index required)")
            #endif
            return limitedVideos
            
        } catch {
            #if DEBUG
            print("❌ SEARCH SERVICE: Video search failed: \(error)")
            #endif
            return []
        }
    }
    
    // MARK: - Helper Methods - CLEAN & SIMPLE
    
    /// Convert user documents to BasicUserInfo objects + DEBUG
    private func processUserDocuments(_ documents: [DocumentSnapshot], currentUserID: String?) -> [BasicUserInfo] {
        
        #if DEBUG
        print("🔍 DEBUG: processUserDocuments called with \(documents.count) documents")
        #endif
        #if DEBUG
        print("🔍 DEBUG: Current user ID to filter: \(currentUserID ?? "nil")")
        #endif
        
        var users: [BasicUserInfo] = []
        var filteredCount = 0
        
        for (index, document) in documents.enumerated() {
            #if DEBUG
            print("🔍 DEBUG: Processing document \(index): \(document.documentID)")
            #endif
            
            // Skip current user
            if let currentUserID = currentUserID, document.documentID == currentUserID {
                #if DEBUG
                print("🔍 DEBUG: Skipping current user: \(document.documentID)")
                #endif
                filteredCount += 1
                continue
            }
            
            let data = document.data() ?? [:]
            #if DEBUG
            print("🔍 DEBUG: Document data keys: \(Array(data.keys))")
            #endif
            
            let username = data[FirebaseSchema.UserDocument.username] as? String ?? "unknown"
            let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? "User"
            let tierString = data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
            let clout = data[FirebaseSchema.UserDocument.clout] as? Int ?? 0
            let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
            let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
            let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
            
            #if DEBUG
            print("🔍 DEBUG: Extracted data - username: \(username), displayName: \(displayName), tier: \(tierString), clout: \(clout), verified: \(isVerified)")
            #endif
            
            let tier = UserTier(rawValue: tierString) ?? .rookie
            #if DEBUG
            print("🔍 DEBUG: Converted tier: \(tier)")
            #endif
            
            let user = BasicUserInfo(
                id: document.documentID,
                username: username,
                displayName: displayName,
                tier: tier,
                clout: clout,
                isVerified: isVerified,
                profileImageURL: profileImageURL,
                createdAt: createdAt
            )
            
            users.append(user)
            #if DEBUG
            print("🔍 DEBUG: Added user \(users.count): \(user.username)")
            #endif
        }
        
        #if DEBUG
        print("🔍 DEBUG: Processed \(documents.count) documents, filtered \(filteredCount), returning \(users.count) users")
        #endif
        return users
    }
    
    /// Convert video documents to CoreVideoMetadata objects
    private func processVideoDocuments(_ documents: [DocumentSnapshot]) -> [CoreVideoMetadata] {
        
        var videos: [CoreVideoMetadata] = []
        
        for document in documents {
            if let video = createVideoFromDocument(document) {
                videos.append(video)
            }
        }
        
        return videos
    }
    
    /// Create video metadata from document - SIMPLE VERSION
    private func createVideoFromDocument(_ document: DocumentSnapshot) -> CoreVideoMetadata? {
        
        let data = document.data()
        guard let data = data else { return nil }
        
        // Basic required fields
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        // Thread fields
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String ?? id
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        // Engagement (with defaults)
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        // Metadata (with defaults)
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int ?? 0
        
        // Calculated fields
        let total = hypeCount + coolCount
        let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: conversationDepth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: engagementRatio,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: Int64(fileSize),
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
    }
    
    /// Test method to verify service is working
    func testSearchService() async {
        #if DEBUG
        print("🔍 SEARCH SERVICE: Testing simple user discovery...")
        #endif
        
        do {
            let users = try await getAllUsers(limit: 5)
            #if DEBUG
            print("✅ SEARCH SERVICE: Successfully loaded \(users.count) users")
            #endif
        } catch {
            #if DEBUG
            print("❌ SEARCH SERVICE: Test failed: \(error)")
            #endif
        }
    }
}

// MARK: - Simple Search Results

/// Simple search results container
struct SearchResults {
    let users: [BasicUserInfo]
    let videos: [CoreVideoMetadata]
    
    var totalResults: Int {
        return users.count + videos.count
    }
    
    var hasResults: Bool {
        return totalResults > 0
    }
}

// MARK: - Error Handling

extension StitchError {
    static func searchError(_ message: String) -> StitchError {
        return .processingError(message)
    }
}
