//
//  CommunityDetailView.swift
//  StitchSocial
//
//  Layer 8: Views - Modular Card-Based Community Screen
//  REPLACES old tab-based layout with scrollable card grid matching mockup.
//
//  Cards:
//   1. Creator Header (avatar, verified, badges, stats: Members/Live Now/Trending)
//   2. XP Progress Bar
//   3. Discussion Card (left) + Upper Flow Leaderboard (right)
//   4. Highlight Reel (left) + Top Supporters (right)
//   5. Live Now Banner (full width)
//   6. Super Hype Stats (left) + Badge Holders (right)
//   7. Recent Posts feed
//
//  CACHING: All data from cached services. Cards don't trigger extra Firestore reads.
//  Only addition: fetchMembers(limit: 10) — one query powers leaderboard + supporters + badges.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Colors (Mockup Dark Theme)

private let darkBg = Color(hex: "0D0F1A")
private let cardBg = Color(hex: "161929")
private let cardBorder = Color(hex: "2A2F4A")
private let accentCyan = Color(hex: "00D4FF")
private let accentOrange = Color(hex: "FF8C42")
private let accentPurple = Color(hex: "9C5FFF")
private let accentGold = Color(hex: "FFD700")
private let accentPink = Color(hex: "FF4F9A")
private let textPrimary = Color.white
private let textSecondary = Color(hex: "8B8FA3")
private let textMuted = Color(hex: "5A5E72")

// MARK: - Main Screen

struct CommunityDetailView: View {
    
    let userID: String
    let communityID: String
    let communityItem: CommunityListItem
    
    @ObservedObject private var communityService = CommunityService.shared
    @ObservedObject private var feedService = CommunityFeedService.shared
    @ObservedObject private var xpService = CommunityXPService.shared
    @ObservedObject private var streamService = LiveStreamService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var membership: CommunityMembership?
    @State private var topMembers: [CommunityMembership] = []
    @State private var isLoading = true
    @State private var isCreatorLive = false
    @State private var liveStreamID: String?
    @State private var liveListener: ListenerRegistration?
    @State private var showingComposer = false
    @State private var showingGoLive = false
    @State private var showingViewerStream = false
    @State private var showingLeaderboard = false
    @State private var showingSupporters = false
    @State private var showingBadges = false
    @State private var showingHighlight = false
    @State private var selectedPost: CommunityPost?
    @State private var leaderboardSort: LeaderboardSort = .level
    
    private var isCreator: Bool {
        userID == communityID || SubscriptionService.shared.isDeveloper
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            darkBg.ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.3)
                    .progressViewStyle(CircularProgressViewStyle(tint: accentCyan))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        creatorHeader
                        xpProgressCard
                        
                        // 3. Discussion + Upper Flow
                        HStack(alignment: .top, spacing: 10) {
                            discussionCard
                            upperFlowCard
                                .onTapGesture { leaderboardSort = .level; showingLeaderboard = true }
                        }
                        .padding(.horizontal, 16)
                        
                        // 4. Highlight Reel + Top Supporters
                        HStack(alignment: .top, spacing: 10) {
                            highlightReelCard
                                .onTapGesture { showingHighlight = true }
                            topSupportersCard
                                .onTapGesture { showingSupporters = true }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        
                        // 5. Stream Hub (always visible)
                        liveNowCard
                        
                        // 6. Super Hype + Badge Holders
                        HStack(alignment: .top, spacing: 10) {
                            superHypeStatsCard
                            badgeHoldersCard
                                .onTapGesture { showingBadges = true }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        
                        // 7. Recent Posts
                        sectionLabel("Recent Posts")
                        
                        ForEach(feedService.currentFeed.prefix(5)) { post in
                            postCard(post)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .onTapGesture { selectedPost = post }
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            
            // Compose FAB
            Button { showingComposer = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 56, height: 56)
                    .background(accentCyan)
                    .clipShape(Circle())
                    .shadow(color: accentCyan.opacity(0.4), radius: 12, y: 4)
            }
            .padding(20)
        }
        .navigationBarHidden(true)
        .task { await loadData() }
        .onDisappear { liveListener?.remove() }
        .fullScreenCover(isPresented: $showingComposer) {
            CommunityComposeSheet(
                userID: userID,
                communityID: communityID,
                membership: membership,
                feedService: feedService
            )
        }
        .fullScreenCover(isPresented: $showingGoLive) {
            LiveStreamCreatorView(
                creatorID: communityID,
                tier: .spark
            )
        }
        .fullScreenCover(isPresented: $showingViewerStream) {
            LiveStreamViewerView(
                userID: userID,
                communityID: communityID,
                streamID: liveStreamID ?? streamService.activeStream?.id ?? "",
                userLevel: membership?.level ?? 1
            )
        }
        .fullScreenCover(isPresented: $showingLeaderboard) {
            MemberLeaderboardView(communityID: communityID, initialSort: leaderboardSort)
        }
        .fullScreenCover(isPresented: $showingSupporters) {
            MemberLeaderboardView(communityID: communityID, initialSort: .hypesGiven)
        }
        .fullScreenCover(isPresented: $showingBadges) {
            BadgeGalleryView(currentLevel: membership?.level ?? communityItem.userLevel, earnedBadgeIDs: membership?.earnedBadgeIDs ?? [])
        }
        .fullScreenCover(isPresented: $showingHighlight) {
            HighlightPlayerView(communityID: communityID, communityName: communityItem.creatorDisplayName)
        }
        .fullScreenCover(item: $selectedPost) { post in
            PostDetailView(post: post, communityID: communityID, userID: userID, membership: membership)
        }
    }
    
    private func loadData() async {
        membership = try? await communityService.fetchMembership(userID: userID, creatorID: communityID)
        _ = try? await feedService.fetchFeed(communityID: communityID)
        let result = try? await communityService.fetchMembers(creatorID: communityID, limit: 10)
        topMembers = result?.members ?? []
        _ = try? await xpService.claimDailyLogin(userID: userID, communityID: communityID)
        
        // Recover active stream if creator relaunched app
        if isCreator {
            await streamService.recoverActiveStream(creatorID: communityID)
        }
        
        // Set initial live state from snapshot
        isCreatorLive = communityItem.isCreatorLive
        
        // Real-time listener on community doc for isCreatorLive changes
        // CACHING: Single listener per detail view, removed on disappear. No polling.
        liveListener = FirebaseConfig.firestore
            .collection("communities")
            .document(communityID)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data() else { return }
                let live = data["isCreatorLive"] as? Bool ?? false
                let streamID = data["activeStreamID"] as? String
                
                DispatchQueue.main.async {
                    self.isCreatorLive = live
                    self.liveStreamID = streamID
                }
            }
        
        isLoading = false
    }
    
    // ============================================================
    // 1. CREATOR HEADER
    // ============================================================
    
    private var creatorHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textSecondary)
            }
            .padding(.bottom, 4)
            
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(LinearGradient(colors: [accentPurple, accentPink, accentOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .overlay(Text(initials).font(.system(size: 22, weight: .bold)).foregroundColor(textPrimary))
                    
                    if communityItem.isVerified {
                        Circle().fill(accentCyan).frame(width: 20, height: 20)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("👑").font(.system(size: 14))
                        Text(communityItem.creatorDisplayName).font(.system(size: 18, weight: .bold)).foregroundColor(textPrimary)
                    }
                    HStack(spacing: 8) {
                        badgePill("✅ Community", accentCyan)
                        badgePill("🏆 \(communityItem.creatorTier.displayName)", accentGold)
                    }
                }
                Spacer()
            }
            
            HStack {
                statItem(label: "MEMBERS:", value: formatCount(communityItem.memberCount), color: accentCyan)
                Spacer()
                statItem(label: "LIVE NOW:", value: isCreatorLive ? "🔴" : "—", color: accentOrange)
                Spacer()
                statItem(label: "TRENDING:", value: isCreatorLive ? "🔴 Live" : "—", color: accentPurple)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .background(LinearGradient(colors: [accentPurple.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
    }
    
    // ============================================================
    // 2. XP PROGRESS
    // ============================================================
    
    private var xpProgressCard: some View {
        let level = membership?.level ?? communityItem.userLevel
        let currentXP = membership?.localXP ?? communityItem.userXP
        let progress = xpService.progressToNext(currentXP: currentXP)
        let xpNeeded = xpService.xpToNextLevel(currentXP: currentXP)
        
        return moduleCard {
            HStack(spacing: 10) {
                Text("⭐").font(.system(size: 16))
                Text("Lv \(level)").font(.system(size: 14, weight: .bold)).foregroundColor(accentGold)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(cardBorder)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [accentGold, accentOrange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.5), value: progress)
                    }
                }
                .frame(height: 8)
                Text("\(formatXP(currentXP)) / \(formatXP(currentXP + xpNeeded))").font(.system(size: 10)).foregroundColor(textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    // ============================================================
    // 3. DISCUSSION
    // ============================================================
    
    private var discussionCard: some View {
        let pinnedPost = feedService.currentFeed.first(where: { $0.isCreatorPost })
        
        return moduleCard {
            Text("Discussion").font(.system(size: 14, weight: .bold)).foregroundColor(textPrimary)
            Spacer().frame(height: 10)
            
            if let post = pinnedPost {
                Text("@\(post.authorUsername)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentOrange)
                
                Text(post.body)
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .lineLimit(4)
                
                Spacer().frame(height: 8)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("🔥").font(.system(size: 12))
                        Text("\(post.hypeCount)").font(.system(size: 11)).foregroundColor(textMuted)
                    }
                    HStack(spacing: 4) {
                        Text("💬").font(.system(size: 12))
                        Text("\(post.replyCount)").font(.system(size: 11)).foregroundColor(textMuted)
                    }
                    Spacer()
                }
            } else {
                Text("No active discussions").font(.system(size: 12)).foregroundColor(textMuted)
                Spacer().frame(height: 8)
                smallButton("Start One", color: accentCyan) { showingComposer = true }
            }
        }
    }
    
    // ============================================================
    // 3b. UPPER FLOW
    // ============================================================
    
    private var upperFlowCard: some View {
        moduleCard {
            HStack {
                Text("Upper Flow").font(.system(size: 14, weight: .bold)).foregroundColor(textPrimary)
                Spacer()
                hCoinBadge(size: 24)
            }
            Text("Community Level Leaders").font(.system(size: 10)).foregroundColor(textMuted)
            Spacer().frame(height: 10)
            
            ForEach(topMembers.prefix(3)) { member in
                HStack(spacing: 8) {
                    memberAvatar(name: member.displayName, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.username.isEmpty ? member.displayName : member.username)
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(textPrimary).lineLimit(1)
                        Text("\(member.localXP) Hype").font(.system(size: 9)).foregroundColor(accentOrange)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // ============================================================
    // 4. HIGHLIGHT REEL
    // ============================================================
    
    private var highlightReelCard: some View {
        moduleCard(bgGradient: [cardBg, accentPurple.opacity(0.15)]) {
            Text("Highlight Reel")
                .font(.system(size: 13, weight: .bold)).foregroundColor(textPrimary)
            Text("\(communityItem.creatorDisplayName)'s Streams")
                .font(.system(size: 10)).foregroundColor(textSecondary)
            Spacer().frame(height: 10)
            
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [accentPurple.opacity(0.3), accentCyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 100)
                Circle().fill(accentCyan.opacity(0.3)).frame(width: 44, height: 44)
                    .overlay(Circle().stroke(accentCyan, lineWidth: 2))
                    .overlay(Image(systemName: "play.fill").font(.system(size: 18)).foregroundColor(textPrimary))
            }
            
            Spacer().frame(height: 8)
            Text("Watch the best moments from recent streams.")
                .font(.system(size: 10)).foregroundColor(textSecondary).lineLimit(2)
        }
    }
    
    // ============================================================
    // 4b. TOP SUPPORTERS
    // ============================================================
    
    private var topSupportersCard: some View {
        let sorted = topMembers.sorted { $0.totalHypesGiven > $1.totalHypesGiven }
        
        return moduleCard {
            HStack {
                Text("Top Supporters").font(.system(size: 14, weight: .bold)).foregroundColor(textPrimary)
                Spacer()
                Circle().fill(accentOrange).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundColor(.white))
            }
            Rectangle().fill(cardBorder).frame(height: 1).padding(.vertical, 4)
            
            ForEach(sorted.prefix(6)) { member in
                HStack(spacing: 8) {
                    memberAvatar(name: member.displayName, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.username.isEmpty ? member.displayName : member.username)
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(textPrimary).lineLimit(1)
                        Text("\(member.totalHypesGiven) Hype").font(.system(size: 9)).foregroundColor(accentOrange)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", Double(member.totalHypesGiven) / Double(member.totalHypesGiven + 100) * 100))
                        .font(.system(size: 10)).foregroundColor(textMuted)
                }
                .padding(.vertical, 3)
            }
        }
    }
    
    // ============================================================
    // 5. LIVE NOW BANNER
    // ============================================================
    
    private var liveNowCard: some View {
        let isLive = isCreatorLive
        
        let bgColors: [Color] = isLive
            ? [accentPurple.opacity(0.6), accentCyan.opacity(0.4), accentPurple.opacity(0.5)]
            : [cardBg, accentPurple.opacity(0.08)]
        
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: bgColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(isLive ? accentCyan.opacity(0.3) : cardBorder, lineWidth: 1))
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isLive ? Color.red : textMuted)
                            .frame(width: 8, height: 8)
                        Text(isLive ? "LIVE NOW" : "STREAMS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isLive ? Color.red : textMuted)
                    }
                    
                    if isLive && !isCreator {
                        Text("\(communityItem.creatorDisplayName)\nLIVE!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(textPrimary)
                            .lineSpacing(2)
                    } else if isLive && isCreator {
                        Text("You're LIVE!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(textPrimary)
                        Text("Streaming to your community now")
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary)
                    } else if isCreator {
                        Text("Go Live")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(textPrimary)
                        Text("Start streaming to your community")
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary)
                    } else {
                        Text("\(communityItem.creatorDisplayName)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(textPrimary)
                        Text("Not streaming right now")
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary)
                    }
                }
                Spacer()
                
                if isLive {
                    hCoinBadge(size: 40)
                } else {
                    Image(systemName: isCreator ? "video.fill" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundColor(textMuted)
                }
            }
            .padding(20)
            
            // CTA button
            if isLive && !isCreator {
                // Viewer sees Join Live
                Button { showingViewerStream = true } label: {
                    Text("Join Live")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(16)
            } else if !isLive && isCreator {
                // Creator sees Go Live
                Button { showingGoLive = true } label: {
                    Text("Go Live")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(accentOrange)
                        .cornerRadius(12)
                }
                .padding(16)
            }
            // Creator who is already live — show re-enter
            // Viewer when offline — no button
            if isLive && isCreator {
                Button { showingGoLive = true } label: {
                    Text("Re-enter Stream")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(16)
            }
        }
        .frame(height: isLive ? 140 : 110)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // ============================================================
    // 6. SUPER HYPE STATS
    // ============================================================
    
    private var superHypeStatsCard: some View {
        let totalHype = topMembers.reduce(0) { $0 + $1.totalHypesGiven }
        let totalPosts = topMembers.reduce(0) { $0 + $1.totalPosts }
        let totalStreams = topMembers.reduce(0) { $0 + $1.streamsAttended }
        let maxStat = max(totalHype, max(totalPosts, max(totalStreams, 1)))
        
        return moduleCard {
            Text("Community Stats")
                .font(.system(size: 13, weight: .bold)).foregroundColor(textPrimary)
            Text("\(topMembers.count) active members")
                .font(.system(size: 10)).foregroundColor(textSecondary)
            Spacer().frame(height: 12)
            hypeStatRow(emoji: "🔥", label: "Total Hype", sub: "", value: formatCount(totalHype))
            Spacer().frame(height: 6)
            hypeStatRow(emoji: "📝", label: "Total Posts", sub: "", value: formatCount(totalPosts))
            Spacer().frame(height: 6)
            hypeStatRow(emoji: "📡", label: "Streams Attended", sub: "", value: formatCount(totalStreams))
            Spacer().frame(height: 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(cardBorder)
                    RoundedRectangle(cornerRadius: 2).fill(accentCyan)
                        .frame(width: geo.size.width * CGFloat(totalHype) / CGFloat(maxStat))
                }
            }
            .frame(height: 4)
        }
    }
    
    // ============================================================
    // 6b. BADGE HOLDERS
    // ============================================================
    
    private var badgeHoldersCard: some View {
        let holders = topMembers.filter { !$0.earnedBadgeIDs.isEmpty }
        
        return moduleCard {
            Text("Badge Holders").font(.system(size: 14, weight: .bold)).foregroundColor(textPrimary)
            Spacer().frame(height: 10)
            
            if holders.isEmpty {
                Text("No badge holders yet").font(.system(size: 11)).foregroundColor(textMuted)
            } else {
                ForEach(holders.prefix(4)) { member in
                    let badge = CommunityBadgeDefinition.allBadges.last(where: { member.earnedBadgeIDs.contains($0.id) })
                    HStack(spacing: 10) {
                        Circle().fill(accentPurple.opacity(0.2)).frame(width: 32, height: 32)
                            .overlay(Text(badge?.emoji ?? "🏅").font(.system(size: 16)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(badge?.name ?? "Member").font(.system(size: 12, weight: .semibold)).foregroundColor(textPrimary)
                            Text("\(member.localXP) Hype").font(.system(size: 9)).foregroundColor(accentOrange)
                        }
                        Spacer()
                        Circle().fill(accentGold.opacity(0.15)).frame(width: 24, height: 24)
                            .overlay(Text(badge?.emoji ?? "⭐").font(.system(size: 12)))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // ============================================================
    // 7. POST CARD
    // ============================================================
    
    private func postCard(_ post: CommunityPost) -> some View {
        moduleCard {
            HStack {
                memberAvatar(name: post.authorDisplayName, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("@\(post.authorUsername)").font(.system(size: 13, weight: .bold)).foregroundColor(textPrimary)
                        if post.isCreatorPost {
                            Text("CREATOR").font(.system(size: 8, weight: .bold)).foregroundColor(accentCyan)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(accentCyan.opacity(0.12)).cornerRadius(4)
                        }
                    }
                    Text("Lv \(post.authorLevel) • \(timeAgo(post.createdAt))").font(.system(size: 10)).foregroundColor(textMuted)
                }
                Spacer()
                if post.isPinned { Text("📌").font(.system(size: 14)) }
            }
            Spacer().frame(height: 8)
            Text(post.body).font(.system(size: 13)).foregroundColor(textSecondary).lineSpacing(4)
            Spacer().frame(height: 8)
            HStack(spacing: 16) {
                Button {
                    Task { _ = try? await feedService.hypePost(postID: post.id, communityID: communityID, userID: userID) }
                } label: {
                    HStack(spacing: 4) { Text("🔥").font(.system(size: 14)); Text("\(post.hypeCount)").font(.system(size: 12)).foregroundColor(textMuted) }
                }
                HStack(spacing: 4) { Text("💬").font(.system(size: 14)); Text("\(post.replyCount)").font(.system(size: 12)).foregroundColor(textMuted) }
            }
        }
    }
    
    // ============================================================
    // SHARED COMPONENTS
    // ============================================================
    
    private func moduleCard<Content: View>(bgGradient: [Color]? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: bgGradient ?? [cardBg, cardBg], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(cardBorder, lineWidth: 1))
    }
    
    private func memberAvatar(name: String, size: CGFloat) -> some View {
        let g: [[Color]] = [[accentCyan, accentPurple], [accentPink, accentOrange], [accentPurple, accentPink], [accentOrange, accentGold]]
        let parts = name.split(separator: " ")
        let ini = String((parts.first?.prefix(1) ?? "") + (parts.count > 1 ? parts[1].prefix(1) : "")).uppercased()
        return Circle().fill(LinearGradient(colors: g[abs(name.hashValue) % g.count], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size).overlay(Text(ini).font(.system(size: size * 0.38, weight: .bold)).foregroundColor(textPrimary))
    }
    
    private func hCoinBadge(size: CGFloat) -> some View {
        Circle().fill(accentOrange).frame(width: size, height: size)
            .overlay(Text("H").font(.system(size: size * 0.45, weight: .bold)).foregroundColor(.white))
    }
    
    private func badgePill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.12)).cornerRadius(6)
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(textMuted)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(color)
        }
    }
    
    private func hypeStatRow(emoji: String, label: String, sub: String, value: String) -> some View {
        HStack {
            Text(emoji).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(textPrimary)
                if !sub.isEmpty { Text(sub).font(.system(size: 8)).foregroundColor(accentOrange) }
            }
            Spacer()
            Text(value).font(.system(size: 11)).foregroundColor(textSecondary)
        }
    }
    
    private func smallButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 6).background(color).cornerRadius(10)
        }
    }
    
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.5)
            .foregroundColor(textMuted).padding(.horizontal, 16).padding(.vertical, 10)
    }
    
    // ============================================================
    // HELPERS
    // ============================================================
    
    private var initials: String {
        let parts = communityItem.creatorDisplayName.split(separator: " ")
        return String((parts.first?.prefix(1) ?? "") + (parts.count > 1 ? parts[1].prefix(1) : "")).uppercased()
    }
    
    private func formatXP(_ xp: Int) -> String {
        if xp >= 1_000_000 { return String(format: "%.1fM", Double(xp) / 1_000_000) }
        if xp >= 1000 { return String(format: "%.1fK", Double(xp) / 1000) }
        return "\(xp)"
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return "\(count)"
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Compose Sheet (inline — CommunityComposeView doesn't exist yet)

struct CommunityComposeSheet: View {
    let userID: String
    let communityID: String
    let membership: CommunityMembership?
    let feedService: CommunityFeedService
    @Environment(\.dismiss) private var dismiss
    @State private var postBody = ""
    @State private var isPosting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0D0F1A").ignoresSafeArea()
                VStack(spacing: 16) {
                    TextEditor(text: $postBody)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color(hex: "161929"))
                        .cornerRadius(12)
                        .frame(minHeight: 150)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        isPosting = true
                        Task {
                            _ = try? await feedService.createPost(
                                communityID: communityID,
                                authorID: userID,
                                authorUsername: membership?.username ?? "",
                                authorDisplayName: membership?.displayName ?? "",
                                authorLevel: membership?.level ?? 1,
                                authorBadgeIDs: membership?.earnedBadgeIDs ?? [],
                                isCreatorPost: userID == communityID,
                                postType: .text,
                                body: postBody
                            )
                            dismiss()
                        }
                    }
                    .disabled(postBody.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
