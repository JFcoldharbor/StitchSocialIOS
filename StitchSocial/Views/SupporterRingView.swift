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

            // Supporter ring — centered on same ZStack
            if !subs.isEmpty {
                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .shadow(color: ringColor.opacity(0.7), radius: 5)
            }
        }
        // Count bubble pinned to bottom-trailing of the 100pt circle
        .overlay(alignment: .bottomTrailing) {
            if !subs.isEmpty {
                Button { showSheet = true } label: {
                    Text("\(subs.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ringColor)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                }
            }
        }
        .frame(width: 100, height: 100)
        .onAppear { loadSubs() }
        .sheet(isPresented: $showSheet) {
            SubscriptionsSheetView(subs: subs, userID: userID)
                .preferredColorScheme(.dark)
        }
    }

    private func loadSubs() {
        Task {
            // Always fetch for the VIEWER (current auth user), not profile owner
            guard let viewerID = Auth.auth().currentUser?.uid else { return }
            let fetched = (try? await SubscriptionService.shared.fetchMySubscriptions(userID: viewerID)) ?? []
            await MainActor.run { subs = fetched.filter { $0.status == .active } }
        }
    }
}

// MARK: - Subscriptions Sheet

struct SubscriptionsSheetView: View {

    let subs:   [ActiveSubscription]
    let userID: String

    @Environment(\.dismiss) private var dismiss
    @State private var creatorInfos: [String: BasicUserInfo] = [:]

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
                        Text("Supporting")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                        Text("\(subs.count) creator\(subs.count == 1 ? "" : "s")")
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
                .padding(.bottom, 20)

                // Subscription rows
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(subs) { sub in
                            SubRow(sub: sub, creatorInfo: creatorInfos[sub.creatorID])
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear { loadCreatorInfos() }
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
