//
//  CollageConfiguration.swift
//  StitchSocial
//
//  Created by James Garmon on 2/19/26.
//


//
//  CollageConfiguration.swift
//  StitchSocial
//
//  Layer 3: Models - Thread Collage Configuration
//  Dependencies: Foundation, AVFoundation
//  Defines layout, timing, transitions, and watermark settings for thread collage export
//

import Foundation
import AVFoundation

// MARK: - Collage Configuration

/// Configuration for composing a 60-second thread collage video
struct CollageConfiguration {
    
    // MARK: - Timing
    
    /// Total collage duration in seconds (default 60)
    var totalDuration: TimeInterval = 60.0
    
    /// How time is distributed across clips
    var timeStrategy: TimeStrategy = .mainWeighted
    
    /// Minimum seconds any single clip can occupy
    var minimumClipDuration: TimeInterval = 5.0
    
    /// Maximum seconds the main/parent clip can occupy
    var maximumMainClipDuration: TimeInterval = 20.0
    
    // MARK: - Transitions
    
    /// Transition type between clips
    var transitionType: CollageTransition = .crossDissolve
    
    /// Transition duration in seconds (eaten from total, not added)
    var transitionDuration: TimeInterval = 0.5
    
    // MARK: - Watermark
    
    /// Creator username for watermark (e.g., "@username")
    var creatorUsername: String = ""
    
    /// Duration of watermark end card in seconds (included in totalDuration)
    var watermarkDuration: TimeInterval = 3.0
    
    /// Watermark font size
    var watermarkFontSize: CGFloat = 42.0
    
    /// App branding text shown below username
    var brandingText: String = "StitchSocial"
    
    // MARK: - Output Quality
    
    /// Output resolution (matches source or capped)
    var outputResolution: OutputResolution = .hd1080p
    
    /// Video bitrate for export
    var videoBitRate: Int = 8_000_000 // 8 Mbps
    
    /// Audio bitrate for export
    var audioBitRate: Int = 128_000 // 128 kbps
    
    /// Frame rate
    var frameRate: Int32 = 30
    
    // MARK: - Computed Properties
    
    /// Usable content duration after watermark end card
    var contentDuration: TimeInterval {
        return totalDuration - watermarkDuration
    }
    
    /// Calculate time allocation for each clip
    /// - Parameters:
    ///   - mainClipDuration: Original duration of the main/parent video
    ///   - responseClipDurations: Original durations of selected response videos
    /// - Returns: Array of allocated durations [main, response1, response2, ...]
    func calculateTimeAllocations(
        mainClipDuration: TimeInterval,
        responseClipDurations: [TimeInterval]
    ) -> [TimeInterval] {
        let clipCount = 1 + responseClipDurations.count
        let transitionOverhead = transitionDuration * Double(clipCount - 1)
        let availableTime = contentDuration - transitionOverhead
        
        guard availableTime > 0, clipCount > 0 else { return [] }
        
        switch timeStrategy {
        case .equal:
            let perClip = availableTime / Double(clipCount)
            let clamped = max(minimumClipDuration, perClip)
            return Array(repeating: clamped, count: clipCount)
            
        case .mainWeighted:
            // Main gets 30% of available time, responses split the rest equally
            let mainAllocation = min(
                maximumMainClipDuration,
                max(minimumClipDuration, availableTime * 0.30)
            )
            let remaining = availableTime - mainAllocation
            let perResponse = max(
                minimumClipDuration,
                remaining / Double(responseClipDurations.count)
            )
            var allocations = [mainAllocation]
            allocations.append(contentsOf: Array(repeating: perResponse, count: responseClipDurations.count))
            return allocations
            
        case .proportional:
            // Proportional to original clip lengths, clamped
            let allDurations = [mainClipDuration] + responseClipDurations
            let totalOriginal = allDurations.reduce(0, +)
            guard totalOriginal > 0 else {
                let perClip = availableTime / Double(clipCount)
                return Array(repeating: perClip, count: clipCount)
            }
            return allDurations.map { original in
                let ratio = original / totalOriginal
                let allocated = availableTime * ratio
                return max(minimumClipDuration, min(maximumMainClipDuration, allocated))
            }
        }
    }
}

// MARK: - Supporting Enums

/// How time is distributed across clips in the collage
enum TimeStrategy: String, CaseIterable {
    case equal          // All clips get equal time
    case mainWeighted   // Main clip gets 30%, rest split evenly
    case proportional   // Proportional to original clip durations
    
    var displayName: String {
        switch self {
        case .equal: return "Equal"
        case .mainWeighted: return "Main Featured"
        case .proportional: return "Proportional"
        }
    }
}

/// Transition type between clips
enum CollageTransition: String, CaseIterable {
    case cut            // Hard cut, no transition
    case crossDissolve  // Crossfade between clips
    
    var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .crossDissolve: return "Dissolve"
        }
    }
}

/// Output resolution presets
enum OutputResolution: String, CaseIterable {
    case hd720p     // 720x1280 portrait
    case hd1080p    // 1080x1920 portrait
    
    var size: CGSize {
        switch self {
        case .hd720p: return CGSize(width: 720, height: 1280)
        case .hd1080p: return CGSize(width: 1080, height: 1920)
        }
    }
    
    var displayName: String {
        switch self {
        case .hd720p: return "720p"
        case .hd1080p: return "1080p"
        }
    }
}

// MARK: - Clip Selection Model

/// Represents a selected clip for the collage (cached AVAsset reference)
struct CollageClip: Identifiable {
    let id: String              // video ID
    let videoMetadata: CoreVideoMetadata
    var asset: AVAsset?         // Cached — loaded once, reused for composition
    var originalDuration: TimeInterval
    var allocatedDuration: TimeInterval = 0
    var trimStart: TimeInterval = 0  // Where to start within the original clip
    let isMainClip: Bool
    
    /// Computed trim end based on allocated duration
    var trimEnd: TimeInterval {
        return min(trimStart + allocatedDuration, originalDuration)
    }
    
    /// CMTimeRange for AVComposition insertion — single computation, no repeated conversions
    var compositionTimeRange: CMTimeRange {
        return CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: allocatedDuration, preferredTimescale: 600)
        )
    }
}

// MARK: - Collage State

/// Tracks collage build progress
enum CollageState: Equatable {
    case idle
    case selectingClips
    case loadingAssets         // Batch loading AVAssets
    case composing             // Building AVMutableComposition
    case addingWatermark       // Overlay pass
    case exporting(progress: Double)
    case completed(url: URL)
    case failed(error: String)
    
    static func == (lhs: CollageState, rhs: CollageState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.selectingClips, .selectingClips),
             (.loadingAssets, .loadingAssets),
             (.composing, .composing),
             (.addingWatermark, .addingWatermark): return true
        case (.exporting(let a), .exporting(let b)): return a == b
        case (.completed(let a), .completed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}