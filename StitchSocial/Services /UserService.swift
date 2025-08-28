//
//  UserService.swift
//  StitchSocial
//
//  Layer 4: Core Services - User Management with REVERTED Following/Followers
//  Dependencies: Firebase Firestore, SpecialUserEntry
//  Features: User CRUD, subcollection-based following system, profiles, Firebase integration
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service for user management and operations
@MainActor
class UserService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let storage = Storage.storage()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Core User Operations
    
    /// Create new user profile
    func createUser(
        id: String,
        email: String,
        displayName: String? = nil,
        profileImageURL: String? = nil,
        isSpecialUser: Bool = false
    ) async throws -> BasicUserInfo {
        
        let username = generateUsername(from: email, id: id)
        let now = Timestamp()
        
        // Determine initial tier and clout
        let initialTier: UserTier = isSpecialUser ? .founder : .rookie
        let initialClout = isSpecialUser ? 50000 : 0
        
        let userData: [String: Any] = [
            FirebaseSchema.UserDocument.email: email,
            FirebaseSchema.UserDocument.username: username,
            FirebaseSchema.UserDocument.displayName: displayName ?? username,
            FirebaseSchema.UserDocument.bio: isSpecialUser ? "Founder of Stitch Social | Building the future of social video" : "",
            FirebaseSchema.UserDocument.profileImageURL: profileImageURL ?? "",
            FirebaseSchema.UserDocument.tier: initialTier.rawValue,
            FirebaseSchema.UserDocument.clout: initialClout,
            FirebaseSchema.UserDocument.isVerified: isSpecialUser,
            FirebaseSchema.UserDocument.createdAt: now,
            FirebaseSchema.UserDocument.updatedAt: now,
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.videoCount: 0,
            FirebaseSchema.UserDocument.threadCount: 0,
            FirebaseSchema.UserDocument.totalHypesReceived: 0,
            FirebaseSchema.UserDocument.totalCoolsReceived: 0,
            FirebaseSchema.UserDocument.isPrivate: false,
            FirebaseSchema.UserDocument.isBanned: false
        ]
        
        try await db.collection(FirebaseSchema.Collections.users).document(id).setData(userData)
        
        let user = BasicUserInfo(
            id: id,
            username: username,
            displayName: displayName ?? username,
            tier: initialTier,
            clout: initialClout,
            isVerified: isSpecialUser,
            profileImageURL: profileImageURL
        )
        
        print("USER SERVICE: Created user \(username) with tier \(initialTier.displayName)")
        return user
    }
    
    /// Get user by ID
    func getUser(id: String) async throws -> BasicUserInfo? {
        
        let document = try await db.collection(FirebaseSchema.Collections.users).document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            print("USER SERVICE: User not found: \(id)")
            return nil
        }
        
        let user = createBasicUserInfo(from: data, id: id)
        print("USER SERVICE: Loaded user \(user.username)")
        return user
    }
    
    /// Update user profile
    func updateProfile(
        userID: String,
        displayName: String? = nil,
        bio: String? = nil,
        isPrivate: Bool? = nil
    ) async throws {
        
        var updates: [String: Any] = [
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ]
        
        if let displayName = displayName {
            updates[FirebaseSchema.UserDocument.displayName] = displayName
        }
        
        if let bio = bio {
            updates[FirebaseSchema.UserDocument.bio] = bio
        }
        
        if let isPrivate = isPrivate {
            updates[FirebaseSchema.UserDocument.isPrivate] = isPrivate
        }
        
        try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData(updates)
        
        print("USER SERVICE: Updated profile for \(userID)")
    }
    
    /// Upload profile image
    func uploadProfileImage(userID: String, imageData: Data) async throws -> String {
        let storageRef = storage.reference().child("profile_images/\(userID).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let url = try await storageRef.downloadURL()
        let urlString = url.absoluteString
        
        // Update user document
        try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData([
            FirebaseSchema.UserDocument.profileImageURL: urlString,
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ])
        
        print("USER SERVICE: Profile image uploaded for \(userID)")
        return urlString
    }
    
    /// Update user clout
    func updateClout(userID: String, cloutChange: Int) async throws {
        let userRef = db.collection(FirebaseSchema.Collections.users).document(userID)
        
        try await userRef.updateData([
            FirebaseSchema.UserDocument.clout: FieldValue.increment(Int64(cloutChange)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ])
        
        // Get new clout for tier check
        let document = try await userRef.getDocument()
        if let newClout = document.data()?[FirebaseSchema.UserDocument.clout] as? Int {
            await checkTierUpgrade(userID: userID, newClout: newClout)
        }
        
        print("USER SERVICE: Updated clout by \(cloutChange) for \(userID)")
    }
    
    // MARK: - Following System - REVERTED to match your existing Firebase structure
    
    /// Get following IDs - REVERTED to subcollection approach
    func getFollowingIDs(userID: String) async throws -> [String] {
        print("USER SERVICE: Loading following IDs for user: \(userID)")
        
        // Use your existing subcollection structure
        let snapshot = try await db.collection("users")
            .document(userID)
            .collection("following")
            .getDocuments()
        
        // Document IDs ARE the followed user IDs in your structure
        let followingIDs = snapshot.documents.map { $0.documentID }
        
        print("USER SERVICE: Found \(followingIDs.count) following IDs")
        return followingIDs
    }
    
    /// Get following list - REVERTED for subcollection structure
    func getFollowing(userID: String, limit: Int = 100) async throws -> [BasicUserInfo] {
        print("USER SERVICE: Loading following for user: \(userID)")
        
        let followingIDs = try await getFollowingIDs(userID: userID)
        var following: [BasicUserInfo] = []
        
        for followingUserID in followingIDs {
            if let user = try await getUser(id: followingUserID) {
                following.append(user)
            }
        }
        
        print("USER SERVICE: Loaded \(following.count) following users")
        return following
    }
    
    /// Get followers list - REVERTED to query subcollections
    func getFollowers(userID: String, limit: Int = 100) async throws -> [BasicUserInfo] {
        print("USER SERVICE: Loading followers for user: \(userID)")
        
        // Query all users' following subcollections for this userID
        let usersSnapshot = try await db.collection("users").getDocuments()
        var followers: [BasicUserInfo] = []
        
        for userDoc in usersSnapshot.documents {
            let followerID = userDoc.documentID
            
            // Check if this user follows the target user
            let followingDoc = try await db.collection("users")
                .document(followerID)
                .collection("following")
                .document(userID)
                .getDocument()
            
            if followingDoc.exists {
                if let follower = try await getUser(id: followerID) {
                    followers.append(follower)
                }
            }
        }
        
        print("USER SERVICE: Found \(followers.count) followers")
        return followers
    }
    
    /// Follow a user - REVERTED to subcollection approach
    func followUser(followerID: String, followingID: String) async throws {
        guard followerID != followingID else {
            throw StitchError.validationError("Cannot follow yourself")
        }
        
        // Check if already following
        let followingDoc = try await db.collection("users")
            .document(followerID)
            .collection("following")
            .document(followingID)
            .getDocument()
        
        if followingDoc.exists {
            print("USER SERVICE: Already following \(followingID)")
            return
        }
        
        // Use batch write for atomic operation
        let batch = db.batch()
        
        // Create follow relationship in subcollection
        let followRef = db.collection("users")
            .document(followerID)
            .collection("following")
            .document(followingID)
        
        batch.setData([
            "createdAt": Timestamp(),
            "isActive": true
        ], forDocument: followRef)
        
        // Update follower count
        let followingUserRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(1))
        ], forDocument: followingUserRef)
        
        // Update following count
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(1))
        ], forDocument: followerUserRef)
        
        try await batch.commit()
        
        print("USER SERVICE: \(followerID) followed \(followingID)")
    }
    
    /// Unfollow a user - REVERTED to subcollection approach
    func unfollowUser(followerID: String, followingID: String) async throws {
        // Check if actually following
        let followingDoc = try await db.collection("users")
            .document(followerID)
            .collection("following")
            .document(followingID)
            .getDocument()
        
        if !followingDoc.exists {
            print("USER SERVICE: Not following \(followingID)")
            return
        }
        
        // Use batch write for atomic operation
        let batch = db.batch()
        
        // Delete follow relationship from subcollection
        let followRef = db.collection("users")
            .document(followerID)
            .collection("following")
            .document(followingID)
        batch.deleteDocument(followRef)
        
        // Update follower count
        let followingUserRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(-1))
        ], forDocument: followingUserRef)
        
        // Update following count
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(-1))
        ], forDocument: followerUserRef)
        
        try await batch.commit()
        
        print("USER SERVICE: \(followerID) unfollowed \(followingID)")
    }
    
    /// Check if user is following another user - REVERTED to subcollection
    func isFollowing(followerID: String, followingID: String) async throws -> Bool {
        let document = try await db.collection("users")
            .document(followerID)
            .collection("following")
            .document(followingID)
            .getDocument()
        
        return document.exists
    }
    
    // MARK: - Helper Methods
    
    /// Create BasicUserInfo from Firestore data
    private func createBasicUserInfo(from data: [String: Any], id: String) -> BasicUserInfo {
        return BasicUserInfo(
            id: id,
            username: data[FirebaseSchema.UserDocument.username] as? String ?? "unknown",
            displayName: data[FirebaseSchema.UserDocument.displayName] as? String ?? "Unknown User",
            tier: UserTier(rawValue: data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie") ?? .rookie,
            clout: data[FirebaseSchema.UserDocument.clout] as? Int ?? 0,
            isVerified: data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false,
            profileImageURL: data[FirebaseSchema.UserDocument.profileImageURL] as? String,
            createdAt: (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    /// Generate username from email and ID
    private func generateUsername(from email: String, id: String) -> String {
        if !email.isEmpty {
            let emailPrefix = String(email.split(separator: "@").first ?? "user")
            return "\(emailPrefix)_\(String(id.prefix(6)))"
        } else {
            return "user_\(String(id.prefix(8)))"
        }
    }
    
    /// Check and apply tier upgrades
    private func checkTierUpgrade(userID: String, newClout: Int) async {
        let currentTier = UserTier.allCases.first { tier in
            tier.cloutRange.contains(newClout) && tier.isAchievableTier
        }
        
        if let newTier = currentTier {
            do {
                try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData([
                    FirebaseSchema.UserDocument.tier: newTier.rawValue,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
                
                print("USER SERVICE: Tier upgraded to \(newTier.displayName)")
            } catch {
                print("USER SERVICE: Failed to upgrade tier: \(error)")
            }
        }
    }
}
