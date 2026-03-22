//
//  ProfileBadgePreviewRow.swift
//  StitchSocial
//
//  CACHING: All data from BadgeService.shared in-memory cache.
//  Zero Firestore reads. Uses .sheet() — no NavigationStack required.

import SwiftUI

struct ProfileBadgePreviewRow: View {

    let userID: String
    let isOwner: Bool
    let stats: RealUserStats
    let xp: Int
    let tierRaw: String
    let signalStats: SignalStats

    @ObservedObject private var service = BadgeService.shared
    @State private var showBadgePage = false

    private var earned: [EarnedBadge] { service.earnedBadges(for: userID) }
    private var boost: Double          { service.hypeBoostMultiplier(for: userID) }

    private var previewBadges: [EarnedBadge] {
        let pinned = earned.filter { $0.isPinned }
        let rest   = earned.filter { !$0.isPinned }.sorted { $0.earnedAt > $1.earnedAt }
        return Array((pinned + rest).prefix(6))
    }

    private var newCount: Int { earned.filter { $0.isNew }.count }

    var body: some View {
        Button { showBadgePage = true } label: {
            HStack(spacing: 10) {

                HStack(spacing: -6) {
                    ForEach(previewBadges.prefix(5)) { eb in
                        if let def = eb.definition {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().stroke(eb.isNew ? def.rarity.glowColor : Color.clear, lineWidth: 2)
                                    )
                                Text(def.emoji).font(.system(size: 16))
                            }
                        }
                    }
                    if earned.count > 5 {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 34, height: 34)
                            Text("+\(earned.count - 5)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(earned.count) Badges")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                        if newCount > 0 {
                            Text("\(newCount) new")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                    if boost > 1.0 {
                        Label("+\(Int((boost - 1) * 100))% Hype Active", systemImage: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    } else {
                        Text("View collection")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showBadgePage) {
            NavigationStack {
                BadgePageView(
                    userID: userID,
                    isOwner: isOwner,
                    stats: stats,
                    xp: xp,
                    tierRaw: tierRaw,
                    signalStats: signalStats
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showBadgePage = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
