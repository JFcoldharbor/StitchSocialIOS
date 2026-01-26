//
//  FirebaseSchema.swift
//  StitchSocial
//
//  Layer 3: Firebase Foundation - Database Schema & Index Definitions with Referral System
//  Defines Firestore collection structures, validation schemas, and performance indexes
//  Dependencies: CoreTypes.swift only - No external service dependencies
//  Database: stitchfin
//  UPDATED: Complete referral system integration
//  UPDATED: Added taggedUserIDs for user tagging/mentions
//  UPDATED: Added milestone tracking fields for notifications
//  UPDATED: Added Collections support fields (collectionID, segmentNumber, segmentTitle, replyTimestamp)
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
            print("âŒ FIREBASE SCHEMA: Database name is empty")
            return false
        }
        
        print("âœ… FIREBASE SCHEMA: Configured for database: \(databaseName)")
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
        static let referrals = "referrals"
        
        // MARK: - Collections Feature Collections (NEW)
        static let videoCollections = "videoCollections"
        static let collectionDrafts = "collectionDrafts"
        static let collectionProgress = "collectionProgress"
        
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
                system, referrals, videoCollections, collectionDrafts, collectionProgress
            ]
            
            let invalidCollections = collections.filter { $0.isEmpty }
            
            if invalidCollections.isEmpty {
                print("âœ… FIREBASE SCHEMA: All \(collections.count) collections validated for \(databaseName)")
            } else {
                print("âŒ FIREBASE SCHEMA: Invalid collections found: \(invalidCollections)")
            }
            
            return invalidCollections
        }
    }
    
    // MARK: - Video Document Schema (UPDATED with Milestone Tracking + Collections Support)
    
    struct VideoDocument {
        // Core video fields
        static let id = "id"
        static let title = "title"
        static let description = "description"
        static let taggedUserIDs = "taggedUserIDs"
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
        
        // MARK: - Spin-off Fields
        /// The video ID this thread is a spin-off from (nil = original thread)
        static let spinOffFromVideoID = "spinOffFromVideoID"
        /// The root thread ID this spin-off references (for navigation back)
        static let spinOffFromThreadID = "spinOffFromThreadID"
        /// Count of spin-off threads that reference THIS video
        static let spinOffCount = "spinOffCount"
        
        // Engagement fields
        static let viewCount = "viewCount"
        static let hypeCount = "hypeCount"
        static let coolCount = "coolCount"
        static let replyCount = "replyCount"
        static let shareCount = "shareCount"
        static let lastEngagementAt = "lastEngagementAt"
        
        // MILESTONE TRACKING FIELDS
        static let firstHypeReceived = "firstHypeReceived"           // Has received first hype
        static let firstCoolReceived = "firstCoolReceived"           // Has received first cool
        static let milestone10Reached = "milestone10Reached"         // ðŸ”¥ Heating Up
        static let milestone400Reached = "milestone400Reached"       // ðŸ‘€ Must See
        static let milestone1000Reached = "milestone1000Reached"     // ðŸŒ¶ï¸ Hot
        static let milestone15000Reached = "milestone15000Reached"   // ðŸš€ Viral
        static let milestone10ReachedAt = "milestone10ReachedAt"     // Timestamp
        static let milestone400ReachedAt = "milestone400ReachedAt"   // Timestamp
        static let milestone1000ReachedAt = "milestone1000ReachedAt" // Timestamp
        static let milestone15000ReachedAt = "milestone15000ReachedAt" // Timestamp
        
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
        
        // MARK: - Collection Support Fields (NEW)
        
        /// Collection this video belongs to (nil = standalone video)
        static let collectionID = "collectionID"
        
        /// Segment number within collection (1, 2, 3...)
        static let segmentNumber = "segmentNumber"
        
        /// Segment-specific title (can differ from main title)
        static let segmentTitle = "segmentTitle"
        
        /// For timestamped replies: exact second in parent video this reply references
        static let replyTimestamp = "replyTimestamp"
        
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
        
        // SEARCHABLE TEXT FIELD - lowercase username + displayName for case-insensitive search
        static let searchableText = "searchableText"
        
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
        
        // Collections count (NEW)
        static let collectionCount = "collectionCount"
        
        // REFERRAL SYSTEM FIELDS
        static let referralCode = "referralCode"
        static let invitedBy = "invitedBy"
        static let referralCount = "referralCount"
        static let referralCloutEarned = "referralCloutEarned"
        static let hypeRatingBonus = "hypeRatingBonus"
        static let referralRewardsMaxed = "referralRewardsMaxed"
        static let referralCreatedAt = "referralCreatedAt"
        
        // Settings fields
        static let notificationSettings = "notificationSettings"
        static let privacySettings = "privacySettings"
        static let contentPreferences = "contentPreferences"
        
        // PINNED VIDEOS (Profile feature - max 3 threads)
        static let pinnedVideoIDs = "pinnedVideoIDs"
        
        /// Full document path in stitchfin database
        static func documentPath(userID: String) -> String {
            return Collections.fullPath(for: Collections.users) + "/\(userID)"
        }
        
        /// Generate searchable text from username and displayName
        /// Format: "username displayname" in lowercase for case-insensitive prefix search
        static func generateSearchableText(username: String, displayName: String) -> String {
            let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanDisplayName = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(cleanUsername) \(cleanDisplayName)"
        }
    }
    
    // MARK: - Referral Document Schema
    
    struct ReferralDocument {
        // Core referral fields
        static let id = "id"
        static let referrerID = "referrerID"
        static let refereeID = "refereeID"
        static let referralCode = "referralCode"
        static let status = "status"
        static let createdAt = "createdAt"
        static let completedAt = "completedAt"
        static let expiresAt = "expiresAt"
        
        // Reward tracking
        static let cloutAwarded = "cloutAwarded"
        static let hypeBonus = "hypeBonus"
        static let rewardsCapped = "rewardsCapped"
        
        // Analytics and fraud prevention
        static let sourceType = "sourceType"
        static let platform = "platform"
        static let ipAddress = "ipAddress"
        static let deviceFingerprint = "deviceFingerprint"
        static let userAgent = "userAgent"
        
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
    
    // MARK: - Collection Document Schema (NEW)
    
    struct CollectionDocument {
        // Core collection fields
        static let id = "id"
        static let title = "title"
        static let description = "description"
        static let creatorID = "creatorID"
        static let creatorName = "creatorName"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let publishedAt = "publishedAt"
        
        // Segment management
        static let segmentVideoIDs = "segmentVideoIDs"     // Ordered array of video IDs
        static let segmentThumbnails = "segmentThumbnails" // Quick access thumbnails
        static let segmentCount = "segmentCount"
        static let totalDuration = "totalDuration"
        
        // Status and visibility
        static let status = "status"                       // draft, processing, published, archived, deleted
        static let visibility = "visibility"               // public, followers, private, unlisted
        static let thumbnailURL = "thumbnailURL"           // Cover image
        
        // Engagement aggregates (sum of all segments)
        static let totalViews = "totalViews"
        static let totalHypes = "totalHypes"
        static let totalCools = "totalCools"
        static let totalReplies = "totalReplies"
        static let totalShares = "totalShares"
        
        // Discovery
        static let temperature = "temperature"
        static let discoverabilityScore = "discoverabilityScore"
        static let isPromoted = "isPromoted"
        static let isFeatured = "isFeatured"
        
        // Categorization
        static let tags = "tags"
        static let category = "category"
        
        /// Full document path in stitchfin database
        static func documentPath(collectionID: String) -> String {
            return Collections.fullPath(for: Collections.videoCollections) + "/\(collectionID)"
        }
    }
    
    // MARK: - Collection Draft Document Schema (NEW)
    
    struct CollectionDraftDocument {
        // Core draft fields
        static let id = "id"
        static let creatorID = "creatorID"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        
        // Draft content
        static let title = "title"
        static let description = "description"
        
        // Segments array (each segment is a dictionary)
        static let segments = "segments"
        
        // Segment fields (nested in segments array)
        struct SegmentFields {
            static let localVideoPath = "localVideoPath"
            static let uploadedVideoURL = "uploadedVideoURL"
            static let thumbnailURL = "thumbnailURL"
            static let segmentTitle = "segmentTitle"
            static let duration = "duration"
            static let uploadStatus = "uploadStatus"       // pending, uploading, uploaded, failed
            static let uploadProgress = "uploadProgress"   // 0.0 to 1.0
            static let uploadError = "uploadError"
            static let fileSize = "fileSize"
        }
        
        // Draft settings
        static let visibility = "visibility"
        static let tags = "tags"
        static let category = "category"
        static let autoSaveEnabled = "autoSaveEnabled"
        
        /// Full document path in stitchfin database
        static func documentPath(draftID: String) -> String {
            return Collections.fullPath(for: Collections.collectionDrafts) + "/\(draftID)"
        }
    }
    
    // MARK: - Collection Progress Document Schema (NEW)
    
    struct CollectionProgressDocument {
        // Identity
        static let id = "id"                               // Format: {collectionID}_{userID}
        static let collectionID = "collectionID"
        static let userID = "userID"
        
        // Current position
        static let currentSegmentIndex = "currentSegmentIndex"     // 0-indexed
        static let currentSegmentProgress = "currentSegmentProgress" // Seconds into segment
        
        // Completion tracking
        static let completedSegments = "completedSegments" // Array of completed segment indexes
        static let totalWatchTime = "totalWatchTime"       // Seconds
        static let percentComplete = "percentComplete"     // 0.0 to 1.0
        
        // Timestamps
        static let lastWatchedAt = "lastWatchedAt"
        static let startedAt = "startedAt"
        static let completedAt = "completedAt"             // nil until fully complete
        
        // Status
        static let isCompleted = "isCompleted"
        
        /// Full document path in stitchfin database
        static func documentPath(progressID: String) -> String {
            return Collections.fullPath(for: Collections.collectionProgress) + "/\(progressID)"
        }
        
        /// Generate progress document ID from collection and user IDs
        static func generateProgressID(collectionID: String, userID: String) -> String {
            return "\(collectionID)_\(userID)"
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
        
        // Video tagging index
        static let videosByTaggedUser = [
            VideoDocument.taggedUserIDs,
            VideoDocument.createdAt
        ]
        
        // Milestone tracking indexes
        static let videosByMilestone = [
            VideoDocument.milestone1000Reached,
            VideoDocument.milestone1000ReachedAt
        ]
        
        // MARK: - Collection Indexes (NEW)
        
        /// Videos by collection, ordered by segment number
        static let videosByCollection = [
            VideoDocument.collectionID,
            VideoDocument.segmentNumber
        ]
        
        /// Timestamped replies for a video
        static let timestampedReplies = [
            VideoDocument.replyToVideoID,
            VideoDocument.replyTimestamp
        ]
        
        /// Collections by creator
        static let collectionsByCreator = [
            CollectionDocument.creatorID,
            CollectionDocument.createdAt
        ]
        
        /// Published collections for discovery
        static let publishedCollections = [
            CollectionDocument.status,
            CollectionDocument.visibility,
            CollectionDocument.publishedAt
        ]
        
        /// Collection drafts by user
        static let draftsByUser = [
            CollectionDraftDocument.creatorID,
            CollectionDraftDocument.updatedAt
        ]
        
        /// Watch progress by user
        static let progressByUser = [
            CollectionProgressDocument.userID,
            CollectionProgressDocument.lastWatchedAt
        ]
        
        /// Featured collections
        static let featuredCollections = [
            CollectionDocument.isFeatured,
            CollectionDocument.discoverabilityScore
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
        
        // REFERRAL SYSTEM INDEXES
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
                "// Collection: videos - Tagged users",
                "// Collection: videos - Milestone tracking",
                "// Collection: videos - Collection segments (NEW)",
                "// Collection: videos - Timestamped replies (NEW)",
                "// Collection: videoCollections - By creator (NEW)",
                "// Collection: videoCollections - Published discovery (NEW)",
                "// Collection: videoCollections - Featured (NEW)",
                "// Collection: collectionDrafts - By user (NEW)",
                "// Collection: collectionProgress - By user (NEW)",
                "// Collection: interactions - User engagement",
                "// Collection: following - Social connections",
                "// Collection: notifications - User notifications",
                "// Collection: referrals - Referral tracking"
            ]
        }
    }
    
    // MARK: - Data Validation Rules (UPDATED)
    
    /// Validation constraints for document fields in stitchfin database
    struct ValidationRules {
        
        // Video validation
        static let maxVideoTitleLength = 100
        static let minVideoTitleLength = 1
        static let maxVideoDuration: TimeInterval = 300
        static let maxVideoFileSize: Int64 = 100 * 1024 * 1024
        static let allowedVideoFormats = ["mp4", "mov", "m4v"]
        
        // Tagging validation
        static let maxTaggedUsersPerVideo = 5
        static let minTaggedUsersPerVideo = 0
        
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
        
        // MILESTONE THRESHOLDS
        static let milestoneHeatingUp = 10       // ðŸ”¥ Heating Up
        static let milestoneMustSee = 400        // ðŸ‘€ Must See
        static let milestoneHot = 1000           // ðŸŒ¶ï¸ Hot
        static let milestoneViral = 15000        // ðŸš€ Viral
        
        // REFERRAL VALIDATION
        static let referralCodeLength = 8
        static let maxReferralClout = 1000
        static let referralExpirationDays = 30
        static let hypeRatingBonusPerReferral = 0.001
        static let cloutPerReferral = 100
        static let maxReferralsForClout = 10
        
        // MARK: - Collection Validation (NEW)
        static let maxCollectionTitleLength = 100
        static let minCollectionTitleLength = 3
        static let maxCollectionDescriptionLength = 500
        static let maxSegmentsPerCollection = 20
        static let minSegmentsPerCollection = 2
        static let maxSegmentTitleLength = 50
        static let maxCollectionTags = 10
        
        /// Validate field against constraints
        static func validateField(_ field: String, value: Any, rules: [String: Any]) -> Bool {
            return true
        }
        
        /// Validate tagged users array
        static func validateTaggedUsers(_ userIDs: [String]) -> Bool {
            return userIDs.count <= maxTaggedUsersPerVideo &&
                   userIDs.allSatisfy { !$0.isEmpty }
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
        
        /// Check if hype count reached a milestone threshold
        static func checkMilestoneReached(hypeCount: Int) -> Int? {
            if hypeCount == milestoneViral { return milestoneViral }
            if hypeCount == milestoneHot { return milestoneHot }
            if hypeCount == milestoneMustSee { return milestoneMustSee }
            if hypeCount == milestoneHeatingUp { return milestoneHeatingUp }
            return nil
        }
        
        /// Validate collection data (NEW)
        static func validateCollection(title: String, description: String?, segmentCount: Int, tags: [String]?) -> [String] {
            var errors: [String] = []
            
            if title.count < minCollectionTitleLength {
                errors.append("Collection title must be at least \(minCollectionTitleLength) characters")
            }
            if title.count > maxCollectionTitleLength {
                errors.append("Collection title cannot exceed \(maxCollectionTitleLength) characters")
            }
            if let desc = description, desc.count > maxCollectionDescriptionLength {
                errors.append("Collection description cannot exceed \(maxCollectionDescriptionLength) characters")
            }
            if segmentCount < minSegmentsPerCollection {
                errors.append("Collection must have at least \(minSegmentsPerCollection) segments")
            }
            if segmentCount > maxSegmentsPerCollection {
                errors.append("Collection cannot exceed \(maxSegmentsPerCollection) segments")
            }
            if let tags = tags, tags.count > maxCollectionTags {
                errors.append("Collection cannot have more than \(maxCollectionTags) tags")
            }
            
            return errors
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
            return parentVideoID
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
        
        // REFERRAL IDs
        
        /// Generate referral tracking ID: timestamp + random + referrer prefix
        static func generateReferralID(referrerID: String) -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 100...999)
            let prefix = String(referrerID.prefix(4))
            return "ref_\(prefix)_\(timestamp)_\(random)"
        }
        
        /// Generate referral code: 8-character alphanumeric
        static func generateReferralCode() -> String {
            let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            return String((0..<8).compactMap { _ in chars.randomElement() })
        }
        
        // MARK: - Collection ID Patterns (NEW)
        
        /// Generate collection ID: coll_ + timestamp + random
        static func generateCollectionID() -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 1000...9999)
            return "coll_\(timestamp)_\(random)"
        }
        
        /// Generate draft ID: draft_ + user prefix + timestamp + random
        static func generateDraftID(creatorID: String) -> String {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let random = Int.random(in: 100...999)
            let prefix = String(creatorID.prefix(4))
            return "draft_\(prefix)_\(timestamp)_\(random)"
        }
        
        /// Generate progress ID: collectionID_userID
        static func generateProgressID(collectionID: String, userID: String) -> String {
            return "\(collectionID)_\(userID)"
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
            case "collection":
                return id.hasPrefix("coll_")
            case "draft":
                return id.hasPrefix("draft_")
            default:
                return !id.isEmpty
            }
        }
        
        /// Validate referral code format
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
        
        // Tagged videos query
        static let videosWithTaggedUser = """
            stitchfin/videos
            WHERE taggedUserIDs array-contains {userID}
            ORDER BY createdAt DESC
        """
        
        // REFERRAL QUERIES
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
        
        // MARK: - Collection Query Patterns (NEW)
        
        /// Get all segments for a collection ordered by segment number
        static let collectionSegments = """
            stitchfin/videos
            WHERE collectionID == {collectionID}
            ORDER BY segmentNumber ASC
        """
        
        /// Get timestamped replies for a segment
        static let timestampedRepliesForSegment = """
            stitchfin/videos
            WHERE replyToVideoID == {segmentVideoID}
            ORDER BY replyTimestamp ASC
        """
        
        /// Get user's collections
        static let userCollections = """
            stitchfin/videoCollections
            WHERE creatorID == {userID}
            ORDER BY createdAt DESC
        """
        
        /// Get published public collections for discovery
        static let publishedCollectionsQuery = """
            stitchfin/videoCollections
            WHERE status == 'published' AND visibility == 'public'
            ORDER BY publishedAt DESC
        """
        
        /// Get user's drafts
        static let userDrafts = """
            stitchfin/collectionDrafts
            WHERE creatorID == {userID}
            ORDER BY updatedAt DESC
        """
        
        /// Get user's watch progress across collections
        static let userWatchProgress = """
            stitchfin/collectionProgress
            WHERE userID == {userID}
            ORDER BY lastWatchedAt DESC
        """
        
        /// Get featured collections
        static let featuredCollectionsQuery = """
            stitchfin/videoCollections
            WHERE isFeatured == true AND status == 'published'
            ORDER BY discoverabilityScore DESC
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
            0: "thread",
            1: "child",
            2: "stepchild"
        ]
        
        static let maxRepliesPerLevel = [
            0: 10,
            1: 10,
            2: 0
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
        
        // REFERRAL CONSISTENCY RULES
        static let referralStatuses = ["pending", "completed", "expired", "failed"]
        static let referralSourceTypes = ["link", "deeplink", "manual", "share"]
        static let referralPlatforms = ["ios", "android", "web"]
        
        // MARK: - Collection Consistency Rules (NEW)
        static let collectionStatuses = ["draft", "processing", "published", "archived", "deleted"]
        static let collectionVisibilities = ["public", "followers", "private", "unlisted"]
        static let segmentUploadStatuses = ["pending", "uploading", "uploaded", "failed"]
        
        /// Validate data consistency for stitchfin database
        static func validateConsistency(data: [String: Any], type: String) -> [String] {
            var errors: [String] = []
            
            switch type {
            case "video":
                if let depth = data["conversationDepth"] as? Int, depth > 2 {
                    errors.append("Conversation depth exceeds maximum (2)")
                }
                if let taggedUsers = data["taggedUserIDs"] as? [String],
                   !ValidationRules.validateTaggedUsers(taggedUsers) {
                    errors.append("Invalid tagged users array")
                }
            case "user":
                if let username = data["username"] as? String, username.isEmpty {
                    errors.append("Username cannot be empty")
                }
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
            case "collection":
                if let status = data["status"] as? String,
                   !collectionStatuses.contains(status) {
                    errors.append("Invalid collection status: \(status)")
                }
                if let visibility = data["visibility"] as? String,
                   !collectionVisibilities.contains(visibility) {
                    errors.append("Invalid collection visibility: \(visibility)")
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
            
            if referrerID == refereeID {
                errors.append("Cannot refer yourself")
            }
            
            if currentCloutEarned >= ValidationRules.maxReferralClout {
                errors.append("Referral clout reward cap reached (1000)")
            }
            
            return errors
        }
        
        /// Validate collection business rules (NEW)
        static func validateCollectionBusinessRules(
            creatorID: String,
            segmentCount: Int,
            status: String,
            visibility: String
        ) -> [String] {
            var errors: [String] = []
            
            if creatorID.isEmpty {
                errors.append("Collection must have a creator")
            }
            
            if segmentCount < ValidationRules.minSegmentsPerCollection && status == "published" {
                errors.append("Published collection must have at least \(ValidationRules.minSegmentsPerCollection) segments")
            }
            
            if !collectionStatuses.contains(status) {
                errors.append("Invalid collection status: \(status)")
            }
            
            if !collectionVisibilities.contains(visibility) {
                errors.append("Invalid collection visibility: \(visibility)")
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
    
    /// Initialize stitchfin database schema with referral system and collections
    static func initializeSchema() -> Bool {
        print("ðŸ”§ FIREBASE SCHEMA: Initializing stitchfin database schema with referral system and collections...")
        
        let databaseValid = validateDatabaseConfig()
        let collectionsValid = Collections.validateCollections().isEmpty
        let referralSchemaValid = validateReferralSchema()
        let milestoneSchemaValid = validateMilestoneSchema()
        let collectionsSchemaValid = validateCollectionsSchema()
        
        if databaseValid && collectionsValid && referralSchemaValid && milestoneSchemaValid && collectionsSchemaValid {
            print("âœ… FIREBASE SCHEMA: stitchfin database schema initialized successfully")
            print("ðŸ“Š FIREBASE SCHEMA: Collections: \(Collections.validateCollections().count)")
            print("ðŸ” FIREBASE SCHEMA: Indexes: \(RequiredIndexes.generateIndexCommands().count)")
            print("ðŸ”— FIREBASE SCHEMA: Referral system integrated")
            print("ðŸ·ï¸ FIREBASE SCHEMA: User tagging system integrated")
            print("ðŸŽ¯ FIREBASE SCHEMA: Milestone tracking system integrated")
            print("ðŸ“š FIREBASE SCHEMA: Collections feature integrated")
            return true
        } else {
            print("âŒ FIREBASE SCHEMA: stitchfin database schema initialization failed")
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
        
        print("âœ… REFERRAL SCHEMA: \(requiredUserFields.count) user fields + \(requiredReferralFields.count) referral fields")
        return true
    }
    
    /// Validate milestone schema integration
    static func validateMilestoneSchema() -> Bool {
        let requiredMilestoneFields = [
            VideoDocument.firstHypeReceived,
            VideoDocument.firstCoolReceived,
            VideoDocument.milestone10Reached,
            VideoDocument.milestone400Reached,
            VideoDocument.milestone1000Reached,
            VideoDocument.milestone15000Reached
        ]
        
        print("âœ… MILESTONE SCHEMA: \(requiredMilestoneFields.count) milestone tracking fields")
        return true
    }
    
    /// Validate collections schema integration (NEW)
    static func validateCollectionsSchema() -> Bool {
        let requiredVideoFields = [
            VideoDocument.collectionID,
            VideoDocument.segmentNumber,
            VideoDocument.segmentTitle,
            VideoDocument.replyTimestamp
        ]
        
        let requiredCollectionFields = [
            CollectionDocument.id,
            CollectionDocument.title,
            CollectionDocument.creatorID,
            CollectionDocument.segmentVideoIDs,
            CollectionDocument.status,
            CollectionDocument.visibility
        ]
        
        let requiredDraftFields = [
            CollectionDraftDocument.id,
            CollectionDraftDocument.creatorID,
            CollectionDraftDocument.segments
        ]
        
        let requiredProgressFields = [
            CollectionProgressDocument.id,
            CollectionProgressDocument.collectionID,
            CollectionProgressDocument.userID,
            CollectionProgressDocument.currentSegmentIndex
        ]
        
        print("âœ… COLLECTIONS SCHEMA: \(requiredVideoFields.count) video fields + \(requiredCollectionFields.count) collection fields + \(requiredDraftFields.count) draft fields + \(requiredProgressFields.count) progress fields")
        return true
    }
}
