//
//  VideoQualityAnalyzer.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Video Quality Assessment & Compression Optimization
//  Dependencies: Foundation only - PURE FUNCTIONS ONLY
//  Critical for 28MB → 2-3MB compression and feed content ranking
//  UPDATED: Duration-based tiered compression with user tier privileges
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
/// UPDATED: Duration-based tiered compression with user privilege system
struct VideoQualityAnalyzer {
    
    // MARK: - DURATION-BASED TIERED COMPRESSION (NEW)
    
    /// Calculate optimal resolution based on video duration and user tier
    /// 0-2 min: 1440p | 2-5 min: 1080p | 5+ min: 720p (unless premium user)
    /// Premium users (ambassadors, partners, etc.) get quality boost for long videos
    static func calculateOptimalResolution(
        duration: TimeInterval,
        userTier: UserTier
    ) -> CGSize {
        // Premium tiers get quality boost for longer content
        let isPremiumUser = userTier == .partner ||
                           userTier == .topCreator ||
                           userTier == .legendary ||
                           userTier == .elite ||
                           userTier == .influencer ||
                           userTier == .founder ||
                           userTier == .coFounder
        
        switch duration {
        case 0...120:  // 0-2 minutes: Highest quality for short content
            return CGSize(width: 1440, height: 2560)  // 1440p for all users
            
        case 120...300:  // 2-5 minutes: Balanced quality
            return CGSize(width: 1080, height: 1920)  // 1080p for all users
            
        default:  // 5+ minutes: Aggressive compression unless premium
            return isPremiumUser ?
                CGSize(width: 1080, height: 1920) :  // Premium users keep 1080p
                CGSize(width: 720, height: 1280)     // Regular users get 720p
        }
    }
    
    /// Get compression strategy description for UI display
    static func getCompressionStrategyDescription(
        duration: TimeInterval,
        userTier: UserTier
    ) -> String {
        let resolution = calculateOptimalResolution(duration: duration, userTier: userTier)
        let isPremium = userTier == .partner ||
                        userTier == .topCreator ||
                        userTier == .legendary ||
                        userTier == .elite ||
                        userTier == .influencer ||
                        userTier == .founder ||
                        userTier == .coFounder
        
        switch duration {
        case 0...120:
            return "Short video (≤2 min): 1440p quality - optimal for engagement"
        case 120...300:
            return "Medium video (2-5 min): 1080p quality - balanced compression"
        default:
            return isPremium ?
                "Long video (5+ min): 1080p quality - premium user benefit" :
                "Long video (5+ min): 720p quality - optimized for file size"
        }
    }
    
    // MARK: - Quality Assessment Functions
    
    /// Calculates overall video quality score (0-100) from technical metrics
    /// Used for feed ranking and content discovery algorithms
    static func calculateQualityScore(resolution: CGSize, bitrate: Double, frameRate: Double) -> Double {
        let resolutionScore = calculateResolutionScore(width: Double(resolution.width), height: Double(resolution.height))
        let bitrateScore = calculateBitrateEfficiency(bitrate: bitrate, resolution: resolution, duration: 30.0)
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
        if pixelCount >= 3686400 { return 100.0 } // 1440x2560 (4K)
        if pixelCount >= 2073600 { return 95.0 }  // 1080x1920 (1080p)
        if pixelCount >= 921600 { return 85.0 }   // 720x1280 (720p)
        if pixelCount >= 409920 { return 70.0 }   // 480x854 (480p)
        if pixelCount >= 230400 { return 50.0 }   // 360x640 (360p)
        if pixelCount >= 76800 { return 30.0 }    // 240x320 (240p)
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
        if frameRate >= 24 { return 85.0 }   // Cinematic smooth
        if frameRate >= 15 { return 60.0 }   // Acceptable minimum
        if frameRate >= 10 { return 30.0 }   // Poor quality
        return 10.0 // Unacceptable
    }
    
    /// Calculates aspect ratio optimization score for mobile viewing
    static func calculateAspectRatioScore(aspectRatio: Double) -> Double {
        // Optimal mobile aspect ratios (portrait focused)
        let targetRatio = 9.0 / 16.0  // 16:9 portrait (optimal for mobile)
        let difference = abs(aspectRatio - targetRatio)
        
        if difference <= 0.1 { return 100.0 }     // Perfect mobile ratio
        if difference <= 0.2 { return 90.0 }      // Very good
        if difference <= 0.3 { return 75.0 }      // Good
        if difference <= 0.5 { return 60.0 }      // Acceptable
        if difference <= 1.0 { return 40.0 }      // Poor
        return 20.0 // Very poor aspect ratio
    }
    
    // MARK: - Compression Optimization Functions
    
    /// Calculate compression settings optimized for duration and user tier
    static func calculateCompressionSettings(
        input: VideoQualityInput,
        targetSizeMB: Double = 3.0,
        userTier: UserTier
    ) -> VideoCompressionSettings {
        
        // Use duration-based resolution calculation
        let optimalResolution = calculateOptimalResolution(
            duration: input.duration,
            userTier: userTier
        )
        
        let targetSize = Int64(targetSizeMB * 1024 * 1024) // Convert MB to bytes
        let targetBitrate = calculateTargetBitrate(
            currentSize: input.fileSize,
            targetSize: targetSize,
            duration: input.duration
        )
        
        let compressionRatio = Double(input.fileSize) / Double(targetSize)
        let qualityFactor = calculateQualityFactor(compressionRatio: compressionRatio)
        
        return VideoCompressionSettings(
            targetBitrate: targetBitrate,
            maxResolution: optimalResolution,
            quality: qualityFactor,
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
            (CGSize(width: 1440, height: 2560), 1_200_000), // 1440p requires high bitrate
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
    static func calculateCompressionRatio(originalSize: Int64, compressedSize: Int64) -> Double {
        guard originalSize > 0 else { return 1.0 }
        return Double(originalSize) / Double(compressedSize)
    }
    
    /// Calculates optimal bitrate for a given resolution
    private static func calculateOptimalBitrateForResolution(resolution: CGSize) -> Double {
        let pixelCount = Double(resolution.width * resolution.height)
        
        // Bitrate recommendations for mobile optimization
        if pixelCount >= 3686400 { return 1_200_000 } // 1440p
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
    
    // MARK: - Testing & Validation
    
    /// Test duration-based compression strategy
    static func testCompressionStrategy() {
        print("🎬 TESTING DURATION-BASED COMPRESSION STRATEGY")
        
        let testCases: [(TimeInterval, UserTier, String)] = [
            (90, .rookie, "Short video - Regular user"),
            (90, .topCreator, "Short video - Premium user"),
            (180, .rookie, "Medium video - Regular user"),
            (180, .partner, "Medium video - Premium user"),
            (420, .rookie, "Long video - Regular user"),
            (420, .legendary, "Long video - Premium user"),
            (600, .founder, "Very long video - Founder")
        ]
        
        for (duration, tier, description) in testCases {
            let resolution = calculateOptimalResolution(duration: duration, userTier: tier)
            let strategy = getCompressionStrategyDescription(duration: duration, userTier: tier)
            
            print("📊 \(description):")
            print("   Duration: \(Int(duration))s | Tier: \(tier.displayName)")
            print("   Resolution: \(Int(resolution.width))x\(Int(resolution.height))")
            print("   Strategy: \(strategy)")
            print("")
        }
        
        print("✅ Duration-based compression strategy testing complete")
    }
}
