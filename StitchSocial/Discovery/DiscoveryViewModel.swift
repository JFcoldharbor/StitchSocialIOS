//
//  DiscoveryViewModel.swift
//  StitchSocial
//
//  SIMPLE DISCOVERY: One query, all videos, shuffle on exhaust.
//  Load all videos once → display in order → shuffle at end → repeat.
//
//  FIXES:
//  - Shuffle on initial load so first session isn't always newest-first
//  - swipeIndex moved here so tab returns restore position (not reset to 0)
//  - karmenaesthetic diagnostic: logs why each video is filtered out
//

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
class DiscoveryViewModel: ObservableObject {

    // MARK: - Feed State
    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var errorMessage: String?

    // FIX: Swipe index lives in ViewModel so tab returns restore position
    @Published var swipeIndex: Int = 0

    // Collections
    @Published var discoveryCollections: [VideoCollection] = []
    @Published var isLoadingCollections = false
    var collectionCardMap: [String: VideoCollection] = [:]

    // Hashtags
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var isLoadingHashtags = false
    @Published var selectedHashtag: TrendingHashtag?
    @Published var hashtagVideos: [CoreVideoMetadata] = []

    // MARK: - Private
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let discoveryService = DiscoveryService()
    private let collectionService = CollectionService()
    private let hashtagService = HashtagService()
    private let videoService = VideoService()
    private var allVideos: [CoreVideoMetadata] = []   // full catalog in memory
    private var hasLoaded = false
    private var lastLoadedAt: Date? = nil
    private let staleDuration: TimeInterval = 30 * 60  // 30 min — refresh if app foregrounded after this

    // MARK: - Diagnostic: creator IDs to trace through filters
    // Add any creatorID here to get per-video filter logs
    private let trackedCreatorIDs: Set<String> = [
        "C8XHI9GpUrShtMXm3iLVCT4tle93",  // LetsFaceIt
        "cJsxoB3DuWS64tbuqt4xtoeRMDS2"   // karmenaesthetic (correct UID from Firestore)
    ]

    // MARK: - Load All Videos (one query, entire session)
    // CACHING: Results are session-scoped in allVideos. No repeat reads until refreshContent().

    func loadInitialContent() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()

            var filteredOut: [String: Int] = [
                "isDeleted": 0,
                "isCollectionSegment": 0,
                "depth>0": 0,
                "notPublic": 0,
                "emptyURL": 0
            ]

            let loaded = snapshot.documents.compactMap { doc -> CoreVideoMetadata? in
                let data = doc.data()
                let creatorID = data["creatorID"] as? String ?? ""
                let isTracked = trackedCreatorIDs.contains(creatorID)

                if data["isDeleted"] as? Bool == true {
                    filteredOut["isDeleted"]! += 1
                    if isTracked { print("🔍 DISCOVERY TRACE [\(creatorID.prefix(8))]: filtered — isDeleted") }
                    return nil
                }
                if data["isCollectionSegment"] as? Bool == true {
                    filteredOut["isCollectionSegment"]! += 1
                    if isTracked { print("🔍 DISCOVERY TRACE [\(creatorID.prefix(8))]: filtered — isCollectionSegment") }
                    return nil
                }
                let depth = data["conversationDepth"] as? Int ?? 0
                if depth > 0 {
                    filteredOut["depth>0"]! += 1
                    if isTracked { print("🔍 DISCOVERY TRACE [\(creatorID.prefix(8))]: filtered — depth=\(depth)") }
                    return nil
                }
                let vis = data["visibility"] as? String ?? "public"
                if vis == "private" || vis == "followersOnly" {
                    filteredOut["notPublic"]! += 1
                    if isTracked { print("🔍 DISCOVERY TRACE [\(creatorID.prefix(8))]: filtered — visibility=\(vis)") }
                    return nil
                }
                guard let url = data["videoURL"] as? String, !url.isEmpty else {
                    filteredOut["emptyURL"]! += 1
                    if isTracked { print("🔍 DISCOVERY TRACE [\(creatorID.prefix(8))]: filtered — empty videoURL") }
                    return nil
                }

                if isTracked { print("✅ DISCOVERY TRACE [\(creatorID.prefix(8))]: passed all filters") }
                return videoService.createCoreVideoMetadata(from: data, id: doc.documentID)
            }

            print("✅ DISCOVERY: Loaded \(loaded.count) / \(snapshot.documents.count) docs — filtered: \(filteredOut)")

            // FIX: Shuffle on initial load — 48hr fresh content always surfaces first
            allVideos = shuffleWithRecencyPin(loaded)
            hasLoaded = true
            lastLoadedAt = Date()

            // Fetch featured collections and inject as special cards in the swipe feed
            // CACHING: collectionCardMap is session-scoped â one read, zero repeats
            await loadFeaturedCollectionsForSwipeFeed()

            applyBlockedCreatorFilter()
            print("✅ DISCOVERY: \(allVideos.count) videos + \(collectionCardMap.count) collection cards injected")

        } catch {
            errorMessage = "Failed to load videos"
            print("❌ DISCOVERY: \(error)")
        }
    }

    // MARK: - Shuffle at end (called by view when user reaches last video)

    func reshuffleAndRestart() {
        allVideos = shuffleWithRecencyPin(allVideos)
        applyBlockedCreatorFilter()
        swipeIndex = 0
        print("🔀 DISCOVERY: Reshuffled \(filteredVideos.count) videos (48hr pinned to front)")
    }

    /// Shuffle that keeps videos created in the last 48 hours at the front.
    /// Within each bucket (fresh / rest) the order is random.
    private func shuffleWithRecencyPin(_ input: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        var fresh = input.filter { $0.createdAt > cutoff }.shuffled()
        var rest  = input.filter { $0.createdAt <= cutoff }.shuffled()

        // Re-space collection cards evenly through the rest bucket
        let collectionCards = rest.filter { collectionCardMap[$0.id] != nil }
        rest = rest.filter { collectionCardMap[$0.id] == nil }
        let step = max(rest.count / max(collectionCards.count, 1), 5)
        for (i, card) in collectionCards.enumerated() {
            let at = min((i + 1) * step, rest.count)
            rest.insert(card, at: at)
        }

        print("📌 DISCOVERY: \(fresh.count) fresh (≤48hr) pinned, \(rest.count) shuffled behind")
        return fresh + rest
    }

    // MARK: - Debug / Admin

    /// Unblock a creator that was accidentally over-cooled.
    /// Clears memory preference — pass the Firestore creatorID.
    func clearBlockForCreator(_ creatorID: String) {
        DiscoveryEngagementTracker.shared.resetPreference(for: creatorID)
        applyBlockedCreatorFilter()
        print("🔓 DISCOVERY: Cleared block for creator \(creatorID.prefix(8))")
    }

    // MARK: - Foreground Refresh

    /// Call from .onChange(of: scenePhase) when app returns to foreground.
    /// Resets hasLoaded if data is stale so new videos posted while away appear.
    func handleForeground() {
        guard let last = lastLoadedAt else { return }
        if Date().timeIntervalSince(last) > staleDuration {
            hasLoaded = false
            allVideos = []
            videos = []
            filteredVideos = []
            collectionCardMap = [:]
            swipeIndex = 0
            print("🔄 DISCOVERY: Stale data (>30min) — will reload on next appear")
        }
    }

    // MARK: - Refresh (pull to refresh)

    func refreshContent() async {
        hasLoaded = false
        allVideos = []
        videos = []
        filteredVideos = []
        swipeIndex = 0
        await loadInitialContent()
    }

    // MARK: - Hashtags

    func loadTrendingHashtags() async {
        isLoadingHashtags = true
        await hashtagService.loadTrendingHashtags(limit: 10)
        trendingHashtags = hashtagService.trendingHashtags
        isLoadingHashtags = false
    }

    func selectHashtag(_ hashtag: TrendingHashtag) async {
        selectedHashtag = hashtag
        isLoading = true
        do {
            let result = try await hashtagService.getVideosForHashtag(hashtag.tag, limit: 40)
            hashtagVideos = result.videos
            filteredVideos = result.videos
        } catch {
            print("❌ DISCOVERY: Hashtag load failed: \(error)")
        }
        isLoading = false
    }

    func clearHashtagFilter() {
        selectedHashtag = nil
        hashtagVideos = []
        applyBlockedCreatorFilter()
    }

    // MARK: - Collections

    func loadCollections(for category: DiscoveryCategory) async {
        isLoadingCollections = true
        defer { isLoadingCollections = false }
        do {
            switch category {
            case .collections: discoveryCollections = try await collectionService.getDiscoveryCollections(limit: 30)
            case .podcasts:    discoveryCollections = try await discoveryService.getPodcastDiscovery(limit: 20)
            case .films:       discoveryCollections = try await discoveryService.getFilmsDiscovery(limit: 20)
            default: break
            }
        } catch { discoveryCollections = [] }
    }

    // MARK: - Category filter (non-All tabs use existing service)

    func filterBy(category: DiscoveryCategory) async {
        currentCategory = category
        guard category.isVideoCategory, category != .all else {
            applyBlockedCreatorFilter()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let threads: [ThreadData]
            switch category {
            case .trending:      threads = try await discoveryService.getTrendingDiscovery(limit: 40)
            case .recent:        threads = try await discoveryService.getRecentDiscovery(limit: 40)
            case .following:     threads = try await discoveryService.getFollowingFeed(limit: 40)
            case .hotHashtags:   threads = try await discoveryService.getHotHashtagDiscovery(limit: 40)
            case .heatCheck:     threads = try await discoveryService.getHeatCheckDiscovery(limit: 40)
            case .undiscovered:  threads = try await discoveryService.getUndiscoveredDiscovery(limit: 40)
            case .longestThreads:threads = try await discoveryService.getLongestThreadsDiscovery(limit: 40)
            case .spinOffs:      threads = try await discoveryService.getSpinOffDiscovery(limit: 40)
            case .rollTheDice:   reshuffleAndRestart(); return
            default: return
            }
            let valid = threads.map { $0.parentVideo }.filter { !$0.id.isEmpty }
            videos = valid
            filteredVideos = valid
            swipeIndex = 0
        } catch {
            print("❌ DISCOVERY: filterBy \(category) failed: \(error)")
        }
    }

    // MARK: - Collection Cards for Swipe Feed

    /// Fetches up to 6 featured collections and injects a representative video card
    /// into the swipe feed at evenly-spaced intervals. The card's videoID is mapped
    /// in collectionCardMap so onTap in DiscoveryView opens CollectionPlayerView.
    ///
    /// CACHING: Session-scoped. Called once per loadInitialContent. Zero extra reads on swipe.
    /// BATCHING: Single Firestore query for all featured collections.
    private func loadFeaturedCollectionsForSwipeFeed() async {
        do {
            let collections = try await collectionService.getDiscoveryCollections(limit: 6)
            guard !collections.isEmpty else { return }

            var injected: [CoreVideoMetadata] = []

            for collection in collections {
                // Use the collection's coverVideo as the card's video data.
                // If no coverVideo exists, synthesize a placeholder CoreVideoMetadata
                // using the collection's metadata — no extra reads needed.
                // Build a placeholder CoreVideoMetadata for the collection card.
                // videoURL intentionally empty — collectionCardContent renders cover image, not a player.
                // isPromoted: true is the isCollectionCard signal read by DiscoveryCard.
                let card = CoreVideoMetadata(
                    id: collection.id,
                    title: collection.title,
                    description: "",
                    videoURL: "",
                    thumbnailURL: collection.coverImageURL ?? "",
                    creatorID: collection.creatorID,
                    creatorName: collection.creatorName,
                    createdAt: Date(),
                    threadID: collection.id,
                    replyToVideoID: nil,
                    conversationDepth: 0,
                    viewCount: 0,
                    hypeCount: 0,
                    coolCount: 0,
                    replyCount: 0,
                    shareCount: 0,
                    temperature: "neutral",
                    qualityScore: 75,
                    engagementRatio: 0.5,
                    velocityScore: 0,
                    trendingScore: 0,
                    duration: 0,
                    aspectRatio: 9.0/16.0,
                    fileSize: 0,
                    discoverabilityScore: 0.8,
                    isPromoted: true,
                    lastEngagementAt: nil,
                    collectionID: collection.id,
                    segmentNumber: nil,
                    segmentTitle: nil,
                    isCollectionSegment: false
                )
                collectionCardMap[collection.id] = collection
                injected.append(card)
            }

            // Inject at fixed positions — first card within 10 swipes, then every 15
            // Cap prevents cards from being buried hundreds of swipes deep in large catalogs
            guard !allVideos.isEmpty else { return }
            let firstPosition = min(10, allVideos.count)
            let spacing = 15
            for (i, card) in injected.enumerated() {
                let insertAt = min(firstPosition + (i * spacing), allVideos.count)
                allVideos.insert(card, at: insertAt)
            }

            print("🎬 DISCOVERY: Injected \(injected.count) collection cards into swipe feed")
        } catch {
            print("⚠️ DISCOVERY: Collection card load failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func applyBlockedCreatorFilter() {
        let blocked = Set(DiscoveryEngagementTracker.shared.blockedCreatorIDs())
        let base = allVideos.isEmpty ? videos : allVideos
        filteredVideos = blocked.isEmpty ? base : base.filter { !blocked.contains($0.creatorID) }
        videos = filteredVideos
    }
}
