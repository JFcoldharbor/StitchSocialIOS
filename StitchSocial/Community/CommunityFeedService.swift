//
//  CommunityFeedService.swift
//  StitchSocial
//
//  Layer 5: Services - Community Feed, Posts, Replies, Pagination
//  Dependencies: CommunityTypes (Layer 1), CommunityService (Layer 5), CommunityXPService (Layer 5)
//  Features: Create/fetch posts, replies, hype posts, auto video announcements, cursor pagination
//
//  CACHING STRATEGY:
//  - feedCache: First 20 posts per community, 2-min TTL, invalidate on new post
//  - postDetailCache: Individual post objects, 2-min TTL, for detail view
//  - replyCache: First 20 replies per post, 2-min TTL
//  - hypeStateCache: Bool per userID+postID, 5-min TTL — prevents re-reading hype status
//  Add to CachingOptimization.swift under "Community Feed Cache" section
//
//  BATCHING NOTES:
//  - New post: batched write (post doc + community totalPosts increment + membership totalPosts increment)
//  - Hype post: batched write (hype doc + post hypeCount increment) — NO read-then-write
//  - Replies: batched write (reply doc + post replyCount increment)
//  - Feed pagination: cursor-based, one query per page, no offset scanning
//

import Foundation
import FirebaseFirestore

class CommunityFeedService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CommunityFeedService()
    
    // MARK: - Properties
    
    private let db = FirebaseConfig.firestore
    private let communityService = CommunityService.shared
    private let xpService = CommunityXPService.shared
    
    @Published var currentFeed: [CommunityPost] = []
    @Published var currentReplies: [CommunityReply] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Cache
    
    private var feedCache: [String: CachedFeed] = [:]
    private var postDetailCache: [String: CachedItem<CommunityPost>] = [:]
    private var replyCache: [String: CachedItem<[CommunityReply]>] = [:]
    private var hypeStateCache: [String: CachedItem<Bool>] = [:]
    
    private struct CachedFeed {
        let posts: [CommunityPost]
        let lastDocument: DocumentSnapshot?
        let cachedAt: Date
        let ttl: TimeInterval = 120 // 2 min
        
        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }
    
    private struct CachedItem<T> {
        let value: T
        let cachedAt: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }
    
    private let feedTTL: TimeInterval = 120     // 2 min
    private let detailTTL: TimeInterval = 120   // 2 min
    private let hypeTTL: TimeInterval = 300     // 5 min
    
    // MARK: - Pagination State
    
    private var lastDocuments: [String: DocumentSnapshot] = [:]     // Per community
    private var replyLastDocs: [String: DocumentSnapshot] = [:]     // Per post
    private var hasMorePosts: [String: Bool] = [:]
    private var hasMoreReplies: [String: Bool] = [:]
    
    // MARK: - Collections
    
    private enum Collections {
        static let communities = "communities"
        static let posts = "posts"
        static let replies = "replies"
        static let hypes = "hypes"
        static let members = "members"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Feed (Cursor Paginated)
    
    /// Fetches community posts with cursor-based pagination
    /// First call returns cached if fresh, subsequent calls paginate forward
    @MainActor
    func fetchFeed(
        communityID: String,
        limit: Int = 20,
        refresh: Bool = false
    ) async throws -> [CommunityPost] {
        
        // Check cache on first load (not refresh or pagination)
        if !refresh, let cached = feedCache[communityID], !cached.isExpired {
            self.currentFeed = cached.posts
            return cached.posts
        }
        
        if refresh {
            lastDocuments.removeValue(forKey: communityID)
            feedCache.removeValue(forKey: communityID)
            hasMorePosts[communityID] = true
        }
        
        isLoading = true
        defer { isLoading = false }
        
        var query = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .order(by: "isPinned", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocuments[communityID] {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> CommunityPost? in
            try? doc.data(as: CommunityPost.self)
        }
        
        // Update pagination state
        lastDocuments[communityID] = snapshot.documents.last
        hasMorePosts[communityID] = posts.count == limit
        
        if lastDocuments[communityID] == nil || refresh {
            // First page or refresh — replace feed
            self.currentFeed = posts
            feedCache[communityID] = CachedFeed(
                posts: posts,
                lastDocument: snapshot.documents.last,
                cachedAt: Date()
            )
        } else {
            // Pagination — append
            self.currentFeed.append(contentsOf: posts)
        }
        
        print("✅ FEED: Loaded \(posts.count) posts for \(communityID), total: \(currentFeed.count)")
        return posts
    }
    
    /// Check if more posts are available
    func canLoadMore(communityID: String) -> Bool {
        return hasMorePosts[communityID] ?? true
    }
    
    // MARK: - Create Post (Batched Write)
    
    /// Creates a new community post — batched: post doc + community count + member count
    @MainActor
    func createPost(
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        authorBadgeIDs: [String],
        isCreatorPost: Bool,
        postType: CommunityPostType,
        body: String,
        videoLinkID: String? = nil,
        videoThumbnailURL: String? = nil
    ) async throws -> CommunityPost {
        
        isLoading = true
        defer { isLoading = false }
        
        // Level gate for video clips
        if postType == .videoClip && authorLevel < CommunityFeatureGate.videoClips.requiredLevel {
            throw CommunityFeedError.levelTooLow(required: CommunityFeatureGate.videoClips.requiredLevel)
        }
        
        let post = CommunityPost(
            communityID: communityID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorLevel: authorLevel,
            authorBadgeIDs: authorBadgeIDs,
            isCreatorPost: isCreatorPost,
            postType: postType,
            body: body,
            videoLinkID: videoLinkID,
            videoThumbnailURL: videoThumbnailURL
        )
        
        // BATCHED WRITE: post + community totalPosts + member totalPosts
        let batch = db.batch()
        
        let postRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(post.id)
        try batch.setData(from: post, forDocument: postRef)
        
        let communityRef = db.collection(Collections.communities).document(communityID)
        batch.updateData([
            "totalPosts": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: communityRef)
        
        let memberRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.members)
            .document(authorID)
        batch.updateData([
            "totalPosts": FieldValue.increment(Int64(1)),
            "lastActiveAt": Timestamp(date: Date())
        ], forDocument: memberRef)
        
        try await batch.commit()
        
        // Award XP (buffered, not immediate)
        let source: CommunityXPSource = postType == .videoClip ? .videoPost : .textPost
        xpService.awardXP(userID: authorID, communityID: communityID, source: source)
        
        // Invalidate feed cache — new post needs to show
        feedCache.removeValue(forKey: communityID)
        communityService.invalidateListCache()
        communityService.invalidateMembershipCache(userID: authorID, creatorID: communityID)
        
        // Prepend to current feed for instant UI update
        self.currentFeed.insert(post, at: 0)
        
        print("✅ FEED: Post created by \(authorUsername) in \(communityID)")
        return post
    }
    
    // MARK: - Create Auto Video Announcement (Cloud Function Helper)
    
    /// Creates an auto-generated discussion post when creator publishes a video
    /// In production this should be a Cloud Function trigger on video creation
    /// This method exists for client-side fallback or testing
    @MainActor
    func createVideoAnnouncement(payload: VideoAnnouncementPayload) async throws -> CommunityPost {
        
        // Fetch creator info from community
        guard let community = try await communityService.fetchCommunity(creatorID: payload.creatorID) else {
            throw CommunityFeedError.communityNotFound
        }
        
        let post = CommunityPost(
            communityID: payload.communityID,
            authorID: payload.creatorID,
            authorUsername: community.creatorUsername,
            authorDisplayName: community.creatorDisplayName,
            authorLevel: 0, // Creator doesn't have a level in their own community
            isCreatorPost: true,
            postType: .autoVideoAnnouncement,
            body: payload.postBody,
            videoLinkID: payload.videoID,
            videoThumbnailURL: payload.thumbnailURL,
            isAutoGenerated: true
        )
        
        let postRef = db.collection(Collections.communities)
            .document(payload.communityID)
            .collection(Collections.posts)
            .document(post.id)
        
        try postRef.setData(from: post)
        
        // Invalidate feed cache
        feedCache.removeValue(forKey: payload.communityID)
        
        print("✅ FEED: Auto video announcement for \(payload.videoTitle) in \(payload.communityID)")
        return post
    }
    
    // MARK: - Pin/Unpin Post (Creator Only)
    
    @MainActor
    func pinPost(postID: String, communityID: String, creatorID: String, pin: Bool) async throws {
        
        // If pinning, unpin existing pinned post first
        if pin {
            let community = try await communityService.fetchCommunity(creatorID: creatorID)
            if let existingPinID = community?.pinnedPostID {
                try await db.collection(Collections.communities)
                    .document(communityID)
                    .collection(Collections.posts)
                    .document(existingPinID)
                    .updateData(["isPinned": false])
            }
        }
        
        // BATCHED: update post + community pinnedPostID
        let batch = db.batch()
        
        let postRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
        batch.updateData(["isPinned": pin], forDocument: postRef)
        
        let communityRef = db.collection(Collections.communities).document(communityID)
        batch.updateData([
            "pinnedPostID": pin ? postID : FieldValue.delete()
        ], forDocument: communityRef)
        
        try await batch.commit()
        
        // Invalidate caches
        feedCache.removeValue(forKey: communityID)
        communityService.invalidateMembershipCache(userID: creatorID, creatorID: communityID)
        postDetailCache.removeValue(forKey: postID)
        
        print("✅ FEED: Post \(postID) \(pin ? "pinned" : "unpinned") in \(communityID)")
    }
    
    // MARK: - Delete Post
    
    @MainActor
    func deletePost(postID: String, communityID: String, authorID: String) async throws {
        
        // BATCHED: delete post + decrement community count + member count
        let batch = db.batch()
        
        let postRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
        batch.deleteDocument(postRef)
        
        let communityRef = db.collection(Collections.communities).document(communityID)
        batch.updateData([
            "totalPosts": FieldValue.increment(Int64(-1))
        ], forDocument: communityRef)
        
        let memberRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.members)
            .document(authorID)
        batch.updateData([
            "totalPosts": FieldValue.increment(Int64(-1))
        ], forDocument: memberRef)
        
        try await batch.commit()
        
        // Clean up caches
        feedCache.removeValue(forKey: communityID)
        postDetailCache.removeValue(forKey: postID)
        replyCache.removeValue(forKey: postID)
        self.currentFeed.removeAll { $0.id == postID }
        
        print("🗑️ FEED: Deleted post \(postID) from \(communityID)")
    }
    
    // MARK: - Fetch Replies (Cursor Paginated)
    
    @MainActor
    func fetchReplies(
        postID: String,
        communityID: String,
        limit: Int = 20,
        refresh: Bool = false
    ) async throws -> [CommunityReply] {
        
        // Check cache
        if !refresh, let cached = replyCache[postID], !cached.isExpired {
            self.currentReplies = cached.value
            return cached.value
        }
        
        if refresh {
            replyLastDocs.removeValue(forKey: postID)
            replyCache.removeValue(forKey: postID)
            hasMoreReplies[postID] = true
        }
        
        var query = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
            .collection(Collections.replies)
            .order(by: "createdAt", descending: false)
            .limit(to: limit)
        
        if let lastDoc = replyLastDocs[postID] {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let replies = snapshot.documents.compactMap { doc -> CommunityReply? in
            try? doc.data(as: CommunityReply.self)
        }
        
        replyLastDocs[postID] = snapshot.documents.last
        hasMoreReplies[postID] = replies.count == limit
        
        if replyLastDocs[postID] == nil || refresh {
            self.currentReplies = replies
            replyCache[postID] = CachedItem(value: replies, cachedAt: Date(), ttl: feedTTL)
        } else {
            self.currentReplies.append(contentsOf: replies)
        }
        
        return replies
    }
    
    // MARK: - Create Reply (Batched Write)
    
    @MainActor
    func createReply(
        postID: String,
        communityID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        isCreatorReply: Bool,
        body: String
    ) async throws -> CommunityReply {
        
        let reply = CommunityReply(
            postID: postID,
            communityID: communityID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorLevel: authorLevel,
            isCreatorReply: isCreatorReply,
            body: body
        )
        
        // BATCHED: reply doc + post replyCount + member totalReplies
        let batch = db.batch()
        
        let replyRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
            .collection(Collections.replies)
            .document(reply.id)
        try batch.setData(from: reply, forDocument: replyRef)
        
        let postRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
        batch.updateData([
            "replyCount": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: postRef)
        
        let memberRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.members)
            .document(authorID)
        batch.updateData([
            "totalReplies": FieldValue.increment(Int64(1)),
            "lastActiveAt": Timestamp(date: Date())
        ], forDocument: memberRef)
        
        try await batch.commit()
        
        // Award XP (buffered)
        xpService.awardXP(userID: authorID, communityID: communityID, source: .reply)
        
        // Invalidate caches
        replyCache.removeValue(forKey: postID)
        postDetailCache.removeValue(forKey: postID)
        communityService.invalidateMembershipCache(userID: authorID, creatorID: communityID)
        
        // Append for instant UI
        self.currentReplies.append(reply)
        
        print("✅ FEED: Reply by \(authorUsername) on \(postID)")
        return reply
    }
    
    // MARK: - Hype Post (Batched, Cached)
    
    /// Hype a community post — batched write, cached state
    /// NO read-then-write: uses FieldValue.increment + hype subdocument
    @MainActor
    func hypePost(
        postID: String,
        communityID: String,
        userID: String
    ) async throws -> Bool {
        
        let cacheKey = "\(userID)_\(postID)"
        
        // Check cache — avoid duplicate hype reads
        if let cached = hypeStateCache[cacheKey], !cached.isExpired, cached.value {
            throw CommunityFeedError.alreadyHyped
        }
        
        let hypeRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
            .collection(Collections.hypes)
            .document(userID)
        
        // Check if already hyped (only if not cached)
        let existingDoc = try await hypeRef.getDocument()
        if existingDoc.exists {
            hypeStateCache[cacheKey] = CachedItem(value: true, cachedAt: Date(), ttl: hypeTTL)
            throw CommunityFeedError.alreadyHyped
        }
        
        let hype = CommunityPostHype(postID: postID, userID: userID, communityID: communityID)
        
        // BATCHED: hype doc + post hypeCount increment
        let batch = db.batch()
        
        try batch.setData(from: hype, forDocument: hypeRef)
        
        let postRef = db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
        batch.updateData(["hypeCount": FieldValue.increment(Int64(1))], forDocument: postRef)
        
        try await batch.commit()
        
        // Cache hype state
        hypeStateCache[cacheKey] = CachedItem(value: true, cachedAt: Date(), ttl: hypeTTL)
        
        // Award XP to both giver and receiver (buffered)
        xpService.awardXP(userID: userID, communityID: communityID, source: .gaveHype)
        
        // Find post author for received hype XP
        if let post = currentFeed.first(where: { $0.id == postID }) {
            xpService.awardXP(userID: post.authorID, communityID: communityID, source: .receivedHype)
        }
        
        // Update local feed for instant UI
        if let index = currentFeed.firstIndex(where: { $0.id == postID }) {
            currentFeed[index].hypeCount += 1
        }
        
        // Invalidate post detail cache
        postDetailCache.removeValue(forKey: postID)
        
        print("🔥 FEED: \(userID) hyped post \(postID)")
        return true
    }
    
    // MARK: - Check Hype State (Cached)
    
    func hasHyped(userID: String, postID: String, communityID: String) async throws -> Bool {
        let cacheKey = "\(userID)_\(postID)"
        
        if let cached = hypeStateCache[cacheKey], !cached.isExpired {
            return cached.value
        }
        
        let doc = try await db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
            .collection(Collections.hypes)
            .document(userID)
            .getDocument()
        
        let result = doc.exists
        hypeStateCache[cacheKey] = CachedItem(value: result, cachedAt: Date(), ttl: hypeTTL)
        return result
    }
    
    // MARK: - Batch Check Hype States (For Feed Rendering)
    
    /// Check hype states for multiple posts at once — reduces N reads to N
    /// Call this when loading a feed page to pre-warm hype cache
    func preloadHypeStates(
        postIDs: [String],
        communityID: String,
        userID: String
    ) async {
        for postID in postIDs {
            let cacheKey = "\(userID)_\(postID)"
            guard hypeStateCache[cacheKey] == nil || hypeStateCache[cacheKey]!.isExpired else {
                continue // Already cached and fresh
            }
            
            do {
                _ = try await hasHyped(userID: userID, postID: postID, communityID: communityID)
            } catch {
                // Silently fail — UI will show unhyped state by default
            }
        }
    }
    
    // MARK: - Fetch Single Post
    
    func fetchPost(postID: String, communityID: String) async throws -> CommunityPost? {
        if let cached = postDetailCache[postID], !cached.isExpired {
            return cached.value
        }
        
        let doc = try await db.collection(Collections.communities)
            .document(communityID)
            .collection(Collections.posts)
            .document(postID)
            .getDocument()
        
        guard let post = try? doc.data(as: CommunityPost.self) else { return nil }
        
        postDetailCache[postID] = CachedItem(value: post, cachedAt: Date(), ttl: detailTTL)
        return post
    }
    
    // MARK: - Cache Management
    
    func clearAllCaches() {
        feedCache.removeAll()
        postDetailCache.removeAll()
        replyCache.removeAll()
        hypeStateCache.removeAll()
        lastDocuments.removeAll()
        replyLastDocs.removeAll()
        hasMorePosts.removeAll()
        hasMoreReplies.removeAll()
        currentFeed = []
        currentReplies = []
    }
    
    func invalidateFeedCache(communityID: String) {
        feedCache.removeValue(forKey: communityID)
    }
    
    /// Prune expired entries to prevent memory bloat
    func pruneExpiredCaches() {
        feedCache = feedCache.filter { !$0.value.isExpired }
        postDetailCache = postDetailCache.filter { !$0.value.isExpired }
        replyCache = replyCache.filter { !$0.value.isExpired }
        hypeStateCache = hypeStateCache.filter { !$0.value.isExpired }
    }
}

// MARK: - Errors

enum CommunityFeedError: LocalizedError {
    case communityNotFound
    case levelTooLow(required: Int)
    case alreadyHyped
    case postNotFound
    case replyNotFound
    
    var errorDescription: String? {
        switch self {
        case .communityNotFound:
            return "Community not found"
        case .levelTooLow(let required):
            return "You need level \(required) to do this"
        case .alreadyHyped:
            return "You already hyped this post"
        case .postNotFound:
            return "Post not found"
        case .replyNotFound:
            return "Reply not found"
        }
    }
}
