//
//  FeedViewHistory.swift
//  StitchSocial
//
//  Layer 4: Services - Feed View History & Position Tracking
//  Features: Track seen videos, persist feed position, enable "pick up where you left off"
//

import Foundation

/// Tracks viewed videos and feed position for personalized content delivery
class FeedViewHistory {
    
    static let shared = FeedViewHistory()
    
    // MARK: - Storage Keys
    
    private let seenVideoIDsKey = "feed_seen_video_ids"
    private let feedPositionKey = "feed_position"
    private let lastSessionFeedKey = "feed_last_session"
    private let lastSessionTimestampKey = "feed_last_session_timestamp"
    private let viewHistoryTimestampsKey = "feed_view_timestamps"
    
    // MARK: - Configuration
    
    /// Maximum seen video IDs to track (rolling window)
    private let maxSeenVideoIDs = 500
    
    /// Session resume window - if user returns within this time, offer to resume
    private let resumeWindowHours: Double = 24
    
    /// How long to consider a video as "recently seen" (affects re-showing)
    private let recentlySeenHours: Double = 4
    
    private init() {
        cleanupOldHistory()
    }
    
    // MARK: - Seen Video Tracking
    
    /// Mark a video as seen
    func markVideoSeen(_ videoID: String) {
        var seenIDs = getSeenVideoIDs()
        var timestamps = getViewTimestamps()
        
        // Add if not already present
        if !seenIDs.contains(videoID) {
            seenIDs.append(videoID)
            timestamps[videoID] = Date().timeIntervalSince1970
            
            // Trim to max size (remove oldest)
            if seenIDs.count > maxSeenVideoIDs {
                let oldestID = seenIDs.removeFirst()
                timestamps.removeValue(forKey: oldestID)
            }
            
            saveSeenVideoIDs(seenIDs)
            saveViewTimestamps(timestamps)
        }
    }
    
    /// Mark multiple videos as seen
    func markVideosSeen(_ videoIDs: [String]) {
        var seenIDs = getSeenVideoIDs()
        var timestamps = getViewTimestamps()
        let now = Date().timeIntervalSince1970
        
        for videoID in videoIDs {
            if !seenIDs.contains(videoID) {
                seenIDs.append(videoID)
                timestamps[videoID] = now
            }
        }
        
        // Trim to max size
        while seenIDs.count > maxSeenVideoIDs {
            let oldestID = seenIDs.removeFirst()
            timestamps.removeValue(forKey: oldestID)
        }
        
        saveSeenVideoIDs(seenIDs)
        saveViewTimestamps(timestamps)
    }
    
    /// Check if video was seen
    func wasVideoSeen(_ videoID: String) -> Bool {
        return getSeenVideoIDs().contains(videoID)
    }
    
    /// Check if video was recently seen (within recentlySeenHours)
    func wasVideoRecentlySeen(_ videoID: String) -> Bool {
        let timestamps = getViewTimestamps()
        guard let timestamp = timestamps[videoID] else { return false }
        
        let ageHours = (Date().timeIntervalSince1970 - timestamp) / 3600
        return ageHours < recentlySeenHours
    }
    
    /// Get all seen video IDs
    func getSeenVideoIDs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: seenVideoIDsKey) ?? []
    }
    
    /// Get recently seen video IDs (for stronger exclusion)
    func getRecentlySeenVideoIDs() -> Set<String> {
        let timestamps = getViewTimestamps()
        let now = Date().timeIntervalSince1970
        let cutoff = now - (recentlySeenHours * 3600)
        
        return Set(timestamps.filter { $0.value > cutoff }.keys)
    }
    
    /// Get count of seen videos
    func seenVideoCount() -> Int {
        return getSeenVideoIDs().count
    }
    
    /// Filter out seen videos from a list
    func filterUnseenVideos(_ videoIDs: [String]) -> [String] {
        let seenSet = Set(getSeenVideoIDs())
        return videoIDs.filter { !seenSet.contains($0) }
    }
    
    /// Filter threads to exclude recently seen content
    func filterThreads(_ threads: [ThreadData], excludeRecentlySeen: Bool = true) -> [ThreadData] {
        let exclusionSet = excludeRecentlySeen ? getRecentlySeenVideoIDs() : Set(getSeenVideoIDs())
        return threads.filter { !exclusionSet.contains($0.parentVideo.id) }
    }
    
    // MARK: - Feed Position Persistence
    
    /// Save current feed position
    func saveFeedPosition(itemIndex: Int, stitchIndex: Int, threadID: String?) {
        let position = FeedPosition(
            itemIndex: itemIndex,
            stitchIndex: stitchIndex,
            threadID: threadID,
            savedAt: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(position)
            UserDefaults.standard.set(data, forKey: feedPositionKey)
            print("📍 FEED HISTORY: Saved position - item \(itemIndex), stitch \(stitchIndex)")
        } catch {
            print("❌ FEED HISTORY: Failed to save position - \(error)")
        }
    }
    
    /// Get saved feed position
    func getSavedPosition() -> FeedPosition? {
        guard let data = UserDefaults.standard.data(forKey: feedPositionKey) else {
            return nil
        }
        
        do {
            let position = try JSONDecoder().decode(FeedPosition.self, from: data)
            
            // Check if position is still valid (within resume window)
            let ageHours = Date().timeIntervalSince(position.savedAt) / 3600
            if ageHours > resumeWindowHours {
                clearFeedPosition()
                return nil
            }
            
            return position
        } catch {
            print("❌ FEED HISTORY: Failed to decode position - \(error)")
            return nil
        }
    }
    
    /// Clear saved position
    func clearFeedPosition() {
        UserDefaults.standard.removeObject(forKey: feedPositionKey)
    }
    
    // MARK: - Last Session Feed
    
    /// Save current feed for session resume
    func saveLastSessionFeed(_ threads: [ThreadData]) {
        // Only save thread IDs and essential data, not full objects
        let sessionData = threads.prefix(50).map { thread -> SessionThread in
            SessionThread(
                id: thread.id,
                parentVideoID: thread.parentVideo.id,
                creatorID: thread.parentVideo.creatorID
            )
        }
        
        do {
            let data = try JSONEncoder().encode(sessionData)
            UserDefaults.standard.set(data, forKey: lastSessionFeedKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSessionTimestampKey)
            print("💾 FEED HISTORY: Saved \(sessionData.count) threads for session resume")
        } catch {
            print("❌ FEED HISTORY: Failed to save session feed - \(error)")
        }
    }
    
    /// Get last session thread IDs (for rebuilding feed)
    func getLastSessionThreadIDs() -> [String]? {
        // Check timestamp
        guard let timestamp = UserDefaults.standard.object(forKey: lastSessionTimestampKey) as? TimeInterval else {
            return nil
        }
        
        let ageHours = (Date().timeIntervalSince1970 - timestamp) / 3600
        if ageHours > resumeWindowHours {
            clearLastSession()
            return nil
        }
        
        guard let data = UserDefaults.standard.data(forKey: lastSessionFeedKey) else {
            return nil
        }
        
        do {
            let sessionData = try JSONDecoder().decode([SessionThread].self, from: data)
            return sessionData.map { $0.id }
        } catch {
            print("❌ FEED HISTORY: Failed to decode session feed - \(error)")
            return nil
        }
    }
    
    /// Check if we can offer session resume
    func canResumeSession() -> Bool {
        guard getSavedPosition() != nil else { return false }
        guard getLastSessionThreadIDs() != nil else { return false }
        return true
    }
    
    /// Clear last session
    func clearLastSession() {
        UserDefaults.standard.removeObject(forKey: lastSessionFeedKey)
        UserDefaults.standard.removeObject(forKey: lastSessionTimestampKey)
    }
    
    // MARK: - Private Helpers
    
    private func saveSeenVideoIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: seenVideoIDsKey)
    }
    
    private func getViewTimestamps() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: viewHistoryTimestampsKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }
    
    private func saveViewTimestamps(_ timestamps: [String: TimeInterval]) {
        if let data = try? JSONEncoder().encode(timestamps) {
            UserDefaults.standard.set(data, forKey: viewHistoryTimestampsKey)
        }
    }
    
    /// Clean up old history entries
    private func cleanupOldHistory() {
        var timestamps = getViewTimestamps()
        let cutoff = Date().timeIntervalSince1970 - (72 * 3600) // 72 hours
        
        let oldKeys = timestamps.filter { $0.value < cutoff }.keys
        for key in oldKeys {
            timestamps.removeValue(forKey: key)
        }
        
        if !oldKeys.isEmpty {
            saveViewTimestamps(timestamps)
            
            // Also clean up seenIDs to match
            var seenIDs = getSeenVideoIDs()
            seenIDs.removeAll { oldKeys.contains($0) }
            saveSeenVideoIDs(seenIDs)
            
            print("🧹 FEED HISTORY: Cleaned \(oldKeys.count) old entries")
        }
    }
    
    // MARK: - Reset
    
    /// Clear all history (for testing or user request)
    func clearAllHistory() {
        UserDefaults.standard.removeObject(forKey: seenVideoIDsKey)
        UserDefaults.standard.removeObject(forKey: feedPositionKey)
        UserDefaults.standard.removeObject(forKey: lastSessionFeedKey)
        UserDefaults.standard.removeObject(forKey: lastSessionTimestampKey)
        UserDefaults.standard.removeObject(forKey: viewHistoryTimestampsKey)
        print("🗑️ FEED HISTORY: Cleared all history")
    }
    
    // MARK: - Debug
    
    func debugStatus() -> String {
        let seenCount = seenVideoCount()
        let recentCount = getRecentlySeenVideoIDs().count
        let hasPosition = getSavedPosition() != nil
        let canResume = canResumeSession()
        
        return """
        📊 Feed History Status:
        - Seen videos: \(seenCount)
        - Recently seen: \(recentCount)
        - Has saved position: \(hasPosition)
        - Can resume: \(canResume)
        """
    }
}

// MARK: - Supporting Types

struct FeedPosition: Codable {
    let itemIndex: Int
    let stitchIndex: Int
    let threadID: String?
    let savedAt: Date
}

struct SessionThread: Codable {
    let id: String
    let parentVideoID: String
    let creatorID: String
}
