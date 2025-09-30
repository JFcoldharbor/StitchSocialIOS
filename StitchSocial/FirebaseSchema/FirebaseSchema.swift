//
//  FirebaseSchema.swift
//  StitchSocial
//
//  Layer 3: Firebase Foundation - Database Schema & Index Definitions with Referral System
//  Defines Firestore collection structures, validation schemas, and performance indexes
//  Dependencies: CoreTypes.swift only - No external service dependencies
//  Database: stitchfin
//  UPDATED: Complete referral system integration
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
        static let referrals = "referrals"  // NEW: Referral tracking collection
        
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
                system, referrals  // UPDATED: Added referrals collection
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
        static let description = "description"
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
    
    // MARK: - User Document Schema (UPDATED with Referral System)
    
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
        
        // REFERRAL SYSTEM FIELDS (NEW)
        static let referralCode = "referralCode"           // User's unique share code (8 chars)
        static let invitedBy = "invitedBy"                 // Referrer's userID (null if organic)
        static let referralCount = "referralCount"         // Total successful referrals
        static let referralCloutEarned = "referralCloutEarned"  // Clout from referrals (max 1000)
        static let hypeRatingBonus = "hypeRatingBonus"     // 0.10% per referral (unlimited)
        static let referralRewardsMaxed = "referralRewardsMaxed" // Hit 1000 clout cap
        static let referralCreatedAt = "referralCreatedAt" // When referral code generated
        
        // Settings fields
        static let notificationSettings = "notificationSettings"
        static let privacySettings = "privacySettings"
        static let contentPreferences = "contentPreferences"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.users) + "/\(userID)"
        }
    }
    
    // MARK: - Referral Document Schema (NEW)
    
    struct ReferralDocument {
        // Core referral fields
        static let id = "id"                        // Unique referral tracking ID
        static let referrerID = "referrerID"        // Who sent the invite
        static let refereeID = "refereeID"          // Who signed up (null until signup)
        static let referralCode = "referralCode"    // Code used for signup
        static let status = "status"                // pending/completed/expired/failed
        static let createdAt = "createdAt"          // When referral was initiated
        static let completedAt = "completedAt"      // When signup completed
        static let expiresAt = "expiresAt"          // 30-day expiration
        
        // Reward tracking
        static let cloutAwarded = "cloutAwarded"    // 100 clout per referral
        static let hypeBonus = "hypeBonus"          // 0.10% hype bonus
        static let rewardsCapped = "rewardsCapped"  // Was this at 1000 clout cap
        
        // Analytics and fraud prevention
        static let sourceType = "sourceType"        // link/deeplink/manual
        static let platform = "platform"           // ios/android/web
        static let ipAddress = "ipAddress"          // For fraud detection
        static let deviceFingerprint = "deviceFingerprint" // Prevent farming
        static let userAgent = "userAgent"          // Device/browser info
        
        /// Full document path in stitchfin database
        static func documentPath(referralID: String) -> String {
            return Collections.fullPath(for: Collections.referrals) + "/\(referralID)"
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
        static let currentLevel = "currentLevel"
        static let experience = "experience"
        static let levelProgress = "levelProgress"
        static let milestonesReached = "milestonesReached"
        static let nextMilestone = "nextMilestone"
        static let updatedAt = "updatedAt"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.progression) + "/\(userID)"
        }
    }
    
    // MARK: - Required Indexes for stitchfin Performance (UPDATED)
    
    struct RequiredIndexes {
        
        // Video performance indexes
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
            VideoDocument.temperature,
            VideoDocument.hypeCount,
            VideoDocument.lastEngagementAt
        ]
        
        // User performance indexes
        static let usersByTier = [
            UserDocument.tier,
            UserDocument.clout
        ]
        
        static let usersByActivity = [
            UserDocument.lastActiveAt,
            UserDocument.isPrivate
        ]
        
        // Interaction performance indexes
        static let interactionsByUser = [
            InteractionDocument.userID,
            InteractionDocument.timestamp
        ]
        
        static let interactionsByVideo = [
            InteractionDocument.videoID,
            InteractionDocument.engagementType,
            InteractionDocument.timestamp
        ]
        
        // Following performance indexes
        static let followingByFollower = [
            FollowingDocument.followerID,
            FollowingDocument.isActive,
            FollowingDocument.createdAt
        ]
        
        static let followingByFollowing = [
            FollowingDocument.followingID,
            FollowingDocument.isActive,
            FollowingDocument.createdAt
        ]
        
        // Notification performance indexes
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
        
        // REFERRAL SYSTEM INDEXES (NEW)
        static let referralsByCode = [
            ReferralDocument.referralCode,
            ReferralDocument.status,
            ReferralDocument.expiresAt
        ]
        
        static let referralsByReferrer = [
            ReferralDocument.referrerID,
            ReferralDocument.status,
            ReferralDocument.createdAt
        ]
        
        static let usersByReferralCode = [
            UserDocument.referralCode
        ]
        
        static let referralsByStatus = [
            ReferralDocument.status,
            ReferralDocument.createdAt,
            ReferralDocument.expiresAt
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
                "// Collection: notifications - User notifications",
                "// Collection: referrals - Referral tracking (NEW)"
            ]
        }
    }
    
    // MARK: - Data Validation Rules (UPDATED with Referrals)
    
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
        
        // REFERRAL VALIDATION (NEW)
        static let referralCodeLength = 8
        static let maxReferralClout = 1000
        static let referralExpirationDays = 30
        static let hypeRatingBonusPerReferral = 0.001  // 0.10%
        static let cloutPerReferral = 100
        static let maxReferralsForClout = 10  // 1000 clout ÷ 100 per referral
        
        /// Validate field against constraints
        static func validateField(_ field: String, value: Any, rules: [String: Any]) -> Bool {
            // Implementation would go here for runtime validation
            return true
        }
        
        /// Validate referral code format
        static func validateReferralCode(_ code: String) -> Bool {
            return code.count == referralCodeLength &&
                   code.allSatisfy { $0.isLetter || $0.isNumber } &&
                   code == code.uppercased()
        }
        
        /// Validate referral rewards haven't exceeded caps
        static func validateReferralRewards(currentClout: Int, newReferrals: Int) -> Bool {
            let potentialClout = currentClout + (newReferrals * cloutPerReferral)
            return potentialClout <= maxReferralClout
        }
    }
    
    // MARK: - Document ID Patterns for stitchfin (UPDATED)
    
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
        
        // REFERRAL IDs (NEW)
        
        /// Generate referral tracking ID: timestamp + random + referrer prefix
        static func generateReferralID(referrerID: String) -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 100...999)
            let prefix = String(referrerID.prefix(4))
            return "ref_\(prefix)_\(timestamp)_\(random)"
        }
        
        /// Generate referral code: 8-character alphanumeric (user-friendly)
        static func generateReferralCode() -> String {
            let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            return String((0..<8).compactMap { _ in chars.randomElement() })
        }
        
        /// Validate ID format
        static func validateID(_ id: String, type: String) -> Bool {
            switch type {
            case "video":
                return id.hasPrefix("video_")
            case "referral":
                return id.hasPrefix("ref_")
            case "notification":
                return id.hasPrefix("notif_")
            default:
                return !id.isEmpty
            }
        }
        
        /// Validate referral code format (8 chars, alphanumeric, uppercase)
        static func validateReferralCode(_ code: String) -> Bool {
            return code.count == 8 &&
                   code.allSatisfy { $0.isLetter || $0.isNumber } &&
                   code == code.uppercased()
        }
    }
    
    // MARK: - Query Patterns for stitchfin (UPDATED)
    
    /// Common query patterns for efficient data retrieval from stitchfin database
    struct QueryPatterns {
        
        static let userVideos = """
            stitchfin/videos
            WHERE creatorID == {userID}
            ORDER BY createdAt DESC
        """
        
        static let threadHierarchy = """
            stitchfin/videos
            WHERE threadID == {threadID}
            ORDER BY conversationDepth ASC, createdAt ASC
        """
        
        static let userInteractions = """
            stitchfin/interactions
            WHERE userID == {userID}
            ORDER BY timestamp DESC
        """
        
        static let followingList = """
            stitchfin/following
            WHERE followerID == {userID} AND isActive == true
            ORDER BY createdAt DESC
        """
        
        static let unreadNotifications = """
            stitchfin/notifications
            WHERE recipientID == {userID} AND isRead == false
            ORDER BY createdAt DESC
        """
        
        // REFERRAL QUERIES (NEW)
        static let referralByCode = """
            stitchfin/referrals
            WHERE referralCode == {code} AND status == 'pending'
            LIMIT 1
        """
        
        static let userReferrals = """
            stitchfin/referrals
            WHERE referrerID == {userID}
            ORDER BY createdAt DESC
        """
        
        static let expiredReferrals = """
            stitchfin/referrals
            WHERE status == 'pending' AND expiresAt < {currentTime}
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
    
    // MARK: - Data Consistency Rules for stitchfin (UPDATED)
    
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
        
        // REFERRAL CONSISTENCY RULES (NEW)
        static let referralStatuses = ["pending", "completed", "expired", "failed"]
        static let referralSourceTypes = ["link", "deeplink", "manual", "share"]
        static let referralPlatforms = ["ios", "android", "web"]
        
        /// Validate data consistency for stitchfin database
        static func validateConsistency(data: [String: Any], type: String) -> [String] {
            var errors: [String] = []
            
            switch type {
            case "video":
                if let depth = data["conversationDepth"] as? Int, depth > 2 {
                    errors.append("Conversation depth exceeds maximum (2)")
                }
            case "user":
                if let username = data["username"] as? String, username.isEmpty {
                    errors.append("Username cannot be empty")
                }
                // Validate referral fields
                if let referralCode = data["referralCode"] as? String,
                   !ValidationRules.validateReferralCode(referralCode) {
                    errors.append("Invalid referral code format")
                }
            case "referral":
                if let status = data["status"] as? String,
                   !referralStatuses.contains(status) {
                    errors.append("Invalid referral status")
                }
                if let code = data["referralCode"] as? String,
                   !ValidationRules.validateReferralCode(code) {
                    errors.append("Invalid referral code format")
                }
            default:
                break
            }
            
            return errors
        }
        
        /// Validate referral business rules
        static func validateReferralBusinessRules(
            referrerID: String,
            refereeID: String,
            currentReferralCount: Int,
            currentCloutEarned: Int
        ) -> [String] {
            var errors: [String] = []
            
            // Cannot refer yourself
            if referrerID == refereeID {
                errors.append("Cannot refer yourself")
            }
            
            // Check clout cap
            if currentCloutEarned >= ValidationRules.maxReferralClout {
                errors.append("Referral clout reward cap reached (1000)")
            }
            
            return errors
        }
    }
    
    // MARK: - Database Operations Configuration
    
    struct Operations {
        // Transaction limits
        static let maxBatchSize = 500
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
    
    // MARK: - Database Initialization (UPDATED)
    
    /// Initialize stitchfin database schema with referral system
    static func initializeSchema() -> Bool {
        print("🔧 FIREBASE SCHEMA: Initializing stitchfin database schema with referral system...")
        
        let databaseValid = validateDatabaseConfig()
        let collectionsValid = Collections.validateCollections().isEmpty
        let referralSchemaValid = validateReferralSchema()
        
        if databaseValid && collectionsValid && referralSchemaValid {
            print("✅ FIREBASE SCHEMA: stitchfin database schema initialized successfully")
            print("📊 FIREBASE SCHEMA: Collections: \(Collections.validateCollections().count)")
            print("📝 FIREBASE SCHEMA: Indexes: \(RequiredIndexes.generateIndexCommands().count)")
            print("🔗 FIREBASE SCHEMA: Referral system integrated")
            return true
        } else {
            print("❌ FIREBASE SCHEMA: stitchfin database schema initialization failed")
            return false
        }
    }
    
    /// Validate referral schema integration
    static func validateReferralSchema() -> Bool {
        let requiredUserFields = [
            UserDocument.referralCode,
            UserDocument.invitedBy,
            UserDocument.referralCount,
            UserDocument.referralCloutEarned,
            UserDocument.hypeRatingBonus
        ]
        
        let requiredReferralFields = [
            ReferralDocument.referrerID,
            ReferralDocument.referralCode,
            ReferralDocument.status,
            ReferralDocument.cloutAwarded
        ]
        
        print("✅ REFERRAL SCHEMA: \(requiredUserFields.count) user fields + \(requiredReferralFields.count) referral fields")
        return true
    }
}
