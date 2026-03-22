//
//  CreatorPricingSettingsView.swift
//  StitchSocial
//
//  Created by James Garmon on 3/11/26.
//


//
//  CreatorPricingSettingsView.swift
//  StitchSocial
//
//  Creator-facing settings to enable subscriptions and set pricing.
//  Rookie–Veteran: locked at 200 coins. Influencer+: choose 200/500/900/2000.
//  60-day cooldown on price changes. Shows subscriber count + earnings.
//
//  CACHING: Reads plan from SubscriptionService cache (10min TTL).
//  Single write on save. No polling.
//

import SwiftUI

struct CreatorPricingSettingsView: View {
    
    let creatorID: String
    let creatorTier: UserTier
    
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEnabled = true
    @State private var tierPricing: TierPricing = TierPricing()
    @State private var welcomeMessage = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSaved = false
    
    
    
    private var perks: [SubscriptionPerk] {
        // Show max perks (Max tier) so creator sees full perk ladder
        return SubscriptionPerks.perks(for: .max)
    }
    


    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    content
                }
            }
            .navigationTitle("Subscription Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .foregroundColor(.cyan)
                        .disabled(isSaving)
                }
            }
        }
        .task {
            await loadPlan()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Saved", isPresented: $showSaved) {
            Button("OK") { dismiss() }
        } message: {
            Text("Subscription settings updated.")
        }
    }
    
    // MARK: - Content
    
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Enable toggle
                enableSection
                
                if isEnabled {
                    // Pricing
                    pricingSection
                    
                    // Cooldown warning
                    if let plan = subscriptionService.creatorPlan, !plan.canChangePrice {
                        cooldownBanner(daysLeft: plan.daysUntilPriceChange)
                    }
                    
                    // Perks preview
                    perksPreview
                    
                    // Stats
                    if let plan = subscriptionService.creatorPlan {
                        statsSection(plan)
                    }
                    
                    // Welcome message
                    welcomeSection
                }
            }
            .padding()
        }
    }
    
    // MARK: - Enable Section
    
    private var enableSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Subscriptions")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text("Allow fans to subscribe to you")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .tint(.cyan)
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription Tiers")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text("Prices are fixed by platform. Customize which perks each tier unlocks.")
                .font(.caption)
                .foregroundColor(.gray)

            VStack(spacing: 8) {
                ForEach(CoinPriceTier.allCases, id: \.self) { tier in
                    tierPriceRow(tier)
                }
            }

            let share = SubscriptionRevenueShare.creatorShare(for: creatorTier)
            Text("Your revenue share: \(Int(share * 100))% (\(creatorTier.displayName) tier)")
                .font(.system(size: 12))
                .foregroundColor(.cyan)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }

    @State private var expandedTier: CoinPriceTier? = nil

    // All perks creator can assign (excludes supportBadge — always on)
    private let assignablePerks: [SubscriptionPerk] = [
        .communityAccess, .noAds, .dmAccess, .exclusiveCollections,
        .hypeBoost15, .earlyContent, .commentHighlights,
        .hypeBoost20, .priorityQA, .exclusiveEmotes, .coHostEligibility, .communityMod
    ]

    @ViewBuilder
    private func tierPriceRow(_ tier: CoinPriceTier) -> some View {
        let currentPrice = tierPricing.price(for: tier)
        let tierPerks = tierPricing.perks(for: tier)
        let isExpanded = expandedTier == tier

        VStack(spacing: 0) {
            // Header row
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) {
                expandedTier = isExpanded ? nil : tier
            }}) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(tierPerks.count) perks")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("\(tier.rawValue) coins")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.yellow)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.gray)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            // Perk toggles — expanded
            if isExpanded {
                Divider().background(Color.gray.opacity(0.2))
                VStack(spacing: 0) {
                    // Supporter Badge — locked on
                    HStack {
                        Image(systemName: SubscriptionPerk.supportBadge.icon)
                            .font(.system(size: 11)).foregroundColor(.cyan).frame(width: 20)
                        Text(SubscriptionPerk.supportBadge.displayName)
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    ForEach(assignablePerks, id: \.self) { perk in
                        let isOn = tierPerks.contains(perk)
                        Button(action: {
                            var p = tierPricing
                            p.togglePerk(perk, for: tier)
                            tierPricing = p
                        }) {
                            HStack {
                                Image(systemName: perk.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(isOn ? .cyan : .gray.opacity(0.4))
                                    .frame(width: 20)
                                Text(perk.displayName)
                                    .font(.system(size: 13))
                                    .foregroundColor(isOn ? .white : .gray)
                                Spacer()
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isOn ? .cyan : .gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .background(Color.black.opacity(0.2))
            }
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Cooldown Banner
    
    private func cooldownBanner(daysLeft: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Price Change Locked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(daysLeft) days until you can change pricing again")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Perks Preview
    
    private var perksPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subscriber Perks")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("Perks are automatic based on your tier. As you grow, subscribers get more.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
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
            
            if perks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Supporter Badge — subscribers show their support")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }
    
    // MARK: - Stats
    
    private func statsSection(_ plan: CreatorSubscriptionPlan) -> some View {
        HStack(spacing: 16) {
            statCard(title: "Subscribers", value: "\(plan.subscriberCount)", color: .cyan)
            statCard(title: "Total Earned", value: "\(plan.totalEarned) coins", color: .yellow)
        }
    }
    
    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Welcome Message
    
    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome Message (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            TextEditor(text: $welcomeMessage)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(minHeight: 60)
                .padding(8)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
                .scrollContentBackground(.hidden)
            
            Text("Shown to new subscribers after they subscribe")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
    }
    
    // MARK: - Actions
    
    private func loadPlan() async {
        isLoading = true
        do {
            if let plan = try await subscriptionService.fetchCreatorPlan(creatorID: creatorID) {
                await MainActor.run {
                    isEnabled = plan.isEnabled
                    tierPricing = plan.tierPricing
                    welcomeMessage = plan.customWelcomeMessage ?? ""
                }
            }
        } catch {
            print("⚠️ PRICING: Failed to load plan")
        }
        isLoading = false
    }
    
    private func save() {
        isSaving = true
        Task {
            do {
                _ = try await subscriptionService.createOrUpdatePlan(
                    creatorID: creatorID,
                    creatorTier: creatorTier,
                    isEnabled: isEnabled,
                    tierPricing: tierPricing,
                    welcomeMessage: welcomeMessage.isEmpty ? nil : welcomeMessage
                )
                await MainActor.run {
                    isSaving = false
                    showSaved = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
