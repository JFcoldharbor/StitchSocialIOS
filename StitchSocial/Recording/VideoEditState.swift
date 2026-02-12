//
//  VideoEditState.swift
//  StitchSocial
//
//  Layer 3: State Management - Video Edit State During Review
//  Dependencies: Foundation, AVFoundation
//  Features: Tracks trim, filter, caption state before posting
//
//  ðŸ”§ UPDATED: Added compression state tracking
//  ðŸ”§ UPDATED: Better trim detection (checks both start AND end)
//  ðŸ”§ UPDATED: Added finalVideoURL that prefers compressed/processed
//

import Foundation
import AVFoundation

/// Represents the complete edit state of a video in review
struct VideoEditState: Codable {
    
    // MARK: - Video Source
    
    let videoURL: URL
    let videoDuration: TimeInterval
    let videoSize: CGSize
    let createdAt: Date
    
    // MARK: - Trim State
    
    var trimStartTime: TimeInterval
    var trimEndTime: TimeInterval
    
    var trimmedDuration: TimeInterval {
        trimEndTime - trimStartTime
    }
    
    var trimRange: ClosedRange<TimeInterval> {
        trimStartTime...trimEndTime
    }
    
    // MARK: - Filter State
    
    var selectedFilter: VideoFilter?
    var filterIntensity: Double // 0.0 to 1.0
    
    // MARK: - Caption State
    
    var captions: [VideoCaption]
    
    // MARK: - Processing State
    
    var isProcessing: Bool
    var processingProgress: Double // 0.0 to 1.0
    var processedVideoURL: URL?
    var processedThumbnailURL: URL?
    
    // MARK: - Compression State
    
    var compressedVideoURL: URL?
    var compressionComplete: Bool
    var compressionProgress: Double
    var originalFileSize: Int64
    var compressedFileSize: Int64
    
    // MARK: - Draft State
    
    var draftID: String
    var lastModified: Date
    
    // MARK: - 🆕 Upload State (for background upload system)
    
    var uploadStatus: DraftUploadStatus
    var uploadMetadata: PersistedUploadMetadata?
    var uploadContext: PersistedRecordingContext?
    var uploadErrorMessage: String?
    var uploadAttemptCount: Int
    
    // MARK: - Initialization
    
    init(
        videoURL: URL,
        videoDuration: TimeInterval,
        videoSize: CGSize,
        draftID: String = UUID().uuidString
    ) {
        self.videoURL = videoURL
        self.videoDuration = videoDuration
        self.videoSize = videoSize
        self.createdAt = Date()
        
        // Default: no trim (full video)
        self.trimStartTime = 0
        self.trimEndTime = videoDuration
        
        // Default: no filter
        self.selectedFilter = nil
        self.filterIntensity = 1.0
        
        // Default: no captions
        self.captions = []
        
        // Default: not processing
        self.isProcessing = false
        self.processingProgress = 0.0
        self.processedVideoURL = nil
        self.processedThumbnailURL = nil
        
        // Default: not compressed
        self.compressedVideoURL = nil
        self.compressionComplete = false
        self.compressionProgress = 0.0
        self.originalFileSize = 0
        self.compressedFileSize = 0
        
        // Draft metadata
        self.draftID = draftID
        self.lastModified = Date()
        
        // Upload state defaults
        self.uploadStatus = DraftUploadStatus.draft
        self.uploadMetadata = nil
        self.uploadContext = nil
        self.uploadErrorMessage = nil
        self.uploadAttemptCount = 0
    }
    
    // MARK: - Custom Codable (backward-compatible with existing drafts)
    
    enum CodingKeys: String, CodingKey {
        case videoURL, videoDuration, videoSize, createdAt
        case trimStartTime, trimEndTime
        case selectedFilter, filterIntensity
        case captions
        case isProcessing, processingProgress, processedVideoURL, processedThumbnailURL
        case compressedVideoURL, compressionComplete, compressionProgress, originalFileSize, compressedFileSize
        case draftID, lastModified
        case uploadStatus, uploadMetadata, uploadContext, uploadErrorMessage, uploadAttemptCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        videoURL = try container.decode(URL.self, forKey: .videoURL)
        videoDuration = try container.decode(TimeInterval.self, forKey: .videoDuration)
        videoSize = try container.decode(CGSize.self, forKey: .videoSize)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        
        trimStartTime = try container.decode(TimeInterval.self, forKey: .trimStartTime)
        trimEndTime = try container.decode(TimeInterval.self, forKey: .trimEndTime)
        
        selectedFilter = try container.decodeIfPresent(VideoFilter.self, forKey: .selectedFilter)
        filterIntensity = try container.decode(Double.self, forKey: .filterIntensity)
        
        captions = try container.decode([VideoCaption].self, forKey: .captions)
        
        isProcessing = try container.decode(Bool.self, forKey: .isProcessing)
        processingProgress = try container.decode(Double.self, forKey: .processingProgress)
        processedVideoURL = try container.decodeIfPresent(URL.self, forKey: .processedVideoURL)
        processedThumbnailURL = try container.decodeIfPresent(URL.self, forKey: .processedThumbnailURL)
        
        compressedVideoURL = try container.decodeIfPresent(URL.self, forKey: .compressedVideoURL)
        compressionComplete = try container.decode(Bool.self, forKey: .compressionComplete)
        compressionProgress = try container.decode(Double.self, forKey: .compressionProgress)
        originalFileSize = try container.decode(Int64.self, forKey: .originalFileSize)
        compressedFileSize = try container.decode(Int64.self, forKey: .compressedFileSize)
        
        draftID = try container.decode(String.self, forKey: .draftID)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        
        // 🆕 New fields with defaults for backward compatibility
        uploadStatus = try container.decodeIfPresent(DraftUploadStatus.self, forKey: .uploadStatus) ?? .draft
        uploadMetadata = try container.decodeIfPresent(PersistedUploadMetadata.self, forKey: .uploadMetadata)
        uploadContext = try container.decodeIfPresent(PersistedRecordingContext.self, forKey: .uploadContext)
        uploadErrorMessage = try container.decodeIfPresent(String.self, forKey: .uploadErrorMessage)
        uploadAttemptCount = try container.decodeIfPresent(Int.self, forKey: .uploadAttemptCount) ?? 0
    }
    
    // MARK: - Modification Methods
    
    mutating func updateTrimRange(start: TimeInterval, end: TimeInterval) {
        let oldStart = trimStartTime
        let oldEnd = trimEndTime
        
        trimStartTime = max(0, min(start, videoDuration))
        trimEndTime = max(trimStartTime, min(end, videoDuration))
        lastModified = Date()
        
        // ðŸ†• Invalidate compression if trim changed significantly
        if abs(oldStart - trimStartTime) > 0.5 || abs(oldEnd - trimEndTime) > 0.5 {
            invalidateCompression()
        }
    }
    
    mutating func setFilter(_ filter: VideoFilter?, intensity: Double = 1.0) {
        selectedFilter = filter
        filterIntensity = max(0.0, min(1.0, intensity))
        lastModified = Date()
    }
    
    mutating func addCaption(_ caption: VideoCaption) {
        captions.append(caption)
        lastModified = Date()
    }
    
    mutating func removeCaption(id: String) {
        captions.removeAll { $0.id == id }
        lastModified = Date()
    }
    
    mutating func updateCaption(id: String, update: (inout VideoCaption) -> Void) {
        if let index = captions.firstIndex(where: { $0.id == id }) {
            update(&captions[index])
            lastModified = Date()
        }
    }
    
    // MARK: - ðŸ†• NEW: Compression Methods
    
    mutating func setCompressedVideo(url: URL, originalSize: Int64, compressedSize: Int64) {
        compressedVideoURL = url
        compressionComplete = true
        compressionProgress = 1.0
        self.originalFileSize = originalSize
        self.compressedFileSize = compressedSize
        lastModified = Date()
    }
    
    mutating func updateCompressionProgress(_ progress: Double) {
        compressionProgress = max(0.0, min(1.0, progress))
    }
    
    mutating func invalidateCompression() {
        // Clean up old compressed file
        if let url = compressedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        compressedVideoURL = nil
        compressionComplete = false
        compressionProgress = 0.0
        compressedFileSize = 0
    }
    
    // MARK: - Processing State
    
    mutating func startProcessing() {
        isProcessing = true
        processingProgress = 0.0
        lastModified = Date()
    }
    
    mutating func updateProcessingProgress(_ progress: Double) {
        processingProgress = max(0.0, min(1.0, progress))
    }
    
    mutating func finishProcessing(processedVideoURL: URL, thumbnailURL: URL) {
        isProcessing = false
        processingProgress = 1.0
        self.processedVideoURL = processedVideoURL
        self.processedThumbnailURL = thumbnailURL
        lastModified = Date()
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        // Must have valid duration
        guard trimmedDuration > 0.5 else { return false }
        
        // Caption timestamps must be within trim range
        for caption in captions {
            if caption.startTime < trimStartTime || caption.startTime > trimEndTime {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - ðŸ”§ IMPROVED: Edit Detection
    
    /// Detects if start was trimmed (more than 0.1s from beginning)
    var hasStartTrim: Bool {
        trimStartTime > 0.1
    }
    
    /// Detects if end was trimmed (more than 0.1s from end)
    var hasEndTrim: Bool {
        trimEndTime < (videoDuration - 0.1)
    }
    
    /// ðŸ”§ FIXED: Properly detects BOTH start and end trimming
    var hasTrim: Bool {
        hasStartTrim || hasEndTrim
    }
    
    var hasFilter: Bool {
        selectedFilter != nil
    }
    
    var hasCaptions: Bool {
        !captions.isEmpty
    }
    
    var hasEdits: Bool {
        hasTrim || hasFilter || hasCaptions
    }
    
    var hasCompression: Bool {
        compressionComplete && compressedVideoURL != nil
    }
    
    // MARK: - Export Readiness
    
    var isReadyToPost: Bool {
        // Must be valid
        guard isValid else { return false }
        
        // If edits were made, processing must be complete
        if hasEdits && !isProcessingComplete {
            return false
        }
        
        return true
    }
    
    var isProcessingComplete: Bool {
        return processedVideoURL != nil && processedThumbnailURL != nil
    }
    
    // MARK: - ðŸ”§ IMPROVED: Final Video URL
    
    /// Returns the URL to use for posting
    /// Priority: processed (if edited) > compressed > original
    var finalVideoURL: URL {
        // If user made edits, use processed version
        if hasEdits, let processed = processedVideoURL {
            return processed
        }
        // Otherwise prefer compressed version
        if hasCompression, let compressed = compressedVideoURL {
            return compressed
        }
        // Fall back to original
        return videoURL
    }
    
    var finalThumbnailURL: URL? {
        if hasEdits {
            return processedThumbnailURL
        }
        return nil // Will generate from original
    }
    
    // MARK: - ðŸ†• NEW: Compression Stats
    
    var compressionRatio: Double {
        guard originalFileSize > 0, compressedFileSize > 0 else { return 1.0 }
        return Double(compressedFileSize) / Double(originalFileSize)
    }
    
    var compressionSavingsPercent: Double {
        (1.0 - compressionRatio) * 100.0
    }
    
    var compressionSavingsFormatted: String {
        String(format: "%.0f%% smaller", compressionSavingsPercent)
    }
    
    // MARK: - 🆕 Upload Status Methods
    
    mutating func markReadyToUpload(metadata: PersistedUploadMetadata, context: PersistedRecordingContext) {
        uploadStatus = DraftUploadStatus.readyToUpload
        uploadMetadata = metadata
        uploadContext = context
        uploadErrorMessage = nil
        lastModified = Date()
    }
    
    mutating func markUploading() {
        uploadStatus = DraftUploadStatus.uploading
        uploadAttemptCount += 1
        uploadErrorMessage = nil
        lastModified = Date()
    }
    
    mutating func markUploadFailed(error: String) {
        uploadStatus = DraftUploadStatus.failed
        uploadErrorMessage = error
        lastModified = Date()
    }
    
    mutating func markUploadComplete() {
        uploadStatus = DraftUploadStatus.complete
        uploadErrorMessage = nil
        lastModified = Date()
    }
    
    var canRetryUpload: Bool {
        uploadStatus == DraftUploadStatus.failed && uploadMetadata != nil && uploadContext != nil
    }
}

// MARK: - Upload Status

enum DraftUploadStatus: String, Codable {
    case draft          // Saved locally, not yet submitted for upload
    case readyToUpload  // User tapped Post, queued for background upload
    case uploading      // Currently uploading in background
    case failed         // Upload failed, can retry
    case complete       // Successfully uploaded
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .readyToUpload: return "Queued"
        case .uploading: return "Uploading"
        case .failed: return "Failed"
        case .complete: return "Posted"
        }
    }
    
    var iconName: String {
        switch self {
        case .draft: return "pencil"
        case .readyToUpload: return "clock"
        case .uploading: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Persisted Upload Metadata (Codable version of VideoUploadMetadata)

struct PersistedUploadMetadata: Codable {
    let videoID: String
    let title: String
    let description: String
    let hashtags: [String]
    let creatorID: String
    let creatorName: String
    let taggedUserIDs: [String]
    let recordingSource: String
    
    init(
        title: String,
        description: String = "",
        hashtags: [String] = [],
        creatorID: String,
        creatorName: String,
        taggedUserIDs: [String] = [],
        recordingSource: String = "unknown"
    ) {
        self.videoID = UUID().uuidString
        self.title = title
        self.description = description
        self.hashtags = hashtags
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.taggedUserIDs = taggedUserIDs
        self.recordingSource = recordingSource
    }
    
    /// Convert to VideoUploadMetadata for the upload service
    func toUploadMetadata() -> VideoUploadMetadata {
        return VideoUploadMetadata(
            title: title,
            description: description,
            hashtags: hashtags,
            creatorID: creatorID,
            creatorName: creatorName
        )
    }
}

// MARK: - Persisted Recording Context (Codable version of RecordingContext)

enum PersistedRecordingContext: Codable {
    case newThread
    case stitchToThread(threadID: String, threadInfo: PersistedThreadInfo)
    case replyToVideo(videoID: String, videoInfo: PersistedVideoInfo)
    case continueThread(threadID: String, threadInfo: PersistedThreadInfo)
    case spinOffFrom(videoID: String, threadID: String, videoInfo: PersistedVideoInfo)
    
    /// Convert to RecordingContext for the upload service
    func toRecordingContext() -> RecordingContext {
        switch self {
        case .newThread:
            return .newThread
        case .stitchToThread(let threadID, let info):
            return .stitchToThread(threadID: threadID, threadInfo: info.toThreadInfo())
        case .replyToVideo(let videoID, let info):
            return .replyToVideo(videoID: videoID, videoInfo: info.toCameraVideoInfo())
        case .continueThread(let threadID, let info):
            return .continueThread(threadID: threadID, threadInfo: info.toThreadInfo())
        case .spinOffFrom(let videoID, let threadID, let info):
            return .spinOffFrom(videoID: videoID, threadID: threadID, videoInfo: info.toCameraVideoInfo())
        }
    }
    
    /// Create from RecordingContext
    static func from(_ context: RecordingContext) -> PersistedRecordingContext {
        switch context {
        case .newThread:
            return .newThread
        case .stitchToThread(let threadID, let info):
            return .stitchToThread(threadID: threadID, threadInfo: PersistedThreadInfo.from(info))
        case .replyToVideo(let videoID, let info):
            return .replyToVideo(videoID: videoID, videoInfo: PersistedVideoInfo.from(info))
        case .continueThread(let threadID, let info):
            return .continueThread(threadID: threadID, threadInfo: PersistedThreadInfo.from(info))
        case .spinOffFrom(let videoID, let threadID, let info):
            return .spinOffFrom(videoID: videoID, threadID: threadID, videoInfo: PersistedVideoInfo.from(info))
        }
    }
}

struct PersistedThreadInfo: Codable {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
    let participantCount: Int
    let stitchCount: Int
    
    func toThreadInfo() -> ThreadInfo {
        return ThreadInfo(
            title: title,
            creatorName: creatorName,
            creatorID: creatorID,
            thumbnailURL: thumbnailURL,
            participantCount: participantCount,
            stitchCount: stitchCount
        )
    }
    
    static func from(_ info: ThreadInfo) -> PersistedThreadInfo {
        return PersistedThreadInfo(
            title: info.title,
            creatorName: info.creatorName,
            creatorID: info.creatorID,
            thumbnailURL: info.thumbnailURL,
            participantCount: info.participantCount,
            stitchCount: info.stitchCount
        )
    }
}

struct PersistedVideoInfo: Codable {
    let title: String
    let creatorName: String
    let creatorID: String
    let thumbnailURL: String?
    
    func toCameraVideoInfo() -> CameraVideoInfo {
        return CameraVideoInfo(
            title: title,
            creatorName: creatorName,
            creatorID: creatorID,
            thumbnailURL: thumbnailURL
        )
    }
    
    static func from(_ info: CameraVideoInfo) -> PersistedVideoInfo {
        return PersistedVideoInfo(
            title: info.title,
            creatorName: info.creatorName,
            creatorID: info.creatorID,
            thumbnailURL: info.thumbnailURL
        )
    }
}

// MARK: - Supporting Types

/// Video filter options
enum VideoFilter: String, Codable, CaseIterable {
    case none = "None"
    case vivid = "Vivid"
    case warm = "Warm"
    case cool = "Cool"
    case dramatic = "Dramatic"
    case vintage = "Vintage"
    case monochrome = "Monochrome"
    case cinematic = "Cinematic"
    case sunset = "Sunset"
    
    var displayName: String {
        rawValue
    }
    
    var ciFilterName: String? {
        switch self {
        case .none:
            return nil
        case .vivid:
            return "CIColorControls" // Increase saturation
        case .warm:
            return "CITemperatureAndTint"
        case .cool:
            return "CITemperatureAndTint"
        case .dramatic:
            return "CIColorControls" // High contrast
        case .vintage:
            return "CIPhotoEffectTransfer"
        case .monochrome:
            return "CIPhotoEffectMono"
        case .cinematic:
            return "CIVignette"
        case .sunset:
            return "CIColorMonochrome"
        }
    }
    
    var thumbnailIcon: String {
        switch self {
        case .none: return "circle"
        case .vivid: return "sparkles"
        case .warm: return "sun.max.fill"
        case .cool: return "snowflake"
        case .dramatic: return "bolt.fill"
        case .vintage: return "camera.fill"
        case .monochrome: return "circle.lefthalf.filled"
        case .cinematic: return "film.fill"
        case .sunset: return "sunset.fill"
        }
    }
}

/// Video caption/text overlay
struct VideoCaption: Codable, Identifiable {
    let id: String
    var text: String
    var startTime: TimeInterval
    var duration: TimeInterval
    var position: CaptionPosition
    var style: CaptionStyle
    
    var endTime: TimeInterval {
        startTime + duration
    }
    
    init(
        text: String,
        startTime: TimeInterval,
        duration: TimeInterval = 3.0,
        position: CaptionPosition = .center,
        style: CaptionStyle = .standard
    ) {
        self.id = UUID().uuidString
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.position = position
        self.style = style
    }
}

/// Caption position on video
enum CaptionPosition: String, Codable, CaseIterable {
    case top
    case center
    case bottom
    
    var offset: CGFloat {
        switch self {
        case .top: return 0.2
        case .center: return 0.5
        case .bottom: return 0.8
        }
    }
}

/// Caption style options
enum CaptionStyle: String, Codable, CaseIterable {
    case standard
    case bold
    case outlined
    case shadow
    
    var fontSize: CGFloat {
        switch self {
        case .standard: return 24
        case .bold: return 28
        case .outlined: return 26
        case .shadow: return 24
        }
    }
    
    var fontWeight: String {
        switch self {
        case .bold: return "bold"
        default: return "semibold"
        }
    }
}
