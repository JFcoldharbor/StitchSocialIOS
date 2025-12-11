//
//  SegmentUploadStatus.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionDraft.swift
//  StitchSocial
//
//  Layer 1: Foundation - Collection Draft Data Models
//  Dependencies: Foundation only
//  Handles draft state during collection creation, segment uploads, and auto-save
//  Critical for preventing data loss during multi-segment uploads
//  CREATED: Collections feature for long-form segmented content
//

import Foundation

// MARK: - Segment Upload Status

/// Upload status for individual segments within a collection draft
enum SegmentUploadStatus: String, CaseIterable, Codable {
    case pending = "pending"           // Not yet started
    case uploading = "uploading"       // Currently uploading
    case processing = "processing"     // Upload complete, processing thumbnail/metadata
    case complete = "complete"         // Fully ready
    case failed = "failed"             // Upload failed
    case cancelled = "cancelled"       // User cancelled
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .uploading: return "Uploading"
        case .processing: return "Processing"
        case .complete: return "Complete"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var isInProgress: Bool {
        return self == .uploading || self == .processing
    }
    
    var isComplete: Bool {
        return self == .complete
    }
    
    var canRetry: Bool {
        return self == .failed || self == .cancelled
    }
    
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle"
        case .processing: return "gearshape"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Segment Draft

/// Individual segment within a collection draft
/// Tracks local file, upload progress, and metadata during creation
struct SegmentDraft: Identifiable, Codable, Hashable {
    
    // MARK: - Identity
    
    let id: String
    
    /// Position in collection (1-based for display, 0-based internally)
    var order: Int
    
    // MARK: - Video Files
    
    /// Local file path (before upload)
    var localVideoPath: String?
    
    /// Firebase Storage URL (after upload)
    var uploadedVideoURL: String?
    
    /// Local thumbnail path
    var thumbnailLocalPath: String?
    
    /// Firebase Storage thumbnail URL
    var thumbnailURL: String?
    
    // MARK: - Upload State
    
    /// Upload progress (0.0 to 1.0)
    var uploadProgress: Double
    
    /// Current upload status
    var uploadStatus: SegmentUploadStatus
    
    /// Error message if upload failed
    var uploadError: String?
    
    /// Upload task identifier for cancellation
    var uploadTaskID: String?
    
    // MARK: - Metadata
    
    /// Segment title (optional, can be set by user)
    var title: String?
    
    /// Segment description (optional)
    var description: String?
    
    /// Video duration in seconds
    var duration: TimeInterval?
    
    /// Video file size in bytes
    var fileSize: Int64?
    
    /// Video aspect ratio
    var aspectRatio: Double?
    
    // MARK: - Timestamps
    
    var addedAt: Date
    var uploadStartedAt: Date?
    var uploadCompletedAt: Date?
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        order: Int,
        localVideoPath: String? = nil,
        uploadedVideoURL: String? = nil,
        thumbnailLocalPath: String? = nil,
        thumbnailURL: String? = nil,
        uploadProgress: Double = 0.0,
        uploadStatus: SegmentUploadStatus = .pending,
        uploadError: String? = nil,
        uploadTaskID: String? = nil,
        title: String? = nil,
        description: String? = nil,
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        aspectRatio: Double? = nil,
        addedAt: Date = Date(),
        uploadStartedAt: Date? = nil,
        uploadCompletedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.localVideoPath = localVideoPath
        self.uploadedVideoURL = uploadedVideoURL
        self.thumbnailLocalPath = thumbnailLocalPath
        self.thumbnailURL = thumbnailURL
        self.uploadProgress = uploadProgress
        self.uploadStatus = uploadStatus
        self.uploadError = uploadError
        self.uploadTaskID = uploadTaskID
        self.title = title
        self.description = description
        self.duration = duration
        self.fileSize = fileSize
        self.aspectRatio = aspectRatio
        self.addedAt = addedAt
        self.uploadStartedAt = uploadStartedAt
        self.uploadCompletedAt = uploadCompletedAt
    }
    
    // MARK: - Computed Properties
    
    /// True if segment has a local video ready for upload
    var hasLocalVideo: Bool {
        return localVideoPath != nil
    }
    
    /// True if segment has been fully uploaded
    var isUploaded: Bool {
        return uploadStatus == .complete && uploadedVideoURL != nil
    }
    
    /// True if segment can be uploaded
    var canUpload: Bool {
        return hasLocalVideo && (uploadStatus == .pending || uploadStatus == .failed || uploadStatus == .cancelled)
    }
    
    /// Display title (falls back to "Part X")
    var displayTitle: String {
        return title ?? "Part \(order + 1)"
    }
    
    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formatted file size
    var formattedFileSize: String? {
        guard let fileSize = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Upload progress as percentage string
    var progressPercentage: String {
        return String(format: "%.0f%%", uploadProgress * 100)
    }
    
    /// Time since added
    var timeSinceAdded: TimeInterval {
        return Date().timeIntervalSince(addedAt)
    }
    
    // MARK: - Hashable & Equatable
    
    static func == (lhs: SegmentDraft, rhs: SegmentDraft) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Segment Draft Update Methods

extension SegmentDraft {
    
    /// Creates a copy with updated upload progress
    func withUploadProgress(_ progress: Double, status: SegmentUploadStatus? = nil) -> SegmentDraft {
        var copy = self
        copy.uploadProgress = progress
        if let status = status {
            copy.uploadStatus = status
        }
        if progress > 0 && uploadStartedAt == nil {
            copy.uploadStartedAt = Date()
        }
        if progress >= 1.0 && status == .complete {
            copy.uploadCompletedAt = Date()
        }
        return copy
    }
    
    /// Creates a copy marked as upload failed
    func withUploadError(_ error: String) -> SegmentDraft {
        var copy = self
        copy.uploadStatus = .failed
        copy.uploadError = error
        return copy
    }
    
    /// Creates a copy with uploaded URL
    func withUploadedURL(_ url: String, thumbnailURL: String? = nil) -> SegmentDraft {
        var copy = self
        copy.uploadedVideoURL = url
        if let thumbnailURL = thumbnailURL {
            copy.thumbnailURL = thumbnailURL
        }
        copy.uploadStatus = .complete
        copy.uploadProgress = 1.0
        copy.uploadCompletedAt = Date()
        copy.uploadError = nil
        return copy
    }
    
    /// Creates a copy with updated metadata
    func withMetadata(
        title: String? = nil,
        description: String? = nil,
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        aspectRatio: Double? = nil
    ) -> SegmentDraft {
        var copy = self
        if let title = title { copy.title = title }
        if let description = description { copy.description = description }
        if let duration = duration { copy.duration = duration }
        if let fileSize = fileSize { copy.fileSize = fileSize }
        if let aspectRatio = aspectRatio { copy.aspectRatio = aspectRatio }
        return copy
    }
    
    /// Creates a copy with updated order
    func withOrder(_ newOrder: Int) -> SegmentDraft {
        var copy = self
        copy.order = newOrder
        return copy
    }
    
    /// Resets upload state for retry
    func resetForRetry() -> SegmentDraft {
        var copy = self
        copy.uploadProgress = 0.0
        copy.uploadStatus = .pending
        copy.uploadError = nil
        copy.uploadStartedAt = nil
        copy.uploadCompletedAt = nil
        copy.uploadTaskID = nil
        return copy
    }
}

// MARK: - Collection Draft

/// Complete draft state for a collection being created
/// Persisted locally for auto-save and recovery
struct CollectionDraft: Identifiable, Codable {
    
    // MARK: - Identity
    
    let id: String
    let creatorID: String
    
    // MARK: - Metadata
    
    var title: String?
    var description: String?
    var coverImageURL: String?
    var coverImageLocalPath: String?
    
    // MARK: - Settings
    
    var visibility: CollectionVisibility
    var allowReplies: Bool
    
    // MARK: - Segments
    
    var segments: [SegmentDraft]
    
    // MARK: - Timestamps
    
    let createdAt: Date
    var lastModifiedAt: Date
    var autoSavedAt: Date
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        creatorID: String,
        title: String? = nil,
        description: String? = nil,
        coverImageURL: String? = nil,
        coverImageLocalPath: String? = nil,
        visibility: CollectionVisibility = .publicVisible,
        allowReplies: Bool = true,
        segments: [SegmentDraft] = [],
        createdAt: Date = Date(),
        lastModifiedAt: Date = Date(),
        autoSavedAt: Date = Date()
    ) {
        self.id = id
        self.creatorID = creatorID
        self.title = title
        self.description = description
        self.coverImageURL = coverImageURL
        self.coverImageLocalPath = coverImageLocalPath
        self.visibility = visibility
        self.allowReplies = allowReplies
        self.segments = segments
        self.createdAt = createdAt
        self.lastModifiedAt = lastModifiedAt
        self.autoSavedAt = autoSavedAt
    }
    
    // MARK: - Computed Properties
    
    /// True if draft has required title
    var hasTitle: Bool {
        guard let title = title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// True if all segments are uploaded
    var allSegmentsUploaded: Bool {
        return !segments.isEmpty && segments.allSatisfy { $0.isUploaded }
    }
    
    /// True if draft meets minimum requirements for publishing
    var isComplete: Bool {
        return hasTitle && segments.count >= 2 && allSegmentsUploaded
    }
    
    /// True if draft can be published
    var canPublish: Bool {
        return isComplete
    }
    
    /// Number of segments that have been uploaded
    var uploadedSegmentCount: Int {
        return segments.filter { $0.isUploaded }.count
    }
    
    /// Number of segments currently uploading
    var uploadingSegmentCount: Int {
        return segments.filter { $0.uploadStatus == .uploading || $0.uploadStatus == .processing }.count
    }
    
    /// Number of segments that failed to upload
    var failedSegmentCount: Int {
        return segments.filter { $0.uploadStatus == .failed }.count
    }
    
    /// Overall upload progress (0.0 to 1.0)
    var overallUploadProgress: Double {
        guard !segments.isEmpty else { return 0.0 }
        let totalProgress = segments.reduce(0.0) { $0 + $1.uploadProgress }
        return totalProgress / Double(segments.count)
    }
    
    /// Total duration of all segments
    var totalDuration: TimeInterval {
        return segments.compactMap { $0.duration }.reduce(0, +)
    }
    
    /// Total file size of all segments
    var totalFileSize: Int64 {
        return segments.compactMap { $0.fileSize }.reduce(0, +)
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
    
    /// Formatted total file size
    var formattedTotalFileSize: String {
        return ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
    
    /// Progress display string (e.g., "3/5 segments uploaded")
    var progressDisplayString: String {
        return "\(uploadedSegmentCount)/\(segments.count) segments uploaded"
    }
    
    /// Time since last modification
    var timeSinceModified: TimeInterval {
        return Date().timeIntervalSince(lastModifiedAt)
    }
    
    /// Time since creation
    var timeSinceCreated: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }
    
    /// Days since last activity (for expiration check)
    var daysSinceActivity: Int {
        return Int(timeSinceModified / (24 * 60 * 60))
    }
    
    /// True if draft should be auto-deleted (30 days inactive)
    var isExpired: Bool {
        return daysSinceActivity >= 30
    }
    
    /// Segments sorted by order
    var sortedSegments: [SegmentDraft] {
        return segments.sorted { $0.order < $1.order }
    }
}

// MARK: - Collection Draft Update Methods

extension CollectionDraft {
    
    /// Creates a copy with updated metadata
    mutating func updateMetadata(
        title: String? = nil,
        description: String? = nil,
        visibility: CollectionVisibility? = nil,
        allowReplies: Bool? = nil
    ) {
        if let title = title { self.title = title }
        if let description = description { self.description = description }
        if let visibility = visibility { self.visibility = visibility }
        if let allowReplies = allowReplies { self.allowReplies = allowReplies }
        self.lastModifiedAt = Date()
    }
    
    /// Adds a new segment to the draft
    mutating func addSegment(_ segment: SegmentDraft) {
        var newSegment = segment
        newSegment.order = segments.count
        segments.append(newSegment)
        lastModifiedAt = Date()
    }
    
    /// Removes a segment by ID
    mutating func removeSegment(id: String) {
        segments.removeAll { $0.id == id }
        // Reorder remaining segments
        for (index, _) in segments.enumerated() {
            segments[index].order = index
        }
        lastModifiedAt = Date()
    }
    
    /// Updates a segment in place
    mutating func updateSegment(_ updatedSegment: SegmentDraft) {
        if let index = segments.firstIndex(where: { $0.id == updatedSegment.id }) {
            segments[index] = updatedSegment
            lastModifiedAt = Date()
        }
    }
    
    /// Reorders segments
    mutating func reorderSegments(_ newOrder: [String]) {
        var reorderedSegments: [SegmentDraft] = []
        for (index, segmentID) in newOrder.enumerated() {
            if var segment = segments.first(where: { $0.id == segmentID }) {
                segment.order = index
                reorderedSegments.append(segment)
            }
        }
        segments = reorderedSegments
        lastModifiedAt = Date()
    }
    
    /// Moves segment from one position to another
    mutating func moveSegment(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < segments.count,
              destinationIndex >= 0, destinationIndex < segments.count else {
            return
        }
        
        let segment = segments.remove(at: sourceIndex)
        segments.insert(segment, at: destinationIndex)
        
        // Update order for all segments
        for (index, _) in segments.enumerated() {
            segments[index].order = index
        }
        lastModifiedAt = Date()
    }
    
    /// Marks auto-save timestamp
    mutating func markAutoSaved() {
        autoSavedAt = Date()
    }
    
    /// Gets segment by ID
    func segment(withID id: String) -> SegmentDraft? {
        return segments.first { $0.id == id }
    }
    
    /// Gets segment by order
    func segment(at order: Int) -> SegmentDraft? {
        return segments.first { $0.order == order }
    }
}

// MARK: - Validation

extension CollectionDraft {
    
    /// Validation result
    struct ValidationResult {
        let isValid: Bool
        let errors: [String]
        let warnings: [String]
        
        static let valid = ValidationResult(isValid: true, errors: [], warnings: [])
        
        static func invalid(_ errors: [String], warnings: [String] = []) -> ValidationResult {
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
    }
    
    /// Validates draft for publishing
    func validateForPublishing() -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Required: Title
        if !hasTitle {
            errors.append("Title is required")
        } else if let title = title, title.count > 100 {
            errors.append("Title must be 100 characters or less")
        }
        
        // Optional but validated: Description
        if let description = description, description.count > 500 {
            errors.append("Description must be 500 characters or less")
        }
        
        // Required: Minimum segments
        if segments.count < 2 {
            errors.append("Collection must have at least 2 segments")
        }
        
        // Maximum segments
        if segments.count > 50 {
            errors.append("Collection cannot have more than 50 segments")
        }
        
        // All segments must be uploaded
        let pendingSegments = segments.filter { !$0.isUploaded }
        if !pendingSegments.isEmpty {
            errors.append("\(pendingSegments.count) segment(s) still uploading")
        }
        
        // Check for failed uploads
        let failedSegments = segments.filter { $0.uploadStatus == .failed }
        if !failedSegments.isEmpty {
            errors.append("\(failedSegments.count) segment(s) failed to upload")
        }
        
        // Warnings (non-blocking)
        if description == nil || description?.isEmpty == true {
            warnings.append("Adding a description helps viewers find your content")
        }
        
        if coverImageURL == nil && coverImageLocalPath == nil {
            warnings.append("Consider adding a cover image")
        }
        
        // Check segment durations
        for segment in segments {
            if let duration = segment.duration, duration > 300 {
                errors.append("Segment '\(segment.displayTitle)' exceeds 5 minute limit")
            }
            if let duration = segment.duration, duration < 10 {
                warnings.append("Segment '\(segment.displayTitle)' is very short")
            }
        }
        
        return errors.isEmpty ? .valid : .invalid(errors, warnings: warnings)
    }
}

// MARK: - Local Storage Keys

extension CollectionDraft {
    
    /// Key for storing draft in UserDefaults/local storage
    var storageKey: String {
        return "collection_draft_\(id)"
    }
    
    /// Key prefix for all drafts by a user
    static func storageKeyPrefix(for userID: String) -> String {
        return "collection_draft_user_\(userID)"
    }
}