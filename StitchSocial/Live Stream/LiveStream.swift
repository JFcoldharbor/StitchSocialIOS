//
//  LiveStreamTypes.swift
//  StitchSocial
//
//  Layer 1: Foundation - Live Stream Data Models
//  Dependencies: UserTier (Layer 1), CommunityTypes (Layer 1) ONLY
//  Features: Stream sessions, duration tiers, video comments, hype events,
//            attendance tracking, collective goals, completion records
//
//  CACHING NOTES:
//  - StreamDurationTier.allTiers: Static array, cache at launch, never refetch
//  - StreamBadgeDefinition.allBadges: Static, cache at launch
//  - LiveStream active doc: Single real-time listener per community, not per viewer
//  - VideoComment queue: Single listener on creator device ONLY
//  - StreamCollectiveGoal: Single listener shared by all viewers (one doc)
//  - StreamAttendance heartbeats: Batch write every 5 min, NOT per interaction
//  - StreamHypeEvent transactions: Batch write every 30 sec, NOT per tap
//  - Post-stream XP/badges: Cloud Function on stream end, NOT client-side
//  - PiP video URL: Cache locally for overlay duration, purge on dismiss
//  - Viewer activity check: Local 15-min timer, no Firestore per check
//  - Add all above to CachingOptimization.swift under "Live Stream Batching" section
//

import Foundation

// MARK: - Live Stream Session

/// Firestore: communities/{creatorID}/streams/{streamID}
struct LiveStream: Codable, Identifiable {
    let id: String
    let creatorID: String
    let communityID: String             // Same as creatorID
    let durationTier: StreamDurationTier
    var status: StreamStatus
    var viewerCount: Int
    var peakViewerCount: Int
    var totalCoinsSpent: Int
    var totalHypeEvents: Int
    var hypeCount: Int                   // Aggregate free hype taps from all viewers
    var totalVideoComments: Int
    var acceptedVideoComments: Int
    var extensionMinutes: Int           // Bonus time from collective goal
    var maxDurationSeconds: Int         // Tier limit + extensions
    let startedAt: Date
    var endedAt: Date?
    var lastHeartbeatAt: Date           // Creator heartbeat to detect crashes
    
    /// Computed: seconds elapsed since start
    var elapsedSeconds: Int {
        let end = endedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt))
    }
    
    /// Computed: did creator stream the full tier duration?
    var isFullCompletion: Bool {
        let tierSeconds = durationTier.durationSeconds
        return elapsedSeconds >= tierSeconds
    }
    
    /// Computed: progress toward tier duration (0.0 - 1.0+)
    var durationProgress: Double {
        return Double(elapsedSeconds) / Double(durationTier.durationSeconds)
    }
    
    init(
        creatorID: String,
        durationTier: StreamDurationTier
    ) {
        self.id = UUID().uuidString
        self.creatorID = creatorID
        self.communityID = creatorID
        self.durationTier = durationTier
        self.status = .live
        self.viewerCount = 0
        self.peakViewerCount = 0
        self.totalCoinsSpent = 0
        self.totalHypeEvents = 0
        self.hypeCount = 0
        self.totalVideoComments = 0
        self.acceptedVideoComments = 0
        self.extensionMinutes = 0
        self.maxDurationSeconds = durationTier.durationSeconds
        self.startedAt = Date()
        self.endedAt = nil
        self.lastHeartbeatAt = Date()
    }
}

enum StreamStatus: String, Codable {
    case live = "live"
    case ended = "ended"
    case crashed = "crashed"            // No heartbeat for 2 min
}

// MARK: - Stream Duration Tiers (Spark → Triple)

/// Static progression — cache at launch, never changes
enum StreamDurationTier: String, Codable, CaseIterable, Identifiable {
    case spark      // 30 min
    case flame      // 1 hr
    case blaze      // 2 hr
    case inferno    // 4 hr
    case furnace    // 6 hr
    case eruption   // 8 hr
    case volcano    // 10 hr
    case marathon   // 12 hr
    case double     // 24 hr
    case triple     // 36 hr
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .spark: return "Spark"
        case .flame: return "Flame"
        case .blaze: return "Blaze"
        case .inferno: return "Inferno"
        case .furnace: return "Furnace"
        case .eruption: return "Eruption"
        case .volcano: return "Volcano"
        case .marathon: return "Marathon"
        case .double: return "Double"
        case .triple: return "Triple"
        }
    }
    
    var emoji: String {
        switch self {
        case .spark: return "✨"
        case .flame: return "🔥"
        case .blaze: return "💥"
        case .inferno: return "🌋"
        case .furnace: return "⚒️"
        case .eruption: return "🌊"
        case .volcano: return "🗻"
        case .marathon: return "🏃"
        case .double: return "⚡"
        case .triple: return "👑"
        }
    }
    
    var durationSeconds: Int {
        switch self {
        case .spark:    return 30 * 60          // 1,800
        case .flame:    return 60 * 60          // 3,600
        case .blaze:    return 2 * 60 * 60      // 7,200
        case .inferno:  return 4 * 60 * 60      // 14,400
        case .furnace:  return 6 * 60 * 60      // 21,600
        case .eruption: return 8 * 60 * 60      // 28,800
        case .volcano:  return 10 * 60 * 60     // 36,000
        case .marathon: return 12 * 60 * 60     // 43,200
        case .double:   return 24 * 60 * 60     // 86,400
        case .triple:   return 36 * 60 * 60     // 129,600
        }
    }
    
    var durationDisplay: String {
        switch self {
        case .spark:    return "30 min"
        case .flame:    return "1 hr"
        case .blaze:    return "2 hr"
        case .inferno:  return "4 hr"
        case .furnace:  return "6 hr"
        case .eruption: return "8 hr"
        case .volcano:  return "10 hr"
        case .marathon: return "12 hr"
        case .double:   return "24 hr"
        case .triple:   return "36 hr"
        }
    }
    
    /// Required community level to unlock this tier
    var requiredLevel: Int {
        switch self {
        case .spark:    return 50
        case .flame:    return 75
        case .blaze:    return 100
        case .inferno:  return 150
        case .furnace:  return 200
        case .eruption: return 300
        case .volcano:  return 400
        case .marathon: return 500
        case .double:   return 700
        case .triple:   return 1000
        }
    }
    
    /// Number of full completions of the previous tier required
    var completionsRequired: Int {
        switch self {
        case .spark:    return 0    // Just hit level 50
        case .flame:    return 3    // 3 full Sparks
        case .blaze:    return 3    // 3 full Flames
        case .inferno:  return 3    // 3 full Blazes
        case .furnace:  return 2    // 2 full Infernos
        case .eruption: return 2    // 2 full Furnaces
        case .volcano:  return 2    // 2 full Eruptions
        case .marathon: return 2    // 2 full Volcanos
        case .double:   return 1    // 1 full Marathon
        case .triple:   return 1    // 1 full Double
        }
    }
    
    /// Previous tier that must be completed
    var previousTier: StreamDurationTier? {
        switch self {
        case .spark:    return nil
        case .flame:    return .spark
        case .blaze:    return .flame
        case .inferno:  return .blaze
        case .furnace:  return .inferno
        case .eruption: return .furnace
        case .volcano:  return .eruption
        case .marathon: return .volcano
        case .double:   return .marathon
        case .triple:   return .double
        }
    }
    
    var nextTier: StreamDurationTier? {
        let all = StreamDurationTier.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
    
    // MARK: - Viewer XP Rewards
    
    var baseXP: Int {
        switch self {
        case .spark:    return 50
        case .flame:    return 100
        case .blaze:    return 200
        case .inferno:  return 400
        case .furnace:  return 600
        case .eruption: return 800
        case .volcano:  return 1000
        case .marathon: return 1500
        case .double:   return 3000
        case .triple:   return 5000
        }
    }
    
    var fullStayBonusXP: Int {
        switch self {
        case .spark:    return 25
        case .flame:    return 50
        case .blaze:    return 100
        case .inferno:  return 250
        case .furnace:  return 400
        case .eruption: return 600
        case .volcano:  return 800
        case .marathon: return 1200
        case .double:   return 2500
        case .triple:   return 4000
        }
    }
    
    /// Permanent clout bonus for viewers who stay for Double/Triple
    var viewerCloutBonus: Int {
        switch self {
        case .double:   return 500
        case .triple:   return 2000
        default:        return 0
        }
    }
}

// MARK: - Stream Completion Record

/// Firestore: users/{creatorID}/streamCompletions/{completionID}
/// Tracks completed streams for tier unlock gating
struct StreamCompletionRecord: Codable, Identifiable {
    let id: String
    let creatorID: String
    let streamID: String
    let tier: StreamDurationTier
    let durationSeconds: Int
    let isFullCompletion: Bool          // Streamed full tier duration
    let peakViewerCount: Int
    let totalCoinsEarned: Int
    let completedAt: Date
    let countsTowardGate: Bool          // False if daily cap exceeded
    
    init(stream: LiveStream, countsTowardGate: Bool = true) {
        self.id = UUID().uuidString
        self.creatorID = stream.creatorID
        self.streamID = stream.id
        self.tier = stream.durationTier
        self.durationSeconds = stream.elapsedSeconds
        self.isFullCompletion = stream.isFullCompletion
        self.peakViewerCount = stream.peakViewerCount
        self.totalCoinsEarned = stream.totalCoinsSpent
        self.completedAt = Date()
        self.countsTowardGate = countsTowardGate
    }
}

// MARK: - Daily Stream Limits

/// Controls stream frequency to prevent XP farming.
/// Rules:
///   - 3 full completions/day count toward tier unlocks
///   - 1-hour cooldown after a full completion
///   - Skip cooldown if last stream was under 5 minutes (crash recovery)
///   - 25% XP for everyone on stream 4+ per day
///   - No completion credit on stream 4+ per day
struct StreamDailyLimits {
    static let maxCompletionsPerDay = 3
    static let cooldownAfterCompletion: TimeInterval = 3600  // 1 hour
    static let crashRecoveryThreshold = 300                   // 5 min — skip cooldown
    static let reducedXPMultiplier: Double = 0.25             // 25% XP past cap
    
    /// Check how many full completions creator has today
    static func todaysCompletionCount(from completions: [StreamCompletionRecord]) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return completions.filter {
            $0.isFullCompletion && $0.completedAt >= startOfDay
        }.count
    }
    
    /// Check if creator is past the daily cap
    static func isPastDailyCap(from completions: [StreamCompletionRecord]) -> Bool {
        todaysCompletionCount(from: completions) >= maxCompletionsPerDay
    }
    
    /// Get cooldown remaining in seconds. Returns 0 if no cooldown.
    static func cooldownRemaining(from completions: [StreamCompletionRecord]) -> TimeInterval {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        // Find most recent completion today
        guard let lastCompletion = completions.first(where: {
            $0.completedAt >= startOfDay
        }) else {
            return 0
        }
        
        // Skip cooldown if last stream was under 5 min (crash/false start)
        if lastCompletion.durationSeconds < crashRecoveryThreshold {
            return 0
        }
        
        // Skip cooldown if it wasn't a full completion
        if !lastCompletion.isFullCompletion {
            return 0
        }
        
        let elapsed = Date().timeIntervalSince(lastCompletion.completedAt)
        let remaining = cooldownAfterCompletion - elapsed
        return max(0, remaining)
    }
    
    /// XP multiplier for this stream. 1.0 normal, 0.25 past cap.
    static func xpMultiplier(from completions: [StreamCompletionRecord]) -> Double {
        isPastDailyCap(from: completions) ? reducedXPMultiplier : 1.0
    }
}

struct DailyStreamStatus {
    let completionsToday: Int
    let maxCompletionsPerDay: Int
    let cooldownRemainingSeconds: Int
    let isPastDailyCap: Bool
    let xpMultiplier: Double
    
    var completionsRemaining: Int { max(0, maxCompletionsPerDay - completionsToday) }
    var isOnCooldown: Bool { cooldownRemainingSeconds > 0 }
    var cooldownFormatted: String {
        let min = cooldownRemainingSeconds / 60
        return "\(min) min"
    }
}

// MARK: - Stream Duration Gate Check

/// Pure logic result — no Firestore reads needed if completions are cached
struct StreamDurationGateResult {
    let tier: StreamDurationTier
    let isUnlocked: Bool
    let levelMet: Bool
    let completionsMet: Bool
    let currentCompletions: Int
    let requiredCompletions: Int
    let currentLevel: Int
    let requiredLevel: Int
    
    var levelsNeeded: Int { max(0, requiredLevel - currentLevel) }
    var completionsNeeded: Int { max(0, requiredCompletions - currentCompletions) }
}

// MARK: - Video Comment (Queue System)

/// Firestore: communities/{creatorID}/streams/{streamID}/videoComments/{commentID}
struct VideoComment: Codable, Identifiable, Hashable {
    static func == (lhs: VideoComment, rhs: VideoComment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let streamID: String
    let communityID: String
    let authorID: String
    let authorUsername: String
    let authorDisplayName: String
    let authorLevel: Int
    var videoURL: String                // Storage URL of uploaded clip
    var thumbnailURL: String?
    var durationSeconds: Int            // Max based on level gate
    var status: VideoCommentStatus
    var isPriority: Bool                // Paid to skip queue
    var priorityCoinsCost: Int          // How many coins they paid
    var caption: String                 // Short text description
    let submittedAt: Date
    var reviewedAt: Date?
    var displayedAt: Date?
    
    init(
        streamID: String,
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        videoURL: String,
        durationSeconds: Int,
        caption: String = "",
        isPriority: Bool = false,
        priorityCoinsCost: Int = 0
    ) {
        self.id = UUID().uuidString
        self.streamID = streamID
        self.communityID = communityID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorLevel = authorLevel
        self.videoURL = videoURL
        self.thumbnailURL = nil
        self.durationSeconds = durationSeconds
        self.status = .pending
        self.isPriority = isPriority
        self.priorityCoinsCost = priorityCoinsCost
        self.caption = caption
        self.submittedAt = Date()
        self.reviewedAt = nil
        self.displayedAt = nil
    }
    
    /// Max clip duration based on community level
    static func maxClipSeconds(forLevel level: Int) -> Int {
        if level >= 30 { return 30 }
        if level >= 20 { return 15 }
        return 10   // Level 20 minimum to submit
    }
    
    /// Minimum community level to submit video comments
    static let minimumLevel: Int = 20
}

enum VideoCommentStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"          // Creator approved, waiting to display
    case displayed = "displayed"        // Shown on stream as PiP
    case rejected = "rejected"
    case expired = "expired"            // Stream ended before review
}

// MARK: - Video Comment XP Rewards

struct VideoCommentXPReward {
    /// XP for submitting a video comment
    static let submitted: Int = 25
    
    /// XP for getting accepted and displayed
    static let accepted: Int = 150
    
    /// XP for getting accepted during Marathon or higher
    static let acceptedMarathonPlus: Int = 300
    
    /// Check if stream tier qualifies for Marathon+ bonus
    static func xpForAccepted(tier: StreamDurationTier) -> Int {
        let marathonIndex = StreamDurationTier.allCases.firstIndex(of: .marathon) ?? 7
        let tierIndex = StreamDurationTier.allCases.firstIndex(of: tier) ?? 0
        return tierIndex >= marathonIndex ? acceptedMarathonPlus : accepted
    }
}

// MARK: - Stream Hype Events (Coin Spending During Live)

/// Firestore: communities/{creatorID}/streams/{streamID}/hypeEvents/{eventID}
/// BATCHING: Buffer locally, flush every 30 seconds
struct StreamHypeEvent: Codable, Identifiable, Equatable {
    let id: String
    let streamID: String
    let communityID: String
    let senderID: String
    let senderUsername: String
    let senderLevel: Int
    let hypeType: StreamHypeType
    let coinCost: Int
    let creatorRevenue: Int             // After platform cut
    let xpMultiplier: Int               // Viewer XP boost
    let multiplierDurationSeconds: Int
    let sentAt: Date
    
    init(
        streamID: String,
        communityID: String,
        senderID: String,
        senderUsername: String,
        senderLevel: Int,
        hypeType: StreamHypeType
    ) {
        self.id = UUID().uuidString
        self.streamID = streamID
        self.communityID = communityID
        self.senderID = senderID
        self.senderUsername = senderUsername
        self.senderLevel = senderLevel
        self.hypeType = hypeType
        self.coinCost = hypeType.coinCost
        self.creatorRevenue = hypeType.creatorRevenue
        self.xpMultiplier = hypeType.xpMultiplier
        self.multiplierDurationSeconds = hypeType.multiplierDurationSeconds
        self.sentAt = Date()
    }
}

enum StreamHypeType: String, Codable, CaseIterable {
    case superHype = "superHype"
    case megaHype = "megaHype"
    case ultraHype = "ultraHype"
    case giftSub = "giftSub"
    case spotlight = "spotlight"
    case boostStream = "boostStream"
    
    var displayName: String {
        switch self {
        case .superHype:    return "Super Hype"
        case .megaHype:     return "Mega Hype"
        case .ultraHype:    return "Ultra Hype"
        case .giftSub:      return "Gift Sub"
        case .spotlight:    return "Spotlight"
        case .boostStream:  return "Boost Stream"
        }
    }
    
    var emoji: String {
        switch self {
        case .superHype:    return "🔥"
        case .megaHype:     return "⚡"
        case .ultraHype:    return "💎"
        case .giftSub:      return "🎁"
        case .spotlight:    return "📌"
        case .boostStream:  return "🚀"
        }
    }
    
    var coinCost: Int {
        switch self {
        case .superHype:    return 5
        case .megaHype:     return 15
        case .ultraHype:    return 50
        case .giftSub:      return 25
        case .spotlight:    return 10
        case .boostStream:  return 100
        }
    }
    
    /// Creator gets this percentage of coin value
    var creatorRevenuePercent: Double {
        switch self {
        case .superHype:    return 0.70
        case .megaHype:     return 0.70
        case .ultraHype:    return 0.75
        case .giftSub:      return 0.70
        case .spotlight:    return 0.70
        case .boostStream:  return 0.50  // Platform keeps more for discovery push
        }
    }
    
    var creatorRevenue: Int {
        Int(Double(coinCost) * creatorRevenuePercent)
    }
    
    /// XP multiplier applied to viewer for duration
    var xpMultiplier: Int {
        switch self {
        case .superHype:    return 2
        case .megaHype:     return 5
        case .ultraHype:    return 10
        case .giftSub:      return 1    // No multiplier, gives bonus XP instead
        case .spotlight:    return 1    // No multiplier, pins message
        case .boostStream:  return 1    // No viewer multiplier, pushes stream
        }
    }
    
    var multiplierDurationSeconds: Int {
        switch self {
        case .superHype:    return 600      // 10 min
        case .megaHype:     return 600      // 10 min
        case .ultraHype:    return 900      // 15 min
        default:            return 0
        }
    }
    
    /// XP viewer earns per coin spent (on top of multiplier)
    static let xpPerCoinSpent: Int = 20
    
    /// Visual effect on stream
    var alertType: StreamAlertType {
        switch self {
        case .superHype:    return .standard
        case .megaHype:     return .animated
        case .ultraHype:    return .fullScreen
        case .giftSub:      return .animated
        case .spotlight:    return .pinned
        case .boostStream:  return .fullScreen
        }
    }
}

enum StreamAlertType: String, Codable {
    case standard = "standard"          // Small alert
    case animated = "animated"          // Animated alert + sound
    case fullScreen = "fullScreen"      // Full screen takeover
    case pinned = "pinned"              // Pinned message for 5 min
}

// MARK: - Stream Attendance (Viewer Tracking)

/// Firestore: communities/{creatorID}/streams/{streamID}/attendance/{userID}
/// BATCHING: Write every 5 min heartbeat, NOT per interaction
struct StreamAttendance: Codable, Identifiable {
    var id: String                      // Same as userID
    let userID: String
    let streamID: String
    let communityID: String
    let userLevel: Int
    var joinedAt: Date
    var lastHeartbeatAt: Date
    var lastInteractionAt: Date         // For anti-idle check
    var totalWatchSeconds: Int
    var interactionCount: Int           // Taps, chats, reactions
    var isCurrentlyWatching: Bool
    var isIdleWarned: Bool              // Hit 15-min idle threshold
    var earnedBaseXP: Bool              // Showed up
    var earnedFullStayXP: Bool          // Stayed for full duration
    var activeXPMultiplier: Int         // From hype purchases
    var multiplierExpiresAt: Date?
    
    init(
        userID: String,
        streamID: String,
        communityID: String,
        userLevel: Int
    ) {
        self.id = userID
        self.userID = userID
        self.streamID = streamID
        self.communityID = communityID
        self.userLevel = userLevel
        self.joinedAt = Date()
        self.lastHeartbeatAt = Date()
        self.lastInteractionAt = Date()
        self.totalWatchSeconds = 0
        self.interactionCount = 0
        self.isCurrentlyWatching = true
        self.isIdleWarned = false
        self.earnedBaseXP = false
        self.earnedFullStayXP = false
        self.activeXPMultiplier = 1
        self.multiplierExpiresAt = nil
    }
    
    /// Check if viewer has been idle for 15+ minutes
    var isIdle: Bool {
        Date().timeIntervalSince(lastInteractionAt) > 900
    }
    
    /// Check if XP multiplier is still active
    var hasActiveMultiplier: Bool {
        guard let expires = multiplierExpiresAt else { return false }
        return Date() < expires && activeXPMultiplier > 1
    }
}

// MARK: - Stream Collective Goals

/// Firestore: communities/{creatorID}/streams/{streamID} (fields on stream doc)
/// SINGLE real-time listener shared by all viewers
struct StreamCollectiveGoal: Codable, Identifiable {
    let id: String                      // "goal_500", "goal_2000", etc.
    let threshold: Int                  // Coin threshold
    let effect: CollectiveGoalEffect
    let displayName: String
    var isReached: Bool
    var reachedAt: Date?
    
    static let allGoals: [StreamCollectiveGoal] = [
        StreamCollectiveGoal(
            id: "goal_500", threshold: 500,
            effect: .hotTag,
            displayName: "🔥 Hot Stream Tag"
        ),
        StreamCollectiveGoal(
            id: "goal_2000", threshold: 2000,
            effect: .streamExtension,
            displayName: "⏰ +30 Min Extension"
        ),
        StreamCollectiveGoal(
            id: "goal_5000", threshold: 5000,
            effect: .bonusXP,
            displayName: "⭐ All Viewers +200 XP"
        ),
        StreamCollectiveGoal(
            id: "goal_10000", threshold: 10000,
            effect: .legendaryBadge,
            displayName: "🏆 Legendary Stream Badge"
        ),
        StreamCollectiveGoal(
            id: "goal_25000", threshold: 25000,
            effect: .permanentHighlight,
            displayName: "💎 Permanent Community Highlight"
        )
    ]
    
    init(id: String, threshold: Int, effect: CollectiveGoalEffect, displayName: String) {
        self.id = id
        self.threshold = threshold
        self.effect = effect
        self.displayName = displayName
        self.isReached = false
        self.reachedAt = nil
    }
    
    /// Get the next unreached goal for a given coin total
    static func nextGoal(totalCoins: Int) -> StreamCollectiveGoal? {
        allGoals.first { totalCoins < $0.threshold }
    }
    
    /// Get progress toward next goal (0.0 - 1.0)
    static func progress(totalCoins: Int) -> Double {
        guard let next = nextGoal(totalCoins: totalCoins) else { return 1.0 }
        let prev = allGoals.last { $0.threshold <= totalCoins }
        let base = prev?.threshold ?? 0
        let range = next.threshold - base
        guard range > 0 else { return 0 }
        return Double(totalCoins - base) / Double(range)
    }
}

enum CollectiveGoalEffect: String, Codable {
    case hotTag = "hotTag"                      // Stream gets "Hot" in community
    case streamExtension = "streamExtension"    // +30 min beyond tier limit
    case bonusXP = "bonusXP"                    // All viewers +200 XP
    case legendaryBadge = "legendaryBadge"      // All attendees get badge
    case permanentHighlight = "permanentHighlight" // Archived as highlight
}

// MARK: - Stream Badges (Viewer Attendance Rewards)

/// Static definitions — cache at launch
struct StreamBadgeDefinition: Identifiable {
    let id: String
    let tier: StreamDurationTier
    let name: String
    let emoji: String
    let description: String
    let requiredFullAttendances: Int     // Full stays at this tier
    let isTimestamped: Bool             // Unique per stream (FOMO badges)
    
    /// All stream attendance badges
    static let allBadges: [StreamBadgeDefinition] = [
        // Spark badges
        StreamBadgeDefinition(
            id: "spark_witness", tier: .spark,
            name: "Spark Witness", emoji: "✨",
            description: "Attended 5 full Spark streams",
            requiredFullAttendances: 5, isTimestamped: false
        ),
        // Flame badges
        StreamBadgeDefinition(
            id: "flame_keeper", tier: .flame,
            name: "Flame Keeper", emoji: "🔥",
            description: "Attended 3 full Flame streams",
            requiredFullAttendances: 3, isTimestamped: false
        ),
        // Blaze badges
        StreamBadgeDefinition(
            id: "blaze_veteran", tier: .blaze,
            name: "Blaze Veteran", emoji: "💥",
            description: "Attended 3 full Blaze streams",
            requiredFullAttendances: 3, isTimestamped: false
        ),
        // Inferno badges
        StreamBadgeDefinition(
            id: "inferno_survivor", tier: .inferno,
            name: "Inferno Survivor", emoji: "🌋",
            description: "Survived a full 4hr Inferno",
            requiredFullAttendances: 1, isTimestamped: false
        ),
        // Furnace badges
        StreamBadgeDefinition(
            id: "furnace_forged", tier: .furnace,
            name: "Furnace Forged", emoji: "⚒️",
            description: "Endured a full 6hr Furnace",
            requiredFullAttendances: 1, isTimestamped: false
        ),
        // Eruption badges
        StreamBadgeDefinition(
            id: "eruption_core", tier: .eruption,
            name: "Eruption Core", emoji: "🌊",
            description: "Witnessed a full 8hr Eruption",
            requiredFullAttendances: 1, isTimestamped: false
        ),
        // Volcano badges
        StreamBadgeDefinition(
            id: "volcano_heart", tier: .volcano,
            name: "Volcano Heart", emoji: "🗻",
            description: "Survived a full 10hr Volcano",
            requiredFullAttendances: 1, isTimestamped: false
        ),
        // Marathon — timestamped FOMO badge
        StreamBadgeDefinition(
            id: "marathon_witness", tier: .marathon,
            name: "I Was There", emoji: "🏃",
            description: "Full 12hr Marathon — timestamped, unique forever",
            requiredFullAttendances: 1, isTimestamped: true
        ),
        // Double — legendary
        StreamBadgeDefinition(
            id: "double_down", tier: .double,
            name: "Double Down", emoji: "⚡",
            description: "Survived a full 24hr Double",
            requiredFullAttendances: 1, isTimestamped: true
        ),
        // Triple — mythic
        StreamBadgeDefinition(
            id: "triple_crown", tier: .triple,
            name: "Triple Crown", emoji: "👑",
            description: "The rarest badge — full 36hr Triple",
            requiredFullAttendances: 1, isTimestamped: true
        ),
    ]
    
    /// Find badge for a given tier
    static func badge(for tier: StreamDurationTier) -> StreamBadgeDefinition? {
        allBadges.first { $0.tier == tier }
    }
}

// MARK: - Stream Badge Award (Per Viewer)

/// Firestore: communities/{creatorID}/members/{userID} — streamBadgeIDs array
/// Or separate subcollection if timestamped badges need metadata
struct StreamBadgeAward: Codable, Identifiable {
    let id: String
    let badgeID: String
    let userID: String
    let communityID: String
    let streamID: String
    let tier: StreamDurationTier
    let isTimestamped: Bool
    let streamDate: Date                // For "I Was There" display
    let awardedAt: Date
    
    init(badge: StreamBadgeDefinition, userID: String, communityID: String, streamID: String) {
        self.id = UUID().uuidString
        self.badgeID = badge.id
        self.userID = userID
        self.communityID = communityID
        self.streamID = streamID
        self.tier = badge.tier
        self.isTimestamped = badge.isTimestamped
        self.streamDate = Date()
        self.awardedAt = Date()
    }
}

// MARK: - Post-Stream Recap

/// Computed locally from stream data — no extra Firestore doc needed
struct StreamRecap {
    let stream: LiveStream
    let tier: StreamDurationTier
    let durationFormatted: String
    let viewerXPEarned: Int
    let fullStayBonus: Int
    let coinsSpent: Int
    let xpFromCoins: Int
    let badgesEarned: [StreamBadgeDefinition]
    let cloutBonus: Int
    let goalsReached: [StreamCollectiveGoal]
    let wasFullCompletion: Bool
    
    var totalXP: Int {
        viewerXPEarned + fullStayBonus + xpFromCoins
    }
}

// MARK: - Active XP Multiplier State (Local Only)

/// Tracked locally per viewer during stream — never written to Firestore per-tick
/// CACHING: 100% local, zero Firestore cost during stream
struct ActiveXPMultiplier {
    var multiplier: Int = 1
    var expiresAt: Date?
    var source: StreamHypeType?
    
    var isActive: Bool {
        guard let expires = expiresAt else { return false }
        return Date() < expires && multiplier > 1
    }
    
    var remainingSeconds: Int {
        guard let expires = expiresAt else { return 0 }
        return max(0, Int(expires.timeIntervalSinceNow))
    }
    
    mutating func apply(hypeType: StreamHypeType) {
        // Higher multiplier always wins, resets timer
        if hypeType.xpMultiplier > multiplier || !isActive {
            multiplier = hypeType.xpMultiplier
            expiresAt = Date().addingTimeInterval(TimeInterval(hypeType.multiplierDurationSeconds))
            source = hypeType
        } else if hypeType.xpMultiplier == multiplier {
            // Same multiplier extends duration
            expiresAt = Date().addingTimeInterval(TimeInterval(hypeType.multiplierDurationSeconds))
        }
    }
    
    mutating func reset() {
        multiplier = 1
        expiresAt = nil
        source = nil
    }
}

// MARK: - Pending Hype Event Buffer (Local Only)

/// Buffers hype events locally, flushes to Firestore every 30 sec
/// BATCHING: 20 hypes in 30 sec = 1 write instead of 20
struct PendingHypeBuffer {
    var events: [StreamHypeEvent] = []
    var totalCoins: Int = 0
    var lastFlushAt: Date = Date()
    
    mutating func add(_ event: StreamHypeEvent) {
        events.append(event)
        totalCoins += event.coinCost
    }
    
    mutating func flush() -> [StreamHypeEvent] {
        let flushed = events
        events = []
        totalCoins = 0
        lastFlushAt = Date()
        return flushed
    }
    
    var shouldFlush: Bool {
        Date().timeIntervalSince(lastFlushAt) >= 30 || events.count >= 20
    }
}

// MARK: - Pending Heartbeat Buffer (Local Only)

/// Tracks viewer activity locally, syncs to Firestore every 5 min
/// BATCHING: Avoids per-interaction writes
struct PendingHeartbeatBuffer {
    var interactionCount: Int = 0
    var watchSeconds: Int = 0
    var lastSyncAt: Date = Date()
    var lastInteractionAt: Date = Date()
    
    mutating func recordInteraction() {
        interactionCount += 1
        lastInteractionAt = Date()
    }
    
    mutating func addWatchTime(_ seconds: Int) {
        watchSeconds += seconds
    }
    
    mutating func flush() -> (interactions: Int, watchSeconds: Int) {
        let result = (interactionCount, watchSeconds)
        interactionCount = 0
        watchSeconds = 0
        lastSyncAt = Date()
        return result
    }
    
    var shouldSync: Bool {
        Date().timeIntervalSince(lastSyncAt) >= 300  // 5 min
    }
}
