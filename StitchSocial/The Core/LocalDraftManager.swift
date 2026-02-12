//
//  LocalDraftManager.swift
//  StitchSocial
//
//  Created by James Garmon on 12/14/25.
//


//
//  LocalDraftManager.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Local Draft Management
//  Dependencies: VideoEditState (Layer 3)
//  Features: Save/load drafts locally, auto-save, cleanup
//

import Foundation

/// Manages local video drafts before they're posted
@MainActor
class LocalDraftManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LocalDraftManager()
    
    // MARK: - Published State
    
    @Published var drafts: [VideoEditState] = []
    @Published var isLoading = false
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private let draftsDirectory: URL
    private let maxDrafts = 10
    private let maxDraftAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    // MARK: - Initialization
    
    private init() {
        // Create drafts directory in app's documents
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        draftsDirectory = documentsURL.appendingPathComponent("VideoEditDrafts", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
        
        // Load existing drafts
        Task {
            await loadDrafts()
        }
        
        print("ðŸ“ DRAFT MANAGER: Initialized at \(draftsDirectory.path)")
    }
    
    // MARK: - Public Interface
    
    /// Save draft to disk
    func saveDraft(_ editState: VideoEditState) async throws {
        let draftURL = draftFileURL(for: editState.draftID)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(editState)
        try data.write(to: draftURL)
        
        // Update in-memory list
        if let index = drafts.firstIndex(where: { $0.draftID == editState.draftID }) {
            drafts[index] = editState
        } else {
            drafts.append(editState)
            
            // Enforce max drafts limit
            if drafts.count > maxDrafts {
                // Remove oldest draft
                if let oldestDraft = drafts.min(by: { $0.lastModified < $1.lastModified }) {
                    try? await deleteDraft(id: oldestDraft.draftID)
                }
            }
        }
        
        print("ðŸ’¾ DRAFT MANAGER: Saved draft \(editState.draftID)")
    }
    
    /// Auto-save draft (debounced)
    func autoSaveDraft(_ editState: VideoEditState) {
        Task {
            // Small delay to avoid excessive saves
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            try? await saveDraft(editState)
        }
    }
    
    /// Load specific draft
    func loadDraft(id: String) async throws -> VideoEditState? {
        let draftURL = draftFileURL(for: id)
        
        guard fileManager.fileExists(atPath: draftURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: draftURL)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let draft = try decoder.decode(VideoEditState.self, from: data)
        return draft
    }
    
    /// Delete draft
    func deleteDraft(id: String) async throws {
        let draftURL = draftFileURL(for: id)
        
        // Delete file
        try? fileManager.removeItem(at: draftURL)
        
        // Remove from memory
        drafts.removeAll { $0.draftID == id }
        
        print("ðŸ—‘ï¸ DRAFT MANAGER: Deleted draft \(id)")
    }
    
    /// Load all drafts from disk
    func loadDrafts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: draftsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            var loadedDrafts: [VideoEditState] = []
            
            for fileURL in files where fileURL.pathExtension == "draft" {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let draft = try decoder.decode(VideoEditState.self, from: data)
                    
                    // Check if draft is too old
                    if Date().timeIntervalSince(draft.lastModified) < maxDraftAge {
                        loadedDrafts.append(draft)
                    } else {
                        // Delete old draft
                        try? fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    print("âš ï¸ DRAFT MANAGER: Failed to load draft from \(fileURL.lastPathComponent): \(error)")
                }
            }
            
            // Sort by last modified (newest first)
            loadedDrafts.sort { $0.lastModified > $1.lastModified }
            
            drafts = loadedDrafts
            
            print("ðŸ“‚ DRAFT MANAGER: Loaded \(drafts.count) drafts")
            
        } catch {
            print("âŒ DRAFT MANAGER: Failed to load drafts: \(error)")
        }
    }
    
    /// Clean up old drafts and orphaned video files
    func cleanupOldDrafts() async {
        var deletedCount = 0
        
        for draft in drafts {
            // Delete if too old
            if Date().timeIntervalSince(draft.lastModified) > maxDraftAge {
                try? await deleteDraft(id: draft.draftID)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            print("ðŸ§¹ DRAFT MANAGER: Cleaned up \(deletedCount) old drafts")
        }
    }
    
    /// Get draft by ID from memory
    func getDraft(id: String) -> VideoEditState? {
        return drafts.first { $0.draftID == id }
    }
    
    // MARK: - 🆕 Upload Status Queries
    
    /// Drafts that haven't been submitted for upload yet
    var pendingDrafts: [VideoEditState] {
        drafts.filter { $0.uploadStatus == DraftUploadStatus.draft }
    }
    
    /// Drafts that failed to upload and can be retried
    var failedUploads: [VideoEditState] {
        drafts.filter { $0.uploadStatus == DraftUploadStatus.failed }
    }
    
    /// Drafts currently uploading in background
    var activeUploads: [VideoEditState] {
        drafts.filter { $0.uploadStatus == DraftUploadStatus.uploading }
    }
    
    /// Drafts queued and waiting to upload
    var queuedUploads: [VideoEditState] {
        drafts.filter { $0.uploadStatus == DraftUploadStatus.readyToUpload }
    }
    
    /// All drafts that are not yet complete (shown in drafts UI)
    var incompleteDrafts: [VideoEditState] {
        drafts.filter { $0.uploadStatus != DraftUploadStatus.complete }
    }
    
    /// Total count for badge display
    var draftsBadgeCount: Int {
        incompleteDrafts.count
    }
    
    /// Whether there are any failed uploads needing attention
    var hasFailedUploads: Bool {
        !failedUploads.isEmpty
    }
    
    /// Update upload status for a specific draft
    func markUploadStatus(draftID: String, status: DraftUploadStatus, errorMessage: String? = nil) async {
        guard let index = drafts.firstIndex(where: { $0.draftID == draftID }) else { return }
        
        switch status {
        case .uploading:
            drafts[index].markUploading()
        case .failed:
            drafts[index].markUploadFailed(error: errorMessage ?? "Unknown error")
        case .complete:
            drafts[index].markUploadComplete()
        default:
            drafts[index].uploadStatus = status
            drafts[index].lastModified = Date()
        }
        
        // Persist to disk
        try? await saveDraft(drafts[index])
        
        print("📋 DRAFT MANAGER: Updated \(draftID.prefix(8)) status → \(status.displayName)")
    }
    
    /// Find drafts that were interrupted mid-upload (app was killed)
    /// Called on app launch to re-queue them
    func recoverInterruptedUploads() -> [VideoEditState] {
        let interrupted = drafts.filter { $0.uploadStatus == DraftUploadStatus.uploading || $0.uploadStatus == DraftUploadStatus.readyToUpload }
        
        if !interrupted.isEmpty {
            print("🔄 DRAFT MANAGER: Found \(interrupted.count) interrupted uploads to recover")
        }
        
        return interrupted
    }
    
    /// Remove completed drafts (cleanup after successful upload)
    func cleanupCompletedUploads() async {
        let completed = drafts.filter { $0.uploadStatus == .complete }
        
        for draft in completed {
            try? await deleteDraft(id: draft.draftID)
        }
        
        if !completed.isEmpty {
            print("🧹 DRAFT MANAGER: Cleaned up \(completed.count) completed uploads")
        }
    }
    
    // MARK: - Private Helpers
    
    private func draftFileURL(for draftID: String) -> URL {
        return draftsDirectory.appendingPathComponent("\(draftID).draft")
    }
}

// MARK: - Draft List Item (for UI)

struct DraftListItem: Identifiable {
    let id: String
    let thumbnailURL: URL?
    let duration: TimeInterval
    let lastModified: Date
    let isProcessing: Bool
    
    init(from editState: VideoEditState) {
        self.id = editState.draftID
        self.thumbnailURL = editState.processedThumbnailURL
        self.duration = editState.trimmedDuration
        self.lastModified = editState.lastModified
        self.isProcessing = editState.isProcessing
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
}
