//
//  BackgroundUploadManager.swift
//  StitchSocial
//
//  Layer 4: Services - Background Video Upload Manager
//  Dependencies: VideoUploadService, LocalDraftManager, VideoEditState
//  Features: Background upload queue, retry on failure, app-kill recovery, progress tracking
//
//  Owns the upload lifecycle after user taps "Post":
//  1. User taps Post → screens dismiss → job queued here
//  2. Runs upload via VideoUploadService in background
//  3. On success → cleans up draft, posts notification
//  4. On failure → marks draft as .failed, keeps for retry
//  5. On app relaunch → recovers interrupted uploads automatically
//

import Foundation
import Combine

/// Manages background video uploads so users can keep scrolling while videos post
@MainActor
class BackgroundUploadManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = BackgroundUploadManager()
    
    // MARK: - Published State (consumed by UploadProgressPill)
    
    @Published var currentUploadProgress: Double = 0.0
    @Published var currentUploadStatus: UploadJobStatus = .idle
    @Published var currentUploadTitle: String = ""
    @Published var activeUploadCount: Int = 0
    @Published var lastCompletedTitle: String?
    @Published var lastErrorMessage: String?
    
    // MARK: - Upload Job Status
    
    enum UploadJobStatus: Equatable {
        case idle           // No active uploads
        case uploading      // Currently uploading a video
        case completing     // Upload done, creating Firestore document
        case success        // Just finished successfully (briefly shown)
        case failed         // Upload failed (shown until dismissed)
    }
    
    // MARK: - Private State
    
    private let uploadService = VideoUploadService()
    private let draftManager = LocalDraftManager.shared
    private var uploadQueue: [String] = [] // draftIDs in order
    private var currentUploadTask: Task<Void, Never>?
    private var isProcessingQueue = false
    private let maxRetries = 3
    
    // MARK: - Notifications
    
    static let uploadCompletedNotification = Notification.Name("BackgroundUploadCompleted")
    static let uploadFailedNotification = Notification.Name("BackgroundUploadFailed")
    
    // MARK: - Initialization
    
    private init() {
        print("📤 BACKGROUND UPLOAD: Manager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Queue a draft for background upload
    /// Call this when user taps "Post" — screens can dismiss immediately after
    func queueUpload(draftID: String) {
        guard !uploadQueue.contains(draftID) else {
            print("⚠️ BACKGROUND UPLOAD: Draft \(draftID.prefix(8)) already in queue")
            return
        }
        
        uploadQueue.append(draftID)
        activeUploadCount = uploadQueue.count
        
        Task {
            await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.readyToUpload)
        }
        
        print("📤 BACKGROUND UPLOAD: Queued draft \(draftID.prefix(8)) — queue size: \(uploadQueue.count)")
        
        // Start processing if not already running
        processNextInQueue()
    }
    
    /// Retry a specific failed upload
    func retryUpload(draftID: String) {
        guard let draft = draftManager.getDraft(id: draftID),
              draft.canRetryUpload else {
            print("❌ BACKGROUND UPLOAD: Cannot retry \(draftID.prefix(8)) — missing metadata")
            return
        }
        
        // Re-queue it
        queueUpload(draftID: draftID)
        
        print("🔄 BACKGROUND UPLOAD: Retrying draft \(draftID.prefix(8)) — attempt \(draft.uploadAttemptCount + 1)")
    }
    
    /// Retry all failed uploads
    func retryAllFailed() {
        let failed = draftManager.failedUploads
        for draft in failed {
            retryUpload(draftID: draft.draftID)
        }
        
        if !failed.isEmpty {
            print("🔄 BACKGROUND UPLOAD: Retrying \(failed.count) failed uploads")
        }
    }
    
    /// Cancel current upload and clear queue
    func cancelAll() {
        currentUploadTask?.cancel()
        currentUploadTask = nil
        
        // Mark all queued as draft (not failed)
        for draftID in uploadQueue {
            Task {
                await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.draft)
            }
        }
        
        uploadQueue.removeAll()
        activeUploadCount = 0
        currentUploadStatus = .idle
        isProcessingQueue = false
        
        print("🛑 BACKGROUND UPLOAD: Cancelled all uploads")
    }
    
    /// Called on app launch to recover interrupted uploads
    func recoverInterruptedUploads() {
        let interrupted = draftManager.recoverInterruptedUploads()
        
        for draft in interrupted {
            if !uploadQueue.contains(draft.draftID) {
                uploadQueue.append(draft.draftID)
            }
        }
        
        if !interrupted.isEmpty {
            activeUploadCount = uploadQueue.count
            print("🔄 BACKGROUND UPLOAD: Recovered \(interrupted.count) interrupted uploads")
            processNextInQueue()
        }
        
        // Also clean up any completed drafts from previous sessions
        Task {
            await draftManager.cleanupCompletedUploads()
        }
    }
    
    // MARK: - Queue Processing
    
    private func processNextInQueue() {
        guard !isProcessingQueue else { return }
        guard !uploadQueue.isEmpty else {
            currentUploadStatus = .idle
            activeUploadCount = 0
            return
        }
        
        isProcessingQueue = true
        let draftID = uploadQueue[0]
        
        currentUploadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.processUpload(draftID: draftID)
        }
    }
    
    private func processUpload(draftID: String) async {
        guard let draft = draftManager.getDraft(id: draftID),
              let uploadMeta = draft.uploadMetadata,
              let uploadContext = draft.uploadContext else {
            print("❌ BACKGROUND UPLOAD: Draft \(draftID.prefix(8)) missing required data — skipping")
            removeFromQueue(draftID: draftID)
            await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.failed, errorMessage: "Missing upload data")
            isProcessingQueue = false
            processNextInQueue()
            return
        }
        
        // Update UI state
        currentUploadStatus = .uploading
        currentUploadTitle = uploadMeta.title
        currentUploadProgress = 0.0
        
        // Mark as uploading in draft manager
        await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.uploading)
        
        print("📤 BACKGROUND UPLOAD: Starting upload for '\(uploadMeta.title)'")
        
        do {
            // Determine the best video URL to upload
            let videoURL = draft.finalVideoURL
            
            // Verify file exists
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                throw UploadError.fileNotFound("Video file no longer exists at \(videoURL.path)")
            }
            
            // Convert persisted metadata to upload types
            let metadata = uploadMeta.toUploadMetadata()
            let context = uploadContext.toRecordingContext()
            
            // Monitor upload progress
            let progressObserver = Task { [weak self] in
                guard let self = self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    await MainActor.run {
                        self.currentUploadProgress = self.uploadService.uploadProgress
                    }
                }
            }
            
            // Perform the actual upload
            let result = try await uploadService.uploadVideo(
                videoURL: videoURL,
                metadata: metadata,
                recordingContext: context
            )
            
            progressObserver.cancel()
            
            // Create the video document in Firestore
            currentUploadStatus = .completing
            currentUploadProgress = 0.95
            
            let videoService = VideoService()
            let userService = UserService()
            let notificationService = NotificationService()
            
            _ = try await uploadService.createVideoDocument(
                uploadResult: result,
                metadata: metadata,
                recordingContext: context,
                videoService: videoService,
                userService: userService,
                notificationService: notificationService,
                taggedUserIDs: uploadMeta.taggedUserIDs,
                recordingSource: uploadMeta.recordingSource,
                hashtags: uploadMeta.hashtags
            )
            
            // SUCCESS
            currentUploadStatus = .success
            currentUploadProgress = 1.0
            lastCompletedTitle = uploadMeta.title
            lastErrorMessage = nil
            
            // Mark complete and clean up
            await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.complete)
            removeFromQueue(draftID: draftID)
            
            // Post notification for UI refresh (e.g. profile grid)
            NotificationCenter.default.post(
                name: Self.uploadCompletedNotification,
                object: nil,
                userInfo: ["draftID": draftID, "title": uploadMeta.title]
            )
            
            // Also trigger profile refresh
            NotificationCenter.default.post(name: NSNotification.Name("RefreshProfile"), object: nil)
            
            print("✅ BACKGROUND UPLOAD: '\(uploadMeta.title)' uploaded successfully")
            
            // Brief success display, then move on
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            
            // Clean up completed draft after delay
            Task {
                await draftManager.cleanupCompletedUploads()
            }
            
        } catch {
            // FAILURE
            guard !Task.isCancelled else {
                print("🛑 BACKGROUND UPLOAD: Cancelled for '\(uploadMeta.title)'")
                isProcessingQueue = false
                return
            }
            
            let errorMsg = error.localizedDescription
            currentUploadStatus = .failed
            lastErrorMessage = errorMsg
            
            await draftManager.markUploadStatus(draftID: draftID, status: DraftUploadStatus.failed, errorMessage: errorMsg)
            removeFromQueue(draftID: draftID)
            
            // Post failure notification
            NotificationCenter.default.post(
                name: Self.uploadFailedNotification,
                object: nil,
                userInfo: ["draftID": draftID, "error": errorMsg]
            )
            
            print("❌ BACKGROUND UPLOAD: Failed for '\(uploadMeta.title)' — \(errorMsg)")
        }
        
        // Process next in queue
        isProcessingQueue = false
        activeUploadCount = uploadQueue.count
        processNextInQueue()
    }
    
    // MARK: - Queue Helpers
    
    private func removeFromQueue(draftID: String) {
        uploadQueue.removeAll { $0 == draftID }
        activeUploadCount = uploadQueue.count
    }
    
    /// Check if a specific draft is currently being uploaded
    func isUploading(draftID: String) -> Bool {
        return uploadQueue.first == draftID && isProcessingQueue
    }
    
    /// Check if a specific draft is in the queue
    func isQueued(draftID: String) -> Bool {
        return uploadQueue.contains(draftID)
    }
}
