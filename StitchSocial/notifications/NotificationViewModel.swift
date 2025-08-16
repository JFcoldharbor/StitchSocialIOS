//
//  NotificationViewModel.swift
//  CleanBeta
//
//  Layer 7: ViewModels - Notification Management Connected to Service
//  Dependencies: NotificationService, AuthService
//  Features: Real database integration, pagination, proper data mapping
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Notification view model with complete service integration
@MainActor
class NotificationViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let notificationService: NotificationService
    private let authService: AuthService?
    
    // MARK: - Published State
    
    @Published var notifications: [NotificationData] = []
    @Published var filteredNotifications: [NotificationData] = []
    @Published var isLoading = false
    @Published var hasMoreNotifications = true
    @Published var currentFilter: NotificationTab = .all
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var currentUserID: String {
        authService?.currentUser?.id ?? Auth.auth().currentUser?.uid ?? ""
    }
    private let notificationsPerPage = 20
    private var lastDocument: DocumentSnapshot?
    private var allNotificationsLoaded = false
    
    // MARK: - Computed Properties
    
    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }
    
    // MARK: - Initialization
    
    init(
        notificationService: NotificationService? = nil,
        authService: AuthService? = nil
    ) {
        self.notificationService = notificationService ?? NotificationService()
        self.authService = authService
        
        print("📧 NOTIFICATION VM: Initialized with service integration")
    }
    
    // MARK: - Public Methods
    
    /// Load initial notifications from database
    func loadNotifications() async {
        guard !currentUserID.isEmpty else {
            print("⚠️ NOTIFICATION VM: No user ID available")
            return
        }
        
        isLoading = true
        errorMessage = nil
        lastDocument = nil
        allNotificationsLoaded = false
        
        do {
            let result = try await notificationService.loadNotifications(
                for: currentUserID,
                limit: notificationsPerPage,
                lastDocument: nil
            )
            
            await MainActor.run {
                // Convert StitchNotification to NotificationData for UI compatibility
                self.notifications = result.notifications.map { stitchNotif in
                    convertToNotificationData(stitchNotif)
                }
                
                self.lastDocument = result.lastDocument
                self.hasMoreNotifications = result.hasMore
                self.allNotificationsLoaded = !result.hasMore
                
                // Apply current filter
                self.filterNotifications(by: self.currentFilter)
                
                print("📧 NOTIFICATION VM: Loaded \(self.notifications.count) notifications")
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load notifications: \(error.localizedDescription)"
                print("❌ NOTIFICATION VM: Load failed - \(error)")
            }
        }
        
        isLoading = false
    }
    
    /// Refresh notifications (pull-to-refresh)
    func refreshNotifications() async {
        await loadNotifications()
    }
    
    /// Load more notifications (pagination)
    func loadMoreNotifications() async {
        guard hasMoreNotifications && !isLoading && !allNotificationsLoaded else {
            print("📧 NOTIFICATION VM: No more notifications to load")
            return
        }
        
        guard let lastDoc = lastDocument else {
            print("⚠️ NOTIFICATION VM: No last document for pagination")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await notificationService.loadNotifications(
                for: currentUserID,
                limit: notificationsPerPage,
                lastDocument: lastDoc
            )
            
            await MainActor.run {
                // Append new notifications
                let newNotifications = result.notifications.map { stitchNotif in
                    convertToNotificationData(stitchNotif)
                }
                
                self.notifications.append(contentsOf: newNotifications)
                self.lastDocument = result.lastDocument
                self.hasMoreNotifications = result.hasMore
                self.allNotificationsLoaded = !result.hasMore
                
                // Reapply filter to include new notifications
                self.filterNotifications(by: self.currentFilter)
                
                print("📧 NOTIFICATION VM: Loaded \(newNotifications.count) more notifications")
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load more notifications: \(error.localizedDescription)"
                print("❌ NOTIFICATION VM: Load more failed - \(error)")
            }
        }
        
        isLoading = false
    }
    
    /// Mark notification as read
    func markAsRead(_ notificationID: String) async {
        do {
            // Update on server first
            try await notificationService.markNotificationAsRead(notificationID: notificationID)
            
            // Update local state
            await MainActor.run {
                if let index = notifications.firstIndex(where: { $0.id == notificationID }) {
                    notifications[index] = NotificationData(
                        id: notifications[index].id,
                        recipientID: notifications[index].recipientID,
                        senderID: notifications[index].senderID,
                        senderUsername: notifications[index].senderUsername,
                        senderProfileImageURL: notifications[index].senderProfileImageURL,
                        type: notifications[index].type,
                        title: notifications[index].title,
                        message: notifications[index].message,
                        payload: notifications[index].payload,
                        isRead: true,
                        createdAt: notifications[index].createdAt,
                        expiresAt: notifications[index].expiresAt
                    )
                }
                
                // Reapply filter
                filterNotifications(by: currentFilter)
            }
            
            print("📧 NOTIFICATION VM: Marked \(notificationID) as read")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to mark notification as read: \(error.localizedDescription)"
                print("❌ NOTIFICATION VM: Mark as read failed - \(error)")
            }
        }
    }
    
    /// Mark all notifications as read
    func markAllAsRead() async {
        guard !currentUserID.isEmpty else { return }
        
        do {
            // Update on server first
            try await notificationService.markAllNotificationsAsRead(for: currentUserID)
            
            // Update local state
            await MainActor.run {
                notifications = notifications.map { notification in
                    NotificationData(
                        id: notification.id,
                        recipientID: notification.recipientID,
                        senderID: notification.senderID,
                        senderUsername: notification.senderUsername,
                        senderProfileImageURL: notification.senderProfileImageURL,
                        type: notification.type,
                        title: notification.title,
                        message: notification.message,
                        payload: notification.payload,
                        isRead: true,
                        createdAt: notification.createdAt,
                        expiresAt: notification.expiresAt
                    )
                }
                
                // Reapply filter
                filterNotifications(by: currentFilter)
            }
            
            print("📧 NOTIFICATION VM: Marked all notifications as read")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to mark all notifications as read: \(error.localizedDescription)"
                print("❌ NOTIFICATION VM: Mark all as read failed - \(error)")
            }
        }
    }
    
    /// Filter notifications by tab
    func filterNotifications(by tab: NotificationTab) {
        currentFilter = tab
        
        switch tab {
        case .all:
            filteredNotifications = notifications
        case .hypes:
            filteredNotifications = notifications.filter {
                $0.type == .hype || $0.type == .cool
            }
        case .follows:
            filteredNotifications = notifications.filter {
                $0.type == .follow
            }
        case .replies:
            filteredNotifications = notifications.filter {
                $0.type == .reply || $0.type == .mention
            }
        }
        
        print("📧 NOTIFICATION VM: Filtered to \(filteredNotifications.count) notifications for \(tab.displayName)")
    }
    
    /// Get unread count from server
    func updateUnreadCount() async {
        guard !currentUserID.isEmpty else { return }
        
        do {
            let count = try await notificationService.getUnreadCount(for: currentUserID)
            
            await MainActor.run {
                // Update from server takes precedence
                print("📧 NOTIFICATION VM: Updated unread count to \(count)")
            }
            
        } catch {
            print("❌ NOTIFICATION VM: Failed to update unread count - \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Convert StitchNotification to NotificationData for UI compatibility
    private func convertToNotificationData(_ stitchNotif: StitchNotification) -> NotificationData {
        // Map StitchNotificationType to NotificationType
        let uiType: NotificationType
        switch stitchNotif.type {
        case .engagementReward, .progressiveTap:
            uiType = .hype // Map engagement notifications to hype
        case .newFollower:
            uiType = .follow
        case .videoReply:
            uiType = .reply
        case .mention:
            uiType = .mention
        case .badgeUnlock, .tierAdvancement, .systemAlert:
            uiType = .hype // Map system notifications to hype category
        }
        
        // Extract username from payload or use senderID as fallback
        let senderUsername = extractUsername(from: stitchNotif.payload) ?? stitchNotif.senderID
        let senderProfileImage = extractProfileImage(from: stitchNotif.payload)
        
        // Convert payload to [String: String] for UI compatibility
        let uiPayload = convertPayload(stitchNotif.payload)
        
        return NotificationData(
            id: stitchNotif.id,
            recipientID: stitchNotif.recipientID,
            senderID: stitchNotif.senderID,
            senderUsername: senderUsername,
            senderProfileImageURL: senderProfileImage,
            type: uiType,
            title: stitchNotif.title,
            message: stitchNotif.message,
            payload: uiPayload,
            isRead: stitchNotif.isRead,
            createdAt: stitchNotif.createdAt,
            expiresAt: stitchNotif.expiresAt
        )
    }
    
    /// Extract username from notification payload
    private func extractUsername(from payload: [String: Any]) -> String? {
        // Try different possible keys for username
        if let username = payload["senderUsername"] as? String { return username }
        if let username = payload["followerUsername"] as? String { return username }
        if let username = payload["replierUsername"] as? String { return username }
        return nil
    }
    
    /// Extract profile image URL from notification payload
    private func extractProfileImage(from payload: [String: Any]) -> String? {
        // Try different possible keys for profile image
        if let imageURL = payload["senderProfileImageURL"] as? String { return imageURL }
        if let imageURL = payload["followerProfileImageURL"] as? String { return imageURL }
        if let imageURL = payload["replierProfileImageURL"] as? String { return imageURL }
        return nil
    }
    
    /// Convert [String: Any] payload to [String: String] for UI
    private func convertPayload(_ payload: [String: Any]) -> [String: String] {
        var converted: [String: String] = [:]
        
        for (key, value) in payload {
            if let stringValue = value as? String {
                converted[key] = stringValue
            } else if let intValue = value as? Int {
                converted[key] = String(intValue)
            } else if let doubleValue = value as? Double {
                converted[key] = String(doubleValue)
            } else if let boolValue = value as? Bool {
                converted[key] = String(boolValue)
            }
            // Skip other types that can't be converted to String
        }
        
        return converted
    }
}

// MARK: - Supporting Types

/// Notification tab types for filtering
enum NotificationTab: String, CaseIterable {
    case all = "all"
    case hypes = "hypes"
    case follows = "follows"
    case replies = "replies"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .hypes: return "Hypes"
        case .follows: return "Follows"
        case .replies: return "Replies"
        }
    }
}

/// UI-compatible notification type
enum NotificationType: String, CaseIterable, Codable {
    case hype = "hype"
    case cool = "cool"
    case follow = "follow"
    case reply = "reply"
    case mention = "mention"
    
    var iconName: String {
        switch self {
        case .hype: return "heart.fill"
        case .cool: return "hand.thumbsdown.fill"
        case .follow: return "person.badge.plus.fill"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        }
    }
    
    var color: Color {
        switch self {
        case .hype: return StitchColors.hype
        case .cool: return StitchColors.cool
        case .follow: return StitchColors.primary
        case .reply: return StitchColors.reply
        case .mention: return StitchColors.warning
        }
    }
    
    var actionText: String {
        switch self {
        case .hype: return "hyped your video"
        case .cool: return "cooled your video"
        case .follow: return "started following you"
        case .reply: return "replied to your thread"
        case .mention: return "mentioned you"
        }
    }
}

/// UI-compatible notification data structure
struct NotificationData: Identifiable, Codable {
    let id: String
    let recipientID: String
    let senderID: String
    let senderUsername: String
    let senderProfileImageURL: String?
    let type: NotificationType
    let title: String
    let message: String
    let payload: [String: String]
    let isRead: Bool
    let createdAt: Date
    let expiresAt: Date?
    
    init(
        id: String = UUID().uuidString,
        recipientID: String,
        senderID: String,
        senderUsername: String,
        senderProfileImageURL: String? = nil,
        type: NotificationType,
        title: String,
        message: String,
        payload: [String: String] = [:],
        isRead: Bool = false,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.recipientID = recipientID
        self.senderID = senderID
        self.senderUsername = senderUsername
        self.senderProfileImageURL = senderProfileImageURL
        self.type = type
        self.title = title
        self.message = message
        self.payload = payload
        self.isRead = isRead
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
