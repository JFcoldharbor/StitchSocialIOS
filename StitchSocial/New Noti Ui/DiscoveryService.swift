//
//  DiscoveryService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Discovery and Leaderboard Data Service
//  Dependencies: Firebase Firestore, FirebaseSchema, LeaderboardModels
//  Features: Recent users, hype leaderboard queries
//

import Foundation
import FirebaseFirestore

/// Service for fetching discovery and leaderboard data
@MainActor
class DiscoveryService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Recent Users
    
    /// Get recently joined users (last 7 days, excluding private accounts)
    func getRecentUsers(limit: Int = 20) async throws -> [RecentUser] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🆕 DISCOVERY: Fetching recent users (last 7 days, limit: \(limit))")
        
        // Calculate 7 days ago (extended for testing)
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        // Query users created in last 7 days
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: cutoffDate))
            .whereField(FirebaseSchema.UserDocument.isPrivate, isEqualTo: false) // Exclude private accounts
            .order(by: FirebaseSchema.UserDocument.createdAt, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let recentUsers = snapshot.documents.compactMap { doc -> RecentUser? in
            let data = doc.data()
            
            guard let username = data[FirebaseSchema.UserDocument.username] as? String,
                  let displayName = data[FirebaseSchema.UserDocument.displayName] as? String,
                  let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            let profileImageURL = data[FirebaseSchema.UserDocument.profileImageURL] as? String
            let isVerified = data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false
            
            return RecentUser(
                id: doc.documentID,
                username: username,
                displayName: displayName,
                profileImageURL: profileImageURL,
                joinedAt: createdAt,
                isVerified: isVerified
            )
        }
        
        print("✅ DISCOVERY: Found \(recentUsers.count) recent users")
        return recentUsers
    }
    
    // MARK: - Hype Leaderboard
    
    /// Get top videos by hype count (last 7 days)
    func getHypeLeaderboard(limit: Int = 10) async throws -> [LeaderboardVideo] {
        
        isLoading = true
        defer { isLoading = false }
        
        print("🔥 DISCOVERY: Fetching hype leaderboard (last 7 days, limit: \(limit))")
        
        // Calculate 7 days ago
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        // Query top videos by hype count from last 7 days
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.createdAt, isGreaterThanOrEqualTo: Timestamp(date: cutoffDate))
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let leaderboardVideos = snapshot.documents.compactMap { doc -> LeaderboardVideo? in
            let data = doc.data()
            
            guard let title = data[FirebaseSchema.VideoDocument.title] as? String,
                  let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String,
                  let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String,
                  let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int,
                  let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int,
                  let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String,
                  let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() else {
                print("⚠️ DISCOVERY: Skipping video - missing required fields")
                return nil
            }
            
            let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String
            
            print("🎬 DISCOVERY: Video '\(title)' by '@\(creatorName)' - \(hypeCount) hypes")
            
            return LeaderboardVideo(
                id: doc.documentID,
                title: title,
                creatorID: creatorID,
                creatorName: creatorName,
                thumbnailURL: thumbnailURL,
                hypeCount: hypeCount,
                coolCount: coolCount,
                temperature: temperature,
                createdAt: createdAt
            )
        }
        
        print("✅ DISCOVERY: Found \(leaderboardVideos.count) leaderboard videos")
        return leaderboardVideos
    }
    
    // MARK: - Helper Methods
    
    /// Refresh both recent users and leaderboard
    func refreshDiscoveryData(userLimit: Int = 20, leaderboardLimit: Int = 10) async throws -> (users: [RecentUser], videos: [LeaderboardVideo]) {
        
        print("🔄 DISCOVERY: Refreshing all discovery data")
        
        async let users = getRecentUsers(limit: userLimit)
        async let videos = getHypeLeaderboard(limit: leaderboardLimit)
        
        let (fetchedUsers, fetchedVideos) = try await (users, videos)
        
        print("✅ DISCOVERY: Refresh complete - \(fetchedUsers.count) users, \(fetchedVideos.count) videos")
        return (users: fetchedUsers, videos: fetchedVideos)
    }
}

// MARK: - Extensions

extension DiscoveryService {
    
    /// Test discovery service functionality
    func helloWorldTest() {
        print("🔍 DISCOVERY SERVICE: Hello World - Ready for discovery!")
        print("🔍 Features: Recent users (7d), Hype leaderboard (7d)")
        print("🔍 Status: Firebase integration, Composite queries")
    }
}
