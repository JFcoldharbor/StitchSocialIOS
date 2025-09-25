//
//  FirebaseSchema.swift
//  CleanBeta
//
//  Created by James Garmon on 8/6/25.
//  FIXED: Updated for stitchfin database configuration
//

//
//  FirebaseSchema.swift
//  CleanBeta
//
//  Layer 3: Firebase Foundation - Database Schema & Index Definitions
//  Defines Firestore collection structures, validation schemas, and performance indexes
//  Dependencies: CoreTypes.swift only - No external service dependencies
//  Database: stitchfin
//

import Foundation

// MARK: - Firebase Database Schema

/// Centralized database schema definitions for Firestore collections
/// Ensures consistent data structures across the entire stitchfin database
struct FirebaseSchema {
    
    // MARK: - Database Configuration
    
    /// Database identifier for stitchfin
    static let databaseName = "stitchfin"
    
    /// Validate database configuration
    static func validateDatabaseConfig() -> Bool {
        guard !databaseName.isEmpty else {
            print("❌ FIREBASE SCHEMA: Database name is empty")
            return false
        }
        
        print("✅ FIREBASE SCHEMA: Configured for database: \(databaseName)")
        return true
    }
    
    // MARK: - Collection Names
    
    struct Collections {
        static let videos = "videos"
        static let users = "users"
        static let threads = "threads"
        static let engagement = "engagement"
        static let interactions = "interactions"
        static let tapProgress = "tapProgress"
        static let notifications = "notifications"
        static let following = "following"
        static let userBadges = "userBadges"
        static let progression = "progression"
        static let analytics = "analytics"
        static let comments = "comments"
        static let reports = "reports"
        static let cache = "cache"
        static let system = "system"
        
        /// Get full collection path for stitchfin database
           static func fullPath(for collection: String) -> String {
               return "projects/stitchbeta-8bbfe/databases/\(databaseName)/documents/\(collection)"
           }
           
           /// Validate all collection names
           static func validateCollections() -> [String] {
               let collections = [
                   videos, users, threads, engagement, interactions,
                   tapProgress, notifications, following, userBadges,
                   progression, analytics, comments, reports, cache,
                   system  // ← ADD THIS TO THE VALIDATION ARRAY TOO
               ]
               
               let invalidCollections = collections.filter { $0.isEmpty }
               
               if invalidCollections.isEmpty {
                   print("✅ FIREBASE SCHEMA: All \(collections.count) collections validated for \(databaseName)")
               } else {
                   print("❌ FIREBASE SCHEMA: Invalid collections found: \(invalidCollections)")
               }
               
               return invalidCollections
           }
       }
    
    // MARK: - Video Document Schema
    
    struct VideoDocument {
        // Core video fields
        static let id = "id"
        static let title = "title"
        static let videoURL = "videoURL"
        static let thumbnailURL = "thumbnailURL"
        static let creatorID = "creatorID"
        static let creatorName = "creatorName"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        
        // Thread hierarchy fields
        static let threadID = "threadID"
        static let replyToVideoID = "replyToVideoID"
        static let conversationDepth = "conversationDepth"
        static let childVideoIDs = "childVideoIDs"
        static let stepchildVideoIDs = "stepchildVideoIDs"
        
        // Engagement fields
        static let viewCount = "viewCount"
        static let hypeCount = "hypeCount"
        static let coolCount = "coolCount"
        static let replyCount = "replyCount"
        static let shareCount = "shareCount"
        static let lastEngagementAt = "lastEngagementAt"
        
        // Metadata fields
        static let duration = "duration"
        static let aspectRatio = "aspectRatio"
        static let fileSize = "fileSize"
        static let temperature = "temperature"
        static let contentType = "contentType"
        static let qualityScore = "qualityScore"
        static let discoverabilityScore = "discoverabilityScore"
        static let isPromoted = "isPromoted"
        
        // Internal fields
        static let isInternalAccount = "isInternalAccount"
        static let isDeleted = "isDeleted"
        static let moderationStatus = "moderationStatus"
        
        /// Full document path in stitchfin database
        static func documentPath(videoID: String) -> String {
            return Collections.fullPath(for: Collections.videos) + "/\(videoID)"
        }
    }
    
    // MARK: - User Document Schema
    
    struct UserDocument {
        // Core user fields
        static let id = "id"
        static let username = "username"
        static let displayName = "displayName"
        static let email = "email"
        static let profileImageURL = "profileImageURL"
        static let bio = "bio"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let lastActiveAt = "lastActiveAt"
        
        // Tier and status fields
        static let tier = "tier"
        static let clout = "clout"
        static let isVerified = "isVerified"
        static let isInternalAccount = "isInternalAccount"
        static let isBanned = "isBanned"
        static let isPrivate = "isPrivate"
        
        // Statistics fields
        static let followerCount = "followerCount"
        static let followingCount = "followingCount"
        static let videoCount = "videoCount"
        static let threadCount = "threadCount"
        static let totalHypesReceived = "totalHypesReceived"
        static let totalCoolsReceived = "totalCoolsReceived"
        static let deletedVideoCount = "deletedVideoCount"
        
        // Settings fields
        static let notificationSettings = "notificationSettings"
        static let privacySettings = "privacySettings"
        static let contentPreferences = "contentPreferences"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.users) + "/\(userID)"
        }
    }
    
    // MARK: - Thread Document Schema
    
    struct ThreadDocument {
        // Core thread fields
        static let id = "id"
        static let title = "title"
        static let description = "description"
        static let creatorID = "creatorID"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let lastActivityAt = "lastActivityAt"
        
        // Thread structure fields
        static let parentVideoID = "parentVideoID"
        static let childVideoIDs = "childVideoIDs"
        static let stepchildVideoIDs = "stepchildVideoIDs"
        static let conversationDepth = "conversationDepth"
        static let maxDepth = "maxDepth"
        
        // Thread status fields
        static let isLocked = "isLocked"
        static let isArchived = "isArchived"
        static let temperature = "temperature"
        static let trending = "trending"
        static let participantCount = "participantCount"
        
        // Engagement summary
        static let totalReplies = "totalReplies"
        static let totalEngagement = "totalEngagement"
        static let averageEngagement = "averageEngagement"
        
        /// Full document path in stitchfin database
        static func documentPath(threadID: String) -> String {
            return Collections.fullPath(for: Collections.threads) + "/\(threadID)"
        }
    }
    
    // MARK: - Engagement Document Schema
    
    struct EngagementDocument {
        // Core engagement fields
        static let videoID = "videoID"
        static let creatorID = "creatorID"
        static let hypeCount = "hypeCount"
        static let coolCount = "coolCount"
        static let shareCount = "shareCount"
        static let replyCount = "replyCount"
        static let viewCount = "viewCount"
        static let lastEngagementAt = "lastEngagementAt"
        static let updatedAt = "updatedAt"
        
        // Calculated fields
        static let netScore = "netScore"
        static let engagementRatio = "engagementRatio"
        static let velocityScore = "velocityScore"
        static let trendingScore = "trendingScore"
        
        /// Full document path in stitchfin database
        static func documentPath(videoID: String) -> String {
            return Collections.fullPath(for: Collections.engagement) + "/\(videoID)"
        }
    }
    
    // MARK: - Interaction Document Schema (Subcollection)
    
    struct InteractionDocument {
        static let userID = "userID"
        static let videoID = "videoID"
        static let engagementType = "engagementType"
        static let timestamp = "timestamp"
        static let currentTaps = "currentTaps"
        static let requiredTaps = "requiredTaps"
        static let isCompleted = "isCompleted"
        static let impactValue = "impactValue"
        
        /// Full document path in stitchfin database
        static func documentPath(interactionID: String) -> String {
            return Collections.fullPath(for: Collections.interactions) + "/\(interactionID)"
        }
    }
    
    // MARK: - Tap Progress Document Schema
    
    struct TapProgressDocument {
        static let videoID = "videoID"
        static let userID = "userID"
        static let engagementType = "engagementType"
        static let currentTaps = "currentTaps"
        static let requiredTaps = "requiredTaps"
        static let lastTapTime = "lastTapTime"
        static let isCompleted = "isCompleted"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        
        /// Full document path in stitchfin database
        static func documentPath(progressID: String) -> String {
            return Collections.fullPath(for: Collections.tapProgress) + "/\(progressID)"
        }
    }
    
    // MARK: - Notification Document Schema
    
    struct NotificationDocument {
        static let id = "id"
        static let recipientID = "recipientID"
        static let senderID = "senderID"
        static let type = "type"
        static let title = "title"
        static let message = "message"
        static let payload = "payload"
        static let isRead = "isRead"
        static let createdAt = "createdAt"
        static let readAt = "readAt"
        static let expiresAt = "expiresAt"
        
        /// Full document path in stitchfin database
        static func documentPath(notificationID: String) -> String {
            return Collections.fullPath(for: Collections.notifications) + "/\(notificationID)"
        }
    }
    
    // MARK: - Following Document Schema
    
    struct FollowingDocument {
        static let followerID = "followerID"
        static let followingID = "followingID"
        static let createdAt = "createdAt"
        static let isActive = "isActive"
        static let notificationEnabled = "notificationEnabled"
        
        /// Full document path in stitchfin database
        static func documentPath(followingID: String) -> String {
            return Collections.fullPath(for: Collections.following) + "/\(followingID)"
        }
    }
    
    // MARK: - Badge & Progression Schema
    
    struct UserBadgesDocument {
        static let userID = "userID"
        static let earnedBadges = "earnedBadges"
        static let badgeProgress = "badgeProgress"
        static let totalBadgesEarned = "totalBadgesEarned"
        static let lastBadgeEarned = "lastBadgeEarned"
        static let updatedAt = "updatedAt"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.userBadges) + "/\(userID)"
        }
    }
    
    struct ProgressionDocument {
        static let userID = "userID"
        static let currentTier = "currentTier"
        static let clout = "clout"
        static let totalEngagement = "totalEngagement"
        static let tierProgress = "tierProgress"
        static let nextTierRequirements = "nextTierRequirements"
        static let lastTierUpdate = "lastTierUpdate"
        static let updatedAt = "updatedAt"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.progression) + "/\(userID)"
        }
    }
    
    // MARK: - Performance Index Definitions for stitchfin
    
    /// Required Firestore composite indexes for optimal query performance in stitchfin database
    struct RequiredIndexes {
        
        // Videos collection indexes
        static let videosByCreator = [
            VideoDocument.creatorID,
            VideoDocument.createdAt
        ]
        
        static let videosByThread = [
            VideoDocument.threadID,
            VideoDocument.conversationDepth,
            VideoDocument.createdAt
        ]
        
        static let videosByEngagement = [
            VideoDocument.hypeCount,
            VideoDocument.coolCount,
            VideoDocument.createdAt
        ]
        
        static let videosByTemperature = [
            VideoDocument.temperature,
            VideoDocument.createdAt
        ]
        
        static let threadHierarchy = [
            VideoDocument.replyToVideoID,
            VideoDocument.conversationDepth,
            VideoDocument.createdAt
        ]
        
        // User engagement indexes
        static let userEngagementByVideo = [
            InteractionDocument.userID,
            InteractionDocument.videoID,
            InteractionDocument.timestamp
        ]
        
        static let engagementByType = [
            InteractionDocument.engagementType,
            InteractionDocument.timestamp
        ]
        
        // Following system indexes
        static let followersByUser = [
            FollowingDocument.followingID,
            FollowingDocument.createdAt
        ]
        
        static let followingByUser = [
            FollowingDocument.followerID,
            FollowingDocument.createdAt
        ]
        
        // Notification indexes
        static let notificationsByRecipient = [
            NotificationDocument.recipientID,
            NotificationDocument.isRead,
            NotificationDocument.createdAt
        ]
        
        static let notificationsByType = [
            NotificationDocument.type,
            NotificationDocument.createdAt
        ]
        
        // Thread performance indexes
        static let threadsByActivity = [
            ThreadDocument.lastActivityAt,
            ThreadDocument.trending
        ]
        
        static let threadsByTemperature = [
            ThreadDocument.temperature,
            ThreadDocument.participantCount
        ]
        
        /// Generate index creation commands for stitchfin database
        static func generateIndexCommands() -> [String] {
            return [
                "firebase firestore:indexes --project=stitchbeta-8bbfe --database=stitchfin",
                "// Add these composite indexes to firestore.indexes.json",
                "// Database: stitchfin",
                "// Collection: videos - Creator timeline",
                "// Collection: videos - Thread hierarchy",
                "// Collection: interactions - User engagement",
                "// Collection: following - Social connections",
                "// Collection: notifications - User notifications"
            ]
        }
    }
    
    // MARK: - Data Validation Rules
    
    /// Validation constraints for document fields in stitchfin database
    struct ValidationRules {
        
        // Video validation
        static let maxVideoTitleLength = 100
        static let minVideoTitleLength = 1
        static let maxVideoDuration: TimeInterval = 300 // 5 minutes
        static let maxVideoFileSize: Int64 = 100 * 1024 * 1024 // 100MB
        static let allowedVideoFormats = ["mp4", "mov", "m4v"]
        
        // User validation
        static let maxUsernameLength = 20
        static let minUsernameLength = 3
        static let maxDisplayNameLength = 50
        static let maxBioLength = 150
        static let usernamePattern = "^[a-zA-Z0-9_]+$"
        
        // Thread validation
        static let maxThreadTitleLength = 100
        static let minThreadTitleLength = 3
        static let maxConversationDepth = 2
        static let maxChildrenPerThread = 10
        static let maxStepchildrenPerChild = 10
        
        // Engagement validation
        static let maxTapsRequired = 10
        static let minTapsRequired = 1
        static let engagementCooldownSeconds = 1
        static let maxEngagementRatePerMinute = 60
        
        // Notification validation
        static let maxNotificationTitleLength = 80
        static let maxNotificationMessageLength = 200
        static let notificationExpirationDays = 30
        
        /// Validate field against constraints
        static func validateField(_ field: String, value: Any, rules: [String: Any]) -> Bool {
            // Implementation would go here for runtime validation
            return true
        }
    }
    
    // MARK: - Document ID Patterns for stitchfin
    
    /// Standardized document ID generation patterns for stitchfin database
    struct DocumentIDPatterns {
        
        // Video IDs: timestamp + random
        static func generateVideoID() -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 1000...9999)
            return "video_\(timestamp)_\(random)"
        }
        
        // Thread IDs: same as parent video ID
        static func generateThreadID(parentVideoID: String) -> String {
            return parentVideoID // Thread ID matches its root video ID
        }
        
        // Engagement document IDs: videoID for easy lookup
        static func generateEngagementID(videoID: String) -> String {
            return videoID
        }
        
        // Interaction IDs: videoID_userID_type
        static func generateInteractionID(videoID: String, userID: String, type: String) -> String {
            return "\(videoID)_\(userID)_\(type)"
        }
        
        // Tap progress IDs: videoID_userID_type
        static func generateTapProgressID(videoID: String, userID: String, type: String) -> String {
            return "\(videoID)_\(userID)_\(type)"
        }
        
        // Following IDs: followerID_followingID
        static func generateFollowingID(followerID: String, followingID: String) -> String {
            return "\(followerID)_\(followingID)"
        }
        
        // Notification IDs: timestamp + random
        static func generateNotificationID() -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 100...999)
            return "notif_\(timestamp)_\(random)"
        }
        
        /// Validate ID format
        static func validateID(_ id: String, type: String) -> Bool {
            switch type {
            case "video":
                return id.hasPrefix("video_") && id.count > 10
            case "notification":
                return id.hasPrefix("notif_") && id.count > 10
            default:
                return !id.isEmpty && id.count >= 3
            }
        }
    }
    
    // MARK: - Query Optimization Patterns for stitchfin
    
    /// Pre-defined query patterns for common operations in stitchfin database
    struct QueryPatterns {
        
        // Home feed queries
        static let homeFeedThreads = """
            stitchfin/videos
            WHERE conversationDepth == 0 
            ORDER BY createdAt DESC
            LIMIT 20
        """
        
        static let threadChildren = """
            stitchfin/videos
            WHERE threadID == {threadID} AND conversationDepth == 1
            ORDER BY createdAt ASC
            LIMIT 10
        """
        
        static let childStepchildren = """
            stitchfin/videos
            WHERE replyToVideoID == {childVideoID} AND conversationDepth == 2
            ORDER BY createdAt ASC
            LIMIT 10
        """
        
        // User content queries
        static let userVideos = """
            stitchfin/videos
            WHERE creatorID == {userID}
            ORDER BY createdAt DESC
            LIMIT 50
        """
        
        static let userThreads = """
            stitchfin/videos
            WHERE creatorID == {userID} AND conversationDepth == 0
            ORDER BY createdAt DESC
            LIMIT 20
        """
        
        // Engagement queries
        static let videoEngagement = """
            stitchfin/engagement/{videoID}/interactions
            WHERE userID == {userID}
        """
        
        static let userTapProgress = """
            stitchfin/tapProgress
            WHERE userID == {userID} AND videoID == {videoID}
        """
        
        // Social queries
        static let userFollowers = """
            stitchfin/following
            WHERE followingID == {userID} AND isActive == true
            ORDER BY createdAt DESC
        """
        
        static let userFollowing = """
            stitchfin/following
            WHERE followerID == {userID} AND isActive == true
            ORDER BY createdAt DESC
        """
        
        // Notification queries
        static let userNotifications = """
            stitchfin/notifications
            WHERE recipientID == {userID}
            ORDER BY createdAt DESC
            LIMIT 50
        """
        
        static let unreadNotifications = """
            stitchfin/notifications
            WHERE recipientID == {userID} AND isRead == false
            ORDER BY createdAt DESC
        """
        
        /// Generate Firestore query for stitchfin database
        static func generateQuery(pattern: String, parameters: [String: String]) -> String {
            var query = pattern
            for (key, value) in parameters {
                query = query.replacingOccurrences(of: "{\(key)}", with: value)
            }
            return query
        }
    }
    
    // MARK: - Data Consistency Rules for stitchfin
    
    /// Business rules for maintaining data consistency in stitchfin database
    struct ConsistencyRules {
        
        // Thread hierarchy rules
        static let threadDepthLimits = [
            0: "thread",    // Root thread (conversationDepth = 0)
            1: "child",     // Direct reply to thread (conversationDepth = 1)
            2: "stepchild"  // Reply to child (conversationDepth = 2, max depth)
        ]
        
        static let maxRepliesPerLevel = [
            0: 10,  // Max 10 children per thread
            1: 10,  // Max 10 stepchildren per child
            2: 0    // Stepchildren cannot have replies
        ]
        
        // Engagement consistency rules
        static let engagementTypes = ["hype", "cool", "share", "reply", "view"]
        static let requiredTapsByTier = [
            "rookie": 1,
            "rising": 2,
            "influencer": 3,
            "partner": 4,
            "topCreator": 5,
            "founder": 1,
            "coFounder": 1
        ]
        
        // User tier progression rules
        static let tierRequirements = [
            "rookie": (clout: 0, followers: 0),
            "rising": (clout: 5000, followers: 50),
            "influencer": (clout: 15000, followers: 200),
            "partner": (clout: 50000, followers: 1000),
            "topCreator": (clout: 150000, followers: 5000),
            "founder": (clout: 0, followers: 0),
            "coFounder": (clout: 0, followers: 0)
        ]
        
        /// Validate data consistency for stitchfin database
        static func validateConsistency(data: [String: Any], type: String) -> [String] {
            var errors: [String] = []
            
            switch type {
            case "video":
                if let depth = data["conversationDepth"] as? Int, depth > 2 {
                    errors.append("Conversation depth exceeds maximum (2)")
                }
            case "user":
                if let username = data["username"] as? String, username.count > ValidationRules.maxUsernameLength {
                    errors.append("Username exceeds maximum length")
                }
            default:
                break
            }
            
            return errors
        }
    }
    
    // MARK: - Security Constraints for stitchfin
    
    /// Security validation constraints for stitchfin database
    struct SecurityConstraints {
        
        // Content moderation
        static let maxReportsPerUser = 10
        static let reportCooldownHours = 24
        static let autoModerationThreshold = 5
        
        // Rate limiting
        static let maxVideosPerDay = 50
        static let maxEngagementsPerMinute = 60
        static let maxFollowsPerDay = 100
        static let maxNotificationsPerUser = 1000
        
        // Thread security
        static let threadCreationCooldownMinutes = 5
        static let maxActiveThreadsPerUser = 20
        static let threadAutoLockDays = 7
        
        // User account security
        static let maxUsernameChangesPerMonth = 2
        static let accountDeletionGracePeriodDays = 30
        static let maxLoginAttemptsPerHour = 10
        
        /// Check rate limits for stitchfin database
        static func checkRateLimit(userID: String, action: String, timeWindow: TimeInterval) -> Bool {
            // Implementation would check action count within time window
            return true
        }
    }
    
    // MARK: - Cache Configuration for stitchfin
    
    /// Caching strategies for different data types in stitchfin database
    struct CacheConfiguration {
        
        // Video content caching
        static let videoCacheTTL: TimeInterval = 300 // 5 minutes
        static let thumbnailCacheTTL: TimeInterval = 3600 // 1 hour
        static let profileImageCacheTTL: TimeInterval = 1800 // 30 minutes
        
        // Engagement data caching
        static let engagementCacheTTL: TimeInterval = 30 // 30 seconds
        static let tapProgressCacheTTL: TimeInterval = 60 // 1 minute
        
        // User data caching
        static let userProfileCacheTTL: TimeInterval = 600 // 10 minutes
        static let followingListCacheTTL: TimeInterval = 300 // 5 minutes
        
        // Thread data caching
        static let threadStructureCacheTTL: TimeInterval = 180 // 3 minutes
        static let threadListCacheTTL: TimeInterval = 120 // 2 minutes
        
        /// Generate cache key for stitchfin database
        static func cacheKey(collection: String, document: String) -> String {
            return "stitchfin_\(collection)_\(document)"
        }
    }
    
    // MARK: - Database Operations for stitchfin
    
    /// Standard database operation patterns for stitchfin database
    struct Operations {
        
        // Batch write patterns
        static let maxBatchSize = 500
        static let batchRetryAttempts = 3
        static let batchTimeoutSeconds = 30
        
        // Transaction patterns
        static let maxTransactionRetries = 5
        static let transactionTimeoutSeconds = 60
        
        // Realtime listener patterns
        static let maxListenersPerView = 5
        static let listenerReconnectDelaySeconds = 2
        static let listenerMaxReconnectAttempts = 10
        
        /// Generate operation metrics for stitchfin database
        static func operationMetrics() -> [String: Any] {
            return [
                "database": databaseName,
                "maxBatchSize": maxBatchSize,
                "maxTransactionRetries": maxTransactionRetries,
                "maxListeners": maxListenersPerView
            ]
        }
    }
    
    // MARK: - Database Initialization
    
    /// Initialize stitchfin database schema
    static func initializeSchema() -> Bool {
        print("🔧 FIREBASE SCHEMA: Initializing stitchfin database schema...")
        
        let databaseValid = validateDatabaseConfig()
        let collectionsValid = Collections.validateCollections().isEmpty
        
        if databaseValid && collectionsValid {
            print("✅ FIREBASE SCHEMA: stitchfin database schema initialized successfully")
            print("📊 FIREBASE SCHEMA: Collections: \(Collections.validateCollections().count)")
            print("🔍 FIREBASE SCHEMA: Indexes: \(RequiredIndexes.generateIndexCommands().count)")
            return true
        } else {
            print("❌ FIREBASE SCHEMA: stitchfin database schema initialization failed")
            return false
        }
    }
}
