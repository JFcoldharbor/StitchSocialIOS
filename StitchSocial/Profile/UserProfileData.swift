//
//  UserProfileData.swift
//  CleanBeta
//
//  Profile data model for extended user information
//  Combines BasicUserInfo with extended profile data
//

import Foundation
import FirebaseFirestore

/// Extended user profile data combining BasicUserInfo with additional profile information
struct UserProfileData: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let email: String
    let bio: String
    let profileImageURL: String?
    let tier: UserTier
    let clout: Int
    let isVerified: Bool
    let followerCount: Int
    let followingCount: Int
    let videoCount: Int
    let threadCount: Int
    let totalHypesReceived: Int
    let totalCoolsReceived: Int
    let createdAt: Date
    let lastActiveAt: Date
    let isPrivate: Bool
    
    // MARK: - Single Initializer (Fixed duplicate issue)
    
    /// Initialize from BasicUserInfo and extended data dictionary
    init(from basicUser: BasicUserInfo, extended: [String: Any]) {
        self.id = basicUser.id
        self.username = basicUser.username
        self.displayName = basicUser.displayName
        self.email = extended["email"] as? String ?? ""
        self.bio = extended["bio"] as? String ?? ""
        self.profileImageURL = basicUser.profileImageURL
        self.tier = basicUser.tier
        self.clout = basicUser.clout
        self.isVerified = basicUser.isVerified
        self.followerCount = extended["followerCount"] as? Int ?? 0
        self.followingCount = extended["followingCount"] as? Int ?? 0
        self.videoCount = extended["videoCount"] as? Int ?? 0
        self.threadCount = extended["threadCount"] as? Int ?? 0
        self.totalHypesReceived = extended["totalHypesReceived"] as? Int ?? 0
        self.totalCoolsReceived = extended["totalCoolsReceived"] as? Int ?? 0
        self.createdAt = basicUser.createdAt
        self.lastActiveAt = (extended["lastActiveAt"] as? Timestamp)?.dateValue() ?? Date()
        self.isPrivate = extended["isPrivate"] as? Bool ?? false
    }
    
    // MARK: - Computed Properties
    
    var totalEngagement: Int {
        return totalHypesReceived + totalCoolsReceived
    }
    
    var engagementRate: Double {
        guard followerCount > 0 else { return 0.0 }
        return Double(totalEngagement) / Double(followerCount)
    }
    
    var contentCount: Int {
        return videoCount + threadCount
    }
    
    // MARK: - Immutable Update Methods
    
    /// Create a copy with updated follower count
    func withUpdatedFollowerCount(_ newCount: Int) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: self.displayName,
            email: self.email,
            bio: self.bio,
            profileImageURL: self.profileImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: newCount,
            followingCount: self.followingCount,
            videoCount: self.videoCount,
            threadCount: self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: self.isPrivate
        )
    }
    
    /// Create a copy with updated profile image
    func withUpdatedProfileImage(_ newImageURL: String) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: self.displayName,
            email: self.email,
            bio: self.bio,
            profileImageURL: newImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: self.followerCount,
            followingCount: self.followingCount,
            videoCount: self.videoCount,
            threadCount: self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: self.isPrivate
        )
    }
    
    /// Create a copy with updated bio
    func withUpdatedBio(_ newBio: String) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: self.displayName,
            email: self.email,
            bio: newBio,
            profileImageURL: self.profileImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: self.followerCount,
            followingCount: self.followingCount,
            videoCount: self.videoCount,
            threadCount: self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: self.isPrivate
        )
    }
    
    /// Create a copy with updated privacy setting
    func withUpdatedPrivacy(_ newPrivacy: Bool) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: self.displayName,
            email: self.email,
            bio: self.bio,
            profileImageURL: self.profileImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: self.followerCount,
            followingCount: self.followingCount,
            videoCount: self.videoCount,
            threadCount: self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: newPrivacy
        )
    }
    
    /// Create a copy with updated display name
    func withUpdatedDisplayName(_ newDisplayName: String) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: newDisplayName,
            email: self.email,
            bio: self.bio,
            profileImageURL: self.profileImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: self.followerCount,
            followingCount: self.followingCount,
            videoCount: self.videoCount,
            threadCount: self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: self.isPrivate
        )
    }
    
    /// Create a copy with updated content counts
    func withUpdatedContentCounts(videos: Int? = nil, threads: Int? = nil) -> UserProfileData {
        return UserProfileData(
            id: self.id,
            username: self.username,
            displayName: self.displayName,
            email: self.email,
            bio: self.bio,
            profileImageURL: self.profileImageURL,
            tier: self.tier,
            clout: self.clout,
            isVerified: self.isVerified,
            followerCount: self.followerCount,
            followingCount: self.followingCount,
            videoCount: videos ?? self.videoCount,
            threadCount: threads ?? self.threadCount,
            totalHypesReceived: self.totalHypesReceived,
            totalCoolsReceived: self.totalCoolsReceived,
            createdAt: self.createdAt,
            lastActiveAt: self.lastActiveAt,
            isPrivate: self.isPrivate
        )
    }
}

// MARK: - Direct Property Initializer

extension UserProfileData {
    /// Direct initializer for all properties
    init(
        id: String,
        username: String,
        displayName: String,
        email: String,
        bio: String,
        profileImageURL: String?,
        tier: UserTier,
        clout: Int,
        isVerified: Bool,
        followerCount: Int,
        followingCount: Int,
        videoCount: Int,
        threadCount: Int,
        totalHypesReceived: Int,
        totalCoolsReceived: Int,
        createdAt: Date,
        lastActiveAt: Date,
        isPrivate: Bool
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.bio = bio
        self.profileImageURL = profileImageURL
        self.tier = tier
        self.clout = clout
        self.isVerified = isVerified
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.videoCount = videoCount
        self.threadCount = threadCount
        self.totalHypesReceived = totalHypesReceived
        self.totalCoolsReceived = totalCoolsReceived
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.isPrivate = isPrivate
    }
}
