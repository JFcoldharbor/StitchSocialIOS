//
//  NotificationNames.swift
//  StitchSocial
//
//  Single Source of Truth for All Notification Names
//

import Foundation

// MARK: - Unified Notification Names

extension Notification.Name {
    
    // MARK: - Player Control
    
    static let killAllVideoPlayers = Notification.Name("com.stitchsocial.killAllVideoPlayers")
    static let pauseAllVideoPlayers = Notification.Name("com.stitchsocial.pauseAllVideoPlayers")
    static let resumeVideoPlayback = Notification.Name("com.stitchsocial.resumeVideoPlayback")
    
    // MARK: - Feed Notifications
    
    static let preloadHomeFeed = Notification.Name("com.stitchsocial.preloadHomeFeed")
    static let refreshFeeds = Notification.Name("com.stitchsocial.refreshFeeds")
    static let refreshHomeFeed = Notification.Name("com.stitchsocial.refreshHomeFeed")
    static let refreshDiscovery = Notification.Name("com.stitchsocial.refreshDiscovery")
    static let refreshProfile = Notification.Name("com.stitchsocial.refreshProfile")
    
    // MARK: - Navigation Notifications
    
    static let navigateToVideo = Notification.Name("com.stitchsocial.navigateToVideo")
    static let navigateToProfile = Notification.Name("com.stitchsocial.navigateToProfile")
    static let navigateToThread = Notification.Name("com.stitchsocial.navigateToThread")
    static let navigateToNotifications = Notification.Name("com.stitchsocial.navigateToNotifications")
    static let scrollToVideo = Notification.Name("com.stitchsocial.scrollToVideo")
    static let focusThread = Notification.Name("com.stitchsocial.focusThread")
    static let loadUserProfile = Notification.Name("com.stitchsocial.loadUserProfile")
    static let setDiscoveryFilter = Notification.Name("com.stitchsocial.setDiscoveryFilter")
    
    // MARK: - Recording Notifications
    
    static let presentRecording = Notification.Name("com.stitchsocial.presentRecording")
    static let recordingCompleted = Notification.Name("com.stitchsocial.recordingCompleted")
    
    // MARK: - App State Notifications
    
    static let fullscreenModeActivated = Notification.Name("com.stitchsocial.fullscreenModeActivated")
    static let fullscreenProfileOpened = Notification.Name("com.stitchsocial.fullscreenProfileOpened")
    static let fullscreenProfileClosed = Notification.Name("com.stitchsocial.fullscreenProfileClosed")
    static let userDataCacheUpdated = Notification.Name("com.stitchsocial.userDataCacheUpdated")
    static let stopAllBackgroundActivity = Notification.Name("com.stitchsocial.stopAllBackgroundActivity")
    static let deactivateAllPlayers = Notification.Name("com.stitchsocial.deactivateAllPlayers")
    static let disableVideoAutoRestart = Notification.Name("com.stitchsocial.disableVideoAutoRestart")
    
    // MARK: - Background Activity
    
    static let killAllBackgroundTimers = Notification.Name("com.stitchsocial.killAllBackgroundTimers")
    
    // MARK: - Push Notifications
    
    static let pushNotificationReceived = Notification.Name("com.stitchsocial.pushNotificationReceived")
    static let pushNotificationTapped = Notification.Name("com.stitchsocial.pushNotificationTapped")
    
    // MARK: - Push Notification Deep Link Relay (ContentView → NotificationView)
    
    static let pushNotificationNavigateToVideo = Notification.Name("com.stitchsocial.pushNotificationNavigateToVideo")
    static let pushNotificationNavigateToProfile = Notification.Name("com.stitchsocial.pushNotificationNavigateToProfile")
    static let pushNotificationNavigateToThread = Notification.Name("com.stitchsocial.pushNotificationNavigateToThread")
    
    // MARK: - Collection Notifications
    
    static let segmentUploadCompleted = Notification.Name("com.stitchsocial.segmentUploadCompleted")
    static let segmentUploadFailed = Notification.Name("com.stitchsocial.segmentUploadFailed")
    static let collectionPublished = Notification.Name("com.stitchsocial.collectionPublished")
    static let collectionUpdated = Notification.Name("com.stitchsocial.collectionUpdated")
}

// MARK: - Notification Helper

struct MyStitchNotification {
    
    static func killAllPlayers() {
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
    }
    
    static func pauseAllPlayers() {
        NotificationCenter.default.post(name: .pauseAllVideoPlayers, object: nil)
    }
    
    static func resumePlayback() {
        NotificationCenter.default.post(name: .resumeVideoPlayback, object: nil)
    }
    
    static func stopAllVideoActivity() {
        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .pauseAllVideoPlayers, object: nil)
        NotificationCenter.default.post(name: .stopAllBackgroundActivity, object: nil)
        NotificationCenter.default.post(name: .deactivateAllPlayers, object: nil)
    }
    
    static func refreshAllFeeds(newVideoID: String? = nil) {
        var userInfo: [String: Any]? = nil
        if let videoID = newVideoID {
            userInfo = ["newVideoID": videoID]
        }
        NotificationCenter.default.post(name: .refreshFeeds, object: nil, userInfo: userInfo)
    }
    
    static func refreshProfile() {
        NotificationCenter.default.post(name: .refreshProfile, object: nil)
    }
}

// MARK: - Observer Management

class NotificationObserverBag {
    private var observers: [NSObjectProtocol] = []
    
    func add(_ observer: NSObjectProtocol) {
        observers.append(observer)
    }
    
    func removeAll() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
    
    func observe(_ name: Notification.Name, object: Any? = nil, queue: OperationQueue? = .main, using block: @escaping (Notification) -> Void) {
        let observer = NotificationCenter.default.addObserver(forName: name, object: object, queue: queue, using: block)
        add(observer)
    }
    
    deinit {
        removeAll()
    }
}
