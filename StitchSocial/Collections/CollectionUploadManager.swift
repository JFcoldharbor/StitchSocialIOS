//
//  CollectionUploadManager.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionUploadManager.swift
//  StitchSocial
//
//  Layer 4: Core Services - Background Upload Management
//  Dependencies: Firebase Storage, CollectionDraft, SegmentDraft
//  Features: Background uploads, retry logic, persistence, queue management, progress tracking
//  CREATED: Phase 7 - Collections feature Polish
//

import Foundation
import FirebaseStorage
import Combine
import UIKit

/// Manages background uploads for collection segments
/// Handles queuing, retries, persistence, and progress tracking
@MainActor
class CollectionUploadManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CollectionUploadManager()
    
    // MARK: - Properties
    
    private let storage = Storage.storage()
    private let userDefaults = UserDefaults.standard
    private let maxConcurrentUploads = 2
    private let maxRetryAttempts = 3
    private let retryDelayBase: TimeInterval = 2.0 // Exponential backoff base
    
    // MARK: - Published State
    
    /// All upload tasks (active, queued, completed, failed)
    @Published private(set) var uploadTasks: [SegmentUploadInfo] = []
    
    /// Currently uploading tasks
    @Published private(set) var activeUploads: [String] = []
    
    /// Overall progress across all uploads
    @Published private(set) var overallProgress: Double = 0.0
    
    /// Whether any uploads are in progress
    @Published private(set) var isUploading: Bool = false
    
    /// Network reachability
    @Published private(set) var isNetworkAvailable: Bool = true
    
    // MARK: - Private State
    
    private var uploadOperations: [String: StorageUploadTask] = [:]
    private var retryTimers: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // MARK: - Persistence Keys
    
    private let pendingUploadsKey = "collection_pending_uploads"
    
    // MARK: - Initialization
    
    private init() {
        setupNetworkMonitoring()
        restorePendingUploads()
        
        // Listen for app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        print("📤 UPLOAD MANAGER: Initialized")
    }
    
    // MARK: - Public API
    
    /// Queue a segment for upload
    func queueUpload(
        draftID: String,
        segment: SegmentDraft,
        creatorID: String
    ) {
        guard let localPath = segment.localVideoPath else {
            print("❌ UPLOAD MANAGER: No local path for segment \(segment.id)")
            return
        }
        
        // Check if already queued
        if uploadTasks.contains(where: { $0.segmentID == segment.id }) {
            print("⚠️ UPLOAD MANAGER: Segment \(segment.id) already queued")
            return
        }
        
        let uploadInfo = SegmentUploadInfo(
            id: UUID().uuidString,
            draftID: draftID,
            segmentID: segment.id,
            creatorID: creatorID,
            localVideoPath: localPath,
            localThumbnailPath: segment.thumbnailLocalPath,
            status: .queued,
            progress: 0.0,
            retryCount: 0,
            createdAt: Date()
        )
        
        uploadTasks.append(uploadInfo)
        persistPendingUploads()
        
        print("➕ UPLOAD MANAGER: Queued segment \(segment.id)")
        
        processQueue()
    }
    
    /// Queue multiple segments
    func queueUploads(
        draftID: String,
        segments: [SegmentDraft],
        creatorID: String
    ) {
        for segment in segments {
            queueUpload(draftID: draftID, segment: segment, creatorID: creatorID)
        }
    }
    
    /// Cancel a specific upload
    func cancelUpload(segmentID: String) {
        // Cancel active upload
        if let task = uploadOperations[segmentID] {
            task.cancel()
            uploadOperations.removeValue(forKey: segmentID)
        }
        
        // Cancel retry timer
        retryTimers[segmentID]?.cancel()
        retryTimers.removeValue(forKey: segmentID)
        
        // Remove from active
        activeUploads.removeAll { $0 == segmentID }
        
        // Update status
        if let index = uploadTasks.firstIndex(where: { $0.segmentID == segmentID }) {
            uploadTasks[index].status = .cancelled
        }
        
        persistPendingUploads()
        updateOverallProgress()
        
        print("🚫 UPLOAD MANAGER: Cancelled upload for \(segmentID)")
        
        processQueue()
    }
    
    /// Cancel all uploads for a draft
    func cancelUploads(draftID: String) {
        let segmentsToCancel = uploadTasks.filter { $0.draftID == draftID }
        
        for segment in segmentsToCancel {
            cancelUpload(segmentID: segment.segmentID)
        }
        
        print("🚫 UPLOAD MANAGER: Cancelled all uploads for draft \(draftID)")
    }
    
    /// Cancel all uploads
    func cancelAllUploads() {
        for (segmentID, task) in uploadOperations {
            task.cancel()
            print("🚫 UPLOAD MANAGER: Cancelled \(segmentID)")
        }
        
        uploadOperations.removeAll()
        
        for (_, timer) in retryTimers {
            timer.cancel()
        }
        retryTimers.removeAll()
        
        activeUploads.removeAll()
        
        for index in uploadTasks.indices {
            if uploadTasks[index].status == .uploading || uploadTasks[index].status == .queued {
                uploadTasks[index].status = .cancelled
            }
        }
        
        isUploading = false
        overallProgress = 0
        
        persistPendingUploads()
        
        print("🚫 UPLOAD MANAGER: Cancelled all uploads")
    }
    
    /// Retry a failed upload
    func retryUpload(segmentID: String) {
        guard let index = uploadTasks.firstIndex(where: { $0.segmentID == segmentID }) else {
            return
        }
        
        uploadTasks[index].status = .queued
        uploadTasks[index].retryCount = 0
        uploadTasks[index].error = nil
        
        persistPendingUploads()
        processQueue()
        
        print("🔄 UPLOAD MANAGER: Retrying upload for \(segmentID)")
    }
    
    /// Retry all failed uploads
    func retryAllFailed() {
        for index in uploadTasks.indices {
            if uploadTasks[index].status == .failed {
                uploadTasks[index].status = .queued
                uploadTasks[index].retryCount = 0
                uploadTasks[index].error = nil
            }
        }
        
        persistPendingUploads()
        processQueue()
        
        print("🔄 UPLOAD MANAGER: Retrying all failed uploads")
    }
    
    /// Get upload info for a segment
    func getUploadInfo(segmentID: String) -> SegmentUploadInfo? {
        return uploadTasks.first { $0.segmentID == segmentID }
    }
    
    /// Get all uploads for a draft
    func getUploads(draftID: String) -> [SegmentUploadInfo] {
        return uploadTasks.filter { $0.draftID == draftID }
    }
    
    /// Clear completed uploads
    func clearCompleted() {
        uploadTasks.removeAll { $0.status == .completed }
        persistPendingUploads()
    }
    
    /// Clear all uploads for a draft (after publishing or deletion)
    func clearUploads(draftID: String) {
        // Cancel any active uploads first
        cancelUploads(draftID: draftID)
        
        // Remove from list
        uploadTasks.removeAll { $0.draftID == draftID }
        persistPendingUploads()
        
        print("🗑️ UPLOAD MANAGER: Cleared uploads for draft \(draftID)")
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        guard isNetworkAvailable else {
            print("⏸️ UPLOAD MANAGER: Network unavailable, pausing queue")
            return
        }
        
        // Count active uploads
        let activeCount = activeUploads.count
        
        guard activeCount < maxConcurrentUploads else {
            return
        }
        
        // Find next queued upload
        let queuedUploads = uploadTasks.filter { $0.status == .queued }
        let slotsAvailable = maxConcurrentUploads - activeCount
        
        for upload in queuedUploads.prefix(slotsAvailable) {
            startUpload(upload)
        }
        
        updateOverallProgress()
    }
    
    private func startUpload(_ uploadInfo: SegmentUploadInfo) {
        guard let index = uploadTasks.firstIndex(where: { $0.id == uploadInfo.id }) else {
            return
        }
        
        // Begin background task
        beginBackgroundTask()
        
        // Update status
        uploadTasks[index].status = .uploading
        uploadTasks[index].startedAt = Date()
        activeUploads.append(uploadInfo.segmentID)
        isUploading = true
        
        // Create storage path
        let videoPath = "collections/\(uploadInfo.creatorID)/\(uploadInfo.draftID)/\(uploadInfo.segmentID).mp4"
        let videoRef = storage.reference().child(videoPath)
        
        // Get local file URL
        let localURL = URL(fileURLWithPath: uploadInfo.localVideoPath)
        
        // Create upload task
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        let uploadTask = videoRef.putFile(from: localURL, metadata: metadata)
        uploadOperations[uploadInfo.segmentID] = uploadTask
        
        // Observe progress
        uploadTask.observe(.progress) { [weak self] snapshot in
            Task { @MainActor in
                guard let self = self,
                      let progress = snapshot.progress else { return }
                
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                
                if let idx = self.uploadTasks.firstIndex(where: { $0.segmentID == uploadInfo.segmentID }) {
                    self.uploadTasks[idx].progress = percentComplete
                }
                
                self.updateOverallProgress()
            }
        }
        
        // Observe completion
        uploadTask.observe(.success) { [weak self] snapshot in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Get download URL
                do {
                    let downloadURL = try await videoRef.downloadURL()
                    
                    // Upload thumbnail if exists
                    var thumbnailURL: String? = nil
                    if let thumbnailPath = uploadInfo.localThumbnailPath {
                        thumbnailURL = try await self.uploadThumbnail(
                            localPath: thumbnailPath,
                            creatorID: uploadInfo.creatorID,
                            draftID: uploadInfo.draftID,
                            segmentID: uploadInfo.segmentID
                        )
                    }
                    
                    self.completeUpload(
                        segmentID: uploadInfo.segmentID,
                        videoURL: downloadURL.absoluteString,
                        thumbnailURL: thumbnailURL
                    )
                    
                } catch {
                    self.failUpload(segmentID: uploadInfo.segmentID, error: error)
                }
            }
        }
        
        // Observe failure
        uploadTask.observe(.failure) { [weak self] snapshot in
            Task { @MainActor in
                guard let self = self else { return }
                
                let error = snapshot.error ?? NSError(domain: "UploadError", code: -1)
                self.failUpload(segmentID: uploadInfo.segmentID, error: error)
            }
        }
        
        print("🚀 UPLOAD MANAGER: Started upload for \(uploadInfo.segmentID)")
    }
    
    private func uploadThumbnail(
        localPath: String,
        creatorID: String,
        draftID: String,
        segmentID: String
    ) async throws -> String {
        let thumbnailPath = "collections/\(creatorID)/\(draftID)/thumbnails/\(segmentID).jpg"
        let thumbnailRef = storage.reference().child(thumbnailPath)
        
        let localURL = URL(fileURLWithPath: localPath)
        let data = try Data(contentsOf: localURL)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await thumbnailRef.putDataAsync(data, metadata: metadata)
        let downloadURL = try await thumbnailRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    private func completeUpload(segmentID: String, videoURL: String, thumbnailURL: String?) {
        // Remove from active
        activeUploads.removeAll { $0 == segmentID }
        uploadOperations.removeValue(forKey: segmentID)
        
        // Update status
        if let index = uploadTasks.firstIndex(where: { $0.segmentID == segmentID }) {
            uploadTasks[index].status = .completed
            uploadTasks[index].progress = 1.0
            uploadTasks[index].completedAt = Date()
            uploadTasks[index].uploadedVideoURL = videoURL
            uploadTasks[index].uploadedThumbnailURL = thumbnailURL
        }
        
        persistPendingUploads()
        updateOverallProgress()
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .segmentUploadCompleted,
            object: nil,
            userInfo: [
                "segmentID": segmentID,
                "videoURL": videoURL,
                "thumbnailURL": thumbnailURL as Any
            ]
        )
        
        print("✅ UPLOAD MANAGER: Completed upload for \(segmentID)")
        
        // Process next in queue
        processQueue()
        
        // End background task if no more uploads
        if activeUploads.isEmpty {
            endBackgroundTask()
        }
    }
    
    private func failUpload(segmentID: String, error: Error) {
        // Remove from active
        activeUploads.removeAll { $0 == segmentID }
        uploadOperations.removeValue(forKey: segmentID)
        
        guard let index = uploadTasks.firstIndex(where: { $0.segmentID == segmentID }) else {
            return
        }
        
        let uploadInfo = uploadTasks[index]
        
        // Check if should retry
        if uploadInfo.retryCount < maxRetryAttempts && isRetryableError(error) {
            // Schedule retry with exponential backoff
            let delay = retryDelayBase * pow(2.0, Double(uploadInfo.retryCount))
            
            uploadTasks[index].status = .retrying
            uploadTasks[index].retryCount += 1
            uploadTasks[index].error = error.localizedDescription
            
            print("⏳ UPLOAD MANAGER: Scheduling retry \(uploadInfo.retryCount + 1)/\(maxRetryAttempts) for \(segmentID) in \(delay)s")
            
            let retryTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    if let idx = self.uploadTasks.firstIndex(where: { $0.segmentID == segmentID }) {
                        self.uploadTasks[idx].status = .queued
                    }
                    self.processQueue()
                }
            }
            
            retryTimers[segmentID] = retryTask
            
        } else {
            // Max retries reached or non-retryable error
            uploadTasks[index].status = .failed
            uploadTasks[index].error = error.localizedDescription
            
            // Post notification
            NotificationCenter.default.post(
                name: .segmentUploadFailed,
                object: nil,
                userInfo: [
                    "segmentID": segmentID,
                    "error": error.localizedDescription
                ]
            )
            
            print("❌ UPLOAD MANAGER: Failed upload for \(segmentID): \(error.localizedDescription)")
        }
        
        persistPendingUploads()
        updateOverallProgress()
        
        // Process next in queue
        processQueue()
        
        // End background task if no more uploads
        if activeUploads.isEmpty {
            endBackgroundTask()
        }
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Network errors are retryable
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        
        // Storage errors
        if let storageError = error as? StorageError {
            switch storageError {
            case .retryLimitExceeded, .unknown:
                return true
            default:
                return false
            }
        }
        
        return true // Default to retryable
    }
    
    // MARK: - Progress Tracking
    
    private func updateOverallProgress() {
        let activeAndQueued = uploadTasks.filter {
            $0.status == .uploading || $0.status == .queued || $0.status == .retrying
        }
        
        guard !activeAndQueued.isEmpty else {
            overallProgress = uploadTasks.contains(where: { $0.status == .completed }) ? 1.0 : 0.0
            isUploading = false
            return
        }
        
        let totalProgress = activeAndQueued.reduce(0.0) { $0 + $1.progress }
        overallProgress = totalProgress / Double(activeAndQueued.count)
        isUploading = true
    }
    
    // MARK: - Persistence
    
    private func persistPendingUploads() {
        let pendingUploads = uploadTasks.filter {
            $0.status == .queued || $0.status == .uploading || $0.status == .retrying || $0.status == .failed
        }
        
        do {
            let data = try JSONEncoder().encode(pendingUploads)
            userDefaults.set(data, forKey: pendingUploadsKey)
        } catch {
            print("❌ UPLOAD MANAGER: Failed to persist uploads: \(error)")
        }
    }
    
    private func restorePendingUploads() {
        guard let data = userDefaults.data(forKey: pendingUploadsKey),
              let uploads = try? JSONDecoder().decode([SegmentUploadInfo].self, from: data) else {
            return
        }
        
        // Reset uploading status to queued (app was killed)
        uploadTasks = uploads.map { upload in
            var restored = upload
            if restored.status == .uploading || restored.status == .retrying {
                restored.status = .queued
            }
            return restored
        }
        
        print("📥 UPLOAD MANAGER: Restored \(uploadTasks.count) pending uploads")
        
        // Resume processing
        processQueue()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        // Simplified - in production use NWPathMonitor
        isNetworkAvailable = true
        
        // Would monitor network changes and pause/resume queue
    }
    
    // MARK: - Background Task
    
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        print("🔄 UPLOAD MANAGER: Started background task")
    }
    
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        
        print("✓ UPLOAD MANAGER: Ended background task")
    }
    
    // MARK: - App Lifecycle
    
    @objc private func appWillResignActive() {
        // Persist state
        persistPendingUploads()
        
        // Begin background task to continue uploads
        if !activeUploads.isEmpty {
            beginBackgroundTask()
        }
    }
    
    @objc private func appDidBecomeActive() {
        // Resume queue processing
        processQueue()
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Upload Info Model

/// Information about a segment upload
struct SegmentUploadInfo: Identifiable, Codable {
    let id: String
    let draftID: String
    let segmentID: String
    let creatorID: String
    let localVideoPath: String
    let localThumbnailPath: String?
    
    var status: UploadStatus
    var progress: Double
    var retryCount: Int
    var error: String?
    
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    
    var uploadedVideoURL: String?
    var uploadedThumbnailURL: String?
    
    /// Formatted progress percentage
    var progressPercentage: String {
        return String(format: "%.0f%%", progress * 100)
    }
    
    /// Time elapsed since start
    var elapsedTime: TimeInterval? {
        guard let startedAt = startedAt else { return nil }
        return Date().timeIntervalSince(startedAt)
    }
    
    /// Whether upload can be retried
    var canRetry: Bool {
        return status == .failed || status == .cancelled
    }
    
    /// Whether upload can be cancelled
    var canCancel: Bool {
        return status == .queued || status == .uploading || status == .retrying
    }
}

/// Upload status
enum UploadStatus: String, Codable {
    case queued = "queued"
    case uploading = "uploading"
    case retrying = "retrying"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .uploading: return "Uploading"
        case .retrying: return "Retrying"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var iconName: String {
        switch self {
        case .queued: return "clock"
        case .uploading: return "arrow.up.circle"
        case .retrying: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .queued: return "secondary"
        case .uploading: return "blue"
        case .retrying: return "orange"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }
}

// MARK: - Storage Error Extension

enum StorageError: Error {
    case retryLimitExceeded
    case unknown
    case cancelled
    case unauthorized
    case quotaExceeded
}
