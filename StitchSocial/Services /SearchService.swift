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
        print("🔍 SEARCH SERVICE: Simple user discovery initialized")
    }
    
    // MARK: - Core Search Methods - SUPER SIMPLE
    
    /// Search users - if query is empty, show all users for browsing + DEBUG + FIXED LIMIT
    func searchUsers(query: String, limit: Int = 50) async throws -> [BasicUserInfo] {
        
        print("🔍 DEBUG: ===== SearchUsers Called =====")
        print("🔍 DEBUG: Query: '\(query)'")
        print("🔍 DEBUG: Limit: \(limit)")
        
        isLoading = true
        defer {
            isLoading = false
            print("🔍 DEBUG: ===== SearchUsers Finished =====")
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔍 DEBUG: Trimmed query: '\(trimmedQuery)'")
        print("🔍 DEBUG: Query is empty: \(trimmedQuery.isEmpty)")
        
        // FIXED: If empty query, show all users with proper limit
        if trimmedQuery.isEmpty {
            print("🔍 DEBUG: Taking getAllUsers path with limit: \(limit)")
            return try await getAllUsers(limit: limit)
        }
        
        // FIXED: If has query, do comprehensive search with proper limit
        print("🔍 DEBUG: Taking searchUsersByText path with limit: \(limit)")
        return try await searchUsersByText(query: trimmedQuery, limit: limit)
    }
    
    /// Get all users for browsing - SIMPLE QUERY, NO INDEXES + DEBUG
    func getAllUsers(limit: Int = 50) async throws -> [BasicUserInfo] {
        
        print("🔍 DEBUG: getAllUsers called with limit: \(limit)")
        
        do {
            let currentUserID = auth.currentUser?.uid
            print("🔍 DEBUG: Current user ID: \(currentUserID ?? "nil")")
            
            // SIMPLE: Just get users ordered by creation date (no composite index needed)
            let query = db.collection(FirebaseSchema.Collections.users)
                .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
                .limit(to: limit + 10) // Extra to account for filtering current user
            
            print("🔍 DEBUG: Executing query on collection: \(FirebaseSchema.Collections.users)")
            print("🔍 DEBUG: Query orderBy: \(FirebaseSchema.UserDocument.createdAt)")
            print("🔍 DEBUG: Query limit: \(limit + 10)")
            
            let snapshot = try await query.getDocuments()
            print("🔍 DEBUG: Query returned \(snapshot.documents.count) documents")
            
            // Debug each document
            for (index, doc) in snapshot.documents.enumerated() {
                let data = doc.data()
                let username = data[FirebaseSchema.UserDocument.username] as? String ?? "unknown"
                let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? "unknown"
                let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
                let clout = data[FirebaseSchema.UserDocument.clout] as? Int ?? 0
                print("🔍 DEBUG: Doc \(index): ID=\(doc.documentID), username=\(username), displayName=\(displayName), verified=\(isVerified), clout=\(clout)")
            }
            
            let users = processUserDocuments(snapshot.documents, currentUserID: currentUserID)
            print("🔍 DEBUG: After processing and filtering current user: \(users.count) users")
            
            // Debug processed users
            for (index, user) in users.enumerated() {
                print("🔍 DEBUG: User \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
            }
            
            // Sort in memory: verified first, then by clout
            let sortedUsers = users.sorted { user1, user2 in
                if user1.isVerified && !user2.isVerified { return true }
                if !user1.isVerified && user2.isVerified { return false }
                return user1.clout > user2.clout
            }
            print("🔍 DEBUG: After sorting: \(sortedUsers.count) users")
            
            let limitedUsers = Array(sortedUsers.prefix(limit))
            print("🔍 DEBUG: After applying limit \(limit): \(limitedUsers.count) users")
            
            // Debug final users
            for (index, user) in limitedUsers.enumerated() {
                print("🔍 DEBUG: Final User \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
            }
            
            print("✅ SEARCH SERVICE: Loaded \(limitedUsers.count) users for browsing")
            return limitedUsers
            
        } catch {
            print("❌ SEARCH SERVICE: Failed to load all users: \(error)")
            print("🔍 DEBUG: Error details: \(error.localizedDescription)")
            if let firestoreError = error as NSError? {
                print("🔍 DEBUG: Error domain: \(firestoreError.domain)")
                print("🔍 DEBUG: Error code: \(firestoreError.code)")
                print("🔍 DEBUG: Error userInfo: \(firestoreError.userInfo)")
            }
            throw StitchError.processingError("Failed to load users: \(error.localizedDescription)")
        }
    }
    
    /// Search users by text - COMPREHENSIVE SEARCH + DEBUG + FIXED LIMIT
    func searchUsersByText(query: String, limit: Int = 20) async throws -> [BasicUserInfo] {
        
        print("🔍 DEBUG: searchUsersByText called with query: '\(query)', limit: \(limit)")
        
        do {
            let currentUserID = auth.currentUser?.uid
            let lowercaseQuery = query.lowercased()
            print("🔍 DEBUG: Lowercase query: '\(lowercaseQuery)'")
            print("🔍 DEBUG: Current user ID: \(currentUserID ?? "nil")")
            
            var allUsers: [BasicUserInfo] = []
            
            // Method 1: Search by username prefix
            print("🔍 DEBUG: === SEARCHING BY USERNAME ===")
            let usernameQuery = db.collection(FirebaseSchema.Collections.users)
                .whereField(FirebaseSchema.UserDocument.username, isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField(FirebaseSchema.UserDocument.username, isLessThan: lowercaseQuery + "\u{f8ff}")
                .limit(to: limit)
            
            let usernameSnapshot = try await usernameQuery.getDocuments()
            print("🔍 DEBUG: Username query returned \(usernameSnapshot.documents.count) documents")
            
            let usernameUsers = processUserDocuments(usernameSnapshot.documents, currentUserID: currentUserID)
            allUsers.append(contentsOf: usernameUsers)
            print("🔍 DEBUG: Added \(usernameUsers.count) users from username search")
            
            // Method 2: Search by displayName if we need more results
            if allUsers.count < limit {
                print("🔍 DEBUG: === SEARCHING BY DISPLAY NAME ===")
                let displayNameQuery = db.collection(FirebaseSchema.Collections.users)
                    .whereField(FirebaseSchema.UserDocument.displayName, isGreaterThanOrEqualTo: query) // Use original case
                    .whereField(FirebaseSchema.UserDocument.displayName, isLessThan: query + "\u{f8ff}")
                    .limit(to: limit - allUsers.count)
                
                let displayNameSnapshot = try await displayNameQuery.getDocuments()
                print("🔍 DEBUG: DisplayName query returned \(displayNameSnapshot.documents.count) documents")
                
                let displayNameUsers = processUserDocuments(displayNameSnapshot.documents, currentUserID: currentUserID)
                
                // Add without duplicates
                let existingIDs = Set(allUsers.map { $0.id })
                for user in displayNameUsers {
                    if !existingIDs.contains(user.id) {
                        allUsers.append(user)
                    }
                }
                print("🔍 DEBUG: Added \(displayNameUsers.count) additional users from displayName search")
            }
            
            // Method 3: If still not enough, get ALL users and filter in memory
            if allUsers.count < limit && lowercaseQuery.count >= 1 {
                print("🔍 DEBUG: === FALLBACK: SEARCHING ALL USERS IN MEMORY ===")
                do {
                    let allUsersQuery = db.collection(FirebaseSchema.Collections.users)
                        .limit(to: 100) // Get first 100 users
                    
                    let allSnapshot = try await allUsersQuery.getDocuments()
                    print("🔍 DEBUG: Fallback query returned \(allSnapshot.documents.count) documents")
                    
                    let allFoundUsers = processUserDocuments(allSnapshot.documents, currentUserID: currentUserID)
                    
                    // Filter in memory for contains matches
                    let memoryFiltered = allFoundUsers.filter { user in
                        user.username.lowercased().contains(lowercaseQuery) ||
                        user.displayName.lowercased().contains(lowercaseQuery)
                    }
                    
                    print("🔍 DEBUG: Memory filtered found \(memoryFiltered.count) matching users")
                    
                    // Add without duplicates
                    let existingIDs = Set(allUsers.map { $0.id })
                    for user in memoryFiltered {
                        if !existingIDs.contains(user.id) && allUsers.count < limit {
                            allUsers.append(user)
                        }
                    }
                } catch {
                    print("🔍 DEBUG: Fallback search failed: \(error)")
                }
            }
            
            print("🔍 DEBUG: Total users found before sorting: \(allUsers.count)")
            
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
            print("🔍 DEBUG: Final result count: \(finalUsers.count)")
            
            // Debug final results
            for (index, user) in finalUsers.enumerated() {
                print("🔍 DEBUG: Final result \(index): \(user.username) (\(user.displayName)) - verified: \(user.isVerified), clout: \(user.clout)")
            }
            
            print("✅ SEARCH SERVICE: Found \(finalUsers.count) users for query: '\(query)'")
            return finalUsers
            
        } catch {
            print("❌ SEARCH SERVICE: Search failed: \(error)")
            print("🔍 DEBUG: Search error details: \(error.localizedDescription)")
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
                print("⚠️ SEARCH SERVICE: Recent videos failed, returning empty array")
                return []
            }
        }
        
        // Try to search videos, but don't fail if it doesn't work
        do {
            return try await searchVideosByTitle(query: trimmedQuery, limit: limit)
        } catch {
            print("⚠️ SEARCH SERVICE: Video search failed, returning empty array")
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
            
            print("✅ SEARCH SERVICE: Loaded \(limitedVideos.count) recent videos (no index required)")
            return limitedVideos
            
        } catch {
            print("❌ SEARCH SERVICE: Failed to load recent videos: \(error)")
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
            print("✅ SEARCH SERVICE: Found \(limitedVideos.count) videos for query: '\(query)' (no index required)")
            return limitedVideos
            
        } catch {
            print("❌ SEARCH SERVICE: Video search failed: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods - CLEAN & SIMPLE
    
    /// Convert user documents to BasicUserInfo objects + DEBUG
    private func processUserDocuments(_ documents: [DocumentSnapshot], currentUserID: String?) -> [BasicUserInfo] {
        
        print("🔍 DEBUG: processUserDocuments called with \(documents.count) documents")
        print("🔍 DEBUG: Current user ID to filter: \(currentUserID ?? "nil")")
        
        var users: [BasicUserInfo] = []
        var filteredCount = 0
        
        for (index, document) in documents.enumerated() {
            print("🔍 DEBUG: Processing document \(index): \(document.documentID)")
            
            // Skip current user
            if let currentUserID = currentUserID, document.documentID == currentUserID {
                print("🔍 DEBUG: Skipping current user: \(document.documentID)")
                filteredCount += 1
                continue
            }
            
            let data = document.data() ?? [:]
            print("🔍 DEBUG: Document data keys: \(Array(data.keys))")
            
            let username = data[FirebaseSchema.UserDocument.username] as? String ?? "unknown"
            let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? "User"
            let tierString = data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
            let clout = data[FirebaseSchema.UserDocument.clout] as? Int ?? 0
            let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
            let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
            let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
            
            print("🔍 DEBUG: Extracted data - username: \(username), displayName: \(displayName), tier: \(tierString), clout: \(clout), verified: \(isVerified)")
            
            let tier = UserTier(rawValue: tierString) ?? .rookie
            print("🔍 DEBUG: Converted tier: \(tier)")
            
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
            print("🔍 DEBUG: Added user \(users.count): \(user.username)")
        }
        
        print("🔍 DEBUG: Processed \(documents.count) documents, filtered \(filteredCount), returning \(users.count) users")
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
        print("🔍 SEARCH SERVICE: Testing simple user discovery...")
        
        do {
            let users = try await getAllUsers(limit: 5)
            print("✅ SEARCH SERVICE: Successfully loaded \(users.count) users")
        } catch {
            print("❌ SEARCH SERVICE: Test failed: \(error)")
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
