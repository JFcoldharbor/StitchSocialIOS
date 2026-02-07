//
//  RecordingSource.swift
//  StitchSocial
//
//  Created by James Garmon on 2/5/26.
//


//
//  ContentScoreCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Dynamic Quality & Discoverability Score Calculations
//  Dependencies: CoreVideoMetadata, EngagementConfig
//  Features: Recording source multipliers, engagement-based quality scoring, dynamic discoverability
//

import Foundation

// MARK: - Recording Source

/// Tracks how a video was created — used for authenticity scoring
enum RecordingSource: String, Codable {
    case inApp = "inApp"              // Recorded live via tap-and-hold in StitchSocial
    case cameraRoll = "cameraRoll"    // Uploaded from device photo library
    case unknown = "unknown"          // Legacy content or undetermined
    
    /// Discoverability multiplier — rewards authentic in-app content
    var discoverabilityMultiplier: Double {
        switch self {
        case .inApp:      return 1.25   // 25% boost for live-recorded content
        case .cameraRoll: return 0.70   // 30% penalty for uploads
        case .unknown:    return 0.85   // Slight penalty for legacy/unknown
        }
    }
    
    /// Display label for UI badge
    var badgeLabel: String? {
        switch self {
        case .inApp: return "Recorded Live"
        case .cameraRoll: return nil
        case .unknown: return nil
        }
    }
}

// MARK: - Content Score Calculator

/// Calculates dynamic qualityScore (0–100) and discoverabilityScore (0.0–1.0)
/// based on real engagement data, recording source, and content signals.
struct ContentScoreCalculator {
    
    // MARK: - Quality Score (0–100)
    
    /// Recalculate qualityScore from engagement data
    /// Components:
    ///   - Engagement ratio (hype vs cool):  0–25 points
    ///   - Reply depth / conversation:       0–20 points
    ///   - Share traction:                   0–15 points
    ///   - View-to-engagement conversion:    0–20 points
    ///   - Content completeness:             0–10 points
    ///   - Recording source bonus:           0–10 points
    static func calculateQualityScore(
        hypeCount: Int,
        coolCount: Int,
        replyCount: Int,
        shareCount: Int,
        viewCount: Int,
        conversationDepth: Int,
        duration: TimeInterval,
        recordingSource: RecordingSource
    ) -> Int {
        
        // 1. Engagement ratio (0–25)
        let totalReactions = hypeCount + coolCount
        let positivityRatio: Double = totalReactions > 0
            ? Double(hypeCount) / Double(totalReactions)
            : 0.5
        let engagementPoints = positivityRatio * 25.0
        
        // 2. Reply/conversation depth (0–20)
        //    More replies = more valuable content that sparks conversation
        let replyPoints = min(20.0, Double(replyCount) * 2.0)
        
        // 3. Share traction (0–15)
        let sharePoints = min(15.0, Double(shareCount) * 3.0)
        
        // 4. View-to-engagement conversion (0–20)
        //    High engagement relative to views = quality content
        let totalEngagement = hypeCount + coolCount + replyCount + shareCount
        let conversionRate: Double = viewCount > 0
            ? Double(totalEngagement) / Double(viewCount)
            : 0.0
        let conversionPoints = min(20.0, conversionRate * 100.0)
        
        // 5. Content completeness (0–10)
        //    Reasonable duration = not too short, not filler
        let durationPoints: Double
        if duration >= 5.0 && duration <= 45.0 {
            durationPoints = 10.0  // Sweet spot
        } else if duration >= 3.0 && duration <= 55.0 {
            durationPoints = 6.0   // Acceptable
        } else {
            durationPoints = 2.0   // Very short or maxed out
        }
        
        // 6. Recording source bonus (0–10)
        let sourcePoints: Double
        switch recordingSource {
        case .inApp:      sourcePoints = 10.0
        case .cameraRoll: sourcePoints = 2.0
        case .unknown:    sourcePoints = 4.0
        }
        
        let rawScore = engagementPoints + replyPoints + sharePoints + conversionPoints + durationPoints + sourcePoints
        return max(0, min(100, Int(rawScore)))
    }
    
    // MARK: - Discoverability Score (0.0–1.0)
    
    /// Recalculate discoverabilityScore from quality, recency, temperature, and source
    /// This is the primary feed ranking signal.
    static func calculateDiscoverabilityScore(
        qualityScore: Int,
        temperature: String,
        createdAt: Date,
        recordingSource: RecordingSource,
        hypeCount: Int,
        viewCount: Int,
        replyCount: Int,
        isPromoted: Bool
    ) -> Double {
        
        // 1. Quality base (0.0–0.40)
        let qualityBase = (Double(qualityScore) / 100.0) * 0.40
        
        // 2. Temperature multiplier (0.0–0.25)
        let temperatureBonus: Double
        switch temperature {
        case "blazing": temperatureBonus = 0.25
        case "hot":     temperatureBonus = 0.20
        case "warm":    temperatureBonus = 0.12
        case "neutral": temperatureBonus = 0.05
        case "cold":    temperatureBonus = 0.0
        default:        temperatureBonus = 0.05
        }
        
        // 3. Recency decay (0.0–0.20)
        //    Content loses discoverability over time unless engagement sustains it
        let ageHours = max(0, Date().timeIntervalSince(createdAt) / 3600.0)
        let recencyScore: Double
        if ageHours < 1 {
            recencyScore = 0.20       // Brand new — full recency boost
        } else if ageHours < 6 {
            recencyScore = 0.16
        } else if ageHours < 24 {
            recencyScore = 0.10
        } else if ageHours < 72 {
            recencyScore = 0.05
        } else {
            recencyScore = 0.01       // Old content — minimal recency
        }
        
        // 4. Recording source multiplier (applied to total)
        let sourceMultiplier = recordingSource.discoverabilityMultiplier
        
        // 5. Engagement velocity bonus (0.0–0.15)
        //    Rewards content gaining traction quickly
        let velocityBase: Double = ageHours > 0
            ? Double(hypeCount + replyCount) / ageHours
            : Double(hypeCount + replyCount)
        let velocityBonus = min(0.15, velocityBase / 200.0)
        
        // Combine
        var rawScore = (qualityBase + temperatureBonus + recencyScore + velocityBonus) * sourceMultiplier
        
        // Promoted content gets a flat boost
        if isPromoted {
            rawScore += 0.10
        }
        
        return max(0.0, min(1.0, rawScore))
    }
    
    // MARK: - Convenience: Full Recalculation
    
    /// Recalculate both scores for a video — returns (qualityScore, discoverabilityScore)
    static func recalculateScores(for video: CoreVideoMetadata) -> (qualityScore: Int, discoverabilityScore: Double) {
        
        let source = RecordingSource(rawValue: video.recordingSource) ?? .unknown
        
        let quality = calculateQualityScore(
            hypeCount: video.hypeCount,
            coolCount: video.coolCount,
            replyCount: video.replyCount,
            shareCount: video.shareCount,
            viewCount: video.viewCount,
            conversationDepth: video.conversationDepth,
            duration: video.duration,
            recordingSource: source
        )
        
        let discoverability = calculateDiscoverabilityScore(
            qualityScore: quality,
            temperature: video.temperature,
            createdAt: video.createdAt,
            recordingSource: source,
            hypeCount: video.hypeCount,
            viewCount: video.viewCount,
            replyCount: video.replyCount,
            isPromoted: video.isPromoted
        )
        
        return (quality, discoverability)
    }
}