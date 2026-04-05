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
                        episodeList
                        playButton
                    }
                }
            }
        }
        .task { await loadShow() }
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
        
        return LazyVStack(spacing: 0) {
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