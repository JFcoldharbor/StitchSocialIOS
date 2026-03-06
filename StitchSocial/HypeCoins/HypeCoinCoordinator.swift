//
//  HypeCoinCoordinator.swift
//  StitchSocial
//
//  Created by James Garmon on 3/3/26.
//


//
//  HypeCoinCoordinator.swift
//  StitchSocial
//
//  Coordinates Hype Coin flows: web purchases, tipping, subscriptions, deep links
//
//  CACHING STRATEGY:
//  - Balance cached locally, synced on foreground + deep link return
//  - Real-time Firestore listener for instant web purchase detection
//  - Tip cooldown prevents spam (1 tip per 2 seconds)
//
//  BATCHING:
//  - Multiple quick tips batched into single Firestore write
//

import Foundation
import FirebaseFirestore
import Combine
import UIKit

@MainActor
final class HypeCoinCoordinator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = HypeCoinCoordinator()
    
    // MARK: - Services
    
    private let coinService = HypeCoinService.shared
    private let subscriptionService = SubscriptionService.shared
    private let db = Firestore.firestore()
    
    // MARK: - Published State
    
    @Published private(set) var balance: HypeCoinBalance?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var showPurchaseSuccess = false
    @Published private(set) var lastPurchaseAmount: Int = 0
    
    // MARK: - Cache
    
    /// Local balance cache to reduce reads
    private var cachedBalance: HypeCoinBalance?
    private var balanceLastFetched: Date?
    private let balanceCacheTTL: TimeInterval = 60 // 1 minute
    
    /// Tip cooldown to prevent spam
    private var lastTipTime: Date?
    private let tipCooldown: TimeInterval = 2.0
    
    /// Pending tips to batch
    private var pendingTips: [(toUserID: String, amount: Int, completion: ((Bool) -> Void)?)] = []
    private var tipBatchTimer: Timer?
    
    // MARK: - Firestore Listener
    
    private var balanceListener: ListenerRegistration?
    private var currentUserID: String?
    
    // MARK: - Lifecycle
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    private init() {
        setupAppLifecycleObservers()
    }
    
    deinit {
        balanceListener?.remove()
        tipBatchTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    func configure(userID: String) {
        guard currentUserID != userID else { return }
        
        // Clean up previous listener
        balanceListener?.remove()
        currentUserID = userID
        
        // Start real-time listener for balance changes (catches web purchases)
        startBalanceListener(userID: userID)
        
        // Initial fetch
        Task {
            await syncBalance()
        }
    }
    
    func disconnect() {
        balanceListener?.remove()
        balanceListener = nil
        currentUserID = nil
        cachedBalance = nil
        balance = nil
    }
    
    // MARK: - App Lifecycle (Sync on Foreground)
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncBalance()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Real-Time Balance Listener
    
    private func startBalanceListener(userID: String) {
        let docRef = db.collection("coin_balances").document(userID)
        
        balanceListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ COINS: Listener error - \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data(),
                  let newBalance = try? snapshot?.data(as: HypeCoinBalance.self) else {
                return
            }
            
            // Detect web purchase (balance increased)
            if let cached = self.cachedBalance,
               newBalance.availableCoins > cached.availableCoins {
                let purchased = newBalance.availableCoins - cached.availableCoins
                
                Task { @MainActor in
                    self.lastPurchaseAmount = purchased
                    self.showPurchaseSuccess = true
                    
                    // Auto-dismiss after 3 seconds
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.showPurchaseSuccess = false
                }
                
                print("💰 COINS: Detected web purchase of \(purchased) coins")
            }
            
            // Update cache
            Task { @MainActor in
                self.cachedBalance = newBalance
                self.balance = newBalance
                self.balanceLastFetched = Date()
            }
        }
    }
    
    // MARK: - Balance Operations
    
    func syncBalance() async {
        guard let userID = currentUserID else { return }
        
        do {
            let freshBalance = try await coinService.fetchBalance(userID: userID)
            cachedBalance = freshBalance
            balance = freshBalance
            balanceLastFetched = Date()
            print("🔄 COINS: Balance synced - \(freshBalance.availableCoins) available")
        } catch {
            lastError = error.localizedDescription
            print("❌ COINS: Sync failed - \(error)")
        }
    }
    
    func getBalance() async -> Int {
        // Return cached if fresh
        if let cached = cachedBalance,
           let lastFetch = balanceLastFetched,
           Date().timeIntervalSince(lastFetch) < balanceCacheTTL {
            return cached.availableCoins
        }
        
        // Fetch fresh
        await syncBalance()
        return cachedBalance?.availableCoins ?? 0
    }
    
    func canAfford(_ amount: Int) async -> Bool {
        let balance = await getBalance()
        return balance >= amount
    }
    
    // MARK: - Deep Link Handling
    
    /// Call when app receives deep link from web (after purchase)
    func handleDeepLink(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "stitchsocial" else {
            return
        }
        
        switch components.host {
        case "purchase-complete":
            // Web purchase completed - sync balance
            Task {
                await syncBalance()
            }
            
        case "purchase-cancelled":
            // User cancelled - no action needed
            print("ℹ️ COINS: Purchase cancelled by user")
            
        default:
            break
        }
    }
    
    // MARK: - Tipping
    
    func sendTip(toUserID: String, amount: Int, completion: ((Bool) -> Void)? = nil) {
        guard let fromUserID = currentUserID else {
            completion?(false)
            return
        }
        
        // Enforce cooldown
        if let lastTip = lastTipTime,
           Date().timeIntervalSince(lastTip) < tipCooldown {
            // Queue tip for batch processing
            pendingTips.append((toUserID, amount, completion))
            scheduleTipBatch()
            return
        }
        
        // Send immediately
        lastTipTime = Date()
        
        Task {
            do {
                try await coinService.transferCoins(
                    fromUserID: fromUserID,
                    toUserID: toUserID,
                    amount: amount,
                    type: .tipReceived
                )
                await syncBalance()
                completion?(true)
                print("💸 COINS: Tipped \(amount) to \(toUserID)")
            } catch {
                lastError = error.localizedDescription
                completion?(false)
                print("❌ COINS: Tip failed - \(error)")
            }
        }
    }
    
    /// Quick tip presets
    func sendQuickTip(_ preset: TipPreset, toUserID: String, completion: ((Bool) -> Void)? = nil) {
        sendTip(toUserID: toUserID, amount: preset.amount, completion: completion)
    }
    
    // MARK: - Tip Batching
    
    private func scheduleTipBatch() {
        tipBatchTimer?.invalidate()
        tipBatchTimer = Timer.scheduledTimer(withTimeInterval: tipCooldown, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.processPendingTips()
            }
        }
    }
    
    private func processPendingTips() async {
        guard !pendingTips.isEmpty, let fromUserID = currentUserID else { return }
        
        let tips = pendingTips
        pendingTips = []
        
        // Group tips by recipient
        var grouped: [String: (total: Int, completions: [((Bool) -> Void)?])] = [:]
        for tip in tips {
            if grouped[tip.toUserID] == nil {
                grouped[tip.toUserID] = (0, [])
            }
            grouped[tip.toUserID]!.total += tip.amount
            grouped[tip.toUserID]!.completions.append(tip.completion)
        }
        
        // Process each recipient
        for (toUserID, data) in grouped {
            do {
                try await coinService.transferCoins(
                    fromUserID: fromUserID,
                    toUserID: toUserID,
                    amount: data.total,
                    type: .tipReceived
                )
                data.completions.forEach { $0?(true) }
                print("💸 COINS: Batched tip of \(data.total) to \(toUserID)")
            } catch {
                data.completions.forEach { $0?(false) }
                print("❌ COINS: Batched tip failed - \(error)")
            }
        }
        
        await syncBalance()
        lastTipTime = Date()
    }
    
    // MARK: - Subscriptions
    
    func subscribe(toCreatorID: String, tier: SubscriptionTier) async throws {
        guard let userID = currentUserID else {
            throw CoinError.transferFailed
        }
        
        isLoading = true
        defer { isLoading = false }
        
        _ = try await subscriptionService.subscribe(
            subscriberID: userID,
            creatorID: toCreatorID,
            tier: tier
        )
        
        await syncBalance()
        print("🎉 COINS: Subscribed to \(toCreatorID) at \(tier.displayName)")
    }
    
    func cancelSubscription(creatorID: String) async throws {
        guard let userID = currentUserID else { return }
        
        try await subscriptionService.cancelSubscription(
            subscriberID: userID,
            creatorID: creatorID
        )
    }
    
    // MARK: - Cash Out
    
    func requestCashOut(amount: Int, tier: UserTier, method: PayoutMethod) async throws -> CashOutRequest {
        guard let userID = currentUserID else {
            throw CoinError.transferFailed
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let request = try await coinService.requestCashOut(
            userID: userID,
            amount: amount,
            tier: tier,
            payoutMethod: method
        )
        
        await syncBalance()
        return request
    }
    
    // MARK: - Purchase URL Generation
    
    func getPurchaseURL(package: HypeCoinPackage) -> URL? {
        guard let userID = currentUserID else { return nil }
        
        // Generate auth token for web auto-login
        let token = generateAuthToken(userID: userID)
        
        let urlString = "https://stitchsocial.me/app/account#wallet?token=\(token)&package=\(package.rawValue)"
        return URL(string: urlString)
    }
    
    private func generateAuthToken(userID: String) -> String {
        // TODO: Implement proper JWT token generation
        // For now, use a simple encoded string (replace with Firebase Custom Token)
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(userID)_\(timestamp)".data(using: .utf8)?.base64EncodedString() ?? ""
    }
}

// MARK: - Tip Presets

enum TipPreset: CaseIterable {
    case small
    case medium
    case large
    case huge
    
    var amount: Int {
        switch self {
        case .small: return 10
        case .medium: return 50
        case .large: return 100
        case .huge: return 500
        }
    }
    
    var displayName: String {
        switch self {
        case .small: return "Nice! 👍"
        case .medium: return "Love it! ❤️"
        case .large: return "Amazing! 🔥"
        case .huge: return "Mind blown! 🤯"
        }
    }
    
    var emoji: String {
        switch self {
        case .small: return "👍"
        case .medium: return "❤️"
        case .large: return "🔥"
        case .huge: return "🤯"
        }
    }
    
    var coinDisplay: String {
        "\(amount) coins"
    }
}

// MARK: - App Delegate Integration

extension HypeCoinCoordinator {
    
    /// Call from AppDelegate or SceneDelegate
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "stitchsocial" {
            handleDeepLink(url: url)
            return true
        }
        return false
    }
}