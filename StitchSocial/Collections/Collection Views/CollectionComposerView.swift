//
//  CollectionComposerView.swift
//  StitchSocial
//
//  Layer 6: Views - Collection Creation Interface
//  REDESIGNED: Horizontal film strip + segment detail sheet
//  Features: Per-segment titles, tap-to-edit, reorder, inline preview
//

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Composer Field Focus

enum ComposerField: Hashable {
    case title
    case description
    case segmentTitle(String) // segment ID
}

// MARK: - Collection Composer View

struct CollectionComposerView: View {
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: CollectionComposerViewModel
    @ObservedObject var coordinator: CollectionCoordinator
    let onDismiss: () -> Void
    
    // MARK: - Local State
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedSegment: SegmentDraft?
    @State private var showSegmentDetail = false
    @State private var showPublishSuccess = false
    @State private var showFileImporter = false
    @FocusState private var focusedField: ComposerField?
    
    // Cover photo
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var coverPhotoImage: UIImage?
    
    var body: some View {
        navigationWrapper
    }
    
    // MARK: - Navigation Wrapper (split for type checker)
    
    private var navigationWrapper: some View {
        NavigationStack {
            decoratedContent
        }
    }
    
    private var decoratedContent: some View {
        mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSegmentDetail) { segmentSheet }
            .modifier(ComposerEventHandlers(
                selectedPhotos: $selectedPhotos,
                selectedCoverPhoto: $selectedCoverPhoto,
                showPublishConfirmation: $coordinator.showPublishConfirmation,
                showFileImporter: $showFileImporter,
                viewModel: viewModel,
                coordinator: coordinator,
                handlePhotosSelection: handlePhotosSelection,
                loadCoverPhoto: loadCoverPhoto,
                handleFileImport: handleFileImport
            ))
    }
    
    // MARK: - Main Content (extracted for type checker)
    
    private var mainContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.06, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    scrollContent
                }
                bottomBar
            }
        }
    }
    
    private var scrollContent: some View {
        VStack(spacing: 24) {
            headerSection
                .padding(.top, 8)
            
            filmStripSection
            
            settingsCard
            
            if !viewModel.validationErrors.isEmpty {
                validationBanner
            }
            
            Spacer(minLength: 100)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
                coordinator.closeComposer()
            }
            .foregroundColor(.gray)
        }
        ToolbarItem(placement: .principal) {
            Text(viewModel.isEditingExisting ? "Edit Collection" : "New Collection")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await viewModel.saveDraft() }
            } label: {
                Text(viewModel.isSaving ? "Saving..." : "Save")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.cyan)
            }
            .disabled(viewModel.isSaving)
        }
    }
    
    // MARK: - Segment Sheet
    
    @ViewBuilder
    private var segmentSheet: some View {
        if let segment = selectedSegment {
            SegmentDetailSheet(
                segment: segment,
                segmentIndex: viewModel.segments.firstIndex(where: { $0.id == segment.id }) ?? 0,
                totalSegments: viewModel.segments.count,
                onTitleChange: { newTitle in
                    viewModel.updateSegmentTitle(id: segment.id, title: newTitle)
                },
                onDelete: {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.removeSegment(id: segment.id)
                    }
                    showSegmentDetail = false
                },
                onRetry: {
                    coordinator.retryUpload(segmentID: segment.id)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(red: 0.1, green: 0.08, blue: 0.16))
        }
    }
    
    // MARK: - Header Section (Cover + Title + Description)
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Cover photo
            coverPhotoView
            
            // Title + Description
            VStack(alignment: .leading, spacing: 12) {
                // Title
                TextField("Collection title", text: $viewModel.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .title)
                    .tint(.cyan)
                
                // Description
                TextField("What's this about?", text: $viewModel.description, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .description)
                    .tint(.cyan)
                
                // Stats row
                HStack(spacing: 12) {
                    Label("\(viewModel.segments.count) segments", systemImage: "film.stack")
                    
                    if viewModel.totalDuration > 0 {
                        Label(formatDuration(viewModel.totalDuration), systemImage: "clock")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Cover Photo
    
    private var coverPhotoView: some View {
        PhotosPicker(selection: $selectedCoverPhoto, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 100, height: 140)
                
                if let coverImage = coverPhotoImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let thumb = viewModel.segments.first?.thumbnailURL,
                          !thumb.isEmpty, let url = URL(string: thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        coverPlaceholder
                    }
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    coverPlaceholder
                }
                
                // Edit badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, .cyan.opacity(0.8))
                            .padding(6)
                    }
                }
                .frame(width: 100, height: 140)
            }
        }
    }
    
    private var coverPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(.gray)
            Text("Cover")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(width: 100, height: 140)
    }
    
    // MARK: - Film Strip Section
    
    private var filmStripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Segments")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if viewModel.canAddMoreSegments {
                    HStack(spacing: 8) {
                        // Files import
                        Button {
                            showFileImporter = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Files")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        
                        // Gallery import
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: max(1, viewModel.maxSegments - viewModel.segments.count),
                            matching: .videos
                        ) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Gallery")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            
            // Upload progress bar (when active)
            if coordinator.isUploading {
                HStack(spacing: 8) {
                    ProgressView(value: coordinator.overallUploadProgress)
                        .tint(.cyan)
                    Text("\(Int(coordinator.overallUploadProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                        .frame(width: 36)
                }
                .padding(.horizontal, 4)
            }
            
            if viewModel.segments.isEmpty {
                // Empty state
                emptyFilmStrip
            } else {
                // Horizontal scrolling film strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                            FilmStripCard(
                                segment: segment,
                                index: index,
                                isSelected: selectedSegment?.id == segment.id,
                                onTap: {
                                    selectedSegment = segment
                                    showSegmentDetail = true
                                },
                                onTitleChange: { newTitle in
                                    viewModel.updateSegmentTitle(id: segment.id, title: newTitle)
                                }
                            )
                        }
                        
                        // Add more card
                        if viewModel.canAddMoreSegments {
                            addSegmentCard
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Empty Film Strip
    
    private var emptyFilmStrip: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: viewModel.maxSegments,
            matching: .videos
        ) {
            VStack(spacing: 14) {
                Image(systemName: "film.stack")
                    .font(.system(size: 36))
                    .foregroundColor(.gray.opacity(0.5))
                
                Text("Add video segments")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("Min \(viewModel.minSegments) segments to publish")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .foregroundColor(.gray.opacity(0.3))
            )
        }
    }
    
    // MARK: - Add Segment Card (in strip)
    
    private var addSegmentCard: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: max(1, viewModel.maxSegments - viewModel.segments.count),
            matching: .videos
        ) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.gray.opacity(0.4))
                        .frame(width: 100, height: 140)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Text("Add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(width: 100)
            }
        }
    }
    
    // MARK: - Settings Card
    
    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Visibility
            settingsRow(
                icon: "globe",
                iconColor: .blue,
                title: "Visibility"
            ) {
                Picker("", selection: $viewModel.visibility) {
                    ForEach(CollectionVisibility.allCases, id: \.self) { vis in
                        Text(vis.displayName).tag(vis)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }
            
            settingsDivider
            
            // Content Type
            settingsRow(
                icon: "tag",
                iconColor: .purple,
                title: "Type"
            ) {
                Picker("", selection: $viewModel.contentType) {
                    ForEach(CollectionContentType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white.opacity(0.7))
            }
            
            settingsDivider
            
            // Allow Replies
            settingsRow(
                icon: "bubble.left.and.bubble.right",
                iconColor: .green,
                title: "Allow Replies"
            ) {
                Toggle("", isOn: $viewModel.allowReplies)
                    .tint(.cyan)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func settingsRow<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.white)
            
            Spacer()
            
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var settingsDivider: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 52)
    }
    
    // MARK: - Validation Banner
    
    private var validationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.validationErrors, id: \.self) { error in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.9))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Delete draft
            if viewModel.isEditingExisting {
                Button(role: .destructive) {
                    coordinator.deleteCurrentDraft()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            Spacer()
            
            // Publish
            Button {
                viewModel.validate()
                if viewModel.canPublish {
                    coordinator.showPublishConfirmation = true
                } else {
                    coordinator.errorMessage = viewModel.validationErrors.first ?? "Cannot publish"
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPublishing {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                    }
                    Text("Publish")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    viewModel.canPublish
                        ? LinearGradient(colors: [.cyan, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
            }
            .disabled(!viewModel.canPublish || viewModel.isPublishing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.95)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    // MARK: - Helpers
    
    private func loadCoverPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                coverPhotoImage = image
                viewModel.coverImageData = data
            }
        } catch {
            print("❌ COMPOSER: Cover photo load failed: \(error)")
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Video Import (Sequential — first to last)
    
    /// Process photo picker items one at a time in order.
    /// Ensures draft exists first, then loads → adds → uploads each sequentially.
    func handlePhotosSelection(_ items: [PhotosPickerItem]) {
        let capturedItems = items
        selectedPhotos = []
        
        Task {
            // Ensure draft exists before any uploads
            guard let draftID = await viewModel.ensureDraftExists() else {
                await MainActor.run {
                    coordinator.errorMessage = "Failed to create draft for uploads"
                }
                return
            }
            
            for (index, item) in capturedItems.enumerated() {
                print("📤 COMPOSER: Processing video \(index + 1)/\(capturedItems.count)")
                await loadAndUploadPickerItem(item, draftID: draftID)
            }
            
            print("✅ COMPOSER: All \(capturedItems.count) videos processed sequentially")
        }
    }
    
    /// Load a single picker item, add to model, upload, wait for completion.
    private func loadAndUploadPickerItem(_ item: PhotosPickerItem, draftID: String) async {
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            if let movie = try? await item.loadTransferable(type: Movie.self) {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: movie.url, to: tempURL)
            } else if let videoData = try? await item.loadTransferable(type: Data.self) {
                try videoData.write(to: tempURL)
            } else {
                print("❌ COMPOSER: Failed to load video from picker")
                return
            }
            
            await processAndUploadVideo(at: tempURL, draftID: draftID)
        } catch {
            print("❌ COMPOSER: Picker item load failed: \(error)")
            await MainActor.run {
                coordinator.errorMessage = "Failed to add video: \(error.localizedDescription)"
            }
        }
    }
    
    /// Process file importer results sequentially.
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                guard let draftID = await viewModel.ensureDraftExists() else {
                    await MainActor.run {
                        coordinator.errorMessage = "Failed to create draft for uploads"
                    }
                    return
                }
                
                for (index, url) in urls.enumerated() {
                    guard url.startAccessingSecurityScopedResource() else {
                        print("❌ COMPOSER: Cannot access file: \(url.lastPathComponent)")
                        continue
                    }
                    
                    print("📤 COMPOSER: Importing file \(index + 1)/\(urls.count)")
                    
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        await processAndUploadVideo(at: tempURL, draftID: draftID)
                    } catch {
                        print("❌ COMPOSER: File import failed: \(error)")
                        await MainActor.run {
                            coordinator.errorMessage = "Failed to import: \(error.localizedDescription)"
                        }
                    }
                    
                    url.stopAccessingSecurityScopedResource()
                }
            }
        case .failure(let error):
            coordinator.errorMessage = "File picker error: \(error.localizedDescription)"
        }
    }
    
    /// Core sequential pipeline: extract metadata → add segment → upload → wait → mark complete.
    private func processAndUploadVideo(at tempURL: URL, draftID: String) async {
        do {
            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                print("❌ COMPOSER: Video file missing at \(tempURL.path)")
                return
            }
            
            // 1. Extract metadata
            let asset = AVURLAsset(url: tempURL)
            let duration = try await asset.load(.duration).seconds
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            let thumbnailPath = await generateThumbnail(for: tempURL)
            
            // 2. Add segment — capture exact ID (no race on .last)
            let segmentID: String? = await MainActor.run {
                viewModel.addSegment(
                    localVideoPath: tempURL.path,
                    duration: duration,
                    fileSize: fileSize,
                    thumbnailPath: thumbnailPath
                )
            }
            
            guard let segmentID = segmentID else {
                print("❌ COMPOSER: Failed to add segment (max reached?)")
                return
            }
            
            // 3. Upload and WAIT for completion (sequential)
            if let result = await coordinator.uploadSegment(
                segmentID: segmentID,
                localURL: tempURL,
                thumbnailPath: thumbnailPath,
                draftID: draftID
            ) {
                await MainActor.run {
                    viewModel.markSegmentUploaded(
                        id: segmentID,
                        videoURL: result.videoURL,
                        thumbnailURL: result.thumbnailURL ?? ""
                    )
                }
                print("✅ COMPOSER: Segment \(segmentID) uploaded")
            } else {
                await MainActor.run {
                    viewModel.markSegmentFailed(id: segmentID, error: "Upload failed or timed out")
                }
                print("❌ COMPOSER: Segment \(segmentID) upload failed")
            }
        } catch {
            print("❌ COMPOSER: processAndUploadVideo failed: \(error)")
        }
    }
    
    private func generateThumbnail(for url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        do {
            let cgImage = try await generator.image(at: time).image
            let thumbnailURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            
            if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnailURL)
                return thumbnailURL.path
            }
        } catch {
            print("⚠️ COMPOSER: Thumbnail generation failed: \(error)")
        }
        return nil
    }
}

// MARK: - Film Strip Card

struct FilmStripCard: View {
    let segment: SegmentDraft
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onTitleChange: (String) -> Void
    
    @State private var editingTitle: String = ""
    @State private var isEditingTitle = false
    @FocusState private var titleFocused: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail
            ZStack {
                // Thumbnail image
                thumbnailView
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Part number badge
                VStack {
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            .padding(4)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(width: 100, height: 140)
                
                // Duration badge
                if let duration = segment.formattedDuration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(duration)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                    .frame(width: 100, height: 140)
                }
                
                // Upload status overlay
                statusOverlay
                
                // Selection ring
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cyan, lineWidth: 2)
                        .frame(width: 100, height: 140)
                }
            }
            .onTapGesture { onTap() }
            
            // Editable title
            if isEditingTitle {
                TextField("Title", text: $editingTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .focused($titleFocused)
                    .onSubmit {
                        onTitleChange(editingTitle)
                        isEditingTitle = false
                    }
                    .tint(.cyan)
            } else {
                Text(segment.title ?? "Part \(index + 1)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: 100)
                    .onTapGesture {
                        editingTitle = segment.title ?? ""
                        isEditingTitle = true
                        titleFocused = true
                    }
            }
        }
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let url = segment.thumbnailURL, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                thumbnailPlaceholder
            }
        } else if let path = segment.thumbnailLocalPath, let img = UIImage(contentsOfFile: path) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            thumbnailPlaceholder
        }
    }
    
    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: "video.fill")
                .font(.system(size: 20))
                .foregroundColor(.gray.opacity(0.4))
        }
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        switch segment.uploadStatus {
        case .uploading:
            ZStack {
                Color.black.opacity(0.5)
                VStack(spacing: 4) {
                    ProgressView()
                        .tint(.cyan)
                        .scaleEffect(0.8)
                    Text("\(Int(segment.uploadProgress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 100, height: 140)
            
        case .failed:
            ZStack {
                Color.red.opacity(0.3)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 100, height: 140)
            
        case .pending:
            ZStack {
                Color.black.opacity(0.4)
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 100, height: 140)
            
        case .complete:
            // Small checkmark badge
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .background(Color.black.opacity(0.5).clipShape(Circle()))
                        .padding(4)
                }
                Spacer()
            }
            .frame(width: 100, height: 140)
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Segment Detail Sheet

struct SegmentDetailSheet: View {
    let segment: SegmentDraft
    let segmentIndex: Int
    let totalSegments: Int
    let onTitleChange: (String) -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    
    @State private var title: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Part \(segmentIndex + 1) of \(totalSegments)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.cyan)
                
                Spacer()
                
                Button("Done") {
                    onTitleChange(title)
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.cyan)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider().background(Color.white.opacity(0.08))
            
            ScrollView {
                VStack(spacing: 20) {
                    // Thumbnail preview (large)
                    thumbnailPreview
                    
                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Segment Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.gray)
                        
                        TextField("Part \(segmentIndex + 1)", text: $title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .tint(.cyan)
                    }
                    .padding(.horizontal, 20)
                    
                    // Info row
                    HStack(spacing: 20) {
                        infoChip(icon: "clock", label: segment.formattedDuration ?? "--:--")
                        infoChip(icon: "doc", label: segment.formattedFileSize ?? "-- MB")
                        infoChip(icon: statusIcon, label: statusLabel)
                    }
                    .padding(.horizontal, 20)
                    
                    // Actions
                    VStack(spacing: 10) {
                        if segment.uploadStatus == .failed {
                            Button {
                                onRetry()
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry Upload")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                        
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove Segment")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }
        }
        .onAppear {
            title = segment.title ?? ""
        }
    }
    
    private var thumbnailPreview: some View {
        ZStack {
            if let url = segment.thumbnailURL, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.06)
                }
            } else if let path = segment.thumbnailLocalPath, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.06)
                Image(systemName: "video.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
    
    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.gray)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        switch segment.uploadStatus {
        case .complete: return "checkmark.circle"
        case .uploading: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle"
        case .pending: return "clock"
        default: return "circle"
        }
    }
    
    private var statusLabel: String {
        segment.uploadStatus.displayName
    }
}

// MARK: - Event Handlers Modifier (isolates onChange + confirmationDialog for type checker)

struct ComposerEventHandlers: ViewModifier {
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var selectedCoverPhoto: PhotosPickerItem?
    @Binding var showPublishConfirmation: Bool
    @Binding var showFileImporter: Bool
    let viewModel: CollectionComposerViewModel
    let coordinator: CollectionCoordinator
    let handlePhotosSelection: ([PhotosPickerItem]) -> Void
    let loadCoverPhoto: (PhotosPickerItem?) async -> Void
    let handleFileImport: (Result<[URL], Error>) -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: selectedPhotos) { _, newItems in
                guard !newItems.isEmpty else { return }
                handlePhotosSelection(newItems)
            }
            .onChange(of: selectedCoverPhoto) { _, newValue in
                Task { await loadCoverPhoto(newValue) }
            }
            .confirmationDialog(
                "Publish Collection",
                isPresented: $showPublishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Publish") {
                    Task { await coordinator.confirmPublish() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Publish \"\(viewModel.title)\" with \(viewModel.segments.count) segments?")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
    }
}

// MARK: - Preview

#if DEBUG
struct CollectionComposerView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview requires ViewModel + Coordinator")
            .preferredColorScheme(.dark)
    }
}
#endif
