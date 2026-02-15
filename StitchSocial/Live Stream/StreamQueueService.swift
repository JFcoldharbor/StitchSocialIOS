//
//  StreamQueueService.swift
//  StitchSocial
//
//  Layer 6: Services - Video Comment Queue Management
//  Dependencies: LiveStreamTypes, CommunityXPService
//  Features: Submit video comments, priority queue, accept/reject, PiP state
//
//  CACHING:
//  - Queue listener: Single Firestore listener on creator device ONLY
//  - Viewers don't listen to queue — only see accepted PiP overlay
//  - activePiP: Local state, set when creator accepts, cleared after display
//  - Video URLs: Cache locally for overlay duration, purge on dismiss
//
//  BATCHING:
//  - Video upload goes to Storage, only URL reference stored in Firestore
//  - Accept = 1 batched write (status update + stream videoComment count + XP award)
//  - Reject = 1 write (status update only)
//  - Queue cleanup: Cloud Function on stream end expires all pending
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class StreamQueueService: ObservableObject {
    
    static let shared = StreamQueueService()
    
    // MARK: - Published State
    
    @Published var pendingComments: [VideoComment] = []
    @Published var activePiP: VideoComment?         // Currently displayed on stream
    @Published var queueCount: Int = 0
    
    // MARK: - Private
    
    private let db = FirebaseConfig.firestore
    private var queueListener: ListenerRegistration?
    
    private struct Paths {
        static func comments(_ creatorID: String, _ streamID: String) -> String {
            "communities/\(creatorID)/streams/\(streamID)/videoComments"
        }
    }
    
    private init() {}
    
    // MARK: - Submit Video Comment (Viewer)
    
    /// Viewer submits a video comment to the queue
    /// Video must already be uploaded to Storage — pass URL only
    func submitVideoComment(
        streamID: String,
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        videoURL: String,
        durationSeconds: Int,
        caption: String = "",
        isPriority: Bool = false,
        priorityCoinsCost: Int = 0
    ) async throws -> VideoComment {
        
        // Level gate
        guard authorLevel >= VideoComment.minimumLevel else {
            throw QueueError.levelTooLow(current: authorLevel, required: VideoComment.minimumLevel)
        }
        
        // Enforce max clip duration for level
        let maxClip = VideoComment.maxClipSeconds(forLevel: authorLevel)
        let clampedDuration = min(durationSeconds, maxClip)
        
        let comment = VideoComment(
            streamID: streamID,
            communityID: communityID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorLevel: authorLevel,
            videoURL: videoURL,
            durationSeconds: clampedDuration,
            caption: caption,
            isPriority: isPriority,
            priorityCoinsCost: priorityCoinsCost
        )
        
        let docRef = db.collection(Paths.comments(communityID, streamID)).document(comment.id)
        try docRef.setData(from: comment)
        
        // Award submission XP through buffer
        // attendedLive source = 50 XP, multiplier 0.5 = 25 XP for submission
        CommunityXPService.shared.awardXP(
            userID: authorID,
            communityID: communityID,
            source: .attendedLive,
            multiplier: 0.5
        )
        
        print("📹 QUEUE: Video comment submitted by @\(authorUsername) (Lv \(authorLevel))")
        return comment
    }
    
    // MARK: - Accept Video Comment (Creator)
    
    func acceptComment(
        commentID: String,
        communityID: String,
        streamID: String
    ) async throws {
        let batch = db.batch()
        
        let commentRef = db.collection(Paths.comments(communityID, streamID)).document(commentID)
        batch.updateData([
            "status": VideoCommentStatus.accepted.rawValue,
            "reviewedAt": Timestamp(date: Date())
        ], forDocument: commentRef)
        
        // Increment stream accepted count
        let streamRef = db.document("communities/\(communityID)/streams/\(streamID)")
        batch.updateData([
            "acceptedVideoComments": FieldValue.increment(Int64(1))
        ], forDocument: streamRef)
        
        try await batch.commit()
        
        // Find the comment in local state and set as active PiP
        if let comment = pendingComments.first(where: { $0.id == commentID }) {
            var accepted = comment
            accepted.status = .accepted
            accepted.reviewedAt = Date()
            self.activePiP = accepted
            
            // Remove from pending list
            pendingComments.removeAll { $0.id == commentID }
            queueCount = pendingComments.count
            
            // Award accepted XP to the author
            // attendedLive = 50 XP base, multiplier 3.0 = 150 XP accepted, 6.0 = 300 XP marathon+
            let tier = LiveStreamService.shared.activeStream?.durationTier ?? .spark
            let isMarathonPlus = tier.rawValue >= StreamDurationTier.marathon.rawValue
            let xpMultiplier = isMarathonPlus ? 6.0 : 3.0
            CommunityXPService.shared.awardXP(
                userID: comment.authorID,
                communityID: communityID,
                source: .attendedLive,
                multiplier: xpMultiplier
            )
            
            print("✅ QUEUE: Accepted @\(comment.authorUsername)'s video comment")
        }
    }
    
    // MARK: - Mark as Displayed (After PiP Shows)
    
    func markDisplayed(commentID: String, communityID: String, streamID: String) async {
        try? await db.collection(Paths.comments(communityID, streamID))
            .document(commentID)
            .updateData([
                "status": VideoCommentStatus.displayed.rawValue,
                "displayedAt": Timestamp(date: Date())
            ])
        
        if activePiP?.id == commentID {
            activePiP = nil
        }
    }
    
    // MARK: - Reject Video Comment (Creator)
    
    func rejectComment(
        commentID: String,
        communityID: String,
        streamID: String
    ) async throws {
        try await db.collection(Paths.comments(communityID, streamID))
            .document(commentID)
            .updateData([
                "status": VideoCommentStatus.rejected.rawValue,
                "reviewedAt": Timestamp(date: Date())
            ])
        
        pendingComments.removeAll { $0.id == commentID }
        queueCount = pendingComments.count
        
        print("❌ QUEUE: Rejected video comment \(commentID)")
    }
    
    // MARK: - Queue Listener (Creator Device Only)
    
    /// Only the creator listens to the queue — viewers don't need it
    /// Ordered: priority first, then by submission time
    func listenToQueue(communityID: String, streamID: String) {
        removeQueueListener()
        
        queueListener = db.collection(Paths.comments(communityID, streamID))
            .whereField("status", isEqualTo: VideoCommentStatus.pending.rawValue)
            .order(by: "isPriority", descending: true)
            .order(by: "submittedAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents else { return }
                
                Task { @MainActor in
                    self.pendingComments = docs.compactMap {
                        try? $0.data(as: VideoComment.self)
                    }
                    self.queueCount = self.pendingComments.count
                }
            }
    }
    
    func removeQueueListener() {
        queueListener?.remove()
        queueListener = nil
    }
    
    // MARK: - Dismiss PiP
    
    func dismissPiP() {
        if let pip = activePiP {
            Task {
                await markDisplayed(
                    commentID: pip.id,
                    communityID: pip.communityID,
                    streamID: pip.streamID
                )
            }
        }
        activePiP = nil
    }
    
    // MARK: - Cleanup
    
    func onStreamEnd() {
        removeQueueListener()
        pendingComments = []
        activePiP = nil
        queueCount = 0
    }
    
    func onLogout() {
        onStreamEnd()
    }
}

// MARK: - Errors

enum QueueError: LocalizedError {
    case levelTooLow(current: Int, required: Int)
    case streamNotLive
    case alreadySubmitted
    
    var errorDescription: String? {
        switch self {
        case .levelTooLow(let current, let required):
            return "Reach Level \(required) to submit video comments (you're Level \(current))"
        case .streamNotLive:
            return "Stream has ended"
        case .alreadySubmitted:
            return "You already have a pending video comment"
        }
    }
}
