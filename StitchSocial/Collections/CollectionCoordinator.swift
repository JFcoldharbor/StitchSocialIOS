//
//  CollectionCoordinator.swift
//  StitchSocial
//
//  Layer 5: Coordinators - Collection Workflow Management
//  Dependencies: CollectionService, VideoService, CollectionComposerViewModel, CollectionPlayerViewModel
//  Features: Creation workflow, segment upload orchestration, navigation, state management
//  FIXED: Real Firebase Storage upload instead of simulated
//

import Foundation
import SwiftUI
import Combine
import PhotosUI
import AVFoundation
import FirebaseStorage
import UniformTypeIdentifiers

/// Coordinator for collection creation, editing, and playback workflows
/// Manages navigation, upload orchestration, and state persistence
@MainActor
class CollectionCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let collectionService: CollectionService
    private let videoService: VideoService
    private let userID: String
    private let username: String
    private let storage = Storage.storage()
    
    // MARK: - Published State - Navigation
    
    /// Current screen in the collection flow
    @Published var currentScreen: CollectionScreen = .none
    
    /// Navigation path for programmatic navigation
    @Published var navigationPath: [CollectionDestination] = []
    
    /// Whether a sheet is presented
    @Published var isPresentingSheet: Bool = false
    
    /// Current sheet content
    @Published var sheetContent: CollectionSheetContent?
    
    /// Whether fullscreen cover is presented
    @Published var isPresentingFullscreen: Bool = false
    
    /// Fullscreen content type
    @Published var fullscreenContent: CollectionFullscreenContent?
    
    // MARK: - Published State - Composer
    
    /// Active composer view model
    @Published private(set) var composerViewModel: CollectionComposerViewModel?
    
    /// Link an externally-created viewModel to this coordinator (used by ComposerSheet)
    func linkComposerViewModel(_ viewModel: CollectionComposerViewModel) {
        composerViewModel = viewModel
        print("🔗 COORDINATOR: Linked external composerViewModel")
    }
    
    /// Whether composer has unsaved changes (for discard confirmation)
    @Published var composerHasUnsavedChanges: Bool = false
    
    // MARK: - Published State - Player
    
    /// Active player view model
    @Published private(set) var playerViewModel: CollectionPlayerViewModel?
    
    // MARK: - Published State - Upload
    
    /// Active upload tasks
    @Published private(set) var activeUploads: [SegmentUploadTask] = []
    
    /// Overall upload progress across all segments
    @Published private(set) var overallUploadProgress: Double = 0.0
    
    /// Whether uploads are in progress
    @Published private(set) var isUploading: Bool = false
    
    /// Upload error if any
    @Published var uploadError: String?
    
    // MARK: - Published State - UI
    
    /// Loading state
    @Published private(set) var isLoading: Bool = false
    
    /// Error message for alerts
    @Published var errorMessage: String?
    
    /// Success message for toasts
    @Published var successMessage: String?
    
    /// Whether to show discard confirmation
    @Published var showDiscardConfirmation: Bool = false
    
    /// Whether to show delete confirmation
    @Published var showDeleteConfirmation: Bool = false
    
    /// Whether to show publish confirmation
    @Published var showPublishConfirmation: Bool = false
    
    // MARK: - Private State
    
    private var cancellables = Set<AnyCancellable>()
    private var uploadTasks: [String: Task<(videoURL: String, thumbnailURL: String?)?, Never>] = [:]
    private var storageUploadTasks: [String: StorageUploadTask] = [:]
    
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
        
        setupBindings()
        
        print("🎬 COLLECTION COORDINATOR: Initialized for user \(userID)")
    }
    
    /// Convenience initializer with default services
    convenience init(userID: String, username: String) {
        self.init(
            userID: userID,
            username: username,
            collectionService: CollectionService(),
            videoService: VideoService()
        )
    }
    
    // MARK: - Navigation - Composer
    
    /// Start creating a new collection
    func startNewCollection() {
        let viewModel = CollectionComposerViewModel(
            userID: userID,
            username: username,
            collectionService: collectionService,
            videoService: videoService
        )
        
        // Set up cover image upload closure
        viewModel.uploadCoverImage = { [weak self] data, collectionID in
            guard let self = self else { throw CoordinatorError.uploadFailed("Coordinator unavailable") }
            return try await self.uploadCoverPhoto(imageData: data, collectionID: collectionID)
        }
        
        composerViewModel = viewModel
        currentScreen = .composer
        isPresentingFullscreen = true
        fullscreenContent = .composer
        
        // Create draft in background
        Task {
            await viewModel.createNewDraft()
        }
        
        print("🆕 COORDINATOR: Started new collection")
    }
    
    /// Edit existing draft
    func editDraft(_ draft: CollectionDraft) {
        let viewModel = CollectionComposerViewModel(
            draft: draft,
            username: username,
            collectionService: collectionService,
            videoService: videoService
        )
        
        // Set up cover image upload closure
        viewModel.uploadCoverImage = { [weak self] data, collectionID in
            guard let self = self else { throw CoordinatorError.uploadFailed("Coordinator unavailable") }
            return try await self.uploadCoverPhoto(imageData: data, collectionID: collectionID)
        }
        
        composerViewModel = viewModel
        currentScreen = .composer
        isPresentingFullscreen = true
        fullscreenContent = .composer
        
        print("✏️ COORDINATOR: Editing draft \(draft.id)")
    }
    
    /// Edit existing draft by ID
    func editDraft(draftID: String) {
        let viewModel = CollectionComposerViewModel(
            userID: userID,
            username: username,
            collectionService: collectionService,
            videoService: videoService
        )
        
        // Set up cover image upload closure
        viewModel.uploadCoverImage = { [weak self] data, collectionID in
            guard let self = self else { throw CoordinatorError.uploadFailed("Coordinator unavailable") }
            return try await self.uploadCoverPhoto(imageData: data, collectionID: collectionID)
        }
        
        composerViewModel = viewModel
        currentScreen = .composer
        isPresentingFullscreen = true
        fullscreenContent = .composer
        
        Task {
            await viewModel.loadDraft(draftID: draftID)
        }
        
        print("✏️ COORDINATOR: Loading draft \(draftID)")
    }
    
    /// Close composer with save check
    func closeComposer(forceSave: Bool = false) {
        guard let viewModel = composerViewModel else {
            dismissComposer()
            return
        }
        
        if viewModel.hasUnsavedChanges && !forceSave {
            showDiscardConfirmation = true
        } else if forceSave {
            Task {
                await viewModel.saveDraft()
                dismissComposer()
            }
        } else {
            dismissComposer()
        }
    }
    
    /// Dismiss composer without saving
    func dismissComposer() {
        composerViewModel = nil
        currentScreen = .none
        isPresentingFullscreen = false
        fullscreenContent = nil
        
        print("👋 COORDINATOR: Composer dismissed")
    }
    
    /// Discard changes and close
    func discardAndClose() {
        composerViewModel?.discardChanges()
        dismissComposer()
        showDiscardConfirmation = false
    }
    
    // MARK: - Navigation - Player
    
    /// Play a collection
    func playCollection(_ collection: VideoCollection) {
        print("▶️ COORDINATOR: playCollection called for '\(collection.title)' (ID: \(collection.id))")
        
        let viewModel = CollectionPlayerViewModel(
            collection: collection,
            userID: userID,
            collectionService: collectionService,
            videoService: videoService
        )
        
        playerViewModel = viewModel
        currentScreen = .player
        isPresentingFullscreen = true
        fullscreenContent = .player
        
        print("▶️ COORDINATOR: Set isPresentingFullscreen=true, fullscreenContent=.player")
        
        Task {
            await viewModel.load()
        }
        
        print("▶️ COORDINATOR: Playing collection \(collection.id)")
    }
    
    /// Play a collection by ID
    func playCollection(collectionID: String) {
        isLoading = true
        
        Task {
            do {
                if let collection = try await collectionService.getCollection(id: collectionID) {
                    playCollection(collection)
                } else {
                    errorMessage = "Collection not found"
                }
            } catch {
                errorMessage = "Failed to load collection: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    /// Close player
    func closePlayer() {
        Task {
            await playerViewModel?.cleanup()
            playerViewModel = nil
            currentScreen = .none
            isPresentingFullscreen = false
            fullscreenContent = nil
            
            print("👋 COORDINATOR: Player dismissed")
        }
    }
    
    // MARK: - Navigation - Sheets
    
    /// Show segment picker
    func showSegmentPicker() {
        sheetContent = .segmentPicker
        isPresentingSheet = true
    }
    
    /// Show segment reorder
    func showSegmentReorder() {
        sheetContent = .segmentReorder
        isPresentingSheet = true
    }
    
    /// Show settings
    func showSettings() {
        sheetContent = .settings
        isPresentingSheet = true
    }
    
    /// Show segment list (in player)
    func showSegmentList() {
        sheetContent = .segmentList
        isPresentingSheet = true
    }
    
    /// Dismiss current sheet
    func dismissSheet() {
        isPresentingSheet = false
        sheetContent = nil
    }
    
    // MARK: - Segment Upload Management (REAL FIREBASE UPLOAD)
    
    /// Add video segment from Photos picker
    func addSegmentFromPhotos(_ item: PhotosPickerItem) {
        guard let viewModel = composerViewModel else {
            print("❌ COORDINATOR: No composer view model")
            return
        }
        guard viewModel.canAddMoreSegments else {
            errorMessage = "Maximum segments reached"
            return
        }
        
        print("📹 COORDINATOR: Starting to load video from PhotosPickerItem")
        
        Task {
            do {
                // Create temp file path
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                
                // Try loading as Movie type first (most reliable for videos)
                var videoLoaded = false
                
                // Method 1: Try loading transferable Movie
                if let movie = try? await item.loadTransferable(type: Movie.self) {
                    print("📹 COORDINATOR: Loaded via Movie transferable")
                    try FileManager.default.copyItem(at: movie.url, to: tempURL)
                    videoLoaded = true
                }
                
                // Method 2: Try loading as Data (works for smaller videos)
                if !videoLoaded, let videoData = try? await item.loadTransferable(type: Data.self) {
                    print("📹 COORDINATOR: Loaded via Data transferable (\(videoData.count) bytes)")
                    try videoData.write(to: tempURL)
                    videoLoaded = true
                }
                
                // Method 3: Use the item provider directly
                if !videoLoaded {
                    print("📹 COORDINATOR: Trying item provider method...")
                    let loadedURL = try await loadVideoFromItemProvider(item)
                    try FileManager.default.copyItem(at: loadedURL, to: tempURL)
                    videoLoaded = true
                }
                
                guard videoLoaded else {
                    throw CoordinatorError.videoLoadFailed
                }
                
                // Verify file exists
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    print("❌ COORDINATOR: Video file doesn't exist at \(tempURL.path)")
                    throw CoordinatorError.videoLoadFailed
                }
                
                // Get video metadata
                let asset = AVURLAsset(url: tempURL)
                let duration = try await asset.load(.duration).seconds
                
                // Get file size
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0
                
                // Generate thumbnail
                let thumbnailPath = try await generateThumbnail(for: tempURL)
                
                print("📹 COORDINATOR: Video loaded - duration: \(duration)s, size: \(fileSize) bytes")
                
                // Add to composer on main thread
                await MainActor.run {
                    viewModel.addSegment(
                        localVideoPath: tempURL.path,
                        duration: duration,
                        fileSize: fileSize,
                        thumbnailPath: thumbnailPath
                    )
                }
                
                // Get segment ID
                let segmentID = await MainActor.run {
                    viewModel.segments.last?.id ?? UUID().uuidString
                }
                
                // Start REAL upload
                await startSegmentUpload(
                    segmentID: segmentID,
                    localURL: tempURL,
                    thumbnailPath: thumbnailPath
                )
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add video: \(error.localizedDescription)"
                }
                print("❌ COORDINATOR: Failed to add segment: \(error)")
            }
        }
    }
    
    /// Load video from PhotosPickerItem using NSItemProvider
    private func loadVideoFromItemProvider(_ item: PhotosPickerItem) async throws -> URL {
        // Get the underlying item provider
        guard let itemProvider = await getItemProvider(from: item) else {
            throw CoordinatorError.videoLoadFailed
        }
        
        // Check for video types
        let videoTypes = ["public.movie", "public.mpeg-4", "com.apple.quicktime-movie", "public.avi"]
        
        for typeIdentifier in videoTypes {
            if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                print("📹 COORDINATOR: Found type \(typeIdentifier)")
                
                return try await withCheckedThrowingContinuation { continuation in
                    itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let url = url else {
                            continuation.resume(throwing: CoordinatorError.videoLoadFailed)
                            return
                        }
                        
                        // Copy to temp location because the provided URL is temporary
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        
                        do {
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            continuation.resume(returning: tempURL)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
        
        throw CoordinatorError.videoLoadFailed
    }
    
    /// Extract item provider from PhotosPickerItem (workaround)
    private func getItemProvider(from item: PhotosPickerItem) async -> NSItemProvider? {
        // PhotosPickerItem doesn't directly expose itemProvider, so we use reflection or try different loading
        // Actually, we can use loadTransferable to trigger the provider
        
        // Return nil to indicate we should use the continuation-based approach differently
        // The PhotosPickerItem should be handled via loadTransferable
        return nil
    }
    
    /// Add video segment from URL
    func addSegmentFromURL(_ url: URL, duration: TimeInterval, fileSize: Int64) {
        guard let viewModel = composerViewModel else { return }
        guard viewModel.canAddMoreSegments else {
            errorMessage = "Maximum segments reached"
            return
        }
        
        Task {
            do {
                let thumbnailPath = try await generateThumbnail(for: url)
                
                viewModel.addSegment(
                    localVideoPath: url.path,
                    duration: duration,
                    fileSize: fileSize,
                    thumbnailPath: thumbnailPath
                )
                
                let segmentID = viewModel.segments.last?.id ?? UUID().uuidString
                await startSegmentUpload(
                    segmentID: segmentID,
                    localURL: url,
                    thumbnailPath: thumbnailPath
                )
                
            } catch {
                errorMessage = "Failed to add video: \(error.localizedDescription)"
            }
        }
    }
    
    /// Public method to upload a segment (called from view when coordinator.composerViewModel might be stale)
    /// Public method to upload a segment - returns (videoURL, thumbnailURL) on success
    func uploadSegment(segmentID: String, localURL: URL, thumbnailPath: String?, draftID: String? = nil) async -> (videoURL: String, thumbnailURL: String?)? {
        let effectiveDraftID = draftID ?? composerViewModel?.draftID ?? "unknown_\(UUID().uuidString.prefix(8))"
        return await performUpload(segmentID: segmentID, localURL: localURL, thumbnailPath: thumbnailPath, draftID: effectiveDraftID)
    }
    
    /// Start uploading a segment - REAL FIREBASE STORAGE UPLOAD
    private func startSegmentUpload(segmentID: String, localURL: URL, thumbnailPath: String?) async {
        guard let viewModel = composerViewModel else {
            print("❌ COORDINATOR: No composer view model for upload")
            return
        }
        guard let draftID = viewModel.draftID else {
            print("❌ COORDINATOR: No draft ID available for upload")
            return
        }
        
        let _ = await performUpload(segmentID: segmentID, localURL: localURL, thumbnailPath: thumbnailPath, draftID: draftID)
    }
    
    /// Perform the actual upload - returns URLs on success
    private func performUpload(segmentID: String, localURL: URL, thumbnailPath: String?, draftID: String) async -> (videoURL: String, thumbnailURL: String?)? {
        // Create upload task tracking
        let uploadTask = SegmentUploadTask(
            id: segmentID,
            segmentID: segmentID,
            localURL: localURL,
            thumbnailPath: thumbnailPath,
            status: .uploading,
            progress: 0.0
        )
        
        activeUploads.append(uploadTask)
        isUploading = true
        
        // Update viewModel if available
        composerViewModel?.updateSegmentProgress(id: segmentID, progress: 0.0, status: .uploading)
        
        print("📤 COORDINATOR: Starting upload for segment \(segmentID) to draft \(draftID)")
        
        // Start async upload task with explicit return type
        let task = Task<(videoURL: String, thumbnailURL: String?)?, Never> {
            do {
                // 1. Upload video to Firebase Storage
                let videoRef = storage.reference()
                    .child("collections")
                    .child(userID)
                    .child(draftID)
                    .child("segments")
                    .child("\(segmentID).mp4")
                
                let metadata = StorageMetadata()
                metadata.contentType = "video/mp4"
                
                // Create upload task
                let firebaseUploadTask = videoRef.putFile(from: localURL, metadata: metadata)
                storageUploadTasks[segmentID] = firebaseUploadTask
                
                // Observe progress
                firebaseUploadTask.observe(.progress) { [weak self] snapshot in
                    guard let progress = snapshot.progress else { return }
                    let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    
                    Task { @MainActor in
                        self?.updateUploadProgress(segmentID: segmentID, progress: percentComplete * 0.9) // Reserve 10% for thumbnail
                    }
                }
                
                // Wait for completion with timeout (5 min max per segment)
                _ = try await withThrowingTaskGroup(of: StorageMetadata.self) { group in
                    group.addTask {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
                            firebaseUploadTask.observe(.success) { snapshot in
                                if let metadata = snapshot.metadata {
                                    continuation.resume(returning: metadata)
                                }
                            }
                            firebaseUploadTask.observe(.failure) { snapshot in
                                let error = snapshot.error ?? NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                    // Timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                        throw NSError(domain: "UploadError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Upload timed out after 5 minutes"])
                    }
                    
                    // First to finish wins — cancel the other
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                
                // Get download URL
                let videoURL = try await videoRef.downloadURL().absoluteString
                
                print("✅ COORDINATOR: Video uploaded to \(videoURL)")
                
                // Update progress to 95% after video upload
                await MainActor.run {
                    self.updateUploadProgress(segmentID: segmentID, progress: 0.95)
                }
                
                // 2. Upload thumbnail if exists
                var thumbnailURL: String? = nil
                if let thumbPath = thumbnailPath {
                    // Verify thumbnail file exists before attempting upload
                    if FileManager.default.fileExists(atPath: thumbPath) {
                        print("📸 COORDINATOR: Starting thumbnail upload from \(thumbPath)")
                        
                        let thumbFileURL = URL(fileURLWithPath: thumbPath)
                        let thumbRef = storage.reference()
                            .child("collections")
                            .child(userID)
                            .child(draftID)
                            .child("thumbnails")
                            .child("\(segmentID).jpg")
                        
                        let thumbMetadata = StorageMetadata()
                        thumbMetadata.contentType = "image/jpeg"
                        
                        // Upload thumbnail using continuation pattern
                        do {
                            let thumbUploadTask = thumbRef.putFile(from: thumbFileURL, metadata: thumbMetadata)
                            
                            // Wait for thumbnail upload with timeout (60s)
                            _ = try await withThrowingTaskGroup(of: StorageMetadata.self) { group in
                                group.addTask {
                                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
                                        thumbUploadTask.observe(.success) { snapshot in
                                            if let metadata = snapshot.metadata {
                                                continuation.resume(returning: metadata)
                                            }
                                        }
                                        thumbUploadTask.observe(.failure) { snapshot in
                                            let error = snapshot.error ?? NSError(domain: "UploadError", code: -1)
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                                
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                                    throw NSError(domain: "UploadError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Thumbnail upload timed out"])
                                }
                                
                                let result = try await group.next()!
                                group.cancelAll()
                                return result
                            }
                            
                            // Now get download URL after upload is confirmed complete
                            thumbnailURL = try await thumbRef.downloadURL().absoluteString
                            print("✅ COORDINATOR: Thumbnail uploaded to \(thumbnailURL ?? "unknown")")
                        } catch {
                            // Thumbnail upload failed, but video is already uploaded - continue anyway
                            print("⚠️ COORDINATOR: Thumbnail upload failed: \(error.localizedDescription) - continuing without thumbnail")
                        }
                    } else {
                        print("⚠️ COORDINATOR: Thumbnail file not found at \(thumbPath), skipping thumbnail upload")
                    }
                } else {
                    print("⚠️ COORDINATOR: No thumbnail path provided, skipping thumbnail upload")
                }
                
                // Update progress to 100%
                await MainActor.run {
                    self.updateUploadProgress(segmentID: segmentID, progress: 1.0)
                }
                
                // 3. Complete upload (success even without thumbnail)
                await MainActor.run {
                    completeUpload(segmentID: segmentID, videoURL: videoURL, thumbnailURL: thumbnailURL ?? "")
                }
                
                print("🎉 COORDINATOR: Upload fully complete for segment \(segmentID)")
                
                return (videoURL, thumbnailURL)
                
            } catch {
                await MainActor.run {
                    failUpload(segmentID: segmentID, error: error.localizedDescription)
                }
                return nil
            }
        }
        
        uploadTasks[segmentID] = task
        
        // Wait for the task to complete and return result
        return await task.value
    }
    
    /// Update upload progress
    private func updateUploadProgress(segmentID: String, progress: Double) {
        // Update active upload
        if let index = activeUploads.firstIndex(where: { $0.segmentID == segmentID }) {
            activeUploads[index].progress = progress
        }
        
        // Update composer
        composerViewModel?.updateSegmentProgress(id: segmentID, progress: progress, status: .uploading)
        
        // Calculate overall progress
        let total = activeUploads.reduce(0.0) { $0 + $1.progress }
        overallUploadProgress = activeUploads.isEmpty ? 0 : total / Double(activeUploads.count)
    }
    
    /// Complete upload
    private func completeUpload(segmentID: String, videoURL: String, thumbnailURL: String) {
        // Remove from active uploads
        activeUploads.removeAll { $0.segmentID == segmentID }
        uploadTasks.removeValue(forKey: segmentID)
        storageUploadTasks.removeValue(forKey: segmentID)
        
        // Update composer
        composerViewModel?.markSegmentUploaded(id: segmentID, videoURL: videoURL, thumbnailURL: thumbnailURL)
        
        // Update uploading state
        isUploading = !activeUploads.isEmpty
        
        if activeUploads.isEmpty {
            overallUploadProgress = 0
        }
        
        // Auto-save draft
        Task {
            await composerViewModel?.saveDraft()
        }
        
        print("✅ COORDINATOR: Upload complete for \(segmentID)")
    }
    
    /// Fail upload
    private func failUpload(segmentID: String, error: String) {
        // Update active upload
        if let index = activeUploads.firstIndex(where: { $0.segmentID == segmentID }) {
            activeUploads[index].status = .failed
            activeUploads[index].error = error
        }
        
        uploadTasks.removeValue(forKey: segmentID)
        storageUploadTasks.removeValue(forKey: segmentID)
        
        // Update composer
        composerViewModel?.updateSegmentProgress(id: segmentID, progress: 0, status: .failed)
        
        uploadError = "Upload failed: \(error)"
        
        print("❌ COORDINATOR: Upload failed for \(segmentID): \(error)")
    }
    
    /// Retry failed upload
    func retryUpload(segmentID: String) {
        guard let segment = composerViewModel?.segments.first(where: { $0.id == segmentID }),
              let localPath = segment.localVideoPath else {
            return
        }
        
        // Remove from failed
        activeUploads.removeAll { $0.segmentID == segmentID }
        
        // Retry
        Task {
            await startSegmentUpload(
                segmentID: segmentID,
                localURL: URL(fileURLWithPath: localPath),
                thumbnailPath: segment.thumbnailLocalPath
            )
        }
    }
    
    /// Cancel upload
    func cancelUpload(segmentID: String) {
        // Cancel the Swift task
        uploadTasks[segmentID]?.cancel()
        uploadTasks.removeValue(forKey: segmentID)
        
        // Cancel the Firebase upload task
        storageUploadTasks[segmentID]?.cancel()
        storageUploadTasks.removeValue(forKey: segmentID)
        
        activeUploads.removeAll { $0.segmentID == segmentID }
        
        composerViewModel?.updateSegmentProgress(id: segmentID, progress: 0, status: .cancelled)
        
        isUploading = !activeUploads.isEmpty
        
        print("🚫 COORDINATOR: Upload cancelled for \(segmentID)")
    }
    
    /// Cancel all uploads
    func cancelAllUploads() {
        for (segmentID, task) in uploadTasks {
            task.cancel()
            composerViewModel?.updateSegmentProgress(id: segmentID, progress: 0, status: .cancelled)
        }
        
        for (_, task) in storageUploadTasks {
            task.cancel()
        }
        
        uploadTasks.removeAll()
        storageUploadTasks.removeAll()
        activeUploads.removeAll()
        isUploading = false
        overallUploadProgress = 0
        
        print("🚫 COORDINATOR: All uploads cancelled")
    }
    
    // MARK: - Publishing
    
    /// Publish current collection
    func publishCollection() {
        guard let viewModel = composerViewModel else { return }
        
        if viewModel.canPublish {
            showPublishConfirmation = true
        } else {
            viewModel.validate()
            errorMessage = viewModel.validationErrors.first ?? "Cannot publish collection"
        }
    }
    
    /// Confirm and execute publish
    func confirmPublish() async {
        showPublishConfirmation = false
        
        // Cancel any pending auto-save to prevent draft resurrection
        composerViewModel?.cancelAutoSave()
        
        await composerViewModel?.publish()
        
        if composerViewModel?.shouldDismiss == true {
            successMessage = "Collection published!"
            
            // Notify profile to reload collections
            NotificationCenter.default.post(name: NSNotification.Name("RefreshProfile"), object: nil)
            
            dismissComposer()
        } else {
            // Publish failed — surface the error so user sees it
            errorMessage = composerViewModel?.errorMessage ?? "Publish failed. Please try again."
            print("❌ COORDINATOR: Publish did not complete — shouldDismiss is false")
        }
    }
    
    /// Upload cover photo to Firebase Storage
    /// Returns the download URL string
    func uploadCoverPhoto(imageData: Data, collectionID: String) async throws -> String {
        let coverRef = storage.reference().child("collections/\(collectionID)/cover.jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        print("📸 COORDINATOR: Uploading cover photo for collection \(collectionID)")
        
        // Upload using continuation pattern for reliability
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            let uploadTask = coverRef.putData(imageData, metadata: metadata)
            
            uploadTask.observe(.success) { snapshot in
                continuation.resume(returning: snapshot.metadata!)
            }
            
            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: CoordinatorError.uploadFailed("Cover photo upload failed"))
                }
            }
        }
        
        // Get download URL
        let downloadURL = try await coverRef.downloadURL()
        print("✅ COORDINATOR: Cover photo uploaded - \(downloadURL.absoluteString)")
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Draft Management
    
    /// Load user's drafts
    func loadUserDrafts() async -> [CollectionDraft] {
        do {
            return try await collectionService.loadUserDrafts(creatorID: userID)
        } catch {
            errorMessage = "Failed to load drafts: \(error.localizedDescription)"
            return []
        }
    }
    
    /// Delete draft
    func deleteDraft(_ draft: CollectionDraft) {
        Task {
            do {
                try await collectionService.deleteDraft(draftID: draft.id)
                successMessage = "Draft deleted"
            } catch {
                errorMessage = "Failed to delete draft: \(error.localizedDescription)"
            }
        }
    }
    
    /// Delete current draft
    func deleteCurrentDraft() {
        showDeleteConfirmation = true
    }
    
    /// Confirm draft deletion
    func confirmDeleteDraft() {
        showDeleteConfirmation = false
        
        Task {
            await composerViewModel?.deleteDraft()
            dismissComposer()
        }
    }
    
    // MARK: - Helpers
    
    /// Generate thumbnail for video
    private func generateThumbnail(for videoURL: URL) async throws -> String? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        do {
            let cgImage = try await imageGenerator.image(at: time).image
            let uiImage = UIImage(cgImage: cgImage)
            
            // Save to temp file
            let thumbnailURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnailURL)
                return thumbnailURL.path
            }
        } catch {
            print("⚠️ COORDINATOR: Failed to generate thumbnail: \(error)")
        }
        
        return nil
    }
    
    /// Setup bindings between view models and coordinator
    private func setupBindings() {
        // Bindings are set up when view models are created
        // This is a placeholder for future reactive bindings
    }
    
    // MARK: - Cleanup
    
    /// Cleanup on deallocation
    func cleanup() {
        cancelAllUploads()
        
        Task {
            await playerViewModel?.cleanup()
        }
        
        composerViewModel = nil
        playerViewModel = nil
    }
}

// MARK: - Supporting Types

/// Current screen in collection flow
enum CollectionScreen {
    case none
    case composer
    case player
    case drafts
}

/// Navigation destinations
enum CollectionDestination: Hashable {
    case composer(draftID: String?)
    case player(collectionID: String)
    case drafts
    case settings
}

/// Sheet content types
enum CollectionSheetContent {
    case segmentPicker
    case segmentReorder
    case settings
    case segmentList
    case segmentDetails(segmentID: String)
}

/// Fullscreen content types
enum CollectionFullscreenContent {
    case composer
    case player
}

/// Segment upload task tracking
struct SegmentUploadTask: Identifiable {
    let id: String
    let segmentID: String
    let localURL: URL
    let thumbnailPath: String?
    var status: SegmentUploadStatus
    var progress: Double
    var error: String?
}

/// Coordinator errors
enum CoordinatorError: LocalizedError {
    case videoLoadFailed
    case thumbnailGenerationFailed
    case uploadFailed(String)
    case noDraftID
    case collectionNotFound
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .videoLoadFailed:
            return "Failed to load video"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .noDraftID:
            return "No draft ID available"
        case .collectionNotFound:
            return "Collection not found"
        case .unauthorized:
            return "You don't have permission to perform this action"
        }
    }
}

// MARK: - Video Transferable

/// Standard Transferable type for handling video files from PhotosPicker
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension)
            
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            print("📹 Movie: Copied video to \(tempURL.path)")
            return Self(url: tempURL)
        }
    }
}
