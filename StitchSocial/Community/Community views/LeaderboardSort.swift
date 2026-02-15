//
//  LeaderboardSort.swift
//  StitchSocial
//
//  Created by James Garmon on 2/13/26.
//


//
//  CommunitySubViews.swift
//  StitchSocial
//
//  Layer 8: Views - Detail views for community card taps
//  1. MemberLeaderboardView — Upper Flow + Top Supporters (reusable, sort param)
//  2. BadgeGalleryView — All 25 badges with earned/locked states
//  3. PostDetailView — Full post + replies thread
//  4. HighlightPlayerView — Stream highlight video playback
//
//  CACHING: MemberLeaderboardView uses fetchMembers (already paginated/cached).
//           PostDetailView uses fetchReplies (cursor-paginated, 2-min cache).
//           BadgeGalleryView is pure local — zero Firestore reads.
//

import SwiftUI

// ============================================================
// SHARED COLORS (same as CommunityDetailView)
// ============================================================

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

// ============================================================
// 1. MEMBER LEADERBOARD VIEW
//    Reusable for Upper Flow (sort by level) and Top Supporters (sort by hype)
//    CACHING: fetchMembers already cached in CommunityService (paginated)
// ============================================================

enum LeaderboardSort: String, CaseIterable {
    case level = "Level"
    case hypesGiven = "Hype Given"
    case hypesReceived = "Hype Received"
    case posts = "Posts"
    case streams = "Streams Attended"
}

struct MemberLeaderboardView: View {
    let communityID: String
    let initialSort: LeaderboardSort
    
    @ObservedObject private var communityService = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var members: [CommunityMembership] = []
    @State private var selectedSort: LeaderboardSort = .level
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(textSecondary)
                    }
                    Spacer()
                    Text(selectedSort == .level ? "Upper Flow" : "Top Supporters")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textPrimary)
                    Spacer()
                    // Placeholder for symmetry
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)
                
                // Sort tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(LeaderboardSort.allCases, id: \.self) { sort in
                            Button {
                                selectedSort = sort
                                sortMembers()
                            } label: {
                                Text(sort.rawValue)
                                    .font(.system(size: 12, weight: selectedSort == sort ? .bold : .medium))
                                    .foregroundColor(selectedSort == sort ? accentCyan : textMuted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedSort == sort ? accentCyan.opacity(0.12) : cardBg)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedSort == sort ? accentCyan.opacity(0.3) : cardBorder, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
                
                // List
                if isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: accentCyan))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                                leaderboardRow(rank: index + 1, member: member)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .task {
            selectedSort = initialSort
            let result = try? await communityService.fetchMembers(creatorID: communityID, limit: 50)
            members = result?.members ?? []
            sortMembers()
            isLoading = false
        }
    }
    
    private func sortMembers() {
        switch selectedSort {
        case .level: members.sort { $0.level > $1.level }
        case .hypesGiven: members.sort { $0.totalHypesGiven > $1.totalHypesGiven }
        case .hypesReceived: members.sort { $0.totalHypesReceived > $1.totalHypesReceived }
        case .posts: members.sort { $0.totalPosts > $1.totalPosts }
        case .streams: members.sort { $0.streamsAttended > $1.streamsAttended }
        }
    }
    
    private func leaderboardRow(rank: Int, member: CommunityMembership) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(rank <= 3 ? accentGold : textMuted)
                .frame(width: 28)
            
            // Avatar
            memberAvatar(name: member.displayName, size: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.username.isEmpty ? member.displayName : member.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)
                    
                    if member.isModerator {
                        Text("MOD")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(accentPurple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(accentPurple.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                
                Text("Lv \(member.level) • \(member.localXP) XP")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
            }
            
            Spacer()
            
            // Stat value
            VStack(alignment: .trailing, spacing: 1) {
                Text(statValue(for: member))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accentOrange)
                Text(selectedSort.rawValue)
                    .font(.system(size: 9))
                    .foregroundColor(textMuted)
            }
            
            // Badges
            if let topBadge = CommunityBadgeDefinition.allBadges.last(where: { member.earnedBadgeIDs.contains($0.id) }) {
                Text(topBadge.emoji)
                    .font(.system(size: 18))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            rank <= 3
                ? RoundedRectangle(cornerRadius: 12).fill(accentGold.opacity(0.04)).eraseToAnyView()
                : RoundedRectangle(cornerRadius: 12).fill(Color.clear).eraseToAnyView()
        )
    }
    
    private func statValue(for member: CommunityMembership) -> String {
        switch selectedSort {
        case .level: return "Lv \(member.level)"
        case .hypesGiven: return "\(member.totalHypesGiven)"
        case .hypesReceived: return "\(member.totalHypesReceived)"
        case .posts: return "\(member.totalPosts)"
        case .streams: return "\(member.streamsAttended)"
        }
    }
}

// ============================================================
// 2. BADGE GALLERY VIEW
//    All 25 badges — earned vs locked, progress indicator
//    CACHING: 100% local. Zero Firestore reads. Pure logic against static badge list.
// ============================================================

struct BadgeGalleryView: View {
    let currentLevel: Int
    let earnedBadgeIDs: [String]
    
    @Environment(\.dismiss) private var dismiss
    
    private var earnedSet: Set<String> {
        Set(earnedBadgeIDs)
    }
    
    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(textSecondary)
                    }
                    Spacer()
                    Text("Badge Gallery")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textPrimary)
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 8)
                
                // Progress summary
                let earned = CommunityBadgeDefinition.allBadges.filter { $0.level <= currentLevel }.count
                let total = CommunityBadgeDefinition.allBadges.count
                
                HStack(spacing: 12) {
                    Text("⭐ Lv \(currentLevel)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accentGold)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(cardBorder)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [accentGold, accentOrange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(earned) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                    
                    Text("\(earned)/\(total)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Badge grid
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(CommunityBadgeDefinition.allBadges) { badge in
                            let isEarned = badge.level <= currentLevel
                            let isNext = !isEarned && (CommunityBadgeDefinition.nextBadge(afterLevel: currentLevel)?.id == badge.id)
                            
                            HStack(spacing: 14) {
                                // Badge icon
                                ZStack {
                                    Circle()
                                        .fill(isEarned ? accentPurple.opacity(0.2) : cardBg)
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Circle().stroke(
                                                isNext ? accentCyan : (isEarned ? accentGold.opacity(0.3) : cardBorder),
                                                lineWidth: isNext ? 2 : 1
                                            )
                                        )
                                    
                                    Text(badge.emoji)
                                        .font(.system(size: 22))
                                        .opacity(isEarned ? 1.0 : 0.3)
                                }
                                
                                // Info
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(badge.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(isEarned ? textPrimary : textMuted)
                                        
                                        Text("Lv \(badge.level)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(isEarned ? accentGold : textMuted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isEarned ? accentGold : textMuted).opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    
                                    Text(badge.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(textMuted)
                                    
                                    Text(badge.rewardDescription)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isEarned ? accentCyan : textMuted.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                // Status
                                if isEarned {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(accentGold)
                                } else if isNext {
                                    VStack(spacing: 1) {
                                        Text("\(badge.level - currentLevel)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(accentCyan)
                                        Text("lvls")
                                            .font(.system(size: 8))
                                            .foregroundColor(textMuted)
                                    }
                                } else {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(textMuted.opacity(0.4))
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isNext ? accentCyan.opacity(0.04) : cardBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isNext ? accentCyan.opacity(0.3) : cardBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// ============================================================
// 3. POST DETAIL VIEW
//    Full post + replies thread with compose reply
//    CACHING: fetchReplies cursor-paginated, 2-min TTL in FeedService
// ============================================================

struct PostDetailView: View {
    let post: CommunityPost
    let communityID: String
    let userID: String
    let membership: CommunityMembership?
    
    @ObservedObject private var feedService = CommunityFeedService.shared
    @ObservedObject private var xpService = CommunityXPService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var replyText = ""
    @State private var isReplying = false
    
    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(textSecondary)
                    }
                    Spacer()
                    Text("Post")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textPrimary)
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Original post
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                memberAvatar(name: post.authorDisplayName, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("@\(post.authorUsername)")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(textPrimary)
                                        if post.isCreatorPost {
                                            Text("CREATOR")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(accentCyan)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(accentCyan.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text("Lv \(post.authorLevel) • \(timeAgo(post.createdAt))")
                                        .font(.system(size: 11))
                                        .foregroundColor(textMuted)
                                }
                                Spacer()
                            }
                            
                            Text(post.body)
                                .font(.system(size: 15))
                                .foregroundColor(textPrimary)
                                .lineSpacing(5)
                            
                            HStack(spacing: 20) {
                                Button {
                                    Task { _ = try? await feedService.hypePost(postID: post.id, communityID: communityID, userID: userID) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("🔥").font(.system(size: 16))
                                        Text("\(post.hypeCount)").font(.system(size: 13)).foregroundColor(textSecondary)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Text("💬").font(.system(size: 16))
                                    Text("\(post.replyCount)").font(.system(size: 13)).foregroundColor(textSecondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .background(cardBg)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(cardBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                        
                        // Replies header
                        Text("REPLIES")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(textMuted)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        
                        // Replies
                        ForEach(feedService.currentReplies) { reply in
                            replyRow(reply)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 3)
                        }
                        
                        Spacer(minLength: 80)
                    }
                }
                
                // Reply input
                HStack(spacing: 10) {
                    TextField("Write a reply...", text: $replyText)
                        .foregroundColor(textPrimary)
                        .padding(10)
                        .background(cardBg)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
                    
                    Button {
                        guard !replyText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isReplying = true
                        Task {
                            _ = try? await feedService.createReply(
                                postID: post.id,
                                communityID: communityID,
                                authorID: userID,
                                authorUsername: membership?.username ?? "",
                                authorDisplayName: membership?.displayName ?? "",
                                authorLevel: membership?.level ?? 1,
                                isCreatorReply: userID == communityID,
                                body: replyText
                            )
                            replyText = ""
                            isReplying = false
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty ? textMuted : accentCyan)
                    }
                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty || isReplying)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(darkBg)
            }
        }
        .task {
            _ = try? await feedService.fetchReplies(postID: post.id, communityID: communityID, refresh: true)
        }
    }
    
    private func replyRow(_ reply: CommunityReply) -> some View {
        HStack(alignment: .top, spacing: 10) {
            memberAvatar(name: reply.authorDisplayName, size: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("@\(reply.authorUsername)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(textPrimary)
                    
                    if reply.isCreatorReply {
                        Text("CREATOR")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(accentCyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accentCyan.opacity(0.12))
                            .cornerRadius(3)
                    }
                    
                    Text("Lv \(reply.authorLevel)")
                        .font(.system(size: 9))
                        .foregroundColor(textMuted)
                    
                    Spacer()
                    
                    Text(timeAgo(reply.createdAt))
                        .font(.system(size: 9))
                        .foregroundColor(textMuted)
                }
                
                Text(reply.body)
                    .font(.system(size: 13))
                    .foregroundColor(textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1))
    }
}

// ============================================================
// 4. HIGHLIGHT PLAYER VIEW
//    Stream highlight video playback (placeholder — integrate AVPlayer)
// ============================================================

struct HighlightPlayerView: View {
    let communityID: String
    let communityName: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(communityName)'s Highlights")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("Stream Replays")
                            .font(.system(size: 11))
                            .foregroundColor(textSecondary)
                    }
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 12)
                
                // Video area placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [accentPurple.opacity(0.3), accentCyan.opacity(0.2), accentPink.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 16) {
                        Circle()
                            .fill(accentCyan.opacity(0.3))
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(accentCyan, lineWidth: 2))
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            )
                        
                        Text("Highlights from \(communityName)")
                            .font(.system(size: 14))
                            .foregroundColor(textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Info section
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(communityName)'s Best Moments")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textPrimary)
                    
                    Text("Clips from the highest-engagement moments of recent live streams. Accepted video comments from viewers appear here.")
                        .font(.system(size: 13))
                        .foregroundColor(textSecondary)
                        .lineSpacing(4)
                    
                    HStack(spacing: 16) {
                        highlightStat(emoji: "🔥", label: "Hype Events", value: "—")
                        highlightStat(emoji: "👁", label: "Peak Viewers", value: "—")
                        highlightStat(emoji: "📹", label: "Clips", value: "—")
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(cardBg)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardBorder, lineWidth: 1))
                .padding(.horizontal, 16)
                
                Spacer(minLength: 40)
            }
        }
    }
    
    private func highlightStat(emoji: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 18))
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(accentOrange)
            Text(label).font(.system(size: 9)).foregroundColor(textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// ============================================================
// SHARED HELPERS
// ============================================================

private func memberAvatar(name: String, size: CGFloat) -> some View {
    let g: [[Color]] = [[accentCyan, accentPurple], [accentPink, accentOrange], [accentPurple, accentPink], [accentOrange, accentGold]]
    let parts = name.split(separator: " ")
    let ini = String((parts.first?.prefix(1) ?? "") + (parts.count > 1 ? parts[1].prefix(1) : "")).uppercased()
    return Circle()
        .fill(LinearGradient(colors: g[abs(name.hashValue) % g.count], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: size, height: size)
        .overlay(Text(ini).font(.system(size: size * 0.38, weight: .bold)).foregroundColor(.white))
}

private func timeAgo(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    return "\(Int(interval / 86400))d"
}

// Type erasure helper for conditional backgrounds
extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}