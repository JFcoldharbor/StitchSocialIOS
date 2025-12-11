//
//  CollectionComposerView.swift
//  StitchSocial
//
//  Layer 6: Views - Collection Creation Interface
//  WITH DEBUG LOGGING
//

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// Full-screen view for creating and editing collections
struct CollectionComposerView: View {
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: CollectionComposerViewModel
    @ObservedObject var coordinator: CollectionCoordinator
    
    /// Dismiss action
    let onDismiss: () -> Void
    
    // MARK: - Local State
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @FocusState private var focusedField: ComposerField?
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Main Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Card
                        metadataCard
                        
                        // Segments Section
                        segmentsSection
                        
                        // Settings Section
                        settingsSection
                        
                        // Validation Messages
                        if !viewModel.validationErrors.isEmpty || !viewModel.validationWarnings.isEmpty {
                            validationSection
                        }
                        
                        // DEBUG: Show picker state
                        debugSection
                        
                        // Spacer for bottom padding
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
                
                // Bottom Action Bar
                VStack {
                    Spacer()
                    bottomActionBar
                }
            }
            .navigationTitle(viewModel.draftID == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    closeButton
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    saveButton
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: max(1, viewModel.maxSegments - viewModel.segments.count),
                matching: .videos
            )
            .onChange(of: showPhotoPicker) { oldValue, newValue in
                print("🎬 COMPOSER: showPhotoPicker changed from \(oldValue) to \(newValue)")
            }
            .onChange(of: selectedPhotos) { oldValue, newItems in
                print("🎬 COMPOSER: selectedPhotos changed - count: \(newItems.count)")
                handlePhotosSelection(newItems)
            }
            .alert("Discard Changes?", isPresented: $coordinator.showDiscardConfirmation) {
                Button("Discard", role: .destructive) {
                    coordinator.discardAndClose()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .alert("Delete Draft?", isPresented: $coordinator.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    coordinator.confirmDeleteDraft()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your draft and all uploaded segments.")
            }
            .alert("Publish Collection?", isPresented: $coordinator.showPublishConfirmation) {
                Button("Publish", role: .none) {
                    Task {
                        await viewModel.publish()
                        if viewModel.shouldDismiss {
                            coordinator.successMessage = "Collection published!"
                            coordinator.dismissComposer()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your collection will be visible to \(visibilityDescription). This cannot be undone.")
            }
        }
    }
    
    // MARK: - DEBUG Section
    
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG INFO")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.red)
            
            Text("showPhotoPicker: \(showPhotoPicker ? "TRUE" : "FALSE")")
                .font(.caption)
            Text("selectedPhotos count: \(selectedPhotos.count)")
                .font(.caption)
            Text("segments count: \(viewModel.segments.count)")
                .font(.caption)
            Text("canAddMore: \(viewModel.canAddMoreSegments ? "YES" : "NO")")
                .font(.caption)
            Text("draftID: \(viewModel.draftID ?? "nil")")
                .font(.caption)
            
            Divider()
            
            Text("PUBLISH STATUS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
            
            Text("canPublish: \(viewModel.canPublish ? "YES ✅" : "NO ❌")")
                .font(.caption)
                .foregroundColor(viewModel.canPublish ? .green : .red)
            Text("isTitleValid: \(viewModel.isTitleValid ? "YES" : "NO") (title: '\(viewModel.title)')")
                .font(.caption)
            Text("hasMinSegments: \(viewModel.hasMinimumSegments ? "YES" : "NO") (\(viewModel.segments.count)/\(viewModel.minSegments))")
                .font(.caption)
            Text("allUploaded: \(viewModel.allSegmentsUploaded ? "YES" : "NO")")
                .font(.caption)
            Text("uploadInProgress: \(viewModel.hasUploadInProgress ? "YES" : "NO")")
                .font(.caption)
            Text("failedCount: \(viewModel.failedSegmentCount)")
                .font(.caption)
            
            // Show each segment status
            ForEach(viewModel.segments) { segment in
                HStack {
                    Text("Seg \(segment.order + 1):")
                        .font(.caption2)
                    Text(segment.uploadStatus.rawValue)
                        .font(.caption2)
                        .foregroundColor(segment.isUploaded ? .green : .orange)
                    Text("(\(Int(segment.uploadProgress * 100))%)")
                        .font(.caption2)
                }
            }
            
            // Direct picker button for testing
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .videos
            ) {
                Text("DEBUG: Direct PhotosPicker")
                    .font(.caption)
                    .padding(8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.3))
        .cornerRadius(8)
    }
    
    // MARK: - Metadata Card
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cover Photo Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Cover Photo")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                coverPhotoSelector
            }
            
            // Title Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(viewModel.titleCharacterCount)
                        .font(.caption)
                        .foregroundColor(viewModel.title.count > viewModel.maxTitleLength ? .red : .secondary)
                }
                
                TextField("Collection title", text: $viewModel.title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
            }
            
            // Description Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(viewModel.descriptionCharacterCount)
                        .font(.caption)
                        .foregroundColor(viewModel.description.count > viewModel.maxDescriptionLength ? .red : .secondary)
                }
                
                TextField("What's this collection about?", text: $viewModel.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .description)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Cover Photo Selector
    
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var coverPhotoImage: UIImage?
    
    private var coverPhotoSelector: some View {
        HStack(spacing: 16) {
            // Cover photo preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 160)
                
                if let coverImage = coverPhotoImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let firstThumbnail = viewModel.segments.first?.thumbnailURL,
                          !firstThumbnail.isEmpty {
                    // Show first segment thumbnail as default
                    AsyncImage(url: URL(string: firstThumbnail)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Add Cover")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Play icon overlay to indicate it's a collection
                if coverPhotoImage != nil || viewModel.segments.first?.thumbnailURL != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                                .padding(8)
                        }
                    }
                    .frame(width: 120, height: 160)
                }
            }
            
            // Actions
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(
                    selection: $selectedCoverPhoto,
                    matching: .images
                ) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .onChange(of: selectedCoverPhoto) { _, newValue in
                    Task {
                        await loadCoverPhoto(from: newValue)
                    }
                }
                
                if coverPhotoImage != nil {
                    Button {
                        coverPhotoImage = nil
                        selectedCoverPhoto = nil
                        viewModel.coverImageData = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                
                Text("9:16 ratio recommended")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func loadCoverPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    self.coverPhotoImage = uiImage
                    self.viewModel.coverImageData = data
                    print("📸 COMPOSER: Cover photo loaded")
                }
            }
        } catch {
            print("❌ COMPOSER: Failed to load cover photo: \(error)")
        }
    }
    
    // MARK: - Segments Section
    
    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Segments")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.canAddMoreSegments {
                    addSegmentButton
                }
            }
            
            // Empty State or Segment List
            if viewModel.segments.isEmpty {
                emptySegmentsState
            } else {
                segmentsList
            }
            
            // Upload Progress
            if coordinator.isUploading {
                uploadProgressSection
            }
        }
    }
    
    private var emptySegmentsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No segments yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Add at least \(viewModel.minSegments) video segments to create a collection")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Use PhotosPicker directly instead of Button + .photosPicker modifier
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: max(1, viewModel.maxSegments - viewModel.segments.count),
                matching: .videos
            ) {
                Label("Add Videos", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var segmentsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                SegmentRowView(
                    segment: segment,
                    index: index,
                    onDelete: {
                        withAnimation {
                            viewModel.removeSegment(id: segment.id)
                        }
                    },
                    onRetry: {
                        coordinator.retryUpload(segmentID: segment.id)
                    },
                    onTitleChange: { newTitle in
                        viewModel.updateSegmentTitle(id: segment.id, title: newTitle)
                    }
                )
            }
            .onMove { source, destination in
                viewModel.moveSegment(from: source, to: destination)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var addSegmentButton: some View {
        // Use PhotosPicker directly
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: max(1, viewModel.maxSegments - viewModel.segments.count),
            matching: .videos
        ) {
            Label("Add", systemImage: "plus")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private var uploadProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Uploading...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(coordinator.overallUploadProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: coordinator.overallUploadProgress)
                .tint(.accentColor)
            
            Button("Cancel All") {
                coordinator.cancelAllUploads()
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            
            VStack(spacing: 0) {
                // Visibility
                HStack {
                    Image(systemName: viewModel.visibility.iconName)
                        .foregroundColor(.blue)
                        .frame(width: 28)
                    
                    Text("Visibility")
                    
                    Spacer()
                    
                    Picker("Visibility", selection: $viewModel.visibility) {
                        ForEach(CollectionVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName).tag(visibility)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding()
                
                Divider()
                    .padding(.leading, 44)
                
                // Allow Replies
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(.purple)
                        .frame(width: 28)
                    
                    Toggle("Allow Replies", isOn: $viewModel.allowReplies)
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Validation Section
    
    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.validationErrors, id: \.self) { error in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            
            ForEach(viewModel.validationWarnings, id: \.self) { warning in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text(warning)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Delete Draft Button
                if viewModel.draftID != nil {
                    Button(role: .destructive) {
                        coordinator.deleteCurrentDraft()
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                Spacer()
                
                // Publish Button
                Button {
                    print("🚀 COMPOSER: Publish button tapped")
                    print("🚀 COMPOSER: canPublish = \(viewModel.canPublish)")
                    print("🚀 COMPOSER: segments count = \(viewModel.segments.count)")
                    print("🚀 COMPOSER: title = '\(viewModel.title)'")
                    
                    viewModel.validate()
                    
                    print("🚀 COMPOSER: validation errors = \(viewModel.validationErrors)")
                    print("🚀 COMPOSER: validation warnings = \(viewModel.validationWarnings)")
                    
                    if viewModel.canPublish {
                        print("🚀 COMPOSER: Showing publish confirmation")
                        coordinator.showPublishConfirmation = true
                    } else {
                        print("🚀 COMPOSER: Cannot publish - showing error")
                        coordinator.errorMessage = viewModel.validationErrors.first ?? "Cannot publish collection"
                    }
                } label: {
                    HStack {
                        if viewModel.isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Publish")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPublish || viewModel.isPublishing)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var closeButton: some View {
        Button("Cancel") {
            coordinator.closeComposer()
        }
    }
    
    private var saveButton: some View {
        Button {
            Task {
                await viewModel.saveDraft()
            }
        } label: {
            if viewModel.isSaving {
                ProgressView()
            } else {
                Text("Save")
            }
        }
        .disabled(viewModel.isSaving)
    }
    
    // MARK: - Helpers
    
    private var visibilityDescription: String {
        switch viewModel.visibility {
        case .publicVisible:
            return "everyone"
        case .followers:
            return "your followers"
        case .privateOnly:
            return "only you"
        }
    }
    
    private func handlePhotosSelection(_ items: [PhotosPickerItem]) {
        print("🎬 COMPOSER: handlePhotosSelection called with \(items.count) items")
        print("🎬 COMPOSER: viewModel segments count: \(viewModel.segments.count)")
        print("🎬 COMPOSER: coordinator.composerViewModel is nil: \(coordinator.composerViewModel == nil)")
        
        for item in items {
            print("🎬 COMPOSER: Processing item: \(item)")
            // Pass the viewModel reference directly to ensure it's not nil
            loadVideoFromPicker(item: item, viewModel: viewModel)
        }
        selectedPhotos = []
    }
    
    /// Load video from PhotosPicker item and add to viewModel
    private func loadVideoFromPicker(item: PhotosPickerItem, viewModel: CollectionComposerViewModel) {
        Task {
            do {
                print("📹 COMPOSER: Starting to load video...")
                
                // Create temp file path
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                
                // Try loading as Movie type
                if let movie = try? await item.loadTransferable(type: Movie.self) {
                    print("📹 COMPOSER: Loaded via Movie transferable at \(movie.url)")
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: movie.url, to: tempURL)
                } else {
                    print("❌ COMPOSER: Movie transferable returned nil, trying Data...")
                    
                    // Try loading as Data
                    if let videoData = try? await item.loadTransferable(type: Data.self) {
                        print("📹 COMPOSER: Loaded via Data transferable (\(videoData.count) bytes)")
                        try videoData.write(to: tempURL)
                    } else {
                        print("❌ COMPOSER: Both Movie and Data transferable failed")
                        throw CoordinatorError.videoLoadFailed
                    }
                }
                
                // Verify file exists
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    print("❌ COMPOSER: Video file doesn't exist at \(tempURL.path)")
                    throw CoordinatorError.videoLoadFailed
                }
                
                // Get video metadata
                let asset = AVURLAsset(url: tempURL)
                let duration = try await asset.load(.duration).seconds
                
                // Get file size
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0
                
                // Generate thumbnail
                let thumbnailPath = await generateThumbnailForVideo(url: tempURL)
                
                print("📹 COMPOSER: Video loaded - duration: \(duration)s, size: \(fileSize) bytes")
                
                // Add to viewModel on main thread
                await MainActor.run {
                    viewModel.addSegment(
                        localVideoPath: tempURL.path,
                        duration: duration,
                        fileSize: fileSize,
                        thumbnailPath: thumbnailPath
                    )
                    print("✅ COMPOSER: Segment added, total segments: \(viewModel.segments.count)")
                }
                
                // Get segment ID and start upload via coordinator
                let segmentID = await MainActor.run {
                    viewModel.segments.last?.id ?? UUID().uuidString
                }
                
                let draftID = await MainActor.run {
                    viewModel.draftID
                }
                
                // Use coordinator for upload (it has Firebase access)
                // Returns URLs on success so we can mark segment as uploaded
                if let result = await coordinator.uploadSegment(
                    segmentID: segmentID,
                    localURL: tempURL,
                    thumbnailPath: thumbnailPath,
                    draftID: draftID
                ) {
                    // Mark segment as uploaded in viewModel directly
                    await MainActor.run {
                        viewModel.markSegmentUploaded(
                            id: segmentID,
                            videoURL: result.videoURL,
                            thumbnailURL: result.thumbnailURL ?? ""
                        )
                        print("✅ COMPOSER: Segment \(segmentID) marked as uploaded in viewModel")
                    }
                } else {
                    print("❌ COMPOSER: Upload failed for segment \(segmentID)")
                }
                
            } catch {
                print("❌ COMPOSER: Failed to load video: \(error)")
                await MainActor.run {
                    coordinator.errorMessage = "Failed to add video: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Generate thumbnail for video
    private func generateThumbnailForVideo(url: URL) async -> String? {
        print("🖼️ COMPOSER: Generating thumbnail for \(url.path)")
        
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        do {
            let cgImage = try await imageGenerator.image(at: time).image
            let uiImage = UIImage(cgImage: cgImage)
            
            let thumbnailURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnailURL)
                print("🖼️ COMPOSER: Thumbnail saved to \(thumbnailURL.path)")
                
                // Verify file exists
                if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    print("🖼️ COMPOSER: Thumbnail file verified at \(thumbnailURL.path)")
                    return thumbnailURL.path
                } else {
                    print("❌ COMPOSER: Thumbnail file NOT found after write!")
                }
            } else {
                print("❌ COMPOSER: Failed to create JPEG data")
            }
        } catch {
            print("⚠️ COMPOSER: Failed to generate thumbnail: \(error)")
        }
        
        return nil
    }
}

// MARK: - Focused Field

enum ComposerField: Hashable {
    case title
    case description
}

// MARK: - Segment Row View

struct SegmentRowView: View {
    let segment: SegmentDraft
    let index: Int
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onTitleChange: (String) -> Void
    
    @State private var editingTitle: String = ""
    @State private var isEditingTitle: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag Handle
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Thumbnail
            segmentThumbnail
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Title
                if isEditingTitle {
                    TextField("Segment title", text: $editingTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .onSubmit {
                            onTitleChange(editingTitle)
                            isEditingTitle = false
                        }
                } else {
                    Text(segment.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .onTapGesture {
                            editingTitle = segment.title ?? ""
                            isEditingTitle = true
                        }
                }
                
                // Duration & Size
                HStack(spacing: 8) {
                    if let duration = segment.formattedDuration {
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let size = segment.formattedFileSize {
                        Text(size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Upload Status
                uploadStatusView
            }
            
            Spacer()
            
            // Actions
            if segment.uploadStatus == .failed {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.orange)
                }
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var segmentThumbnail: some View {
        ZStack {
            if let thumbnailURL = segment.thumbnailURL, let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    thumbnailPlaceholder
                }
            } else if let localPath = segment.thumbnailLocalPath {
                if let uiImage = UIImage(contentsOfFile: localPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    thumbnailPlaceholder
                }
            } else {
                thumbnailPlaceholder
            }
            
            // Part number overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
            }
            .padding(4)
        }
        .frame(width: 60, height: 80)
        .cornerRadius(8)
        .clipped()
    }
    
    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            
            Image(systemName: "video.fill")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var uploadStatusView: some View {
        switch segment.uploadStatus {
        case .pending:
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("Pending")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            
        case .uploading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(segment.uploadProgress * 100))%")
            }
            .font(.caption2)
            .foregroundColor(.accentColor)
            
        case .processing:
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                Text("Processing")
            }
            .font(.caption2)
            .foregroundColor(.orange)
            
        case .complete:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Ready")
            }
            .font(.caption2)
            .foregroundColor(.green)
            
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(segment.uploadError ?? "Failed")
            }
            .font(.caption2)
            .foregroundColor(.red)
            
        case .cancelled:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                Text("Cancelled")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CollectionComposerView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available")
    }
}
#endif
