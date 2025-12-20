//
//  VideoEditState.swift
//  StitchSocial
//
//  Layer 3: State Management - Video Edit State During Review
//  Dependencies: Foundation, AVFoundation
//  Features: Tracks trim, filter, caption state before posting
//
//  🔧 UPDATED: Added compression state tracking
//  🔧 UPDATED: Better trim detection (checks both start AND end)
//  🔧 UPDATED: Added finalVideoURL that prefers compressed/processed
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
    
    // MARK: - 🆕 NEW: Compression State
    
    var compressedVideoURL: URL?
    var compressionComplete: Bool
    var compressionProgress: Double
    var originalFileSize: Int64
    var compressedFileSize: Int64
    
    // MARK: - Draft State
    
    var draftID: String
    var lastModified: Date
    
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
    }
    
    // MARK: - Modification Methods
    
    mutating func updateTrimRange(start: TimeInterval, end: TimeInterval) {
        let oldStart = trimStartTime
        let oldEnd = trimEndTime
        
        trimStartTime = max(0, min(start, videoDuration))
        trimEndTime = max(trimStartTime, min(end, videoDuration))
        lastModified = Date()
        
        // 🆕 Invalidate compression if trim changed significantly
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
    
    // MARK: - 🆕 NEW: Compression Methods
    
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
    
    // MARK: - 🔧 IMPROVED: Edit Detection
    
    /// Detects if start was trimmed (more than 0.1s from beginning)
    var hasStartTrim: Bool {
        trimStartTime > 0.1
    }
    
    /// Detects if end was trimmed (more than 0.1s from end)
    var hasEndTrim: Bool {
        trimEndTime < (videoDuration - 0.1)
    }
    
    /// 🔧 FIXED: Properly detects BOTH start and end trimming
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
    
    // MARK: - 🔧 IMPROVED: Final Video URL
    
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
    
    // MARK: - 🆕 NEW: Compression Stats
    
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
