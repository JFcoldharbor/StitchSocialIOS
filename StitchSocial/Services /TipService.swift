//
//  TipService.swift
//  StitchSocial
//
//  Tip mechanic service.
//
//  CACHING STRATEGY (add to caching optimization file):
//  1. localCoinBalance — loaded once from coin_balances/{uid}.availableCoins.
//     Updated optimistically on each tap. No per-tap Firestore reads.
//  2. pendingAmount accumulator — buffers taps locally, debounced flush
//     every TipConfig.flushDebounceInterval seconds. Prevents N writes for N taps.
//  3. Rollback — if transfer fails, localCoinBalance is restored and session total corrected.
//  4. Cleanup — tipStates dict cleared on deinit / video change via clearState(videoID:).
//
//  BATCHING: All taps within the debounce window are combined into ONE
//  HypeCoinService.transferCoins call (deduct tipper + credit creator + record txn).
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class TipService: ObservableObject {

    // MARK: - Singleton
    static let shared = TipService()

    // MARK: - Published
    @Published var localCoinBalance: Int = 0
    @Published var isLoadingBalance: Bool = false
    @Published var balanceLoaded: Bool = false

    // MARK: - Private State
    private var tipStates: [String: TipState] = [:]
    private var flushTimers: [String: Task<Void, Never>] = [:]

    private var coordinatorCancellable: AnyCancellable?
    // Username cache: avoids repeated Firestore reads for the same tipper
    private var usernameCache: [String: String] = [:]

    // Set by App root via TipService.shared.configure(notificationService:)
    // CACHING: NotificationService handles its own 60s cooldown — no caching needed here
    weak var notificationService: NotificationService?

    func configure(notificationService: NotificationService) {
        self.notificationService = notificationService
    }

    private init() {
        // Stay in sync with coordinator after Firestore propagates.
        // Only update if TipService has no pending flush (prevents overwriting optimistic state).
        coordinatorCancellable = HypeCoinCoordinator.shared.$balance
            .compactMap { $0?.availableCoins }
            .receive(on: RunLoop.main)
            .sink { [weak self] serverBalance in
                guard let self else { return }
                let hasPending = self.tipStates.values.contains { $0.pendingAmount > 0 || $0.isFlushing }
                if !hasPending {
                    self.localCoinBalance = serverBalance
                }
            }
    }

    // MARK: - Private: Username Fetch (cached)
    // In-memory cache — avoids re-reading Firestore for same tipper across multiple flushes.
    private func fetchUsername(_ userID: String) async -> String? {
        if let cached = usernameCache[userID] { return cached }
        let db = Firestore.firestore()
        guard let data = try? await db.collection("users").document(userID).getDocument().data(),
              let username = data["username"] as? String else { return nil }
        usernameCache[userID] = username
        return username
    }
    // HypeCoinCoordinator already caches balance with a real-time listener.
    // We read from it directly — zero extra Firestore reads.

    func loadBalance(userID: String) async {
        guard !balanceLoaded else { return }

        // Configure coordinator if not already running
        HypeCoinCoordinator.shared.configure(userID: userID)

        // Wait briefly for coordinator's initial fetch if needed
        if HypeCoinCoordinator.shared.balance == nil {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        localCoinBalance = HypeCoinCoordinator.shared.balance?.availableCoins ?? 0
        balanceLoaded = true
        print("💰 TIP SERVICE: Balance from coordinator — \(localCoinBalance) coins")
    }

    // MARK: - Public Tap Entry Points

    func handleTap(videoID: String, tipperID: String, creatorID: String, amount: Int = TipConfig.singleTapAmount) {
        guard canTip(tipperID: tipperID, creatorID: creatorID, amount: amount) else { return }
        accumulate(videoID: videoID, tipperID: tipperID, creatorID: creatorID, amount: amount)
    }

    func handleLongPress(videoID: String, tipperID: String, creatorID: String) {
        handleTap(videoID: videoID, tipperID: tipperID, creatorID: creatorID, amount: TipConfig.longPressAmount)
    }

    // MARK: - Session State Accessors

    func sessionTotal(for videoID: String) -> Int {
        tipStates[videoID]?.sessionTotal ?? 0
    }

    func isFlushing(for videoID: String) -> Bool {
        tipStates[videoID]?.isFlushing ?? false
    }

    // MARK: - Cleanup

    func clearState(videoID: String) {
        flushTimers[videoID]?.cancel()
        flushTimers.removeValue(forKey: videoID)
        tipStates.removeValue(forKey: videoID)
    }

    // MARK: - Private: Balance Guard

    private func canTip(tipperID: String, creatorID: String, amount: Int) -> Bool {
        guard tipperID != creatorID else {
            print("🚫 TIP SERVICE: Self-tip blocked")
            return false
        }
        let pending = tipStates.values.reduce(0) { $0 + $1.pendingAmount }
        guard (localCoinBalance - pending) >= amount else {
            print("🚫 TIP SERVICE: Insufficient funds — balance:\(localCoinBalance) pending:\(pending) needed:\(amount)")
            return false
        }
        return true
    }

    // MARK: - Private: Accumulator

    private func accumulate(videoID: String, tipperID: String, creatorID: String, amount: Int) {
        // Optimistic deduct
        localCoinBalance -= amount

        var state = tipStates[videoID] ?? TipState()
        state.pendingAmount += amount
        state.sessionTotal  += amount
        tipStates[videoID]   = state

        print("🪙 TIP SERVICE: Accumulated +\(amount) — pending:\(state.pendingAmount) session:\(state.sessionTotal)")

        // Debounce flush
        flushTimers[videoID]?.cancel()
        flushTimers[videoID] = Task {
            try? await Task.sleep(nanoseconds: UInt64(TipConfig.flushDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await flush(videoID: videoID, tipperID: tipperID, creatorID: creatorID)
        }
    }

    // MARK: - Private: Flush via HypeCoinCoordinator.sendTip

    private func flush(videoID: String, tipperID: String, creatorID: String) async {
        guard var state = tipStates[videoID], state.hasPending else { return }

        let amountToFlush = state.pendingAmount
        state.pendingAmount = 0
        state.isFlushing = true
        state.lastFlushAt = Date()
        tipStates[videoID] = state

        print("🚀 TIP SERVICE: Flushing \(amountToFlush) coins → creator \(creatorID)")

        // Use coordinator — handles batching, cooldown, and balance sync
        await withCheckedContinuation { continuation in
            HypeCoinCoordinator.shared.sendTip(toUserID: creatorID, amount: amountToFlush) { success in
                Task { @MainActor in
                    if success {
                        // localCoinBalance is already correct from optimistic deduct.
                        // Do NOT overwrite from coordinator here — syncBalance() in sendTip
                        // was removed because Firestore hasn't propagated yet at this point.
                        // The real-time listener on HypeCoinCoordinator will update balance
                        // naturally once the write settles (~200-500ms).

                        // Award small clout bonus to creator
                        let userService = UserService()
                        try? await userService.awardClout(userID: creatorID, amount: TipConfig.cloutBonusPerFlush)

                        // In-app notification to creator (debounced 60s via NotificationService)
                        // Push notification handled server-side by stitchnoti_processTip CF
                        if let tipperUsername = await self.fetchUsername(tipperID),
                           let ns = self.notificationService {
                            try? await ns.sendTipNotification(
                                to: creatorID,
                                fromUserID: tipperID,
                                fromUsername: tipperUsername,
                                amount: amountToFlush,
                                videoID: videoID
                            )
                        }

                        self.tipStates[videoID]?.isFlushing = false
                        print("✅ TIP SERVICE: \(amountToFlush) coins sent to \(creatorID)")
                    } else {
                        // Rollback
                        self.localCoinBalance += amountToFlush
                        self.tipStates[videoID]?.sessionTotal -= amountToFlush
                        self.tipStates[videoID]?.isFlushing   = false
                        print("❌ TIP SERVICE: Flush failed — rolled back \(amountToFlush) coins")
                    }
                    continuation.resume()
                }
            }
        }
    }
}
