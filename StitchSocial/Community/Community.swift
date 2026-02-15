//
//  CommunityTypes.swift
//  StitchSocial
//
//  Layer 1: Foundation - Community System Data Models
//  Dependencies: UserTier (Layer 1), SubscriptionTier (Layer 1) ONLY
//  Features: Community, membership, posts, XP, badges, DMs, global XP
//
//  CACHING NOTES:
//  - CommunityBadgeDefinition.allBadges: Static array, cache at app launch, never refetch
//  - CommunityXPCurve.xpRequired(for:): Pure math, cache as lookup table on launch (1000 entries)
//  - CommunityMembership XP/level: Cache per-session, refresh on post/hype actions
//  - CommunityPost feed: Cursor-paginated, cache first 20 locally with 2-min TTL
//  - GlobalCommunityXP tap multiplier: Cache on login, refresh every 15 min
//  - Community list: Cache on first load with 5-min TTL
//  - Badge definitions: Cache once at launch, immutable
//  - Add all above to CachingOptimization.swift under "Community Cache Policy" section
//

import Foundation
import SwiftUI

// MARK: - Community (One Per Influencer+ Creator)

/// Firestore: communities/{creatorID}
struct Community: Codable, Identifiable, Hashable {
    let id: String                      // Same as creatorID
    let creatorID: String
    let creatorUsername: String
    let creatorDisplayName: String
    let creatorTier: UserTier
    var displayName: String             // Community name (editable by creator)
    var description: String
    var memberCount: Int
    var totalPosts: Int
    var isActive: Bool
    var profileImageURL: String?
    var bannerImageURL: String?
    var pinnedPostID: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        creatorID: String,
        creatorUsername: String,
        creatorDisplayName: String,
        creatorTier: UserTier,
        displayName: String? = nil,
        description: String = ""
    ) {
        self.id = creatorID
        self.creatorID = creatorID
        self.creatorUsername = creatorUsername
        self.creatorDisplayName = creatorDisplayName
        self.creatorTier = creatorTier
        self.displayName = displayName ?? "\(creatorDisplayName)'s Community"
        self.description = description
        self.memberCount = 0
        self.totalPosts = 0
        self.isActive = true
        self.profileImageURL = nil
        self.bannerImageURL = nil
        self.pinnedPostID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Only influencer+ can create communities
    /// Developer emails and founder tiers always bypass
    static func canCreateCommunity(tier: UserTier) -> Bool {
        // Developer bypass
        if SubscriptionService.shared.isDeveloper { return true }
        
        switch tier {
        case .influencer, .ambassador, .elite, .partner,
             .legendary, .topCreator, .founder, .coFounder:
            return true
        default:
            return false
        }
    }
}

// MARK: - Community Membership (Per User Per Community)

/// Firestore: communities/{creatorID}/members/{userID}
struct CommunityMembership: Codable, Identifiable, Hashable {
    let id: String                      // Same as userID
    let userID: String
    let communityID: String             // Same as creatorID
    let username: String
    let displayName: String
    var subscriptionTier: SubscriptionTier
    var localXP: Int
    var level: Int
    var earnedBadgeIDs: [String]        // Badge definition IDs earned
    var isModerator: Bool
    var isBanned: Bool
    var lastActiveAt: Date
    var joinedAt: Date
    var totalPosts: Int
    var totalReplies: Int
    var totalHypesGiven: Int
    var totalHypesReceived: Int
    var streamsAttended: Int
    var dailyLoginStreak: Int
    var lastDailyLoginAt: Date?
    
    init(
        userID: String,
        communityID: String,
        username: String,
        displayName: String,
        subscriptionTier: SubscriptionTier
    ) {
        self.id = userID
        self.userID = userID
        self.communityID = communityID
        self.username = username
        self.displayName = displayName
        self.subscriptionTier = subscriptionTier
        self.localXP = 0
        self.level = 1
        self.earnedBadgeIDs = []
        self.isModerator = false
        self.isBanned = false
        self.lastActiveAt = Date()
        self.joinedAt = Date()
        self.totalPosts = 0
        self.totalReplies = 0
        self.totalHypesGiven = 0
        self.totalHypesReceived = 0
        self.streamsAttended = 0
        self.dailyLoginStreak = 0
        self.lastDailyLoginAt = nil
    }
    
    // MARK: - Level Gate Checks
    
    var canPostVideoClips: Bool { level >= 20 }
    var canDMCreator: Bool { level >= 25 }
    var canAccessPrivateLive: Bool { level >= 50 }
    var canBeNominatedMod: Bool { level >= 100 }
    var canCoHostLive: Bool { level >= 850 }
    
    /// Check if a specific feature is unlocked at current level
    func isUnlocked(_ feature: CommunityFeatureGate) -> Bool {
        return level >= feature.requiredLevel
    }
}

// MARK: - Community Feature Gates

enum CommunityFeatureGate: Int, CaseIterable, Codable {
    case profileBorder = 3
    case customFlair = 5
    case reactionEmotes = 10
    case nameHighlight = 15
    case videoClips = 20
    case dmCreator = 25
    case exclusiveEmotes = 30
    case priorityQA = 40
    case privateLive = 50
    case mainFeedBadge = 75
    case modEligible = 100
    case animatedBorder = 150
    case customTitle = 200
    case earlyAccess = 300
    case merchDiscount = 400
    case animatedBadge = 500
    case entranceAnimation = 600
    case voiceChat = 750
    case coHostLive = 850
    case communityWall = 950
    case immortalStatus = 1000
    
    var requiredLevel: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .profileBorder: return "Profile Border"
        case .customFlair: return "Custom Flair Color"
        case .reactionEmotes: return "Reaction Emotes"
        case .nameHighlight: return "Name Highlighted"
        case .videoClips: return "Post Video Clips"
        case .dmCreator: return "DM Creator"
        case .exclusiveEmotes: return "Exclusive Emotes"
        case .priorityQA: return "Priority Q&A"
        case .privateLive: return "Private Live Access"
        case .mainFeedBadge: return "Main Feed Badge"
        case .modEligible: return "Mod Nomination"
        case .animatedBorder: return "Animated Border"
        case .customTitle: return "Custom Title"
        case .earlyAccess: return "Early Content Access"
        case .merchDiscount: return "Merch Discount"
        case .animatedBadge: return "Animated Badge"
        case .entranceAnimation: return "Entrance Animation"
        case .voiceChat: return "Voice Chat"
        case .coHostLive: return "Co-Host Lives"
        case .communityWall: return "Community Wall"
        case .immortalStatus: return "Immortal Status"
        }
    }
}

// MARK: - Community XP Curve

/// Static XP calculation — CACHE AS LOOKUP TABLE ON APP LAUNCH
struct CommunityXPCurve {
    
    /// XP required to reach a specific level
    /// Levels 1-20: Linear fast growth (level × 50)
    /// Levels 21-100: Exponential (50 × level^1.5)
    /// Levels 101-500: Steep (50 × level^1.8)
    /// Levels 501-1000: Prestige grind (50 × level^2.0)
    static func xpRequired(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        
        switch level {
        case 2...20:
            return level * 50
        case 21...100:
            return Int(50.0 * pow(Double(level), 1.5))
        case 101...500:
            return Int(50.0 * pow(Double(level), 1.8))
        case 501...1000:
            return Int(50.0 * pow(Double(level), 2.0))
        default:
            return Int(50.0 * pow(Double(level), 2.0))
        }
    }
    
    /// Total cumulative XP needed to reach a level
    static func totalXPForLevel(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for l in 2...level {
            total += xpRequired(for: l)
        }
        return total
    }
    
    /// Calculate level from raw XP
    static func levelFromXP(_ xp: Int) -> Int {
        var level = 1
        var accumulated = 0
        while level < 1000 {
            let needed = xpRequired(for: level + 1)
            if accumulated + needed > xp { break }
            accumulated += needed
            level += 1
        }
        return level
    }
    
    /// Progress toward next level (0.0 to 1.0)
    static func progressToNextLevel(currentXP: Int) -> Double {
        let currentLevel = levelFromXP(currentXP)
        guard currentLevel < 1000 else { return 1.0 }
        
        let currentLevelTotal = totalXPForLevel(currentLevel)
        let nextLevelTotal = totalXPForLevel(currentLevel + 1)
        let range = nextLevelTotal - currentLevelTotal
        let progress = currentXP - currentLevelTotal
        
        guard range > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(progress) / Double(range)))
    }
}

// MARK: - XP Source Actions

enum CommunityXPSource: String, CaseIterable, Codable {
    case textPost = "text_post"
    case videoPost = "video_post"
    case reply = "reply"
    case receivedHype = "received_hype"
    case gaveHype = "gave_hype"
    case attendedLive = "attended_live"
    case dailyLogin = "daily_login"
    case spentHypeCoin = "spent_coin"
    case spentHypeRating = "spent_hype_rating"
    
    var xpAmount: Int {
        switch self {
        case .textPost: return 10
        case .videoPost: return 25
        case .reply: return 5
        case .receivedHype: return 3
        case .gaveHype: return 1
        case .attendedLive: return 50
        case .dailyLogin: return 15
        case .spentHypeCoin: return 20   // Per coin spent
        case .spentHypeRating: return 2  // Per hype action
        }
    }
    
    var displayName: String {
        switch self {
        case .textPost: return "Posted"
        case .videoPost: return "Video Post"
        case .reply: return "Replied"
        case .receivedHype: return "Received Hype"
        case .gaveHype: return "Gave Hype"
        case .attendedLive: return "Attended Live"
        case .dailyLogin: return "Daily Login"
        case .spentHypeCoin: return "Spent HypeCoin"
        case .spentHypeRating: return "Hype Action"
        }
    }
}

// MARK: - Community Badge Definitions (25 Badges)

/// Static badge definitions — CACHE AT APP LAUNCH, NEVER REFETCH
struct CommunityBadgeDefinition: Codable, Identifiable, Hashable {
    let id: String
    let level: Int
    let name: String
    let emoji: String
    let description: String
    let rewardDescription: String
    
    static let allBadges: [CommunityBadgeDefinition] = [
        .init(id: "badge_01", level: 1,    name: "Welcome",       emoji: "👋", description: "Joined the community",           rewardDescription: "Community profile created"),
        .init(id: "badge_02", level: 3,    name: "New Face",      emoji: "🟢", description: "Getting started",                rewardDescription: "Profile border in community"),
        .init(id: "badge_03", level: 5,    name: "Colorful",      emoji: "🎨", description: "Finding your style",             rewardDescription: "Custom flair color picker"),
        .init(id: "badge_04", level: 8,    name: "Chatterbox",    emoji: "💬", description: "Active in discussions",           rewardDescription: "Reaction emote pack 1"),
        .init(id: "badge_05", level: 10,   name: "Regular",       emoji: "🔁", description: "Consistent presence",            rewardDescription: "Name highlighted in posts"),
        .init(id: "badge_06", level: 13,   name: "Expressive",    emoji: "🎭", description: "Engaging communicator",          rewardDescription: "Animated emote pack"),
        .init(id: "badge_07", level: 15,   name: "Clipper",       emoji: "📹", description: "Video contributor",              rewardDescription: "Post video clips"),
        .init(id: "badge_08", level: 18,   name: "Rising",        emoji: "🌟", description: "On the way up",                  rewardDescription: "Glow effect on username"),
        .init(id: "badge_09", level: 20,   name: "Connected",     emoji: "✉️", description: "Building relationships",          rewardDescription: "DM creator unlocked"),
        .init(id: "badge_10", level: 25,   name: "Dedicated",     emoji: "🔥", description: "Committed member",               rewardDescription: "Exclusive emote pack 2"),
        .init(id: "badge_11", level: 30,   name: "Sharpshooter",  emoji: "🎯", description: "Precision engagement",           rewardDescription: "Priority in Q&A queues"),
        .init(id: "badge_12", level: 40,   name: "Guardian",      emoji: "🛡️", description: "Community protector",             rewardDescription: "Report/flag priority"),
        .init(id: "badge_13", level: 50,   name: "Inner Circle",  emoji: "🔴", description: "Trusted member",                 rewardDescription: "Private live access"),
        .init(id: "badge_14", level: 75,   name: "Superfan",      emoji: "⭐", description: "Above and beyond",               rewardDescription: "Badge visible on main feed"),
        .init(id: "badge_15", level: 100,  name: "Centurion",     emoji: "👑", description: "Elite status",                   rewardDescription: "Mod nomination eligible"),
        .init(id: "badge_16", level: 150,  name: "Diamond",       emoji: "💎", description: "Rare dedication",                rewardDescription: "Animated profile border"),
        .init(id: "badge_17", level: 200,  name: "Pillar",        emoji: "🏛️", description: "Community foundation",            rewardDescription: "Custom community title"),
        .init(id: "badge_18", level: 300,  name: "Eagle",         emoji: "🦅", description: "Soaring above",                  rewardDescription: "Early access to creator content"),
        .init(id: "badge_19", level: 400,  name: "Warlord",       emoji: "⚔️", description: "Battle tested",                  rewardDescription: "Exclusive merch discount"),
        .init(id: "badge_20", level: 500,  name: "Mythic",        emoji: "🐉", description: "Legendary status",               rewardDescription: "Animated badge + sound effect"),
        .init(id: "badge_21", level: 600,  name: "Transcendent",  emoji: "🌀", description: "Beyond mortal",                  rewardDescription: "Custom entrance animation"),
        .init(id: "badge_22", level: 750,  name: "Oracle",        emoji: "🔮", description: "All-seeing",                     rewardDescription: "Direct voice chat with creator"),
        .init(id: "badge_23", level: 850,  name: "Cosmic",        emoji: "🪐", description: "Universe-level",                 rewardDescription: "Co-host live streams"),
        .init(id: "badge_24", level: 950,  name: "Eternal",       emoji: "⚡", description: "Timeless presence",              rewardDescription: "Name on community wall"),
        .init(id: "badge_25", level: 1000, name: "Immortal",      emoji: "🏆", description: "Maximum dedication",             rewardDescription: "Custom badge + creator collab invite")
    ]
    
    /// Get badges earned at or below a given level
    static func badgesEarned(atLevel level: Int) -> [CommunityBadgeDefinition] {
        return allBadges.filter { $0.level <= level }
    }
    
    /// Get next unearned badge for a given level
    static func nextBadge(afterLevel level: Int) -> CommunityBadgeDefinition? {
        return allBadges.first { $0.level > level }
    }
}

// MARK: - Community Post

/// Firestore: communities/{creatorID}/posts/{postID}
struct CommunityPost: Codable, Identifiable, Hashable {
    let id: String
    let communityID: String
    let authorID: String
    let authorUsername: String
    let authorDisplayName: String
    var authorLevel: Int
    var authorBadgeIDs: [String]
    let isCreatorPost: Bool
    let postType: CommunityPostType
    var body: String
    var videoLinkID: String?            // Deeplink to main feed video
    var videoThumbnailURL: String?
    var hypeCount: Int
    var replyCount: Int
    var isPinned: Bool
    var isAutoGenerated: Bool           // True for "new video dropped" posts
    let createdAt: Date
    var updatedAt: Date
    
    init(
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        authorBadgeIDs: [String] = [],
        isCreatorPost: Bool,
        postType: CommunityPostType,
        body: String,
        videoLinkID: String? = nil,
        videoThumbnailURL: String? = nil,
        isAutoGenerated: Bool = false
    ) {
        self.id = UUID().uuidString
        self.communityID = communityID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorLevel = authorLevel
        self.authorBadgeIDs = authorBadgeIDs
        self.isCreatorPost = isCreatorPost
        self.postType = postType
        self.body = body
        self.videoLinkID = videoLinkID
        self.videoThumbnailURL = videoThumbnailURL
        self.hypeCount = 0
        self.replyCount = 0
        self.isPinned = false
        self.isAutoGenerated = isAutoGenerated
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum CommunityPostType: String, CaseIterable, Codable {
    case text = "text"
    case videoLink = "video_link"           // Deeplink to main feed video
    case videoClip = "video_clip"           // Short clip uploaded to community
    case poll = "poll"
    case autoVideoAnnouncement = "auto_video_announcement"
    
    var displayName: String {
        switch self {
        case .text: return "Text Post"
        case .videoLink: return "Video Link"
        case .videoClip: return "Video Clip"
        case .poll: return "Poll"
        case .autoVideoAnnouncement: return "New Video"
        }
    }
}

// MARK: - Community Reply

/// Firestore: communities/{creatorID}/posts/{postID}/replies/{replyID}
struct CommunityReply: Codable, Identifiable, Hashable {
    let id: String
    let postID: String
    let communityID: String
    let authorID: String
    let authorUsername: String
    let authorDisplayName: String
    var authorLevel: Int
    let isCreatorReply: Bool
    var body: String
    var hypeCount: Int
    let createdAt: Date
    
    init(
        postID: String,
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        isCreatorReply: Bool,
        body: String
    ) {
        self.id = UUID().uuidString
        self.postID = postID
        self.communityID = communityID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorLevel = authorLevel
        self.isCreatorReply = isCreatorReply
        self.body = body
        self.hypeCount = 0
        self.createdAt = Date()
    }
}

// MARK: - Community DM (Member ↔ Creator)

/// Firestore: communities/{creatorID}/dms/{conversationID}/messages/{messageID}
struct CommunityDM: Codable, Identifiable, Hashable {
    let id: String
    let communityID: String
    let senderID: String
    let senderUsername: String
    let recipientID: String
    let body: String
    var isRead: Bool
    let createdAt: Date
    
    init(
        communityID: String,
        senderID: String,
        senderUsername: String,
        recipientID: String,
        body: String
    ) {
        self.id = UUID().uuidString
        self.communityID = communityID
        self.senderID = senderID
        self.senderUsername = senderUsername
        self.recipientID = recipientID
        self.body = body
        self.isRead = false
        self.createdAt = Date()
    }
}

/// DM Conversation summary for list view
/// Firestore: communities/{creatorID}/dms/{conversationID}
struct CommunityDMConversation: Codable, Identifiable, Hashable {
    let id: String                      // Deterministic: sorted userID combo
    let communityID: String
    let memberID: String
    let memberUsername: String
    let memberDisplayName: String
    var memberLevel: Int
    let creatorID: String
    var lastMessage: String
    var lastMessageAt: Date
    var unreadCountMember: Int
    var unreadCountCreator: Int
    
    init(
        communityID: String,
        memberID: String,
        memberUsername: String,
        memberDisplayName: String,
        memberLevel: Int,
        creatorID: String
    ) {
        // Deterministic ID for consistent lookups
        let sorted = [memberID, creatorID].sorted()
        self.id = "\(sorted[0])_\(sorted[1])"
        self.communityID = communityID
        self.memberID = memberID
        self.memberUsername = memberUsername
        self.memberDisplayName = memberDisplayName
        self.memberLevel = memberLevel
        self.creatorID = creatorID
        self.lastMessage = ""
        self.lastMessageAt = Date()
        self.unreadCountMember = 0
        self.unreadCountCreator = 0
    }
}

// MARK: - Global Community XP

/// Firestore: users/{userID}/globalCommunityXP
struct GlobalCommunityXP: Codable, Hashable {
    let userID: String
    var totalGlobalXP: Int              // Sum of all communities at 25%
    var globalLevel: Int
    var permanentCloutBonus: Int        // Accumulated from level milestones
    var tapMultiplierBonus: Int         // 0-5 bonus taps from global level
    var communitiesActive: Int          // Number of communities contributing
    var lastCalculatedAt: Date
    
    init(userID: String) {
        self.userID = userID
        self.totalGlobalXP = 0
        self.globalLevel = 1
        self.permanentCloutBonus = 0
        self.tapMultiplierBonus = 0
        self.communitiesActive = 0
        self.lastCalculatedAt = Date()
    }
    
    // MARK: - Global Level Rewards
    
    /// Clout bonus awarded at global level milestones
    static func cloutBonusForLevel(_ level: Int) -> Int {
        switch level {
        case 10: return 50
        case 25: return 150
        case 50: return 500
        case 75: return 1000
        case 100: return 2000
        case 150: return 3500
        case 200: return 5000
        default: return 0
        }
    }
    
    /// Tap multiplier bonus based on global level (per community per day)
    static func tapMultiplierForLevel(_ level: Int) -> Int {
        switch level {
        case 0..<10: return 0
        case 10..<25: return 1
        case 25..<50: return 2
        case 50..<75: return 3
        case 75..<100: return 4
        default: return 5           // Level 100+ = max +5
        }
    }
    
    /// Global XP contribution rate from local community XP
    static let localToGlobalRate: Double = 0.25
    
    /// Calculate global XP contribution from local XP
    static func globalContribution(from localXP: Int) -> Int {
        return Int(Double(localXP) * localToGlobalRate)
    }
}

// MARK: - Community Tap Multiplier Usage (Per Community Per Day)

/// Local cache only — tracks daily bonus tap usage per community
/// CACHING: Store as local dictionary [communityID: tapsUsedToday], reset at midnight
/// No Firestore reads per tap, sync count at end of session
struct CommunityTapUsage: Codable {
    let communityID: String
    let date: String                    // "yyyy-MM-dd" for daily reset
    var bonusTapsUsed: Int
    let bonusTapsAllowed: Int           // From GlobalCommunityXP.tapMultiplierForLevel
    
    var hasRemainingBonusTaps: Bool {
        return bonusTapsUsed < bonusTapsAllowed
    }
    
    var remainingBonusTaps: Int {
        return max(0, bonusTapsAllowed - bonusTapsUsed)
    }
}

// MARK: - Community Hype (Post Engagement)

/// Firestore: communities/{creatorID}/posts/{postID}/hypes/{userID}
struct CommunityPostHype: Codable, Identifiable, Hashable {
    let id: String                      // Same as userID
    let postID: String
    let userID: String
    let communityID: String
    let createdAt: Date
    
    init(postID: String, userID: String, communityID: String) {
        self.id = userID
        self.postID = postID
        self.userID = userID
        self.communityID = communityID
        self.createdAt = Date()
    }
}

// MARK: - XP Transaction Log

/// Firestore: communities/{creatorID}/members/{userID}/xpLog/{logID}
/// BATCHING NOTE: Batch XP writes — don't write per action. Accumulate locally,
/// flush to Firestore every 30 seconds or on app background.
struct CommunityXPTransaction: Codable, Identifiable {
    let id: String
    let communityID: String
    let userID: String
    let source: CommunityXPSource
    let amount: Int
    let newTotalXP: Int
    let newLevel: Int
    let leveledUp: Bool
    let badgeUnlocked: String?          // Badge ID if level-up triggered badge
    let createdAt: Date
    
    init(
        communityID: String,
        userID: String,
        source: CommunityXPSource,
        amount: Int,
        newTotalXP: Int,
        newLevel: Int,
        leveledUp: Bool,
        badgeUnlocked: String? = nil
    ) {
        self.id = UUID().uuidString
        self.communityID = communityID
        self.userID = userID
        self.source = source
        self.amount = amount
        self.newTotalXP = newTotalXP
        self.newLevel = newLevel
        self.leveledUp = leveledUp
        self.badgeUnlocked = badgeUnlocked
        self.createdAt = Date()
    }
}

// MARK: - Community List Item (Lightweight for List View)

/// Denormalized for fast list rendering — avoids N+1 reads
/// CACHING: Cache entire list with 5-min TTL on first community tab load
struct CommunityListItem: Codable, Identifiable, Hashable {
    let id: String                      // communityID / creatorID
    let creatorUsername: String
    let creatorDisplayName: String
    let creatorTier: UserTier
    let profileImageURL: String?
    var memberCount: Int
    var userLevel: Int                  // This user's level in this community
    var userXP: Int
    var unreadCount: Int
    var lastActivityPreview: String
    var lastActivityAt: Date
    var isCreatorLive: Bool
    var isVerified: Bool
}

// MARK: - Auto Video Announcement Payload

/// Used by Cloud Function when creator publishes a video
/// Triggers auto-post in community feed with deeplink
struct VideoAnnouncementPayload: Codable {
    let videoID: String
    let videoTitle: String
    let thumbnailURL: String?
    let creatorID: String
    let communityID: String
    let createdAt: Date
    
    /// Generate the auto-post body
    var postBody: String {
        return "🎬 New drop: \"\(videoTitle)\" — Watch now and discuss!"
    }
}
