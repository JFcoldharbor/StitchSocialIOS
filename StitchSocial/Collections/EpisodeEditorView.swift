//
//  EpisodeEditorView.swift
//  StitchSocial
//
//  Layer 6: Views - Episode Editor (mirrors web EpisodeEditor.jsx)
//
//  CORRECTED: Finalize writes episode doc to videoCollections/{episodeId}
//  (not shows subcollection). Segments write to videos/{segmentId}.
//  This means all existing views read these episodes automatically.
//

import SwiftUI
import AVKit
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

struct EpisodeEditorView: View {
    
    let showId: String
    let seasonId: String
    let episode: VideoCollection
    let show: Show?
    let onDismiss: () -> Void
    
    @StateObject private var showService = ShowService()
    @StateObject private var videoService = VideoService()
    
    @State private var videoURL: URL?
    @State private var videoDuration: TimeInterval = 0
    @State private var player: AVPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    
    @StateObject private var engine = AutoSplitEngine(duration: 0)
    @State private var editorActive = false
    
    @State private var episodeTitle: String
    @State private var episodeDescription: String
    @State private var episodeStatus: String
    @State private var episodeIsFree: Bool
    @State private var publishIntent: PublishIntent = .draft
    @State private var suggestedSlot: Date? = nil
    
    @State private var uploadPhase: String = "idle"
    @State private var uploadProgress: Double = 0
    @State private var uploadDetail: String = ""
    
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var existingSegments: [CoreVideoMetadata] = []
    @State private var editingSegmentID: String? = nil
    @State private var editingSegmentTitle: String = ""
    @State private var previewingSegment: EditorSegment?
    @State private var showingImportSegments = false
    
    // Episode cover photo
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var episodeCoverImage: UIImage?
    @State private var isUploadingCover = false
    @State private var episodeCoverURL: String?
    @Environment(\.scenePhase) private var scenePhase
    
    init(showId: String, seasonId: String, episode: VideoCollection, show: Show?, onDismiss: @escaping () -> Void) {
        self.showId = showId
        self.seasonId = seasonId
        self.episode = episode
        self.show = show
        self.onDismiss = onDismiss
        self._episodeTitle = State(initialValue: episode.title)
        self._episodeDescription = State(initialValue: episode.description)
        self._episodeStatus = State(initialValue: episode.status.rawValue)
        self._episodeIsFree = State(initialValue: episode.isFree)
        self._publishIntent = State(initialValue: PublishIntent.from(
            status: episode.status.rawValue,
            publishedAt: episode.publishedAt
        ))
        self._episodeCoverURL = State(initialValue: episode.coverImageURL)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                metadataSection
                
                if editorActive {
                    videoPreviewSection
                    timelineSection
                    segmentListSection
                    footerSection
                } else {
                    uploadModeSelector
                    if !existingSegments.isEmpty { existingSegmentsSection }
                }
                
                if uploadPhase != "idle" { uploadProgressSection }
            }
        }
        .background(Color.black)
        .task {
            await loadExistingSegments()
            if let show = show, let config = show.scheduleConfig {
                // Pass existing episodes so ScheduleService can find the next open slot
                let allEps = [episode]   // minimal; caller can expand with season episodes
                suggestedSlot = ScheduleService.nextAvailableSlot(
                    config: config,
                    scheduledEpisodes: allEps
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                Task { await saveDraft() }
            }
        }
        .onDisappear {
            Task { await saveDraft() }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Image(systemName: "arrow.left").foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(show?.title ?? "Show")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Text("Episode \(episode.episodeNumber ?? 0): \(episodeTitle.isEmpty ? "Untitled" : episodeTitle)")
                    .font(.system(size: 18, weight: .black)).foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
    
    // MARK: - Metadata
    
    private var metadataSection: some View {
        VStack(spacing: 12) {
            // Episode cover photo
            episodeCoverSection
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title").font(.system(size: 10)).foregroundColor(.gray)
                    TextField("Episode title...", text: $episodeTitle)
                        .font(.system(size: 13)).foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)
                }
            }
            
            PremiereDatePicker(intent: $publishIntent, suggestedDate: suggestedSlot)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.system(size: 10)).foregroundColor(.gray)
                TextField("Episode description...", text: $episodeDescription, axis: .vertical)
                    .font(.system(size: 13)).foregroundColor(.white).lineLimit(2...4)
                    .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)
            }
            
            Toggle(isOn: $episodeIsFree) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Free episode").font(.system(size: 12)).foregroundColor(.white)
                    Text("Anyone can watch, no tier required").font(.system(size: 10)).foregroundColor(.gray)
                }
            }.tint(.cyan)
            
            HStack {
                Text("\(existingSegments.count) segments \u{2022} \(formatDuration(existingSegments.reduce(0) { $0 + $1.duration }))")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Button(action: { Task { await saveEpisodeMetadata() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 11))
                        Text("Save Episode").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(8)
                }
            }
        }
        .padding(14).background(Color.white.opacity(0.04)).cornerRadius(12)
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
    
    // MARK: - Upload Mode Selector
    
    private var uploadModeSelector: some View {
        VStack(spacing: 12) {
            // Option 1: Split a full video
            uploadZone
            
            // Divider
            HStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                Text("or").font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            }
            .padding(.horizontal, 16)
            
            // Option 2: Import individual segment files
            Button {
                showingImportSegments = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 24))
                        .foregroundColor(.cyan.opacity(0.7))
                    Text("Import Individual Segments")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Text("Upload pre-cut video files one at a time")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.cyan.opacity(0.3))
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .sheet(isPresented: $showingImportSegments) {
                NavigationStack {
                    ImportSegmentsView(
                        episodeId: episode.id,
                        showId: showId,
                        seasonId: seasonId,
                        creatorName: show?.creatorName ?? "",
                        episodeTitle: episodeTitle,
                        episodeNumber: episode.episodeNumber ?? 1,
                        onDismiss: {
                            showingImportSegments = false
                            Task { await loadExistingSegments() }
                        }
                    )
                }
                .preferredColorScheme(.dark)
            }
        }
    }
    
    // MARK: - Upload Zone (Split Video)
    
    private var uploadZone: some View {
        PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.up.circle").font(.system(size: 32)).foregroundColor(.gray)
                Text("Select full episode video").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                Text("MP4, MOV — opens segment editor").font(.system(size: 10)).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 36)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6])).foregroundColor(.gray.opacity(0.3)))
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .onChange(of: selectedVideoItem) { _, newItem in Task { await handleVideoPick(newItem) } }
    }
    
    // MARK: - Video Preview
    
    private var videoPreviewSection: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 220).cornerRadius(8)
                    .onAppear { setupTimeObserver() }
                    .onDisappear { removeTimeObserver() }
            } else {
                Rectangle().fill(Color.black).frame(height: 220)
                    .overlay(Text("Loading video...").foregroundColor(.gray))
            }
            if let seg = previewingSegment {
                VStack { HStack {
                    Text("Previewing: \(seg.title)")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.pink.opacity(0.8)).cornerRadius(12)
                    Spacer()
                }; Spacer() }.padding(10)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
    
    // MARK: - Timeline
    
    private var timelineSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { seekRelative(-5) } label: { Image(systemName: "gobackward.5").font(.system(size: 14)).foregroundColor(.gray) }
                Button { togglePlayback() } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)).foregroundColor(.white) }
                Button { seekRelative(5) } label: { Image(systemName: "goforward.5").font(.system(size: 14)).foregroundColor(.gray) }
                
                Text("\(EditorSegment.formatTime(currentTime)) / \(EditorSegment.formatTime(engine.duration))")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                
                HStack(spacing: 0) {
                    modeButton("Auto", icon: "wand.and.stars", mode: .auto, color: .pink)
                    modeButton("Manual", icon: "hand.draw", mode: .manual, color: .purple)
                }.background(Color.white.opacity(0.06)).cornerRadius(6)
                
                if engine.mode == .auto {
                    Picker("", selection: Binding(get: { engine.interval }, set: { engine.setInterval($0) })) {
                        ForEach(SplitInterval.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).tint(.white).font(.system(size: 10))
                }
                if engine.mode == .manual {
                    Button { engine.splitAtPlayhead(currentTime) } label: {
                        HStack(spacing: 3) { Image(systemName: "scissors").font(.system(size: 10)); Text("Split").font(.system(size: 10, weight: .semibold)) }
                            .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5).background(Color.purple).cornerRadius(6)
                    }
                }
            }.padding(.horizontal, 16)
            
            SegmentTimelineView(engine: engine, currentTime: $currentTime, onSeek: { seekTo($0) })
                .padding(.horizontal, 16)
        }.padding(.bottom, 8)
    }
    
    // MARK: - Segment List
    
    private var segmentListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(engine.segments.enumerated()), id: \.element.id) { i, seg in
                let ads = engine.adSlots.filter { $0.afterSegmentIndex == i }
                SegmentListRow(segment: seg, index: i, hasAdAfter: !ads.isEmpty,
                    onToggleLock: { engine.toggleLock(seg.id) },
                    onRename: { engine.renameSegment(seg.id, title: $0) },
                    onPreview: { previewSegment(seg) },
                    onAddAd: { engine.addAdSlot(afterSegmentIndex: i) },
                    onDelete: { engine.deleteSegment(seg.id) })
                Divider().background(Color.white.opacity(0.06))
                ForEach(ads) { ad in
                    AdSlotRow(adSlot: ad,
                        onUpdateType: { engine.updateAdSlot(ad.id, type: $0) },
                        onUpdateDuration: { engine.updateAdSlot(ad.id, duration: $0) },
                        onRemove: { engine.removeAdSlot(ad.id) })
                    Divider().background(Color.yellow.opacity(0.1))
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        HStack {
            Text("\(engine.segments.count) seg \u{2022} \(engine.adSlots.count) ads \u{2022} \(EditorSegment.formatTime(engine.duration))")
                .font(.system(size: 10)).foregroundColor(.gray)
            if engine.manualCount > 0 {
                Text("\(engine.manualCount) manual").font(.system(size: 10, weight: .medium)).foregroundColor(.pink)
            }
            Spacer()
            Button { Task { await handleFinalize() } } label: {
                HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)); Text("Finalize").font(.system(size: 12, weight: .bold)) }
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)).cornerRadius(8)
            }.disabled(uploadPhase == "uploading" || uploadPhase == "saving")
            Button { cleanupPlayer(); editorActive = false; videoURL = nil } label: {
                Text("\u{2190} Back").font(.system(size: 10)).foregroundColor(.gray)
            }.disabled(uploadPhase == "uploading")
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(Color.white.opacity(0.04))
    }
    
    // MARK: - Existing Segments
    
    private var existingSegmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segments").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            ForEach(Array(existingSegments.enumerated()), id: \.element.id) { idx, seg in
                HStack(spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    
                    // Thumbnail
                    if let url = URL(string: seg.thumbnailURL), !seg.thumbnailURL.isEmpty {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.06))
                        }
                        .frame(width: 40, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 40, height: 28)
                    }
                    
                    // Editable title or display title
                    if editingSegmentID == seg.id {
                        TextField("Name this segment", text: $editingSegmentTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .submitLabel(.done)
                            .onSubmit { saveSegmentTitle(seg) }
                    } else {
                        Text(seg.segmentTitle ?? seg.segmentDisplayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(seg.segmentTitle?.isEmpty == false ? .white : .gray.opacity(0.5))
                            .onTapGesture {
                                editingSegmentID = seg.id
                                editingSegmentTitle = seg.segmentTitle ?? ""
                            }
                    }
                    
                    Spacer()
                    
                    Text(seg.formattedDuration)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    // Save / Edit button
                    if editingSegmentID == seg.id {
                        Button {
                            saveSegmentTitle(seg)
                        } label: {
                            Text("Save")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.pink)
                        }
                    } else {
                        Button {
                            editingSegmentID = seg.id
                            editingSegmentTitle = seg.segmentTitle ?? ""
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(editingSegmentID == seg.id ? 0.08 : 0.04))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
    
    private func saveSegmentTitle(_ seg: CoreVideoMetadata) {
        let newTitle = editingSegmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let segID = seg.id
        editingSegmentID = nil
        
        // Write to Firestore subcollection
        Task {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            try? await db.collection("videoCollections").document(episode.id)
                .collection("segments").document(segID)
                .setData(["segmentTitle": newTitle, "title": newTitle,
                          "updatedAt": FieldValue.serverTimestamp()], merge: true)
            // Reload segments to reflect updated title
            await loadExistingSegments()
            print("✅ EPISODE EDITOR: Segment \(segID.prefix(8)) renamed to '\(newTitle)'")
        }
    }
    
    // MARK: - Upload Progress
    
    private var uploadProgressSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if uploadPhase == "uploading" || uploadPhase == "saving" { ProgressView().tint(.pink).scaleEffect(0.8) }
                else if uploadPhase == "done" { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                else if uploadPhase == "error" { Image(systemName: "xmark.circle.fill").foregroundColor(.red) }
                Text(uploadDetail).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(uploadPhase == "done" ? .green : uploadPhase == "error" ? .red : .pink)
            }
            if uploadPhase == "uploading" { ProgressView(value: uploadProgress, total: 100).tint(.pink) }
        }
        .padding(14).background(Color.white.opacity(0.04)).cornerRadius(10)
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
    
    // MARK: - Episode Cover Photo
    
    private var episodeCoverSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cover").font(.system(size: 10)).foregroundColor(.gray)
            
            PhotosPicker(selection: $coverPickerItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if let img = episodeCoverImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let url = episodeCoverURL, !url.isEmpty, let imgURL = URL(string: url) {
                        AsyncImage(url: imgURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                                    .frame(height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            default:
                                episodeCoverPlaceholder
                            }
                        }
                    } else {
                        episodeCoverPlaceholder
                    }
                    
                    if isUploadingCover {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.5))
                            .frame(height: 100)
                            .overlay(ProgressView().tint(.white).scaleEffect(0.7))
                    }
                }
            }
            .onChange(of: coverPickerItem) { _, newItem in
                Task { await handleEpisodeCoverPick(newItem) }
            }
        }
    }
    
    private var episodeCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.04))
            .frame(height: 100)
            .overlay(
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(.gray.opacity(0.3))
                    Text("Add cover photo")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundColor(.gray.opacity(0.15))
            )
    }
    
    private func handleEpisodeCoverPick(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            
            await MainActor.run { episodeCoverImage = uiImage }
            isUploadingCover = true
            
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                isUploadingCover = false
                return
            }
            
            let path = "collections/\(episode.creatorID)/\(episode.id)/cover.jpg"
            let ref = Storage.storage().reference().child(path)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            let _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            
            // Update episode doc with cover URL
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            try await db.collection("videoCollections").document(episode.id).setData([
                "coverImageURL": downloadURL.absoluteString,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            
            await MainActor.run {
                episodeCoverURL = downloadURL.absoluteString
                isUploadingCover = false
            }
            print("📸 EPISODE EDITOR: Cover uploaded → \(downloadURL.absoluteString.prefix(50))...")
        } catch {
            await MainActor.run { isUploadingCover = false }
            print("❌ EPISODE EDITOR: Cover upload failed: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func modeButton(_ label: String, icon: String, mode: SplitMode, color: Color) -> some View {
        Button { engine.setMode(mode) } label: {
            HStack(spacing: 3) { Image(systemName: icon).font(.system(size: 9)); Text(label).font(.system(size: 10, weight: .semibold)) }
                .foregroundColor(engine.mode == mode ? .white : .gray)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(engine.mode == mode ? color : Color.clear).cornerRadius(5)
        }
    }
    
    private func handleVideoPick(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else { return }
            let asset = AVURLAsset(url: movie.url)
            let dur = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(dur)
            print("📤 EPISODE EDITOR: Video picked — \(String(format: "%.1f", seconds))s")
            await MainActor.run {
                self.videoURL = movie.url
                self.videoDuration = seconds
                self.player = AVPlayer(url: movie.url)
                self.engine.setDuration(seconds)
                self.editorActive = true
            }
        } catch { print("❌ EPISODE EDITOR: Failed to load video: \(error)") }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
    
    private func seekTo(_ time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
    }
    
    private func seekRelative(_ delta: TimeInterval) {
        seekTo(max(0, min(currentTime + delta, engine.duration)))
    }
    
    private func previewSegment(_ seg: EditorSegment) {
        seekTo(seg.startTime); previewingSegment = seg; player?.play(); isPlaying = true
    }
    
    private func setupTimeObserver() {
        guard let player = player, timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = CMTimeGetSeconds(time)
            if let seg = self.previewingSegment, self.currentTime >= seg.endTime {
                player.pause(); self.isPlaying = false; self.previewingSegment = nil
            }
        }
    }
    
    private func removeTimeObserver() {
        if let obs = timeObserver, let p = player { p.removeTimeObserver(obs); timeObserver = nil }
    }
    
    private func cleanupPlayer() {
        removeTimeObserver(); player?.pause(); player = nil; isPlaying = false
    }
    
    private func loadExistingSegments() async {
        do { existingSegments = try await videoService.getVideosByCollection(collectionID: episode.id) }
        catch { print("❌ EPISODE EDITOR: Failed to load segments: \(error)") }
    }
    
    private func saveEpisodeMetadata() async {
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        do {
            let updated = episode.withUpdatedMetadata(title: episodeTitle, description: episodeDescription, coverImageURL: episodeCoverURL)
            try await showService.saveEpisode(showId: showId, seasonId: seasonId, episode: updated)
            var extras = publishIntent.firestoreFields()
            extras["isFree"] = episodeIsFree
            extras["updatedAt"] = FieldValue.serverTimestamp()
            try await db.collection("videoCollections").document(episode.id).setData(extras, merge: true)
        }
        catch { print("❌ EPISODE EDITOR: Save failed: \(error)") }
    }
    
    // MARK: - Auto-Save Draft (on exit, background, phone lock)
    
    private func saveDraft() async {
        // Don't overwrite a published episode with draft data
        guard uploadPhase != "done" else { return }
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        let creatorID = Auth.auth().currentUser?.uid ?? ""
        
        var draftData: [String: Any] = [
            "id": episode.id,
            "title": episodeTitle,
            "description": episodeDescription,
            "creatorID": creatorID,
            "creatorName": show?.creatorName ?? "",
            "coverImageURL": episodeCoverURL ?? "",
            "status": existingSegments.isEmpty ? "draft" : episodeStatus,
            "showId": showId,
            "seasonId": seasonId,
            "episodeNumber": episode.episodeNumber ?? 1,
            "format": "vertical",
            "contentType": episode.contentType.rawValue,
            "visibility": "public",
            "allowReplies": true,
            "isFree": episodeIsFree,
            "segmentCount": existingSegments.count,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        
        // Save segment config if editor is active
        if editorActive && !engine.segments.isEmpty {
            let segConfig = engine.segments.map { seg -> [String: Any] in
                ["startTime": seg.startTime, "endTime": seg.endTime,
                 "title": seg.title, "locked": seg.locked]
            }
            draftData["draftSegmentConfig"] = segConfig
            draftData["draftSplitMode"] = engine.mode == .auto ? "auto" : "manual"
            draftData["draftInterval"] = engine.interval.rawValue
        }
        
        do {
            try await db.collection("videoCollections").document(episode.id)
                .setData(draftData, merge: true)
            print("💾 EPISODE EDITOR: Draft saved")
        } catch {
            print("⚠️ EPISODE EDITOR: Draft save failed: \(error)")
        }
    }
    
    // MARK: - Finalize: Split Video + Upload Each Segment
    
    private func handleFinalize() async {
        guard let localVideoURL = videoURL else {
            print("❌ EPISODE EDITOR: No videoURL set")
            return
        }
        print("📤 EPISODE EDITOR: handleFinalize() started")
        
        // Protect upload from background termination
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "EpisodeFinalize") {
            print("⚠️ EPISODE EDITOR: Background time expiring, saving draft...")
            Task { await self.saveDraft() }
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
        
        let (finalSegments, finalAdSlots, totalDuration) = engine.finalizeData()
        guard !finalSegments.isEmpty else {
            print("❌ EPISODE EDITOR: No segments to finalize")
            uploadPhase = "error"
            uploadDetail = "No segments found"
            return
        }
        
        print("📤 EPISODE EDITOR: \(finalSegments.count) segments, \(String(format: "%.0f", totalDuration))s total")
        
        uploadPhase = "uploading"
        uploadProgress = 0
        uploadDetail = "Splitting video into \(finalSegments.count) segments..."
        
        let creatorID = Auth.auth().currentUser?.uid ?? ""
        let creatorName = show?.creatorName ?? ""
        let asset = AVURLAsset(url: localVideoURL)
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let batch = db.batch()
            var segmentIds: [String] = []
            var firstThumbnailURL: String?
            let totalSegs = finalSegments.count
            
            for (i, seg) in finalSegments.enumerated() {
                let segId = UUID().uuidString
                segmentIds.append(segId)
                
                // 1. Export this segment as its own file
                uploadDetail = "Splitting \(i+1)/\(totalSegs)..."
                uploadProgress = Double(i) / Double(totalSegs) * 40
                print("📤 EPISODE EDITOR: Splitting segment \(i+1) [\(String(format: "%.1f", seg.startTime))s → \(String(format: "%.1f", seg.endTime))s]")
                
                let segURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(segId).mov")
                
                // AVAssetExportPresetPassthrough — no re-encode, preserves original 4K quality
                // Use .mov output — matches iPhone source format, no container conversion needed
                guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                    print("⚠️ EPISODE EDITOR: Could not create export session for segment \(i+1)")
                    continue
                }
                
                let startCMTime = CMTime(seconds: seg.startTime, preferredTimescale: 600)
                let endCMTime = CMTime(seconds: seg.endTime, preferredTimescale: 600)
                exportSession.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
                exportSession.outputURL = segURL
                exportSession.outputFileType = .mov
                exportSession.shouldOptimizeForNetworkUse = true
                
                // Export segment — use async/await version, no polling loop
                // exportAsynchronously + Task.sleep was causing CancellationError
                // when the Task was interrupted between polls
                await exportSession.export()
                
                guard exportSession.status == .completed else {
                    print("⚠️ EPISODE EDITOR: Split failed for segment \(i+1): \(exportSession.error?.localizedDescription ?? "unknown")")
                    continue
                }
                
                print("📤 EPISODE EDITOR: Segment \(i+1) split ✅")
                
                // 2. Generate thumbnail for this segment
                let thumbURL = await generateSegmentThumbnail(from: segURL, segId: segId)
                if i == 0 { firstThumbnailURL = thumbURL }
                
                // 3. Upload this segment file
                uploadDetail = "Uploading \(i+1)/\(totalSegs)..."
                let uploadPctBase = 40.0 + (Double(i) / Double(totalSegs) * 50.0)  // 40-90%
                let videoDownloadURL = try await uploadFileWithProgress(
                    from: segURL,
                    to: "videoCollections/\(episode.id)/segments/\(segId).mov",
                    type: "video/quicktime",
                    progressBase: uploadPctBase,
                    progressRange: 50.0 / Double(totalSegs)
                )
                
                // 4. Upload thumbnail
                var thumbnailDownloadURL = ""
                if let thumbURL = thumbURL {
                    thumbnailDownloadURL = (try? await uploadSimple(from: URL(fileURLWithPath: thumbURL), to: "videoCollections/\(episode.id)/thumbnails/\(segId).jpg", type: "image/jpeg")) ?? ""
                }
                
                // 5. Get file size
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: segURL.path)[.size] as? Int) ?? 0
                
                // 6. Create segment Firestore doc
                let segData: [String: Any] = [
                    "id": segId, "title": seg.title, "description": "",
                    "videoURL": videoDownloadURL, "thumbnailURL": thumbnailDownloadURL,
                    "creatorID": creatorID, "creatorName": creatorName,
                    "createdAt": Timestamp(), "threadID": segId,
                    "replyToVideoID": NSNull(), "conversationDepth": 0,
                    "viewCount": 0, "hypeCount": 0, "coolCount": 0,
                    "replyCount": 0, "shareCount": 0, "tipCount": 0,
                    "temperature": "neutral", "qualityScore": 50,
                    "engagementRatio": 0.5, "velocityScore": 0.0, "trendingScore": 0.0,
                    "duration": seg.duration, "aspectRatio": 9.0 / 16.0, "fileSize": fileSize,
                    "discoverabilityScore": 0.5, "isPromoted": false,
                    "lastEngagementAt": NSNull(),
                    "collectionID": episode.id,
                    "segmentNumber": i + 1,
                    "segmentTitle": seg.title,
                    "isCollectionSegment": true,
                    "uploadStatus": "complete",
                    "isManualCut": seg.locked,
                    "recordingSource": "cameraRoll",
                    "hashtags": [] as [String],
                ]
                // Subcollection: videoCollections/{episodeId}/segments/{segId}
                batch.setData(segData, forDocument: db.collection("videoCollections").document(episode.id).collection("segments").document(segId))
                
                await MainActor.run { /* mark progress */ }
                print("📤 EPISODE EDITOR: Segment \(i+1) uploaded ✅")
                
                // Cleanup temp file
                try? FileManager.default.removeItem(at: segURL)
            }
            
            // 7. Episode doc
            uploadProgress = 92
            uploadDetail = "Saving episode..."
            
            let adSlotData = finalAdSlots.map { slot -> [String: Any] in
                ["afterSegmentIndex": slot.afterSegmentIndex,
                 "insertAfterTime": slot.insertAfterTime ?? 0,
                 "type": slot.type,
                 "durationSeconds": slot.durationSeconds]
            }
            
            batch.setData([
                "id": episode.id,
                "title": episodeTitle,
                "description": episodeDescription,
                "creatorID": creatorID,
                "creatorName": creatorName,
                "coverImageURL": firstThumbnailURL ?? episodeCoverURL ?? "",
                "segmentIDs": segmentIds,
                "segmentCount": finalSegments.count,
                "totalDuration": totalDuration,
                "status": publishIntent.statusString,
                "visibility": "public",
                "allowReplies": true,
                "isFree": episodeIsFree,
                "contentType": episode.contentType.rawValue,
                "showId": showId,
                "seasonId": seasonId,
                "episodeNumber": episode.episodeNumber ?? 1,
                "format": "vertical",
                "adSlots": adSlotData,
                "totalViews": 0, "totalHypes": 0, "totalCools": 0,
                "totalReplies": 0, "totalShares": 0,
                "createdAt": Timestamp(date: episode.createdAt),
                "updatedAt": FieldValue.serverTimestamp(),
                "publishedAt": publishIntent.publishedAt.map { Timestamp(date: $0) } ?? (FieldValue.serverTimestamp() as Any),
            ] as [String: Any], forDocument: db.collection("videoCollections").document(episode.id), merge: true)
            
            print("📤 EPISODE EDITOR: Committing batch...")
            try await batch.commit()
            print("📤 EPISODE EDITOR: Done! ✅")
            
            uploadPhase = "done"
            uploadProgress = 100
            uploadDetail = "\(finalSegments.count) segments created!"
            await loadExistingSegments()
            
            // Fire-and-forget notification to followers + subscribers
            let epTitle = episodeTitle
            let epID = episode.id
            let epNum = episode.episodeNumber
            let free = episodeIsFree
            let showT = show?.title ?? ""
            let creatorName = show?.creatorName ?? ""
            Task {
                try? await NotificationService().sendNewEpisodeNotification(
                    creatorID: Auth.auth().currentUser?.uid ?? "",
                    creatorUsername: creatorName,
                    showTitle: showT,
                    episodeTitle: epTitle,
                    episodeID: epID,
                    showID: showId,
                    episodeNumber: epNum,
                    isFree: free
                )
            }
            
            try? await Task.sleep(for: .seconds(1.5))
            editorActive = false
            videoURL = nil
            uploadPhase = "idle"
            cleanupPlayer()
            
        } catch {
            uploadPhase = "error"
            uploadDetail = "Failed: \(error.localizedDescription)"
            print("❌ EPISODE EDITOR: Finalize failed: \(error)")
        }
    }
    
    // MARK: - Generate Segment Thumbnail
    
    private func generateSegmentThumbnail(from url: URL, segId: String) async -> String? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        do {
            let img = try await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let thumbPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(segId)_thumb.jpg")
            if let data = UIImage(cgImage: img).jpegData(compressionQuality: 0.7) {
                try data.write(to: thumbPath)
                return thumbPath.path
            }
        } catch { print("⚠️ EPISODE EDITOR: Thumbnail failed for \(segId): \(error)") }
        return nil
    }
    
    // MARK: - Upload with Progress (for video files)
    
    private func uploadFileWithProgress(from localURL: URL, to path: String, type: String, progressBase: Double, progressRange: Double) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let meta = StorageMetadata()
        meta.contentType = type
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = ref.putFile(from: localURL, metadata: meta) { _, error in
                if let error = error {
                    print("❌ UPLOAD: Failed \(path): \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                ref.downloadURL { url, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else if let url = url { continuation.resume(returning: url.absoluteString) }
                    else { continuation.resume(throwing: NSError(domain: "Upload", code: -1)) }
                }
            }
            task.observe(.progress) { snapshot in
                guard let p = snapshot.progress else { return }
                let pct = Double(p.completedUnitCount) / Double(max(p.totalUnitCount, 1))
                Task { @MainActor in
                    self.uploadProgress = progressBase + (pct * progressRange)
                    let mb = Double(p.completedUnitCount) / 1024 / 1024
                    let totalMB = Double(p.totalUnitCount) / 1024 / 1024
                    self.uploadDetail = "Uploading — \(String(format: "%.1f", mb))/\(String(format: "%.1f", totalMB))MB"
                }
            }
        }
    }
    
    // MARK: - Simple Upload (thumbnails, small files)
    
    private func uploadSimple(from localURL: URL, to path: String, type: String) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let meta = StorageMetadata()
        meta.contentType = type
        let _ = try await ref.putFileAsync(from: localURL, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }
    

    private func formatDuration(_ seconds: TimeInterval) -> String {
        EditorSegment.formatTime(seconds)
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
