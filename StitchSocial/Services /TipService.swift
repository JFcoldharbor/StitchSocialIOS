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
import FirebaseAuth
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

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var observedUID: String? = Auth.auth().currentUser?.uid

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

        // Reset per-account state when Firebase Auth swaps users so a
        // linked-account toggle doesn't carry over the previous user's
        // optimistic balance, pending flushes, session totals, or the
        // username cache.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }
                let newUID = user?.uid
                if newUID != self.observedUID {
                    self.observedUID = newUID
                    // Cancel any in-flight flush timers cleanly.
                    for (_, task) in self.flushTimers { task.cancel() }
                    self.flushTimers.removeAll()
                    self.tipStates.removeAll()
                    self.usernameCache.removeAll()
                    self.localCoinBalance = 0
                    self.balanceLoaded = false
                    #if DEBUG
                    print("🪙 TIP SERVICE: cache reset on auth swap → \(newUID ?? "nil")")
                    #endif
                }
            }
        }
    }

    // MARK: - Private: Display name for tip notifications (cached)
    // In-memory cache — avoids re-reading Firestore for same tipper across
    // multiple flushes. Prefers displayName (the friendly user-facing name)
    // over username (which is sometimes set to the UID on seeded accounts
    // and reads like a Firebase ID in notification copy). Fallback chain:
    //   displayName → username → "Someone".
    private func fetchUsername(_ userID: String) async -> String {
        if let cached = usernameCache[userID] { return cached }
        let fallback = "Someone"
        guard !userID.isEmpty else { return fallback }
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        let data = (try? await db.collection("users").document(userID).getDocument().data()) ?? [:]
        let resolved = (data["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (data["username"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallback
        usernameCache[userID] = resolved
        return resolved
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
        #if DEBUG
        print("💰 TIP SERVICE: Balance from coordinator — \(localCoinBalance) coins")
        #endif
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
            #if DEBUG
            print("🚫 TIP SERVICE: Self-tip blocked")
            #endif
            return false
        }
        let pending = tipStates.values.reduce(0) { $0 + $1.pendingAmount }
        guard (localCoinBalance - pending) >= amount else {
            #if DEBUG
            print("🚫 TIP SERVICE: Insufficient funds — balance:\(localCoinBalance) pending:\(pending) needed:\(amount)")
            #endif
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

        #if DEBUG
        print("🪙 TIP SERVICE: Accumulated +\(amount) — pending:\(state.pendingAmount) session:\(state.sessionTotal)")
        #endif

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

        #if DEBUG
        print("🚀 TIP SERVICE: Flushing \(amountToFlush) coins → creator \(creatorID)")
        #endif

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

                        // Aggregate writes — per-video total (public social
                        // proof) and creator's top-supporters list (visible
                        // on profile, names only). Run before the notification
                        // so the recipient's profile reflects the new state
                        // by the time the alert lands.
                        let tipperUsername = await self.fetchUsername(tipperID)
                        await self.recordTipAggregates(
                            videoID: videoID,
                            creatorID: creatorID,
                            tipperID: tipperID,
                            tipperUsername: tipperUsername,
                            amount: amountToFlush
                        )

                        // In-app notification to creator (debounced 60s via NotificationService)
                        // Push notification handled server-side by stitchnoti_processTip CF.
                        if let ns = self.notificationService {
                            do {
                                try await ns.sendTipNotification(
                                    to: creatorID,
                                    fromUserID: tipperID,
                                    fromUsername: tipperUsername,
                                    amount: amountToFlush,
                                    videoID: videoID
                                )
                            } catch {
                                #if DEBUG
                                print("⚠️ TIP SERVICE: tip notification failed — \(error)")
                                #endif
                            }
                        } else {
                            #if DEBUG
                            print("⚠️ TIP SERVICE: notificationService not configured — skipping tip notification for \(creatorID)")
                            #endif
                        }

                        self.tipStates[videoID]?.isFlushing = false
                        #if DEBUG
                        print("✅ TIP SERVICE: \(amountToFlush) coins sent to \(creatorID)")
                        #endif
                    } else {
                        // Rollback
                        self.localCoinBalance += amountToFlush
                        self.tipStates[videoID]?.sessionTotal -= amountToFlush
                        self.tipStates[videoID]?.isFlushing   = false
                        #if DEBUG
                        print("❌ TIP SERVICE: Flush failed — rolled back \(amountToFlush) coins")
                        #endif
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Tip Aggregates (per-video total + creator top supporters)
    //
    // Public per-video total drives social proof on the card overlay.
    // Top supporters list lives on the creator's user doc as a denormalized
    // array (top 10) with usernames only — amounts stay private to the
    // tipper and creator.
    //
    // Schema:
    //   videos/{videoID}.coinTotal: Int  (atomic increment)
    //   users/{creatorID}/supporters/{tipperID}: {
    //       tipperID: String, username: String, totalSent: Int, lastSentAt: Timestamp
    //   }
    //   users/{creatorID}.topSupporters: [{tipperID, username, totalSent}]  (cap 10)
    //
    // Each tip flush triggers all three writes. Subcollection is the
    // source of truth; the user-doc array is a denormalized read-cache
    // refreshed lazily after each tip.

    private func recordTipAggregates(
        videoID: String,
        creatorID: String,
        tipperID: String,
        tipperUsername: String,
        amount: Int
    ) async {
        let db = Firestore.firestore(database: Config.Firebase.databaseName)

        // 1) Per-video coin total (public). Increment is atomic; the field
        //    auto-creates on first tip if it doesn't already exist.
        if !videoID.isEmpty {
            do {
                try await db.collection("videos").document(videoID).updateData([
                    "coinTotal": FieldValue.increment(Int64(amount)),
                    "lastTippedAt": Timestamp(date: Date())
                ])
            } catch {
                #if DEBUG
                print("⚠️ TIP AGG: video coinTotal update failed for \(videoID) — \(error)")
                #endif
            }
        }

        // 2) Per-tipper supporter row under the creator. setData with merge
        //    so the doc is created on first tip and incremented thereafter.
        let supporterRef = db.collection("users").document(creatorID)
            .collection("supporters").document(tipperID)
        do {
            try await supporterRef.setData([
                "tipperID": tipperID,
                "username": tipperUsername,
                "totalSent": FieldValue.increment(Int64(amount)),
                "lastSentAt": Timestamp(date: Date())
            ], merge: true)
        } catch {
            #if DEBUG
            print("⚠️ TIP AGG: supporter row update failed for \(creatorID)/\(tipperID) — \(error)")
            #endif
            return
        }

        // 3) Refresh the creator's top-10 array. Read the subcollection
        //    sorted by totalSent desc, project to the public shape, and
        //    write to users/{creatorID}.topSupporters.
        do {
            let snapshot = try await db.collection("users").document(creatorID)
                .collection("supporters")
                .order(by: "totalSent", descending: true)
                .limit(to: 10)
                .getDocuments()

            let top: [[String: Any]] = snapshot.documents.map { doc in
                let data = doc.data()
                return [
                    "tipperID": data["tipperID"] as? String ?? doc.documentID,
                    "username": data["username"] as? String ?? "user",
                    "totalSent": data["totalSent"] as? Int ?? 0
                ]
            }

            try await db.collection("users").document(creatorID).updateData([
                "topSupporters": top
            ])
        } catch {
            #if DEBUG
            print("⚠️ TIP AGG: topSupporters refresh failed for \(creatorID) — \(error)")
            #endif
        }
    }
}
