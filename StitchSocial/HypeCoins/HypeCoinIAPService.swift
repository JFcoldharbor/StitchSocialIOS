//
//  HypeCoinIAPService.swift
//  StitchSocial
//
//  Apple In-App Purchase rail for Hype Coins (StoreKit 2).
//
//  Dual-rail context: web (Stripe) is the cheaper path users see first via the
//  "Save on web" banner in WalletView. This service is the in-app fallback for
//  users who don't want to leave the app. Apple takes 15–30% here, so coin
//  counts are identical to web but iOS prices are raised (~50%) to absorb it.
//
//  Server side: signed JWS is forwarded to the `verifyAppleIAP` Cloud Function,
//  which validates with the App Store Server API and credits the wallet with
//  idempotency key `apple_<transactionId>` (parallel to `stripe_<sessionId>`).
//

import Foundation
import StoreKit
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class HypeCoinIAPService: ObservableObject {

    // MARK: - Singleton

    static let shared = HypeCoinIAPService()

    // MARK: - Published State

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private let functions = Functions.functions()

    private var productIDs: [String] {
        HypeCoinPackage.allCases.map(\.appleProductID)
    }

    private init() {
        transactionListener = startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    /// Load Product objects from the App Store for all coin packs.
    /// Call once at app launch (or first time the wallet opens) — products are cached by StoreKit.
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: productIDs)
            // Preserve package order (Starter → Max), not whatever order StoreKit returned.
            let ordered = HypeCoinPackage.allCases.compactMap { pkg in
                fetched.first(where: { $0.id == pkg.appleProductID })
            }
            self.products = ordered
            #if DEBUG
            print("🛒 IAP: Loaded \(ordered.count)/\(productIDs.count) products")
            for p in ordered {
                print("   • \(p.id) → \(p.displayPrice)")
            }
            #endif
        } catch {
            self.lastError = error.localizedDescription
            #if DEBUG
            print("❌ IAP: Failed to load products — \(error)")
            #endif
        }
    }

    /// Convenience lookup for a coin pack.
    func product(for package: HypeCoinPackage) -> Product? {
        products.first(where: { $0.id == package.appleProductID })
    }

    // MARK: - Purchase

    /// Buy a coin pack via Apple IAP. Returns true if the purchase succeeded and
    /// the backend credited the wallet. Returns false if the user cancelled or
    /// the purchase is still pending parental approval.
    @discardableResult
    func purchase(_ package: HypeCoinPackage) async throws -> Bool {
        guard let product = product(for: package) else {
            throw IAPError.productNotLoaded(package.appleProductID)
        }
        guard let userID = Auth.auth().currentUser?.uid else {
            throw IAPError.notSignedIn
        }

        isLoading = true
        defer { isLoading = false }

        // No appAccountToken — backend identifies the user from the callable's
        // auth context (`context.auth.uid`), and Apple already binds the JWS
        // to the device's signed-in App Store account.
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            try await handle(verification, userID: userID, package: package)
            return true

        case .userCancelled:
            #if DEBUG
            print("🛒 IAP: User cancelled \(package.appleProductID)")
            #endif
            return false

        case .pending:
            // Ask-to-Buy / SCA — Apple will resurface via Transaction.updates.
            #if DEBUG
            print("⏳ IAP: Purchase pending external approval")
            #endif
            return false

        @unknown default:
            throw IAPError.unknownPurchaseResult
        }
    }

    // MARK: - Transaction Handling

    /// Background listener for StoreKit transaction updates — restored purchases,
    /// Ask-to-Buy approvals, interrupted purchases. Without this, a transaction
    /// that completes after the app was killed would never credit the wallet.
    private nonisolated func startTransactionListener() -> Task<Void, Never> {
        return Task.detached {
            for await update in Transaction.updates {
                await MainActor.run {
                    Task { await self.processBackgroundUpdate(update) }
                }
            }
        }
    }

    private func processBackgroundUpdate(_ update: VerificationResult<Transaction>) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        do {
            try await handle(update, userID: userID, package: nil)
        } catch {
            #if DEBUG
            print("❌ IAP: Background transaction handling failed — \(error)")
            #endif
        }
    }

    /// Verify the signed transaction server-side, credit coins, then finish.
    /// Always call `transaction.finish()` once the backend confirms credit —
    /// otherwise StoreKit will keep retrying the transaction forever.
    private func handle(
        _ verification: VerificationResult<Transaction>,
        userID: String,
        package: HypeCoinPackage?
    ) async throws {

        // Client-side signature check (cheap pre-flight; server re-verifies).
        let transaction: Transaction
        switch verification {
        case .verified(let t):
            transaction = t
        case .unverified(_, let error):
            throw IAPError.unverifiedTransaction(error.localizedDescription)
        }

        // The JWS is the canonical thing the backend re-validates with Apple.
        let signedPayload = verification.jwsRepresentation

        // Resolve the package from product ID (background listener won't know it).
        let resolvedPackage = package
            ?? HypeCoinPackage.allCases.first(where: { $0.appleProductID == transaction.productID })

        guard let pkg = resolvedPackage else {
            // Not one of our coin packs — finish and ignore so StoreKit stops retrying.
            await transaction.finish()
            return
        }

        try await sendToBackend(
            signedPayload: signedPayload,
            userID: userID,
            productID: transaction.productID,
            transactionID: transaction.id,
            expectedCoins: pkg.coins
        )

        // Backend credited the wallet — safe to finish.
        await transaction.finish()

        #if DEBUG
        print("✅ IAP: Credited \(pkg.coins) coins for \(transaction.productID) (txn \(transaction.id))")
        #endif
    }

    // MARK: - Backend Verification

    /// Hand the signed JWS to Firebase Functions for App Store Server API validation.
    /// The function returns once the wallet is credited (idempotent on transactionId).
    private func sendToBackend(
        signedPayload: String,
        userID: String,
        productID: String,
        transactionID: UInt64,
        expectedCoins: Int
    ) async throws {
        let payload: [String: Any] = [
            "signedTransaction": signedPayload,
            "productId": productID,
            "transactionId": String(transactionID),
            "expectedCoins": expectedCoins
        ]

        do {
            _ = try await functions.httpsCallable("verifyAppleIAP").call(payload)
        } catch {
            #if DEBUG
            print("❌ IAP: Backend verification failed — \(error)")
            #endif
            throw IAPError.backendVerificationFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum IAPError: LocalizedError {
    case productNotLoaded(String)
    case notSignedIn
    case unverifiedTransaction(String)
    case backendVerificationFailed(String)
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .productNotLoaded(let id):
            return "Coin pack not available right now (\(id)). Try again in a moment."
        case .notSignedIn:
            return "Please sign in to purchase coins."
        case .unverifiedTransaction(let reason):
            return "Purchase couldn't be verified: \(reason)"
        case .backendVerificationFailed(let reason):
            return "Purchase verification failed: \(reason). Your card wasn't charged twice — contact support if coins don't appear."
        case .unknownPurchaseResult:
            return "Unexpected purchase result. Please try again."
        }
    }
}

