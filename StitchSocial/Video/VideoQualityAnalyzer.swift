//
//  VideoQualityAnalyzer.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Video Quality Assessment & Compression Optimization
//  Dependencies: Foundation only - PURE FUNCTIONS ONLY
//  Critical for 28MB → 2-3MB compression and feed content ranking
//

import Foundation
import CoreGraphics

// MARK: - Supporting Types (DEFINED ONCE HERE)

/// Input metadata for video quality analysis
struct VideoQualityInput {
    let duration: TimeInterval
    let fileSize: Int64
    let resolution: CGSize
    let bitrate: Double
    let frameRate: Double
    let aspectRatio: Double
}

/// Video quality assessment result
struct VideoQualityResult {
    let qualityScore: Double        // 0-100 overall quality
    let resolutionScore: Double     // 0-100 resolution quality
    let bitrateScore: Double        // 0-100 bitrate efficiency
    let frameRateScore: Double      // 0-100 frame rate quality
    let aspectRatioScore: Double    // 0-100 aspect ratio optimization
    let overallGrade: String        // A, B, C, D, F letter grade
}

/// Compression optimization settings
struct VideoCompressionSettings {
    let targetBitrate: Int          // Target video bitrate (bps)
    let maxResolution: CGSize       // Maximum output resolution
    let quality: Float              // Compression quality (0.1-1.0)
    let codec: String               // Video codec (H.264/H.265)
    let estimatedOutputSize: Int64  // Estimated compressed file size
}

/// Pure calculation functions for video quality assessment and compression optimization
/// Enables 90% file size reduction while maintaining visual quality for mobile optimization
struct VideoQualityAnalyzer {
    
    // MARK: - Quality Assessment Functions
    
    /// Calculates overall video quality score (0-100) from technical metrics
    /// Used for feed ranking and content discovery algorithms
    static func calculateQualityScore(resolution: CGSize, bitrate: Double, frameRate: Double) -> Double {
        let resolutionScore = calculateResolutionScore(width: Double(resolution.width), height: Double(resolution.height))
        let bitrateScore = calculateBitrateEfficiency(bitrate: bitrate, resolution: resolution, duration: 30.0) // Assume 30s videos
        let frameRateScore = calculateFrameRateScore(frameRate: frameRate)
        let aspectRatioScore = calculateAspectRatioScore(aspectRatio: Double(resolution.width) / Double(resolution.height))
        
        // Weighted composite score
        let overallScore = (resolutionScore * 0.4) + (bitrateScore * 0.3) + (frameRateScore * 0.2) + (aspectRatioScore * 0.1)
        
        return min(100.0, max(0.0, overallScore))
    }
    
    /// Calculates resolution quality score based on optimal mobile viewing standards
    static func calculateResolutionScore(width: Double, height: Double) -> Double {
        let pixelCount = width * height
        
        // Mobile-optimized scoring thresholds
        if pixelCount >= 2073600 { return 100.0 } // 1440x1440 or better
        if pixelCount >= 2073600 { return 95.0 }  // 1920x1080
        if pixelCount >= 921600 { return 85.0 }   // 1280x720
        if pixelCount >= 409920 { return 70.0 }   // 854x480
        if pixelCount >= 230400 { return 50.0 }   // 640x360
        if pixelCount >= 76800 { return 30.0 }    // 320x240
        return 10.0 // Below mobile standards
    }
    
    /// Calculates bitrate efficiency score for compression optimization
    static func calculateBitrateEfficiency(bitrate: Double, resolution: CGSize, duration: TimeInterval) -> Double {
        let optimalBitrate = calculateOptimalBitrateForResolution(resolution: resolution)
        let efficiency = min(1.0, bitrate / optimalBitrate)
        
        // Scoring based on efficiency vs optimal
        if efficiency >= 0.8 { return 100.0 }
        if efficiency >= 0.6 { return 85.0 }
        if efficiency >= 0.4 { return 70.0 }
        if efficiency >= 0.2 { return 50.0 }
        return 25.0
    }
    
    /// Calculates frame rate quality score for smooth playback assessment
    static func calculateFrameRateScore(frameRate: Double) -> Double {
        // Mobile-optimized frame rate scoring
        if frameRate >= 60 { return 100.0 }  // High frame rate
        if frameRate >= 30 { return 95.0 }   // Standard smooth
        if frameRate >= 24 { return 80.0 }   // Cinematic standard
        if frameRate >= 15 { return 60.0 }   // Acceptable minimum
        return 30.0 // Below acceptable standards
    }
    
    /// Calculates aspect ratio optimization score for mobile viewing
    static func calculateAspectRatioScore(aspectRatio: Double) -> Double {
        // Mobile-first aspect ratio optimization
        if aspectRatio >= 0.5 && aspectRatio <= 0.6 { return 100.0 } // 9:16 to 5:8 (optimal mobile)
        if aspectRatio >= 0.7 && aspectRatio <= 0.8 { return 90.0 }  // 4:5 to 5:7 (good mobile)
        if aspectRatio >= 0.9 && aspectRatio <= 1.1 { return 80.0 }  // Square (acceptable)
        if aspectRatio >= 1.2 && aspectRatio <= 1.8 { return 60.0 }  // Landscape (suboptimal mobile)
        return 40.0 // Poor mobile optimization
    }
    
    // MARK: - Compression Optimization Functions
    
    /// Calculates optimal compression settings for 90% size reduction while preserving quality
    static func calculateOptimalSettings(inputVideo: VideoQualityInput) -> VideoCompressionSettings {
        let targetSize: Int64 = 3 * 1024 * 1024 // 3MB target
        let duration = inputVideo.duration
        
        // Calculate target bitrate for size optimization
        let targetBitrate = calculateTargetBitrate(
            currentSize: inputVideo.fileSize,
            targetSize: targetSize,
            duration: duration
        )
        
        // Calculate maximum resolution for target file size
        let maxResolution = calculateMaxResolution(
            targetFileSize: targetSize,
            duration: duration,
            targetBitrate: targetBitrate
        )
        
        // Quality factor based on compression aggressiveness
        let compressionRatio = calculateCompressionRatio(
            originalSize: inputVideo.fileSize,
            targetSize: targetSize
        )
        let quality = calculateQualityFactor(compressionRatio: compressionRatio)
        
        return VideoCompressionSettings(
            targetBitrate: targetBitrate,
            maxResolution: maxResolution,
            quality: quality,
            codec: "H.264",
            estimatedOutputSize: targetSize
        )
    }
    
    /// Calculates target bitrate for achieving specific file size
    static func calculateTargetBitrate(currentSize: Int64, targetSize: Int64, duration: TimeInterval) -> Int {
        // Account for audio bitrate (assume 128kbps AAC)
        let audioBitrate = 128_000 // 128 kbps
        let targetFileSizeBits = Double(targetSize * 8) // Convert bytes to bits
        let durationSeconds = max(1.0, duration) // Prevent division by zero
        
        // Calculate total bitrate budget
        let totalBitrate = targetFileSizeBits / durationSeconds
        
        // Reserve space for audio, give remainder to video
        let videoBitrate = totalBitrate - Double(audioBitrate)
        
        // Clamp to reasonable bounds for mobile optimization
        let clampedBitrate = min(1_500_000, max(400_000, videoBitrate)) // 400kbps to 1.5Mbps
        
        return Int(clampedBitrate)
    }
    
    /// Calculates maximum resolution that fits within file size constraints
    static func calculateMaxResolution(targetFileSize: Int64, duration: TimeInterval, targetBitrate: Int) -> CGSize {
        // Resolution tiers optimized for compression efficiency
        let resolutionTiers: [(CGSize, Int)] = [
            (CGSize(width: 1440, height: 2560), 1_200_000), // 4K requires high bitrate
            (CGSize(width: 1080, height: 1920), 800_000),   // 1080p optimal
            (CGSize(width: 720, height: 1280), 500_000),    // 720p efficient
            (CGSize(width: 540, height: 960), 300_000),     // 540p minimum
            (CGSize(width: 480, height: 854), 250_000)      // 480p fallback
        ]
        
        // Select highest resolution that fits within bitrate budget
        for (resolution, minBitrate) in resolutionTiers {
            if targetBitrate >= minBitrate {
                return resolution
            }
        }
        
        // Fallback to lowest tier
        return CGSize(width: 480, height: 854)
    }
    
    /// Calculates compression ratio for quality assessment
    static func calculateCompressionRatio(originalSize: Int64, targetSize: Int64) -> Double {
        guard originalSize > 0 else { return 1.0 }
        return Double(originalSize) / Double(targetSize)
    }
    
    // MARK: - Performance Calculation Functions
    
    /// Estimates compression processing time based on file complexity
    static func calculateEstimatedCompressionTime(fileSize: Int64, compressionRatio: Double) -> TimeInterval {
        // Base processing rate: ~5MB per second on modern mobile hardware
        let baseProcessingRate: Double = 5 * 1024 * 1024 // 5MB/s
        
        // Complexity multiplier based on compression aggressiveness
        let complexityMultiplier = sqrt(compressionRatio) // More aggressive = longer time
        
        let estimatedTime = (Double(fileSize) / baseProcessingRate) * complexityMultiplier
        
        // Clamp to reasonable bounds (5 seconds to 5 minutes)
        return min(300.0, max(5.0, estimatedTime))
    }
    
    /// Calculates quality loss score from bitrate reduction
    static func calculateQualityLossScore(originalBitrate: Int, targetBitrate: Int) -> Double {
        guard originalBitrate > 0 else { return 0.0 }
        
        let reductionRatio = Double(targetBitrate) / Double(originalBitrate)
        
        // Quality loss estimation (exponential degradation below 50% bitrate)
        if reductionRatio >= 0.8 { return 5.0 }   // Minimal loss
        if reductionRatio >= 0.6 { return 15.0 }  // Slight loss
        if reductionRatio >= 0.4 { return 30.0 }  // Moderate loss
        if reductionRatio >= 0.2 { return 50.0 }  // Noticeable loss
        return 75.0 // Significant quality degradation
    }
    
    // MARK: - Helper Functions
    
    /// Calculates optimal bitrate for given resolution
    private static func calculateOptimalBitrateForResolution(resolution: CGSize) -> Double {
        let pixelCount = Double(resolution.width * resolution.height)
        
        // Optimal bitrates based on resolution (optimized for mobile)
        if pixelCount >= 2073600 { return 1_200_000 } // 1440p
        if pixelCount >= 2073600 { return 800_000 }   // 1080p
        if pixelCount >= 921600 { return 500_000 }    // 720p
        if pixelCount >= 409920 { return 300_000 }    // 480p
        return 200_000 // Lower resolutions
    }
    
    /// Calculates quality factor for compression settings
    private static func calculateQualityFactor(compressionRatio: Double) -> Float {
        // Quality factor (0.1 to 1.0) based on compression aggressiveness
        if compressionRatio <= 2.0 { return 0.9 }      // Light compression
        if compressionRatio <= 5.0 { return 0.75 }     // Moderate compression
        if compressionRatio <= 10.0 { return 0.6 }     // Aggressive compression
        if compressionRatio <= 20.0 { return 0.45 }    // Very aggressive
        return 0.3 // Ultra compression for extreme size constraints
    }
    
    // MARK: - Public Result Types
    
    /// Complete video quality assessment result
    static func generateQualityResult(resolution: CGSize, bitrate: Double, frameRate: Double) -> VideoQualityResult {
        let resolutionScore = calculateResolutionScore(width: Double(resolution.width), height: Double(resolution.height))
        let bitrateScore = calculateBitrateEfficiency(bitrate: bitrate, resolution: resolution, duration: 30.0)
        let frameRateScore = calculateFrameRateScore(frameRate: frameRate)
        let aspectRatioScore = calculateAspectRatioScore(aspectRatio: Double(resolution.width) / Double(resolution.height))
        let qualityScore = calculateQualityScore(resolution: resolution, bitrate: bitrate, frameRate: frameRate)
        
        // Letter grade assignment
        let grade: String
        if qualityScore >= 90 { grade = "A" }
        else if qualityScore >= 80 { grade = "B" }
        else if qualityScore >= 70 { grade = "C" }
        else if qualityScore >= 60 { grade = "D" }
        else { grade = "F" }
        
        return VideoQualityResult(
            qualityScore: qualityScore,
            resolutionScore: resolutionScore,
            bitrateScore: bitrateScore,
            frameRateScore: frameRateScore,
            aspectRatioScore: aspectRatioScore,
            overallGrade: grade
        )
    }
}
