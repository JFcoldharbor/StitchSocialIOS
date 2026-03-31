//
//  ShowEditorView.swift
//  StitchSocial
//
//  Layer 6: Views - Show Editor (mirrors web ShowEditor.jsx)
//  Dependencies: ShowService, Show, Season, VideoCollection, EpisodeEditorView
//  Features: Show metadata editing, season CRUD, episode CRUD, navigate to episode editor
//
//  CACHING: ShowService handles all caching. loadFullShow() fetches in parallel.
//  Season add/delete invalidates cache automatically via ShowService.
//

import SwiftUI
import FirebaseAuth

struct ShowEditorView: View {
    
    // MARK: - Input
    
    @State var show: Show
    let isNew: Bool
    var onSave: ((Show) -> Void)?
    let onDismiss: () -> Void
    
    // MARK: - Services
    
    @StateObject private var showService = ShowService()
    
    // MARK: - State
    
    @State private var seasons: [Season] = []
    @State private var episodesBySeasonId: [String: [VideoCollection]] = [:]
    @State private var expandedSeason: String?
    @State private var saving = false
    @State private var isLoading = true
    
    // MARK: - Navigation
    
    @State private var selectedEpisode: EpisodeNavItem?
    @State private var showingEpisodeEditor = false
    
    struct EpisodeNavItem: Identifiable {
        let id: String
        let episode: VideoCollection
        let seasonId: String
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Show metadata
                showMetadataSection
                
                // Seasons + Episodes
                seasonsSection
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .navigationTitle(isNew ? "New Show" : "Edit Show")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await handleSave() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                        Text(saving ? "Saving..." : "Save")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(8)
                }
                .disabled(saving)
            }
        }
        .task {
            if !isNew { await loadFullShow() }
            isLoading = false
        }
        .fullScreenCover(item: $selectedEpisode) { item in
            EpisodeEditorView(
                showId: show.id,
                seasonId: item.seasonId,
                episode: item.episode,
                show: show,
                onDismiss: {
                    selectedEpisode = nil
                    // Refresh episodes for that season
                    Task {
                        if let eps = try? await showService.getEpisodes(showId: show.id, seasonId: item.seasonId) {
                            episodesBySeasonId[item.seasonId] = eps
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - Show Metadata
    
    private var showMetadataSection: some View {
        VStack(spacing: 12) {
            // Title + Creator
            HStack(spacing: 12) {
                fieldView("Title", text: $show.title)
                fieldView("Creator", text: $show.creatorName)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                TextField("Show description...", text: $show.description, axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(3...5)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
            }
            
            // Format + Genre + Status
            HStack(spacing: 10) {
                pickerView("Format", selection: $show.format, options: ShowFormat.allCases) { $0.displayName }
                pickerView("Genre", selection: $show.genre, options: ShowGenre.allCases) { $0.displayName }
                pickerView("Status", selection: $show.status, options: ShowStatus.allCases) { $0.displayName }
            }
            
            // Tags
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ShowTag.allCases, id: \.self) { tag in
                            Button {
                                if show.tags.contains(tag) {
                                    show.tags.removeAll { $0 == tag }
                                } else {
                                    show.tags.append(tag)
                                }
                            } label: {
                                Text(tag.displayName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(show.tags.contains(tag) ? .white : .gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(show.tags.contains(tag) ? tag.color.opacity(0.8) : Color.white.opacity(0.06))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            
            // Featured toggle
            Toggle(isOn: $show.isFeatured) {
                Text("Featured on home screen")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .tint(.pink)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Seasons Section
    
    private var seasonsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Seasons")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    Task { await addSeason() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("Add Season")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            
            if seasons.isEmpty {
                Text("No seasons yet. Add one to start creating episodes.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
            } else {
                ForEach(seasons) { season in
                    seasonCard(season)
                }
            }
        }
    }
    
    // MARK: - Season Card (Expandable)
    
    private func seasonCard(_ season: Season) -> some View {
        VStack(spacing: 0) {
            // Season header — tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSeason = expandedSeason == season.id ? nil : season.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(season.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\((episodesBySeasonId[season.id] ?? []).count) episodes")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Delete season
                    Button {
                        Task { await deleteSeason(season) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(expandedSeason == season.id ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            // Expanded: episode list
            if expandedSeason == season.id {
                Divider().background(Color.white.opacity(0.08))
                
                VStack(spacing: 6) {
                    let episodes = episodesBySeasonId[season.id] ?? []
                    
                    ForEach(episodes) { ep in
                        episodeRow(ep, seasonId: season.id)
                    }
                    
                    // Add episode button
                    Button {
                        Task { await addEpisode(seasonId: season.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("Add Episode")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.gray)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Episode Row
    
    private func episodeRow(_ ep: VideoCollection, seasonId: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Ep \(ep.episodeNumber ?? 0): \(ep.title.isEmpty ? "Untitled" : ep.title)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(ep.segmentCount) segments")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Edit / Upload
            Button {
                selectedEpisode = EpisodeNavItem(id: ep.id, episode: ep, seasonId: seasonId)
            } label: {
                Text("Edit / Upload")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.pink)
            }
            
            // Delete
            Button {
                Task { await deleteEpisode(ep, seasonId: seasonId) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func handleSave() async {
        saving = true
        show.seasonCount = seasons.count
        show.totalEpisodes = episodesBySeasonId.values.flatMap { $0 }.count
        do {
            try await showService.saveShow(show)
            onSave?(show)
        } catch {
            print("❌ SHOW EDITOR: Save failed: \(error)")
        }
        saving = false
    }
    
    private func loadFullShow() async {
        do {
            let (loadedShow, loadedSeasons, loadedEpisodes) = try await showService.loadFullShow(show.id)
            if let s = loadedShow { show = s }
            seasons = loadedSeasons
            episodesBySeasonId = loadedEpisodes
            if let first = loadedSeasons.first { expandedSeason = first.id }
        } catch {
            print("❌ SHOW EDITOR: Load failed: \(error)")
        }
    }
    
    private func addSeason() async {
        do {
            // Ensure show doc exists in Firestore before adding subcollections
            try await showService.saveShow(show)
            let season = try await showService.addSeason(to: show.id)
            seasons.append(season)
            episodesBySeasonId[season.id] = []
            expandedSeason = season.id
        } catch {
            print("❌ SHOW EDITOR: Add season failed: \(error)")
        }
    }
    
    private func deleteSeason(_ season: Season) async {
        do {
            try await showService.deleteSeason(showId: show.id, seasonId: season.id)
            seasons.removeAll { $0.id == season.id }
            episodesBySeasonId.removeValue(forKey: season.id)
        } catch {
            print("❌ SHOW EDITOR: Delete season failed: \(error)")
        }
    }
    
    private func addEpisode(seasonId: String) async {
        do {
            let ep = try await showService.addEpisode(
                showId: show.id,
                seasonId: seasonId,
                creatorID: show.creatorID,
                creatorName: show.creatorName,
                format: show.format
            )
            episodesBySeasonId[seasonId, default: []].append(ep)
        } catch {
            print("❌ SHOW EDITOR: Add episode failed: \(error)")
        }
    }
    
    private func deleteEpisode(_ ep: VideoCollection, seasonId: String) async {
        do {
            try await showService.deleteEpisode(showId: show.id, seasonId: seasonId, episodeId: ep.id)
            episodesBySeasonId[seasonId]?.removeAll { $0.id == ep.id }
        } catch {
            print("❌ SHOW EDITOR: Delete episode failed: \(error)")
        }
    }
    
    // MARK: - Reusable Field Views
    
    private func fieldView(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            TextField("\(label)...", text: text)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
        }
    }
    
    private func pickerView<T: Hashable>(_ label: String, selection: Binding<T>, options: [T], display: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(display(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .padding(4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
        }
    }
}
