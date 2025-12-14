//
//  RealtimeDataService.swift
//  StitchSocial
//
//  Created by James Garmon on 12/14/25.
//


import Foundation
import FirebaseDatabase
import FirebaseAuth

/// Service for managing real-time features using Firebase Realtime Database
class RealtimeDataService {
    static let shared = RealtimeDataService()
    
    private let database = Database.database().reference()
    private var presenceRef: DatabaseReference?
    private var observers: [DatabaseHandle] = []
    
    private init() {}
    
    // MARK: - User Presence
    
    /// Start tracking user presence
    func startPresenceTracking() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let userPresenceRef = database.child("presence").child(userId)
        
        // Set user as online
        userPresenceRef.setValue([
            "online": true,
            "lastSeen": ServerValue.timestamp()
        ])
        
        // Set offline when disconnected
        userPresenceRef.onDisconnectUpdateChildValues([
            "online": false,
            "lastSeen": ServerValue.timestamp()
        ])
        
        presenceRef = userPresenceRef
    }
    
    /// Stop tracking user presence
    func stopPresenceTracking() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let userPresenceRef = database.child("presence").child(userId)
        userPresenceRef.setValue([
            "online": false,
            "lastSeen": ServerValue.timestamp()
        ])
        
        presenceRef = nil
    }
    
    /// Observe user online status
    func observeUserPresence(userId: String, completion: @escaping (Bool, Date?) -> Void) {
        let presenceRef = database.child("presence").child(userId)
        
        let handle = presenceRef.observe(.value) { snapshot in
            guard let data = snapshot.value as? [String: Any] else {
                completion(false, nil)
                return
            }
            
            let isOnline = data["online"] as? Bool ?? false
            let lastSeenTimestamp = data["lastSeen"] as? TimeInterval
            let lastSeen = lastSeenTimestamp.map { Date(timeIntervalSince1970: $0 / 1000) }
            
            completion(isOnline, lastSeen)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Live Video Engagement
    
    /// Update live viewer count for a video
    func updateViewerCount(videoId: String, increment: Bool) {
        let viewersRef = database.child("live_engagement").child(videoId).child("viewers")
        
        viewersRef.runTransactionBlock { currentData in
            var count = currentData.value as? Int ?? 0
            count += increment ? 1 : -1
            currentData.value = max(0, count)
            return .success(withValue: currentData)
        }
    }
    
    /// Observe live viewer count for a video
    func observeViewerCount(videoId: String, completion: @escaping (Int) -> Void) {
        let viewersRef = database.child("live_engagement").child(videoId).child("viewers")
        
        let handle = viewersRef.observe(.value) { snapshot in
            let count = snapshot.value as? Int ?? 0
            completion(count)
        }
        
        observers.append(handle)
    }
    
    /// Track live reactions/hype for a video
    func addReaction(videoId: String, reactionType: String) {
        let reactionsRef = database.child("live_engagement").child(videoId).child("reactions")
        
        reactionsRef.runTransactionBlock { currentData in
            var reactions = currentData.value as? [String: Int] ?? [:]
            reactions[reactionType] = (reactions[reactionType] ?? 0) + 1
            currentData.value = reactions
            return .success(withValue: currentData)
        }
    }
    
    /// Observe live reactions for a video
    func observeReactions(videoId: String, completion: @escaping ([String: Int]) -> Void) {
        let reactionsRef = database.child("live_engagement").child(videoId).child("reactions")
        
        let handle = reactionsRef.observe(.value) { snapshot in
            let reactions = snapshot.value as? [String: Int] ?? [:]
            completion(reactions)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Live Comments/Chat
    
    /// Post a live comment on a video
    func postLiveComment(videoId: String, comment: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "RealtimeDataService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let commentsRef = database.child("live_comments").child(videoId).childByAutoId()
        
        try await commentsRef.setValue([
            "userId": userId,
            "comment": comment,
            "timestamp": ServerValue.timestamp()
        ])
    }
    
    /// Observe live comments for a video (last 50)
    func observeLiveComments(videoId: String, completion: @escaping ([LiveComment]) -> Void) {
        let commentsRef = database.child("live_comments").child(videoId)
            .queryLimited(toLast: 50)
        
        let handle = commentsRef.observe(.value) { snapshot in
            var comments: [LiveComment] = []
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      let data = childSnapshot.value as? [String: Any],
                      let userId = data["userId"] as? String,
                      let comment = data["comment"] as? String,
                      let timestamp = data["timestamp"] as? TimeInterval else {
                    continue
                }
                
                comments.append(LiveComment(
                    id: childSnapshot.key,
                    userId: userId,
                    comment: comment,
                    timestamp: Date(timeIntervalSince1970: timestamp / 1000)
                ))
            }
            
            completion(comments)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Trending/Viral Tracking
    
    /// Update trending score for a video
    func updateTrendingScore(videoId: String, score: Double) {
        let trendingRef = database.child("trending").child(videoId)
        
        trendingRef.setValue([
            "score": score,
            "timestamp": ServerValue.timestamp()
        ])
    }
    
    /// Get top trending videos
    func observeTopTrending(limit: UInt, completion: @escaping ([String]) -> Void) {
        let trendingRef = database.child("trending")
            .queryOrdered(byChild: "score")
            .queryLimited(toLast: limit)
        
        let handle = trendingRef.observe(.value) { snapshot in
            var videoIds: [String] = []
            
            for child in snapshot.children.reversed() {
                guard let childSnapshot = child as? DataSnapshot else { continue }
                videoIds.append(childSnapshot.key)
            }
            
            completion(videoIds)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Typing Indicators
    
    /// Set typing status for a thread
    func setTypingStatus(threadId: String, isTyping: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let typingRef = database.child("typing").child(threadId).child(userId)
        
        if isTyping {
            typingRef.setValue(true)
            typingRef.onDisconnectRemoveValue()
        } else {
            typingRef.removeValue()
        }
    }
    
    /// Observe typing indicators for a thread
    func observeTypingIndicators(threadId: String, completion: @escaping ([String]) -> Void) {
        let typingRef = database.child("typing").child(threadId)
        
        let handle = typingRef.observe(.value) { snapshot in
            var typingUsers: [String] = []
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      childSnapshot.value as? Bool == true else {
                    continue
                }
                typingUsers.append(childSnapshot.key)
            }
            
            completion(typingUsers)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Live Leaderboard
    
    /// Update user score in leaderboard
    func updateLeaderboardScore(userId: String, score: Int) {
        let leaderboardRef = database.child("leaderboard").child(userId)
        
        leaderboardRef.setValue([
            "score": score,
            "timestamp": ServerValue.timestamp()
        ])
    }
    
    /// Observe top leaderboard entries
    func observeLeaderboard(limit: UInt, completion: @escaping ([(userId: String, score: Int)]) -> Void) {
        let leaderboardRef = database.child("leaderboard")
            .queryOrdered(byChild: "score")
            .queryLimited(toLast: limit)
        
        let handle = leaderboardRef.observe(.value) { snapshot in
            var entries: [(userId: String, score: Int)] = []
            
            for child in snapshot.children.reversed() {
                guard let childSnapshot = child as? DataSnapshot,
                      let data = childSnapshot.value as? [String: Any],
                      let score = data["score"] as? Int else {
                    continue
                }
                entries.append((userId: childSnapshot.key, score: score))
            }
            
            completion(entries)
        }
        
        observers.append(handle)
    }
    
    // MARK: - Cleanup
    
    /// Remove all observers
    func removeAllObservers() {
        for handle in observers {
            database.removeObserver(withHandle: handle)
        }
        observers.removeAll()
    }
    
    deinit {
        removeAllObservers()
        stopPresenceTracking()
    }
}

// MARK: - Supporting Models

struct LiveComment {
    let id: String
    let userId: String
    let comment: String
    let timestamp: Date
}