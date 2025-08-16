//
//  SearchService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Basic Search Functionality
//  Dependencies: Firebase Firestore
//  Features: User and video search with prefix matching
//

import Foundation
import FirebaseFirestore

/// Basic search functionality for users and videos
@MainActor
class SearchService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: StitchError?
    
    // MARK: - Initialization
    
    init() {
        print("🔍 SEARCH SERVICE: Initialized with database: \(Config.Firebase.databaseName)")
    }
    
    // MARK: - User Search
    
    /// Search users by username or display name
    func searchUsers(query: String, limit: Int = 20) async throws -> [BasicUserInfo] {
        
        isLoading = true
        defer { isLoading = false }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            print("⚠️ SEARCH SERVICE: Empty query provided")
            return []
        }
        
        guard trimmedQuery.count >= 2 else {
            print("⚠️ SEARCH SERVICE: Query too short (minimum 2 characters)")
            return []
        }
        
        do {
            // Search by username (prefix match)
            let usernameQuery = db.collection(FirebaseSchema.Collections.users)
                .whereField(FirebaseSchema.UserDocument.username, isGreaterThanOrEqualTo: trimmedQuery)
                .whereField(FirebaseSchema.UserDocument.username, isLessThan: trimmedQuery + "\u{f8ff}")
                .limit(to: limit)
            
            let snapshot = try await usernameQuery.getDocuments()
            
            var users: [BasicUserInfo] = []
            
            for document in snapshot.documents {
                let data = document.data()
                
                let userInfo = BasicUserInfo(
                    id: document.documentID,
                    username: data[FirebaseSchema.UserDocument.username] as? String ?? "unknown",
                    displayName: data[FirebaseSchema.UserDocument.displayName] as? String ?? "User",
                    tier: UserTier(rawValue: data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie") ?? .rookie,
                    clout: data[FirebaseSchema.UserDocument.clout] as? Int ?? 1500,
                    isVerified: data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false,
                    profileImageURL: data[FirebaseSchema.UserDocument.profileImageURL] as? String,
                    createdAt: (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
                )
                
                users.append(userInfo)
            }
            
            // Sort by relevance (exact matches first, then partial)
            users.sort { user1, user2 in
                let query1Exact = user1.username.lowercased() == trimmedQuery
                let query2Exact = user2.username.lowercased() == trimmedQuery
                
                if query1Exact && !query2Exact { return true }
                if !query1Exact && query2Exact { return false }
                
                // Secondary sort by tier (higher tiers first)
                return user1.tier.cloutRange.lowerBound > user2.tier.cloutRange.lowerBound
            }
            
            print("✅ SEARCH SERVICE: Found \(users.count) users for query: '\(trimmedQuery)'")
            return users
            
        } catch {
            lastError = .processingError("User search failed: \(error.localizedDescription)")
            print("❌ SEARCH SERVICE: User search failed: \(error)")
            throw lastError!
        }
    }
    
    // MARK: - Video Search
    
    /// Search videos by title or creator name
    func searchVideos(query: String, limit: Int = 20) async throws -> [CoreVideoMetadata] {
        
        isLoading = true
        defer { isLoading = false }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            print("⚠️ SEARCH SERVICE: Empty video query provided")
            return []
        }
        
        guard trimmedQuery.count >= 2 else {
            print("⚠️ SEARCH SERVICE: Video query too short (minimum 2 characters)")
            return []
        }
        
        do {
            // Search by title (prefix match)
            let titleQuery = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.title, isGreaterThanOrEqualTo: trimmedQuery)
                .whereField(FirebaseSchema.VideoDocument.title, isLessThan: trimmedQuery + "\u{f8ff}")
                .whereField(FirebaseSchema.VideoDocument.isDeleted, isEqualTo: false)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
            
            let snapshot = try await titleQuery.getDocuments()
            
            var videos: [CoreVideoMetadata] = []
            
            for document in snapshot.documents {
                if let video = try createVideoFromDocument(document) {
                    videos.append(video)
                }
            }
            
            // Sort by relevance and engagement
            videos.sort { video1, video2 in
                let query1Exact = video1.title.lowercased().contains(trimmedQuery)
                let query2Exact = video2.title.lowercased().contains(trimmedQuery)
                
                if query1Exact && !query2Exact { return true }
                if !query1Exact && query2Exact { return false }
                
                // Secondary sort by engagement score
                let engagement1 = video1.hypeCount + video1.coolCount + video1.replyCount
                let engagement2 = video2.hypeCount + video2.coolCount + video2.replyCount
                
                return engagement1 > engagement2
            }
            
            print("✅ SEARCH SERVICE: Found \(videos.count) videos for query: '\(trimmedQuery)'")
            return videos
            
        } catch {
            lastError = .processingError("Video search failed: \(error.localizedDescription)")
            print("❌ SEARCH SERVICE: Video search failed: \(error)")
            throw lastError!
        }
    }
    
    // MARK: - Combined Search
    
    /// Combined search returning both users and videos
    func searchAll(query: String, userLimit: Int = 10, videoLimit: Int = 10) async throws -> SearchResults {
        
        isLoading = true
        defer { isLoading = false }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchResults(users: [], videos: [], totalResults: 0)
        }
        
        do {
            // Execute both searches concurrently
            async let userResults = searchUsers(query: trimmedQuery, limit: userLimit)
            async let videoResults = searchVideos(query: trimmedQuery, limit: videoLimit)
            
            let users = try await userResults
            let videos = try await videoResults
            
            let results = SearchResults(
                users: users,
                videos: videos,
                totalResults: users.count + videos.count
            )
            
            print("✅ SEARCH SERVICE: Combined search found \(results.totalResults) results")
            return results
            
        } catch {
            lastError = .processingError("Combined search failed: \(error.localizedDescription)")
            print("❌ SEARCH SERVICE: Combined search failed: \(error)")
            throw lastError!
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create video metadata from Firestore document
    private func createVideoFromDocument(_ document: DocumentSnapshot) throws -> CoreVideoMetadata? {
        let data = document.data()
        guard let data = data else { return nil }
        
        let id = data[FirebaseSchema.VideoDocument.id] as? String ?? document.documentID
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "Unknown"
        
        let createdAtTimestamp = data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp
        let createdAt = createdAtTimestamp?.dateValue() ?? Date()
        
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String ?? id
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        // Engagement metrics
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        // Content metadata
        let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0.0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        let discoverabilityScore = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false
        let lastEngagementAtTimestamp = data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp
        let lastEngagementAt = lastEngagementAtTimestamp?.dateValue()
        
        // Calculate derived metrics
        let total = hypeCount + coolCount
        let engagementRatio = total > 0 ? Double(hypeCount) / Double(total) : 0.5
        let totalInteractions = hypeCount + coolCount + replyCount + shareCount
        let ageInHours = Date().timeIntervalSince(createdAt) / 3600.0
        let velocityScore = ageInHours > 0 ? Double(totalInteractions) / ageInHours : 0.0
        
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
            temperature: temperature,
            qualityScore: qualityScore,
            engagementRatio: engagementRatio,
            velocityScore: velocityScore,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: lastEngagementAt
        )
    }
    
    /// Test search service functionality
    func helloWorldTest() {
        print("🔍 SEARCH SERVICE: Hello World - Ready for user and video search!")
    }
}

// MARK: - Supporting Types

/// Combined search results structure
struct SearchResults {
    let users: [BasicUserInfo]
    let videos: [CoreVideoMetadata]
    let totalResults: Int
    
    /// Check if search returned any results
    var hasResults: Bool {
        return totalResults > 0
    }
    
    /// Get combined results for display purposes
    var combinedResults: [Any] {
        var results: [Any] = []
        results.append(contentsOf: users)
        results.append(contentsOf: videos)
        return results
    }
}

// MARK: - Search Error Extension

extension StitchError {
    static func searchError(_ message: String) -> StitchError {
        return .processingError(message)
    }
}
