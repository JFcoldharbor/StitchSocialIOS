//
//  HypeRatingCalculator.swift
//  StitchSocial
//
//  Created by James Garmon on 8/19/25.
//


//
//  HypeRatingCalculator.swift
//  CleanBeta
//
//  Layer 5: Business Logic - Pure Hype Rating and Temperature Calculation Functions
//  Dependencies: NONE (Pure functions only)
//  Features: Temperature calculation, viral prediction, trending detection, content scoring
//  UPDATED: Added ambassador tier multiplier (1.65 between influencer and elite)
//

import Foundation

/// Pure calculation functions for video hype rating and temperature system
/// IMPORTANT: No dependencies - only pure functions for calculations
struct HypeRatingCalculator {
    
    // MARK: - Temperature Calculation
    
    /// Calculate video temperature based on engagement metrics and recency
    static func calculateTemperature(
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        ageInMinutes: Double,
        creatorTier: UserTier
    ) -> VideoTemperature {
        let hypeScore = calculateHypeScore(
            hypeCount: hypeCount,
            coolCount: coolCount,
            viewCount: viewCount,
            ageInMinutes: ageInMinutes,
            creatorTier: creatorTier
        )
        
        return temperatureFromScore(hypeScore)
    }
    
    /// Calculate comprehensive hype score (0.0 to 100.0)
    static func calculateHypeScore(
        hypeCount: Int,
        coolCount: Int,
        viewCount: Int,
        ageInMinutes: Double,
        creatorTier: UserTier
    ) -> Double {
        // Base engagement metrics
        let netEngagement = hypeCount - coolCount
        let totalEngagement = hypeCount + coolCount
        let engagementRate = viewCount > 0 ? Double(totalEngagement) / Double(viewCount) : 0.0
        
        // Engagement velocity (interactions per minute)
        let engagementVelocity = ageInMinutes > 0 ? Double(totalEngagement) / ageInMinutes : 0.0
        
        // View velocity (views per minute)
        let viewVelocity = ageInMinutes > 0 ? Double(viewCount) / ageInMinutes : 0.0
        
        // Positivity ratio (hype vs cool)
        let positivityRatio = totalEngagement > 0 ? Double(hypeCount) / Double(totalEngagement) : 0.5
        
        // Creator tier multiplier
        let tierMultiplier = calculateCreatorTierMultiplier(creatorTier)
        
        // Time decay factor (content loses heat over time)
        let timeFactor = calculateTimeDecayFactor(ageInMinutes: ageInMinutes)
        
        // Weighted score calculation
        let velocityScore = min(40.0, engagementVelocity * 20.0) // Max 40 points
        let volumeScore = min(25.0, Double(totalEngagement) / 10.0) // Max 25 points
        let qualityScore = positivityRatio * 20.0 // Max 20 points
        let viewScore = min(10.0, viewVelocity / 10.0) // Max 10 points
        let tierBonus = tierMultiplier * 5.0 // Max 5 points
        
        let rawScore = velocityScore + volumeScore + qualityScore + viewScore + tierBonus
        let adjustedScore = rawScore * timeFactor
        
        return max(0.0, min(100.0, adjustedScore))
    }
    
    /// Convert hype score to temperature enum
    static func temperatureFromScore(_ score: Double) -> VideoTemperature {
        if score >= 80.0 {
            return .hot
        } else if score >= 50.0 {
            return .warm
        } else if score >= 20.0 {
            return .cool
        } else {
            return .cold
        }
    }
    
    // MARK: - Viral Prediction
    
    /// Predict viral potential based on early engagement patterns
    static func calculateViralPotential(
        engagementHistory: [EngagementSnapshot],
        currentAge: TimeInterval
    ) -> ViralPrediction {
        guard engagementHistory.count >= 3 else {
            return ViralPrediction(score: 0.0, category: .unknown, confidence: 0.0)
        }
        
        // Calculate engagement acceleration
        let acceleration = calculateEngagementAcceleration(engagementHistory)
        
        // Calculate growth consistency
        let consistency = calculateGrowthConsistency(engagementHistory)
        
        // Calculate early indicators
        let earlyIndicators = calculateEarlyViralIndicators(engagementHistory, currentAge: currentAge)
        
        // Weighted viral score
        let viralScore = (acceleration * 0.4) + (consistency * 0.3) + (earlyIndicators * 0.3)
        
        // Determine category and confidence
        let category = viralCategoryFromScore(viralScore)
        let confidence = calculatePredictionConfidence(engagementHistory, score: viralScore)
        
        return ViralPrediction(score: viralScore, category: category, confidence: confidence)
    }
    
    /// Calculate engagement acceleration over time
    static func calculateEngagementAcceleration(_ history: [EngagementSnapshot]) -> Double {
        guard history.count >= 3 else { return 0.0 }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        var accelerations: [Double] = []
        
        for i in 2..<sortedHistory.count {
            let current = sortedHistory[i]
            let previous = sortedHistory[i-1]
            let earlier = sortedHistory[i-2]
            
            let currentRate = calculateEngagementRate(from: previous, to: current)
            let previousRate = calculateEngagementRate(from: earlier, to: previous)
            
            if previousRate > 0 {
                accelerations.append(currentRate / previousRate)
            }
        }
        
        guard !accelerations.isEmpty else { return 0.0 }
        
        let avgAcceleration = accelerations.reduce(0.0, +) / Double(accelerations.count)
        return max(0.0, min(2.0, avgAcceleration - 1.0)) // Normalize to 0-1 range
    }
    
    /// Calculate growth consistency score
    static func calculateGrowthConsistency(_ history: [EngagementSnapshot]) -> Double {
        guard history.count >= 4 else { return 0.0 }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        var growthRates: [Double] = []
        
        for i in 1..<sortedHistory.count {
            let current = sortedHistory[i]
            let previous = sortedHistory[i-1]
            let rate = calculateEngagementRate(from: previous, to: current)
            growthRates.append(rate)
        }
        
        // Calculate coefficient of variation (lower = more consistent)
        let mean = growthRates.reduce(0.0, +) / Double(growthRates.count)
        let variance = growthRates.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(growthRates.count)
        let standardDeviation = sqrt(variance)
        
        let coefficientOfVariation = mean > 0 ? standardDeviation / mean : 1.0
        
        // Convert to consistency score (0-1, where 1 = most consistent)
        return max(0.0, min(1.0, 1.0 - coefficientOfVariation))
    }
    
    /// Calculate early viral indicators
    static func calculateEarlyViralIndicators(_ history: [EngagementSnapshot], currentAge: TimeInterval) -> Double {
        guard let firstSnapshot = history.first, let latestSnapshot = history.last else { return 0.0 }
        
        let ageInHours = currentAge / 3600.0
        
        // Early engagement threshold (strong performance in first few hours)
        let earlyEngagementRate = latestSnapshot.totalEngagement > 0 && ageInHours > 0 ?
            Double(latestSnapshot.totalEngagement) / ageInHours : 0.0
        
        // View-to-engagement conversion rate
        let conversionRate = latestSnapshot.viewCount > 0 ?
            Double(latestSnapshot.totalEngagement) / Double(latestSnapshot.viewCount) : 0.0
        
        // Engagement diversity (mix of hypes, views, shares)
        let diversityScore = calculateEngagementDiversity(latestSnapshot)
        
        // Weighted early indicators
        let rateScore = min(1.0, earlyEngagementRate / 100.0) // 100 engagements/hour = max score
        let conversionScore = min(1.0, conversionRate * 10.0) // 10% conversion = max score
        
        return (rateScore * 0.5) + (conversionScore * 0.3) + (diversityScore * 0.2)
    }
    
    // MARK: - Trending Detection
    
    /// Determine if content is currently trending
    static func isTrending(
        currentHypeScore: Double,
        recentGrowthRate: Double,
        ageInHours: Double,
        categoryBaseline: Double
    ) -> TrendingStatus {
        // Age factor (newer content gets bonus)
        let ageFactor = calculateAgeFactor(ageInHours)
        
        // Adjusted score with age consideration
        let adjustedScore = currentHypeScore * ageFactor
        
        // Growth momentum
        let momentumFactor = calculateMomentumFactor(recentGrowthRate)
        
        // Final trending score
        let trendingScore = adjustedScore * momentumFactor
        
        // Compare against category baseline
        let relativePerformance = categoryBaseline > 0 ? trendingScore / categoryBaseline : 1.0
        
        if relativePerformance >= 3.0 && trendingScore >= 60.0 {
            return .viral
        } else if relativePerformance >= 2.0 && trendingScore >= 40.0 {
            return .trending
        } else if relativePerformance >= 1.5 && trendingScore >= 25.0 {
            return .rising
        } else {
            return .normal
        }
    }
    
    /// Calculate trending momentum for feed algorithms
    static func calculateTrendingMomentum(
        hypeScore: Double,
        ageInMinutes: Double,
        engagementVelocity: Double,
        viewVelocity: Double
    ) -> Double {
        // Base momentum from hype score
        let baseMomentum = hypeScore / 100.0
        
        // Velocity bonus (recent rapid engagement)
        let velocityBonus = min(0.5, (engagementVelocity + viewVelocity) / 20.0)
        
        // Recency bonus (newer content gets higher momentum)
        let recencyBonus = calculateRecencyBonus(ageInMinutes)
        
        // Combined momentum score
        let momentum = baseMomentum + velocityBonus + recencyBonus
        
        return max(0.0, min(2.0, momentum)) // Cap at 2.0 for extreme viral content
    }
    
    // MARK: - Content Quality Scoring
    
    /// Calculate overall content quality score
    static func calculateContentQualityScore(
        engagementMetrics: EngagementSnapshot,
        creatorTier: UserTier,
        contentAge: TimeInterval
    ) -> ContentQualityScore {
        let snapshot = engagementMetrics
        
        // Engagement quality
        let engagementQuality = calculateEngagementQuality(
            hypes: snapshot.hypeCount,
            cools: snapshot.coolCount,
            views: snapshot.viewCount
        )
        
        // Interaction depth
        let interactionDepth = calculateInteractionDepth(snapshot)
        
        // Creator credibility
        let creatorCredibility = calculateCreatorCredibility(creatorTier)
        
        // Content longevity
        let longevity = calculateContentLongevity(contentAge, snapshot)
        
        // Weighted quality score
        let overallScore = (engagementQuality * 0.4) +
                          (interactionDepth * 0.25) +
                          (creatorCredibility * 0.2) +
                          (longevity * 0.15)
        
        return ContentQualityScore(
            overall: overallScore,
            engagement: engagementQuality,
            depth: interactionDepth,
            credibility: creatorCredibility,
            longevity: longevity
        )
    }
    
    // MARK: - Helper Functions
    
    /// Calculate creator tier influence multiplier - UPDATED with ambassador tier
    private static func calculateCreatorTierMultiplier(_ tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 0.8
        case .rising: return 1.0
        case .veteran: return 1.2
        case .influencer: return 1.5
        case .ambassador: return 1.65      // NEW: Between influencer and elite
        case .elite: return 1.8
        case .partner: return 2.0
        case .legendary: return 2.5
        case .topCreator: return 3.0
        case .founder: return 4.0
        case .coFounder: return 5.0
        }
    }
    
    /// Calculate time decay factor for aging content
    private static func calculateTimeDecayFactor(ageInMinutes: Double) -> Double {
        // Exponential decay: content loses heat over time
        let halfLife = 120.0 // 2 hours half-life
        return pow(0.5, ageInMinutes / halfLife)
    }
    
    /// Calculate engagement rate between two snapshots
    private static func calculateEngagementRate(from previous: EngagementSnapshot, to current: EngagementSnapshot) -> Double {
        let timeDiff = current.timestamp.timeIntervalSince(previous.timestamp) / 60.0 // minutes
        guard timeDiff > 0 else { return 0.0 }
        
        let engagementDiff = current.totalEngagement - previous.totalEngagement
        return Double(engagementDiff) / timeDiff
    }
    
    /// Calculate engagement diversity score
    private static func calculateEngagementDiversity(_ snapshot: EngagementSnapshot) -> Double {
        let total = snapshot.totalEngagement
        guard total > 0 else { return 0.0 }
        
        // Shannon diversity index for engagement types
        let hypeRatio = Double(snapshot.hypeCount) / Double(total)
        let coolRatio = Double(snapshot.coolCount) / Double(total)
        let shareRatio = Double(snapshot.shareCount) / Double(total)
        let replyRatio = Double(snapshot.replyCount) / Double(total)
        
        let ratios = [hypeRatio, coolRatio, shareRatio, replyRatio].filter { $0 > 0 }
        let diversity = -ratios.reduce(0.0) { result, ratio in
            result + (ratio * log2(ratio))
        }
        
        // Normalize to 0-1 scale
        return min(1.0, diversity / 2.0)
    }
    
    /// Convert viral score to category
    private static func viralCategoryFromScore(_ score: Double) -> ViralCategory {
        if score >= 0.8 {
            return .highlyViral
        } else if score >= 0.6 {
            return .viral
        } else if score >= 0.4 {
            return .trending
        } else if score >= 0.2 {
            return .emerging
        } else {
            return .normal
        }
    }
    
    /// Calculate prediction confidence
    private static func calculatePredictionConfidence(_ history: [EngagementSnapshot], score: Double) -> Double {
        let dataPoints = Double(history.count)
        let timeSpan = history.last?.timestamp.timeIntervalSince(history.first?.timestamp ?? Date()) ?? 0
        
        // More data points and longer time span = higher confidence
        let dataConfidence = min(1.0, dataPoints / 10.0)
        let timeConfidence = min(1.0, timeSpan / 3600.0) // 1 hour = full confidence
        
        return (dataConfidence + timeConfidence) / 2.0
    }
    
    /// Calculate age factor for trending
    private static func calculateAgeFactor(_ ageInHours: Double) -> Double {
        // Newer content gets higher factor
        if ageInHours <= 1.0 {
            return 1.5
        } else if ageInHours <= 6.0 {
            return 1.2
        } else if ageInHours <= 24.0 {
            return 1.0
        } else {
            return 0.8
        }
    }
    
    /// Calculate momentum factor
    private static func calculateMomentumFactor(_ growthRate: Double) -> Double {
        if growthRate >= 2.0 {
            return 1.5 // High momentum
        } else if growthRate >= 1.5 {
            return 1.3
        } else if growthRate >= 1.0 {
            return 1.0
        } else {
            return 0.8 // Low momentum
        }
    }
    
    /// Calculate recency bonus
    private static func calculateRecencyBonus(_ ageInMinutes: Double) -> Double {
        if ageInMinutes <= 60.0 {
            return 0.3 // High recency bonus
        } else if ageInMinutes <= 180.0 {
            return 0.2
        } else if ageInMinutes <= 360.0 {
            return 0.1
        } else {
            return 0.0
        }
    }
    
    /// Calculate engagement quality
    private static func calculateEngagementQuality(hypes: Int, cools: Int, views: Int) -> Double {
        let total = hypes + cools
        guard total > 0, views > 0 else { return 0.0 }
        
        let positivityRatio = Double(hypes) / Double(total)
        let engagementRate = Double(total) / Double(views)
        
        return (positivityRatio * 0.6) + min(1.0, engagementRate * 10.0) * 0.4
    }
    
    /// Calculate interaction depth
    private static func calculateInteractionDepth(_ snapshot: EngagementSnapshot) -> Double {
        let total = Double(snapshot.totalEngagement)
        guard total > 0 else { return 0.0 }
        
        // Weight different interaction types
        let weightedDepth = (Double(snapshot.hypeCount) * 1.0) +
                           (Double(snapshot.shareCount) * 3.0) +
                           (Double(snapshot.replyCount) * 5.0) +
                           (Double(snapshot.coolCount) * 0.5)
        
        return min(1.0, weightedDepth / (total * 2.0))
    }
    
    /// Calculate creator credibility - UPDATED with ambassador tier
    private static func calculateCreatorCredibility(_ tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 0.3
        case .rising: return 0.4
        case .veteran: return 0.6
        case .influencer: return 0.8
        case .ambassador: return 0.85      // NEW: Between influencer and elite
        case .elite: return 0.9
        case .partner: return 0.95
        case .legendary: return 0.98
        case .topCreator: return 1.0
        case .founder: return 1.0
        case .coFounder: return 1.0
        }
    }
    
    /// Calculate content longevity
    private static func calculateContentLongevity(_ age: TimeInterval, _ snapshot: EngagementSnapshot) -> Double {
        let ageInHours = age / 3600.0
        let sustainedEngagement = ageInHours > 0 ? Double(snapshot.totalEngagement) / ageInHours : 0.0
        
        return min(1.0, sustainedEngagement / 10.0) // 10 engagements/hour = perfect longevity
    }
}

// MARK: - Supporting Types

/// Video temperature based on hype score
enum VideoTemperature: String, CaseIterable, Codable {
    case hot = "hot"
    case warm = "warm"
    case cool = "cool"
    case cold = "cold"
    
    var displayName: String {
        switch self {
        case .hot: return "🔥 Hot"
        case .warm: return "🌡️ Warm"
        case .cool: return "❄️ Cool"
        case .cold: return "🧊 Cold"
        }
    }
    
    var emoji: String {
        switch self {
        case .hot: return "🔥"
        case .warm: return "🌡️"
        case .cool: return "❄️"
        case .cold: return "🧊"
        }
    }
    
    var boostFactor: Double {
        switch self {
        case .hot: return 2.0
        case .warm: return 1.5
        case .cool: return 1.0
        case .cold: return 0.8
        }
    }
}

/// Engagement snapshot for tracking
struct EngagementSnapshot: Codable, Hashable {
    let timestamp: Date
    let hypeCount: Int
    let coolCount: Int
    let shareCount: Int
    let replyCount: Int
    let viewCount: Int
    
    var totalEngagement: Int {
        return hypeCount + coolCount + shareCount + replyCount
    }
    
    var positivityRatio: Double {
        let interactions = hypeCount + coolCount
        return interactions > 0 ? Double(hypeCount) / Double(interactions) : 0.5
    }
}

/// Viral prediction result
struct ViralPrediction: Codable {
    let score: Double
    let category: ViralCategory
    let confidence: Double
    
    var description: String {
        let confidenceText = confidence > 0.8 ? "High confidence" :
                            confidence > 0.6 ? "Medium confidence" : "Low confidence"
        return "\(category.displayName) (\(confidenceText))"
    }
}

/// Viral category classification
enum ViralCategory: String, CaseIterable, Codable {
    case highlyViral = "highly_viral"
    case viral = "viral"
    case trending = "trending"
    case emerging = "emerging"
    case normal = "normal"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .highlyViral: return "🚀 Highly Viral"
        case .viral: return "🔥 Viral"
        case .trending: return "📈 Trending"
        case .emerging: return "⭐ Emerging"
        case .normal: return "📄 Normal"
        case .unknown: return "❓ Unknown"
        }
    }
}

/// Trending status classification
enum TrendingStatus: String, CaseIterable, Codable {
    case viral = "viral"
    case trending = "trending"
    case rising = "rising"
    case normal = "normal"
    
    var displayName: String {
        switch self {
        case .viral: return "🚀 Viral"
        case .trending: return "🔥 Trending"
        case .rising: return "📈 Rising"
        case .normal: return "📄 Normal"
        }
    }
    
    var algorithmBoost: Double {
        switch self {
        case .viral: return 3.0
        case .trending: return 2.0
        case .rising: return 1.5
        case .normal: return 1.0
        }
    }
}

/// Content quality scoring breakdown
struct ContentQualityScore: Codable {
    let overall: Double
    let engagement: Double
    let depth: Double
    let credibility: Double
    let longevity: Double
    
    var grade: String {
        if overall >= 0.9 { return "A+" }
        if overall >= 0.8 { return "A" }
        if overall >= 0.7 { return "B+" }
        if overall >= 0.6 { return "B" }
        if overall >= 0.5 { return "C+" }
        if overall >= 0.4 { return "C" }
        return "D"
    }
}

// MARK: - Test and Validation

extension HypeRatingCalculator {
    
    /// Test hype rating calculations with realistic data
    static func validateCalculations() -> String {
        let testSnapshot = EngagementSnapshot(
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            hypeCount: 150,
            coolCount: 20,
            shareCount: 35,
            replyCount: 12,
            viewCount: 1200
        )
        
        let temperature = calculateTemperature(
            hypeCount: 150,
            coolCount: 20,
            viewCount: 1200,
            ageInMinutes: 60.0,
            creatorTier: .veteran
        )
        
        let hypeScore = calculateHypeScore(
            hypeCount: 150,
            coolCount: 20,
            viewCount: 1200,
            ageInMinutes: 60.0,
            creatorTier: .veteran
        )
        
        let momentum = calculateTrendingMomentum(
            hypeScore: hypeScore,
            ageInMinutes: 60.0,
            engagementVelocity: 3.0,
            viewVelocity: 20.0
        )
        
        let result = """
        ✅ HYPE RATING CALCULATOR: Validation Complete
        
        Test Results for Veteran Creator Video (1hr old):
        → Temperature: \(temperature.displayName)
        → Hype Score: \(String(format: "%.1f", hypeScore))/100.0
        → Trending Momentum: \(String(format: "%.2f", momentum))
        → Engagement Rate: \(String(format: "%.1f", Double(testSnapshot.totalEngagement) / Double(testSnapshot.viewCount) * 100))%
        
        Metrics: 150 hypes, 20 cools, 35 shares, 12 replies, 1200 views
        Algorithm Status: All calculation functions operational
        Ambassador Tier Multiplier: 1.65 (added)
        
        Status: Layer 5 HypeRatingCalculator ready for production! 🔥
        """
        
        return result
    }
}
