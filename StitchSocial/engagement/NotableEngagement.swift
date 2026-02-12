//
//  NotableEngagement.swift
//  StitchSocial
//
//  Created by James Garmon on 2/7/26.
//


//
//  NotableEngagement.swift
//  StitchSocial
//
//  Layer 2: Data Models - Notable Engagement & Social Signal Types
//  Dependencies: Foundation only
//  Features: Records high-tier hypes for megaphone distribution
//

import Foundation

// MARK: - Notable Engagement Record

/// Written to videos/{videoID}/notableEngagements/{docID}
/// when a Partner+ tier user hypes a video
struct NotableEngagement: Codable, Identifiable {
    let id: String
    let engagerID: String
    let engagerName: String
    let engagerTier: String
    let engagerProfileImageURL: String?
    let videoID: String
    let videoCreatorID: String
    let hypeWeight: Int              // Visual hypes given (tier multiplied)
    let cloutAwarded: Int
    let createdAt: Date
    
    /// Minimum tier to qualify as notable
    static let megaphoneTiers: Set<String> = [
        "partner", "elite", "ambassador", "legendary", "topCreator", "coFounder", "founder"
    ]
    
    static func isMegaphoneTier(_ tier: String) -> Bool {
        megaphoneTiers.contains(tier)
    }
}

// MARK: - Social Signal (Feed Injection Record)

/// Written to users/{followerID}/socialSignals/{docID}
/// One per follower of the engager, for feed injection
struct SocialSignal: Codable, Identifiable {
    let id: String
    let videoID: String
    let videoCreatorID: String
    let videoCreatorName: String
    let videoTitle: String
    let videoThumbnailURL: String?
    let engagerID: String
    let engagerName: String
    let engagerTier: String
    let engagerProfileImageURL: String?
    let hypeWeight: Int
    let createdAt: Date
    
    // Impression tracking (2-strike dismissal)
    var impressionCount: Int
    var dismissed: Bool               // True after 2 impressions with no engagement
    var engagedWith: Bool             // True if user tapped in / hyped / etc
    var lastImpressionAt: Date?
    
    init(
        id: String = UUID().uuidString,
        videoID: String,
        videoCreatorID: String,
        videoCreatorName: String,
        videoTitle: String,
        videoThumbnailURL: String?,
        engagerID: String,
        engagerName: String,
        engagerTier: String,
        engagerProfileImageURL: String?,
        hypeWeight: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoID = videoID
        self.videoCreatorID = videoCreatorID
        self.videoCreatorName = videoCreatorName
        self.videoTitle = videoTitle
        self.videoThumbnailURL = videoThumbnailURL
        self.engagerID = engagerID
        self.engagerName = engagerName
        self.engagerTier = engagerTier
        self.engagerProfileImageURL = engagerProfileImageURL
        self.hypeWeight = hypeWeight
        self.createdAt = createdAt
        self.impressionCount = 0
        self.dismissed = false
        self.engagedWith = false
        self.lastImpressionAt = nil
    }
}

// MARK: - Signal Impression Event

/// Lightweight event for tracking card views in feed
struct SignalImpression {
    let signalID: String
    let userID: String
    let timestamp: Date
    let didEngage: Bool
}