//
//  StreamCoinService.swift
//  StitchSocial
//
//  Layer 6: Services - Stream Coin/Hype Spending
//  Dependencies: LiveStreamTypes, HypeCoinService, CommunityXPService, LiveStreamService
//  Features: Hype purchases, revenue splits, collective goals, XP multipliers
//
//  CACHING:
//  - activeMultiplier: 100% local, zero Firestore per-tick
//  - collectiveGoalState: Derived from stream doc listener (already active)
//  - hypeBuffer: Local PendingHypeBuffer, flush every 30 sec
//
//  BATCHING:
//  - Hype events: Buffer locally, flush every 30 sec or 20 events
//  - Coin deduction + creator credit: Single batched write per flush
//  - Collective goal check: Pure logic against stream.totalCoinsSpent
//  - Revenue splits: Cloud Function post-stream, not per-event
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class StreamCoinService: ObservableObject {
    
    static let shared = StreamCoinService()
    
    // MARK: - Published State
    
    @Published var activeMultiplier = ActiveXPMultiplier()
    @Published var lastHypeAlert: StreamHypeEvent?
    @Published var currentGoal: StreamCollectiveGoal?
    @Published var goalProgress: Double = 0
    
    // MARK: - Private
    
    private let db = FirebaseConfig.firestore
    private var hypeBuffer = PendingHypeBuffer()
    private var flushTimer: Timer?
    
    private struct Paths {
        static func hypeEvents(_ creatorID: String, _ streamID: String) -> String {
            "communities/\(creatorID)/streams/\(streamID)/hypeEvents"
        }
    }
    
    private init() {}
    
    // MARK: - Send Hype (Viewer)
    
    /// Viewer sends a hype during live stream
    /// Deducts coins locally (optimistic), buffers event, applies multiplier
    func sendHype(
        hypeType: StreamHypeType,
        streamID: String,
        communityID: String,
        senderID: String,
        senderUsername: String,
        senderLevel: Int
    ) async throws -> StreamHypeEvent {
        
        // Check coin balance (cached in HypeCoinService)
        let currentBalance = HypeCoinService.shared.balance?.availableCoins ?? 0
        guard currentBalance >= hypeType.coinCost else {
            throw StreamCoinError.insufficientBalance
        }
        
        // Transfer coins from sender to creator (handles deduction + transaction log)
        try await HypeCoinService.shared.transferCoins(
            fromUserID: senderID,
            toUserID: communityID, // communityID == creatorID
            amount: hypeType.coinCost,
            type: .tipSent
        )
        
        let event = StreamHypeEvent(
            streamID: streamID,
            communityID: communityID,
            senderID: senderID,
            senderUsername: senderUsername,
            senderLevel: senderLevel,
            hypeType: hypeType
        )
        
        // Buffer event (not written yet)
        hypeBuffer.add(event)
        
        // Apply XP multiplier locally
        if hypeType.xpMultiplier > 1 {
            activeMultiplier.apply(hypeType: hypeType)
        }
        
        // Award XP per coin spent (through community XP buffer)
        // spentHypeCoin source = 20 XP per coin, multiply by coin cost
        CommunityXPService.shared.awardXP(
            userID: senderID,
            communityID: communityID,
            source: .spentHypeCoin,
            multiplier: Double(hypeType.coinCost)
        )
        
        // Update stream total locally (optimistic)
        LiveStreamService.shared.updateCoinTotal(
            (LiveStreamService.shared.activeStream?.totalCoinsSpent ?? 0) + hypeType.coinCost
        )
        
        // Check collective goals
        checkCollectiveGoals()
        
        // Set alert for UI
        self.lastHypeAlert = event
        
        // Auto-flush if buffer is full
        if hypeBuffer.shouldFlush {
            await flushHypeBuffer(communityID: communityID, streamID: streamID)
        }
        
        print("🔥 HYPE: @\(senderUsername) sent \(hypeType.displayName) (\(hypeType.coinCost) coins)")
        return event
    }
    
    // MARK: - Flush Hype Buffer
    
    /// Batched write of all buffered hype events
    private func flushHypeBuffer(communityID: String, streamID: String) async {
        let events = hypeBuffer.flush()
        guard !events.isEmpty else { return }
        
        let batch = db.batch()
        
        // Write each event
        for event in events {
            let ref = db.collection(Paths.hypeEvents(communityID, streamID)).document(event.id)
            try? batch.setData(from: event, forDocument: ref)
        }
        
        // Update stream totals in one write
        let totalCoins = events.reduce(0) { $0 + $1.coinCost }
        let streamRef = db.document("communities/\(communityID)/streams/\(streamID)")
        batch.updateData([
            "totalCoinsSpent": FieldValue.increment(Int64(totalCoins)),
            "totalHypeEvents": FieldValue.increment(Int64(events.count))
        ], forDocument: streamRef)
        
        try? await batch.commit()
        
        print("📦 HYPE FLUSH: \(events.count) events, \(totalCoins) coins written")
    }
    
    // MARK: - Collective Goals
    
    private func checkCollectiveGoals() {
        let total = LiveStreamService.shared.collectiveCoinsTotal
        
        // Update current goal and progress
        currentGoal = StreamCollectiveGoal.nextGoal(totalCoins: total)
        goalProgress = StreamCollectiveGoal.progress(totalCoins: total)
        
        // Check for newly reached goals
        for goal in StreamCollectiveGoal.allGoals {
            if total >= goal.threshold && !goal.isReached {
                handleGoalReached(goal)
            }
        }
    }
    
    private func handleGoalReached(_ goal: StreamCollectiveGoal) {
        switch goal.effect {
        case .streamExtension:
            // Give creator +30 min
            if let stream = LiveStreamService.shared.activeStream {
                Task {
                    try? await LiveStreamService.shared.applyExtension(
                        creatorID: stream.creatorID,
                        streamID: stream.id,
                        minutes: 30
                    )
                }
            }
            
        case .bonusXP:
            // Award 200 XP to all current viewers — handled by Cloud Function
            // Client just shows the celebration UI
            print("🎉 GOAL: Bonus XP goal reached! Cloud Function will award.")
            
        case .legendaryBadge:
            // Legendary badge for all attendees — Cloud Function on stream end
            print("🏆 GOAL: Legendary Stream badge unlocked!")
            
        case .hotTag, .permanentHighlight:
            // These are metadata flags handled by stream doc update
            print("✨ GOAL: \(goal.displayName) reached!")
        }
    }
    
    // MARK: - Start/Stop Flush Timer
    
    func startFlushTimer(communityID: String, streamID: String) {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.flushHypeBuffer(communityID: communityID, streamID: streamID)
            }
        }
    }
    
    func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }
    
    // MARK: - Get Current Multiplier for XP Calculation
    
    /// Called by attendance XP logic to apply active multiplier
    func currentMultiplier() -> Int {
        return activeMultiplier.isActive ? activeMultiplier.multiplier : 1
    }
    
    // MARK: - Cleanup
    
    func onStreamEnd(communityID: String, streamID: String) async {
        // Final flush
        await flushHypeBuffer(communityID: communityID, streamID: streamID)
        stopFlushTimer()
        
        activeMultiplier.reset()
        lastHypeAlert = nil
        currentGoal = nil
        goalProgress = 0
        hypeBuffer = PendingHypeBuffer()
    }
    
    func onLogout() {
        stopFlushTimer()
        activeMultiplier.reset()
        lastHypeAlert = nil
        currentGoal = nil
        hypeBuffer = PendingHypeBuffer()
    }
}

// MARK: - Errors

enum StreamCoinError: LocalizedError {
    case insufficientBalance
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientBalance:
            return "Not enough Hype Coins"
        case .transactionFailed:
            return "Transaction failed, coins not deducted"
        }
    }
}
