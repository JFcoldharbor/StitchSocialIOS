//
//  LiveStreamService.swift
//  StitchSocial
//
//  Layer 6: Services - Live Stream Management
//  Dependencies: LiveStreamTypes, CommunityTypes, CommunityService, CommunityXPService
//  Features: Start/end stream, duration gate validation, completion tracking,
//            viewer attendance, heartbeats, post-stream recap
//
//  CACHING:
//  - activeStream: Single cached LiveStream per community, real-time listener
//  - completionCache: Creator's completion history, 10-min TTL (small doc set)
//  - durationGateCache: Gate results per tier, invalidate on stream end
//  - viewerAttendance: Local PendingHeartbeatBuffer, sync every 5 min
//
//  BATCHING:
//  - Viewer heartbeats: Local buffer, single Firestore write every 5 min
//  - Viewer count: FieldValue.increment on join/leave, not read-then-write
//  - Post-stream XP: Cloud Function batch on stream end, not per-viewer client write
//  - Completion record: Single write on stream end
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import Combine

@MainActor
class LiveStreamService: ObservableObject {
    
    static let shared = LiveStreamService()
    
    // MARK: - Published State
    
    @Published var activeStream: LiveStream?
    @Published var isStreaming: Bool = false
    @Published var viewerCount: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var collectiveCoinsTotal: Int = 0
    
    // MARK: - Private
    
    private let db = FirebaseConfig.firestore
    private var streamListener: ListenerRegistration?
    private var streamTimer: Timer?
    private var heartbeatTimer: Timer?
    private var heartbeatBuffer = PendingHeartbeatBuffer()
    
    // Cache
    private var completionCache: [String: CachedItem<[StreamCompletionRecord]>] = [:]
    private var durationGateCache: [String: [StreamDurationTier: StreamDurationGateResult]] = [:]
    private let completionTTL: TimeInterval = 600 // 10 min
    
    private struct CachedItem<T> {
        let value: T
        let cachedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(cachedAt) > ttl }
    }
    
    // Firestore paths
    private struct Paths {
        static func streams(_ creatorID: String) -> String {
            "communities/\(creatorID)/streams"
        }
        static func stream(_ creatorID: String, _ streamID: String) -> String {
            "communities/\(creatorID)/streams/\(streamID)"
        }
        static func attendance(_ creatorID: String, _ streamID: String) -> String {
            "communities/\(creatorID)/streams/\(streamID)/attendance"
        }
        static func completions(_ creatorID: String) -> String {
            "users/\(creatorID)/streamCompletions"
        }
    }
    
    private init() {}
    
    // MARK: - Start Stream (Creator)
    
    /// Validates duration gate, creates stream doc, starts timers
    func startStream(
        creatorID: String,
        tier: StreamDurationTier
    ) async throws -> LiveStream {
        
        // Validate duration gate
        let gate = try await checkDurationGate(
            creatorID: creatorID,
            tier: tier
        )
        
        guard gate.isUnlocked else {
            throw LiveStreamError.tierLocked(gate)
        }
        
        // Check no active stream already
        if activeStream != nil {
            throw LiveStreamError.alreadyStreaming
        }
        
        // Check cooldown (1 hr after full completion, skip if last was <5 min)
        let completions = try await fetchCompletions(creatorID: creatorID)
        let cooldown = StreamDailyLimits.cooldownRemaining(from: completions)
        if cooldown > 0 {
            throw LiveStreamError.onCooldown(remainingSeconds: Int(cooldown))
        }
        
        let stream = LiveStream(creatorID: creatorID, durationTier: tier)
        
        let docRef = db.collection(Paths.streams(creatorID)).document(stream.id)
        try docRef.setData(from: stream)
        
        // Update community isCreatorLive flag
        try await db.collection("communities").document(creatorID).updateData([
            "isCreatorLive": true,
            "activeStreamID": stream.id
        ])
        
        self.activeStream = stream
        self.isStreaming = true
        self.viewerCount = 0
        self.collectiveCoinsTotal = 0
        
        startStreamTimer()
        startCreatorHeartbeat(creatorID: creatorID, streamID: stream.id)
        
        // Send go-live notification to community members (fire-and-forget)
        Task {
            await sendGoLiveNotification(creatorID: creatorID, streamID: stream.id)
        }
        
        print("✅ STREAM: Started \(tier.displayName) for \(creatorID)")
        return stream
    }
    
    /// Notify community members that creator went live
    /// Cost: 1 read (members query) + 1 write per member (notification doc)
    private func sendGoLiveNotification(creatorID: String, streamID: String) async {
        do {
            let membersSnap = try await db.collection("communities")
                .document(creatorID)
                .collection("members")
                .limit(to: 200)
                .getDocuments()
            
            let batch = db.batch()
            for doc in membersSnap.documents {
                let memberID = doc.documentID
                guard memberID != creatorID else { continue }
                
                let notifRef = db.collection("notifications").document()
                batch.setData([
                    "id": notifRef.documentID,
                    "recipientID": memberID,
                    "senderID": creatorID,
                    "type": "go_live",
                    "title": "🔴 Creator is LIVE!",
                    "message": "Tap to join the stream",
                    "payload": [
                        "communityID": creatorID,
                        "streamID": streamID
                    ],
                    "isRead": false,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: notifRef)
            }
            try await batch.commit()
            print("📢 STREAM: Sent go-live notification to \(membersSnap.documents.count) members")
        } catch {
            print("⚠️ STREAM: Go-live notification failed - \(error.localizedDescription)")
        }
    }
    
    // MARK: - End Stream (Creator)
    
    func endStream(creatorID: String) async throws -> StreamCompletionRecord? {
        guard var stream = activeStream else {
            throw LiveStreamError.noActiveStream
        }
        
        stream.status = .ended
        stream.endedAt = Date()
        
        let docRef = db.document(Paths.stream(creatorID, stream.id))
        try await docRef.updateData([
            "status": StreamStatus.ended.rawValue,
            "endedAt": Timestamp(date: stream.endedAt!),
            "viewerCount": 0
        ])
        
        // Clear community live flag
        try await db.collection("communities").document(creatorID).updateData([
            "isCreatorLive": false,
            "activeStreamID": FieldValue.delete()
        ])
        
        // Write completion record (check daily cap)
        let completions = (try? await fetchCompletions(creatorID: creatorID)) ?? []
        let pastCap = StreamDailyLimits.isPastDailyCap(from: completions)
        let completion = StreamCompletionRecord(stream: stream, countsTowardGate: !pastCap)
        let completionRef = db.collection(Paths.completions(creatorID)).document(completion.id)
        try completionRef.setData(from: completion)
        
        // Invalidate caches
        completionCache.removeValue(forKey: creatorID)
        durationGateCache.removeValue(forKey: creatorID)
        
        // Cleanup
        stopStreamTimer()
        stopCreatorHeartbeat()
        removeStreamListener()
        
        self.activeStream = nil
        self.isStreaming = false
        
        // Delete all ephemeral stream data (fire-and-forget)
        // Chat, video comments, viewer list, then the stream doc itself.
        // Only the completion record persists.
        Task {
            await purgeStreamData(creatorID: creatorID, streamID: stream.id)
        }
        
        print("✅ STREAM: Ended \(stream.durationTier.displayName) — \(stream.elapsedSeconds)s elapsed, full: \(completion.isFullCompletion)")
        return completion
    }
    
    // MARK: - Purge Stream Data (No VOD)
    
    /// Deletes ALL ephemeral stream data after stream ends.
    /// Streams are live-only — no playback, no archive.
    /// Only StreamCompletionRecord survives for XP/badge history.
    ///
    /// Deletes:
    /// - chat subcollection (all messages)
    /// - videoComments subcollection (all docs)
    /// - video comment files in Storage (clips + thumbnails)
    /// - viewer subcollection
    /// - the stream document itself
    ///
    /// Cost: N reads for subcollection queries + N deletes. Runs async after dismiss.
    private func purgeStreamData(creatorID: String, streamID: String) async {
        let streamPath = "communities/\(creatorID)/streams/\(streamID)"
        
        // 1. Delete chat messages
        await deleteSubcollection(path: "\(streamPath)/chat")
        
        // 2. Delete video comments + their Storage files
        await deleteVideoComments(creatorID: creatorID, streamID: streamID)
        
        // 3. Delete viewer list
        await deleteSubcollection(path: "\(streamPath)/viewers")
        
        // 4. Delete the stream doc itself
        try? await db.document(streamPath).delete()
        
        print("🗑️ STREAM: Purged all data for stream \(streamID)")
    }
    
    /// Delete all docs in a subcollection. Batches of 100.
    /// Cost: 1 query + N/100 batch deletes
    private func deleteSubcollection(path: String) async {
        do {
            var hasMore = true
            while hasMore {
                let snapshot = try await db.collection(path)
                    .limit(to: 100)
                    .getDocuments()
                
                if snapshot.documents.isEmpty {
                    hasMore = false
                    break
                }
                
                let batch = db.batch()
                for doc in snapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                try await batch.commit()
                
                hasMore = snapshot.documents.count == 100
            }
        } catch {
            print("⚠️ STREAM PURGE: Failed to delete \(path) — \(error.localizedDescription)")
        }
    }
    
    /// Delete video comment docs + their Storage files (clips + thumbnails)
    /// Cost: 1 query + N Storage deletes + N/100 batch Firestore deletes
    private func deleteVideoComments(creatorID: String, streamID: String) async {
        let path = "communities/\(creatorID)/streams/\(streamID)/videoComments"
        let storage = Storage.storage()
        
        do {
            let snapshot = try await db.collection(path).getDocuments()
            
            // Delete Storage files for each comment
            for doc in snapshot.documents {
                let commentID = doc.documentID
                let clipRef = storage.reference().child("stream-clips/\(creatorID)/\(streamID)/\(commentID).mp4")
                let thumbRef = storage.reference().child("stream-clips/\(creatorID)/\(streamID)/\(commentID)_thumb.jpg")
                
                try? await clipRef.delete()
                try? await thumbRef.delete()
            }
            
            // Delete Firestore docs in batches
            if !snapshot.documents.isEmpty {
                let batch = db.batch()
                for doc in snapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                try await batch.commit()
            }
            
            if !snapshot.documents.isEmpty {
                print("🗑️ STREAM: Deleted \(snapshot.documents.count) video comments + Storage files")
            }
        } catch {
            print("⚠️ STREAM PURGE: Failed to delete video comments — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Daily Stream Status (for UI)
    
    /// Returns today's stream count, remaining completions, cooldown, and XP multiplier.
    /// Cost: Uses cached completions — 0 reads if warm, 1 read if cold.
    func getDailyStreamStatus(creatorID: String) async throws -> DailyStreamStatus {
        let completions = try await fetchCompletions(creatorID: creatorID)
        let todayCount = StreamDailyLimits.todaysCompletionCount(from: completions)
        let cooldown = StreamDailyLimits.cooldownRemaining(from: completions)
        let pastCap = StreamDailyLimits.isPastDailyCap(from: completions)
        let xpMultiplier = StreamDailyLimits.xpMultiplier(from: completions)
        
        return DailyStreamStatus(
            completionsToday: todayCount,
            maxCompletionsPerDay: StreamDailyLimits.maxCompletionsPerDay,
            cooldownRemainingSeconds: Int(cooldown),
            isPastDailyCap: pastCap,
            xpMultiplier: xpMultiplier
        )
    }
    
    // MARK: - Duration Gate Validation
    
    /// Pure logic check — uses cached completions
    /// Returns gate result with level/completion status
    func checkDurationGate(
        creatorID: String,
        tier: StreamDurationTier
    ) async throws -> StreamDurationGateResult {
        
        // Check cache first
        if let cached = durationGateCache[creatorID]?[tier] {
            return cached
        }
        
        // Get creator's community level
        let membership = try await CommunityService.shared.fetchMembership(
            userID: creatorID,
            creatorID: creatorID
        )
        let currentLevel = membership?.level ?? 0
        let levelMet = currentLevel >= tier.requiredLevel
        
        // Get completion history
        let completions = try await fetchCompletions(creatorID: creatorID)
        
        var completionsMet = true
        var currentCompletions = 0
        
        if let prevTier = tier.previousTier {
            let prevCompletions = completions.filter {
                $0.tier == prevTier && $0.isFullCompletion && $0.countsTowardGate
            }
            currentCompletions = prevCompletions.count
            completionsMet = currentCompletions >= tier.completionsRequired
        }
        
        let result = StreamDurationGateResult(
            tier: tier,
            isUnlocked: levelMet && completionsMet,
            levelMet: levelMet,
            completionsMet: completionsMet,
            currentCompletions: currentCompletions,
            requiredCompletions: tier.completionsRequired,
            currentLevel: currentLevel,
            requiredLevel: tier.requiredLevel
        )
        
        // Cache result
        if durationGateCache[creatorID] == nil {
            durationGateCache[creatorID] = [:]
        }
        durationGateCache[creatorID]?[tier] = result
        
        return result
    }
    
    /// Check all tiers and return the highest unlocked
    func highestUnlockedTier(creatorID: String) async throws -> StreamDurationTier? {
        var highest: StreamDurationTier?
        for tier in StreamDurationTier.allCases {
            let gate = try await checkDurationGate(creatorID: creatorID, tier: tier)
            if gate.isUnlocked {
                highest = tier
            } else {
                break // Tiers are sequential, stop at first locked
            }
        }
        return highest
    }
    
    /// All gate results for creator's progression UI
    func allDurationGates(creatorID: String) async throws -> [StreamDurationGateResult] {
        var results: [StreamDurationGateResult] = []
        for tier in StreamDurationTier.allCases {
            let gate = try await checkDurationGate(creatorID: creatorID, tier: tier)
            results.append(gate)
        }
        return results
    }
    
    // MARK: - Fetch Completions (Cached)
    
    private func fetchCompletions(creatorID: String) async throws -> [StreamCompletionRecord] {
        // Check cache
        if let cached = completionCache[creatorID], !cached.isExpired {
            return cached.value
        }
        
        let snapshot = try await db.collection(Paths.completions(creatorID))
            .order(by: "completedAt", descending: true)
            .getDocuments()
        
        let records = snapshot.documents.compactMap {
            try? $0.data(as: StreamCompletionRecord.self)
        }
        
        completionCache[creatorID] = CachedItem(
            value: records,
            cachedAt: Date(),
            ttl: completionTTL
        )
        
        return records
    }
    
    // MARK: - Apply Stream Extension
    
    /// When collective goal hits 2000 coins, creator gets +30 min
    func applyExtension(creatorID: String, streamID: String, minutes: Int) async throws {
        guard var stream = activeStream, stream.id == streamID else { return }
        
        stream.extensionMinutes += minutes
        stream.maxDurationSeconds += (minutes * 60)
        
        try await db.document(Paths.stream(creatorID, streamID)).updateData([
            "extensionMinutes": stream.extensionMinutes,
            "maxDurationSeconds": stream.maxDurationSeconds
        ])
        
        self.activeStream = stream
        print("⏰ STREAM: Extended \(minutes) min — new max: \(stream.maxDurationSeconds / 60) min")
    }
    
    // MARK: - Viewer Join/Leave
    
    func viewerJoined(
        creatorID: String,
        streamID: String,
        userID: String,
        userLevel: Int
    ) async throws {
        let attendance = StreamAttendance(
            userID: userID,
            streamID: streamID,
            communityID: creatorID,
            userLevel: userLevel
        )
        
        let batch = db.batch()
        
        // Create attendance doc
        let attendRef = db.collection(Paths.attendance(creatorID, streamID)).document(userID)
        try batch.setData(from: attendance, forDocument: attendRef)
        
        // Increment viewer count (not read-then-write)
        let streamRef = db.document(Paths.stream(creatorID, streamID))
        batch.updateData([
            "viewerCount": FieldValue.increment(Int64(1))
        ], forDocument: streamRef)
        
        try await batch.commit()
        
        // Start local heartbeat buffer
        heartbeatBuffer = PendingHeartbeatBuffer()
        startViewerHeartbeat(creatorID: creatorID, streamID: streamID, userID: userID)
    }
    
    func viewerLeft(
        creatorID: String,
        streamID: String,
        userID: String
    ) async throws {
        // Flush pending heartbeat data first
        await flushHeartbeat(creatorID: creatorID, streamID: streamID, userID: userID)
        
        let batch = db.batch()
        
        // Update attendance
        let attendRef = db.collection(Paths.attendance(creatorID, streamID)).document(userID)
        batch.updateData([
            "isCurrentlyWatching": false,
            "lastHeartbeatAt": Timestamp(date: Date())
        ], forDocument: attendRef)
        
        // Decrement viewer count
        let streamRef = db.document(Paths.stream(creatorID, streamID))
        batch.updateData([
            "viewerCount": FieldValue.increment(Int64(-1))
        ], forDocument: streamRef)
        
        try await batch.commit()
        
        stopViewerHeartbeat()
    }
    
    // MARK: - Viewer Interaction (Local Buffer)
    
    /// Called on chat, tap, reaction — local only, no Firestore write
    func recordViewerInteraction() {
        heartbeatBuffer.recordInteraction()
    }
    
    // MARK: - Update Coin Total (From StreamCoinService)
    
    func updateCoinTotal(_ total: Int) {
        collectiveCoinsTotal = total
        activeStream?.totalCoinsSpent = total
    }
    
    // MARK: - Update Peak Viewer Count
    
    func updatePeakViewerCount(creatorID: String, streamID: String, current: Int) async {
        guard var stream = activeStream, current > stream.peakViewerCount else { return }
        stream.peakViewerCount = current
        self.activeStream = stream
        
        try? await db.document(Paths.stream(creatorID, streamID)).updateData([
            "peakViewerCount": current
        ])
    }
    
    // MARK: - Stream Listener (Viewer Side)
    
    /// Viewer subscribes to stream doc for real-time updates
    func listenToStream(creatorID: String, streamID: String) {
        removeStreamListener()
        
        streamListener = db.document(Paths.stream(creatorID, streamID))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let data = snapshot else { return }
                
                if let stream = try? data.data(as: LiveStream.self) {
                    Task { @MainActor in
                        self.activeStream = stream
                        self.viewerCount = stream.viewerCount
                        self.collectiveCoinsTotal = stream.totalCoinsSpent
                        self.isStreaming = stream.status == .live
                    }
                }
            }
    }
    
    func removeStreamListener() {
        streamListener?.remove()
        streamListener = nil
    }
    
    // MARK: - Fetch Active Stream (For Community Detail)
    
    func fetchActiveStream(creatorID: String) async throws -> LiveStream? {
        let snapshot = try await db.collection(Paths.streams(creatorID))
            .whereField("status", isEqualTo: StreamStatus.live.rawValue)
            .limit(to: 1)
            .getDocuments()
        
        return snapshot.documents.first.flatMap {
            try? $0.data(as: LiveStream.self)
        }
    }
    
    // MARK: - Timers
    
    private func startStreamTimer() {
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let stream = self.activeStream else { return }
                self.elapsedSeconds = stream.elapsedSeconds
                
                // Check if past max duration (tier + extensions)
                if stream.elapsedSeconds >= stream.maxDurationSeconds {
                    // Auto-end when time runs out
                    try? await self.endStream(creatorID: stream.creatorID)
                }
            }
        }
    }
    
    private func stopStreamTimer() {
        streamTimer?.invalidate()
        streamTimer = nil
        elapsedSeconds = 0
    }
    
    // Creator heartbeat — writes every 60 sec so server knows stream is alive
    private func startCreatorHeartbeat(creatorID: String, streamID: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task {
                try? await self?.db.document(Paths.stream(creatorID, streamID)).updateData([
                    "lastHeartbeatAt": Timestamp(date: Date())
                ])
            }
        }
    }
    
    private func stopCreatorHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    // Viewer heartbeat — flushes local buffer every 5 min
    private func startViewerHeartbeat(creatorID: String, streamID: String, userID: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task {
                await self?.flushHeartbeat(creatorID: creatorID, streamID: streamID, userID: userID)
            }
        }
    }
    
    private func stopViewerHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func flushHeartbeat(creatorID: String, streamID: String, userID: String) async {
        let (interactions, watchSeconds) = heartbeatBuffer.flush()
        guard interactions > 0 || watchSeconds > 0 else { return }
        
        try? await db.collection(Paths.attendance(creatorID, streamID))
            .document(userID)
            .updateData([
                "interactionCount": FieldValue.increment(Int64(interactions)),
                "totalWatchSeconds": FieldValue.increment(Int64(watchSeconds)),
                "lastHeartbeatAt": Timestamp(date: Date()),
                "lastInteractionAt": Timestamp(date: heartbeatBuffer.lastInteractionAt)
            ])
    }
    
    // MARK: - Stream Recovery (App Relaunch / Crash Recovery)
    
    /// Call on app launch — checks if creator has an active stream in Firestore
    /// If found and heartbeat is recent (<2 min), recovers it.
    /// If heartbeat is stale (>2 min), auto-ends it as abandoned.
    /// Cost: 1 read (community doc). Recovery adds 1 read (stream doc).
    @MainActor
    func recoverActiveStream(creatorID: String) async {
        // Already have one locally
        guard activeStream == nil else { return }
        
        do {
            let communityDoc = try await db.collection("communities").document(creatorID).getDocument()
            guard let data = communityDoc.data(),
                  let isLive = data["isCreatorLive"] as? Bool, isLive,
                  let streamID = data["activeStreamID"] as? String else {
                return
            }
            
            // Fetch the stream doc
            let streamDoc = try await db.document(Paths.stream(creatorID, streamID)).getDocument()
            guard streamDoc.exists,
                  let stream = try? streamDoc.data(as: LiveStream.self),
                  stream.status == .live else {
                // Stream doc missing or already ended — clean up community flag
                try? await cleanupStaleLiveFlag(creatorID: creatorID)
                return
            }
            
            // Check heartbeat freshness
            let heartbeatAge = Date().timeIntervalSince(stream.lastHeartbeatAt ?? stream.startedAt)
            
            if heartbeatAge > 120 {
                // Stale — creator crashed/closed app >2 min ago. Auto-end.
                print("⚠️ STREAM: Stale stream detected (\(Int(heartbeatAge))s since heartbeat). Auto-ending.")
                self.activeStream = stream
                self.isStreaming = true
                _ = try? await endStream(creatorID: creatorID)
            } else {
                // Fresh — recover the stream
                self.activeStream = stream
                self.isStreaming = true
                self.viewerCount = stream.viewerCount
                self.elapsedSeconds = stream.elapsedSeconds
                self.collectiveCoinsTotal = stream.totalCoinsSpent
                
                startStreamTimer()
                startCreatorHeartbeat(creatorID: creatorID, streamID: streamID)
                
                print("✅ STREAM: Recovered active stream \(streamID) — \(stream.elapsedSeconds)s elapsed")
            }
        } catch {
            print("⚠️ STREAM: Recovery check failed: \(error.localizedDescription)")
        }
    }
    
    /// Clean up isCreatorLive flag when stream doc is missing or ended
    private func cleanupStaleLiveFlag(creatorID: String) async throws {
        try await db.collection("communities").document(creatorID).updateData([
            "isCreatorLive": false,
            "activeStreamID": FieldValue.delete()
        ])
        print("🧹 STREAM: Cleaned stale live flag for \(creatorID)")
    }
    
    /// Check if creator has a recoverable stream (for UI — no side effects)
    /// Cost: 0 reads if community doc already fetched via listener
    var hasRecoverableStream: Bool {
        activeStream != nil && isStreaming
    }
    
    // MARK: - Build Recap (Post-Stream)
    
    func buildRecap(
        stream: LiveStream,
        coinsSpent: Int,
        badgesEarned: [StreamBadgeDefinition]
    ) -> StreamRecap {
        let tier = stream.durationTier
        let wasFullCompletion = stream.isFullCompletion
        
        let goalsReached = StreamCollectiveGoal.allGoals.filter {
            stream.totalCoinsSpent >= $0.threshold
        }
        
        return StreamRecap(
            stream: stream,
            tier: tier,
            durationFormatted: formatDuration(stream.elapsedSeconds),
            viewerXPEarned: tier.baseXP,
            fullStayBonus: wasFullCompletion ? tier.fullStayBonusXP : 0,
            coinsSpent: coinsSpent,
            xpFromCoins: coinsSpent * StreamHypeType.xpPerCoinSpent,
            badgesEarned: badgesEarned,
            cloutBonus: wasFullCompletion ? tier.viewerCloutBonus : 0,
            goalsReached: goalsReached,
            wasFullCompletion: wasFullCompletion
        )
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - Cleanup
    
    func onAppBackground() async {
        // Flush viewer heartbeat
        if let stream = activeStream {
            await flushHeartbeat(
                creatorID: stream.creatorID,
                streamID: stream.id,
                userID: "" // TODO: Pass actual viewer userID
            )
        }
    }
    
    func onLogout() {
        stopStreamTimer()
        stopCreatorHeartbeat()
        stopViewerHeartbeat()
        removeStreamListener()
        activeStream = nil
        isStreaming = false
        completionCache.removeAll()
        durationGateCache.removeAll()
    }
}

// MARK: - Errors

enum LiveStreamError: LocalizedError {
    case tierLocked(StreamDurationGateResult)
    case alreadyStreaming
    case noActiveStream
    case notCreator
    case streamEnded
    case onCooldown(remainingSeconds: Int)
    
    var errorDescription: String? {
        switch self {
        case .tierLocked(let gate):
            if !gate.levelMet {
                return "Reach Level \(gate.requiredLevel) to unlock \(gate.tier.displayName)"
            }
            return "Complete \(gate.completionsNeeded) more \(gate.tier.previousTier?.displayName ?? "") streams"
        case .alreadyStreaming:
            return "You already have an active stream"
        case .noActiveStream:
            return "No active stream to end"
        case .notCreator:
            return "Only the creator can manage this stream"
        case .streamEnded:
            return "This stream has ended"
        case .onCooldown(let remaining):
            let min = remaining / 60
            return "Cooldown active — you can go live again in \(min) min"
        }
    }
}
