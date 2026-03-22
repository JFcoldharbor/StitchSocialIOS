//
//  BadgePageView.swift
//  StitchSocial
//
//  Matches BadgeMockup.jsx:
//  ▸ Rarity legend row
//  ▸ Category filter chips
//  ▸ Badges grouped by category section (SEASONAL 6, HYPE MASTER 3…)
//  ▸ Cards: dark bg, rarity border glow, category accent dot, BadgeArtwork, name, rarity pill
//  ▸ In-progress rows when filter active
//  ▸ Detail sheet: shimmer line, large art, pills, PIN button
//
//  CACHING: @ObservedObject on BadgeService.shared — zero extra Firestore reads.
//  UserDefaults seed happens in BadgeService.listenForBadges before first render.
//

import SwiftUI

// MARK: - Rarity / Category styling (private — no conflict with BadgeArtwork.swift)

private extension BadgeRarity {
    var uiColor: Color {
        switch self {
        case .common:    return Color(hex: "9ca3af")
        case .uncommon:  return Color(hex: "4ade80")
        case .rare:      return Color(hex: "60a5fa")
        case .epic:      return Color(hex: "c084fc")
        case .legendary: return Color(hex: "fbbf24")
        }
    }
    var ringOpacity: Double {
        switch self {
        case .common: return 0.18; case .uncommon: return 0.25
        case .rare:   return 0.30; case .epic:     return 0.36; case .legendary: return 0.44
        }
    }
    var glowRadius: CGFloat {
        switch self {
        case .common: return 4; case .uncommon: return 7
        case .rare:   return 10; case .epic:    return 14; case .legendary: return 20
        }
    }
}

private extension BadgeCategory {
    var uiAccent: Color {
        switch self {
        case .seasonal:     return Color(hex: "f97316")
        case .hypeMaster:   return Color(hex: "eab308")
        case .coolVillain:  return Color(hex: "a855f7")
        case .creator:      return Color(hex: "3b82f6")
        case .engagement:   return Color(hex: "22c55e")
        case .reputation:   return Color(hex: "ef4444")
        case .social:       return Color(hex: "06b6d4")
        case .socialSignal: return Color(hex: "38bdf8")
        case .special:      return Color(hex: "f5c842")
        }
    }
}

// MARK: - BadgePageView

struct BadgePageView: View {

    let userID:      String
    let isOwner:     Bool
    let stats:       RealUserStats
    let xp:          Int
    let tierRaw:     String
    let signalStats: SignalStats

    @ObservedObject private var svc = BadgeService.shared
    @State private var filterCat: BadgeCategory? = nil
    @State private var selected: BadgeDefinition? = nil
    @State private var isLoading = true

    // MARK: - Computed (all in-memory)

    private var earned: [EarnedBadge]  { svc.earnedBadges(for: userID) }
    private var earnedIDs: Set<String> { Set(earned.map(\.id)) }
    private var boost: Double          { svc.hypeBoostMultiplier(for: userID) }

    /// Catalogue — ALL badges grouped by category (earned + locked)
    private var sections: [(BadgeCategory, [BadgeDefinition])] {
        let cats: [BadgeCategory] = filterCat.map { [$0] } ?? BadgeCategory.allCases
        return cats.compactMap { cat in
            let items = BadgeDefinition.allBadges.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    private var inProgress: [BadgeProgress] {
        let std = svc.badgeProgress(for: userID, stats: stats, xp: xp)
        let sig = SignalBadgeEvaluator.progress(stats: signalStats, alreadyEarned: earnedIDs)
        return (std + sig)
            .filter { !earnedIDs.contains($0.id) }
            .filter { filterCat == nil || $0.definition.category == filterCat }
            .sorted { $0.progressFraction > $1.progressFraction }
            .prefix(12).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(hex: "07070b").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    filterBar
                        .padding(.top, 16)

                    // Category sections
                    ForEach(sections, id: \.0.rawValue) { cat, items in
                        categorySection(cat: cat, items: items)
                    }

                    // In-progress (only show when no earned in filter, or always)
                    if !inProgress.isEmpty {
                        inProgressSection
                    }

                    // Empty state
                    if sections.isEmpty && inProgress.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    Spacer(minLength: 80)
                }
            }
        }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .onAppear  { svc.listenForBadges(userID: userID) }
        .onDisappear { if !isOwner { svc.stopListening(userID: userID) } }
        .sheet(item: $selected, content: detailSheet)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Stats row
            HStack(spacing: 10) {
                statPill(value: "\(earned.count)",                      label: "Earned")
                statPill(value: "\(BadgeDefinition.allBadges.count)",   label: "Total")
                if boost > 1 {
                    statPill(value: "+\(Int((boost-1)*100))%", label: "Boost",
                             accent: Color(hex: "f97316"))
                }
            }

            // Completion bar
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "fbbf24"), Color(hex: "f59e0b")],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width
                               * CGFloat(earned.count)
                               / CGFloat(max(1, BadgeDefinition.allBadges.count)))
                }
            }
            .frame(height: 3)

            // Rarity legend
            HStack(spacing: 14) {
                ForEach([BadgeRarity.common, .uncommon, .rare, .epic, .legendary], id: \.rawValue) { r in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(r.uiColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: r.uiColor, radius: 2)
                        Text(r.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.30))
                    }
                }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterChip(nil, label: "All")
                ForEach(BadgeCategory.allCases, id: \.rawValue) { cat in
                    filterChip(cat, label: cat.displayName)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 2)
        }
    }

    private func filterChip(_ cat: BadgeCategory?, label: String) -> some View {
        let active = filterCat == cat
        let accent: Color = cat?.uiAccent ?? .white
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filterCat = cat }
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(active ? .black : .white.opacity(0.48))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(active ? accent : Color.white.opacity(0.05)))
                .overlay(Capsule().stroke(active ? accent : Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    // MARK: - Category section

    private func categorySection(cat: BadgeCategory, items: [BadgeDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(cat.displayName.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(cat.uiAccent)
                    .tracking(1.4)
                Text("\(items.count)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.18))
                Rectangle()
                    .fill(Color.white.opacity(0.055))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { def in
                        let eb = earned.first { $0.id == def.id }
                        badgeCard(def: def, isEarned: eb != nil, isNew: eb?.isNew ?? false)
                            .onTapGesture {
                                selected = def
                                if isOwner, let eb, eb.isNew {
                                    Task { await svc.markSeen(userID: userID, badgeID: def.id) }
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 28)
    }

    // MARK: - Badge card (matches mockup BadgeCard)

    private func badgeCard(def: BadgeDefinition, isEarned: Bool, isNew: Bool) -> some View {
        ZStack {
            // Rarity radial glow
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    gradient: Gradient(colors: [def.rarity.uiColor.opacity(0.20), .clear]),
                    center: .bottom, startRadius: 0, endRadius: 80
                ))
                .blur(radius: 3)
                .padding(-4)

            // Card body
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.032), Color(hex: "08080c")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(def.rarity.uiColor.opacity(def.rarity.ringOpacity), lineWidth: 1.5)
                )

            VStack(spacing: 6) {
                // Top row: category dot + NEW dot
                HStack {
                    Circle()
                        .fill(def.category.uiAccent)
                        .frame(width: 5, height: 5)
                        .shadow(color: def.category.uiAccent, radius: 3)
                    Spacer()
                    if isNew {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                    }
                }
                .padding([.top, .horizontal], 9)

                // Badge artwork — dimmed if locked
                BadgeArtwork(id: def.id, size: 60)
                    .opacity(isEarned ? 1.0 : 0.35)
                    .shadow(color: isEarned ? def.rarity.uiColor.opacity(0.55) : .clear, radius: def.rarity.glowRadius)
                    .padding(.top, 4)

                // Name
                Text(def.name.replacingOccurrences(of: " — .*", with: "", options: .regularExpression))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)

                // Rarity pill
                Text(def.rarity.label.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundColor(def.rarity.uiColor)
                    .tracking(0.9)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(def.rarity.uiColor.opacity(0.12))
                    .overlay(Capsule().stroke(def.rarity.uiColor.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 130, height: 160)
    }

    // MARK: - In-progress section

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("IN PROGRESS")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.22))
                    .tracking(1.4)
                Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(inProgress) { bp in
                    progressRow(bp).onTapGesture { selected = bp.definition }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 28)
    }

    private func progressRow(_ bp: BadgeProgress) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(bp.definition.rarity.uiColor.opacity(0.20), lineWidth: 1))
                BadgeArtwork(id: bp.definition.id, size: 30).opacity(0.35)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(bp.definition.name.replacingOccurrences(of: " — .*", with: "", options: .regularExpression))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("\(bp.currentValue) / \(bp.targetValue)")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.28))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(bp.definition.category.uiAccent)
                            .frame(width: g.size.width * CGFloat(bp.progressFraction))
                    }.frame(height: 3)
                }
                .frame(height: 3)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🏅").font(.system(size: 44))
            Text("No badges yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            Text("Complete challenges to earn your first badge")
                .font(.caption).foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func detailSheet(_ def: BadgeDefinition) -> some View {
        let eb       = earned.first { $0.id == def.id }
        let isEarned = eb != nil

        ZStack {
            Color(hex: "12121a").ignoresSafeArea()

            // Top shimmer line
            VStack {
                LinearGradient(
                    colors: [.clear, def.rarity.uiColor.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing
                ).frame(height: 1)
                Spacer()
            }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, 14)

                // Large artwork with glow
                BadgeArtwork(id: def.id, size: 80)
                    .shadow(color: isEarned ? def.rarity.uiColor.opacity(0.75) : .clear, radius: 32)
                    .padding(.top, 24).padding(.bottom, 14)

                Text(def.name.replacingOccurrences(of: " — .*", with: "", options: .regularExpression))
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.white)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    rarityPill(def.rarity)
                    categoryPill(def.category)
                }
                .padding(.bottom, 16)

                if let eb = eb {
                    Text("Earned \(eb.earnedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "4ade80"))
                        .padding(.bottom, 8)
                }

                Text(def.description)
                    .font(.system(size: 13)).italic()
                    .foregroundColor(.white.opacity(0.38))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 22)

                if def.grantsSeasonalBoost, let season = def.season {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundColor(Color(hex: "f97316"))
                        Text("+\(Int((season.hypeBoostMultiplier-1)*100))% Hype Boost — \(season.displayName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "f97316"))
                    }
                    .padding(10)
                    .background(Color(hex: "f97316").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 36)
                    .padding(.bottom, 20)
                }

                Spacer()

                if isOwner, let eb = eb {
                    Button {
                        Task { await BadgeService.shared.togglePin(userID: userID, badgeID: def.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: eb.isPinned ? "pin.slash.fill" : "pin.fill")
                            Text(eb.isPinned ? "UNPIN BADGE" : "PIN TO PROFILE")
                                .font(.system(size: 13, weight: .black)).tracking(0.8)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(LinearGradient(
                            colors: [def.rarity.uiColor, def.rarity.uiColor.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 32).padding(.bottom, 40)
                } else if !isEarned {
                    Text("Complete the requirements to unlock this badge")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private func statPill(value: String, label: String, accent: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .black)).foregroundColor(accent)
            Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.28))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rarityPill(_ r: BadgeRarity) -> some View {
        Text(r.label.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(r.uiColor).tracking(0.8)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(r.uiColor.opacity(0.14))
            .overlay(Capsule().stroke(r.uiColor.opacity(0.3), lineWidth: 1))
            .clipShape(Capsule())
    }

    private func categoryPill(_ c: BadgeCategory) -> some View {
        Text(c.displayName)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(c.uiAccent)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(c.uiAccent.opacity(0.11))
            .overlay(Capsule().stroke(c.uiAccent.opacity(0.28), lineWidth: 1))
            .clipShape(Capsule())
    }
}
