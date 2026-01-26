//
//  UserService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete User Management Service
//  Dependencies: Firebase Firestore, Firebase Storage, FirebaseSchema, SpecialUserEntry, UserTier
//  Features: CRUD operations, Profile editing, Following system, Auto-follow support, Clout management
//  UPDATED: Automatic searchableText generation for case-insensitive user search
//  FIXED: Proper tier detection from SpecialUserEntry instead of forcing topCreator
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Complete user management service with social features and clout system
@MainActor
class UserService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let storage = Storage.storage()
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - User Creation and Management
    
    /// Create new user with complete profile setup
    func createUser(
        id: String,
        email: String,
        username: String? = nil,
        displayName: String? = nil,
        profileImageURL: String? = nil
    ) async throws -> BasicUserInfo {
        
        isLoading = true
        defer { isLoading = false }
        
        // Generate username if not provided
        let finalUsername = username ?? generateUsername(from: email, id: id)
        let finalDisplayName = displayName ?? finalUsername
        
        // FIXED: Detect special user and use their configured tier
        let specialUserEntry = SpecialUsersConfig.detectSpecialUser(email: email)
        
        // CRITICAL FIX: Use actual tier from SpecialUserEntry, not forced topCreator
        let initialTier: UserTier = {
            if let tierRawValue = specialUserEntry?.tierRawValue {
                return UserTier(rawValue: tierRawValue) ?? .rookie
            }
            return .rookie
        }()
        
        let initialClout = specialUserEntry?.startingClout ?? OptimizationConfig.User.defaultStartingClout
        let isSpecialUser = specialUserEntry != nil
        
        // Use custom bio if special user
        let initialBio = specialUserEntry?.customBio ?? ""
        
        // Generate searchableText for efficient case-insensitive search
        let searchableText = FirebaseSchema.UserDocument.generateSearchableText(
            username: finalUsername,
            displayName: finalDisplayName
        )
        
        print("USER SERVICE: Creating user with tier \(initialTier.displayName), clout: \(initialClout)")
        
        let userData: [String: Any] = [
            FirebaseSchema.UserDocument.id: id,
            FirebaseSchema.UserDocument.email: email,
            FirebaseSchema.UserDocument.username: finalUsername,
            FirebaseSchema.UserDocument.displayName: finalDisplayName,
            FirebaseSchema.UserDocument.searchableText: searchableText,
            FirebaseSchema.UserDocument.bio: initialBio,
            FirebaseSchema.UserDocument.tier: initialTier.rawValue,
            FirebaseSchema.UserDocument.clout: initialClout,
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.isVerified: isSpecialUser,
            FirebaseSchema.UserDocument.isPrivate: false,
            FirebaseSchema.UserDocument.profileImageURL: profileImageURL as Any,
            FirebaseSchema.UserDocument.createdAt: Timestamp(),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.users).document(id).setData(userData)
        
        let user = BasicUserInfo(
            id: id,
            username: finalUsername,
            displayName: finalDisplayName,
            bio: initialBio,
            tier: initialTier,
            clout: initialClout,
            isVerified: isSpecialUser,
            profileImageURL: profileImageURL
        )
        
        print("USER SERVICE: Created user \(finalUsername) with tier \(initialTier.displayName)")
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
    func getExtendedProfile(id: String) async throws -> BasicUserInfo? {
        let document = try await db.collection(FirebaseSchema.Collections.users).document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            print("USER SERVICE: Extended profile not found: \(id)")
            return nil
        }
        
        let basicUser = createBasicUserInfo(from: data, id: id)
        
        print("USER SERVICE: Loaded extended profile for \(basicUser.username)")
        return basicUser
    }
    
    /// Update user profile - COMPLETE SUPPORT FOR ALL FIELDS
    func updateProfile(
        userID: String,
        displayName: String? = nil,
        bio: String? = nil,
        isPrivate: Bool? = nil,
        username: String? = nil
    ) async throws {
        
        print("USER SERVICE: Updating profile for user \(userID)")
        
        var updates: [String: Any] = [
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ]
        
        // Track if we need to update searchableText
        var needsSearchableTextUpdate = false
        var newUsername: String? = nil
        var newDisplayName: String? = nil
        
        // Add fields that are being updated
        if let displayName = displayName {
            updates[FirebaseSchema.UserDocument.displayName] = displayName
            newDisplayName = displayName
            needsSearchableTextUpdate = true
        }
        
        if let bio = bio {
            updates[FirebaseSchema.UserDocument.bio] = bio
        }
        
        if let isPrivate = isPrivate {
            updates[FirebaseSchema.UserDocument.isPrivate] = isPrivate
        }
        
        if let username = username {
            // Username updates require additional validation
            if try await isUsernameAvailable(username, excludingUserID: userID) {
                updates[FirebaseSchema.UserDocument.username] = username
                newUsername = username
                needsSearchableTextUpdate = true
            } else {
                throw StitchError.validationError("Username '\(username)' is already taken")
            }
        }
        
        // If username or displayName changed, regenerate searchableText
        if needsSearchableTextUpdate {
            // Get current user data to fill in missing values
            let currentUser = try await getUser(id: userID)
            let finalUsername = newUsername ?? currentUser?.username ?? ""
            let finalDisplayName = newDisplayName ?? currentUser?.displayName ?? ""
            
            let searchableText = FirebaseSchema.UserDocument.generateSearchableText(
                username: finalUsername,
                displayName: finalDisplayName
            )
            updates[FirebaseSchema.UserDocument.searchableText] = searchableText
            print("USER SERVICE: Updated searchableText to '\(searchableText)'")
        }
        
        try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .updateData(updates)
        
        print("USER SERVICE: Successfully updated \(updates.keys.count) profile fields")
    }
    
    /// Upload and update profile image
    func updateProfileImage(userID: String, imageData: Data) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        let imagePath = "profile_images/\(userID)/profile.jpg"
        let imageRef = storage.reference().child(imagePath)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await imageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await imageRef.downloadURL()
        
        // Update user document with new image URL
        try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .updateData([
                FirebaseSchema.UserDocument.profileImageURL: downloadURL.absoluteString,
                FirebaseSchema.UserDocument.updatedAt: Timestamp()
            ])
        
        print("USER SERVICE: Updated profile image for user \(userID)")
        return downloadURL.absoluteString
    }
    
    // MARK: - Username Management
    
    /// Check if username is available
    func isUsernameAvailable(_ username: String, excludingUserID: String? = nil) async throws -> Bool {
        let query = db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.username, isEqualTo: username)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        if let excludingUserID = excludingUserID {
            // Allow if the only match is the excluded user
            return snapshot.documents.isEmpty ||
                   (snapshot.documents.count == 1 && snapshot.documents.first?.documentID == excludingUserID)
        } else {
            return snapshot.documents.isEmpty
        }
    }
    
    // MARK: - Following System
    
    /// Follow a user
    func followUser(followerID: String, followingID: String) async throws {
        
        guard followerID != followingID else {
            throw StitchError.validationError("Cannot follow yourself")
        }
        
        let batch = db.batch()
        
        // Add to follower's "following" subcollection
        let followingRef = db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
        
        batch.setData([
            "userID": followingID,
            "timestamp": Timestamp()
        ], forDocument: followingRef)
        
        // Add to followee's "followers" subcollection
        let followerRef = db.collection(FirebaseSchema.Collections.users)
            .document(followingID)
            .collection("followers")
            .document(followerID)
        
        batch.setData([
            "userID": followerID,
            "timestamp": Timestamp()
        ], forDocument: followerRef)
        
        // Update follower count for followee
        let followeeRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ], forDocument: followeeRef)
        
        // Update following count for follower
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(1)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ], forDocument: followerUserRef)
        
        try await batch.commit()
        
        print("USER SERVICE: User \(followerID) followed \(followingID)")
    }
    
    /// Unfollow a user
    func unfollowUser(followerID: String, followingID: String) async throws {
        
        let batch = db.batch()
        
        // Remove from follower's "following" subcollection
        let followingRef = db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
        
        batch.deleteDocument(followingRef)
        
        // Remove from followee's "followers" subcollection
        let followerRef = db.collection(FirebaseSchema.Collections.users)
            .document(followingID)
            .collection("followers")
            .document(followerID)
        
        batch.deleteDocument(followerRef)
        
        // Update follower count for followee
        let followeeRef = db.collection(FirebaseSchema.Collections.users).document(followingID)
        batch.updateData([
            FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(-1)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ], forDocument: followeeRef)
        
        // Update following count for follower
        let followerUserRef = db.collection(FirebaseSchema.Collections.users).document(followerID)
        batch.updateData([
            FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(-1)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ], forDocument: followerUserRef)
        
        try await batch.commit()
        
        print("USER SERVICE: User \(followerID) unfollowed \(followingID)")
    }
    
    /// Check if user is following another user
    func isFollowing(followerID: String, followingID: String) async throws -> Bool {
        let followingDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(followerID)
            .collection("following")
            .document(followingID)
            .getDocument()
        
        return followingDoc.exists
    }
    
    /// Get following IDs for a user
    func getFollowingIDs(userID: String) async throws -> [String] {
        let followingSnapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("following")
            .getDocuments()
        
        let followingIDs = followingSnapshot.documents.map { $0.documentID }
        print("USER SERVICE: User \(userID) follows \(followingIDs.count) users")
        return followingIDs
    }
    
    /// Get follower IDs for a user
    func getFollowerIDs(userID: String) async throws -> [String] {
        let followersSnapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("followers")
            .getDocuments()
        
        let followerIDs = followersSnapshot.documents.map { $0.documentID }
        print("USER SERVICE: User \(userID) has \(followerIDs.count) followers")
        return followerIDs
    }
    
    // MARK: - User Search and Discovery
    
    /// Search users by username or display name
    func searchUsers(query: String, limit: Int = 20) async throws -> [BasicUserInfo] {
        
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        
        // Search by username
        let usernameQuery = db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.username, isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField(FirebaseSchema.UserDocument.username, isLessThan: lowercaseQuery + "z")
            .limit(to: limit)
        
        let usernameSnapshot = try await usernameQuery.getDocuments()
        
        let users = usernameSnapshot.documents.compactMap { doc in
            createBasicUserInfo(from: doc.data(), id: doc.documentID)
        }
        
        print("USER SERVICE: Found \(users.count) users matching '\(query)'")
        return users
    }
    
    /// Get users by IDs
    func getUsers(ids: [String]) async throws -> [BasicUserInfo] {
        guard !ids.isEmpty else { return [] }
        
        let chunks = ids.chunked(into: 10) // Firestore limit
        var allUsers: [BasicUserInfo] = []
        
        for chunk in chunks {
            let query = db.collection(FirebaseSchema.Collections.users)
                .whereField(FieldPath.documentID(), in: chunk)
            
            let snapshot = try await query.getDocuments()
            let users = snapshot.documents.compactMap { doc in
                createBasicUserInfo(from: doc.data(), id: doc.documentID)
            }
            
            allUsers.append(contentsOf: users)
        }
        
        return allUsers
    }
    
    /// Get user ID by email
    func getUserID(email: String) async throws -> String? {
        print("🔍 USER SERVICE: Looking up user ID for email: \(email)")
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.email, isEqualTo: email)
            .limit(to: 1)
            .getDocuments()
        
        let userID = snapshot.documents.first?.documentID
        
        if let userID = userID {
            print("✅ USER SERVICE: Found user ID \(userID) for email \(email)")
        } else {
            print("❌ USER SERVICE: No user found for email \(email)")
        }
        
        return userID
    }
    
    /// Get user email by ID
    func getUserEmail(userID: String) async throws -> String? {
        print("🔍 USER SERVICE: Looking up email for user ID: \(userID)")
        
        do {
            let document = try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .getDocument()
            
            guard document.exists else {
                print("❌ USER SERVICE: User document not found for ID: \(userID)")
                throw StitchError.validationError("User not found")
            }
            
            let email = document.data()?[FirebaseSchema.UserDocument.email] as? String
            
            if let email = email {
                print("✅ USER SERVICE: Found email \(email) for user ID \(userID)")
            } else {
                print("⚠️ USER SERVICE: No email found in document for user ID: \(userID)")
            }
            
            return email
            
        } catch {
            print("⚠️ USER SERVICE: Error looking up email for user \(userID): \(error)")
            throw error
        }
    }
    
    /// Check if user exists by email (utility method)
    func userExists(email: String) async throws -> Bool {
        let userID = try await getUserID(email: email)
        return userID != nil
    }
    
    /// Refresh follower/following counts for a user
    func refreshFollowerCounts(userID: String) async throws {
        print("🔄 USER SERVICE: Refreshing follower counts for user \(userID)")
        
        do {
            // Count actual followers in subcollection
            let followersSnapshot = try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("followers")
                .getDocuments()
            
            // Count actual following in subcollection
            let followingSnapshot = try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("following")
                .getDocuments()
            
            let actualFollowerCount = followersSnapshot.documents.count
            let actualFollowingCount = followingSnapshot.documents.count
            
            // Update the user document with accurate counts
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .updateData([
                    FirebaseSchema.UserDocument.followerCount: actualFollowerCount,
                    FirebaseSchema.UserDocument.followingCount: actualFollowingCount,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
            
            print("✅ USER SERVICE: Updated counts - Followers: \(actualFollowerCount), Following: \(actualFollowingCount)")
            
        } catch {
            print("⚠️ USER SERVICE: Failed to refresh follower counts for \(userID): \(error)")
            throw error
        }
    }
    
    /// Get fresh follower/following lists for a user
    func getFreshFollowData(userID: String) async throws -> (followers: [String], following: [String]) {
        print("🔄 USER SERVICE: Getting fresh follow data for user \(userID)")
        
        // Get fresh followers list
        let followersSnapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("followers")
            .getDocuments()
        
        // Get fresh following list
        let followingSnapshot = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .collection("following")
            .getDocuments()
        
        let followers = followersSnapshot.documents.map { $0.documentID }
        let following = followingSnapshot.documents.map { $0.documentID }
        
        print("✅ USER SERVICE: Fresh data - \(followers.count) followers, \(following.count) following")
        
        return (followers: followers, following: following)
    }
    
    // MARK: - Clout Management System
    
    /// Update user clout (base method)
    func updateClout(userID: String, cloutChange: Int) async throws {
        let userRef = db.collection(FirebaseSchema.Collections.users).document(userID)
        
        try await userRef.updateData([
            FirebaseSchema.UserDocument.clout: FieldValue.increment(Int64(cloutChange)),
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ])
        
        print("USER SERVICE: Updated clout by \(cloutChange) for user \(userID)")
    }
    
    /// Award positive clout to user (called by EngagementResult.swift)
    func awardClout(userID: String, amount: Int) async throws {
        guard amount > 0 else {
            print("⚠️ USER SERVICE: Cannot award negative or zero clout amount: \(amount)")
            throw StitchError.validationError("Clout award amount must be positive")
        }
        
        print("💰 USER SERVICE: Awarding \(amount) clout to user \(userID)")
        
        do {
            // Use existing updateClout method with positive amount
            try await updateClout(userID: userID, cloutChange: amount)
            
            // Log successful clout award
            print("✅ USER SERVICE: Successfully awarded \(amount) clout to user \(userID)")
            
        } catch {
            print("❌ USER SERVICE: Failed to award clout to user \(userID): \(error.localizedDescription)")
            throw StitchError.processingError("Failed to award clout: \(error.localizedDescription)")
        }
    }
    
    /// Deduct clout from user with minimum bounds protection (called by EngagementResult.swift)
    func deductClout(userID: String, amount: Int) async throws {
        guard amount > 0 else {
            print("⚠️ USER SERVICE: Cannot deduct negative or zero clout amount: \(amount)")
            throw StitchError.validationError("Clout deduction amount must be positive")
        }
        
        print("💸 USER SERVICE: Deducting \(amount) clout from user \(userID)")
        
        do {
            // Get current user to check clout balance
            guard let currentUser = try await getUser(id: userID) else {
                throw StitchError.validationError("User not found for clout deduction")
            }
            
            // Calculate new clout with minimum protection (prevent going below 0)
            let newClout = max(0, currentUser.clout - amount)
            let actualDeduction = currentUser.clout - newClout
            
            if actualDeduction != amount {
                print("⚠️ USER SERVICE: Clout deduction limited - requested: \(amount), actual: \(actualDeduction)")
            }
            
            // Use existing updateClout method with negative amount
            try await updateClout(userID: userID, cloutChange: -actualDeduction)
            
            // Log successful clout deduction
            print("✅ USER SERVICE: Successfully deducted \(actualDeduction) clout from user \(userID) (requested: \(amount))")
            
        } catch {
            print("❌ USER SERVICE: Failed to deduct clout from user \(userID): \(error.localizedDescription)")
            throw StitchError.processingError("Failed to deduct clout: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Generate username from email and ID
    private func generateUsername(from email: String, id: String) -> String {
        if !email.isEmpty {
            let emailPrefix = String(email.split(separator: "@").first ?? "")
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            
            if !emailPrefix.isEmpty {
                return emailPrefix
            }
        }
        
        return "user_\(String(id.prefix(8)))"
    }
    
    /// Create BasicUserInfo from Firestore data
    private func createBasicUserInfo(from data: [String: Any], id: String) -> BasicUserInfo {
        
        let username = data[FirebaseSchema.UserDocument.username] as? String ?? "unknown"
        let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? "User"
        let bio = data[FirebaseSchema.UserDocument.bio] as? String ?? ""
        let tierRawValue = data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie"
        let tier = UserTier(rawValue: tierRawValue) ?? .rookie
        let clout = data[FirebaseSchema.UserDocument.clout] as? Int ?? 0
        let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
        let isPrivate = data[FirebaseSchema.UserDocument.isPrivate] as? Bool ?? false
        let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
        let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        return BasicUserInfo(
            id: id,
            username: username,
            displayName: displayName,
            bio: bio,
            tier: tier,
            clout: clout,
            isVerified: isVerified,
            isPrivate: isPrivate,
            profileImageURL: profileImageURL,
            createdAt: createdAt
        )
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Backfill Auto-Follows

extension UserService {
    
    /// Backfill auto-follows for existing users (call once on app startup)
    func backfillDefaultFollows() async {
        let defaultAccounts = [
            "4ifwg1CxDGbZ9amfPOvl0lMR6982",  // James Fortune
            "L9cfRdqpDMWA9tq12YBh3IkhnGh1"   // StitchSocial
        ]
        
        print("🔄 BACKFILL: Starting auto-follow backfill for default accounts")
        
        do {
            // Get all users from Firestore
            let snapshot = try await db.collection(FirebaseSchema.Collections.users).getDocuments()
            let userIDs = snapshot.documents.map { $0.documentID }
            
            print("🔄 BACKFILL: Found \(userIDs.count) users to process")
            
            for userID in userIDs {
                for accountID in defaultAccounts {
                    do {
                        // Check if already following
                        let isAlreadyFollowing = try await isFollowing(followerID: userID, followingID: accountID)
                        
                        if !isAlreadyFollowing && userID != accountID {
                            try await followUser(followerID: userID, followingID: accountID)
                            print("✅ BACKFILL: User \(userID) followed \(accountID)")
                        }
                    } catch {
                        print("⚠️ BACKFILL: Error processing \(userID) -> \(accountID): \(error)")
                    }
                }
            }
            
            print("✅ BACKFILL: Completed")
            
        } catch {
            print("❌ BACKFILL: Failed: \(error)")
        }
    }
}

// MARK: - Extensions

extension UserService {
    
    /// Test user service functionality
    func helloWorldTest() {
        print("👥 USER SERVICE: Hello World - Ready for complete user management!")
        print("👥 Features: CRUD operations, Profile editing, Following system, Auto-follow support, Clout management")
        print("👥 Status: Firebase integration, Image upload, Username validation, Email lookup")
    }
}
