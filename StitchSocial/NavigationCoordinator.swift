//
//  NavigationCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - Centralized Navigation Management
//  Dependencies: Layer 1 Foundation only (UserTier, MainAppTab, StitchColors)
//  Manages all app navigation flows and deep linking
//  PHASE 1: Updated notification names to use unified NotificationNames.swift
//

import SwiftUI
import Foundation

/// Centralized navigation coordinator for all app navigation flows
@MainActor
class NavigationCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var selectedTab: MainAppTab = .home
    @Published var showingProfileSheet = false
    @Published var showingSettingsSheet = false
    @Published var selectedUserID: String?
    @Published var showingFullscreenVideo = false
    @Published var fullscreenVideo: CoreVideoMetadata?
    
    // MARK: - Navigation Tracking
    
    @Published var currentNavigation: String = "Home"
    @Published var lastNavigationAction: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        print("NAVIGATION COORDINATOR: Initialized - Ready for app navigation")
    }
    
    // MARK: - Primary Navigation Methods
    
    /// Navigate to user profile
    func navigateToProfile(userID: String) {
        print("NAV: Navigating to profile \(userID)")
        
        // If not on progression tab, switch to it
        if selectedTab != .progression {
            selectedTab = .progression
        }
        
        // PHASE 1 FIX: Use unified notification name
        NotificationCenter.default.post(
            name: .loadUserProfile,
            object: nil,
            userInfo: ["userID": userID]
        )
        
        updateNavigationState("Profile: \(userID)")
    }
    
    /// Navigate to specific video
    func navigateToVideo(videoID: String, threadID: String? = nil) {
        print("NAV: Navigating to video \(videoID) in thread \(threadID ?? "none")")
        
        // Switch to home tab for video content
        selectedTab = .home
        
        // PHASE 1 FIX: Use unified notification name
        NotificationCenter.default.post(
            name: .scrollToVideo,
            object: nil,
            userInfo: [
                "videoID": videoID,
                "threadID": threadID as Any
            ]
        )
        
        updateNavigationState("Video: \(videoID)")
    }
    
    /// Navigate to thread conversation
    func navigateToThread(threadID: String) {
        print("NAV: Navigating to thread \(threadID)")
        
        selectedTab = .home
        
        // PHASE 1 FIX: Use unified notification name
        NotificationCenter.default.post(
            name: .focusThread,
            object: nil,
            userInfo: ["threadID": threadID]
        )
        
        updateNavigationState("Thread: \(threadID)")
    }
    
    /// Navigate to discovery with optional filter
    func navigateToDiscovery(filter: String? = nil) {
        print("NAV: Navigating to discovery with filter \(filter ?? "none")")
        
        selectedTab = .discovery
        
        if let filter = filter {
            // PHASE 1 FIX: Use unified notification name
            NotificationCenter.default.post(
                name: .setDiscoveryFilter,
                object: nil,
                userInfo: ["filter": filter]
            )
        }
        
        updateNavigationState("Discovery: \(filter ?? "all")")
    }
    
    // MARK: - Sheet Presentation
    
    /// Show video in fullscreen
    func presentVideo(_ video: CoreVideoMetadata) {
        print("NAV: Presenting fullscreen video \(video.title)")
        fullscreenVideo = video
        showingFullscreenVideo = true
        updateNavigationState("Fullscreen: \(video.title)")
    }
    
    /// Show settings
    func presentSettings() {
        print("NAV: Presenting settings")
        showingSettingsSheet = true
        updateNavigationState("Settings")
    }
    
    /// Show user profile in sheet
    func presentProfileSheet(userID: String) {
        print("NAV: Presenting profile sheet for \(userID)")
        selectedUserID = userID
        showingProfileSheet = true
        updateNavigationState("Profile Sheet: \(userID)")
    }
    
    // MARK: - Dismissal Methods
    
    /// Dismiss profile sheet
    func dismissProfileSheet() {
        print("NAV: Dismissing profile sheet")
        showingProfileSheet = false
        selectedUserID = nil
        updateNavigationState("Profile Sheet Dismissed")
    }
    
    /// Dismiss settings sheet
    func dismissSettingsSheet() {
        print("NAV: Dismissing settings sheet")
        showingSettingsSheet = false
        updateNavigationState("Settings Sheet Dismissed")
    }
    
    /// Dismiss fullscreen video
    func dismissVideo() {
        print("NAV: Dismissing fullscreen video")
        showingFullscreenVideo = false
        fullscreenVideo = nil
        updateNavigationState("Video Dismissed")
    }
    
    /// Reset all navigation state
    func resetNavigation() {
        selectedTab = .home
        showingProfileSheet = false
        showingSettingsSheet = false
        selectedUserID = nil
        showingFullscreenVideo = false
        fullscreenVideo = nil
        updateNavigationState("Navigation Reset")
    }
    
    // MARK: - Tab Navigation
    
    /// Handle tab selection with state management
    func selectTab(_ tab: MainAppTab) {
        print("NAV: Selecting tab \(tab.rawValue)")
        selectedTab = tab
        updateNavigationState("Tab: \(tab.rawValue)")
    }
    
    // MARK: - Deep Link Support
    
    /// Handle deep links from notifications or external sources
    func handleDeepLink(_ url: URL) {
        print("NAV: Handling deep link \(url)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            print("NAV: Invalid deep link format")
            return
        }
        
        switch host {
        case "video":
            if let videoID = components.queryItems?.first(where: { $0.name == "id" })?.value {
                let threadID = components.queryItems?.first(where: { $0.name == "thread" })?.value
                navigateToVideo(videoID: videoID, threadID: threadID)
            }
            
        case "profile":
            if let userID = components.queryItems?.first(where: { $0.name == "id" })?.value {
                navigateToProfile(userID: userID)
            }
            
        case "thread":
            if let threadID = components.queryItems?.first(where: { $0.name == "id" })?.value {
                navigateToThread(threadID: threadID)
            }
            
        case "discovery":
            let filter = components.queryItems?.first(where: { $0.name == "filter" })?.value
            navigateToDiscovery(filter: filter)
            
        default:
            print("NAV: Unknown deep link host: \(host)")
        }
    }
    
    /// Handle notification navigation with payload parsing
    func handleNotificationNavigation(type: String, payload: [String: Any]) {
        print("NAV: Handling notification navigation - Type: \(type)")
        
        switch type {
        case "hype", "cool", "engagement_reward":
            if let videoID = payload["videoID"] as? String {
                let threadID = payload["threadID"] as? String
                navigateToVideo(videoID: videoID, threadID: threadID)
            }
            
        case "follow", "new_follower":
            if let senderID = payload["senderID"] as? String {
                navigateToProfile(userID: senderID)
            } else if let followerID = payload["followerID"] as? String {
                navigateToProfile(userID: followerID)
            }
            
        case "reply", "video_reply":
            if let threadID = payload["threadID"] as? String {
                navigateToThread(threadID: threadID)
            } else if let videoID = payload["originalVideoID"] as? String {
                navigateToVideo(videoID: videoID)
            }
            
        case "mention":
            if let videoID = payload["videoID"] as? String {
                navigateToVideo(videoID: videoID)
            }
            
        case "badge_unlock", "tier_advancement":
            // Navigate to progression tab to show achievement
            selectedTab = .progression
            updateNavigationState("Achievement Unlocked")
            
        default:
            print("NAV: Unknown notification type: \(type)")
        }
    }
    
    // MARK: - Navigation State Management
    
    /// Update navigation state for debugging
    private func updateNavigationState(_ action: String) {
        currentNavigation = action
        lastNavigationAction = Date()
        print("NAV STATE: \(action) at \(lastNavigationAction)")
    }
    
    /// Check if currently on specific tab
    func isOnTab(_ tab: MainAppTab) -> Bool {
        selectedTab == tab
    }
    
    /// Check if navigation is in progress
    var isNavigating: Bool {
        showingProfileSheet || showingSettingsSheet || showingFullscreenVideo
    }
    
    /// Get current navigation state for debugging
    var navigationState: String {
        var components: [String] = []
        
        components.append("Tab: \(selectedTab.rawValue)")
        
        if showingProfileSheet {
            components.append("Profile Sheet: \(selectedUserID ?? "unknown")")
        }
        
        if showingSettingsSheet {
            components.append("Settings Sheet")
        }
        
        if showingFullscreenVideo {
            components.append("Fullscreen: \(fullscreenVideo?.title ?? "Unknown")")
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - Extensions for View Integration

extension NavigationCoordinator {
    
    /// Handle NotificationCenter navigation events
    func setupNotificationObservers() {
        // PHASE 1 FIX: Use unified notification names
        NotificationCenter.default.addObserver(
            forName: .navigateToVideo,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let videoID = userInfo["videoID"] as? String {
                let threadID = userInfo["threadID"] as? String
                Task { @MainActor in
                    self.navigateToVideo(videoID: videoID, threadID: threadID)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .navigateToProfile,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let userID = userInfo["userID"] as? String {
                Task { @MainActor in
                    self.navigateToProfile(userID: userID)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .navigateToThread,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let threadID = userInfo["threadID"] as? String {
                Task { @MainActor in
                    self.navigateToThread(threadID: threadID)
                }
            }
        }
    }
    
    /// Cleanup notification observers
    func cleanupObservers() {
        NotificationCenter.default.removeObserver(self)
    }
}
