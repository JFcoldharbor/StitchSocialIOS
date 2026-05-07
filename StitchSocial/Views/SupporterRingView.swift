//
//  SupporterRingView.swift
//  StitchSocial
//
//  Wraps EnhancedProfileImage with a tier-colored supporter ring + count bubble.
//  Tapping the bubble opens a sheet listing active subscriptions + perks.
//
//  CACHING: SubscriptionService.shared.mySubscriptions — 5min TTL, zero extra reads
//  if already loaded. fetchMySubscriptions is called once on sheet open.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Supporter Ring View

struct SupporterRingView: View {

    let imageURL:     URL?
    let userInitials: String
    let tierColor:    Color
    let size:         CGFloat
    let userID:       String

    @ObservedObject private var subService = SubscriptionService.shared
    @State private var showSheet = false
    @State private var subs: [ActiveSubscription] = []

    // Highest CoinPriceTier among active subs — drives ring color
    private var highestTier: CoinPriceTier? {
        subs.map(\.coinTier).max(by: { $0.rawValue < $1.rawValue })
    }

    private var ringColor: Color {
        switch highestTier {
        case .starter:  return Color(hex: "9ca3af")   // gray
        case .basic:    return Color(hex: "4ade80")   // green
        case .plus:     return Color(hex: "60a5fa")   // blue
        case .pro:      return Color(hex: "c084fc")   // purple
        case .max:      return Color(hex: "fbbf24")   // gold
        case .none:     return .clear
        }
    }

    var body: some View {
        ZStack {
            // Tier ring background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)

            Circle()
                .stroke(tierColor.opacity(0.6), lineWidth: 3)
                .frame(width: 90, height: 90)

            // Profile image
            AsyncImage(url: imageURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(tierColor.opacity(0.2))
                    .overlay(
                        Text(userInitials)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            // Supporter ring — only paints colored when there's a sub-tier
            // active. We always render the bubble below so the sheet entry
            // point is always accessible (zero extra reads — topSupporters
            // is loaded lazily by the sheet itself).
            if !subs.isEmpty {
                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .shadow(color: ringColor.opacity(0.7), radius: 5)
            }
        }
        // Bubble pinned to bottom-trailing — always visible. Shows the sub
        // count when present, otherwise a small heart icon. Either way it
        // opens the same sheet (which has Supporting + Top Supporters tabs).
        .overlay(alignment: .bottomTrailing) {
            Button { showSheet = true } label: {
                Group {
                    if !subs.isEmpty {
                        Text("\(subs.count)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(subs.isEmpty ? Color.white.opacity(0.85) : ringColor)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
            }
        }
        .frame(width: 100, height: 100)
        .onAppear { loadSubs() }
        .sheet(isPresented: $showSheet) {
            // Default to Top Supporters when the user isn't subscribed to
            // anyone — that's the only data the sheet has to show.
            SubscriptionsSheetView(
                subs: subs,
                userID: userID,
                initialTab: subs.isEmpty ? .topSupporters : .supporting
            )
            .preferredColorScheme(.dark)
        }
    }

    private func loadSubs() {
        Task {
            // Fetch the profile OWNER's subs via read-only path — never touches mySubscriptions
            let fetched = (try? await SubscriptionService.shared.fetchSubscriptions(forUserID: userID)) ?? []
            await MainActor.run { subs = fetched.filter { $0.status == .active } }
        }
    }
}

// MARK: - Subscriptions Sheet

enum SupporterTab: Hashable { case supporting, topSupporters }

/// One row of users/{id}.topSupporters. Names only — amounts are intentionally
/// private (tip totals stay between tipper and creator).
struct TopSupporterEntry: Identifiable, Hashable {
    let id: String          // tipperID
    let username: String
}

struct SubscriptionsSheetView: View {

    let subs:   [ActiveSubscription]
    let userID: String
    let initialTab: SupporterTab

    init(subs: [ActiveSubscription], userID: String, initialTab: SupporterTab = .supporting) {
        self.subs = subs
        self.userID = userID
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var creatorInfos: [String: BasicUserInfo] = [:]
    @State private var selectedTab: SupporterTab
    @State private var topSupporters: [TopSupporterEntry] = []

    var body: some View {
        ZStack {
            Color(hex: "07070b").ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTab == .supporting ? "Supporting" : "Top Supporters")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                        Text(headerSubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Tab picker
                HStack(spacing: 8) {
                    tabPill(.supporting, label: "Supporting")
                    tabPill(.topSupporters, label: "Top Supporters")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        switch selectedTab {
                        case .supporting:
                            if subs.isEmpty {
                                EmptyStateView(
                                    icon: "person.2",
                                    title: "Not supporting anyone yet",
                                    subtitle: "Subscribe to creators to see them here."
                                )
                            } else {
                                ForEach(subs) { sub in
                                    SubRow(sub: sub, creatorInfo: creatorInfos[sub.creatorID])
                                }
                            }
                        case .topSupporters:
                            if topSupporters.isEmpty {
                                EmptyStateView(
                                    icon: "heart.text.square",
                                    title: "No top supporters yet",
                                    subtitle: "Tippers who back your videos will show up here."
                                )
                            } else {
                                ForEach(Array(topSupporters.enumerated()), id: \.element.id) { idx, entry in
                                    TopSupporterRow(rank: idx + 1, entry: entry)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            loadCreatorInfos()
            loadTopSupporters()
        }
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .supporting:
            return "\(subs.count) creator\(subs.count == 1 ? "" : "s")"
        case .topSupporters:
            return "\(topSupporters.count) supporter\(topSupporters.count == 1 ? "" : "s")"
        }
    }

    @ViewBuilder
    private func tabPill(_ tab: SupporterTab, label: String) -> some View {
        let active = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? .black : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(active ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private func loadCreatorInfos() {
        // CACHING: UserService in-memory cache — no extra reads if already loaded
        Task {
            for sub in subs {
                if let info = try? await UserService().getUser(id: sub.creatorID) {
                    await MainActor.run { creatorInfos[sub.creatorID] = info }
                }
            }
        }
    }

    private func loadTopSupporters() {
        // Reads users/{userID}.topSupporters — denormalized top-10 array
        // refreshed by TipService.recordTipAggregates after each tip flush.
        // Names only; tip amounts stay private.
        Task {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            guard let data = try? await db.collection("users").document(userID).getDocument().data(),
                  let raw = data["topSupporters"] as? [[String: Any]] else {
                return
            }
            let parsed: [TopSupporterEntry] = raw.compactMap { row in
                guard let id = row["tipperID"] as? String,
                      !id.isEmpty,
                      let username = row["username"] as? String,
                      !username.isEmpty else { return nil }
                return TopSupporterEntry(id: id, username: username)
            }
            await MainActor.run { topSupporters = parsed }
        }
    }
}

// MARK: - Top Supporter Row

private struct TopSupporterRow: View {
    let rank:  Int
    let entry: TopSupporterEntry

    private var medalColor: Color {
        switch rank {
        case 1:  return Color(hex: "fbbf24") // gold
        case 2:  return Color(hex: "d4d4d8") // silver
        case 3:  return Color(hex: "f97316") // bronze
        default: return Color.white.opacity(0.3)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(rank <= 3 ? .black : .white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(medalColor)
                .clipShape(Circle())

            // Avatar placeholder (initial)
            Text(entry.username.prefix(1).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(Circle().stroke(medalColor.opacity(0.4), lineWidth: 1.5))

            // Username
            Text(entry.username)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(medalColor.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sub Row

private struct SubRow: View {

    let sub:         ActiveSubscription
    let creatorInfo: BasicUserInfo?

    private var tierAccent: Color {
        switch sub.coinTier {
        case .starter: return Color(hex: "9ca3af")
        case .basic:   return Color(hex: "4ade80")
        case .plus:    return Color(hex: "60a5fa")
        case .pro:     return Color(hex: "c084fc")
        case .max:     return Color(hex: "fbbf24")
        }
    }

    private var perks: [SubscriptionPerk] {
        SubscriptionPerks.perks(for: sub.coinTier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Creator row
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: creatorInfo.flatMap { URL(string: $0.profileImageURL ?? "") }) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Text(creatorInfo?.displayName.prefix(1).uppercased() ?? "?")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(tierAccent, lineWidth: 2))
                .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(creatorInfo?.displayName ?? "Loading...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("@\(creatorInfo?.username ?? "...")")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    // Tier pill
                    Text(sub.coinTier.displayName.uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(tierAccent)
                        .tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tierAccent.opacity(0.12))
                        .overlay(Capsule().stroke(tierAccent.opacity(0.3), lineWidth: 1))
                        .clipShape(Capsule())

                    Text("\(sub.daysRemaining)d left")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.28))
                }
            }

            // Perks row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(perks, id: \.rawValue) { perk in
                        HStack(spacing: 4) {
                            Image(systemName: perk.icon)
                                .font(.system(size: 8))
                                .foregroundColor(tierAccent)
                            Text(perk.displayName)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .overlay(Capsule().stroke(tierAccent.opacity(0.2), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
            }

            // Coins + renewal
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "fbbf24"))
                Text("\(sub.coinsPaid) coins/mo")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                if sub.autoRenew {
                    Label("Auto-renews", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tierAccent.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
