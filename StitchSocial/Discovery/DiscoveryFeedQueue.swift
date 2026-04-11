//
//  DiscoveryFeedQueue.swift
//  StitchSocial
//
//  Layer 4: Services — Discovery Feed Memory Queue (REWRITTEN)
//
//  ARCHITECTURE (simple cursor-based):
//  - Ordered array of all fetched videos — no feedSeed, no notIn, no windows
//  - Firestore cursor (DocumentSnapshot) advances forward through createdAt DESC
//  - Fetch 20 on initial load. Prefetch next 20 when user is 5 from end.
//  - Append to tail — never reshuffle mid-stream
//  - Creator diversity: max 2 of the same creator per 15-video window
//    (push extras to back of queue, client-side only — zero reads)
//  - Catalog exhausted (Firestore returns 0): shuffle everything in-memory,
//    reset cursor to nil — replay from beginning with fresh order
//
//  CACHING: Memory only. Cursor stored in-memory for session.
//  BATCHING: Fetch size 20. Background prefetch fires when 5 from end.
//

import Foundation
import FirebaseFirestore

@MainActor
class DiscoveryFeedQueue {

    static let shared = DiscoveryFeedQueue()
    private init() {}

    // MARK: - State

    /// All fetched videos in play order
    private(set) var queue: [CoreVideoMetadata] = []

    /// Firestore cursor — nil means fetch from beginning
    private(set) var lastDocument: DocumentSnapshot? = nil

    /// True when Firestore returned < batch size (end of catalog)
    private(set) var catalogExhausted = false

    /// Background fetch guard
    var isFetching = false

    /// How many videos the UI has consumed (for diversity window tracking)
    private(set) var consumedCount = 0

    // MARK: - Constants

    private let batchSize = 20
    private let prefetchThreshold = 5   // fetch next batch when 5 from end
    private let creatorWindowSize = 15  // max 2 from same creator per 15 videos
    private let creatorWindowMax = 2

    // MARK: - Public Interface

    /// Called by ViewModel on initial load
    func reset() {
        queue.removeAll()
        lastDocument = nil
        catalogExhausted = false
        isFetching = false
        consumedCount = 0
        print("🔄 FEED QUEUE: Reset")
    }

    /// Returns the current play queue for the UI — all fetched so far
    var playQueue: [CoreVideoMetadata] { queue }

    /// Append a fresh batch from Firestore (deduplicated, diversity-adjusted)
    func append(videos: [CoreVideoMetadata], lastDoc: DocumentSnapshot?, hasMore: Bool) {
        let existingIDs = Set(queue.map { $0.id })
        let fresh = videos.filter { !existingIDs.contains($0.id) }
        let diversified = applyCreatorDiversity(incoming: fresh, existingTail: Array(queue.suffix(creatorWindowSize)))
        queue.append(contentsOf: diversified)
        lastDocument = lastDoc
        catalogExhausted = !hasMore
        print("🎯 FEED QUEUE: +\(diversified.count) videos (total: \(queue.count), exhausted: \(catalogExhausted))")
    }

    /// Call when UI advances to `index` — returns true if a prefetch should fire
    func advance(to index: Int) -> Bool {
        consumedCount = max(consumedCount, index)
        let remaining = queue.count - index
        // Only prefetch if we've actually consumed some content (index > 3)
        // and we're close to the end — prevents immediate trigger on small batches
        return index > 3 && remaining <= prefetchThreshold && !isFetching && !catalogExhausted
    }

    /// Called when catalog is exhausted — shuffle everything, reset cursor
    func reshuffleForReplay() {
        queue.shuffle()
        lastDocument = nil
        catalogExhausted = false
        consumedCount = 0
        print("♻️ FEED QUEUE: Catalog exhausted — reshuffled \(queue.count) videos for replay")
    }

    // MARK: - Creator Diversity

    /// Ensures max `creatorWindowMax` per creator per `creatorWindowSize` window.
    /// Pushes excess to the back of the incoming batch — zero reads, O(n).
    private func applyCreatorDiversity(
        incoming: [CoreVideoMetadata],
        existingTail: [CoreVideoMetadata]
    ) -> [CoreVideoMetadata] {
        // Count creator occurrences in the last window already in queue
        var creatorCounts: [String: Int] = [:]
        for video in existingTail {
            creatorCounts[video.creatorID, default: 0] += 1
        }

        var promoted: [CoreVideoMetadata] = []
        var deferred: [CoreVideoMetadata] = []

        for video in incoming {
            let count = creatorCounts[video.creatorID, default: 0]
            if count < creatorWindowMax {
                promoted.append(video)
                creatorCounts[video.creatorID, default: 0] += 1
            } else {
                deferred.append(video)
            }
        }

        // Deferred go at back so they eventually surface fairly
        return promoted + deferred
    }
}
