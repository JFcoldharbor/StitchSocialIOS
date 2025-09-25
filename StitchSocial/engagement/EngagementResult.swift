//
//  EngagementManager.swift
//  StitchSocial
//
//  Layer 6: Coordination - Complete Engagement Management System
//  Dependencies: EngagementCalculator (Layer 5), VideoService (Layer 4), UserService (Layer 4)
//  Purpose: Single source of truth for all engagement processing including hype AND cool
//

import Foundation
import SwiftUI
import FirebaseAuth

/// Result of engagement processing
struct EngagementResult {
    let success: Bool
    let cloutAwarded: Int
    let newHypeCount: Int
    let newCoolCount: Int
    let isFounderFirstTap: Bool
    let visualHypeIncrement: Int // For UI (20 for founder first tap, 1 for others)
    let visualCoolIncrement: Int // For UI (always 1)
    let animationType: EngagementAnimationType
    let message: String
}

/// Animation types for different engagement results
enum EngagementAnimationType {
    case founderExplosion   // First founder tap = massive hype explosion
    case standardHype       // Normal hype animation
    case standardCool       // Normal cool animation
    case coolProgression    // Cool tap progression feedback
    case trollWarning       // Warning animation for potential trolling
    case tierMilestone      // Special tier-based effects
    case none
}

/// Cool spam tracking for troll protection
struct CoolSpamTracker {
    var recentCools: [Date] = []
    var totalCoolsToday: Int = 0
    var consecutiveCoolVideos: Int = 0
    var lastCoolVideoID: String?
    
    /// Check if user is exhibiting spam behavior
    var shouldTriggerWarning: Bool {
        return recentCools.count >= 5 || totalCoolsToday >= 20 || consecutiveCoolVideos >= 3
    }
    
    /// Get recent cools in the last hour
    var coolsInLastHour: Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return recentCools.filter { $0 > oneHourAgo }.count
    }
    
    /// Clean up old tracking data
    mutating func cleanup() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        recentCools.removeAll { $0 < oneHourAgo }
    }
}

/// Troll warning system
struct TrollWarning {
    let level: TrollWarningLevel
    let message: String
    let timestamp: Date
    let expiresAt: Date?
    
    /// Check if warning is still active
    var isActive: Bool {
        guard let expiresAt = expiresAt else { return true }
        return Date() < expiresAt
    }
}

/// Warning levels for progressive troll protection
enum TrollWarningLevel: String, CaseIterable {
    case caution = "caution"
    case warning = "warning"
    case severe = "severe"
    case restricted = "restricted"
    
    var displayMessage: String {
        switch self {
        case .caution:
            return "Please consider more positive interactions"
        case .warning:
            return "Excessive cool usage detected"
        case .severe:
            return "Continued negative behavior may result in restrictions"
        case .restricted:
            return "Cool interactions temporarily limited due to spam"
        }
    }
    
    var coolsAllowed: Bool {
        return self != .restricted
    }
}

/// Complete engagement management system
@MainActor
class EngagementManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let userService: UserService
    private let notificationService: NotificationService // NEW: Notification integration
    public let engagementCoordinator: EngagementCoordinator // Make public for button access
    
    // MARK: - Founder Tracking State
    
    @Published var founderFirstTaps: [String: Set<String>] = [:] // videoID -> Set of founderIDs who used first tap
    
    // MARK: - Cool Progression & Troll Protection State
    
    @Published var coolTapProgress: [String: [String: Int]] = [:] // videoID -> userID -> tap count
    @Published var userCoolSpamTracking: [String: CoolSpamTracker] = [:] // userID -> spam tracking
    @Published var trollWarnings: [String: TrollWarning] = [:] // userID -> warning state
    
    // MARK: - Engagement Processing State
    
    @Published var isProcessing: [String: Bool] = [:] // videoID -> processing state
    @Published var lastEngagementTime: [String: Date] = [:] // videoID -> last engagement timestamp
    
    // MARK: - Configuration
    
    private let engagementCooldown: TimeInterval = 1.0 // Prevent spam tapping
    private let maxEngagementsPerMinute = 30 // Anti-spam protection
    
    // MARK: - Initialization
    
    init(
        videoService: VideoService,
        userService: UserService,
        engagementCoordinator: EngagementCoordinator,
        notificationService: NotificationService? = nil // NEW: Optional notification dependency
    ) {
        self.videoService = videoService
        self.userService = userService
        self.engagementCoordinator = engagementCoordinator
        self.notificationService = notificationService ?? NotificationService() // NEW: Store notification service with fallback
        
        print("🎯 ENGAGEMENT MANAGER: Initialized - Ready for hype AND cool processing with notifications")
    }
    
    // MARK: - FIXED: Temperature String to VideoTemperature Conversion Helper
    
    /// Convert temperature string to VideoTemperature enum with fallback
    private func stringToVideoTemperature(_ temperatureString: String) -> VideoTemperature {
        switch temperatureString.lowercased() {
        case "hot": return .hot
        case "warm": return .warm
        case "cool": return .cool
        case "cold": return .cold
        default: return .warm
        }
    }
    
    // MARK: - Main Engagement Processing
    
    /// Main engagement processing function - handles HYPE and COOL interactions
    func processEngagement(
        videoID: String,
        engagementType: InteractionType,
        userID: String,
        userTier: UserTier
    ) async throws -> EngagementResult {
        
        print("🎯 ENGAGEMENT MANAGER: Processing \(engagementType.rawValue) for video \(videoID)")
        
        // Rate limiting check
        if let lastTime = lastEngagementTime[videoID],
           Date().timeIntervalSince(lastTime) < engagementCooldown {
            throw StitchError.validationError("Please wait before engaging again")
        }
        
        // Set processing state
        isProcessing[videoID] = true
        defer { isProcessing[videoID] = false }
        
        // Update last engagement time
        lastEngagementTime[videoID] = Date()
        
        // Get current video state from VideoService
        let currentVideo = try await videoService.getVideo(id: videoID)
        
        // Process based on engagement type
        let result: EngagementResult
        switch engagementType {
        case .hype:
            result = try await processHypeEngagement(
                videoID: videoID,
                userID: userID,
                userTier: userTier,
                currentHypeCount: currentVideo.hypeCount,
                currentCoolCount: currentVideo.coolCount
            )
            
        case .cool:
            result = try await processCoolEngagement(
                videoID: videoID,
                userID: userID,
                userTier: userTier,
                currentHypeCount: currentVideo.hypeCount,
                currentCoolCount: currentVideo.coolCount
            )
            
        default:
            throw StitchError.validationError("Unsupported engagement type: \(engagementType.rawValue)")
        }
        
        // NEW: Send notifications after successful engagement
        if result.success {
            await sendEngagementNotification(
                videoID: videoID,
                engagementType: engagementType,
                userID: userID,
                result: result
            )
        }
        
        return result
    }
    
    // MARK: - Hype Processing
    
    /// Process hype engagement with founder and regular user logic
    private func processHypeEngagement(
        videoID: String,
        userID: String,
        userTier: UserTier,
        currentHypeCount: Int,
        currentCoolCount: Int
    ) async throws -> EngagementResult {
        
        // Check if user is founder or co-founder
        if userTier == .founder || userTier == .coFounder {
            return try await processFounderHype(
                videoID: videoID,
                userID: userID,
                currentHypeCount: currentHypeCount,
                currentCoolCount: currentCoolCount
            )
        }
        
        // Handle regular user progressive tapping
        return try await processRegularHype(
            videoID: videoID,
            userID: userID,
            userTier: userTier,
            currentHypeCount: currentHypeCount,
            currentCoolCount: currentCoolCount
        )
    }
    
    /// Process founder hype with first-tap mechanics
    private func processFounderHype(
        videoID: String,
        userID: String,
        currentHypeCount: Int,
        currentCoolCount: Int
    ) async throws -> EngagementResult {
        
        let isFirstTap = !hasFounderUsedFirstTap(videoID: videoID, founderID: userID)
        
        if isFirstTap {
            // FOUNDER FIRST TAP: 20 hypes + 200 clout
            markFounderFirstTap(videoID: videoID, founderID: userID)
            
            let newHypeCount = currentHypeCount + 20
            let cloutAwarded = 200
            
            // Update database with 20 hypes
            try await updateVideoEngagement(
                videoID: videoID,
                newHypeCount: newHypeCount,
                newCoolCount: currentCoolCount,
                cloutAwarded: cloutAwarded
            )
            
            print("👑 FOUNDER FIRST TAP: +20 hypes, +200 clout for video \(videoID)")
            
            return EngagementResult(
                success: true,
                cloutAwarded: cloutAwarded,
                newHypeCount: newHypeCount,
                newCoolCount: currentCoolCount,
                isFounderFirstTap: true,
                visualHypeIncrement: 20,
                visualCoolIncrement: 0,
                animationType: .founderExplosion,
                message: "Founder boost: +20 hypes!"
            )
            
        } else {
            // FOUNDER FOLLOW-UP TAP: 1 hype + 20 clout
            let newHypeCount = currentHypeCount + 1
            let cloutAwarded = 20
            
            try await updateVideoEngagement(
                videoID: videoID,
                newHypeCount: newHypeCount,
                newCoolCount: currentCoolCount,
                cloutAwarded: cloutAwarded
            )
            
            print("👑 FOUNDER FOLLOW-UP: +1 hype, +20 clout for video \(videoID)")
            
            return EngagementResult(
                success: true,
                cloutAwarded: cloutAwarded,
                newHypeCount: newHypeCount,
                newCoolCount: currentCoolCount,
                isFounderFirstTap: false,
                visualHypeIncrement: 1,
                visualCoolIncrement: 0,
                animationType: .standardHype,
                message: "Hype added!"
            )
        }
    }
    
    /// Process regular user hype with progressive tapping and clout thresholds
    private func processRegularHype(
        videoID: String,
        userID: String,
        userTier: UserTier,
        currentHypeCount: Int,
        currentCoolCount: Int
    ) async throws -> EngagementResult {
        
        // Progressive tapping complete - award hype
        let newHypeCount = currentHypeCount + 1
        
        // Calculate clout based on 5-hype threshold
        let cloutAwarded = EngagementCalculator.calculateRegularClout(
            userTier: userTier,
            currentHypeCount: newHypeCount
        )
        
        try await updateVideoEngagement(
            videoID: videoID,
            newHypeCount: newHypeCount,
            newCoolCount: currentCoolCount,
            cloutAwarded: cloutAwarded
        )
        
        let message = cloutAwarded > 0 ?
            "Hype +\(cloutAwarded) clout!" :
            "Hype added! (\(5 - (newHypeCount % 5)) to next clout reward)"
        
        print("🔥 REGULAR HYPE: +1 hype, +\(cloutAwarded) clout for video \(videoID)")
        
        return EngagementResult(
            success: true,
            cloutAwarded: cloutAwarded,
            newHypeCount: newHypeCount,
            newCoolCount: currentCoolCount,
            isFounderFirstTap: false,
            visualHypeIncrement: 1,
            visualCoolIncrement: 0,
            animationType: .standardHype,
            message: message
        )
    }
    
    // MARK: - Cool Processing
    
    /// Process cool engagement with troll protection
    private func processCoolEngagement(
        videoID: String,
        userID: String,
        userTier: UserTier,
        currentHypeCount: Int,
        currentCoolCount: Int
    ) async throws -> EngagementResult {
        
        // Update cool spam tracking
        updateCoolSpamTracking(userID: userID, videoID: videoID)
        
        // Check for troll behavior and apply protection
        try validateCoolEngagement(userID: userID, videoID: videoID)
        
        // Process cool engagement
        let newCoolCount = currentCoolCount + 1
        let cloutDeducted = -5 // Cools deduct 5 clout from creator
        
        try await updateVideoEngagement(
            videoID: videoID,
            newHypeCount: currentHypeCount,
            newCoolCount: newCoolCount,
            cloutAwarded: cloutDeducted
        )
        
        // Check for troll warning
        let warning = checkForTrollWarning(userID: userID)
        let animationType: EngagementAnimationType = warning != nil ? .trollWarning : .standardCool
        
        let message = warning?.message ?? "Cool added"
        
        print("❄️ COOL: +1 cool, -5 clout for video \(videoID)")
        
        return EngagementResult(
            success: true,
            cloutAwarded: cloutDeducted,
            newHypeCount: currentHypeCount,
            newCoolCount: newCoolCount,
            isFounderFirstTap: false,
            visualHypeIncrement: 0,
            visualCoolIncrement: 1,
            animationType: animationType,
            message: message
        )
    }
    
    // MARK: - NEW: Notification Integration
    
    /// Send engagement notification to video creator
    private func sendEngagementNotification(
        videoID: String,
        engagementType: InteractionType,
        userID: String,
        result: EngagementResult
    ) async {
        
        // Only send notifications for hype and cool (limited)
        switch engagementType {
        case .hype:
            await sendHypeNotification(videoID: videoID, userID: userID, hypeCount: result.visualHypeIncrement)
            
        case .cool:
            // Limit cool notifications to first 3 to avoid spam
            if result.newCoolCount <= 3 {
                await sendCoolNotification(videoID: videoID, userID: userID)
            }
            
        default:
            // No notifications for other engagement types yet
            break
        }
    }
    
    /// Send hype notification to video creator
    private func sendHypeNotification(videoID: String, userID: String, hypeCount: Int) async {
        do {
            if let video = try? await videoService.getVideo(id: videoID) {
                let senderUsername = await getCurrentUsername(userID: userID)
                
                try await notificationService.notifyHype(
                    videoID: videoID,
                    videoTitle: video.title,
                    recipientID: video.creatorID,
                    senderID: userID,
                    senderUsername: senderUsername
                )
                
                print("🔔 NOTIFICATION: Sent hype notification for video \(videoID)")
            }
        } catch {
            print("❌ NOTIFICATION ERROR: Failed to send hype notification - \(error)")
        }
    }
    
    /// Send cool notification to video creator (limited)
    private func sendCoolNotification(videoID: String, userID: String) async {
        do {
            if let video = try? await videoService.getVideo(id: videoID) {
                let senderUsername = await getCurrentUsername(userID: userID)
                
                try await notificationService.createNotification(
                    recipientID: video.creatorID,
                    senderID: userID,
                    type: StitchNotificationType.cool,
                    title: "❄️ Video cooled",
                    message: "\(senderUsername) cooled your video",
                    payload: [
                        "videoID": videoID,
                        "videoTitle": video.title,
                        "senderUsername": senderUsername
                    ]
                )
                
                print("🔔 NOTIFICATION: Sent cool notification for video \(videoID)")
            }
        } catch {
            print("❌ NOTIFICATION ERROR: Failed to send cool notification - \(error)")
        }
    }
    
    /// Get current username for notifications
    private func getCurrentUsername(userID: String) async -> String {
        // Try to get username from UserService
        if let user = try? await userService.getUser(id: userID) {
            return user.username
        }
        
        // Fallback to Auth display name
        if let currentUser = Auth.auth().currentUser {
            return currentUser.displayName ?? currentUser.email ?? "Someone"
        }
        
        return "Someone"
    }
    
    // MARK: - Cool Spam Protection
    
    /// Update cool spam tracking for user
    private func updateCoolSpamTracking(userID: String, videoID: String) {
        // Initialize tracking if needed
        if userCoolSpamTracking[userID] == nil {
            userCoolSpamTracking[userID] = CoolSpamTracker()
        }
        
        // Update tracking data
        userCoolSpamTracking[userID]?.recentCools.append(Date())
        userCoolSpamTracking[userID]?.totalCoolsToday += 1
        
        // Update consecutive video tracking
        if userCoolSpamTracking[userID]?.lastCoolVideoID != videoID {
            userCoolSpamTracking[userID]?.consecutiveCoolVideos = 1
            userCoolSpamTracking[userID]?.lastCoolVideoID = videoID
        } else {
            userCoolSpamTracking[userID]?.consecutiveCoolVideos += 1
        }
        
        // Cleanup old data
        userCoolSpamTracking[userID]?.cleanup()
    }
    
    /// Check for troll warning triggers
    private func checkForTrollWarning(userID: String) -> TrollWarning? {
        guard let tracker = userCoolSpamTracking[userID] else { return nil }
        
        if tracker.shouldTriggerWarning {
            let warningLevel = determineWarningLevel(tracker: tracker)
            let warning = TrollWarning(
                level: warningLevel,
                message: warningLevel.displayMessage,
                timestamp: Date(),
                expiresAt: warningLevel == .restricted ? Date().addingTimeInterval(3600) : nil // 1 hour restriction
            )
            
            trollWarnings[userID] = warning
            
            print("🚨 TROLL WARNING: \(warningLevel.rawValue) for user \(userID)")
            return warning
        }
        
        return nil
    }
    
    /// Determine appropriate warning level based on spam behavior
    private func determineWarningLevel(tracker: CoolSpamTracker) -> TrollWarningLevel {
        if tracker.coolsInLastHour >= 50 || tracker.consecutiveCoolVideos >= 10 {
            return .restricted
        } else if tracker.coolsInLastHour >= 30 || tracker.consecutiveCoolVideos >= 7 {
            return .severe
        } else if tracker.coolsInLastHour >= 20 || tracker.consecutiveCoolVideos >= 5 {
            return .warning
        } else {
            return .caution
        }
    }
    
    /// Validate cool engagement for troll protection
    private func validateCoolEngagement(userID: String, videoID: String) throws {
        // Check if user has active restrictions
        if let warning = trollWarnings[userID], warning.isActive && !warning.level.coolsAllowed {
            throw StitchError.validationError("Cool button temporarily restricted due to trolling behavior")
        }
        
        // Check for excessive cooling patterns
        if let tracker = userCoolSpamTracking[userID] {
            if tracker.coolsInLastHour >= 100 { // Hard limit
                throw StitchError.validationError("Too many cool interactions. Please try again later.")
            }
        }
    }
    
    // MARK: - Founder Tracking
    
    /// Check if founder has used first tap on this video
    private func hasFounderUsedFirstTap(videoID: String, founderID: String) -> Bool {
        return founderFirstTaps[videoID]?.contains(founderID) ?? false
    }
    
    /// Mark founder as having used first tap
    private func markFounderFirstTap(videoID: String, founderID: String) {
        if founderFirstTaps[videoID] == nil {
            founderFirstTaps[videoID] = Set<String>()
        }
        founderFirstTaps[videoID]?.insert(founderID)
        
        // Persist to database
        Task {
            try await persistFounderFirstTap(videoID: videoID, founderID: founderID)
        }
    }
    
    /// Persist founder first tap to database
    private func persistFounderFirstTap(videoID: String, founderID: String) async throws {
        // TODO: Implement database persistence for founder tracking
        // This should store in a dedicated collection or field to track founder first taps
        print("💾 PERSISTENCE: Founder \(founderID) first tap on video \(videoID)")
    }
    
    // MARK: - FIXED: Database Updates with VideoTemperature Conversion
    
    /// Update video engagement counts and award clout
    private func updateVideoEngagement(
        videoID: String,
        newHypeCount: Int,
        newCoolCount: Int,
        cloutAwarded: Int
    ) async throws {
        
        // Calculate temperature string
        let temperatureString = EngagementCalculator.calculateTemperature(
            hypeCount: newHypeCount,
            coolCount: newCoolCount
        )
        
        // FIXED: Convert string to VideoTemperature enum before passing to VideoService
        let videoTemperature = stringToVideoTemperature(temperatureString)
        
        // Update video engagement metrics
        try await videoService.updateVideoEngagement(
            videoID: videoID,
            hypeCount: newHypeCount,
            coolCount: newCoolCount,
            viewCount: 0, // Not updating views here
            temperature: videoTemperature.rawValue, // FIXED: Now passes VideoTemperature enum
            lastEngagementAt: Date()
        )
        
        // Award clout to video creator if positive
        if cloutAwarded > 0 {
            try await awardCloutToCreator(videoID: videoID, cloutAmount: cloutAwarded)
        } else if cloutAwarded < 0 {
            try await deductCloutFromCreator(videoID: videoID, cloutAmount: abs(cloutAwarded))
        }
    }
    
    /// Record other engagement types
    private func recordEngagement(
        videoID: String,
        userID: String,
        engagementType: InteractionType
    ) async throws {
        
        // Record interaction in VideoService
        try await videoService.recordUserInteraction(
            videoID: videoID,
            userID: userID,
            interactionType: engagementType
        )
        
        print("📝 RECORDED: \(engagementType.rawValue) interaction for video \(videoID)")
    }
    
    // MARK: - Clout Management
    
    /// Award clout to video creator
    private func awardCloutToCreator(videoID: String, cloutAmount: Int) async throws {
        // Get video creator from VideoService
        let video = try await videoService.getVideo(id: videoID)
        
        // Award clout through UserService
        try await userService.awardClout(userID: video.creatorID, amount: cloutAmount)
        
        print("💰 CLOUT AWARDED: +\(cloutAmount) to creator \(video.creatorID) for video \(videoID)")
    }
    
    /// Deduct clout from video creator
    private func deductCloutFromCreator(videoID: String, cloutAmount: Int) async throws {
        // Get video creator from VideoService
        let video = try await videoService.getVideo(id: videoID)
        
        // Deduct clout through UserService
        try await userService.deductClout(userID: video.creatorID, amount: cloutAmount)
        
        print("💸 CLOUT DEDUCTED: -\(cloutAmount) from creator \(video.creatorID) for video \(videoID)")
    }
    
    // MARK: - State Management
    
    /// Get current troll warning for user
    func getCurrentTrollWarning(userID: String) -> TrollWarning? {
        guard let warning = trollWarnings[userID], warning.isActive else { return nil }
        return warning
    }
    
    /// Reset engagement state (for testing or video deletion)
    func resetEngagementState(videoID: String) {
        founderFirstTaps[videoID] = nil
        coolTapProgress[videoID] = nil
        isProcessing[videoID] = nil
        lastEngagementTime[videoID] = nil
        
        print("🔥 RESET: Cleared engagement state for video \(videoID)")
    }
    
    /// Reset user troll tracking (admin function)
    func resetUserTrollTracking(userID: String) {
        userCoolSpamTracking[userID] = nil
        trollWarnings[userID] = nil
        
        print("🔥 ADMIN RESET: Cleared troll tracking for user \(userID)")
    }
    
    /// Load founder first tap data from database
    func loadFounderTracking(videoID: String) async {
        // TODO: Load founder first tap data from database
        // This should populate founderFirstTaps[videoID] from persistence
        print("🔥 LOADING: Founder tracking data for video \(videoID)")
    }
}

// MARK: - Extensions for EngagementCalculator

extension EngagementCalculator {
    
    /// Calculate clout for regular users with 5-hype threshold
    static func calculateRegularClout(userTier: UserTier, currentHypeCount: Int) -> Int {
        // No clout awarded until 5 hypes reached
        guard currentHypeCount >= 5 else { return 0 }
        
        let basePoints = 10 // Base hype points
        let tierMultiplier = calculateTierMultiplier(for: userTier)
        
        return Int(Double(basePoints) * tierMultiplier)
    }
    
    /// Check if clout should be awarded based on hype count
    static func shouldAwardClout(currentHypeCount: Int) -> Bool {
        return currentHypeCount >= 5
    }
}
