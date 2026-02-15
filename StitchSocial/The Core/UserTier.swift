//
//  UserTier.swift
//  CleanBeta
//
//  Created by James Garmon on 7/11/25.
//  UPDATED: Added ambassador tier for 15k-20k clout range
//

import Foundation
import SwiftUI

// MARK: - User System Types

/// User tier system based on clout points
enum UserTier: String, CaseIterable, Codable {
    case rookie = "rookie"
    case rising = "rising"
    case veteran = "veteran"
    case influencer = "influencer"
    case ambassador = "ambassador"      // NEW: 15k-20k range
    case elite = "elite"
    case partner = "partner"
    case legendary = "legendary"
    case topCreator = "top_creator"
    case founder = "founder"
    case coFounder = "co_founder"
    
    var displayName: String {
        switch self {
        case .rookie: return "Rookie"
        case .rising: return "Rising"
        case .veteran: return "Veteran"
        case .influencer: return "Influencer"
        case .ambassador: return "Ambassador"
        case .elite: return "Elite"
        case .partner: return "Partner"
        case .legendary: return "Legendary"
        case .topCreator: return "Top Creator"
        case .founder: return "Founder"
        case .coFounder: return "Co-Founder"
        }
    }
    
    var cloutRange: ClosedRange<Int> {
        switch self {
        case .rookie: return 0...999
        case .rising: return 1000...4999
        case .veteran: return 5000...9999
        case .influencer: return 10000...14999      // ADJUSTED for ambassador
        case .ambassador: return 15000...19999      // NEW tier
        case .elite: return 20000...49999
        case .partner: return 50000...99999
        case .legendary: return 100000...499999
        case .topCreator: return 500000...Int.max
        case .founder: return 0...Int.max
        case .coFounder: return 0...Int.max
        }
    }
    
    // FIXED: Using String badges instead of BadgeType
    var crownBadge: String? {
        switch self {
        case .rookie, .rising, .veteran, .elite, .legendary: return nil
        case .influencer: return "influencer_crown"
        case .ambassador: return "ambassador_crown"     // NEW badge
        case .partner: return "partner_crown"
        case .topCreator: return "top_creator_crown"
        case .founder: return "founder_crown"
        case .coFounder: return "co_founder_crown"
        }
    }
    
    var requiredFollowers: Int {
        switch self {
        case .rookie: return 0
        case .rising: return 1_000
        case .veteran: return 10_000
        case .influencer: return 100_000
        case .ambassador: return 150_000            // NEW: between influencer and elite
        case .elite: return 250_000
        case .partner: return 750_000
        case .legendary: return 2_000_000
        case .topCreator: return 5_000_000
        case .founder, .coFounder: return 0 // Special assignment only
        }
    }
    
    /// Check if this tier has founder privileges
    var isFounderTier: Bool {
        return self == .founder || self == .coFounder
    }
    
    /// Check if this tier is achievable through normal progression
    var isAchievableTier: Bool {
        return !isFounderTier
    }
    
    /// Get the next achievable tier
    var nextTier: UserTier? {
        switch self {
        case .rookie: return .rising
        case .rising: return .veteran
        case .veteran: return .influencer
        case .influencer: return .ambassador        // NEW progression
        case .ambassador: return .elite             // NEW progression
        case .elite: return .partner
        case .partner: return .legendary
        case .legendary: return .topCreator
        case .topCreator: return nil // Max achievable tier
        case .founder, .coFounder: return nil // Special tiers
        }
    }
    
    /// Calculate progress toward next tier (0.0 to 1.0)
    func progressToNext(currentFollowers: Int) -> Double {
        guard let next = nextTier else { return 1.0 }
        
        let currentRequired = self.requiredFollowers
        let nextRequired = next.requiredFollowers
        let progressRange = nextRequired - currentRequired
        let currentProgress = currentFollowers - currentRequired
        
        return max(0.0, min(1.0, Double(currentProgress) / Double(progressRange)))
    }
}

// MARK: - Notification System Types (ADDED BACK - NEEDED BY SERVICES)

/// Primary notification type enum for the Stitch Social app
enum StitchNotificationType: String, CaseIterable, Codable {
    case hype = "hype"
    case cool = "cool"
    case follow = "follow"
    case reply = "reply"
    case mention = "mention"
    case milestone = "milestone"
    case tierUpgrade = "tier_upgrade"
    case system = "system"
    case goLive = "go_live"
    case communityPost = "community_post"
    case communityXP = "community_xp"
    
    var displayName: String {
        switch self {
        case .hype: return "Hype"
        case .cool: return "Cool"
        case .follow: return "Follow"
        case .reply: return "Reply"
        case .mention: return "Mention"
        case .milestone: return "Milestone"
        case .tierUpgrade: return "Tier Upgrade"
        case .system: return "System"
        case .goLive: return "Live"
        case .communityPost: return "Community"
        case .communityXP: return "XP"
        }
    }
    
    var iconName: String {
        switch self {
        case .hype: return "heart.fill"
        case .cool: return "hand.thumbsdown.fill"
        case .follow: return "person.badge.plus.fill"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        case .milestone: return "trophy.fill"
        case .tierUpgrade: return "arrow.up.circle.fill"
        case .system: return "gear.circle.fill"
        case .goLive: return "video.fill"
        case .communityPost: return "bubble.left.and.bubble.right.fill"
        case .communityXP: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .hype: return .red
        case .cool: return .blue
        case .follow: return .green
        case .reply: return .purple
        case .mention: return .orange
        case .milestone: return .yellow
        case .tierUpgrade: return .pink
        case .system: return .gray
        case .goLive: return .red
        case .communityPost: return .cyan
        case .communityXP: return .green
        }
    }
    
    var actionText: String {
        switch self {
        case .hype: return "hyped your video"
        case .cool: return "cooled your video"
        case .follow: return "started following you"
        case .reply: return "replied to your thread"
        case .mention: return "mentioned you"
        case .milestone: return "milestone reached"
        case .tierUpgrade: return "tier upgraded"
        case .system: return "system notification"
        case .goLive: return "is live now"
        case .communityPost: return "posted in community"
        case .communityXP: return "XP earned"
        }
    }
}

/// Core notification document for Firebase
struct StitchNotification: Identifiable {  // âœ…
    let id: String
    let recipientID: String
    let senderID: String
    let type: StitchNotificationType
    let title: String
    let message: String
    let payload: [String: Any]
    let isRead: Bool
    let createdAt: Date
    let readAt: Date?
    let expiresAt: Date?
    
    init(
        id: String = UUID().uuidString,
        recipientID: String,
        senderID: String,
        type: StitchNotificationType,
        title: String,
        message: String,
        payload: [String: Any] = [:],  // âœ… Changed from [String: String]
        isRead: Bool = false,
        createdAt: Date = Date(),
        readAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.recipientID = recipientID
        self.senderID = senderID
        self.type = type
        self.title = title
        self.message = message
        self.payload = payload
        self.isRead = isRead
        self.createdAt = createdAt
        self.readAt = readAt
        self.expiresAt = expiresAt
    }
}

/// Toast notification for in-app display
struct NotificationToast: Codable, Identifiable {
    let id: String
    let type: StitchNotificationType
    let title: String
    let message: String
    let senderUsername: String
    let payload: [String: String]
    let createdAt: Date
    
    var color: Color { type.color }
    var iconName: String { type.iconName }
    var senderName: String { senderUsername }
    
    init(
        id: String = UUID().uuidString,
        type: StitchNotificationType,
        title: String,
        message: String,
        senderUsername: String = "",
        payload: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.senderUsername = senderUsername
        self.payload = payload
        self.createdAt = createdAt
    }
}

// MARK: - Content System Types

/// Video content hierarchy - Thread â†’ Child â†’ Stepchild
enum ContentType: String, CaseIterable, Codable {
    case thread = "thread"        // Original video that starts conversation
    case child = "child"          // Direct reply to thread
    case stepchild = "stepchild"  // Reply to a child (max depth 1)
    
    var displayName: String {
        switch self {
        case .thread: return "Thread"
        case .child: return "Child"
        case .stepchild: return "Stepchild"
        }
    }
    
    var maxDepth: Int {
        switch self {
        case .thread: return 0
        case .child: return 1
        case .stepchild: return 2
        }
    }
}

// MARK: - Authentication States

/// Authentication states for the app
enum AuthState: String, CaseIterable {
    case unauthenticated = "unauthenticated"
    case authenticating = "authenticating"
    case authenticated = "authenticated"
    case signingIn = "signing_in"
    case signingOut = "signing_out"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .unauthenticated: return "Not Signed In"
        case .authenticating: return "Signing In..."
        case .authenticated: return "Signed In"
        case .signingIn: return "Signing In..."
        case .signingOut: return "Signing Out..."
        case .error: return "Sign In Error"
        }
    }
}

/// Video temperature system (like Reddit hot/rising)
enum Temperature: String, CaseIterable, Codable {
    case frozen = "frozen"      // Very low engagement
    case cold = "cold"          // Low engagement
    case cool = "cool"          // Below average
    case warm = "warm"          // Average engagement
    case hot = "hot"            // High engagement
    case blazing = "blazing"    // Viral content
    
    var displayName: String {
        switch self {
        case .frozen: return "Frozen"
        case .cold: return "Cold"
        case .cool: return "Cool"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .blazing: return "Blazing"
        }
    }
    
    var color: Color {
        switch self {
        case .frozen: return .blue
        case .cold: return .cyan
        case .cool: return .green
        case .warm: return .yellow
        case .hot: return .orange
        case .blazing: return .red
        }
    }
    
    var threshold: Double {
        switch self {
        case .frozen: return 0.0
        case .cold: return 0.1
        case .cool: return 0.3
        case .warm: return 0.6
        case .hot: return 0.8
        case .blazing: return 0.95
        }
    }
}

// MARK: - App State Types

/// Main app navigation states
enum AppTab: String, CaseIterable {
    case home = "home"
    case discovery = "discovery"
    case recording = "recording"
    case progression = "progression"
    case notifications = "notifications"
    
    var displayName: String {
        switch self {
        case .home: return "Home"
        case .discovery: return "Discovery"
        case .recording: return "Record"
        case .progression: return "Progress"
        case .notifications: return "Notifications"
        }
    }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .discovery: return "magnifyingglass"
        case .recording: return "plus.circle.fill"
        case .progression: return "chart.line.uptrend.xyaxis"
        case .notifications: return "bell.fill"
        }
    }
}

/// Recording states
enum RecordingState: String, CaseIterable {
    case idle = "idle"
    case recording = "recording"
    case paused = "paused"
    case processing = "processing"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Processing"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }
}

// MARK: - Cache System Types

/// Cache types for different content
enum CacheType: CaseIterable {
    case video
    case image
    case data
    case thumbnail
    case uploadResult
    case userProfile
    case threadData
    case engagement
    
    var prefix: String {
        switch self {
        case .video: return "vid"
        case .image: return "img"
        case .data: return "dat"
        case .thumbnail: return "tmb"
        case .uploadResult: return "upl"
        case .userProfile: return "usr"
        case .threadData: return "thd"
        case .engagement: return "eng"
        }
    }
}

// MARK: - Error Types

/// App-wide error types
enum StitchError: LocalizedError {
    case networkError(String)
    case authenticationError(String)
    case validationError(String)
    case storageError(String)
    case recordingError(String)
    case processingError(String)
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network Error: \(message)"
        case .authenticationError(let message):
            return "Authentication Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .storageError(let message):
            return "Storage Error: \(message)"
        case .recordingError(let message):
            return "Recording Error: \(message)"
        case .processingError(let message):
            return "Processing Error: \(message)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Engagement System Types

/// User starting bonus for new user onboarding and rewards
enum UserStartingBonus: String, CaseIterable, Codable {
    case earlyAdopter = "early_adopter"
    case betaTester = "beta_tester"
    case newcomer = "newcomer"
    case invited = "invited"
    
    var displayName: String {
        switch self {
        case .earlyAdopter: return "Early Adopter"
        case .betaTester: return "Beta Tester"
        case .newcomer: return "Newcomer"
        case .invited: return "Invited"
        }
    }
    
    var bonusAmount: Double {
        switch self {
        case .earlyAdopter: return 50.0
        case .betaTester: return 75.0
        case .newcomer: return 10.0
        case .invited: return 25.0
        }
    }
    
    var bonusDuration: TimeInterval {
        switch self {
        case .earlyAdopter: return 30 * 24 * 60 * 60 // 30 days
        case .betaTester: return 60 * 24 * 60 * 60 // 60 days
        case .newcomer: return 7 * 24 * 60 * 60 // 7 days
        case .invited: return 14 * 24 * 60 * 60 // 14 days
        }
    }
}

/// Hype rating system for dynamic user engagement scoring
struct HypeRating: Codable {
    let userID: String
    var currentRating: Double
    var baseRating: Double
    var engagementDecay: Double
    var communityBonus: Double
    var discoveryPenalty: Double
    var lastUpdate: Date
    var startingBonus: UserStartingBonus
    var bonusExpiresAt: Date?
    
    init(userID: String, baseRating: Double = 100.0, startingBonus: UserStartingBonus = .newcomer) {
        self.userID = userID
        self.currentRating = baseRating + startingBonus.bonusAmount
        self.baseRating = baseRating
        self.engagementDecay = 0.0
        self.communityBonus = 0.0
        self.discoveryPenalty = 0.0
        self.lastUpdate = Date()
        self.startingBonus = startingBonus
        self.bonusExpiresAt = Date().addingTimeInterval(startingBonus.bonusDuration)
    }
    
    /// Calculate effective rating considering time decay and bonuses
    var effectiveRating: Double {
        let now = Date()
        let timeSinceUpdate = now.timeIntervalSince(lastUpdate)
        let decayFactor = max(0.0, 1.0 - (timeSinceUpdate / (24 * 60 * 60))) // Daily decay
        
        var rating = baseRating + communityBonus - discoveryPenalty
        rating *= decayFactor
        
        // Apply starting bonus if still valid
        if let expiry = bonusExpiresAt, now < expiry {
            rating += startingBonus.bonusAmount
        }
        
        return max(0.0, rating)
    }
}

// MARK: - Creation Mode Types

/// Creation flow modes
enum CreationMode: Codable, Hashable {
    case newThread
    case replyToThread(threadID: String)
    case respondToChild(childID: String, threadID: String)
    
    var displayTitle: String {
        switch self {
        case .newThread:
            return "New Thread"
        case .replyToThread:
            return "Reply to Thread"
        case .respondToChild:
            return "Respond to Child"
        }
    }
    
    var contentType: ContentType {
        switch self {
        case .newThread:
            return .thread
        case .replyToThread:
            return .child
        case .respondToChild:
            return .stepchild
        }
    }
}

/// User interaction types
enum InteractionType: String, CaseIterable, Codable {
    case hype = "hype"        // Like/upvote
    case cool = "cool"        // Dislike/downvote
    case reply = "reply"      // Video response
    case share = "share"      // External sharing
    case view = "view"        // Watch video
    
    var displayName: String {
        switch self {
        case .hype: return "Hype"
        case .cool: return "Cool"
        case .reply: return "Reply"
        case .share: return "Share"
        case .view: return "View"
        }
    }
    
    var pointValue: Int {
        switch self {
        case .hype: return 10
        case .cool: return -5
        case .reply: return 50
        case .share: return 25
        case .view: return 1
        }
    }
}

// MARK: - Video System Types

/// Video quality settings
enum RecordingQuality: String, CaseIterable, Codable {
    case standard = "standard"
    case high = "high"
    case premium = "premium"
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        case .premium: return "Premium"
        }
    }
    
    var resolution: CGSize {
        switch self {
        case .standard: return CGSize(width: 720, height: 1280)
        case .high: return CGSize(width: 1080, height: 1920)
        case .premium: return CGSize(width: 1440, height: 2560)
        }
    }
    
    var bitrate: Int {
        switch self {
        case .standard: return 2_000_000  // 2 Mbps
        case .high: return 5_000_000      // 5 Mbps
        case .premium: return 10_000_000  // 10 Mbps
        }
    }
}

// MARK: - User Stats for Badge/Tier System

/// User statistics for tier calculation and badge awards
struct RealUserStats: Codable, Hashable {
    let followers: Int
    let hypes: Int
    let threads: Int
    let posts: Int
    let engagementRate: Double
    let clout: Int
    
    init(followers: Int = 0, hypes: Int = 0, threads: Int = 0, posts: Int = 0, engagementRate: Double = 0.0, clout: Int = 0) {
        self.followers = followers
        self.hypes = hypes
        self.threads = threads
        self.posts = posts
        self.engagementRate = engagementRate
        self.clout = clout
    }
}

// MARK: - Basic Data Structures

/// Simple user information - FIXED: Added bio and isPrivate fields to support ProfileViewModel
struct BasicUserInfo: Codable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let bio: String
    let tier: UserTier
    let clout: Int
    let isVerified: Bool
    let isPrivate: Bool
    let profileImageURL: String?
    let createdAt: Date
    
    init(id: String, username: String, displayName: String, bio: String = "", tier: UserTier, clout: Int, isVerified: Bool = false, isPrivate: Bool = false, profileImageURL: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.tier = tier
        self.clout = clout
        self.isVerified = isVerified
        self.isPrivate = isPrivate
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
    }
}

/// Basic video information
struct BasicVideoInfo: Codable, Hashable {
    let id: String
    let title: String
    let videoURL: String
    let thumbnailURL: String
    let duration: TimeInterval
    let createdAt: Date
    let contentType: ContentType
    let temperature: Temperature
}

/// Engagement metrics
struct EngagementMetrics: Codable, Hashable {
    let hypeCount: Int
    let coolCount: Int
    let replyCount: Int
    let shareCount: Int
    let viewCount: Int
    
    var netScore: Int {
        return hypeCount - coolCount
    }
    
    var engagementRatio: Double {
        let total = hypeCount + coolCount
        return total > 0 ? Double(hypeCount) / Double(total) : 0.0
    }
}

// MARK: - Video Processing Types

/// Video processing states
enum ProcessingState: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Video upload metadata
struct MyVideoUploadMetadata: Codable {
    let originalSize: Int64
    let processedSize: Int64?
    let duration: TimeInterval
    let resolution: CGSize
    let compressionRatio: Double?
    let processingTime: TimeInterval?
    let uploadStarted: Date
    let uploadCompleted: Date?
    
    var compressionPercentage: Double {
        guard let processedSize = processedSize else { return 0 }
        let ratio = 1.0 - (Double(processedSize) / Double(originalSize))
        return max(0, min(100, ratio * 100))
    }
}

// MARK: - Cache System Types Extended

/// Cache policy for different content types
enum CachePolicy: String, Codable {
    case aggressive = "aggressive"    // Cache everything
    case moderate = "moderate"        // Cache frequently accessed
    case minimal = "minimal"          // Cache only critical items
    case disabled = "disabled"        // No caching
    
    var maxItems: Int {
        switch self {
        case .aggressive: return 1000
        case .moderate: return 500
        case .minimal: return 100
        case .disabled: return 0
        }
    }
    
    var ttlSeconds: TimeInterval {
        switch self {
        case .aggressive: return 86400 // 24 hours
        case .moderate: return 43200   // 12 hours
        case .minimal: return 21600    // 6 hours
        case .disabled: return 0
        }
    }
}
