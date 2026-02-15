//
//  NotificationViewModel.swift
//  StitchSocial
//
//  Layer 7: ViewModels - Notification Management
//  UPDATED: Added senderID and payload to NotificationDisplayData for follow-back and video navigation
//  UPDATED: Fixed payload type from [String: String] to [String: Any] for proper navigation data
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class NotificationViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let notificationService: NotificationService
    private var currentUserID: String? {
        return Auth.auth().currentUser?.uid
    }
    
    // MARK: - Published State
    
    @Published var allNotifications: [StitchNotification] = []
    @Published var filteredNotifications: [NotificationDisplayData] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTab: StitchNotificationTab = .all
    
    // MARK: - Pagination
    
    private var lastDocument: DocumentSnapshot?
    @Published var hasMoreNotifications: Bool = false
    
    // MARK: - Initialization
    
    init(notificationService: NotificationService) {
        self.notificationService = notificationService
        print("🔧 NOTIFICATION VM: Initialized with service integration")
        
        // Start real-time listener
        startListening()
    }
    
    deinit {
        print("🔴 NOTIFICATION VM: DEINIT STARTED")
        
        // Stop listener synchronously - don't use Task
        let service = self.notificationService
        
        // Force immediate cleanup
        DispatchQueue.main.async {
            service.stopListening()
            print("🔴 NOTIFICATION VM: DEINIT COMPLETE")
        }
    }
    
    // MARK: - Load Notifications
    
    func loadNotifications() async {
        guard let userID = currentUserID else {
            print("⚠️ NOTIFICATION VM: No user ID")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await notificationService.loadNotifications(
                for: userID,
                limit: 20,
                lastDocument: nil as DocumentSnapshot?
            )
            
            allNotifications = result.notifications
            lastDocument = result.lastDocument
            hasMoreNotifications = result.hasMore
            
            updateFilteredNotifications()
            updateUnreadCount()
            
            print("🔧 NOTIFICATION VM: Loaded \(allNotifications.count) notifications")
            
        } catch {
            errorMessage = "Failed to load notifications: \(error.localizedDescription)"
            print("❌ NOTIFICATION VM: Load failed - \(error)")
        }
        
        isLoading = false
    }
    
    func loadMoreNotifications() async {
        guard let userID = currentUserID,
              hasMoreNotifications,
              !isLoading else {
            return
        }
        
        isLoading = true
        
        do {
            let result = try await notificationService.loadNotifications(
                for: userID,
                limit: 20,
                lastDocument: lastDocument
            )
            
            allNotifications.append(contentsOf: result.notifications)
            lastDocument = result.lastDocument
            hasMoreNotifications = result.hasMore
            
            updateFilteredNotifications()
            
            print("🔧 NOTIFICATION VM: Loaded \(result.notifications.count) more notifications")
            
        } catch {
            print("❌ NOTIFICATION VM: Load more failed - \(error)")
        }
        
        isLoading = false
    }
    
    func refreshNotifications() async {
        lastDocument = nil
        hasMoreNotifications = false
        await loadNotifications()
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(_ notificationID: String) async {
        do {
            try await notificationService.markAsRead(notificationID)
            
            // Reload to get updated state from Firestore
            await refreshNotifications()
            
            print("✅ NOTIFICATION VM: Marked as read - \(notificationID)")
            
        } catch {
            print("❌ NOTIFICATION VM: Mark as read failed - \(error)")
        }
    }
    
    func markAllAsRead() async {
        guard let userID = currentUserID else { return }
        
        isLoading = true
        
        do {
            try await notificationService.markAllAsRead(for: userID)
            
            // Reload to get updated state from Firestore
            await refreshNotifications()
            
            print("✅ NOTIFICATION VM: Marked all as read")
            
        } catch {
            errorMessage = "Failed to mark all as read: \(error.localizedDescription)"
            print("❌ NOTIFICATION VM: Mark all as read failed - \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Filtering
    
    func selectTab(_ tab: StitchNotificationTab) {
        selectedTab = tab
        updateFilteredNotifications()
    }
    
    private func updateFilteredNotifications() {
        var filtered = allNotifications
        
        // Filter by tab
        switch selectedTab {
        case .all:
            break
        case .unread:
            filtered = filtered.filter { !$0.isRead }
        case .hypes:
            filtered = filtered.filter { $0.type == .hype }
        case .follows:
            filtered = filtered.filter { $0.type == .follow }
        case .replies:
            filtered = filtered.filter { $0.type == .reply }
        case .live:
            filtered = filtered.filter { $0.type == .goLive }
        case .community:
            filtered = filtered.filter { $0.type == .communityPost || $0.type == .communityXP }
        case .system:
            filtered = filtered.filter { $0.type == .system }
        }
        
        // Convert to display data
        filteredNotifications = filtered.map { notification in
            NotificationDisplayData(
                id: notification.id,
                title: notification.title,
                message: notification.message,
                notificationType: notification.type,
                senderID: notification.senderID,
                senderUsername: (notification.payload["senderUsername"] as? String) ?? "Unknown",
                payload: notification.payload,  // ✅ Now [String: Any]
                isRead: notification.isRead,
                createdAt: notification.createdAt
            )
        }
        
        print("🔧 NOTIFICATION VM: Filtered to \(filteredNotifications.count) notifications for \(selectedTab.displayName)")
    }
    
    private func updateUnreadCount() {
        unreadCount = allNotifications.filter { !$0.isRead }.count
    }
    
    // MARK: - Real-time Listener
    
    private func startListening() {
        guard let userID = currentUserID else {
            print("⚠️ NOTIFICATION VM: Cannot start listener - no user ID")
            return
        }
        
        notificationService.startListening(for: userID) { [weak self] notifications in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.allNotifications = notifications
                self.updateFilteredNotifications()
                self.updateUnreadCount()
                
                print("🔔 NOTIFICATION VM: Real-time update - \(notifications.count) notifications")
            }
        }
    }
}

// MARK: - Display Data (UPDATED)

struct NotificationDisplayData: Identifiable {
    let id: String
    let title: String
    let message: String
    let notificationType: StitchNotificationType
    let senderID: String
    let senderUsername: String
    let payload: [String: Any]  // ✅ FIXED: Changed from [String: String] to [String: Any]
    let isRead: Bool
    let createdAt: Date
}
