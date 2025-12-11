//
//  CollectionProgress.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionProgress.swift
//  StitchSocial
//
//  Layer 1: Foundation - Collection Watch Progress Tracking
//  Dependencies: Foundation only
//  Tracks user's viewing progress through collections for resume functionality
//  Enables "Continue watching" prompts and progress indicators
//  CREATED: Collections feature for long-form segmented content
//

import Foundation

// MARK: - Collection Progress

/// Tracks a user's viewing progress through a collection
/// Enables resume functionality and progress visualization
struct CollectionProgress: Identifiable, Codable, Hashable {
    
    // MARK: - Identity
    
    /// Unique ID: {userID}_{collectionID}
    let id: String
    
    /// User who is watching
    let userID: String
    
    /// Collection being watched
    let collectionID: String
    
    // MARK: - Current Position
    
    /// Currently playing segment ID
    var currentSegmentID: String
    
    /// Index of current segment (0-based)
    var currentSegmentIndex: Int
    
    /// Timestamp within current segment (seconds)
    var currentTimestamp: TimeInterval
    
    // MARK: - Progress Tracking
    
    /// IDs of fully watched segments
    var completedSegmentIDs: [String]
    
    /// Per-segment progress: [segmentID: lastTimestamp]
    var segmentProgress: [String: TimeInterval]
    
    /// Overall completion percentage (0.0 to 1.0)
    var percentComplete: Double
    
    /// Total watch time across all segments (seconds)
    var totalWatchTime: TimeInterval
    
    // MARK: - Timestamps
    
    /// When user first started watching
    let startedAt: Date
    
    /// Most recent watch activity
    var lastWatchedAt: Date
    
    // MARK: - Initialization
    
    init(
        userID: String,
        collectionID: String,
        currentSegmentID: String,
        currentSegmentIndex: Int = 0,
        currentTimestamp: TimeInterval = 0,
        completedSegmentIDs: [String] = [],
        segmentProgress: [String: TimeInterval] = [:],
        percentComplete: Double = 0.0,
        totalWatchTime: TimeInterval = 0,
        startedAt: Date = Date(),
        lastWatchedAt: Date = Date()
    ) {
        self.id = "\(userID)_\(collectionID)"
        self.userID = userID
        self.collectionID = collectionID
        self.currentSegmentID = currentSegmentID
        self.currentSegmentIndex = currentSegmentIndex
        self.currentTimestamp = currentTimestamp
        self.completedSegmentIDs = completedSegmentIDs
        self.segmentProgress = segmentProgress
        self.percentComplete = percentComplete
        self.totalWatchTime = totalWatchTime
        self.startedAt = startedAt
        self.lastWatchedAt = lastWatchedAt
    }
    
    // MARK: - Computed Properties
    
    /// True if user has started watching but not finished
    var isInProgress: Bool {
        return percentComplete > 0 && percentComplete < 1.0
    }
    
    /// True if user has completed the entire collection
    var isCompleted: Bool {
        return percentComplete >= 1.0
    }
    
    /// True if user hasn't started watching
    var isNotStarted: Bool {
        return percentComplete == 0 && totalWatchTime == 0
    }
    
    /// Number of segments completed
    var completedSegmentCount: Int {
        return completedSegmentIDs.count
    }
    
    /// Time since last watch activity
    var timeSinceLastWatch: TimeInterval {
        return Date().timeIntervalSince(lastWatchedAt)
    }
    
    /// Days since last watch activity
    var daysSinceLastWatch: Int {
        return Int(timeSinceLastWatch / (24 * 60 * 60))
    }
    
    /// Formatted total watch time
    var formattedTotalWatchTime: String {
        let hours = Int(totalWatchTime) / 3600
        let minutes = (Int(totalWatchTime) % 3600) / 60
        let seconds = Int(totalWatchTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Formatted current timestamp
    var formattedCurrentTimestamp: String {
        let minutes = Int(currentTimestamp) / 60
        let seconds = Int(currentTimestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Percentage as display string (e.g., "75%")
    var percentCompleteDisplay: String {
        return String(format: "%.0f%%", percentComplete * 100)
    }
    
    /// True if should show resume prompt (in progress and recent activity)
    var shouldShowResumePrompt: Bool {
        return isInProgress && daysSinceLastWatch < 30
    }
    
    /// Resume prompt text
    var resumePromptText: String {
        return "Continue from \(formattedCurrentTimestamp) in Part \(currentSegmentIndex + 1)?"
    }
    
    // MARK: - Hashable & Equatable
    
    static func == (lhs: CollectionProgress, rhs: CollectionProgress) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Progress Update Methods

extension CollectionProgress {
    
    /// Updates progress for current segment
    mutating func updateCurrentPosition(
        segmentID: String,
        segmentIndex: Int,
        timestamp: TimeInterval
    ) {
        self.currentSegmentID = segmentID
        self.currentSegmentIndex = segmentIndex
        self.currentTimestamp = timestamp
        self.segmentProgress[segmentID] = timestamp
        self.lastWatchedAt = Date()
    }
    
    /// Marks a segment as completed
    mutating func markSegmentCompleted(_ segmentID: String) {
        if !completedSegmentIDs.contains(segmentID) {
            completedSegmentIDs.append(segmentID)
        }
        lastWatchedAt = Date()
    }
    
    /// Adds watch time
    mutating func addWatchTime(_ seconds: TimeInterval) {
        totalWatchTime += seconds
        lastWatchedAt = Date()
    }
    
    /// Updates overall completion percentage
    mutating func updatePercentComplete(totalSegments: Int) {
        guard totalSegments > 0 else {
            percentComplete = 0
            return
        }
        percentComplete = Double(completedSegmentIDs.count) / Double(totalSegments)
    }
    
    /// Moves to next segment
    mutating func moveToNextSegment(
        nextSegmentID: String,
        nextSegmentIndex: Int
    ) {
        // Mark current as completed if we're moving forward
        if nextSegmentIndex > currentSegmentIndex {
            markSegmentCompleted(currentSegmentID)
        }
        
        currentSegmentID = nextSegmentID
        currentSegmentIndex = nextSegmentIndex
        currentTimestamp = 0
        lastWatchedAt = Date()
    }
    
    /// Gets progress for a specific segment
    func progress(for segmentID: String) -> TimeInterval {
        return segmentProgress[segmentID] ?? 0
    }
    
    /// Checks if a specific segment has been completed
    func isSegmentCompleted(_ segmentID: String) -> Bool {
        return completedSegmentIDs.contains(segmentID)
    }
    
    /// Resets progress (start over)
    mutating func reset(firstSegmentID: String) {
        currentSegmentID = firstSegmentID
        currentSegmentIndex = 0
        currentTimestamp = 0
        completedSegmentIDs = []
        segmentProgress = [:]
        percentComplete = 0
        // Keep totalWatchTime for analytics
        lastWatchedAt = Date()
    }
}

// MARK: - Factory Methods

extension CollectionProgress {
    
    /// Creates new progress for starting a collection
    static func startWatching(
        userID: String,
        collectionID: String,
        firstSegmentID: String
    ) -> CollectionProgress {
        return CollectionProgress(
            userID: userID,
            collectionID: collectionID,
            currentSegmentID: firstSegmentID,
            currentSegmentIndex: 0,
            currentTimestamp: 0,
            completedSegmentIDs: [],
            segmentProgress: [:],
            percentComplete: 0,
            totalWatchTime: 0,
            startedAt: Date(),
            lastWatchedAt: Date()
        )
    }
    
    /// Creates a completed progress record
    static func completed(
        userID: String,
        collectionID: String,
        segmentIDs: [String],
        totalWatchTime: TimeInterval
    ) -> CollectionProgress {
        return CollectionProgress(
            userID: userID,
            collectionID: collectionID,
            currentSegmentID: segmentIDs.last ?? "",
            currentSegmentIndex: segmentIDs.count - 1,
            currentTimestamp: 0,
            completedSegmentIDs: segmentIDs,
            segmentProgress: [:],
            percentComplete: 1.0,
            totalWatchTime: totalWatchTime,
            startedAt: Date(),
            lastWatchedAt: Date()
        )
    }
}

// MARK: - Storage Keys

extension CollectionProgress {
    
    /// Key for storing progress in local cache
    var storageKey: String {
        return "collection_progress_\(id)"
    }
    
    /// Key prefix for all progress by a user
    static func storageKeyPrefix(for userID: String) -> String {
        return "collection_progress_\(userID)"
    }
    
    /// Creates progress ID from user and collection IDs
    static func progressID(userID: String, collectionID: String) -> String {
        return "\(userID)_\(collectionID)"
    }
}

// MARK: - Resume Info

/// Lightweight struct for displaying resume prompts
struct CollectionResumeInfo: Codable {
    let collectionID: String
    let collectionTitle: String
    let currentSegmentIndex: Int
    let currentTimestamp: TimeInterval
    let percentComplete: Double
    let lastWatchedAt: Date
    
    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let minutes = Int(currentTimestamp) / 60
        let seconds = Int(currentTimestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Part number for display (1-based)
    var partNumber: Int {
        return currentSegmentIndex + 1
    }
    
    /// Resume prompt message
    var promptMessage: String {
        return "Continue from \(formattedTimestamp) in Part \(partNumber)?"
    }
    
    /// Days since last watch
    var daysSinceWatch: Int {
        return Int(Date().timeIntervalSince(lastWatchedAt) / (24 * 60 * 60))
    }
    
    /// True if this is a recent view (within last 7 days)
    var isRecent: Bool {
        return daysSinceWatch < 7
    }
}

// MARK: - Segment Watch Event

/// Event logged when user watches part of a segment
/// Used for analytics and engagement tracking
struct SegmentWatchEvent: Codable {
    let id: String
    let userID: String
    let collectionID: String
    let segmentID: String
    let segmentIndex: Int
    let startTimestamp: TimeInterval
    let endTimestamp: TimeInterval
    let watchDuration: TimeInterval
    let completedSegment: Bool
    let timestamp: Date
    
    init(
        userID: String,
        collectionID: String,
        segmentID: String,
        segmentIndex: Int,
        startTimestamp: TimeInterval,
        endTimestamp: TimeInterval,
        completedSegment: Bool = false
    ) {
        self.id = UUID().uuidString
        self.userID = userID
        self.collectionID = collectionID
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.watchDuration = endTimestamp - startTimestamp
        self.completedSegment = completedSegment
        self.timestamp = Date()
    }
    
    /// True if this was a significant watch (> 5 seconds)
    var isSignificantWatch: Bool {
        return watchDuration >= 5.0
    }
}