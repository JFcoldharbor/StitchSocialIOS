//
//  UserService.swift
//  StitchSocial
//
//  Layer 4: Core Services - User Management with Complete Profile Editing Support
//  Dependencies: Firebase Firestore, Firebase Storage, SpecialUserEntry
//  Features: User CRUD, following system, profile editing (bio, photo, username, display name)
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service for user management and operations with complete profile editing support
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
    
    /// Get extended profile data for editing - COMPLETE IMPLEMENTATION
    func getExtendedProfile(id: String) async throws -> UserProfileData? {
        let document = try await db.collection(FirebaseSchema.Collections.users).document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            print("USER SERVICE: Extended profile not found: \(id)")
            return nil
        }
        
        let basicUser = createBasicUserInfo(from: data, id: id)
        let profileData = UserProfileData(from: basicUser, extended: data)
        
        print("USER SERVICE: Loaded extended profile for \(basicUser.username)")
        return profileData
    }
    
    /// Update user profile - COMPLETE SUPPORT FOR ALL FIELDS
    func updateProfile(
        userID: String,
        displayName: String? = nil,
        bio: String? = nil,
        isPrivate: Bool? = nil,
        username: String? = nil
    ) async throws {
        
        // Validate username uniqueness if provided
        if let newUsername = username {
            let isUnique = try await isUsernameUnique(username: newUsername, excludeUserID: userID)
            guard isUnique else {
                throw StitchError.validationError("Username '\(newUsername)' is already taken")
            }
        }
        
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
        
        if let username = username {
            updates[FirebaseSchema.UserDocument.username] = username
        }
        
        try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData(updates)
        
        print("USER SERVICE: Updated profile for \(userID)")
        print("USER SERVICE: Updated fields: \(updates.keys.sorted())")
    }
    
    /// Upload profile image - COMPLETE IMPLEMENTATION
    func uploadProfileImage(userID: String, imageData: Data) async throws -> String {
        
        // Validate image size
        let maxSize = OptimizationConfig.User.maxProfileImageSize
        guard Int64(imageData.count) <= maxSize else {
            throw StitchError.validationError("Image too large. Maximum size is \(maxSize / (1024 * 1024))MB")
        }
        
        let storageRef = storage.reference().child("profile_images/\(userID).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userID": userID,
            "uploadedAt": "\(Date().timeIntervalSince1970)"
        ]
        
        // Upload image
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let url = try await storageRef.downloadURL()
        let urlString = url.absoluteString
        
        // Update user document with new image URL
        try await db.collection(FirebaseSchema.Collections.users).document(userID).updateData([
            FirebaseSchema.UserDocument.profileImageURL: urlString,
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ])
        
        print("USER SERVICE: Profile image uploaded for \(userID)")
        print("USER SERVICE: New image URL: \(urlString)")
        return urlString
    }
    
    /// Check if username is unique - HELPER FOR VALIDATION
    func isUsernameUnique(username: String, excludeUserID: String? = nil) async throws -> Bool {
        let query = db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.username, isEqualTo: username)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        // If no documents found, username is unique
        guard !snapshot.documents.isEmpty else {
            return true
        }
        
        // If excluding a specific user ID (for updates), check if the found user is the excluded one
        if let excludeID = excludeUserID {
            let foundUserID = snapshot.documents.first?.documentID
            return foundUserID == excludeID
        }
        
        // Username is taken
        return false
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
        
        print("USER SERVICE: Updated clout by \(cloutChange) for user \(userID)")
    }
    
    // MARK: - Following System (Subcollection-based)
    
    /// Follow a user
    func followUser(followerID: String, followingID: String) async throws {
        guard followerID != followingID else {
            throw StitchError.validationError("Cannot follow yourself")
        }
        
        let batch = db.batch()
        
        // Add to follower's following subcollection
        let followingRef = db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
        
        // Add to following user's followers subcollection
        let followerRef = db.collection(FirebaseSchema.Collections.users)
            .document(followingID)
            .collection("followers")
            .document(followerID)
        
        let timestamp = Timestamp()
        
        batch.setData([
            "userId": followingID,
            "followedAt": timestamp
        ], forDocument: followingRef)
        
        batch.setData([
            "userId": followerID,
            "followedAt": timestamp
        ], forDocument: followerRef)
        
        // Update counts
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        let followingUserRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.UserDocument.updatedAt: timestamp
        ], forDocument: followerUserRef)
        
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.UserDocument.updatedAt: timestamp
        ], forDocument: followingUserRef)
        
        try await batch.commit()
        print("USER SERVICE: \(followerID) followed \(followingID)")
    }
    
    /// Unfollow a user
    func unfollowUser(followerID: String, followingID: String) async throws {
        let batch = db.batch()
        
        // Remove from follower's following subcollection
        let followingRef = db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
        
        // Remove from following user's followers subcollection
        let followerRef = db.collection(FirebaseSchema.Collections.users)
            .document(followingID)
            .collection("followers")
            .document(followerID)
        
        batch.deleteDocument(followingRef)
        batch.deleteDocument(followerRef)
        
        // Update counts
        let timestamp = Timestamp()
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        let followingUserRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(-1)),
            FirebaseSchema.UserDocument.updatedAt: timestamp
        ], forDocument: followerUserRef)
        
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(-1)),
            FirebaseSchema.UserDocument.updatedAt: timestamp
        ], forDocument: followingUserRef)
        
        try await batch.commit()
        print("USER SERVICE: \(followerID) unfollowed \(followingID)")
    }
    
    /// Check if user is following another user
    func isFollowing(followerID: String, followingID: String) async throws -> Bool {
        let document = try await db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
            .getDocument()
        
        return document.exists
    }
    
    /// Get following IDs for HomeFeedService
    func getFollowingIDs(userID: String) async throws -> [String] {
        print("USER SERVICE: Loading following IDs for user: \(userID)")
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("following")
            .getDocuments()
        
        let followingIDs = snapshot.documents.map { $0.documentID }
        
        print("USER SERVICE: Found \(followingIDs.count) following IDs")
        return followingIDs
    }
    
    /// Get users that the given user is following
    func getFollowing(userID: String, limit: Int = 50) async throws -> [BasicUserInfo] {
        let followingDocs = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("following")
            .order(by: "followedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        var users: [BasicUserInfo] = []
        
        for doc in followingDocs.documents {
            let followingUserID = doc.documentID
            if let user = try await getUser(id: followingUserID) {
                users.append(user)
            }
        }
        
        return users
    }
    
    /// Get followers of the given user
    func getFollowers(userID: String, limit: Int = 50) async throws -> [BasicUserInfo] {
        let followerDocs = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("followers")
            .order(by: "followedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        var users: [BasicUserInfo] = []
        
        for doc in followerDocs.documents {
            let followerUserID = doc.documentID
            if let user = try await getUser(id: followerUserID) {
                users.append(user)
            }
        }
        
        return users
    }
    
    // MARK: - Helper Methods
    
    /// Create BasicUserInfo from Firestore data
    private func createBasicUserInfo(from data: [String: Any], id: String) -> BasicUserInfo {
        let tierRawValue = data[FirebaseSchema.UserDocument.tier] as? String ?? UserTier.rookie.rawValue
        let tier = UserTier(rawValue: tierRawValue) ?? .rookie
        
        return BasicUserInfo(
            id: id,
            username: data[FirebaseSchema.UserDocument.username] as? String ?? "unknown",
            displayName: data[FirebaseSchema.UserDocument.displayName] as? String ?? "Unknown User",
            tier: tier,
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
