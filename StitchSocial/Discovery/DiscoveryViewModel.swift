//
//  DiscoveryViewModel.swift
//  StitchSocial
//
//  Layer 5: ViewModels - Discovery feed state, filtering, shuffling, seed injection
//  Extracted from DiscoveryView.swift
//  Dependencies: DiscoveryService, HashtagService, DiscoveryEngagementTracker,
//                OnboardingSeedService, VideoService
//
//  CACHING:
//  - filteredVideos: in-memory, rebuilt on category switch
//  - TTL cache lives in DiscoveryService — tab switches cost 0 reads within 5 min
//  - Seed video: fetched once by OnboardingSeedService, cached in UserDefaults
//    injected at index 2 on first load only — never re-injected
//  - collectionCardMap: in-memory session cache, cleared on refresh
//
//  BATCHING:
//  - loadInitialContent fires two parallel async tasks (threads + collections)
//  - No per-video reads — threads arrive as bulk query from DiscoveryService
//
//  ADD TO CachingOptimization.swift:
//  "DiscoveryViewModel.injectSeedVideo — seed inserted once at index 2 after
//   initial load. Guarded by seedInjected flag — never runs twice per session.
//   Seed data sourced from OnboardingSeedService (UserDefaults-cached)."
//

import Foundation
import SwiftUI

// MARK: - Discovery ViewModel

@MainActor
class DiscoveryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var videos: [CoreVideoMetadata] = []
    @Published var filteredVideos: [CoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var currentCategory: DiscoveryCategory = .all
    @Published var errorMessage: String?

    // Collection state for podcast/film lanes
    @Published var discoveryCollections: [VideoCollection] = []
    @Published var isLoadingCollections = false

    /// Collections interleaved into the swipe feed — maps video.id to VideoCollection
    var collectionCardMap: [String: VideoCollection] = [:]

    // MARK: - Hashtag State

    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var isLoadingHashtags = false
    @Published var selectedHashtag: TrendingHashtag?
    @Published var hashtagVideos: [CoreVideoMetadata] = []

    // MARK: - Seed Injection Guard
    // Ensures seed video is only injected once per session, even if
    // loadInitialContent is called multiple times (refresh, category switch)
    private var seedInjected = false

    // MARK: - Services

    private let discoveryService = DiscoveryService()
    private let hashtagService = HashtagService()

    // MARK: - Load Initial Content (TTL-aware)

    func loadInitialContent() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            print("🎲 DISCOVERY: Loading weighted content")

            // Load videos and collections in parallel
            // Service-level TTL cache means these may be instant (0 reads)
            async let threadsTask = discoveryService.getDeepRandomizedDiscovery(limit: 40)
            async let collectionsTask = discoveryService.getAllCollectionsDiscovery(limit: 6)

            let threads = try await threadsTask
            let swipeCollections = (try? await collectionsTask) ?? []
            let loadedVideos = threads.map { $0.parentVideo }

            await MainActor.run {
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }

                if validVideos.count < loadedVideos.count {
                    print("⚠️ DISCOVERY: Filtered out \(loadedVideos.count - validVideos.count) videos with empty IDs")
                }

                videos = validVideos
                applyFilterAndShuffle()
                interleaveCollections(swipeCollections)
                errorMessage = nil

                print("✅ DISCOVERY: Loaded \(filteredVideos.count) weighted videos")
            }

            // Inject onboarding seed at index 2 after content is ready
            // Read OnboardingState here at the call site — ViewModel stays decoupled
            let onboardingActive = UserDefaults.standard.bool(forKey: "stitch_onboarding_complete") == false
            await injectSeedIfNeeded(onboardingActive: onboardingActive)

        } catch {
            await MainActor.run {
                errorMessage = "Failed to load discovery content"
                print("❌ DISCOVERY: Load failed: \(error)")
            }
        }
    }

    // MARK: - Seed Injection

    /// Inserts the onboarding seed video at index 2 — only once per session.
    /// Called from DiscoveryView after loadInitialContent succeeds.
    /// onboardingActive passed in from OnboardingState.shared.shouldShow —
    /// keeps this ViewModel independent of the onboarding layer entirely.
    func injectSeedIfNeeded(onboardingActive: Bool) async {
        guard !seedInjected else { return }
        guard onboardingActive else { return }

        guard let seedVideo = await OnboardingSeedService.shared.fetchSeedVideo() else {
            print("⚠️ DISCOVERY SEED: No seed video available — skipping injection")
            return
        }

        // Avoid duplicate if seed already in feed (e.g. organic discovery)
        guard !filteredVideos.contains(where: { $0.id == seedVideo.id }) else {
            seedInjected = true
            print("✅ DISCOVERY SEED: Seed video already in feed naturally at position \(filteredVideos.firstIndex(where: { $0.id == seedVideo.id }) ?? -1)")
            return
        }

        let insertIndex = min(2, filteredVideos.count)
        filteredVideos.insert(seedVideo, at: insertIndex)
        seedInjected = true

        // Tell OnboardingState which index to wait for
        OnboardingState.shared.seedIndex = insertIndex
        print("✅ DISCOVERY SEED: Injected '\(seedVideo.title)' at index \(insertIndex)")
    }

    // MARK: - Load Trending Hashtags

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
            print("❌ DISCOVERY: Failed to load hashtag videos: \(error)")
        }

        isLoading = false
    }

    func clearHashtagFilter() {
        selectedHashtag = nil
        hashtagVideos = []
        applyFilterAndShuffle()
    }

    // MARK: - Load More (APPEND to end, NO reshuffle)

    func loadMoreContent() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            print("📥 DISCOVERY: Loading more content (appending to end)")

            let threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 30)
            let newVideos = threads.map { $0.parentVideo }

            await MainActor.run {
                let validVideos = newVideos.filter { !$0.id.isEmpty }

                // Append to END — don't reshuffle seen content
                videos.append(contentsOf: validVideos)
                filteredVideos.append(contentsOf: validVideos)

                print("✅ DISCOVERY: Appended \(validVideos.count) videos, total: \(filteredVideos.count)")
            }
        } catch {
            print("❌ DISCOVERY: Failed to load more: \(error)")
        }
    }

    // MARK: - Refresh Content

    func refreshContent() async {
        // Invalidate service-level caches so we get fresh Firestore data
        discoveryService.invalidateVideoCaches()

        videos = []
        filteredVideos = []
        // Reset seed guard so it re-injects on fresh load
        seedInjected = false
        await loadInitialContent()
    }

    // MARK: - Randomize (0 reads)

    func randomizeContent() {
        videos = videos.shuffled()
        applyFilterAndShuffle()
        print("🎲 DISCOVERY: Content randomized — \(filteredVideos.count) videos reshuffled")
    }

    // MARK: - Category Filtering (TTL cached)

    func filterBy(category: DiscoveryCategory) async {
        currentCategory = category

        guard category.isVideoCategory else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let threads: [ThreadData]

            switch category {
            case .all:
                threads = try await discoveryService.getDeepRandomizedDiscovery(limit: 40)
            case .trending:
                threads = try await discoveryService.getTrendingDiscovery(limit: 40)
            case .recent:
                threads = try await discoveryService.getRecentDiscovery(limit: 40)
            case .following:
                threads = try await discoveryService.getFollowingFeed(limit: 40)
            case .hotHashtags:
                threads = try await discoveryService.getHotHashtagDiscovery(limit: 40)
            case .heatCheck:
                threads = try await discoveryService.getHeatCheckDiscovery(limit: 40)
            case .undiscovered:
                threads = try await discoveryService.getUndiscoveredDiscovery(limit: 40)
            case .longestThreads:
                threads = try await discoveryService.getLongestThreadsDiscovery(limit: 40)
            case .spinOffs:
                threads = try await discoveryService.getSpinOffDiscovery(limit: 40)
            case .rollTheDice:
                discoveryService.invalidateVideoCaches()
                let allThreads = try await discoveryService.getDeepRandomizedDiscovery(limit: 60)
                threads = allThreads.shuffled()
            case .communities, .collections, .pymk, .podcasts, .films:
                return
            }

            let loadedVideos = threads.map { $0.parentVideo }

            await MainActor.run {
                let validVideos = loadedVideos.filter { !$0.id.isEmpty }
                videos = validVideos
                applyFilterAndShuffle()
                print("📊 DISCOVERY: Applied \(category.displayName) filter — \(filteredVideos.count) videos")
            }

        } catch {
            await MainActor.run {
                errorMessage = "Failed to load \(category.displayName) content"
                print("❌ DISCOVERY: Category load failed: \(error)")
            }
        }
    }

    // MARK: - Collection Loading

    func loadCollections(for category: DiscoveryCategory) async {
        isLoadingCollections = true
        defer { isLoadingCollections = false }

        do {
            switch category {
            case .collections:
                discoveryCollections = try await discoveryService.getAllCollectionsDiscovery(limit: 30)
            case .podcasts:
                discoveryCollections = try await discoveryService.getPodcastDiscovery(limit: 20)
            case .films:
                discoveryCollections = try await discoveryService.getFilmsDiscovery(limit: 20)
            default:
                break
            }
        } catch {
            discoveryCollections = []
        }
    }

    // MARK: - Private: Filter + Shuffle

    private func applyFilterAndShuffle() {
        let blockedIDs = DiscoveryEngagementTracker.shared.blockedCreatorIDs()
        let allowedVideos = blockedIDs.isEmpty
            ? videos
            : videos.filter { !blockedIDs.contains($0.creatorID) }
        filteredVideos = diversifyShuffle(videos: allowedVideos)
    }

    /// Insert collection placeholder cards every ~7 items
    func interleaveCollections(_ collections: [VideoCollection]) {
        guard !collections.isEmpty else { return }
        collectionCardMap.removeAll()

        var insertOffset = 0
        for (i, collection) in collections.enumerated() {
            let placeholderID = "collection_card_\(collection.id)"

            let placeholder = CoreVideoMetadata(
                id: placeholderID,
                title: collection.title,
                description: "\(collection.segmentCount) parts",
                videoURL: "",
                thumbnailURL: collection.coverImageURL ?? "",
                creatorID: collection.creatorID,
                creatorName: collection.creatorName,
                createdAt: collection.publishedAt ?? collection.createdAt,
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: collection.totalViews,
                hypeCount: collection.totalHypes,
                coolCount: collection.totalCools,
                replyCount: collection.totalReplies,
                shareCount: collection.totalShares,
                temperature: "neutral",
                qualityScore: 50,
                engagementRatio: 0,
                velocityScore: 0,
                trendingScore: 0,
                duration: collection.totalDuration,
                aspectRatio: 9.0/16.0,
                fileSize: 0,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil,
                collectionID: collection.id,
                isCollectionSegment: true
            )

            collectionCardMap[placeholderID] = collection

            let insertIndex = min((i + 1) * 7 + insertOffset, filteredVideos.count)
            filteredVideos.insert(placeholder, at: insertIndex)
            insertOffset += 1
        }

        print("📚 DISCOVERY: Interleaved \(collections.count) collection cards")
    }

    /// Shuffle with maximum creator variety
    private func diversifyShuffle(videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        guard videos.count > 1 else { return videos }

        var creatorBuckets: [String: [CoreVideoMetadata]] = [:]
        for video in videos {
            creatorBuckets[video.creatorID, default: []].append(video)
        }

        var shuffledBuckets = creatorBuckets.mapValues { $0.shuffled() }
        var result: [CoreVideoMetadata] = []
        var recentCreators: [String] = []
        let maxRecentTracking = 5

        while !shuffledBuckets.isEmpty {
            let availableCreators = shuffledBuckets.keys.filter { !recentCreators.contains($0) }

            let chosenCreatorID: String
            if !availableCreators.isEmpty {
                chosenCreatorID = availableCreators.randomElement()!
            } else {
                chosenCreatorID = shuffledBuckets.keys.randomElement()!
                recentCreators.removeAll()
            }

            if var creatorVideos = shuffledBuckets[chosenCreatorID], !creatorVideos.isEmpty {
                let video = creatorVideos.removeFirst()
                result.append(video)

                recentCreators.append(chosenCreatorID)
                if recentCreators.count > maxRecentTracking {
                    recentCreators.removeFirst()
                }

                if creatorVideos.isEmpty {
                    shuffledBuckets.removeValue(forKey: chosenCreatorID)
                } else {
                    shuffledBuckets[chosenCreatorID] = creatorVideos
                }
            }
        }

        return result
    }
}

// MARK: - Discovery Mode

enum DiscoveryMode: String, CaseIterable {
    case swipe = "swipe"
    case grid  = "grid"

    var displayName: String {
        switch self {
        case .swipe: return "Swipe"
        case .grid:  return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .swipe: return "square.stack"
        case .grid:  return "rectangle.grid.2x2"
        }
    }
}

// MARK: - Discovery Category

enum DiscoveryCategory: String, CaseIterable {
    case communities   = "communities"
    case collections   = "collections"
    case all           = "all"
    case trending      = "trending"
    case pymk          = "pymk"
    case hotHashtags   = "hotHashtags"
    case recent        = "recent"
    case heatCheck     = "heatCheck"
    case following     = "following"
    case undiscovered  = "undiscovered"
    case longestThreads = "longestThreads"
    case spinOffs      = "spinOffs"
    case podcasts      = "podcasts"
    case films         = "films"
    case rollTheDice   = "rollTheDice"

    var displayName: String {
        switch self {
        case .communities:    return "Communities"
        case .collections:    return "Collections"
        case .following:      return "Following"
        case .trending:       return "Trending"
        case .pymk:           return "PYMK"
        case .hotHashtags:    return "Hot Hashtags"
        case .all:            return "All"
        case .recent:         return "New"
        case .heatCheck:      return "Heat Check"
        case .undiscovered:   return "Undiscovered"
        case .longestThreads: return "Threads"
        case .spinOffs:       return "Spin-Offs"
        case .podcasts:       return "Podcasts"
        case .films:          return "Films"
        case .rollTheDice:    return "Roll the Dice"
        }
    }

    var icon: String {
        switch self {
        case .communities:    return "person.3.fill"
        case .collections:    return "rectangle.stack.fill"
        case .following:      return "heart.fill"
        case .trending:       return "flame.fill"
        case .pymk:           return "person.badge.plus"
        case .hotHashtags:    return "number"
        case .all:            return "square.grid.2x2"
        case .recent:         return "sparkles"
        case .heatCheck:      return "thermometer.high"
        case .undiscovered:   return "binoculars.fill"
        case .longestThreads: return "bubble.left.and.bubble.right.fill"
        case .spinOffs:       return "arrow.triangle.branch"
        case .podcasts:       return "mic.fill"
        case .films:          return "film"
        case .rollTheDice:    return "dice.fill"
        }
    }

    var isVideoCategory: Bool {
        switch self {
        case .communities, .collections, .pymk, .podcasts, .films: return false
        default: return true
        }
    }

    var isCollectionCategory: Bool {
        return self == .podcasts || self == .films || self == .collections
    }
}

// MARK: - Presentation Wrappers

struct DiscoveryVideoPresentation: Identifiable, Equatable {
    let id: String
    let video: CoreVideoMetadata

    static func == (lhs: DiscoveryVideoPresentation, rhs: DiscoveryVideoPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

struct DiscoveryHashtagPresentation: Identifiable {
    let id: String
    let hashtag: TrendingHashtag
}
