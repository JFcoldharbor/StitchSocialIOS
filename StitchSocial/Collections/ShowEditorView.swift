//
//  ShowEditorView.swift
//  StitchSocial
//
//  Layer 6: Views - Show Editor (mirrors web ShowEditor.jsx)
//  Episodes write to videoCollections via ShowService (corrected architecture)
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import UniformTypeIdentifiers

struct ShowEditorView: View {
    
    @State var show: Show
    let isNew: Bool
    var onSave: ((Show) -> Void)?
    let onDismiss: () -> Void
    
    @StateObject private var showService = ShowService()
    
    @State private var seasons: [Season] = []
    @State private var episodesBySeasonId: [String: [VideoCollection]] = [:]
    @State private var expandedSeason: String?
    @State private var saving = false
    @State private var isLoading = true
    @State private var selectedEpisode: EpisodeNavItem?
    
    // Cover photo
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var isUploadingCover = false
    @State private var showingFilePicker = false
    
    struct EpisodeNavItem: Identifiable {
        let id: String
        let episode: VideoCollection
        let seasonId: String
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                showMetadataSection
                seasonsSection
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .navigationTitle(isNew ? "New Show" : "Edit Show")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await handleSave() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                        Text(saving ? "Saving..." : "Save").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(8)
                }.disabled(saving)
            }
        }
        .task {
            if !isNew { await loadFullShow() }
            isLoading = false
        }
        .fullScreenCover(item: $selectedEpisode) { item in
            EpisodeEditorView(
                showId: show.id, seasonId: item.seasonId,
                episode: item.episode, show: show,
                onDismiss: {
                    selectedEpisode = nil
                    // Force fresh data — invalidate cache and re-fetch
                    showService.clearAllCaches()
                    Task {
                        if let eps = try? await showService.getEpisodes(showId: show.id, seasonId: item.seasonId) {
                            episodesBySeasonId[item.seasonId] = eps
                            // Update show totals
                            show.totalEpisodes = episodesBySeasonId.values.flatMap { $0 }.count
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - Show Metadata
    
    private var showMetadataSection: some View {
        VStack(spacing: 12) {
            // Cover photo
            coverPhotoSection
            
            HStack(spacing: 12) {
                fieldView("Title", text: $show.title)
                fieldView("Creator", text: $show.creatorName)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.system(size: 10)).foregroundColor(.gray)
                TextField("Show description...", text: $show.description, axis: .vertical)
                    .font(.system(size: 13)).foregroundColor(.white).lineLimit(3...5)
                    .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)
            }
            HStack(spacing: 10) {
                pickerView("Category", selection: $show.genre, options: ShowGenre.allCases) { $0.displayName }
                pickerView("Status", selection: $show.status, options: ShowStatus.allCases) { $0.displayName }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags").font(.system(size: 10)).foregroundColor(.gray)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ShowTag.allCases, id: \.self) { tag in
                            Button {
                                if show.tags.contains(tag) { show.tags.removeAll { $0 == tag } }
                                else { show.tags.append(tag) }
                            } label: {
                                Text(tag.displayName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(show.tags.contains(tag) ? .white : .gray)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(show.tags.contains(tag) ? tag.color.opacity(0.8) : Color.white.opacity(0.06))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            Toggle(isOn: $show.isFeatured) {
                Text("Featured on home screen").font(.system(size: 12)).foregroundColor(.white)
            }.tint(.pink)
        }
        .padding(14).background(Color.white.opacity(0.04)).cornerRadius(12).padding(.horizontal, 16)
    }
    
    // MARK: - Seasons
    
    private var seasonsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Seasons").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { Task { await addSeason() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.system(size: 12))
                        Text("Add Season").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
                }
            }.padding(.horizontal, 16)
            
            if seasons.isEmpty {
                Text("No seasons yet. Add one to start creating episodes.")
                    .font(.system(size: 12)).foregroundColor(.gray).padding(.horizontal, 16)
            } else {
                ForEach(seasons) { season in seasonCard(season) }
            }
        }
    }
    
    private func seasonCard(_ season: Season) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSeason = expandedSeason == season.id ? nil : season.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(season.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        Text("\((episodesBySeasonId[season.id] ?? []).count) episodes")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    Button { Task { await deleteSeason(season) } } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.red.opacity(0.6))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.gray)
                        .rotationEffect(.degrees(expandedSeason == season.id ? 90 : 0))
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }.buttonStyle(.plain)
            
            if expandedSeason == season.id {
                Divider().background(Color.white.opacity(0.08))
                VStack(spacing: 6) {
                    ForEach(episodesBySeasonId[season.id] ?? []) { ep in
                        episodeRow(ep, seasonId: season.id)
                    }
                    Button { Task { await addEpisode(seasonId: season.id) } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle").font(.system(size: 10))
                            Text("Add Episode").font(.system(size: 10))
                        }.foregroundColor(.gray)
                    }.padding(.top, 4)
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .background(Color.white.opacity(0.04)).cornerRadius(12).padding(.horizontal, 16)
    }
    
    private func episodeRow(_ ep: VideoCollection, seasonId: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film").font(.system(size: 12)).foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ep \(ep.episodeNumber ?? 0): \(ep.title.isEmpty ? "Untitled" : ep.title)")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text("\(ep.segmentCount) segments").font(.system(size: 9)).foregroundColor(.gray)
            }
            Spacer()
            Button { selectedEpisode = EpisodeNavItem(id: ep.id, episode: ep, seasonId: seasonId) } label: {
                Text("Edit / Upload").font(.system(size: 10, weight: .medium)).foregroundColor(.pink)
            }
            Button { Task { await deleteEpisode(ep, seasonId: seasonId) } } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.5))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(0.04)).cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func handleSave() async {
        saving = true
        show.seasonCount = seasons.count
        show.totalEpisodes = episodesBySeasonId.values.flatMap { $0 }.count
        do { try await showService.saveShow(show); onSave?(show) }
        catch { print("❌ SHOW EDITOR: Save failed: \(error)") }
        saving = false
    }
    
    private func loadFullShow() async {
        do {
            let (loadedShow, loadedSeasons, loadedEpisodes) = try await showService.loadFullShow(show.id)
            if let s = loadedShow { show = s }
            seasons = loadedSeasons
            episodesBySeasonId = loadedEpisodes
            if let first = loadedSeasons.first { expandedSeason = first.id }
        } catch { print("❌ SHOW EDITOR: Load failed: \(error)") }
    }
    
    private func addSeason() async {
        do {
            try await showService.saveShow(show)
            let season = try await showService.addSeason(to: show.id)
            seasons.append(season)
            episodesBySeasonId[season.id] = []
            expandedSeason = season.id
        } catch { print("❌ SHOW EDITOR: Add season failed: \(error)") }
    }
    
    private func deleteSeason(_ season: Season) async {
        do {
            try await showService.deleteSeason(showId: show.id, seasonId: season.id)
            seasons.removeAll { $0.id == season.id }
            episodesBySeasonId.removeValue(forKey: season.id)
        } catch { print("❌ SHOW EDITOR: Delete season failed: \(error)") }
    }
    
    private func addEpisode(seasonId: String) async {
        do {
            let ep = try await showService.addEpisode(
                showId: show.id, seasonId: seasonId,
                creatorID: show.creatorID, creatorName: show.creatorName, format: show.format)
            episodesBySeasonId[seasonId, default: []].append(ep)
        } catch { print("❌ SHOW EDITOR: Add episode failed: \(error)") }
    }
    
    private func deleteEpisode(_ ep: VideoCollection, seasonId: String) async {
        do {
            try await showService.deleteEpisode(showId: show.id, seasonId: seasonId, episodeId: ep.id)
            episodesBySeasonId[seasonId]?.removeAll { $0.id == ep.id }
        } catch { print("❌ SHOW EDITOR: Delete episode failed: \(error)") }
    }
    
    // MARK: - Cover Photo
    
    private var coverPhotoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cover Photo").font(.system(size: 10)).foregroundColor(.gray)
            
            // Cover preview — tap to pick from Photos
            PhotosPicker(selection: $coverPickerItem, matching: .images, photoLibrary: .shared()) {
                coverPreview
            }
            .onChange(of: coverPickerItem) { _, newItem in
                Task { await handleCoverPick(newItem) }
            }
            
            // "Or import from Files" button
            Button { showingFilePicker = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("Import from Files")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.cyan.opacity(0.7))
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.image, .png, .jpeg],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
            }
        }
    }
    
    private var coverPreview: some View {
        ZStack {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let url = show.coverImageURL, !url.isEmpty, let imgURL = URL(string: url) {
                AsyncImage(url: imgURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
            
            if isUploadingCover {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.5))
                    .frame(height: 140)
                    .overlay(ProgressView().tint(.white))
            }
        }
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.04))
            .frame(height: 140)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Tap to add cover")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.4))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundColor(.gray.opacity(0.2))
            )
    }
    
    private func handleCoverPick(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }
            
            await MainActor.run { coverImage = uiImage }
            
            // Compress and upload
            isUploadingCover = true
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                isUploadingCover = false
                return
            }
            
            let path = "collections/\(show.creatorID)/\(show.id)/cover.jpg"
            let ref = Storage.storage().reference().child(path)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            let _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            
            await MainActor.run {
                show.coverImageURL = downloadURL.absoluteString
                isUploadingCover = false
            }
            print("📸 SHOW EDITOR: Cover uploaded")
        } catch {
            await MainActor.run { isUploadingCover = false }
            print("❌ SHOW EDITOR: Cover upload failed: \(error)")
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            // Start security-scoped access for Files app URLs
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            guard let uiImage = UIImage(data: data) else { return }
            
            await MainActor.run { coverImage = uiImage }
            isUploadingCover = true
            
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                isUploadingCover = false
                return
            }
            
            let path = "collections/\(show.creatorID)/\(show.id)/cover.jpg"
            let ref = Storage.storage().reference().child(path)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            let _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            
            await MainActor.run {
                show.coverImageURL = downloadURL.absoluteString
                isUploadingCover = false
            }
            print("📸 SHOW EDITOR: Cover uploaded from Files")
        } catch {
            await MainActor.run { isUploadingCover = false }
            print("❌ SHOW EDITOR: File import failed: \(error)")
        }
    }
    
    // MARK: - Reusable
    
    private func fieldView(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
            TextField("\(label)...", text: text)
                .font(.system(size: 13)).foregroundColor(.white)
                .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)
        }
    }
    
    private func pickerView<T: Hashable>(_ label: String, selection: Binding<T>, options: [T], display: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text(display($0)).tag($0) }
            }.pickerStyle(.menu).tint(.white)
            .padding(4).background(Color.white.opacity(0.06)).cornerRadius(8)
        }
    }
}
