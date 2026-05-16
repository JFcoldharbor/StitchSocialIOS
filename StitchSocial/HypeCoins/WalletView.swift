//
//  WalletView.swift
//  StitchSocial
//
//  Hype Coins wallet - purchase, balance, transactions, cash out
//

import SwiftUI
import StoreKit

struct WalletView: View {
    
    // MARK: - Properties
    
    let userID: String
    let userTier: UserTier
    
    @ObservedObject private var coinService = HypeCoinService.shared
    @ObservedObject private var iapService = HypeCoinIAPService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showingCashOut = false
    @State private var showingManageAccount = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var purchasingPackage: HypeCoinPackage?
    
    private let tabs = ["Balance", "Buy Coins", "History"]
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Balance Header
                    balanceHeader
                    
                    // Tab Bar
                    tabBar
                    
                    // Tab Content
                    tabContent
                }
            }
            .navigationTitle("Hype Coins")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(action: { Task { await syncBalance() } }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.cyan)
                },
                trailing: Button("Done") { dismiss() }
                    .foregroundColor(.cyan)
            )
            .refreshable {
                await syncBalance()
            }
        }
        .task {
            await loadData()
            await iapService.loadProducts()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingCashOut) {
            CashOutSheet(
                userID: userID,
                userTier: userTier,
                availableCoins: coinService.balance?.availableCoins ?? 0
            )
        }
        .fullScreenCover(isPresented: $showingManageAccount) {
            AccountWebView.wallet(userID: userID) {
                // On dismiss - sync balance
                Task {
                    try? await HypeCoinService.shared.syncBalance(userID: userID)
                }
            }
        }
    }
    
    // MARK: - Balance Header
    
    private var balanceHeader: some View {
        VStack(spacing: 8) {
            HypeCoinView(size: 90)
                .padding(.top, 20)
            
            // Balance
            Text("\(coinService.balance?.availableCoins ?? 0)")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
            
            Text("Hype Coins")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Pending coins
            if let pending = coinService.balance?.pendingCoins, pending > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(pending) pending")
                        .font(.caption)
                }
                .foregroundColor(.yellow)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 8) {
                        Text(tabs[index])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedTab == index ? .white : .gray)
                        
                        Rectangle()
                            .fill(selectedTab == index ? Color.yellow : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            balanceTab
        case 1:
            buyCoinsTab
        case 2:
            historyTab
        default:
            EmptyView()
        }
    }
    
    // MARK: - Balance Tab
    
    private var balanceTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Actions
                HStack(spacing: 12) {
                    quickActionButton(
                        icon: "globe",
                        title: "Manage",
                        color: .cyan
                    ) {
                        showingManageAccount = true
                    }
                    
                    quickActionButton(
                        icon: "plus.circle.fill",
                        title: "Buy",
                        color: .green
                    ) {
                        selectedTab = 1
                    }
                    
                    if AdRevenueShare.canAccessAds(tier: userTier) {
                        quickActionButton(
                            icon: "banknote",
                            title: "Cash Out",
                            color: .yellow
                        ) {
                            showingCashOut = true
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Stats
                VStack(spacing: 12) {
                    statRow(title: "Lifetime Earned", value: "\(coinService.balance?.lifetimeEarned ?? 0)")
                    statRow(title: "Lifetime Spent", value: "\(coinService.balance?.lifetimeSpent ?? 0)")
                    
                    if let balance = coinService.balance {
                        Divider().background(Color.gray.opacity(0.3))
                        
                        HStack {
                            Text("Your Tier")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(userTier.displayName)
                                .foregroundColor(.purple)
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("Cash Out Rate")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(SubscriptionRevenueShare.creatorShare(for: userTier) * 100))%")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Buy Coins Tab

    private var buyCoinsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero: web discount banner (same coins, lower price on web)
                webDiscountBanner
                    .padding(.top, 20)

                // In-app IAP packs
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Or buy in-app")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("Instant")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    ForEach(HypeCoinPackage.allCases, id: \.self) { package in
                        IAPPackageCard(
                            package: package,
                            product: iapService.product(for: package),
                            isPurchasing: purchasingPackage == package,
                            onBuy: { purchase(package) }
                        )
                    }
                }

                // Disclosure
                Text("In-app prices reflect Apple's transaction fees. Buying on web saves you up to $\(Int(HypeCoinPackage.max.webSavings)) on the largest pack.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
    }

    // MARK: - Web Discount Banner

    private var webDiscountBanner: some View {
        Button(action: { showingManageAccount = true }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 18))
                    Text("Save up to $\(Int(HypeCoinPackage.max.webSavings)) on web")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)

                Text("Same coins, better deal on stitchsocial.me. Your balance syncs back automatically.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(14)
        }
    }

    // MARK: - IAP Purchase

    private func purchase(_ package: HypeCoinPackage) {
        guard purchasingPackage == nil else { return }
        purchasingPackage = package

        Task {
            defer { purchasingPackage = nil }
            do {
                let success = try await iapService.purchase(package)
                if success {
                    // The Firestore listener in HypeCoinCoordinator will surface the
                    // success animation; we just force a sync as a belt-and-braces refresh.
                    try? await HypeCoinService.shared.syncBalance(userID: userID)
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    // MARK: - History Tab
    
    private var historyTab: some View {
        ScrollView {
            if coinService.transactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No transactions yet")
                        .foregroundColor(.gray)
                }
                .padding(.top, 50)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(coinService.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func quickActionButton(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }
    
    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        do {
            _ = try await HypeCoinService.shared.fetchBalance(userID: userID)
            _ = try await HypeCoinService.shared.fetchTransactions(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func syncBalance() async {
        do {
            try await HypeCoinService.shared.syncBalance(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - IAP Package Card (Apple in-app purchase)

struct IAPPackageCard: View {
    let package: HypeCoinPackage
    let product: Product?
    let isPurchasing: Bool
    let onBuy: () -> Void

    /// Prefer Apple's localized display price (handles currency + locale).
    /// Fall back to our raw USD figure only when StoreKit hasn't loaded yet.
    private var displayPrice: String {
        if let product = product { return product.displayPrice }
        return "$\(String(format: "%.2f", package.iosPrice))"
    }

    var body: some View {
        HStack(spacing: 12) {
            HypeCoinView(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(package.coins) coins")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(package.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: onBuy) {
                if isPurchasing {
                    ProgressView()
                        .tint(.black)
                        .frame(minWidth: 70)
                } else {
                    Text(displayPrice)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(minWidth: 70)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(product == nil ? Color.gray : Color.yellow)
            .cornerRadius(20)
            .disabled(product == nil || isPurchasing)
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: CoinTransaction
    
    var body: some View {
        HStack {
            // Icon
            Circle()
                .fill(transaction.amount > 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: transaction.amount > 0 ? "arrow.down" : "arrow.up")
                        .foregroundColor(transaction.amount > 0 ? .green : .red)
                )
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Text(transaction.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Amount
            Text("\(transaction.amount > 0 ? "+" : "")\(transaction.amount)")
                .font(.headline)
                .foregroundColor(transaction.amount > 0 ? .green : .red)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Cash Out Sheet

// CashOutSheet moved to CashOutView.swift
