//
//  SubscribeToJoinView.swift
//  StitchSocial
//
//  Subscribe prompt — works from profile Subscribe button and community join.
//  Shows creator's single price, perks based on creator tier.
//
//  CACHING: Reads from SubscriptionService's cached plan (10min TTL).
//  Balance fetched once on appear — no polling.
//

import SwiftUI

struct SubscribeToJoinView: View {
    
    let userID: String
    let creatorID: String
    let creatorTier: UserTier
    let creatorName: String
    let creatorImageURL: String?
    var onSubscribed: (() -> Void)?
    
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var coinService = HypeCoinService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var plan: CreatorSubscriptionPlan?
    @State private var selectedTier: CoinPriceTier = .starter
    @State private var isLoading = true
    @State private var isSubscribing = false
    @State private var showingBuyCoins = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private var perks: [SubscriptionPerk] {
        plan?.tierPricing.perks(for: selectedTier) ?? SubscriptionPerks.perks(for: selectedTier)
    }
    
    private var balance: Int { coinService.balance?.availableCoins ?? 0 }

    private func priceFor(_ tier: CoinPriceTier) -> Int {
        plan?.price(for: tier) ?? tier.rawValue
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.cyan)
                } else if let plan = plan, plan.isEnabled {
                    subscriptionContent(plan)
                } else {
                    noSubscriptionsView
                }
            }
            .navigationTitle("Subscribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .task {
            await loadData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("Buy Coins") { showingBuyCoins = true }
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingBuyCoins) {
            WalletView(userID: userID, userTier: .rookie)
        }
    }
    
    // MARK: - Content
    
    private func subscriptionContent(_ plan: CreatorSubscriptionPlan) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                creatorHeader
                balanceBar
                tierPickerSection(plan)
                perksSection
                cycleNote
            }
            .padding(20)
        }
    }
    


    @ViewBuilder
    private func tierRow(_ tier: CoinPriceTier, plan: CreatorSubscriptionPlan) -> some View {
        let price = priceFor(tier)
        let canAfford = balance >= price
        let isSelected = selectedTier == tier
        let perkCount = plan.tierPricing.perks(for: tier).count
        let bg: Color = isSelected ? Color.cyan.opacity(0.1) : Color.gray.opacity(0.08)
        let border: Color = isSelected ? Color.cyan.opacity(0.4) : .clear

        Button(action: { selectedTier = tier }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(perkCount) perks")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("\(price) coins")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canAfford ? .yellow : .red.opacity(0.7))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
            .cornerRadius(12)
        }
    }

    // MARK: - Tier Picker

    private func tierPickerSection(_ plan: CreatorSubscriptionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Your Tier")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            ForEach(CoinPriceTier.allCases, id: \.self) { tier in
                tierRow(tier, plan: plan)
            }

            let price = priceFor(selectedTier)
            let canAfford = balance >= price
            Button {
                if canAfford { Task { await subscribe(price: price) } }
                else { showingBuyCoins = true }
            } label: {
                Group {
                    if isSubscribing {
                        ProgressView().tint(.black)
                    } else if canAfford {
                        Text("Subscribe · \(price) coins")
                            .font(.system(size: 16, weight: .bold))
                    } else {
                        Text("Need \(price - balance) more coins")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundColor(canAfford ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canAfford ? Color.cyan : Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(isSubscribing)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    // MARK: - Creator Header
    
    private var creatorHeader: some View {
        HStack(spacing: 14) {
            // Creator avatar
            AsyncImage(url: URL(string: creatorImageURL ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Text(String(creatorName.prefix(1)).uppercased())
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(creatorName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                    Text(creatorTier.displayName)
                        .font(.caption)
                }
                .foregroundColor(.cyan)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Balance Bar
    
    private var balanceBar: some View {
        HStack(spacing: 8) {
            Text("🔥")
                .font(.system(size: 18))
            Text("\(balance) Hype Coins")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.yellow)
            
            Spacer()
            
            Button {
                showingBuyCoins = true
            } label: {
                Text("Buy Coins")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    // MARK: - Perks Section
    
    private var perksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            if perks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.pink)
                        .frame(width: 20)
                    Text("Support \(creatorName) directly")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                ForEach(perks, id: \.self) { perk in
                    HStack(spacing: 10) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.cyan)
                            .frame(width: 22)
                        
                        Text(perk.displayName)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
    }
    
    // MARK: - Cycle Note
    
    private var cycleNote: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("First subscription: 60-day trial period")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
            
            Text("After that, renews every 30 days. Cancel anytime.")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.06))
        .cornerRadius(10)
    }
    
    // MARK: - No Subscriptions
    
    private var noSubscriptionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.2))
            
            Text("Subscriptions Not Available")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            
            Text("This creator hasn't set up subscriptions yet.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        isLoading = true
        do {
            plan = try await subscriptionService.fetchCreatorPlan(creatorID: creatorID)
            _ = try await coinService.fetchBalance(userID: userID)
        } catch {
            print("⚠️ SUBSCRIBE: Failed to load - \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func subscribe(price: Int) async { // price = tierPricing.price(for: selectedTier)
        guard balance >= price else {
            await MainActor.run { showingBuyCoins = true }
            return
        }
        
        isSubscribing = true
        do {
            _ = try await subscriptionService.subscribe(
                subscriberID: userID,
                creatorID: creatorID,
                creatorTier: creatorTier
            )
            
            // Auto-join community if creator tier supports it
            if SubscriptionPerks.hasCommunityAccess(creatorTier: creatorTier, coinTier: selectedTier) {
                _ = try? await CommunityService.shared.joinCommunity(
                    userID: userID,
                    username: "",
                    displayName: "",
                    creatorID: creatorID
                )
            }
            
            onSubscribed?()
            await MainActor.run { dismiss() }
        } catch let error as CoinError where error == .insufficientBalance {
            await MainActor.run {
                isSubscribing = false
                showingBuyCoins = true
            }
        } catch {
            await MainActor.run {
                isSubscribing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
