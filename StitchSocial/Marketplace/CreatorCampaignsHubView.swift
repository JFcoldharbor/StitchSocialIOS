//
//  CreatorCampaignsHubView.swift
//  StitchSocial
//
//  Single entry point for the Mode B marketplace. Role-aware:
//    - Brand accounts: see "My campaigns" + "+ New campaign" button
//    - Creator accounts: see "Browse" + "My applications" tabs +
//      "Payouts" gear linking to PayoutsSetupView
//
//  Detail navigation pushes to CreatorCampaignDetailView, which itself adapts
//  to viewer role (brand sees applicants/deliverables; creator sees apply
//  button or current application status).
//

import SwiftUI

struct CreatorCampaignsHubView: View {
    let currentUserID: String
    let isBrandAccount: Bool
    let brandName: String
    let brandLogoURL: String?

    @StateObject private var service = CreatorCampaignService.shared
    @State private var selectedTab = 0
    @State private var showingCreate = false
    @State private var navTarget: CreatorCampaign?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabBar
                    Divider().background(Color.white.opacity(0.1))
                    content
                }
            }
            .navigationTitle(isBrandAccount ? "Campaigns" : "Marketplace")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isBrandAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCreate = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PayoutsSetupView()
                        } label: {
                            Image(systemName: "creditcard.and.123")
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(item: $navTarget) { campaign in
                CreatorCampaignDetailView(
                    campaign: campaign,
                    currentUserID: currentUserID,
                    isBrandAccount: isBrandAccount,
                    onDismiss: { navTarget = nil }
                )
            }
            .sheet(isPresented: $showingCreate) {
                CreateCreatorCampaignView(
                    brandID: currentUserID,
                    brandName: brandName,
                    brandLogoURL: brandLogoURL,
                    onCreated: { _ in
                        showingCreate = false
                        Task { await loadActiveTab() }
                    },
                    onDismiss: { showingCreate = false }
                )
            }
        }
        .task { await loadActiveTab() }
        .onChange(of: selectedTab) { _, _ in
            Task { await loadActiveTab() }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button {
                    selectedTab = i
                } label: {
                    VStack(spacing: 6) {
                        Text(tabs[i])
                            .font(.system(size: 14, weight: selectedTab == i ? .bold : .medium))
                            .foregroundColor(selectedTab == i ? .white : .gray)
                        Rectangle()
                            .fill(selectedTab == i ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }

    private var tabs: [String] {
        isBrandAccount ? ["My Campaigns", "Drafts"] : ["Browse", "My Applications"]
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if service.isLoading && currentList.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
        } else if currentList.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(currentList) { campaign in
                        Button {
                            navTarget = campaign
                        } label: {
                            CampaignRowCard(campaign: campaign)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private var currentList: [CreatorCampaign] {
        if isBrandAccount {
            // Tab 0 = active, Tab 1 = drafts. We'll filter client-side.
            return service.brandCampaigns.filter {
                selectedTab == 0 ? $0.status != "draft" : $0.status == "draft"
            }
        } else {
            return selectedTab == 0 ? service.openCampaigns : service.myApplications
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: isBrandAccount ? "megaphone" : "magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(.gray.opacity(0.5))
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var emptyMessage: String {
        if isBrandAccount {
            return selectedTab == 0
                ? "No campaigns yet. Tap + to post your first creator brief."
                : "No drafts."
        } else {
            return selectedTab == 0
                ? "No open campaigns right now. Check back soon."
                : "You haven't applied to anything yet."
        }
    }

    // MARK: - Load

    @MainActor
    private func loadActiveTab() async {
        do {
            if isBrandAccount {
                try await service.fetchBrandCampaigns(brandID: currentUserID)
            } else {
                if selectedTab == 0 {
                    try await service.fetchOpenCampaigns()
                } else {
                    try await service.fetchMyApplicationCampaigns(creatorID: currentUserID)
                }
            }
        } catch {
            #if DEBUG
            print("CreatorCampaignsHubView load error: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Row card

private struct CampaignRowCard: View {
    let campaign: CreatorCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(campaign.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let brand = campaign.brandName {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Text("$\(Int(campaign.payoutDollars))")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.green)
            }

            Text(campaign.brief)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)

            HStack(spacing: 6) {
                pill(campaign.status.capitalized, color: statusColor)
                if let count = campaign.applicationsCount, count > 0 {
                    pill("\(count) applied", color: .cyan)
                }
                if let approved = campaign.approvedCount, approved > 0 {
                    pill("\(approved) approved", color: .green)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    private var statusColor: Color {
        switch campaign.status {
        case "open": return .green
        case "reviewing": return .orange
        case "in_progress": return .cyan
        case "completed": return .gray
        case "cancelled": return .red
        default: return .white
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
