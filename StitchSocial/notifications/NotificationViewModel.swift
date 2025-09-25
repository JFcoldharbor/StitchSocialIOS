//
//  NotificationViewModel.swift
//  StitchSocial
//
//  Layer 7: ViewModels - Notification Management
//  Dependencies: NotificationService (Layer 4), AuthService (Layer 4)
//  FIXED: All compilation errors resolved
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Missing Types (Fixed)

/// Result structure for loading notifications with pagination
struct NotificationLoadResult {
    let notifications: [StitchNotification]
    let lastDocument: DocumentSnapshot?
    let hasMore: Bool
    
    init(notifications: [StitchNotification], lastDocument: DocumentSnapshot? = nil, hasMore: Bool = false) {
        self.notifications = notifications
        self.lastDocument = lastDocument
        self.hasMore = hasMore
    }
}

/// UI-compatible notification data for views
struct NotificationDisplayData: Identifiable, Codable {
    let id: String
    let recipientID: String
    let senderID: String
    let senderUsername: String
    let senderProfileImageURL: String?
    let notificationType: StitchNotificationType
    let title: String
    let message: String
    let payload: [String: String]
    let isRead: Bool
    let createdAt: Date
    let expiresAt: Date?
    
    init(from notification: StitchNotification, senderUsername: String, senderProfileImageURL: String? = nil) {
        self.id = notification.id
        self.recipientID = notification.recipientID
        self.senderID = notification.senderID
        self.senderUsername = senderUsername
        self.senderProfileImageURL = senderProfileImageURL
        self.notificationType = notification.type
        self.title = notification.title
        self.message = notification.message
        self.payload = notification.payload
        self.isRead = notification.isRead
        self.createdAt = notification.createdAt
        self.expiresAt = notification.expiresAt
    }
}

/// Notification view model with service integration
@MainActor
class NotificationViewModel: ObservableObject {
    
    // MARK: - Dependencies (Fixed - No Redeclaration)
    
    private let notificationService: NotificationService
    private let authService: AuthService?
    
    // MARK: - Published State
    
    @Published var notifications: [NotificationDisplayData] = []
    @Published var filteredNotifications: [NotificationDisplayData] = []
    @Published var isLoading = false
    @Published var hasMoreNotifications = true
    @Published var currentFilter: StitchNotificationTab = .all
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
    
    // MARK: - Initialization (Fixed - Dependency Injection)
    
    init(notificationService: NotificationService? = nil, authService: AuthService? = nil) {
        self.notificationService = notificationService ?? NotificationService()
        self.authService = authService
        
        print("📧 NOTIFICATION VM: Initialized with service integration")
    }
    
    // MARK: - Public Methods
    
    /// Load initial notifications from service
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
                // Convert to display format
                self.notifications = result.notifications.map { stitchNotif in
                    convertToDisplayData(stitchNotif)
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
                    convertToDisplayData(stitchNotif)
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
                    var updatedNotification = notifications[index]
                    // Create new instance with updated read status
                    let newNotification = NotificationDisplayData(
                        from: StitchNotification(
                            id: updatedNotification.id,
                            recipientID: updatedNotification.recipientID,
                            senderID: updatedNotification.senderID,
                            type: updatedNotification.notificationType,
                            title: updatedNotification.title,
                            message: updatedNotification.message,
                            payload: updatedNotification.payload,
                            isRead: true,
                            createdAt: updatedNotification.createdAt,
                            expiresAt: updatedNotification.expiresAt
                        ),
                        senderUsername: updatedNotification.senderUsername,
                        senderProfileImageURL: updatedNotification.senderProfileImageURL
                    )
                    
                    notifications[index] = newNotification
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
                    NotificationDisplayData(
                        from: StitchNotification(
                            id: notification.id,
                            recipientID: notification.recipientID,
                            senderID: notification.senderID,
                            type: notification.notificationType,
                            title: notification.title,
                            message: notification.message,
                            payload: notification.payload,
                            isRead: true,
                            createdAt: notification.createdAt,
                            expiresAt: notification.expiresAt
                        ),
                        senderUsername: notification.senderUsername,
                        senderProfileImageURL: notification.senderProfileImageURL
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
    func filterNotifications(by tab: StitchNotificationTab) {
        currentFilter = tab
        
        switch tab {
        case .all:
            filteredNotifications = notifications
        case .hypes:
            filteredNotifications = notifications.filter {
                $0.notificationType == .hype || $0.notificationType == .cool
            }
        case .follows:
            filteredNotifications = notifications.filter {
                $0.notificationType == .follow
            }
        case .replies:
            filteredNotifications = notifications.filter {
                $0.notificationType == .reply || $0.notificationType == .mention
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
    
    /// Convert StitchNotification to NotificationDisplayData for UI compatibility
    private func convertToDisplayData(_ stitchNotif: StitchNotification) -> NotificationDisplayData {
        // Extract username from payload or use senderID as fallback
        let senderUsername = extractUsername(from: stitchNotif.payload) ?? stitchNotif.senderID
        let senderProfileImage = extractProfileImage(from: stitchNotif.payload)
        
        return NotificationDisplayData(
            from: stitchNotif,
            senderUsername: senderUsername,
            senderProfileImageURL: senderProfileImage
        )
    }
    
    /// Extract username from notification payload
    private func extractUsername(from payload: [String: String]) -> String? {
        // Try different possible keys for username
        if let username = payload["senderUsername"] { return username }
        if let username = payload["followerUsername"] { return username }
        if let username = payload["replierUsername"] { return username }
        return nil
    }
    
    /// Extract profile image URL from notification payload
    private func extractProfileImage(from payload: [String: String]) -> String? {
        // Try different possible keys for profile image
        if let imageURL = payload["senderProfileImageURL"] { return imageURL }
        if let imageURL = payload["followerProfileImageURL"] { return imageURL }
        if let imageURL = payload["replierProfileImageURL"] { return imageURL }
        return nil
    }
}
