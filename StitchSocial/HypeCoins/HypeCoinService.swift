//
//  HypeCoinService.swift
//  StitchSocial
//
//  Service for Hype Coin web purchases, transfers, and cash out
//  NOTE: Coin purchases happen on stitchsocial.com (web) to avoid Apple's 30% cut
//

import Foundation
import FirebaseFirestore

class HypeCoinService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = HypeCoinService()
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    
    @Published var balance: HypeCoinBalance?
    @Published var transactions: [CoinTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Collections
    
    private enum Collections {
        static let balances = "coin_balances"
        static let transactions = "coin_transactions"
        static let cashOuts = "cash_out_requests"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Balance
    
    @MainActor
    func fetchBalance(userID: String) async throws -> HypeCoinBalance {
        let docRef = db.collection(Collections.balances).document(userID)
        let doc = try await docRef.getDocument()
        
        if let balance = try? doc.data(as: HypeCoinBalance.self) {
            self.balance = balance
            return balance
        }
        
        // Create new balance if doesn't exist
        let newBalance = HypeCoinBalance(userID: userID)
        try docRef.setData(from: newBalance)
        self.balance = newBalance
        return newBalance
    }
    
    // MARK: - Web Purchase Verification
    
    /// Called by backend webhook after Stripe payment succeeds
    /// This function should be triggered by Firebase Cloud Function, not directly from app
    @MainActor
    func creditWebPurchase(userID: String, coins: Int, transactionID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let balanceRef = db.collection(Collections.balances).document(userID)
        
        // Verify transaction hasn't been credited already
        let existingTransaction = try await db.collection(Collections.transactions)
            .whereField("id", isEqualTo: transactionID)
            .getDocuments()
        
        guard existingTransaction.documents.isEmpty else {
            print("⚠️ COINS: Transaction already credited")
            return
        }
        
        // Update balance
        try await balanceRef.updateData([
            "availableCoins": FieldValue.increment(Int64(coins)),
            "lifetimeEarned": FieldValue.increment(Int64(coins)),
            "lastUpdated": Date()
        ])
        
        // Record transaction
        let transaction = CoinTransaction(
            id: transactionID,
            userID: userID,
            type: .purchase,
            amount: coins,
            balanceAfter: (balance?.availableCoins ?? 0) + coins,
            relatedUserID: nil,
            relatedSubscriptionID: nil,
            description: "Purchased \(coins) Hype Coins",
            createdAt: Date()
        )
        
        try db.collection(Collections.transactions)
            .document(transaction.id)
            .setData(from: transaction)
        
        // Refresh balance
        _ = try await fetchBalance(userID: userID)
        
        print("💰 COINS: Credited \(coins) coins from web purchase")
    }
    
    // MARK: - Sync Balance (check for web purchases)
    
    @MainActor
    func syncBalance(userID: String) async throws {
        _ = try await fetchBalance(userID: userID)
        _ = try await fetchTransactions(userID: userID)
        print("🔄 COINS: Balance synced")
    }
    
    // MARK: - Transfer Coins (Subscription/Tip)
    
    @MainActor
    func transferCoins(
        fromUserID: String,
        toUserID: String,
        amount: Int,
        type: CoinTransactionType,
        subscriptionID: String? = nil
    ) async throws {
        
        // Validate sender has enough
        let senderBalance = try await fetchBalance(userID: fromUserID)
        guard senderBalance.availableCoins >= amount else {
            throw CoinError.insufficientBalance
        }
        
        let senderRef = db.collection(Collections.balances).document(fromUserID)
        let receiverRef = db.collection(Collections.balances).document(toUserID)
        
        // Deduct from sender
        try await senderRef.updateData([
            "availableCoins": FieldValue.increment(Int64(-amount)),
            "lifetimeSpent": FieldValue.increment(Int64(amount)),
            "lastUpdated": Date()
        ])
        
        // Credit to receiver (as pending until they cash out)
        try await receiverRef.updateData([
            "pendingCoins": FieldValue.increment(Int64(amount)),
            "lifetimeEarned": FieldValue.increment(Int64(amount)),
            "lastUpdated": Date()
        ])
        
        // Record sender transaction
        let senderTransaction = CoinTransaction(
            id: UUID().uuidString,
            userID: fromUserID,
            type: type == .subscriptionReceived ? .subscriptionSent : .tipSent,
            amount: -amount,
            balanceAfter: senderBalance.availableCoins - amount,
            relatedUserID: toUserID,
            relatedSubscriptionID: subscriptionID,
            description: type == .subscriptionReceived ? "Subscription payment" : "Tip sent",
            createdAt: Date()
        )
        
        try db.collection(Collections.transactions)
            .document(senderTransaction.id)
            .setData(from: senderTransaction)
        
        // Record receiver transaction
        let receiverTransaction = CoinTransaction(
            id: UUID().uuidString,
            userID: toUserID,
            type: type,
            amount: amount,
            balanceAfter: 0, // Will update on fetch
            relatedUserID: fromUserID,
            relatedSubscriptionID: subscriptionID,
            description: type == .subscriptionReceived ? "Subscription received" : "Tip received",
            createdAt: Date()
        )
        
        try db.collection(Collections.transactions)
            .document(receiverTransaction.id)
            .setData(from: receiverTransaction)
        
        // Refresh balance
        _ = try await fetchBalance(userID: fromUserID)
        
        print("💸 COINS: Transferred \(amount) coins from \(fromUserID) to \(toUserID)")
    }
    
    // MARK: - Move Pending to Available
    
    @MainActor
    func releasePendingCoins(userID: String) async throws {
        let balanceRef = db.collection(Collections.balances).document(userID)
        let doc = try await balanceRef.getDocument()
        
        guard let data = doc.data(),
              let pending = data["pendingCoins"] as? Int,
              pending > 0 else {
            return
        }
        
        try await balanceRef.updateData([
            "availableCoins": FieldValue.increment(Int64(pending)),
            "pendingCoins": 0,
            "lastUpdated": Date()
        ])
        
        _ = try await fetchBalance(userID: userID)
        print("✅ COINS: Released \(pending) pending coins")
    }
    
    // MARK: - Cash Out
    
    @MainActor
    func requestCashOut(
        userID: String,
        amount: Int,
        tier: UserTier,
        payoutMethod: PayoutMethod
    ) async throws -> CashOutRequest {
        
        // Validate minimum
        guard amount >= CashOutLimits.minimumCoins else {
            throw CoinError.belowMinimumCashOut
        }
        
        // Validate balance
        let balance = try await fetchBalance(userID: userID)
        guard balance.availableCoins >= amount else {
            throw CoinError.insufficientBalance
        }
        
        // Calculate split
        let (creatorAmount, platformAmount) = SubscriptionRevenueShare.calculateCashOut(
            coins: amount,
            tier: tier
        )
        
        // Create request
        let request = CashOutRequest(
            id: UUID().uuidString,
            userID: userID,
            coinAmount: amount,
            userTier: tier,
            creatorPercentage: SubscriptionRevenueShare.creatorShare(for: tier),
            creatorAmount: creatorAmount,
            platformAmount: platformAmount,
            status: .pending,
            payoutMethod: payoutMethod,
            createdAt: Date(),
            processedAt: nil,
            failureReason: nil
        )
        
        // Save request
        try db.collection(Collections.cashOuts)
            .document(request.id)
            .setData(from: request)
        
        // Deduct from balance
        let balanceRef = db.collection(Collections.balances).document(userID)
        try await balanceRef.updateData([
            "availableCoins": FieldValue.increment(Int64(-amount)),
            "lastUpdated": Date()
        ])
        
        // Record transaction
        let transaction = CoinTransaction(
            id: UUID().uuidString,
            userID: userID,
            type: .cashOut,
            amount: -amount,
            balanceAfter: balance.availableCoins - amount,
            relatedUserID: nil,
            relatedSubscriptionID: nil,
            description: "Cash out: $\(String(format: "%.2f", creatorAmount)) (\(Int(SubscriptionRevenueShare.creatorShare(for: tier) * 100))%)",
            createdAt: Date()
        )
        
        try db.collection(Collections.transactions)
            .document(transaction.id)
            .setData(from: transaction)
        
        _ = try await fetchBalance(userID: userID)
        
        print("💵 CASH OUT: \(amount) coins → $\(String(format: "%.2f", creatorAmount)) for \(tier.displayName)")
        return request
    }
    
    // MARK: - Fetch Transactions
    
    @MainActor
    func fetchTransactions(userID: String, limit: Int = 50) async throws -> [CoinTransaction] {
        let snapshot = try await db.collection(Collections.transactions)
            .whereField("userID", isEqualTo: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let transactions = snapshot.documents.compactMap { doc -> CoinTransaction? in
            try? doc.data(as: CoinTransaction.self)
        }
        
        self.transactions = transactions
        return transactions
    }
    
    // MARK: - Check Can Afford
    
    func canAfford(userID: String, amount: Int) async throws -> Bool {
        let balance = try await fetchBalance(userID: userID)
        return balance.availableCoins >= amount
    }
}

// MARK: - Errors

enum CoinError: LocalizedError {
    case insufficientBalance
    case belowMinimumCashOut
    case purchaseFailed
    case transferFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientBalance:
            return "Not enough Hype Coins"
        case .belowMinimumCashOut:
            return "Minimum cash out is \(CashOutLimits.minimumCoins) coins ($\(CashOutLimits.minimumCoins / 100))"
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        case .transferFailed:
            return "Transfer failed. Please try again."
        }
    }
}
