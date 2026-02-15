//
//  CommunityListView.swift
//  StitchSocial
//
//  Layer 8: Views - Community List (All Subscribed Communities)
//  Dependencies: CommunityService, CommunityTypes, GlobalXPService
//  Features: Community cards, live indicators, XP levels, unread counts, filter tabs
//

import SwiftUI

struct CommunityListView: View {
    
    // MARK: - Properties
    
    let userID: String
    
    @ObservedObject private var communityService = CommunityService.shared
    @ObservedObject private var globalXPService = GlobalXPService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedFilter: CommunityListFilter = .all
    @State private var selectedCommunity: CommunityListItem?
    @State private var showingJoinSheet = false
    @State private var joinCreatorID = ""
    @State private var isJoining = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                globalXPBar
                filterTabs
                
                if isLoading {
                    loadingView
                } else if filteredCommunities.isEmpty && communityService.allCommunities.isEmpty {
                    emptyState
                } else {
                    communityList
                }
            }
        }
        .task {
            await loadCommunities()
        }
        .sheet(item: $selectedCommunity) { community in
            CommunityDetailView(
                userID: userID,
                communityID: community.id,
                communityItem: community
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .alert("Join Community", isPresented: $showingJoinSheet) {
            TextField("Creator ID", text: $joinCreatorID)
            Button("Cancel", role: .cancel) { joinCreatorID = "" }
            Button("Join") {
                Task { await joinByCreatorID() }
            }
        } message: {
            Text("Enter the creator's user ID to join their community.")
        }
        .sheet(isPresented: $showingSubscribe) {
            SubscribeToJoinView(
                userID: userID,
                creatorID: subscribeCreatorID,
                onSubscribed: {
                    Task {
                        communityService.communityListCache = nil
                        await loadCommunities()
                    }
                }
            )
        }
        .sheet(isPresented: $showingBuyCoins) {
            WalletView(userID: userID, userTier: .rookie)
        }
    }
    
    // MARK: - Filtered Communities
    
    private var filteredCommunities: [CommunityListItem] {
        switch selectedFilter {
        case .all:
            return communityService.myCommunities
        case .liveNow:
            return communityService.myCommunities.filter { $0.isCreatorLive }
        case .discover:
            return []  // Discover section handled separately in communityList
        case .unread:
            return communityService.myCommunities.filter { $0.unreadCount > 0 }
        case .favorites:
            return communityService.myCommunities
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Communities")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("\(communityService.myCommunities.count) channels")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button {
                showingJoinSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
            }
            
            Button {
                Task { await loadCommunities() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // MARK: - Global XP Bar
    
    private var globalXPBar: some View {
        let summary = globalXPService.globalSummary()
        
        return HStack(spacing: 12) {
            // Level badge
            HStack(spacing: 4) {
                Text("⭐")
                    .font(.system(size: 14))
                Text("Global Lv \(summary.level)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
            }
            
            // XP bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * summary.progress)
                }
            }
            .frame(height: 6)
            
            // Tap multiplier
            if summary.tapMultiplier > 0 {
                HStack(spacing: 3) {
                    Text("⚡")
                        .font(.system(size: 11))
                    Text("+\(summary.tapMultiplier) taps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(CommunityListFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(filter.icon)
                                    .font(.subheadline)
                                
                                Text(filter.displayName)
                                    .font(.subheadline)
                                    .fontWeight(selectedFilter == filter ? .semibold : .medium)
                            }
                            .foregroundColor(selectedFilter == filter ? .cyan : .white.opacity(0.7))
                            
                            Rectangle()
                                .fill(selectedFilter == filter ? Color.cyan : Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Community List
    
    private var communityList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // Live section
                let liveItems = filteredCommunities.filter { $0.isCreatorLive }
                if !liveItems.isEmpty && selectedFilter == .all {
                    sectionHeader("🔴 Live Now")
                    ForEach(liveItems) { item in
                        CommunityCardView(item: item) {
                            selectedCommunity = item
                        }
                    }
                }
                
                // My communities
                let regularItems = selectedFilter == .all
                    ? filteredCommunities.filter { !$0.isCreatorLive }
                    : filteredCommunities
                
                if !regularItems.isEmpty {
                    if selectedFilter == .all && !liveItems.isEmpty {
                        sectionHeader("My Communities")
                    }
                    ForEach(regularItems) { item in
                        CommunityCardView(item: item) {
                            selectedCommunity = item
                        }
                    }
                }
                
                // Discover section — communities user hasn't joined
                if selectedFilter == .all || selectedFilter == .discover {
                    let myIDs = Set(communityService.myCommunities.map { $0.id })
                    let discoverItems = communityService.allCommunities.filter { !myIDs.contains($0.id) }
                    
                    if !discoverItems.isEmpty {
                        sectionHeader("🔍 Discover Communities")
                        
                        ForEach(discoverItems) { item in
                            DiscoverCommunityCard(item: item) {
                                Task { await joinCommunity(item) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text(selectedFilter == .all ? "No Communities" : "None Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(selectedFilter == .all
                 ? "Subscribe to creators to join their communities and earn XP."
                 : "No communities match this filter.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
            
            Text("Loading communities...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadCommunities() async {
        isLoading = true
        do {
            _ = try await communityService.fetchMyCommunities(userID: userID)
            _ = try await communityService.fetchAllCommunities()
            _ = try await globalXPService.loadGlobalXP(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isLoading = false
    }
    
    @State private var showingSubscribe = false
    @State private var showingBuyCoins = false
    @State private var subscribeCreatorID = ""
    
    private func joinByCreatorID() async {
        let creatorID = joinCreatorID.trimmingCharacters(in: .whitespaces)
        guard !creatorID.isEmpty else { return }
        
        do {
            _ = try await communityService.joinCommunity(
                userID: userID,
                username: "",
                displayName: "",
                creatorID: creatorID
            )
            joinCreatorID = ""
            communityService.communityListCache = nil
            await loadCommunities()
        } catch {
            await MainActor.run {
                joinCreatorID = ""
                handleJoinError(error, creatorID: creatorID)
            }
        }
    }
    
    private func joinCommunity(_ item: CommunityListItem) async {
        do {
            _ = try await communityService.joinCommunity(
                userID: userID,
                username: "",
                displayName: "",
                creatorID: item.id
            )
            communityService.communityListCache = nil
            await loadCommunities()
        } catch {
            await MainActor.run {
                handleJoinError(error, creatorID: item.id)
            }
        }
    }
    
    private func handleJoinError(_ error: Error, creatorID: String) {
        if let communityError = error as? CommunityError, communityError == .subscriptionRequired {
            subscribeCreatorID = creatorID
            showingSubscribe = true
        } else if error is CoinError {
            showingBuyCoins = true
        } else {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Discover Community Card

struct DiscoverCommunityCard: View {
    let item: CommunityListItem
    let onJoin: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            if let url = item.profileImageURL, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                defaultAvatar
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.creatorDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("@\(item.creatorUsername) · \(item.memberCount) members")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Subscribe / Join button
            Button(action: onJoin) {
                Text("Join")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.cyan)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var defaultAvatar: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(
                LinearGradient(
                    colors: [.cyan.opacity(0.4), .purple.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay(
                Text(String(item.creatorDisplayName.prefix(2)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Community List Filter

enum CommunityListFilter: String, CaseIterable {
    case all = "all"
    case liveNow = "live"
    case discover = "discover"
    case unread = "unread"
    case favorites = "favorites"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .liveNow: return "Live Now"
        case .discover: return "Discover"
        case .unread: return "Unread"
        case .favorites: return "Favorites"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "📌"
        case .liveNow: return "🔴"
        case .discover: return "🔍"
        case .unread: return "💬"
        case .favorites: return "⭐"
        }
    }
}

// MARK: - Community Card

struct CommunityCardView: View {
    let item: CommunityListItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                communityAvatar
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("@\(item.creatorUsername)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        if item.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(item.creatorTier.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.purple)
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.3))
                            .font(.system(size: 10))
                        
                        Text(formatMemberCount(item.memberCount))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    if !item.lastActivityPreview.isEmpty {
                        Text(item.lastActivityPreview)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                    
                    if item.isCreatorLive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Live Now")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                // Right side
                VStack(alignment: .trailing, spacing: 6) {
                    // Level badge
                    HStack(spacing: 3) {
                        Text("⭐")
                            .font(.system(size: 10))
                        Text("Lv \(item.userLevel)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Unread count
                    if item.unreadCount > 0 {
                        Text("\(item.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.pink)
                            .cornerRadius(10)
                    }
                    
                    // Time
                    Text(timeAgo(item.lastActivityAt))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                item.isCreatorLive
                                    ? Color.red.opacity(0.4)
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Avatar
    
    private var communityAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: avatarGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            if let url = item.profileImageURL {
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Text(initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text(initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Live badge
            if item.isCreatorLive {
                Text("LIVE")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
                    .offset(x: 0, y: 22)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var initials: String {
        let parts = item.creatorDisplayName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.count > 1 ? parts[1].prefix(1) : ""
        return "\(first)\(second)".uppercased()
    }
    
    private var avatarGradient: [Color] {
        let hash = abs(item.id.hashValue)
        let gradients: [[Color]] = [
            [.cyan, .purple],
            [.pink, .yellow],
            [.green, .cyan],
            [.purple, .pink],
            [.orange, .red],
            [.blue, .purple]
        ]
        return gradients[hash % gradients.count]
    }
    
    private func formatMemberCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(String(format: "%.1f", Double(count) / 1000))K members"
        }
        return "\(count) members"
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
