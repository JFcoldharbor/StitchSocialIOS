//
//  WalletView.swift
//  StitchSocial
//
//  Hype Coins wallet - purchase, balance, transactions, cash out
//

import SwiftUI

struct WalletView: View {
    
    // MARK: - Properties
    
    let userID: String
    let userTier: UserTier
    
    @ObservedObject private var coinService = HypeCoinService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var showingCashOut = false
    @State private var showingManageAccount = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
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
            // Coin icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Text("🔥")
                    .font(.system(size: 30))
            }
            .padding(.top, 20)
            
            // Balance
            Text("\(coinService.balance?.availableCoins ?? 0)")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
            
            Text("Hype Coins")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Cash value
            if let balance = coinService.balance {
                Text("≈ $\(String(format: "%.2f", balance.cashValue))")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
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
                // Manage Account button
                Button(action: { showingManageAccount = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage Account")
                                .font(.headline)
                            
                            Text("Purchase Hype Coins securely")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.top, 20)
                
                // Coin packages preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Packages")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(HypeCoinPackage.allCases, id: \.self) { package in
                        CoinPackageDisplayCard(package: package)
                    }
                }
                
                // Info text
                Text("Tap 'Manage Account' to securely purchase coins. Your balance syncs automatically.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
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

// MARK: - Coin Package Display Card (No Purchase - Web Only)

struct CoinPackageDisplayCard: View {
    let package: HypeCoinPackage
    
    var body: some View {
        HStack {
            // Coin amount
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("🔥")
                    Text("\(package.coins)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("coins")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Text("$\(String(format: "%.2f", package.cashValue)) value")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            // Price
            Text("$\(String(format: "%.2f", package.price))")
                .font(.headline)
                .foregroundColor(.yellow)
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

struct CashOutSheet: View {
    let userID: String
    let userTier: UserTier
    let availableCoins: Int
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var cashOutAmount: String = ""
    @State private var isProcessing = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private var coinAmount: Int {
        Int(cashOutAmount) ?? 0
    }
    
    private var creatorAmount: Double {
        let (creator, _) = SubscriptionRevenueShare.calculateCashOut(coins: coinAmount, tier: userTier)
        return creator
    }
    
    private var isValid: Bool {
        coinAmount >= CashOutLimits.minimumCoins && coinAmount <= availableCoins
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Available balance
                    VStack(spacing: 4) {
                        Text("Available")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("\(availableCoins) coins")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 20)
                    
                    // Amount input
                    VStack(spacing: 8) {
                        TextField("Enter amount", text: $cashOutAmount)
                            .keyboardType(.numberPad)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(12)
                        
                        Text("Minimum: \(CashOutLimits.minimumCoins) coins")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    // Breakdown
                    if coinAmount > 0 {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Your tier")
                                Spacer()
                                Text(userTier.displayName)
                                    .foregroundColor(.purple)
                            }
                            
                            HStack {
                                Text("Your share")
                                Spacer()
                                Text("\(Int(SubscriptionRevenueShare.creatorShare(for: userTier) * 100))%")
                                    .foregroundColor(.green)
                            }
                            
                            Divider().background(Color.gray)
                            
                            HStack {
                                Text("You'll receive")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("$\(String(format: "%.2f", creatorAmount))")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Cash out button
                    Button(action: processCashOut) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Cash Out")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.green : Color.gray)
                        .foregroundColor(isValid ? .black : .gray)
                        .cornerRadius(12)
                    }
                    .disabled(!isValid || isProcessing)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Cash Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .alert("Success!", isPresented: $showingSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Cash out request submitted. You'll receive $\(String(format: "%.2f", creatorAmount)) within 3-5 business days.")
        }
    }
    
    private func processCashOut() {
        isProcessing = true
        
        Task {
            do {
                _ = try await HypeCoinService.shared.requestCashOut(
                    userID: userID,
                    amount: coinAmount,
                    tier: userTier,
                    payoutMethod: .bankTransfer
                )
                
                await MainActor.run {
                    isProcessing = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isProcessing = false
                }
            }
        }
    }
}
