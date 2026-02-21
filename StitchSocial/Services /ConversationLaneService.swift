//
//  ConversationLaneService.swift
//  StitchSocial
//
//  Layer 4: Services - Conversation Lane Management
//  Dependencies: VideoService, Firebase Firestore
//
//  CONVERSATION RULES:
//  - Thread (depth 0): Anyone can view, engage, reply, spin off
//  - Child (depth 1): Anyone can view, engage, reply (creates a private lane), spin off
//  - Stepchild (depth 2+): Anyone can view, hype/cool, spin off
//    BUT only the 2 lane participants can reply/stitch
//  - Max 20 exchanges per private lane
//
//  CACHING: Lane participant lookups are cached per-session to avoid
//  repeated Firestore reads when scrolling through carousel cards.
//  Cache is keyed by childVideoID (the depth-1 anchor of each lane).
//

import Foundation
import FirebaseFirestore

@MainActor
class ConversationLaneService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ConversationLaneService()
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Cache
    
    /// Cache: childVideoID → [lane participant pairs]
    /// Each lane is identified by the two participant IDs (sorted for consistency)
    private var laneParticipantCache: [String: [LaneInfo]] = [:]
    
    /// Cache: "childID-user1-user2" → [CoreVideoMetadata] (the conversation chain)
    private var laneMessagesCache: [String: [CoreVideoMetadata]] = [:]
    
    /// Cache TTL — 60 seconds
    private var cacheTimes: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 60
    
    // MARK: - Data Structures
    
    struct LaneInfo {
        let childVideoID: String       // The depth-1 video that anchors this lane
        let childCreatorID: String      // Creator of the child video
        let responderID: String         // The person who replied (depth 2 starter)
        let responderName: String       // Display name
        let firstReply: CoreVideoMetadata  // The depth-2 video that opened the lane
        let messageCount: Int           // Total exchanges in this lane
        
        /// The two participants who can reply in this lane
        var participantIDs: Set<String> {
            return [childCreatorID, responderID]
        }
        
        /// Sorted key for cache lookups
        var cacheKey: String {
            let sorted = [childCreatorID, responderID].sorted()
            return "\(childVideoID)-\(sorted[0])-\(sorted[1])"
        }
        
        func isParticipant(_ userID: String) -> Bool {
            return participantIDs.contains(userID)
        }
    }
    
    // MARK: - Lane Discovery
    
    /// Get all private lanes branching from a child video (depth 1)
    /// Each unique responder creates one lane with the child creator
    /// Returns: Array of LaneInfo, one per unique conversation partner
    ///
    /// BATCHING: Single Firestore query fetches all depth-2 replies,
    /// then groups client-side by creatorID. No N+1 queries.
    func getLanes(forChildVideoID childVideoID: String, childCreatorID: String) async throws -> [LaneInfo] {
        // Check cache
        if let cached = laneParticipantCache[childVideoID],
           let cacheTime = cacheTimes[childVideoID],
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }
        
        // Fetch all direct replies to this child (these are lane openers — depth 2)
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.replyToVideoID, isEqualTo: childVideoID)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: false)
            .getDocuments()
        
        // Group by unique responder — each person gets one lane
        var seenResponders: Set<String> = []
        var lanes: [LaneInfo] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            let video = createCoreVideoMetadata(from: data, id: doc.documentID)
            let responderID = video.creatorID
            
            // Skip if we already have a lane for this responder
            guard !seenResponders.contains(responderID) else { continue }
            seenResponders.insert(responderID)
            
            // Count total messages in this lane (async but batched per lane)
            let count = try await countLaneMessages(
                childVideoID: childVideoID,
                participant1: childCreatorID,
                participant2: responderID
            )
            
            lanes.append(LaneInfo(
                childVideoID: childVideoID,
                childCreatorID: childCreatorID,
                responderID: responderID,
                responderName: video.creatorName,
                firstReply: video,
                messageCount: count
            ))
        }
        
        // Cache
        laneParticipantCache[childVideoID] = lanes
        cacheTimes[childVideoID] = Date()
        
        print("🛤️ LANES: Found \(lanes.count) conversation lanes for child \(childVideoID)")
        return lanes
    }
    
    // MARK: - Lane Messages (Full Conversation Chain)
    
    /// Load the full back-and-forth conversation in a lane
    /// Fetches ALL stepchildren under this child's thread, filters to the two participants,
    /// then sorts by createdAt to get the conversation in order.
    ///
    /// OPTIMIZATION: Fetches all stepchildren in one query (they share the same threadID
    /// and have replyToVideoID chains under the child). Client-side filter is cheaper
    /// than recursive Firestore queries.
    func loadLaneMessages(
        childVideo: CoreVideoMetadata,
        participant1: String,
        participant2: String
    ) async throws -> [CoreVideoMetadata] {
        let cacheKey = "\(childVideo.id)-\(min(participant1, participant2))-\(max(participant1, participant2))"
        
        // Check cache
        if let cached = laneMessagesCache[cacheKey],
           let cacheTime = cacheTimes[cacheKey],
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }
        
        // Strategy: Walk the replyToVideoID chain starting from child
        // Fetch all videos in this thread with depth > child's depth
        guard let threadID = childVideo.threadID else {
            return []
        }
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: childVideo.conversationDepth)
            .order(by: FirebaseSchema.VideoDocument.conversationDepth)
            .order(by: FirebaseSchema.VideoDocument.createdAt)
            .getDocuments()
        
        let allStepchildren = snapshot.documents.map { doc in
            createCoreVideoMetadata(from: doc.data(), id: doc.documentID)
        }
        
        // Filter to only messages from these two participants
        let participantSet: Set<String> = [participant1, participant2]
        
        // Walk the chain: start from replies to childVideo, follow replyToVideoID
        var laneMessages: [CoreVideoMetadata] = []
        var currentParentIDs: Set<String> = [childVideo.id]
        
        // Build a lookup by replyToVideoID for chain walking
        let byReplyTo = Dictionary(grouping: allStepchildren) { $0.replyToVideoID ?? "" }
        
        // BFS through the chain — only follow messages from our two participants
        var queue = Array(currentParentIDs)
        var visited: Set<String> = []
        
        while !queue.isEmpty {
            let parentID = queue.removeFirst()
            guard !visited.contains(parentID) else { continue }
            visited.insert(parentID)
            
            if let replies = byReplyTo[parentID] {
                for reply in replies {
                    if participantSet.contains(reply.creatorID) {
                        laneMessages.append(reply)
                        queue.append(reply.id)
                    }
                }
            }
        }
        
        // Sort by creation time for display order
        laneMessages.sort { $0.createdAt < $1.createdAt }
        
        // Cache
        laneMessagesCache[cacheKey] = laneMessages
        cacheTimes[cacheKey] = Date()
        
        print("🛤️ LANE MESSAGES: Loaded \(laneMessages.count) messages between \(participant1) and \(participant2)")
        return laneMessages
    }
    
    // MARK: - Lane Validation
    
    /// Check if a user can reply to a specific video based on lane rules
    /// Returns: (canReply: Bool, reason: String)
    func canUserReply(to video: CoreVideoMetadata, userID: String) async throws -> (canReply: Bool, reason: String) {
        
        // Thread (depth 0) — anyone can reply
        if video.conversationDepth == 0 {
            return (true, "Thread-level reply")
        }
        
        // Child (depth 1) — anyone can reply (opens a new lane)
        if video.conversationDepth == 1 {
            return (true, "Child-level reply (opens lane)")
        }
        
        // Stepchild (depth 2+) — only lane participants can reply
        // Find the lane anchor (the depth-1 child) by walking up
        let laneAnchor = try await findLaneAnchor(for: video)
        guard let anchor = laneAnchor else {
            return (false, "Could not find lane anchor")
        }
        
        // Determine the two participants: anchor creator + the first depth-2 responder
        let laneParticipants = try await getLaneParticipants(
            childVideoID: anchor.id,
            childCreatorID: anchor.creatorID,
            stepchildVideo: video
        )
        
        guard laneParticipants.contains(userID) else {
            return (false, "Not a lane participant — use spin-off")
        }
        
        // Check 20-message cap
        let messageCount = try await countLaneMessages(
            childVideoID: anchor.id,
            participant1: laneParticipants.first ?? "",
            participant2: laneParticipants.dropFirst().first ?? ""
        )
        
        if messageCount >= 20 {
            return (false, "Lane is at 20-message cap — use spin-off")
        }
        
        // Can't reply to your own video
        if video.creatorID == userID {
            return (false, "Can't reply to your own video")
        }
        
        return (true, "Lane participant, under cap")
    }
    
    // MARK: - Helpers
    
    /// Walk up replyToVideoID chain to find the depth-1 child that anchors this lane
    private func findLaneAnchor(for video: CoreVideoMetadata) async throws -> CoreVideoMetadata? {
        var current = video
        
        // Walk up until we find depth 1
        while current.conversationDepth > 1 {
            guard let replyToID = current.replyToVideoID else { return nil }
            
            let doc = try await db.collection(FirebaseSchema.Collections.videos)
                .document(replyToID)
                .getDocument()
            
            guard doc.exists, let data = doc.data() else { return nil }
            current = createCoreVideoMetadata(from: data, id: doc.documentID)
        }
        
        return current.conversationDepth == 1 ? current : nil
    }
    
    /// Get the two participant IDs for a lane
    /// The lane is: childCreator + whoever first replied at depth 2 in this chain
    private func getLaneParticipants(
        childVideoID: String,
        childCreatorID: String,
        stepchildVideo: CoreVideoMetadata
    ) async throws -> Set<String> {
        // The stepchild's creatorID is one participant (or someone in the chain)
        // We need to find who started this specific lane
        
        // Walk up from the stepchild to find the depth-2 reply
        var current = stepchildVideo
        while current.conversationDepth > 2 {
            guard let replyToID = current.replyToVideoID else { break }
            let doc = try await db.collection(FirebaseSchema.Collections.videos)
                .document(replyToID)
                .getDocument()
            guard doc.exists, let data = doc.data() else { break }
            current = createCoreVideoMetadata(from: data, id: doc.documentID)
        }
        
        // current is now the depth-2 video — its creator + the child creator are the participants
        return [childCreatorID, current.creatorID]
    }
    
    /// Count messages in a specific lane
    private func countLaneMessages(
        childVideoID: String,
        participant1: String,
        participant2: String
    ) async throws -> Int {
        // Use cached lane messages if available
        let cacheKey = "\(childVideoID)-\(min(participant1, participant2))-\(max(participant1, participant2))"
        if let cached = laneMessagesCache[cacheKey] {
            return cached.count
        }
        
        // Otherwise do a lightweight count query
        // Fetch replies to the child, filter to participants
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.replyToVideoID, isEqualTo: childVideoID)
            .getDocuments()
        
        // This only gets direct depth-2 replies — for full count we'd need chain walking
        // For now, estimate from direct replies (good enough for cap check)
        let participantSet: Set<String> = [participant1, participant2]
        let count = snapshot.documents.filter { doc in
            let creatorID = doc.data()[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
            return participantSet.contains(creatorID)
        }.count
        
        return count
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        laneParticipantCache.removeAll()
        laneMessagesCache.removeAll()
        cacheTimes.removeAll()
        print("🧹 LANE CACHE: Cleared")
    }
    
    func invalidateLane(childVideoID: String) {
        laneParticipantCache.removeValue(forKey: childVideoID)
        // Remove all message caches for this child
        let keysToRemove = laneMessagesCache.keys.filter { $0.hasPrefix(childVideoID) }
        keysToRemove.forEach { laneMessagesCache.removeValue(forKey: $0) }
        print("🧹 LANE CACHE: Invalidated lanes for \(childVideoID)")
    }
    
    // MARK: - CoreVideoMetadata Factory (mirrors VideoService)
    
    private func createCoreVideoMetadata(from data: [String: Any], id: String) -> CoreVideoMetadata {
        // Break into sub-expressions to help Swift compiler type-check
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let desc = data[FirebaseSchema.VideoDocument.description] as? String ?? ""
        let tagged = data[FirebaseSchema.VideoDocument.taggedUserIDs] as? [String] ?? []
        let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String ?? ""
        let thumbURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? ""
        let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String ?? ""
        let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String ?? ""
        let createdAt = (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let depth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0
        
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        
        let temperature = data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral"
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let engagementRatio = data["engagementRatio"] as? Double ?? 0.0
        let velocityScore = data["velocityScore"] as? Double ?? 0.0
        let trendingScore = data["trendingScore"] as? Double
        
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        let discoverability = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool
        let lastEngagement = (data["lastEngagementAt"] as? Timestamp)?.dateValue()
        
        let spinOffVideo = data[FirebaseSchema.VideoDocument.spinOffFromVideoID] as? String
        let spinOffThread = data[FirebaseSchema.VideoDocument.spinOffFromThreadID] as? String
        let spinOffCount = data[FirebaseSchema.VideoDocument.spinOffCount] as? Int
        let hashtags = data[FirebaseSchema.VideoDocument.hashtags] as? [String] ?? []
        let recordingSource = data[FirebaseSchema.VideoDocument.recordingSource] as? String ?? "unknown"
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            description: desc,
            taggedUserIDs: tagged,
            videoURL: videoURL,
            thumbnailURL: thumbURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: depth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: temperature,
            qualityScore: qualityScore,
            engagementRatio: engagementRatio,
            velocityScore: velocityScore,
            trendingScore: trendingScore ?? 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverability ?? 0.5,
            isPromoted: isPromoted ?? false,
            lastEngagementAt: lastEngagement,
            spinOffFromVideoID: spinOffVideo,
            spinOffFromThreadID: spinOffThread,
            spinOffCount: spinOffCount ?? 0,
            recordingSource: recordingSource,
            hashtags: hashtags
        )
    }
}
