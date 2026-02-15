//
//  SubscribeToJoinView.swift
//  StitchSocial
//
//  Layer 8: Views - Subscribe prompt when joining a community
//  Dependencies: SubscriptionService, HypeCoinService, WalletView
//  Shows creator's subscription tiers with pricing, lets user subscribe or buy coins
//

import SwiftUI

struct SubscribeToJoinView: View {
    
    let userID: String
    let creatorID: String
    var onSubscribed: (() -> Void)?
    
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var coinService = HypeCoinService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var plan: CreatorSubscriptionPlan?
    @State private var isLoading = true
    @State private var isSubscribing = false
    @State private var showingBuyCoins = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
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
            .navigationTitle("Subscribe to Join")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .task {
            await loadPlan()
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
    
    // MARK: - Subscription Content
    
    private func subscriptionContent(_ plan: CreatorSubscriptionPlan) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance display
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: 18))
                    Text("\(coinService.balance?.availableCoins ?? 0) Hype Coins")
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
                
                // Tier cards
                if plan.supporterEnabled {
                    tierCard(
                        tier: .supporter,
                        price: plan.supporterPrice,
                        canAfford: (coinService.balance?.availableCoins ?? 0) >= plan.supporterPrice
                    )
                }
                
                if plan.superFanEnabled {
                    tierCard(
                        tier: .superFan,
                        price: plan.superFanPrice,
                        canAfford: (coinService.balance?.availableCoins ?? 0) >= plan.superFanPrice
                    )
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Tier Card
    
    private func tierCard(tier: SubscriptionTier, price: Int, canAfford: Bool) -> some View {
        let dollarPrice = String(format: "%.2f", HypeCoinValue.toDollars(price))
        let coinsNeeded = price - (coinService.balance?.availableCoins ?? 0)
        let borderColor: Color = tier == .superFan ? Color.yellow.opacity(0.3) : Color.white.opacity(0.1)
        let buttonBg: Color = canAfford ? Color.cyan : Color.white.opacity(0.1)
        let buttonFg: Color = canAfford ? .black : .white
        
        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(price) coins/month")
                        .font(.system(size: 13))
                        .foregroundColor(.yellow)
                }
                
                Spacer()
                
                Text("$\(dollarPrice)/mo")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tier.perks, id: \.self) { perk in
                    HStack(spacing: 8) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 11))
                            .foregroundColor(.cyan)
                            .frame(width: 20)
                        Text(perk.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            Button {
                if canAfford {
                    Task { await subscribe(tier: tier) }
                } else {
                    showingBuyCoins = true
                }
            } label: {
                subscribeButtonLabel(canAfford: canAfford, price: price, coinsNeeded: coinsNeeded)
                    .foregroundColor(buttonFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(buttonBg)
                    .cornerRadius(12)
            }
            .disabled(isSubscribing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private func subscribeButtonLabel(canAfford: Bool, price: Int, coinsNeeded: Int) -> some View {
        if isSubscribing {
            ProgressView().tint(.black)
        } else if canAfford {
            Text("Subscribe · \(price) coins")
                .font(.system(size: 15, weight: .bold))
        } else {
            Text("Need \(coinsNeeded) more coins")
                .font(.system(size: 15, weight: .bold))
        }
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
    
    private func loadPlan() async {
        isLoading = true
        do {
            plan = try await subscriptionService.fetchCreatorPlan(creatorID: creatorID)
            _ = try await coinService.fetchBalance(userID: userID)
        } catch {
            print("⚠️ SUBSCRIBE: Failed to load plan - \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func subscribe(tier: SubscriptionTier) async {
        let coins = coinService.balance?.availableCoins ?? 0
        let price = tier == .superFan ? (plan?.superFanPrice ?? 400) : (plan?.supporterPrice ?? 200)
        
        guard coins >= price else {
            await MainActor.run {
                showingBuyCoins = true
            }
            return
        }
        
        isSubscribing = true
        do {
            _ = try await subscriptionService.subscribe(
                subscriberID: userID,
                creatorID: creatorID,
                tier: tier
            )
            
            // Auto-join community after subscribing
            _ = try? await CommunityService.shared.joinCommunity(
                userID: userID,
                username: "",
                displayName: "",
                creatorID: creatorID
            )
            
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
