//
//  BusinessAdDashboardView.swift
//  StitchSocial
//
//  Created by James Garmon on 3/10/26.
//


//
//  BusinessAdDashboardView.swift
//  StitchSocial
//
//  Business account ad management dashboard.
//  Dependencies: AdService, AdRevenueShare (models), UserTier
//
//  Features:
//  - Create new ad campaigns (upload video, set budget, CPM, duration, targeting)
//  - View active/paused/completed campaigns
//  - Analytics: impressions, spend, CPM, matched creators
//  - Ad guidelines and content policy
//
//  CACHING: All data fetched via AdService which has TTL-based caching.
//  Campaign list: 5min TTL. Stats: 10min TTL. No extra caching needed here.
//

import SwiftUI

struct BusinessAdDashboardView: View {
    
    // MARK: - Properties
    
    let user: BasicUserInfo
    @StateObject private var adService = AdService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var showingCreateCampaign = false
    @State private var showingGuidelines = false
    @State private var selectedCampaign: AdCampaign?
    
    private let tabs = ["Campaigns", "Analytics", "Create"]
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                tabBar
                tabContent
            }
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $showingCreateCampaign) {
            CreateCampaignView(user: user)
        }
        .sheet(isPresented: $showingGuidelines) {
            AdGuidelinesView()
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
                
                Text("Ad Manager")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingGuidelines = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
            
            // Quick stats banner
            if let stats = adService.businessStats {
                HStack(spacing: 20) {
                    quickStat(label: "Active", value: "\(stats.activeCampaigns)", color: .green)
                    quickStat(label: "Impressions", value: formatNumber(stats.totalImpressions), color: .cyan)
                    quickStat(label: "Spent", value: "$\(String(format: "%.0f", stats.totalSpend))", color: .yellow)
                }
            }
        }
        .padding()
        .background(Color.black)
    }
    
    private func quickStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    if index == 2 {
                        showingCreateCampaign = true
                    } else {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            if index == 2 {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                            Text(tabs[index])
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(index == 2 ? .green : (selectedTab == index ? .white : .gray))
                        }
                        
                        Rectangle()
                            .fill(selectedTab == index && index != 2 ? Color.green : Color.clear)
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
        case 0: campaignsTab
        case 1: analyticsTab
        default: EmptyView()
        }
    }
    
    // MARK: - Campaigns Tab
    
    private var campaignsTab: some View {
        ScrollView {
            if adService.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 50)
            } else if adService.businessCampaigns.isEmpty {
                emptyStateView(
                    icon: "megaphone",
                    title: "No Campaigns Yet",
                    message: "Create your first ad campaign to reach creators and their audiences."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(adService.businessCampaigns) { campaign in
                        BusinessCampaignCard(
                            campaign: campaign,
                            onPause: { pauseCampaign(campaign) },
                            onResume: { resumeCampaign(campaign) }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Analytics Tab
    
    private var analyticsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Overview Cards
                if let stats = adService.businessStats {
                    VStack(spacing: 12) {
                        analyticsHeader(title: "Overview")
                        
                        HStack(spacing: 12) {
                            analyticsCard(
                                title: "Total Campaigns",
                                value: "\(stats.totalCampaigns)",
                                icon: "megaphone.fill",
                                color: .green
                            )
                            analyticsCard(
                                title: "Active Now",
                                value: "\(stats.activeCampaigns)",
                                icon: "bolt.fill",
                                color: .yellow
                            )
                        }
                        
                        HStack(spacing: 12) {
                            analyticsCard(
                                title: "Total Impressions",
                                value: formatNumber(stats.totalImpressions),
                                icon: "eye.fill",
                                color: .cyan
                            )
                            analyticsCard(
                                title: "Total Spend",
                                value: "$\(String(format: "%.2f", stats.totalSpend))",
                                icon: "dollarsign.circle.fill",
                                color: .orange
                            )
                        }
                        
                        HStack(spacing: 12) {
                            analyticsCard(
                                title: "Avg CPM",
                                value: "$\(String(format: "%.2f", stats.averageCPM))",
                                icon: "chart.bar.fill",
                                color: .purple
                            )
                            analyticsCard(
                                title: "Total Clicks",
                                value: formatNumber(stats.totalClicks),
                                icon: "hand.tap.fill",
                                color: .pink
                            )
                        }
                    }
                } else {
                    emptyStateView(
                        icon: "chart.bar",
                        title: "No Data Yet",
                        message: "Analytics will appear once your first campaign starts running."
                    )
                }
                
                // Ad Guidelines Reminder
                Button(action: { showingGuidelines = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ad Guidelines")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Review content policies before creating campaigns")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Analytics Helpers
    
    private func analyticsHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
    }
    
    private func analyticsCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(14)
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showingCreateCampaign = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Campaign")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(12)
            }
        }
        .padding(.top, 60)
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        do {
            _ = try await adService.fetchBusinessCampaigns(businessID: user.id)
            _ = try await adService.fetchBusinessStats(businessID: user.id)
        } catch {
            print("❌ BUSINESS AD: Failed to load - \(error.localizedDescription)")
        }
    }
    
    private func pauseCampaign(_ campaign: AdCampaign) {
        Task {
            try? await adService.pauseCampaign(campaign.id)
            await loadData()
        }
    }
    
    private func resumeCampaign(_ campaign: AdCampaign) {
        Task {
            try? await adService.resumeCampaign(campaign.id)
            await loadData()
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 { return String(format: "%.1fM", Double(num) / 1_000_000) }
        if num >= 1_000 { return String(format: "%.1fK", Double(num) / 1_000) }
        return "\(num)"
    }
}

// MARK: - Business Campaign Card

struct BusinessCampaignCard: View {
    let campaign: AdCampaign
    let onPause: () -> Void
    let onResume: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(campaign.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 6) {
                        Text(campaign.category.icon)
                        Text(campaign.category.displayName)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Status badge
                statusBadge(campaign.status)
            }
            
            // Budget + CPM
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(campaign.budgetRange)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                if let cpm = campaign.cpmRate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPM Rate")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text("$\(String(format: "%.2f", cpm))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Started")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(campaign.startDate, style: .date)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Targeting summary
            HStack(spacing: 8) {
                targetingPill(label: "Min: \(campaign.requirements.minimumTier.displayName)")
                
                if let hashtags = campaign.requirements.requiredHashtags, !hashtags.isEmpty {
                    targetingPill(label: "#\(hashtags.first ?? "")")
                }
                
                if let cats = campaign.requirements.preferredCategories, !cats.isEmpty {
                    targetingPill(label: cats.first?.displayName ?? "")
                }
            }
            
            // Action buttons
            if campaign.status == .active {
                Button(action: onPause) {
                    HStack {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                        Text("Pause Campaign")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(8)
                }
            } else if campaign.status == .paused {
                Button(action: onResume) {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Resume Campaign")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(16)
    }
    
    private func statusBadge(_ status: AdCampaignStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .active: return ("Active", .green)
            case .paused: return ("Paused", .yellow)
            case .completed: return ("Completed", .gray)
            case .cancelled: return ("Cancelled", .red)
            case .draft: return ("Draft", .blue)
            }
        }()
        
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }
    
    private func targetingPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
    }
}

// MARK: - Create Campaign View

struct CreateCampaignView: View {
    
    let user: BasicUserInfo
    @StateObject private var adService = AdService.shared
    @Environment(\.dismiss) private var dismiss
    
    // Campaign fields
    @State private var campaignTitle = ""
    @State private var campaignDescription = ""
    @State private var selectedCategory: AdCategory = .other
    @State private var adVideoURL = ""
    @State private var adThumbnailURL = ""
    
    // Budget
    @State private var budgetMin: Double = 50
    @State private var budgetMax: Double = 500
    @State private var cpmRate: Double = 5.0
    
    // Duration
    @State private var campaignDuration: CampaignDuration = .twoWeeks
    
    // Targeting
    @State private var minimumTier: UserTier = .influencer
    @State private var selectedTargetCategories: Set<AdCategory> = []
    @State private var hashtagsText = ""
    @State private var minFollowers: String = ""
    @State private var minEngagement: String = ""
    
    // UI State
    @State private var currentStep = 0
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingGuidelinesAccept = false
    @State private var acceptedGuidelines = false
    
    private let steps = ["Content", "Budget", "Targeting", "Review"]
    
    enum CampaignDuration: String, CaseIterable {
        case oneWeek = "1 Week"
        case twoWeeks = "2 Weeks"
        case oneMonth = "1 Month"
        case threeMonths = "3 Months"
        case ongoing = "Ongoing"
        
        var days: Int? {
            switch self {
            case .oneWeek: return 7
            case .twoWeeks: return 14
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .ongoing: return nil
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Step indicator
                    stepIndicator
                    
                    // Step content
                    TabView(selection: $currentStep) {
                        contentStep.tag(0)
                        budgetStep.tag(1)
                        targetingStep.tag(2)
                        reviewStep.tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    
                    // Navigation buttons
                    navigationButtons
                }
            }
            .navigationTitle("Create Campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 3)
                    
                    Text(steps[index])
                        .font(.system(size: 10, weight: index == currentStep ? .bold : .regular))
                        .foregroundColor(index <= currentStep ? .white : .gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    // MARK: - Step 1: Content
    
    private var contentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Campaign Details")
                
                formField(title: "Campaign Title", placeholder: "e.g. Summer Fitness Challenge", text: $campaignTitle)
                
                formField(title: "Description", placeholder: "Describe what you're promoting...", text: $campaignDescription, isMultiline: true)
                
                // Category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AdCategory.allCases, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    Text("\(cat.icon) \(cat.displayName)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selectedCategory == cat ? .black : .white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedCategory == cat ? Color.green : Color.white.opacity(0.08))
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                }
                
                sectionHeader("Ad Creative")
                
                formField(title: "Video URL", placeholder: "Link to your ad video", text: $adVideoURL)
                
                formField(title: "Thumbnail URL (optional)", placeholder: "Link to thumbnail image", text: $adThumbnailURL)
                
                // Guidelines reminder
                guidelinesReminder
            }
            .padding()
        }
    }
    
    // MARK: - Step 2: Budget
    
    private var budgetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Budget Range")
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minimum")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("$\(Int(budgetMin))")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Maximum")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("$\(Int(budgetMax))")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    
                    Slider(value: $budgetMin, in: 10...budgetMax, step: 10)
                        .tint(.green)
                    
                    Slider(value: $budgetMax, in: budgetMin...5000, step: 50)
                        .tint(.green)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(14)
                
                sectionHeader("CPM Rate")
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cost per 1,000 impressions")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$\(String(format: "%.2f", cpmRate))")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.cyan)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Est. impressions")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            Text("\(estimatedImpressions)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Slider(value: $cpmRate, in: 1.0...50.0, step: 0.50)
                        .tint(.cyan)
                    
                    HStack {
                        Text("$1.00")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("$50.00")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(14)
                
                sectionHeader("Duration")
                
                VStack(spacing: 8) {
                    ForEach(CampaignDuration.allCases, id: \.self) { duration in
                        Button(action: { campaignDuration = duration }) {
                            HStack {
                                Text(duration.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(campaignDuration == duration ? .white : .gray)
                                
                                Spacer()
                                
                                if campaignDuration == duration {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(campaignDuration == duration ? Color.green.opacity(0.12) : Color.gray.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Step 3: Targeting
    
    private var targetingStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Creator Requirements")
                
                // Minimum tier
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minimum Creator Tier")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([UserTier.veteran, .influencer, .ambassador, .elite, .partner], id: \.self) { tier in
                                Button(action: { minimumTier = tier }) {
                                    Text(tier.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(minimumTier == tier ? .black : .white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(minimumTier == tier ? Color.green : Color.white.opacity(0.08))
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                    
                    Text("Creators below this tier won't be matched")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                // Target categories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred Content Categories")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(AdCategory.allCases, id: \.self) { cat in
                            Button(action: {
                                if selectedTargetCategories.contains(cat) {
                                    selectedTargetCategories.remove(cat)
                                } else {
                                    selectedTargetCategories.insert(cat)
                                }
                            }) {
                                Text("\(cat.icon) \(cat.displayName)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedTargetCategories.contains(cat) ? .black : .white.opacity(0.6))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selectedTargetCategories.contains(cat) ? Color.green : Color.white.opacity(0.06))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
                
                // Hashtags
                formField(title: "Required Hashtags (comma separated)", placeholder: "fitness, workout, gym", text: $hashtagsText)
                
                // Min followers
                formField(title: "Min Followers (optional)", placeholder: "e.g. 5000", text: $minFollowers)
                
                // Min engagement rate
                formField(title: "Min Engagement Rate % (optional)", placeholder: "e.g. 3.5", text: $minEngagement)
            }
            .padding()
        }
    }
    
    // MARK: - Step 4: Review
    
    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Campaign Summary")
                
                reviewRow(label: "Title", value: campaignTitle.isEmpty ? "—" : campaignTitle)
                reviewRow(label: "Category", value: "\(selectedCategory.icon) \(selectedCategory.displayName)")
                reviewRow(label: "Budget", value: "$\(Int(budgetMin)) – $\(Int(budgetMax))")
                reviewRow(label: "CPM Rate", value: "$\(String(format: "%.2f", cpmRate))")
                reviewRow(label: "Est. Impressions", value: estimatedImpressions)
                reviewRow(label: "Duration", value: campaignDuration.rawValue)
                reviewRow(label: "Min Tier", value: minimumTier.displayName)
                
                if !selectedTargetCategories.isEmpty {
                    reviewRow(label: "Target Categories", value: selectedTargetCategories.map { $0.displayName }.joined(separator: ", "))
                }
                
                if !hashtagsText.isEmpty {
                    reviewRow(label: "Hashtags", value: hashtagsText)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Guidelines acceptance
                Button(action: { acceptedGuidelines.toggle() }) {
                    HStack(spacing: 10) {
                        Image(systemName: acceptedGuidelines ? "checkmark.square.fill" : "square")
                            .foregroundColor(acceptedGuidelines ? .green : .gray)
                        
                        Text("I confirm this ad complies with StitchSocial Ad Guidelines")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.top, 8)
                
                Button(action: { showingGuidelinesAccept = true }) {
                    Text("View Ad Guidelines")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button(action: { withAnimation { currentStep -= 1 } }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                }
            }
            
            if currentStep < steps.count - 1 {
                Button(action: { withAnimation { currentStep += 1 } }) {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.green)
                        .cornerRadius(12)
                }
            } else {
                Button(action: { submitCampaign() }) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "megaphone.fill")
                            Text("Launch Campaign")
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canSubmit ? Color.green : Color.green.opacity(0.3))
                    .cornerRadius(12)
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .padding()
        .background(Color.black)
    }
    
    // MARK: - Helpers
    
    private var canSubmit: Bool {
        !campaignTitle.isEmpty && !adVideoURL.isEmpty && acceptedGuidelines
    }
    
    private var estimatedImpressions: String {
        guard cpmRate > 0 else { return "0" }
        let avgBudget = (budgetMin + budgetMax) / 2
        let impressions = Int((avgBudget / cpmRate) * 1000)
        if impressions >= 1_000_000 { return String(format: "%.1fM", Double(impressions) / 1_000_000) }
        if impressions >= 1_000 { return String(format: "%.0fK", Double(impressions) / 1_000) }
        return "\(impressions)"
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.top, 4)
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>, isMultiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            if isMultiline {
                TextEditor(text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
                    .scrollContentBackground(.hidden)
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
            }
        }
    }
    
    private func reviewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
    
    private var guidelinesReminder: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Ad Content Policy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("All ads must comply with our community guidelines. No misleading claims, explicit content, or prohibited products.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(12)
    }
    
    private func submitCampaign() {
        guard canSubmit else { return }
        isSubmitting = true
        
        let hashtags = hashtagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let endDate: Date? = campaignDuration.days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())! }
        
        let requirements = CreatorRequirements(
            minimumTier: minimumTier,
            minimumStitchers: Int(minFollowers),
            minimumHypeScore: nil,
            minimumHypeRating: nil,
            minimumEngagementRate: Double(minEngagement),
            minimumViewCount: nil,
            minimumCommunityScore: nil,
            requiredHashtags: hashtags.isEmpty ? nil : hashtags,
            preferredCategories: selectedTargetCategories.isEmpty ? nil : Array(selectedTargetCategories)
        )
        
        Task {
            do {
                _ = try await adService.createCampaign(
                    businessID: user.id,
                    businessName: user.displayName,
                    title: campaignTitle,
                    description: campaignDescription,
                    category: selectedCategory,
                    adVideoURL: adVideoURL,
                    adThumbnailURL: adThumbnailURL.isEmpty ? adVideoURL : adThumbnailURL,
                    budgetMin: budgetMin,
                    budgetMax: budgetMax,
                    cpmRate: cpmRate,
                    requirements: requirements
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSubmitting = false
        }
    }
}

// MARK: - Ad Guidelines View

struct AdGuidelinesView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guidelineSection(
                        icon: "checkmark.shield.fill",
                        title: "Allowed Content",
                        color: .green,
                        items: [
                            "Product demonstrations and reviews",
                            "Brand storytelling and awareness campaigns",
                            "Promotional offers and discounts",
                            "Educational content related to your product",
                            "Lifestyle content featuring your brand",
                            "Event promotions and announcements",
                            "App and service promotions"
                        ]
                    )
                    
                    guidelineSection(
                        icon: "xmark.shield.fill",
                        title: "Prohibited Content",
                        color: .red,
                        items: [
                            "Misleading or deceptive claims",
                            "Explicit, sexual, or violent content",
                            "Illegal products or services",
                            "Tobacco, vaping, and recreational drugs",
                            "Weapons and ammunition",
                            "Hate speech or discriminatory content",
                            "Political campaign ads",
                            "Cryptocurrency or unregistered securities",
                            "Fake testimonials or fabricated reviews",
                            "Malware, phishing, or scam content"
                        ]
                    )
                    
                    guidelineSection(
                        icon: "exclamationmark.triangle.fill",
                        title: "Restricted Content (Requires Review)",
                        color: .yellow,
                        items: [
                            "Alcohol brands (age-gated targeting required)",
                            "Gambling and betting services",
                            "Health supplements and wellness claims",
                            "Financial services and investments",
                            "Dating and social apps",
                            "Weight loss products"
                        ]
                    )
                    
                    guidelineSection(
                        icon: "doc.text.fill",
                        title: "Ad Requirements",
                        color: .cyan,
                        items: [
                            "All ads must be clearly identifiable as sponsored content",
                            "Video must be original or properly licensed",
                            "Landing pages must match ad claims",
                            "Prices shown must be accurate and current",
                            "Disclosures required for affiliate content",
                            "Must comply with FTC endorsement guidelines",
                            "Ad creative must match selected category"
                        ]
                    )
                    
                    guidelineSection(
                        icon: "person.2.fill",
                        title: "Creator Auto-Matching",
                        color: .purple,
                        items: [
                            "Platform auto-matches based on your targeting criteria",
                            "You do not select or contact creators directly",
                            "Matched creators can accept or decline your campaign",
                            "Creator content style must align with your category",
                            "Revenue split follows the creator's tier-based rate",
                            "CPM is charged per 1,000 verified impressions"
                        ]
                    )
                    
                    // Policy note
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Policy Enforcement")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Ads that violate these guidelines will be paused or removed without refund. Repeated violations may result in account suspension. StitchSocial reserves the right to reject any ad campaign at its discretion.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(12)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Ad Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private func guidelineSection(icon: String, title: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding()
        .background(color.opacity(0.06))
        .cornerRadius(14)
    }
}