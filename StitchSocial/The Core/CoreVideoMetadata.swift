//
//  CoreVideoMetadata.swift
//  CleanBeta
//
//  Foundation layer - Depends only on CoreTypes
//  Single source of truth for all video content - Reddit/Twitch style with full engagement system
//  Handles Thread/Child/Stepchild logic + Quality scoring + Engagement metrics + Temperature system
//

import Foundation
import SwiftUI

/// Single source of truth for all video content - Reddit/Twitch style with full engagement system
/// Handles Thread/Stitch/Reply logic + Quality scoring + Engagement metrics + Temperature system
struct CoreVideoMetadata: Identifiable, Codable, Hashable {
    // MARK: - Core Identity
    let id: String
    let title: String
    let videoURL: String
    let thumbnailURL: String
    let creatorID: String
    let creatorName: String
    let createdAt: Date
    
    // MARK: - Thread/Parent-Child-Stepchild Logic
    /// nil = new thread (parent), value = part of existing thread
    let threadID: String?
    
    /// nil = thread/child, value = stepchild responding to specific child
    let replyToVideoID: String?
    
    /// 0 = thread/child, 1 = stepchild responding to child
    let conversationDepth: Int
    
    // MARK: - Engagement Metrics (Reddit/Twitch Style)
    let viewCount: Int
    let hypeCount: Int
    let coolCount: Int
    let replyCount: Int
    let shareCount: Int
    
    // MARK: - Quality & Performance (Like Reddit's Scoring)
    let temperature: String // Raw string to avoid Temperature enum conflicts
    let qualityScore: Int
    let engagementRatio: Double  // hypes / (hypes + cools)
    let velocityScore: Double    // recent engagement rate
    let trendingScore: Double    // algorithmic trending weight
    
    // MARK: - Content Metadata
    let duration: TimeInterval
    let aspectRatio: Double
    let fileSize: Int64
    
    // MARK: - Algorithmic Data (Twitch-style)
    let discoverabilityScore: Double  // How likely to appear in feeds
    let isPromoted: Bool             // Algorithmic boost flag
    let lastEngagementAt: Date?      // Most recent interaction
    
    // MARK: - Computed Properties
    
    /// True if this video started a new thread (parent)
    var isThread: Bool {
        threadID == id
    }
    
    /// True if this video is a direct reply to thread starter (child)
    var isChild: Bool {
        threadID != nil && threadID != id && replyToVideoID == nil
    }
    
    /// True if this video is a response to a child (stepchild)
    var isStepchild: Bool {
        replyToVideoID != nil && conversationDepth == 1
    }
    
    /// The root thread ID for this video (always the thread starter)
    var rootThreadID: String {
        threadID ?? id
    }
    
    /// Content type based on position in hierarchy
    var contentType: ContentType {
        if isThread {
            return .thread
        } else if isChild {
            return .child
        } else {
            return .stepchild
        }
    }
    
    /// Net engagement score (hypes - cools)
    var netScore: Int {
        hypeCount - coolCount
    }
    
    /// Total interactions (all engagement types)
    var totalInteractions: Int {
        hypeCount + coolCount + replyCount + shareCount
    }
    
    /// Engagement health ratio (0.0 to 1.0)
    var engagementHealth: Double {
        let total = hypeCount + coolCount
        return total > 0 ? Double(hypeCount) / Double(total) : 0.5
    }
    
    /// Views to engagement ratio (higher = more engaging content)
    var viewEngagementRatio: Double {
        return viewCount > 0 ? Double(totalInteractions) / Double(viewCount) : 0.0
    }
    
    /// Content age in hours
    var ageInHours: Double {
        Date().timeIntervalSince(createdAt) / 3600.0
    }
    
    /// Velocity score - engagement per hour since creation
    var engagementVelocity: Double {
        let age = max(ageInHours, 1.0) // Minimum 1 hour to avoid division by zero
        return Double(totalInteractions) / age
    }
    
    /// Thread hierarchy display string
    var hierarchyDescription: String {
        switch contentType {
        case .thread:
            return "Thread Starter"
        case .child:
            return "Reply to Thread"
        case .stepchild:
            return "Response to Reply"
        }
    }
    
    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formatted file size string
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .binary)
    }
    
    /// Display color based on temperature (FIXED: Removed duplicate "warm" case)
    var temperatureColor: Color {
        switch temperature.lowercased() {
        case "fire", "blazing": return .red
        case "hot": return .orange
        case "warm": return .yellow
        case "neutral": return .green
        case "cool": return .cyan
        case "cold", "frozen": return .blue
        default: return .gray
        }
    }
    
    /// Temperature emoji representation
    var temperatureEmoji: String {
        switch temperature.lowercased() {
        case "fire", "blazing": return "🔥"
        case "hot": return "🌶️"
        case "warm": return "☀️"
        case "neutral": return "😐"
        case "cool": return "❄️"
        case "cold", "frozen": return "🧊"
        default: return "📊"
        }
    }
    
    // MARK: - Hashable & Equatable Conformance
    
    static func == (lhs: CoreVideoMetadata, rhs: CoreVideoMetadata) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Factory Methods

extension CoreVideoMetadata {
    
    /// Creates a new thread (parent video)
    static func newThread(
        id: String = UUID().uuidString,
        title: String,
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: id, // Thread ID equals video ID for parent
            replyToVideoID: nil,
            conversationDepth: 0,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: 9.0/16.0, // Default vertical video
            fileSize: fileSize,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
    }
    
    /// Creates a child reply to a thread
    static func childReply(
        to threadID: String,
        title: String,
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: UUID().uuidString,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: threadID,
            replyToVideoID: nil, // Children don't reply to specific videos, just the thread
            conversationDepth: 1,
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: 9.0/16.0,
            fileSize: fileSize,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
    }
    
    /// Creates a stepchild response to a child
    static func stepchildResponse(
        to childVideoID: String,
        threadID: String,
        title: String,
        videoURL: String,
        thumbnailURL: String,
        creatorID: String,
        creatorName: String,
        duration: TimeInterval,
        fileSize: Int64
    ) -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: UUID().uuidString,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: Date(),
            threadID: threadID,
            replyToVideoID: childVideoID, // Stepchildren reply to specific child videos
            conversationDepth: 1, // Max depth in this system
            viewCount: 0,
            hypeCount: 0,
            coolCount: 0,
            replyCount: 0,
            shareCount: 0,
            temperature: "neutral",
            qualityScore: 50,
            engagementRatio: 0.5,
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: 9.0/16.0,
            fileSize: fileSize,
            discoverabilityScore: 0.5,
            isPromoted: false,
            lastEngagementAt: nil
        )
    }
}

// MARK: - Engagement Updates

extension CoreVideoMetadata {
    
    /// Creates a copy with updated engagement metrics
    func withUpdatedEngagement(
        viewCount: Int? = nil,
        hypeCount: Int? = nil,
        coolCount: Int? = nil,
        replyCount: Int? = nil,
        shareCount: Int? = nil,
        temperature: String? = nil
    ) -> CoreVideoMetadata {
        
        let newViewCount = viewCount ?? self.viewCount
        let newHypeCount = hypeCount ?? self.hypeCount
        let newCoolCount = coolCount ?? self.coolCount
        let newReplyCount = replyCount ?? self.replyCount
        let newShareCount = shareCount ?? self.shareCount
        let newTemperature = temperature ?? self.temperature
        
        // Recalculate derived metrics
        let newTotal = newHypeCount + newCoolCount
        let newEngagementRatio = newTotal > 0 ? Double(newHypeCount) / Double(newTotal) : 0.5
        let newTotalInteractions = newHypeCount + newCoolCount + newReplyCount + newShareCount
        let newVelocityScore = ageInHours > 0 ? Double(newTotalInteractions) / ageInHours : 0.0
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: conversationDepth,
            viewCount: newViewCount,
            hypeCount: newHypeCount,
            coolCount: newCoolCount,
            replyCount: newReplyCount,
            shareCount: newShareCount,
            temperature: newTemperature,
            qualityScore: qualityScore,
            engagementRatio: newEngagementRatio,
            velocityScore: newVelocityScore,
            trendingScore: trendingScore,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: Date()
        )
    }
    
    /// Creates a copy with updated algorithmic scores
    func withUpdatedScores(
        qualityScore: Int? = nil,
        trendingScore: Double? = nil,
        discoverabilityScore: Double? = nil,
        isPromoted: Bool? = nil
    ) -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdAt,
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: conversationDepth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: temperature,
            qualityScore: qualityScore ?? self.qualityScore,
            engagementRatio: engagementRatio,
            velocityScore: velocityScore,
            trendingScore: trendingScore ?? self.trendingScore,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore ?? self.discoverabilityScore,
            isPromoted: isPromoted ?? self.isPromoted,
            lastEngagementAt: lastEngagementAt
        )
    }
}

// MARK: - Thread Hierarchy Helpers

extension CoreVideoMetadata {
    
    /// Validates if this video can have replies based on depth limits
    var canHaveReplies: Bool {
        switch contentType {
        case .thread: return true // Threads can have children
        case .child: return true  // Children can have stepchildren
        case .stepchild: return false // Stepchildren cannot have replies (max depth reached)
        }
    }
    
    /// Maximum replies allowed for this video type
    var maxRepliesAllowed: Int {
        switch contentType {
        case .thread: return 10      // Max 10 children per thread
        case .child: return 10       // Max 10 stepchildren per child
        case .stepchild: return 0    // No replies allowed
        }
    }
    
    /// Display priority for sorting (threads > children > stepchildren)
    var displayPriority: Int {
        switch contentType {
        case .thread: return 332
        case .child: return 2
        case .stepchild: return 1
        }
    }
}
