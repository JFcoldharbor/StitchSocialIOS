//
//  AnnouncementSystem.swift
//  StitchSocial
//
//  Announcement system for platform-wide mandatory content
//  UPDATED: Support for repeating announcements with frequency control
//  - Announcements can repeat multiple times
//  - Max shows per day (e.g., 2 times daily)
//  - Min hours between shows (e.g., 6 hours apart)
//  - Lifetime max shows (optional cap)
//  - Perfect for event announcements that run for weeks/months
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Announcement Model

/// Represents a platform announcement that users must see
struct Announcement: Identifiable, Codable, Hashable {
    let id: String
    let videoId: String
    let creatorId: String
    let title: String
    let message: String?
    let priority: AnnouncementPriority
    let type: AnnouncementType
    let targetAudience: AnnouncementAudience
    let startDate: Date
    let endDate: Date?
    let minimumWatchSeconds: Int
    let isDismissable: Bool
    let requiresAcknowledgment: Bool
    let createdAt: Date
    let updatedAt: Date
    let isActive: Bool
    
    // MARK: - NEW: Repeat/Frequency Settings
    
    /// How the announcement repeats
    let repeatMode: AnnouncementRepeatMode
    
    /// Maximum times to show per day (e.g., 2)
    let maxDailyShows: Int
    
    /// Minimum hours between shows (e.g., 6.0 = 6 hours apart)
    let minHoursBetweenShows: Double
    
    /// Lifetime cap on total shows (nil = unlimited until endDate)
    let maxTotalShows: Int?
    
    // MARK: - Computed Properties
    
    var isCurrentlyActive: Bool {
        let now = Date()
        let afterStart = now >= startDate
        let beforeEnd = endDate == nil || now <= endDate!
        return isActive && afterStart && beforeEnd
    }
    
    var isExpired: Bool {
        guard let endDate = endDate else { return false }
        return Date() > endDate
    }
    
    var isRepeating: Bool {
        return repeatMode != .once
    }
    
    // MARK: - Init with defaults for backward compatibility
    
    init(
        id: String,
        videoId: String,
        creatorId: String,
        title: String,
        message: String?,
        priority: AnnouncementPriority,
        type: AnnouncementType,
        targetAudience: AnnouncementAudience,
        startDate: Date,
        endDate: Date?,
        minimumWatchSeconds: Int,
        isDismissable: Bool,
        requiresAcknowledgment: Bool,
        createdAt: Date,
        updatedAt: Date,
        isActive: Bool,
        repeatMode: AnnouncementRepeatMode = .once,
        maxDailyShows: Int = 1,
        minHoursBetweenShows: Double = 0,
        maxTotalShows: Int? = nil
    ) {
        self.id = id
        self.videoId = videoId
        self.creatorId = creatorId
        self.title = title
        self.message = message
        self.priority = priority
        self.type = type
        self.targetAudience = targetAudience
        self.startDate = startDate
        self.endDate = endDate
        self.minimumWatchSeconds = minimumWatchSeconds
        self.isDismissable = isDismissable
        self.requiresAcknowledgment = requiresAcknowledgment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.repeatMode = repeatMode
        self.maxDailyShows = maxDailyShows
        self.minHoursBetweenShows = minHoursBetweenShows
        self.maxTotalShows = maxTotalShows
    }
}

// MARK: - Announcement Repeat Mode

enum AnnouncementRepeatMode: String, Codable, CaseIterable {
    /// Show only once, ever
    case once = "once"
    
    /// Show daily (up to maxDailyShows per day)
    case daily = "daily"
    
    /// Show on specific schedule (respects minHoursBetweenShows)
    case scheduled = "scheduled"
    
    /// Show until user explicitly stops it (for critical/ongoing events)
    case persistent = "persistent"
    
    var displayName: String {
        switch self {
        case .once: return "One Time"
        case .daily: return "Daily"
        case .scheduled: return "Scheduled"
        case .persistent: return "Persistent"
        }
    }
    
    var description: String {
        switch self {
        case .once: return "Show once, then never again"
        case .daily: return "Show up to X times per day"
        case .scheduled: return "Show with minimum time between views"
        case .persistent: return "Keep showing until event ends"
        }
    }
}

// MARK: - Supporting Enums

enum AnnouncementPriority: String, Codable, CaseIterable {
    case critical = "critical"
    case high = "high"
    case standard = "standard"
    case low = "low"
    
    var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High Priority"
        case .standard: return "Standard"
        case .low: return "Low Priority"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .standard: return 2
        case .low: return 3
        }
    }
}

enum AnnouncementType: String, Codable, CaseIterable {
    case feature = "feature"
    case update = "update"
    case policy = "policy"
    case event = "event"
    case maintenance = "maintenance"
    case promotion = "promotion"
    case community = "community"
    case safety = "safety"
    
    var displayName: String {
        switch self {
        case .feature: return "New Feature"
        case .update: return "App Update"
        case .policy: return "Policy Update"
        case .event: return "Special Event"
        case .maintenance: return "Maintenance"
        case .promotion: return "Promotion"
        case .community: return "Community"
        case .safety: return "Safety Alert"
        }
    }
    
    var icon: String {
        switch self {
        case .feature: return "sparkles"
        case .update: return "arrow.down.app"
        case .policy: return "doc.text"
        case .event: return "star"
        case .maintenance: return "wrench.and.screwdriver"
        case .promotion: return "gift"
        case .community: return "person.3"
        case .safety: return "shield"
        }
    }
}

enum AnnouncementAudience: Codable, Hashable {
    case all
    case newUsers(daysOld: Int)
    case tierAndAbove(String)
    case tierOnly(String)
    case specificUsers([String])
    
    var displayName: String {
        switch self {
        case .all: return "All Users"
        case .newUsers(let days): return "New Users (< \(days) days)"
        case .tierAndAbove(let tier): return "\(tier)+ Users"
        case .tierOnly(let tier): return "\(tier) Only"
        case .specificUsers(let ids): return "\(ids.count) Specific Users"
        }
    }
}

// MARK: - User Announcement Status (UPDATED)

struct UserAnnouncementStatus: Codable, Identifiable {
    var id: String { visibilityId }
    let visibilityId: String
    let userId: String
    let announcementId: String
    let firstSeenAt: Date?
    let completedAt: Date?              // When they first completed it
    let acknowledgedAt: Date?
    let dismissedAt: Date?
    let watchedSeconds: Int?
    let viewCount: Int?                 // Legacy field
    
    // MARK: - NEW: Repeat Tracking Fields
    
    /// Total number of times shown to user
    let totalShowCount: Int
    
    /// Last time the announcement was shown
    let lastShownAt: Date?
    
    /// Number of times shown today (resets daily)
    let showsToday: Int
    
    /// Date of the last "today" count (for daily reset)
    let showsTodayDate: Date?
    
    /// Array of all show timestamps (for analytics)
    let showTimestamps: [Date]
    
    /// User has permanently dismissed (won't show again)
    let permanentlyDismissed: Bool
    
    // MARK: - Computed Properties
    
    var hasCompleted: Bool {
        completedAt != nil
    }
    
    var hasAcknowledged: Bool {
        acknowledgedAt != nil
    }
    
    var hasDismissed: Bool {
        dismissedAt != nil
    }
    
    var hasPermanentlyDismissed: Bool {
        permanentlyDismissed
    }
    
    // MARK: - Init with defaults for backward compatibility
    
    init(
        visibilityId: String,
        userId: String,
        announcementId: String,
        firstSeenAt: Date? = nil,
        completedAt: Date? = nil,
        acknowledgedAt: Date? = nil,
        dismissedAt: Date? = nil,
        watchedSeconds: Int? = nil,
        viewCount: Int? = nil,
        totalShowCount: Int = 0,
        lastShownAt: Date? = nil,
        showsToday: Int = 0,
        showsTodayDate: Date? = nil,
        showTimestamps: [Date] = [],
        permanentlyDismissed: Bool = false
    ) {
        self.visibilityId = visibilityId
        self.userId = userId
        self.announcementId = announcementId
        self.firstSeenAt = firstSeenAt
        self.completedAt = completedAt
        self.acknowledgedAt = acknowledgedAt
        self.dismissedAt = dismissedAt
        self.watchedSeconds = watchedSeconds
        self.viewCount = viewCount
        self.totalShowCount = totalShowCount
        self.lastShownAt = lastShownAt
        self.showsToday = showsToday
        self.showsTodayDate = showsTodayDate
        self.showTimestamps = showTimestamps
        self.permanentlyDismissed = permanentlyDismissed
    }
}

// MARK: - Announcement Service

@MainActor
class AnnouncementService: ObservableObject {
    static let shared = AnnouncementService()
    
    @Published var pendingAnnouncements: [Announcement] = []
    @Published var currentAnnouncement: Announcement?
    @Published var isShowingAnnouncement: Bool = false
    @Published var isLoading: Bool = false
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    private var announcementsCollection: CollectionReference {
        db.collection("announcements")
    }
    private var userStatusCollection: CollectionReference {
        db.collection("user_announcement_status")
    }
    
    private let authorizedCreatorEmails: Set<String> = [
        "developers@stitchsocial.me",
        "james@stitchsocial.me"
    ]
    
    private init() {
        print("📢 ANNOUNCEMENT SERVICE: Initialized with repeat support")
    }
    
    // MARK: - Fetch Announcements (UPDATED with repeat logic)
    
    func fetchPendingAnnouncements(for userId: String, userTier: String, accountAge: Int) async throws -> [Announcement] {
        isLoading = true
        defer { isLoading = false }
        
        print("📢 FETCH: Looking for announcements for user \(userId)")
        
        let snapshot: QuerySnapshot
        do {
            snapshot = try await announcementsCollection
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
        } catch {
            print("📢 FETCH: ❌ Query FAILED: \(error)")
            throw error
        }
        
        print("📢 FETCH: Found \(snapshot.documents.count) active announcements")
        
        var activeAnnouncements: [Announcement] = []
        
        for doc in snapshot.documents {
            do {
                let announcement = try doc.data(as: Announcement.self)
                
                // Check if still active (not expired)
                guard announcement.isCurrentlyActive else {
                    print("📢 FETCH: ⏭️ Skipping '\(announcement.title)' - not currently active")
                    continue
                }
                
                // Check if user is in target audience
                guard isUserInAudience(announcement.targetAudience, userTier: userTier, accountAge: accountAge, userId: userId) else {
                    print("📢 FETCH: ⏭️ Skipping '\(announcement.title)' - user not in target audience")
                    continue
                }
                
                // Get user's status for this announcement
                let status = try await getUserStatus(userId: userId, announcementId: announcement.id)
                
                // Check if user can see this announcement based on repeat rules
                let canShow = canShowAnnouncement(announcement: announcement, status: status)
                
                if canShow {
                    print("📢 FETCH: ✅ Adding '\(announcement.title)' to pending list")
                    activeAnnouncements.append(announcement)
                } else {
                    print("📢 FETCH: ⏭️ Skipping '\(announcement.title)' - repeat rules not met")
                }
                
            } catch {
                print("📢 FETCH: ❌ Failed to decode announcement \(doc.documentID): \(error)")
            }
        }
        
        // Sort by priority
        pendingAnnouncements = activeAnnouncements.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
        
        print("📢 FETCH: Final pending count = \(pendingAnnouncements.count)")
        
        return pendingAnnouncements
    }
    
    // MARK: - NEW: Can Show Announcement (Repeat Logic)
    
    private func canShowAnnouncement(announcement: Announcement, status: UserAnnouncementStatus?) -> Bool {
        let now = Date()
        
        // If no status, user has never seen it - show it
        guard let status = status else {
            print("📢 REPEAT: No status - first time showing")
            return true
        }
        
        // Check if permanently dismissed
        if status.permanentlyDismissed {
            print("📢 REPEAT: Permanently dismissed - skip")
            return false
        }
        
        // Handle based on repeat mode
        switch announcement.repeatMode {
        case .once:
            // Only show if never completed
            let canShow = status.completedAt == nil
            print("📢 REPEAT [once]: completed=\(status.completedAt != nil), canShow=\(canShow)")
            return canShow
            
        case .daily:
            return canShowDaily(announcement: announcement, status: status, now: now)
            
        case .scheduled:
            return canShowScheduled(announcement: announcement, status: status, now: now)
            
        case .persistent:
            return canShowPersistent(announcement: announcement, status: status, now: now)
        }
    }
    
    /// Check if daily repeat announcement can be shown
    private func canShowDaily(announcement: Announcement, status: UserAnnouncementStatus, now: Date) -> Bool {
        // Check lifetime cap
        if let maxTotal = announcement.maxTotalShows, status.totalShowCount >= maxTotal {
            print("📢 REPEAT [daily]: Lifetime cap reached (\(status.totalShowCount)/\(maxTotal))")
            return false
        }
        
        // Check if it's a new day
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        
        var showsTodayCount = status.showsToday
        
        // Reset daily count if it's a new day
        if let lastDate = status.showsTodayDate {
            let lastDateStart = calendar.startOfDay(for: lastDate)
            if todayStart > lastDateStart {
                showsTodayCount = 0 // New day, reset count
                print("📢 REPEAT [daily]: New day - resetting daily count")
            }
        }
        
        // Check daily limit
        if showsTodayCount >= announcement.maxDailyShows {
            print("📢 REPEAT [daily]: Daily limit reached (\(showsTodayCount)/\(announcement.maxDailyShows))")
            return false
        }
        
        // Check minimum time between shows
        if announcement.minHoursBetweenShows > 0, let lastShown = status.lastShownAt {
            let hoursSinceLastShow = now.timeIntervalSince(lastShown) / 3600
            if hoursSinceLastShow < announcement.minHoursBetweenShows {
                print("📢 REPEAT [daily]: Too soon - \(String(format: "%.1f", hoursSinceLastShow))h since last show (min: \(announcement.minHoursBetweenShows)h)")
                return false
            }
        }
        
        print("📢 REPEAT [daily]: ✅ Can show (today: \(showsTodayCount)/\(announcement.maxDailyShows))")
        return true
    }
    
    /// Check if scheduled repeat announcement can be shown
    private func canShowScheduled(announcement: Announcement, status: UserAnnouncementStatus, now: Date) -> Bool {
        // Check lifetime cap
        if let maxTotal = announcement.maxTotalShows, status.totalShowCount >= maxTotal {
            print("📢 REPEAT [scheduled]: Lifetime cap reached")
            return false
        }
        
        // Check minimum time between shows
        if let lastShown = status.lastShownAt {
            let hoursSinceLastShow = now.timeIntervalSince(lastShown) / 3600
            if hoursSinceLastShow < announcement.minHoursBetweenShows {
                print("📢 REPEAT [scheduled]: Too soon - \(String(format: "%.1f", hoursSinceLastShow))h < \(announcement.minHoursBetweenShows)h")
                return false
            }
        }
        
        print("📢 REPEAT [scheduled]: ✅ Can show")
        return true
    }
    
    /// Check if persistent announcement can be shown
    private func canShowPersistent(announcement: Announcement, status: UserAnnouncementStatus, now: Date) -> Bool {
        // Persistent announcements always show, but respect daily/hourly limits
        
        // Check daily limit if set
        if announcement.maxDailyShows > 0 {
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: now)
            
            var showsTodayCount = status.showsToday
            
            if let lastDate = status.showsTodayDate {
                let lastDateStart = calendar.startOfDay(for: lastDate)
                if todayStart > lastDateStart {
                    showsTodayCount = 0
                }
            }
            
            if showsTodayCount >= announcement.maxDailyShows {
                print("📢 REPEAT [persistent]: Daily limit reached")
                return false
            }
        }
        
        // Check minimum time between shows
        if announcement.minHoursBetweenShows > 0, let lastShown = status.lastShownAt {
            let hoursSinceLastShow = now.timeIntervalSince(lastShown) / 3600
            if hoursSinceLastShow < announcement.minHoursBetweenShows {
                print("📢 REPEAT [persistent]: Too soon")
                return false
            }
        }
        
        print("📢 REPEAT [persistent]: ✅ Can show")
        return true
    }
    
    private func isUserInAudience(_ audience: AnnouncementAudience, userTier: String, accountAge: Int, userId: String) -> Bool {
        switch audience {
        case .all:
            return true
        case .newUsers(let maxDays):
            return accountAge <= maxDays
        case .tierAndAbove(let minTier):
            let tierOrder = ["rookie": 0, "regular": 1, "ambassador": 2, "topCreator": 3, "admin": 4]
            let userTierOrder = tierOrder[userTier.lowercased()] ?? 0
            let minTierOrder = tierOrder[minTier.lowercased()] ?? 0
            return userTierOrder >= minTierOrder
        case .tierOnly(let tier):
            return userTier.lowercased() == tier.lowercased()
        case .specificUsers(let userIds):
            return userIds.contains(userId)
        }
    }
    
    // MARK: - User Status Management (UPDATED)
    
    func getUserStatus(userId: String, announcementId: String) async throws -> UserAnnouncementStatus? {
        let statusId = "\(userId)_\(announcementId)"
        
        do {
            let doc = try await userStatusCollection.document(statusId).getDocument()
            guard doc.exists else {
                return nil
            }
            return try doc.data(as: UserAnnouncementStatus.self)
        } catch {
            print("📢 STATUS: Error getting status for \(statusId): \(error)")
            return nil
        }
    }
    
    func markAsSeen(userId: String, announcementId: String) async throws {
        let statusId = "\(userId)_\(announcementId)"
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        
        let existing = try await getUserStatus(userId: userId, announcementId: announcementId)
        
        if var existingStatus = existing {
            // Update existing status
            var newShowsToday = existingStatus.showsToday
            var showsTodayDate = existingStatus.showsTodayDate ?? todayStart
            
            // Reset daily count if new day
            if let lastDate = existingStatus.showsTodayDate {
                let lastDateStart = calendar.startOfDay(for: lastDate)
                if todayStart > lastDateStart {
                    newShowsToday = 0
                    showsTodayDate = todayStart
                }
            }
            
            try await userStatusCollection.document(statusId).updateData([
                "totalShowCount": FieldValue.increment(Int64(1)),
                "lastShownAt": Timestamp(date: now),
                "showsToday": newShowsToday + 1,
                "showsTodayDate": Timestamp(date: showsTodayDate),
                "showTimestamps": FieldValue.arrayUnion([Timestamp(date: now)])
            ])
            
            print("📢 STATUS: Updated show count for \(statusId)")
        } else {
            // Create new status
            let status = UserAnnouncementStatus(
                visibilityId: statusId,
                userId: userId,
                announcementId: announcementId,
                firstSeenAt: now,
                completedAt: nil,
                acknowledgedAt: nil,
                dismissedAt: nil,
                watchedSeconds: 0,
                viewCount: 1,
                totalShowCount: 1,
                lastShownAt: now,
                showsToday: 1,
                showsTodayDate: todayStart,
                showTimestamps: [now],
                permanentlyDismissed: false
            )
            try userStatusCollection.document(statusId).setData(from: status)
            print("📢 STATUS: Created new status for \(statusId)")
        }
    }
    
    func markAsCompleted(userId: String, announcementId: String, watchedSeconds: Int) async throws {
        let statusId = "\(userId)_\(announcementId)"
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        
        // Get existing to preserve show counts
        let existing = try await getUserStatus(userId: userId, announcementId: announcementId)
        
        var updateData: [String: Any] = [
            "visibilityId": statusId,
            "userId": userId,
            "announcementId": announcementId,
            "completedAt": Timestamp(date: now),
            "watchedSeconds": watchedSeconds,
            "lastShownAt": Timestamp(date: now)
        ]
        
        if existing == nil {
            // First time - set initial values
            updateData["firstSeenAt"] = Timestamp(date: now)
            updateData["totalShowCount"] = 1
            updateData["showsToday"] = 1
            updateData["showsTodayDate"] = Timestamp(date: todayStart)
            updateData["showTimestamps"] = [Timestamp(date: now)]
            updateData["permanentlyDismissed"] = false
        } else {
            // Update existing - increment counts
            updateData["totalShowCount"] = FieldValue.increment(Int64(1))
            updateData["showTimestamps"] = FieldValue.arrayUnion([Timestamp(date: now)])
            
            // Handle daily count
            var newShowsToday = (existing?.showsToday ?? 0)
            if let lastDate = existing?.showsTodayDate {
                let lastDateStart = calendar.startOfDay(for: lastDate)
                if todayStart > lastDateStart {
                    newShowsToday = 0
                }
            }
            updateData["showsToday"] = newShowsToday + 1
            updateData["showsTodayDate"] = Timestamp(date: todayStart)
        }
        
        try await userStatusCollection.document(statusId).setData(updateData, merge: true)
        
        print("📢 STATUS: Marked as completed - \(statusId)")
        
        // Remove from pending list
        pendingAnnouncements.removeAll { $0.id == announcementId }
        
        // Check if there are more announcements
        if pendingAnnouncements.isEmpty {
            print("📢 STATUS: No more announcements, closing overlay")
            isShowingAnnouncement = false
            currentAnnouncement = nil
        } else {
            print("📢 STATUS: \(pendingAnnouncements.count) more announcement(s) to show")
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                showNextAnnouncementIfNeeded()
            }
        }
    }
    
    /// Permanently dismiss an announcement (won't show again)
    func permanentlyDismiss(userId: String, announcementId: String) async throws {
        let statusId = "\(userId)_\(announcementId)"
        
        try await userStatusCollection.document(statusId).setData([
            "visibilityId": statusId,
            "userId": userId,
            "announcementId": announcementId,
            "permanentlyDismissed": true,
            "dismissedAt": Timestamp(date: Date())
        ], merge: true)
        
        print("📢 STATUS: Permanently dismissed - \(statusId)")
        
        // Remove from pending list
        pendingAnnouncements.removeAll { $0.id == announcementId }
        
        if pendingAnnouncements.isEmpty {
            isShowingAnnouncement = false
            currentAnnouncement = nil
        } else {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                showNextAnnouncementIfNeeded()
            }
        }
    }
    
    func dismissAnnouncement(userId: String, announcementId: String) async throws {
        // Regular dismiss just marks as completed for this session
        try await markAsCompleted(userId: userId, announcementId: announcementId, watchedSeconds: 0)
    }
    
    // MARK: - Display Logic
    
    func showNextAnnouncementIfNeeded() {
        guard !pendingAnnouncements.isEmpty else {
            print("📢 DISPLAY: No pending announcements")
            isShowingAnnouncement = false
            currentAnnouncement = nil
            return
        }
        
        currentAnnouncement = pendingAnnouncements.first
        isShowingAnnouncement = true
        print("📢 DISPLAY: Showing announcement '\(currentAnnouncement?.title ?? "unknown")'")
    }
    
    /// Check and show announcements on app launch
    func checkForCriticalAnnouncements(userId: String, userTier: String, accountAge: Int) async {
        print("📢 CHECK: Starting announcement check for user \(userId)")
        
        do {
            let pending = try await fetchPendingAnnouncements(for: userId, userTier: userTier, accountAge: accountAge)
            
            print("📢 CHECK: Found \(pending.count) pending announcements")
            
            if let firstAnnouncement = pending.first {
                print("📢 CHECK: ✅ Will show '\(firstAnnouncement.title)' (repeat mode: \(firstAnnouncement.repeatMode.rawValue))")
                currentAnnouncement = firstAnnouncement
                isShowingAnnouncement = true
            } else {
                print("📢 CHECK: No announcements to show")
            }
        } catch {
            print("❌ CHECK: Error checking announcements: \(error)")
        }
    }
    
    // MARK: - Admin: Create Announcement (UPDATED)
    
    func createAnnouncement(
        videoId: String,
        creatorEmail: String,
        creatorId: String,
        title: String,
        message: String? = nil,
        priority: AnnouncementPriority = .standard,
        type: AnnouncementType = .update,
        targetAudience: AnnouncementAudience = .all,
        startDate: Date = Date(),
        endDate: Date? = nil,
        minimumWatchSeconds: Int = 5,
        isDismissable: Bool = true,
        requiresAcknowledgment: Bool = false,
        // NEW: Repeat settings
        repeatMode: AnnouncementRepeatMode = .once,
        maxDailyShows: Int = 1,
        minHoursBetweenShows: Double = 0,
        maxTotalShows: Int? = nil
    ) async throws -> Announcement {
        print("📢 CREATE: Attempting to create announcement")
        print("📢 CREATE: Creator email = \(creatorEmail)")
        print("📢 CREATE: Repeat mode = \(repeatMode.rawValue)")
        
        guard authorizedCreatorEmails.contains(creatorEmail.lowercased()) else {
            print("📢 CREATE: ❌ Unauthorized creator: \(creatorEmail)")
            throw AnnouncementError.unauthorizedCreator
        }
        
        let announcementId = UUID().uuidString
        let now = Date()
        
        let announcement = Announcement(
            id: announcementId,
            videoId: videoId,
            creatorId: creatorId,
            title: title,
            message: message,
            priority: priority,
            type: type,
            targetAudience: targetAudience,
            startDate: startDate,
            endDate: endDate,
            minimumWatchSeconds: minimumWatchSeconds,
            isDismissable: isDismissable,
            requiresAcknowledgment: requiresAcknowledgment,
            createdAt: now,
            updatedAt: now,
            isActive: true,
            repeatMode: repeatMode,
            maxDailyShows: maxDailyShows,
            minHoursBetweenShows: minHoursBetweenShows,
            maxTotalShows: maxTotalShows
        )
        
        try announcementsCollection.document(announcementId).setData(from: announcement)
        
        print("✅ ANNOUNCEMENT: Created '\(title)' with id \(announcementId)")
        print("✅ ANNOUNCEMENT: Repeat=\(repeatMode.rawValue), MaxDaily=\(maxDailyShows), MinHours=\(minHoursBetweenShows)")
        return announcement
    }
    
    func deactivateAnnouncement(announcementId: String, creatorEmail: String) async throws {
        guard authorizedCreatorEmails.contains(creatorEmail.lowercased()) else {
            throw AnnouncementError.unauthorizedCreator
        }
        
        try await announcementsCollection.document(announcementId).updateData([
            "isActive": false,
            "updatedAt": Timestamp(date: Date())
        ])
        
        print("🔕 Deactivated announcement: \(announcementId)")
    }
    
    func getAllAnnouncements() async throws -> [Announcement] {
        let snapshot = try await announcementsCollection
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: Announcement.self) }
    }
    
    // MARK: - Analytics
    
    /// Get view statistics for an announcement
    func getAnnouncementStats(announcementId: String) async throws -> AnnouncementStats {
        let snapshot = try await userStatusCollection
            .whereField("announcementId", isEqualTo: announcementId)
            .getDocuments()
        
        var totalViews = 0
        var uniqueViewers = 0
        var completedCount = 0
        var permanentDismissals = 0
        
        for doc in snapshot.documents {
            uniqueViewers += 1
            if let status = try? doc.data(as: UserAnnouncementStatus.self) {
                totalViews += status.totalShowCount
                if status.hasCompleted { completedCount += 1 }
                if status.permanentlyDismissed { permanentDismissals += 1 }
            }
        }
        
        return AnnouncementStats(
            announcementId: announcementId,
            totalViews: totalViews,
            uniqueViewers: uniqueViewers,
            completedCount: completedCount,
            permanentDismissals: permanentDismissals
        )
    }
}

// MARK: - Announcement Stats

struct AnnouncementStats {
    let announcementId: String
    let totalViews: Int
    let uniqueViewers: Int
    let completedCount: Int
    let permanentDismissals: Int
    
    var averageViewsPerUser: Double {
        guard uniqueViewers > 0 else { return 0 }
        return Double(totalViews) / Double(uniqueViewers)
    }
}

// MARK: - Errors

enum AnnouncementError: LocalizedError {
    case unauthorizedCreator
    case announcementNotFound
    case alreadyCompleted
    case minimumWatchTimeNotMet
    
    var errorDescription: String? {
        switch self {
        case .unauthorizedCreator:
            return "Only authorized accounts can create announcements"
        case .announcementNotFound:
            return "Announcement not found"
        case .alreadyCompleted:
            return "Announcement already completed"
        case .minimumWatchTimeNotMet:
            return "Please watch the full announcement before dismissing"
        }
    }
}

// MARK: - Announcement Helper for Video Upload (UPDATED)

struct AnnouncementVideoHelper {
    
    static func canCreateAnnouncement(email: String) -> Bool {
        let authorizedEmails: Set<String> = [
            "developers@stitchsocial.me",
            "james@stitchsocial.me"
        ]
        return authorizedEmails.contains(email.lowercased())
    }
    
    /// Create a one-time announcement (original behavior)
    static func createAnnouncementFromVideo(
        videoId: String,
        creatorEmail: String,
        creatorId: String,
        title: String,
        message: String? = nil,
        priority: AnnouncementPriority = .standard,
        type: AnnouncementType = .update,
        minimumWatchSeconds: Int = 5
    ) async throws -> Announcement {
        return try await AnnouncementService.shared.createAnnouncement(
            videoId: videoId,
            creatorEmail: creatorEmail,
            creatorId: creatorId,
            title: title,
            message: message,
            priority: priority,
            type: type,
            targetAudience: .all,
            minimumWatchSeconds: minimumWatchSeconds,
            repeatMode: .once,
            maxDailyShows: 1,
            minHoursBetweenShows: 0,
            maxTotalShows: 1
        )
    }
    
    /// Create a repeating event announcement
    /// Perfect for events that are weeks/months away
    static func createEventAnnouncement(
        videoId: String,
        creatorEmail: String,
        creatorId: String,
        title: String,
        message: String? = nil,
        eventDate: Date,
        maxTimesPerDay: Int = 2,
        minHoursBetween: Double = 6.0,
        minimumWatchSeconds: Int = 5
    ) async throws -> Announcement {
        return try await AnnouncementService.shared.createAnnouncement(
            videoId: videoId,
            creatorEmail: creatorEmail,
            creatorId: creatorId,
            title: title,
            message: message,
            priority: .high,
            type: .event,
            targetAudience: .all,
            startDate: Date(),
            endDate: eventDate,
            minimumWatchSeconds: minimumWatchSeconds,
            isDismissable: true,
            requiresAcknowledgment: false,
            repeatMode: .daily,
            maxDailyShows: maxTimesPerDay,
            minHoursBetweenShows: minHoursBetween,
            maxTotalShows: nil  // No lifetime cap - show until event
        )
    }
}
