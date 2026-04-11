//
//  ShowDetailView.swift
//  StitchSocial
//
//  Created by James Garmon on 4/2/26.
//


//
//  ShowDetailView.swift
//  StitchSocial
//
//  Layer 6: Views - Show Detail Page (viewer-facing)
//  Season tabs, episode list, play button. Opens from profile show cards or discovery.
//  Tapping an episode opens the existing CollectionPlayerView.
//

import SwiftUI
import FirebaseAuth

struct ShowDetailView: View {
    
    let showId: String
    let initialEpisodes: [VideoCollection]  // passed from parent to avoid re-fetch
    let onDismiss: () -> Void
    let onPlayEpisode: (VideoCollection) -> Void
    
    @StateObject private var showService = ShowService()
    
    @State private var show: Show?
    @State private var seasons: [Season] = []
    @State private var episodesBySeasonId: [String: [VideoCollection]] = [:]
    @State private var selectedSeasonId: String?
    @State private var isLoading = true
    @State private var episodeToEdit: VideoCollection?
    @State private var showingEpisodeEditor = false
    @State private var isReordering = false

    private var isOwner: Bool {
        show?.creatorID == Auth.auth().currentUser?.uid
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView().tint(.white)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                        if seasons.count > 1 { seasonTabs }
                        weeklyScheduleSection
                        episodeList
                        playButton
                    }
                }
            }
        }
        .task { await loadShow() }
        .fullScreenCover(isPresented: $showingEpisodeEditor) {
            if let ep = episodeToEdit, let s = show,
               let season = seasons.first(where: { episodesBySeasonId[$0.id]?.contains(where: { $0.id == ep.id }) == true }) {
                EpisodeEditorView(
                    showId: showId,
                    seasonId: season.id,
                    episode: ep,
                    show: s,
                    onDismiss: {
                        showingEpisodeEditor = false
                        Task { await loadShow() }
                    }
                )
                .preferredColorScheme(.dark)
            }
        }
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover gradient
            LinearGradient(
                colors: [contentTypeColor.opacity(0.25), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 160)
            
            // Overlay gradient for text readability
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                .frame(height: 160)
            
            VStack(alignment: .leading, spacing: 4) {
                // Badges
                HStack(spacing: 4) {
                    badge(show?.contentType.displayName.uppercased() ?? "SHOW", color: contentTypeColor)
                    badge(show?.genre.displayName.uppercased() ?? "", color: .purple)
                    if show?.status == .published {
                        badge("PUBLISHED", color: .green)
                    }
                    if totalSeasonCount > 1 {
                        badge("\(totalSeasonCount) SEASONS", color: .cyan)
                    }
                }
                
                Text(show?.title ?? "Untitled Show")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Text("by @\(show?.creatorName ?? "")")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(totalEpisodeCount) episodes")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(totalViewCount) views")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(16)
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .padding(12)
                }
                Spacer()
            }
            .frame(height: 160)
        }
    }
    
    // MARK: - Season Tabs
    
    private var seasonTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(seasons) { season in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSeasonId = season.id
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(season.title)
                                .font(.system(size: 12, weight: selectedSeasonId == season.id ? .bold : .regular))
                                .foregroundColor(selectedSeasonId == season.id ? contentTypeColor : .white.opacity(0.35))
                            
                            Rectangle()
                                .fill(selectedSeasonId == season.id ? contentTypeColor : Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.06))
        }
    }
    
    // MARK: - Episode List
    
    private var episodeList: some View {
        let episodes = currentSeasonEpisodes

        // Owner with cadence set gets drag-reorder List; viewers get LazyVStack
        if isOwner, show?.scheduleConfig?.cadence != .custom, show?.scheduleConfig != nil {
            return AnyView(ownerEpisodeList(episodes: episodes))
        }
        return AnyView(viewerEpisodeList(episodes: episodes))
    }

    private func viewerEpisodeList(episodes: [VideoCollection]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                Button { onPlayEpisode(ep) } label: {
                    HStack(spacing: 10) {
                        // Thumbnail
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 70, height: 42)
                            
                            if let cover = ep.coverImageURL, let url = URL(string: cover) {
                                AsyncImage(url: url) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.25))
                                }
                                .frame(width: 70, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.25))
                            }
                            
                            // Duration badge
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text(ep.formattedTotalDuration)
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(2)
                                        .padding(2)
                                }
                            }
                            .frame(width: 70, height: 42)
                        }
                        
                        // Episode info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ep.episodeDisplayTitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text("\(ep.segmentCount) segments · \(formatCount(ep.totalViews)) views")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        
                        Spacer()
                        
                        // NEW badge for latest episode
                        if idx == episodes.count - 1 && episodes.count > 1 {
                            Text("NEW")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(contentTypeColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(contentTypeColor.opacity(0.15))
                                .cornerRadius(3)
                        }

                        // Owner edit / reschedule button
                        if isOwner {
                            Button {
                                episodeToEdit = ep
                                showingEpisodeEditor = true
                            } label: {
                                Image(systemName: ep.status == .published ? "pencil.circle" : "calendar.badge.clock")
                                    .font(.system(size: 18))
                                    .foregroundColor(ep.status == .published ? .gray.opacity(0.5) : .cyan.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                if idx < episodes.count - 1 {
                    Divider().background(Color.white.opacity(0.04)).padding(.leading, 96)
                }
            }
        }
    }

    private func ownerEpisodeList(episodes: [VideoCollection]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Drag to reorder — dates will update automatically")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                if isReordering {
                    ProgressView().scaleEffect(0.6).tint(.cyan)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

            List {
                ForEach(episodes) { ep in
                    episodeRowContent(ep: ep, idx: episodes.firstIndex(where: { $0.id == ep.id }) ?? 0, total: episodes.count)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .onMove { from, to in
                    guard let show = show, let config = show.scheduleConfig else { return }
                    var reordered = episodes
                    reordered.move(fromOffsets: from, toOffset: to)
                    // Update local state immediately
                    if let sid = selectedSeasonId {
                        episodesBySeasonId[sid] = reordered
                    }
                    // Batch-write new dates
                    isReordering = true
                    Task {
                        try? await showService.applyReorderedSchedule(episodes: reordered, show: show)
                        isReordering = false
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: CGFloat(episodes.count) * 66)
        }
    }

    @ViewBuilder
    private func episodeRowContent(ep: VideoCollection, idx: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                    .frame(width: 70, height: 42)
                if let cover = ep.coverImageURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Image(systemName: "play.fill").foregroundColor(.white.opacity(0.25)) }
                        .frame(width: 70, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ep.episodeDisplayTitle).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                if let pub = ep.publishedAt {
                    Text(pub > Date() ? "Premieres \(pub.formatted(date: .abbreviated, time: .shortened))" :
                         "\(ep.segmentCount) segments · \(formatCount(ep.totalViews)) views")
                        .font(.system(size: 9)).foregroundColor(pub > Date() ? .cyan.opacity(0.8) : .white.opacity(0.4))
                } else {
                    Text("\(ep.segmentCount) segments · \(formatCount(ep.totalViews)) views")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            if isOwner {
                Button { episodeToEdit = ep; showingEpisodeEditor = true } label: {
                    Image(systemName: ep.publishedAt != nil && ep.publishedAt! > Date() ? "calendar.badge.clock" : "pencil.circle")
                        .font(.system(size: 18))
                        .foregroundColor(ep.publishedAt != nil && ep.publishedAt! > Date() ? .cyan.opacity(0.8) : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { if !isOwner { onPlayEpisode(ep) } }
    }

    // MARK: - Play Button
    
    private var playButton: some View {
        let episodes = currentSeasonEpisodes
        
        return VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.06))
            
            HStack(spacing: 8) {
                Button {
                    if let first = episodes.first { onPlayEpisode(first) }
                } label: {
                    Text("Play \(selectedSeasonTitle)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [contentTypeColor, contentTypeColor.opacity(0.7)],
                                          startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(8)
                }
                
                Button(action: {}) {
                    Text("Share")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Weekly Schedule
    
    // Derive schedule from publishedAt dates on all episodes.
    // Shows current week Mon-Sun. Episodes published this week get LIVE/NEW badges.
    // Episodes scheduled for future days show SOON. Past episodes show checkmarks.
    
    private var weeklyScheduleSection: some View {
        let days = currentWeekSchedule
        guard !days.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("This Week")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(weekRangeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
                
                VStack(spacing: 0) {
                    ForEach(days) { day in
                        scheduleRow(day)
                        if day.id != days.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.04))
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color.white.opacity(0.02))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        )
    }
    
    private func scheduleRow(_ day: ScheduleDay) -> some View {
        Button {
            if let ep = day.episode, day.state != .soon { onPlayEpisode(ep) }
        } label: {
            HStack(spacing: 12) {
                // Day + date column
                VStack(spacing: 1) {
                    Text(day.dayShort)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(day.isToday ? contentTypeColor : .gray)
                    Text("\(day.dayNumber)")
                        .font(.system(size: 16, weight: day.isToday ? .bold : .regular))
                        .foregroundColor(day.isToday ? .white : .gray.opacity(0.6))
                }
                .frame(width: 32)
                
                // Thumbnail or state indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(day.episode != nil ? 0.08 : 0.03))
                        .frame(width: 52, height: 34)
                    
                    if let ep = day.episode, let cover = ep.coverImageURL, let url = URL(string: cover) {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(width: 52, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if day.state == .soon || day.state == .upcoming {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    
                    // LIVE badge overlay
                    if day.state == .live {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.7))
                            .frame(width: 52, height: 34)
                        Text("LIVE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                
                // Episode info
                VStack(alignment: .leading, spacing: 2) {
                    if let ep = day.episode {
                        Text(ep.title.isEmpty ? "Episode \(ep.episodeNumber ?? 0)" : ep.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(day.state == .upcoming ? .gray.opacity(0.5) : .white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text("\(ep.segmentCount) seg · \(formatDuration(ep.totalDuration))")
                                .font(.system(size: 9))
                                .foregroundColor(.gray.opacity(0.6))
                            if ep.totalViews > 0 {
                                Text("· \(formatCount(ep.totalViews)) views")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }
                    } else {
                        Text(day.state == .upcoming ? "Drops \(day.relativeLabel)" : "No episode")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                }
                
                Spacer()
                
                // State badge
                switch day.state {
                case .live:
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(4)
                case .new:
                    Text("NEW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(contentTypeColor)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(contentTypeColor.opacity(0.15))
                        .cornerRadius(4)
                case .soon:
                    Text("SOON")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(4)
                case .upcoming:
                    EmptyView()
                case .watched:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(day.episode == nil || day.state == .soon || day.state == .upcoming)
    }
    
    // MARK: - Schedule Data Model
    
    enum ScheduleState { case live, new, soon, upcoming, watched }
    
    struct ScheduleDay: Identifiable {
        let id: String
        let date: Date
        let dayShort: String      // "MON"
        let dayNumber: Int        // 14
        let isToday: Bool
        let episode: VideoCollection?
        let state: ScheduleState
        var relativeLabel: String { isToday ? "today" : "tomorrow" }
    }
    
    private var currentWeekSchedule: [ScheduleDay] {
        let calendar = Calendar.current
        let now = Date()
        let allEpisodes = episodesBySeasonId.values.flatMap { $0 }
        guard !allEpisodes.isEmpty else { return [] }
        
        // Get Mon-Sun of current week
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        
        // Build day formatter
        let dayNameFormatter = DateFormatter()
        dayNameFormatter.dateFormat = "EEE"
        
        let result: [ScheduleDay] = days.map { day in
            let isToday = calendar.isDateInToday(day)
            let isFuture = day > now
            let dayNum = calendar.component(.day, from: day)
            let dayShort = dayNameFormatter.string(from: day).uppercased()
            
            // Find episode published on this day
            let ep = allEpisodes.first(where: { ep in
                guard let pub = ep.publishedAt else { return false }
                return calendar.isDate(pub, inSameDayAs: day)
            })
            
            let state: ScheduleState
            if let ep = ep {
                if isToday {
                    // Live if published within last 2 hours
                    let age = now.timeIntervalSince(ep.publishedAt ?? now)
                    state = age < 7200 ? .live : .new
                } else if isFuture {
                    state = .soon
                } else {
                    state = .watched
                }
            } else {
                state = isFuture ? .upcoming : .watched
            }
            
            return ScheduleDay(
                id: dayShort + "\(dayNum)",
                date: day,
                dayShort: dayShort,
                dayNumber: dayNum,
                isToday: isToday,
                episode: ep,
                state: state
            )
        }
        
        // Only show if at least one episode falls in this week
        let hasEpisodes = result.contains { $0.episode != nil }
        return hasEpisodes ? result : []
    }
    
    private var weekRangeLabel: String {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: weekStart)) — \(fmt.string(from: weekEnd))"
    }
    
    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
    
    // MARK: - Load
    
    private func loadShow() async {
        do {
            let (loadedShow, loadedSeasons, loadedEpisodes) = try await showService.loadFullShow(showId)
            show = loadedShow
            seasons = loadedSeasons
            episodesBySeasonId = loadedEpisodes
            selectedSeasonId = loadedSeasons.first?.id
        } catch {
            // Fallback: use initialEpisodes passed in
            print("❌ SHOW DETAIL: Load failed, using initial episodes: \(error)")
        }
        isLoading = false
    }
    
    // MARK: - Helpers
    
    private var currentSeasonEpisodes: [VideoCollection] {
        guard let sid = selectedSeasonId else {
            return episodesBySeasonId.values.flatMap { $0 }
                .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
        }
        return (episodesBySeasonId[sid] ?? [])
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }
    
    private var selectedSeasonTitle: String {
        guard let sid = selectedSeasonId,
              let season = seasons.first(where: { $0.id == sid }) else { return "All" }
        return season.title
    }
    
    private var contentTypeColor: Color {
        ShowCard.colorFor(show?.contentType ?? .series)
    }
    
    private var totalSeasonCount: Int { seasons.count }
    private var totalEpisodeCount: Int { episodesBySeasonId.values.flatMap { $0 }.count }
    private var totalViewCount: String {
        formatCount(episodesBySeasonId.values.flatMap { $0 }.reduce(0) { $0 + $1.totalViews })
    }
    
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(3)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 { return String(format: "%.1fM", Double(count) / 1000000) }
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return "\(count)"
    }
}
