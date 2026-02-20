//
//  CollectionComposerViewModel.swift
//  StitchSocial
//
//  Layer 3: ViewModels - Collection Creation Workflow
//  Dependencies: CollectionService, VideoService, CollectionDraft, SegmentDraft
//  Features: Draft management, segment ordering, upload tracking, validation, publishing
//  CREATED: Phase 3 - Collections feature ViewModels
//

import Foundation
import SwiftUI
import Combine
import PhotosUI

/// ViewModel for the collection creation/editing workflow
/// Manages draft state, segment uploads, reordering, validation, and publishing
@MainActor
class CollectionComposerViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let collectionService: CollectionService
    private let videoService: VideoService
    private let userID: String
    private let username: String
    
    // MARK: - Published State - Draft
    
    /// Current draft being edited
    @Published private(set) var draft: CollectionDraft?
    
    /// Draft ID for tracking
    @Published private(set) var draftID: String?
    
    // MARK: - Published State - Form Fields
    
    /// Collection title
    @Published var title: String = ""
    
    /// Collection description
    @Published var description: String = ""
    
    /// Cover image data (selected by user)
    @Published var coverImageData: Data?
    
    /// Selected visibility setting
    @Published var visibility: CollectionVisibility = .publicVisible
    
    /// Whether replies are allowed
    @Published var allowReplies: Bool = true
    
    /// Content type (standard, podcast, shortFilm, etc.)
    @Published var contentType: CollectionContentType = .standard
    
    /// Segments in order
    @Published var segments: [SegmentDraft] = []
    
    /// Whether editing an existing draft (vs creating new)
    var isEditingExisting: Bool { existingDraftID != nil }
    
    /// Existing draft ID if editing
    private var existingDraftID: String?
    
    // MARK: - Published State - UI State
    
    /// Overall loading state
    @Published private(set) var isLoading: Bool = false
    
    /// Whether currently saving draft
    @Published private(set) var isSaving: Bool = false
    
    /// Whether currently publishing
    @Published private(set) var isPublishing: Bool = false
    
    /// Current error message
    @Published var errorMessage: String?
    
    /// Success message for toasts
    @Published var successMessage: String?
    
    /// Whether to show discard confirmation
    @Published var showDiscardConfirmation: Bool = false
    
    /// Whether to show publish confirmation
    @Published var showPublishConfirmation: Bool = false
    
    /// Whether composer should dismiss
    @Published var shouldDismiss: Bool = false
    
    /// Currently selected segment for editing
    @Published var selectedSegmentID: String?
    
    /// Whether segment picker is showing
    @Published var showSegmentPicker: Bool = false
    
    // MARK: - Published State - Validation
    
    /// Validation errors for display
    @Published private(set) var validationErrors: [String] = []
    
    /// Validation warnings (non-blocking)
    @Published private(set) var validationWarnings: [String] = []
    
    // MARK: - Configuration
    
    let maxSegments: Int = 20
    let minSegments: Int = 2
    let maxTitleLength: Int = 100
    let maxDescriptionLength: Int = 500
    
    // MARK: - Private State
    
    private var autoSaveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        userID: String,
        username: String,
        collectionService: CollectionService,
        videoService: VideoService
    ) {
        self.userID = userID
        self.username = username
        self.collectionService = collectionService
        self.videoService = videoService
        
        setupAutoSave()
        
        print("📝 COMPOSER VM: Initialized for user \(userID)")
    }
    
    /// Convenience initializer with default services
    convenience init(
        userID: String,
        username: String
    ) {
        self.init(
            userID: userID,
            username: username,
            collectionService: CollectionService(),
            videoService: VideoService()
        )
    }
    
    /// Initialize with existing draft
    convenience init(
        draft: CollectionDraft,
        username: String,
        collectionService: CollectionService,
        videoService: VideoService
    ) {
        self.init(
            userID: draft.creatorID,
            username: username,
            collectionService: collectionService,
            videoService: videoService
        )
        
        loadFromDraft(draft)
    }
    
    /// Initialize with existing draft using default services
    convenience init(
        draft: CollectionDraft,
        username: String
    ) {
        self.init(
            draft: draft,
            username: username,
            collectionService: CollectionService(),
            videoService: VideoService()
        )
    }
    
    deinit {
        autoSaveTask?.cancel()
    }
    
    // MARK: - Computed Properties - Display
    
    /// Title character count display
    var titleCharacterCount: String {
        "\(title.count)/\(maxTitleLength)"
    }
    
    /// Description character count display
    var descriptionCharacterCount: String {
        "\(description.count)/\(maxDescriptionLength)"
    }
    
    /// Segment count display
    var segmentCountText: String {
        "\(segments.count)/\(maxSegments) segments"
    }
    
    /// Whether more segments can be added
    var canAddMoreSegments: Bool {
        segments.count < maxSegments
    }
    
    /// Total duration of all segments
    var totalDuration: TimeInterval {
        segments.compactMap { $0.duration }.reduce(0, +)
    }
    
    /// Formatted total duration
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Total file size of all segments
    var totalFileSize: Int64 {
        segments.compactMap { $0.fileSize }.reduce(0, +)
    }
    
    /// Formatted total file size
    var formattedTotalFileSize: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
    
    /// Number of segments uploaded
    var uploadedSegmentCount: Int {
        segments.filter { $0.isUploaded }.count
    }
    
    /// Number of segments currently uploading
    var uploadingSegmentCount: Int {
        segments.filter { $0.uploadStatus == .uploading || $0.uploadStatus == .processing }.count
    }
    
    /// Number of failed uploads
    var failedSegmentCount: Int {
        segments.filter { $0.uploadStatus == .failed }.count
    }
    
    /// Overall upload progress (0.0 to 1.0)
    var overallUploadProgress: Double {
        guard !segments.isEmpty else { return 0.0 }
        let totalProgress = segments.reduce(0.0) { $0 + $1.uploadProgress }
        return totalProgress / Double(segments.count)
    }
    
    /// Progress text for display
    var uploadProgressText: String {
        "\(uploadedSegmentCount)/\(segments.count) uploaded"
    }
    
    /// Whether all segments are uploaded
    var allSegmentsUploaded: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.isUploaded }
    }
    
    /// Whether a cover image has been selected
    var hasCoverImage: Bool {
        coverImageData != nil
    }
    
    /// Whether any upload is in progress
    var hasUploadInProgress: Bool {
        uploadingSegmentCount > 0
    }
    
    /// Whether draft has unsaved changes
    var hasUnsavedChanges: Bool {
        guard let draft = draft else {
            // No draft yet - has changes if any content entered
            return !title.isEmpty || !description.isEmpty || !segments.isEmpty
        }
        
        // Compare with saved draft
        return title != (draft.title ?? "") ||
               description != (draft.description ?? "") ||
               visibility != draft.visibility ||
               allowReplies != draft.allowReplies ||
               segments.count != draft.segments.count
    }
    
    // MARK: - Computed Properties - Validation
    
    /// Whether title is valid
    var isTitleValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.count <= maxTitleLength
    }
    
    /// Whether description is valid (optional but has max length)
    var isDescriptionValid: Bool {
        description.count <= maxDescriptionLength
    }
    
    /// Whether segment count is valid
    var hasMinimumSegments: Bool {
        segments.count >= minSegments
    }
    
    /// Whether collection can be published
    var canPublish: Bool {
        isTitleValid &&
        isDescriptionValid &&
        hasMinimumSegments &&
        allSegmentsUploaded &&
        !hasUploadInProgress &&
        failedSegmentCount == 0
    }
    
    /// Whether draft can be saved
    var canSave: Bool {
        // Can save even empty draft
        true
    }
    
    // MARK: - Draft Management
    
    /// Create a new draft
    /// Ensure a draft exists before uploading. Returns draftID or nil on failure.
    func ensureDraftExists() async -> String? {
        if let id = draftID { return id }
        await createNewDraft()
        return draftID
    }
    
    /// Creates a new draft in Firestore
    func createNewDraft() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let newDraft = try await collectionService.createDraft(
                creatorID: userID,
                title: title.isEmpty ? nil : title,
                description: description.isEmpty ? nil : description,
                visibility: visibility,
                allowReplies: allowReplies
            )
            
            draft = newDraft
            draftID = newDraft.id
            
            print("✅ COMPOSER VM: Created new draft \(newDraft.id)")
            
        } catch {
            errorMessage = "Failed to create draft: \(error.localizedDescription)"
            print("❌ COMPOSER VM: Failed to create draft: \(error)")
        }
        
        isLoading = false
    }
    
    /// Load existing draft
    func loadDraft(draftID: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            if let loadedDraft = try await collectionService.loadDraft(draftID: draftID) {
                loadFromDraft(loadedDraft)
                print("✅ COMPOSER VM: Loaded draft \(draftID)")
            } else {
                errorMessage = "Draft not found"
            }
        } catch {
            errorMessage = "Failed to load draft: \(error.localizedDescription)"
            print("❌ COMPOSER VM: Failed to load draft: \(error)")
        }
        
        isLoading = false
    }
    
    /// Load state from draft object
    private func loadFromDraft(_ loadedDraft: CollectionDraft) {
        draft = loadedDraft
        draftID = loadedDraft.id
        existingDraftID = loadedDraft.id
        title = loadedDraft.title ?? ""
        description = loadedDraft.description ?? ""
        visibility = loadedDraft.visibility
        allowReplies = loadedDraft.allowReplies
        segments = loadedDraft.sortedSegments
    }
    
    /// Save current state to draft
    func saveDraft() async {
        guard canSave else { return }
        
        isSaving = true
        errorMessage = nil
        
        do {
            // Create draft if doesn't exist
            if draft == nil {
                await createNewDraft()
            }
            
            guard var currentDraft = draft else {
                throw CollectionServiceError.draftNotFound("No draft available")
            }
            
            // Update draft with current state
            currentDraft.updateMetadata(
                title: title.isEmpty ? nil : title,
                description: description.isEmpty ? nil : description,
                visibility: visibility,
                allowReplies: allowReplies
            )
            currentDraft.segments = segments
            
            try await collectionService.saveDraft(currentDraft)
            
            draft = currentDraft
            successMessage = "Draft saved"
            
            print("✅ COMPOSER VM: Draft saved")
            
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ COMPOSER VM: Failed to save draft: \(error)")
        }
        
        isSaving = false
    }
    
    /// Delete current draft
    func deleteDraft() async {
        guard let draftID = draftID else { return }
        
        isLoading = true
        
        do {
            try await collectionService.deleteDraft(draftID: draftID)
            
            // Reset state
            draft = nil
            self.draftID = nil
            title = ""
            description = ""
            segments = []
            visibility = .publicVisible
            allowReplies = true
            
            shouldDismiss = true
            
            print("✅ COMPOSER VM: Draft deleted")
            
        } catch {
            errorMessage = "Failed to delete draft: \(error.localizedDescription)"
            print("❌ COMPOSER VM: Failed to delete draft: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Segment Management
    
    /// Add a new segment from local video. Returns the segment ID.
    @discardableResult
    func addSegment(localVideoPath: String, duration: TimeInterval, fileSize: Int64, thumbnailPath: String?) -> String? {
        guard canAddMoreSegments else {
            errorMessage = "Maximum \(maxSegments) segments allowed"
            return nil
        }
        
        let segmentID = UUID().uuidString
        let order = segments.count
        
        let segment = SegmentDraft(
            id: segmentID,
            order: order,
            localVideoPath: localVideoPath,
            thumbnailLocalPath: thumbnailPath,
            uploadProgress: 0.0,
            uploadStatus: .pending,
            title: "Part \(order + 1)",
            duration: duration,
            fileSize: fileSize,
            aspectRatio: 9.0/16.0
        )
        
        segments.append(segment)
        
        print("➕ COMPOSER VM: Added segment \(order + 1) — \(segmentID)")
        
        triggerAutoSave()
        return segmentID
    }
    
    /// Remove a segment by ID
    func removeSegment(id: String) {
        segments.removeAll { $0.id == id }
        
        // Reorder remaining segments
        for (index, _) in segments.enumerated() {
            segments[index] = segments[index].withOrder(index)
        }
        
        print("➖ COMPOSER VM: Removed segment, \(segments.count) remaining")
        
        triggerAutoSave()
    }
    
    /// Move segment from one position to another
    func moveSegment(from source: IndexSet, to destination: Int) {
        segments.move(fromOffsets: source, toOffset: destination)
        
        // Update order for all segments
        for (index, _) in segments.enumerated() {
            segments[index] = segments[index].withOrder(index)
        }
        
        print("🔄 COMPOSER VM: Reordered segments")
        
        triggerAutoSave()
    }
    
    /// Update segment title
    func updateSegmentTitle(id: String, title: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index] = segments[index].withMetadata(title: title)
        
        triggerAutoSave()
    }
    
    /// Retry failed upload for segment
    func retrySegmentUpload(id: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index] = segments[index].resetForRetry()
        
        // TODO: Trigger upload again
        print("🔄 COMPOSER VM: Retrying upload for segment \(id)")
    }
    
    /// Update segment upload progress
    func updateSegmentProgress(id: String, progress: Double, status: SegmentUploadStatus) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index] = segments[index].withUploadProgress(progress, status: status)
    }
    
    /// Mark segment as uploaded
    func markSegmentUploaded(id: String, videoURL: String, thumbnailURL: String?) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index] = segments[index].withUploadedURL(videoURL, thumbnailURL: thumbnailURL)
        
        print("✅ COMPOSER VM: Segment \(id) upload complete")
        
        triggerAutoSave()
    }
    
    /// Mark segment as failed
    func markSegmentFailed(id: String, error: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index] = segments[index].withUploadError(error)
        
        print("❌ COMPOSER VM: Segment \(id) upload failed: \(error)")
    }
    
    // MARK: - Validation
    
    /// Validate current state and update validation errors/warnings
    func validate() {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Title validation
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors.append("Title is required")
        } else if trimmedTitle.count < 3 {
            errors.append("Title must be at least 3 characters")
        } else if trimmedTitle.count > maxTitleLength {
            errors.append("Title must be \(maxTitleLength) characters or less")
        }
        
        // Description validation
        if description.count > maxDescriptionLength {
            errors.append("Description must be \(maxDescriptionLength) characters or less")
        } else if description.isEmpty {
            warnings.append("Adding a description helps viewers find your content")
        }
        
        // Segment validation
        if segments.count < minSegments {
            errors.append("Collection must have at least \(minSegments) segments")
        } else if segments.count > maxSegments {
            errors.append("Collection cannot have more than \(maxSegments) segments")
        }
        
        // Upload status validation
        let pendingCount = segments.filter { !$0.isUploaded }.count
        if pendingCount > 0 {
            errors.append("\(pendingCount) segment(s) not yet uploaded")
        }
        
        let failedCount = failedSegmentCount
        if failedCount > 0 {
            errors.append("\(failedCount) segment(s) failed to upload")
        }
        
        // Duration warnings
        for segment in segments {
            if let duration = segment.duration {
                if duration > 300 {
                    warnings.append("'\(segment.displayTitle)' exceeds 5 minute limit")
                } else if duration < 10 {
                    warnings.append("'\(segment.displayTitle)' is very short")
                }
            }
        }
        
        validationErrors = errors
        validationWarnings = warnings
    }
    
    // MARK: - Publishing
    
    /// Closure to upload cover image (set by coordinator)
    var uploadCoverImage: ((Data, String) async throws -> String)?
    
    /// Publish the collection
    func publish() async {
        guard canPublish else {
            validate()
            errorMessage = validationErrors.first ?? "Cannot publish collection"
            return
        }
        
        // Cancel auto-save to prevent draft resurrection after publish deletes it
        cancelAutoSave()
        
        isPublishing = true
        errorMessage = nil
        
        do {
            // Save draft first to ensure latest state
            await saveDraft()
            
            guard let currentDraft = draft else {
                throw CollectionServiceError.draftNotFound("No draft to publish")
            }
            
            // Get segment video IDs (the actual video documents created for each segment)
            let segmentVideoIDs = segments.compactMap { segment -> String? in
                return segment.id
            }
            
            // Publish the collection - pass cover data and uploader for service to use
            let publishedCollection = try await collectionService.publishCollection(
                draft: currentDraft,
                segmentVideoIDs: segmentVideoIDs,
                totalDuration: totalDuration,
                creatorName: username,
                coverImageData: coverImageData,
                coverImageUploader: uploadCoverImage
            )
            
            successMessage = "Collection published!"
            shouldDismiss = true
            
            print("🎉 COMPOSER VM: Published collection \(publishedCollection.id)")
            
        } catch {
            errorMessage = "Failed to publish: \(error.localizedDescription)"
            print("❌ COMPOSER VM: Failed to publish: \(error)")
        }
        
        isPublishing = false
    }
    
    // MARK: - Auto-Save
    
    /// Setup auto-save on changes
    private func setupAutoSave() {
        // Debounced auto-save when title/description changes
        Publishers.CombineLatest4($title, $description, $visibility, $allowReplies)
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.triggerAutoSave()
            }
            .store(in: &cancellables)
    }
    
    /// Cancel any pending auto-save (call before publish to prevent draft resurrection)
    func cancelAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }
    
    /// Trigger auto-save task
    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
            
            guard !Task.isCancelled else { return }
            
            await self?.saveDraft()
        }
    }
    
    // MARK: - Cleanup
    
    /// Discard changes and reset
    func discardChanges() {
        autoSaveTask?.cancel()
        
        if let originalDraft = draft {
            // Reload from saved draft
            loadFromDraft(originalDraft)
        } else {
            // Reset to empty state
            title = ""
            description = ""
            segments = []
            visibility = .publicVisible
            allowReplies = true
        }
        
        validationErrors = []
        validationWarnings = []
        errorMessage = nil
    }
}

// MARK: - Preview Support

#if DEBUG
extension CollectionComposerViewModel {
    /// Create a preview instance
    static var preview: CollectionComposerViewModel {
        let vm = CollectionComposerViewModel(
            userID: "preview_user",
            username: "PreviewUser"
        )
        
        vm.title = "My Tutorial Series"
        vm.description = "Learn how to build awesome apps"
        
        // Add some mock segments
        vm.segments = [
            SegmentDraft(
                id: "seg1",
                order: 0,
                uploadedVideoURL: "https://example.com/video1.mp4",
                thumbnailURL: "https://example.com/thumb1.jpg",
                uploadProgress: 1.0,
                uploadStatus: .complete,
                title: "Introduction",
                duration: 180,
                fileSize: 15_000_000
            ),
            SegmentDraft(
                id: "seg2",
                order: 1,
                uploadedVideoURL: "https://example.com/video2.mp4",
                thumbnailURL: "https://example.com/thumb2.jpg",
                uploadProgress: 1.0,
                uploadStatus: .complete,
                title: "Getting Started",
                duration: 240,
                fileSize: 20_000_000
            ),
            SegmentDraft(
                id: "seg3",
                order: 2,
                localVideoPath: "/local/video3.mp4",
                uploadProgress: 0.65,
                uploadStatus: .uploading,
                title: "Advanced Topics",
                duration: 300,
                fileSize: 25_000_000
            )
        ]
        
        return vm
    }
    
    /// Create an empty preview instance
    static var emptyPreview: CollectionComposerViewModel {
        CollectionComposerViewModel(
            userID: "preview_user",
            username: "PreviewUser"
        )
    }
}
#endif
