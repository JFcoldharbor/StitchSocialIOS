//
//  AdOpportunitiesView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/2/26.
//


//
//  AdOpportunitiesView.swift
//  StitchSocial
//
//  Creator-facing ad marketplace (Influencer+ only)
//

import SwiftUI

struct AdOpportunitiesView: View {
    
    // MARK: - Properties
    
    let user: BasicUserInfo
    @StateObject private var adService = AdService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var selectedOpportunity: AdOpportunity?
    @State private var showingCampaignDetail = false
    @State private var showingPartnershipDetail = false
    @State private var selectedPartnership: AdPartnership?
    
    private let tabs = ["Available", "My Ads", "Earnings"]
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !AdRevenueShare.canAccessAds(tier: user.tier) {
                lockedView
            } else {
                VStack(spacing: 0) {
                    headerView
                    tabBar
                    tabContent
                }
            }
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $showingCampaignDetail) {
            if let opportunity = selectedOpportunity {
                CampaignDetailView(
                    opportunity: opportunity,
                    userTier: user.tier,
                    onAccept: { acceptOpportunity(opportunity) },
                    onDecline: { declineOpportunity(opportunity) }
                )
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("Ad Opportunities")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Placeholder for symmetry
                Color.clear.frame(width: 24, height: 24)
            }
            
            // Rev share banner
            HStack {
                Text("Your rev share:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("\(Int(AdRevenueShare.creatorShare(for: user.tier) * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(6)
                
                Spacer()
                
                Text(user.tier.displayName)
                    .font(.caption)
                    .foregroundColor(.purple)
            }
        }
        .padding()
        .background(Color.black)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(tabs[index])
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedTab == index ? .white : .gray)
                            
                            if index == 0 && !adService.availableOpportunities.isEmpty {
                                Text("(\(adService.availableOpportunities.count))")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if index == 1 && !adService.activePartnerships.isEmpty {
                                Text("(\(adService.activePartnerships.count))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Rectangle()
                            .fill(selectedTab == index ? Color.purple : Color.clear)
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
            availableOpportunitiesTab
        case 1:
            myAdsTab
        case 2:
            earningsTab
        default:
            EmptyView()
        }
    }
    
    // MARK: - Available Opportunities Tab
    
    private var availableOpportunitiesTab: some View {
        ScrollView {
            if adService.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 50)
            } else if adService.availableOpportunities.isEmpty {
                emptyStateView(
                    icon: "sparkles",
                    title: "No Opportunities Yet",
                    message: "New brand partnerships will appear here when they match your content."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(adService.availableOpportunities) { opportunity in
                        OpportunityCard(opportunity: opportunity)
                            .onTapGesture {
                                selectedOpportunity = opportunity
                                showingCampaignDetail = true
                            }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - My Ads Tab
    
    private var myAdsTab: some View {
        ScrollView {
            if adService.activePartnerships.isEmpty {
                emptyStateView(
                    icon: "rectangle.stack",
                    title: "No Active Partnerships",
                    message: "Accept opportunities to start showing ads in your threads."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(adService.activePartnerships) { partnership in
                        PartnershipCard(partnership: partnership)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Earnings Tab
    
    private var earningsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats cards
                if let stats = adService.creatorStats {
                    earningsStatsView(stats: stats)
                } else {
                    emptyStateView(
                        icon: "dollarsign.circle",
                        title: "No Earnings Yet",
                        message: "Start accepting partnerships to earn revenue."
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Earnings Stats
    
    private func earningsStatsView(stats: CreatorAdStats) -> some View {
        VStack(spacing: 16) {
            // Total earnings card
            VStack(spacing: 8) {
                Text("Total Earnings")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("$\(String(format: "%.2f", stats.totalEarnings))")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(16)
            
            // Stats grid
            HStack(spacing: 12) {
                statCard(title: "Impressions", value: formatNumber(stats.totalImpressions))
                statCard(title: "Partnerships", value: "\(stats.totalPartnerships)")
            }
            
            HStack(spacing: 12) {
                statCard(title: "Pending", value: "$\(String(format: "%.2f", stats.pendingPayout))")
                statCard(title: "Active Ads", value: "\(stats.activePartnerships)")
            }
            
            // Last payout
            if let lastPayout = stats.lastPayoutDate, let amount = stats.lastPayoutAmount {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Last Payout")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("$\(String(format: "%.2f", amount))")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text(lastPayout, style: .date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
        }
    }
    
    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
    
    // MARK: - Locked View
    
    private var lockedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Influencer+ Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Reach Influencer tier to unlock ad opportunities and start earning from your content.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 8) {
                tierRequirement(tier: .influencer, share: 25)
                tierRequirement(tier: .ambassador, share: 28)
                tierRequirement(tier: .elite, share: 32)
                tierRequirement(tier: .partner, share: 35)
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
            
            Button(action: { dismiss() }) {
                Text("Got It")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
    
    private func tierRequirement(tier: UserTier, share: Int) -> some View {
        HStack {
            Text(tier.displayName)
                .font(.subheadline)
                .foregroundColor(user.tier == tier ? .purple : .white)
            
            Spacer()
            
            Text("\(share)% rev share")
                .font(.caption)
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 50)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        do {
            _ = try await adService.fetchOpportunities(for: user.id, tier: user.tier)
            _ = try await adService.fetchActivePartnerships(for: user.id)
            _ = try await adService.fetchCreatorStats(creatorID: user.id)
        } catch {
            print("❌ AD: Failed to load data - \(error.localizedDescription)")
        }
    }
    
    private func acceptOpportunity(_ opportunity: AdOpportunity) {
        Task {
            do {
                _ = try await adService.acceptOpportunity(opportunity, creatorTier: user.tier)
                showingCampaignDetail = false
            } catch {
                print("❌ AD: Failed to accept - \(error.localizedDescription)")
            }
        }
    }
    
    private func declineOpportunity(_ opportunity: AdOpportunity) {
        Task {
            do {
                try await adService.declineOpportunity(opportunity)
                showingCampaignDetail = false
            } catch {
                print("❌ AD: Failed to decline - \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
}

// MARK: - Opportunity Card

struct OpportunityCard: View {
    let opportunity: AdOpportunity
    
    var body: some View {
        HStack(spacing: 12) {
            // Brand logo
            AsyncImage(url: URL(string: opportunity.campaign.brandLogoURL ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.3)
                    Text(opportunity.campaign.category.icon)
                        .font(.title)
                }
            }
            .frame(width: 56, height: 56)
            .cornerRadius(12)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.campaign.brandName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(opportunity.campaign.category.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(opportunity.campaign.budgetRange)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Match score
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(opportunity.matchScore)%")
                    .font(.headline)
                    .foregroundColor(opportunity.matchScore >= 80 ? .green : .yellow)
                
                Text("match")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Partnership Card

struct PartnershipCard: View {
    let partnership: AdPartnership
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Brand thumbnail
                AsyncImage(url: URL(string: partnership.adThumbnailURL)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(partnership.brandName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(String(format: "%.2f", partnership.totalEarnings))")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Text("\(partnership.totalImpressions) views")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Revenue share info
            HStack {
                Text("Your share: \(Int(partnership.revenueShareCreator * 100))%")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("Since \(partnership.acceptedAt, style: .date)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Campaign Detail View

struct CampaignDetailView: View {
    let opportunity: AdOpportunity
    let userTier: UserTier
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding()
                    
                    // Brand info
                    VStack(spacing: 12) {
                        AsyncImage(url: URL(string: opportunity.campaign.brandLogoURL ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ZStack {
                                Color.gray.opacity(0.3)
                                Text(opportunity.campaign.category.icon)
                                    .font(.system(size: 40))
                            }
                        }
                        .frame(width: 80, height: 80)
                        .cornerRadius(20)
                        
                        Text(opportunity.campaign.brandName)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(opportunity.campaign.category.displayName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        // Match badge
                        Text("\(opportunity.matchScore)% match")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(opportunity.matchScore >= 80 ? .green : .yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                (opportunity.matchScore >= 80 ? Color.green : Color.yellow)
                                    .opacity(0.2)
                            )
                            .cornerRadius(20)
                    }
                    
                    // Details
                    VStack(spacing: 12) {
                        detailCard(title: "Campaign Budget", value: opportunity.campaign.budgetRange)
                        
                        detailCard(
                            title: "Your Revenue Share",
                            value: "\(Int(AdRevenueShare.creatorShare(for: userTier) * 100))%",
                            valueColor: .green
                        )
                        
                        // Placement preview
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ad Placement")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 8) {
                                placementBox(label: "YOU", color: .purple)
                                placementBox(label: "AD", color: .green)
                                placementBox(label: "2", color: .gray.opacity(0.5))
                                placementBox(label: "3", color: .gray.opacity(0.5))
                                
                                Text("→")
                                    .foregroundColor(.gray)
                            }
                            
                            Text("Position 2 in your threads")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                        
                        if let description = opportunity.campaign.description.nilIfEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 100)
                }
            }
            
            // Action buttons
            VStack {
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: onAccept) {
                        Text("Accept Partnership")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    
                    Button(action: onDecline) {
                        Text("Not Interested")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
    
    private func detailCard(title: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundColor(valueColor)
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
    
    private func placementBox(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 40, height: 60)
            .background(color)
            .cornerRadius(8)
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}