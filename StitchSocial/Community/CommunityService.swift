//
//  CommunityService.swift
//  StitchSocial
//
//  Layer 5: Services - Community CRUD, Membership, Tier Gating
//  Dependencies: CommunityTypes (Layer 1), UserTier (Layer 1), SubscriptionTier (Layer 1)
//  Features: Create/fetch communities, join/leave, membership checks, community list
//
//  CACHING STRATEGY:
//  - communityCache: Full Community objects, 10-min TTL, keyed by creatorID
//  - membershipCache: CommunityMembership per user+community, 5-min TTL
//  - communityListCache: CommunityListItem array, 5-min TTL, invalidate on join/leave
//  - isMemberCache: Bool lookups, 5-min TTL — avoids repeated Firestore reads on navigation
//  All caches clear on logout. Add to CachingOptimization.swift.
//
//  BATCHING NOTES:
//  - fetchMyCommunities uses a single query with subscriberID filter, not N reads
//  - Community member count uses FieldValue.increment, not read-then-write
//  - Membership creation batches community doc update + member doc write in one batch
//

import Foundation
import FirebaseFirestore

class CommunityService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CommunityService()
    
    // MARK: - Properties
    
    private let db = FirebaseConfig.firestore
    private let subscriptionService = SubscriptionService.shared
    
    @Published var myCommunities: [CommunityListItem] = []
    @Published var currentCommunity: Community?
    @Published var currentMembership: CommunityMembership?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Cache (reduces Firestore reads significantly)
    
    private var communityCache: [String: CachedItem<Community>] = [:]
    private var membershipCache: [String: CachedItem<CommunityMembership>] = [:]
    var communityListCache: CachedItem<[CommunityListItem]>?
    private var isMemberCache: [String: CachedItem<Bool>] = [:]
    
    struct CachedItem<T> {
        let value: T
        let cachedAt: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }
    
    private let communityTTL: TimeInterval = 600    // 10 min
    private let membershipTTL: TimeInterval = 300   // 5 min
    private let listTTL: TimeInterval = 300         // 5 min
    
    // MARK: - Collections
    
    private enum Collections {
        static let communities = "communities"
        static let members = "members"
        static let subscriptions = "subscriptions"
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Stitch Social Official Community
    
    /// The official Stitch Social community — all users auto-join on login
    static let officialCommunityID = "L9cfRdqpDMWA9tq12YBh3IkhnGh1"
    
    /// Auto-join the official Stitch Social community if not already a member.
    /// Call once on login. Costs: 1 read (membership check) + 0-2 writes (join if needed).
    func autoJoinOfficialCommunity(userID: String, username: String, displayName: String) async {
        let creatorID = CommunityService.officialCommunityID
        
        // Skip if already cached as member
        let cacheKey = "\(userID)_\(creatorID)"
        if let cached = isMemberCache[cacheKey], !cached.isExpired, cached.value {
            return
        }
        
        do {
            // Check membership (1 read, may be cached)
            let memberRef = db.collection(Collections.communities)
                .document(creatorID)
                .collection(Collections.members)
                .document(userID)
            
            let doc = try await memberRef.getDocument()
            if doc.exists {
                // Already a member, cache it
                isMemberCache[cacheKey] = CachedItem(value: true, cachedAt: Date(), ttl: membershipTTL)
                return
            }
            
            // Not a member — auto-join with free tier
            let membership = CommunityMembership(
                userID: userID,
                communityID: creatorID,
                username: username,
                displayName: displayName,
                subscriptionTier: .supporter
            )
            
            let batch = db.batch()
            try batch.setData(from: membership, forDocument: memberRef)
            let communityRef = db.collection(Collections.communities).document(creatorID)
            batch.updateData(["memberCount": FieldValue.increment(Int64(1))], forDocument: communityRef)
            try await batch.commit()
            
            // Cache
            isMemberCache[cacheKey] = CachedItem(value: true, cachedAt: Date(), ttl: membershipTTL)
            communityListCache = nil
            
            print("✅ COMMUNITY: Auto-joined \(username) to Stitch Social official")
        } catch {
            print("⚠️ COMMUNITY: Auto-join failed - \(error.localizedDescription)")
        }
    }
    // MARK: - Create Community (Influencer+ Only)
    
    @MainActor
    func createCommunity(
        creatorID: String,
        creatorUsername: String,
        creatorDisplayName: String,
        creatorTier: UserTier,
        displayName: String? = nil,
        description: String = ""
    ) async throws -> Community {
        
        // Tier gate — influencer+ only
        guard Community.canCreateCommunity(tier: creatorTier) else {
            throw CommunityError.insufficientTier
        }
        
        // Check if already exists (one per creator)
        let existingRef = db.collection(Collections.communities).document(creatorID)
        let existingDoc = try await existingRef.getDocument()
        
        if existingDoc.exists {
            throw CommunityError.communityAlreadyExists
        }
        
        let community = Community(
            creatorID: creatorID,
            creatorUsername: creatorUsername,
            creatorDisplayName: creatorDisplayName,
            creatorTier: creatorTier,
            displayName: displayName,
            description: description
        )
        
        try existingRef.setData(from: community)
        
        // Cache it
        communityCache[creatorID] = CachedItem(value: community, cachedAt: Date(), ttl: communityTTL)
        self.currentCommunity = community
        
        print("✅ COMMUNITY: Created for \(creatorUsername)")
        return community
    }
    
    // MARK: - Auto-Create Inactive Community (Called on Tier-Up)
    
    /// Called by tier advancement when user hits Influencer+
    /// Creates an inactive community so it's ready when creator wants to launch
    /// Single write, no UI — runs silently in background
    @MainActor
    func autoCreateCommunity(
        creatorID: String,
        creatorUsername: String,
        creatorDisplayName: String,
        creatorTier: UserTier
    ) async {
        // Only influencer+ gets auto-created
        guard Community.canCreateCommunity(tier: creatorTier) else { return }
        
        // Check if already exists — no error, just skip
        do {
            let existingRef = db.collection(Collections.communities).document(creatorID)
            let existingDoc = try await existingRef.getDocument()
            
            if existingDoc.exists {
                print("ℹ️ COMMUNITY: Already exists for \(creatorUsername), skipping auto-create")
                return
            }
            
            var community = Community(
                creatorID: creatorID,
                creatorUsername: creatorUsername,
                creatorDisplayName: creatorDisplayName,
                creatorTier: creatorTier
            )
            community.isActive = false  // Inactive until creator activates
            
            try existingRef.setData(from: community)
            
            communityCache[creatorID] = CachedItem(value: community, cachedAt: Date(), ttl: communityTTL)
            
            print("✅ COMMUNITY: Auto-created (inactive) for \(creatorUsername) on tier-up to \(creatorTier.displayName)")
        } catch {
            print("⚠️ COMMUNITY: Auto-create failed for \(creatorUsername): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Activate Community (Creator Settings)
    
    /// Creator toggles their community on from settings
    /// Updates isActive flag and optional name/description
    @MainActor
    func activateCommunity(
        creatorID: String,
        displayName: String? = nil,
        description: String? = nil
    ) async throws -> Community {
        
        let docRef = db.collection(Collections.communities).document(creatorID)
        let doc = try await docRef.getDocument()
        
        guard var community = try? doc.data(as: Community.self) else {
            throw CommunityError.communityNotFound
        }
        
        community.isActive = true
        community.updatedAt = Date()
        if let displayName = displayName, !displayName.isEmpty {
            community.displayName = displayName
        }
        if let description = description {
            community.description = description
        }
        
        try docRef.setData(from: community)
        
        communityCache[creatorID] = CachedItem(value: community, cachedAt: Date(), ttl: communityTTL)
        self.currentCommunity = community
        
        print("✅ COMMUNITY: Activated for \(creatorID)")
        return community
    }
    
    // MARK: - Deactivate Community (Creator Settings)
    
    @MainActor
    func deactivateCommunity(creatorID: String) async throws {
        try await db.collection(Collections.communities)
            .document(creatorID)
            .updateData([
                "isActive": false,
                "updatedAt": Timestamp(date: Date())
            ])
        
        communityCache.removeValue(forKey: creatorID)
        
        print("⏸️ COMMUNITY: Deactivated for \(creatorID)")
    }
    
    // MARK: - Fetch Community Status (For Settings UI)
    
    /// Returns community if it exists (active or not) — for creator settings
    func fetchCommunityStatus(creatorID: String) async throws -> CommunityStatus {
        let doc = try await db.collection(Collections.communities)
            .document(creatorID)
            .getDocument()
        
        guard let community = try? doc.data(as: Community.self) else {
            return .notCreated
        }
        
        return community.isActive ? .active(community) : .inactive(community)
    }
    
    // MARK: - Fetch Community
    
    func fetchCommunity(creatorID: String) async throws -> Community? {
        // Check cache first
        if let cached = communityCache[creatorID], !cached.isExpired {
            return cached.value
        }
        
        let docRef = db.collection(Collections.communities).document(creatorID)
        let doc = try await docRef.getDocument()
        
        guard let community = try? doc.data(as: Community.self) else {
            return nil
        }
        
        // Cache
        communityCache[creatorID] = CachedItem(value: community, cachedAt: Date(), ttl: communityTTL)
        return community
    }
    
    // MARK: - Update Community (Creator Only)
    
    @MainActor
    func updateCommunity(
        creatorID: String,
        displayName: String? = nil,
        description: String? = nil,
        profileImageURL: String? = nil,
        bannerImageURL: String? = nil,
        pinnedPostID: String? = nil
    ) async throws {
        
        var updates: [String: Any] = ["updatedAt": Timestamp(date: Date())]
        
        if let displayName = displayName { updates["displayName"] = displayName }
        if let description = description { updates["description"] = description }
        if let profileImageURL = profileImageURL { updates["profileImageURL"] = profileImageURL }
        if let bannerImageURL = bannerImageURL { updates["bannerImageURL"] = bannerImageURL }
        if let pinnedPostID = pinnedPostID { updates["pinnedPostID"] = pinnedPostID }
        
        try await db.collection(Collections.communities)
            .document(creatorID)
            .updateData(updates)
        
        // Invalidate cache
        communityCache.removeValue(forKey: creatorID)
        
        print("✅ COMMUNITY: Updated \(creatorID)")
    }
    
    // MARK: - Join Community (Subscribe Required)
    
    @MainActor
    func joinCommunity(
        userID: String,
        username: String,
        displayName: String,
        creatorID: String
    ) async throws -> CommunityMembership {
        
        isLoading = true
        defer { isLoading = false }
        
        // Determine subscription tier — developers bypass subscription check
        var tier: SubscriptionTier = .superFan
        
        if !SubscriptionService.shared.isDeveloper {
            // Verify active subscription exists
            let subCheck = try await subscriptionService.checkSubscription(
                subscriberID: userID,
                creatorID: creatorID
            )
            
            guard subCheck.isSubscribed, let subTier = subCheck.tier else {
                throw CommunityError.subscriptionRequired
            }
            tier = subTier
        }
        
        // Verify community exists
        guard let community = try await fetchCommunity(creatorID: creatorID),
              community.isActive else {
            throw CommunityError.communityNotFound
        }
        
        // Check if already a member
        let memberRef = db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
        
        let existingDoc = try await memberRef.getDocument()
        if existingDoc.exists {
            if let existing = try? existingDoc.data(as: CommunityMembership.self), !existing.isBanned {
                throw CommunityError.alreadyMember
            }
        }
        
        // Resolve username/displayName if not provided (e.g. join by ID)
        var resolvedUsername = username
        var resolvedDisplayName = displayName
        if resolvedUsername.isEmpty || resolvedDisplayName.isEmpty {
            let userDoc = try await db.collection("users").document(userID).getDocument()
            if let data = userDoc.data() {
                if resolvedUsername.isEmpty {
                    resolvedUsername = data["username"] as? String ?? "user_\(userID.prefix(6))"
                }
                if resolvedDisplayName.isEmpty {
                    resolvedDisplayName = data["displayName"] as? String ?? resolvedUsername
                }
            }
        }
        
        let membership = CommunityMembership(
            userID: userID,
            communityID: creatorID,
            username: resolvedUsername,
            displayName: resolvedDisplayName,
            subscriptionTier: tier
        )
        
        // BATCHED WRITE: membership doc + community member count increment
        let batch = db.batch()
        
        try batch.setData(from: membership, forDocument: memberRef)
        
        let communityRef = db.collection(Collections.communities).document(creatorID)
        batch.updateData(["memberCount": FieldValue.increment(Int64(1))], forDocument: communityRef)
        
        try await batch.commit()
        
        // Cache membership
        let cacheKey = "\(userID)_\(creatorID)"
        membershipCache[cacheKey] = CachedItem(value: membership, cachedAt: Date(), ttl: membershipTTL)
        isMemberCache[cacheKey] = CachedItem(value: true, cachedAt: Date(), ttl: membershipTTL)
        
        // Invalidate community cache (member count changed) and list cache
        communityCache.removeValue(forKey: creatorID)
        communityListCache = nil
        
        self.currentMembership = membership
        
        print("✅ COMMUNITY: \(username) joined \(creatorID)")
        return membership
    }
    
    // MARK: - Leave Community
    
    @MainActor
    func leaveCommunity(userID: String, creatorID: String) async throws {
        
        isLoading = true
        defer { isLoading = false }
        
        let memberRef = db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
        
        // BATCHED WRITE: delete member + decrement count
        let batch = db.batch()
        
        batch.deleteDocument(memberRef)
        
        let communityRef = db.collection(Collections.communities).document(creatorID)
        batch.updateData(["memberCount": FieldValue.increment(Int64(-1))], forDocument: communityRef)
        
        try await batch.commit()
        
        // Clear all related caches
        let cacheKey = "\(userID)_\(creatorID)"
        membershipCache.removeValue(forKey: cacheKey)
        isMemberCache.removeValue(forKey: cacheKey)
        communityCache.removeValue(forKey: creatorID)
        communityListCache = nil
        
        self.currentMembership = nil
        
        print("❌ COMMUNITY: \(userID) left \(creatorID)")
    }
    
    // MARK: - Check Membership (Cached)
    
    func isMember(userID: String, creatorID: String) async throws -> Bool {
        let cacheKey = "\(userID)_\(creatorID)"
        
        // Check cache first — avoids a read on every navigation
        if let cached = isMemberCache[cacheKey], !cached.isExpired {
            return cached.value
        }
        
        let doc = try await db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
            .getDocument()
        
        let result = doc.exists
        isMemberCache[cacheKey] = CachedItem(value: result, cachedAt: Date(), ttl: membershipTTL)
        
        return result
    }
    
    // MARK: - Fetch Membership (with XP/Level)
    
    func fetchMembership(userID: String, creatorID: String) async throws -> CommunityMembership? {
        let cacheKey = "\(userID)_\(creatorID)"
        
        if let cached = membershipCache[cacheKey], !cached.isExpired {
            return cached.value
        }
        
        let doc = try await db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
            .getDocument()
        
        guard var membership = try? doc.data(as: CommunityMembership.self) else {
            return nil
        }
        
        // Developer bypass — max level, all features unlocked
        if SubscriptionService.shared.isDeveloper {
            membership.level = 1000
            membership.localXP = 999999
            membership.isModerator = true
        }
        
        membershipCache[cacheKey] = CachedItem(value: membership, cachedAt: Date(), ttl: membershipTTL)
        return membership
    }
    
    // MARK: - Fetch My Communities (Single Query)
    
    /// Uses subscription list to build community list — ONE query, not N reads
    /// CACHING: Full list cached with 5-min TTL
    @MainActor
    func fetchMyCommunities(userID: String) async throws -> [CommunityListItem] {
        
        // Check list cache
        if let cached = communityListCache, !cached.isExpired {
            self.myCommunities = cached.value
            return cached.value
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Get all active subscriptions (already cached in SubscriptionService)
        let subscriptions = try await subscriptionService.fetchMySubscriptions(userID: userID)
        
        // Collect creatorIDs from subscriptions + own community
        var creatorIDs = subscriptions.map { $0.creatorID }
        
        // Always include user's own community (creator sees their own)
        if !creatorIDs.contains(userID) {
            creatorIDs.append(userID)
        }
        
        // Always include official Stitch Social community
        let officialID = CommunityService.officialCommunityID
        if !creatorIDs.contains(officialID) {
            creatorIDs.append(officialID)
        }
        
        guard !creatorIDs.isEmpty else {
            self.myCommunities = []
            communityListCache = CachedItem(value: [], cachedAt: Date(), ttl: listTTL)
            return []
        }
        
        // Fetch communities and memberships in parallel batches
        // Firestore 'in' queries support max 30 items per batch
        var listItems: [CommunityListItem] = []
        
        let batchSize = 30
        for batchStart in stride(from: 0, to: creatorIDs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, creatorIDs.count)
            let batchIDs = Array(creatorIDs[batchStart..<batchEnd])
            
            let snapshot = try await db.collection(Collections.communities)
                .whereField(FieldPath.documentID(), in: batchIDs)
                .getDocuments()
            
            for doc in snapshot.documents {
                guard let community = try? doc.data(as: Community.self) else { continue }
                
                // Fetch membership for XP/level (may be cached)
                let membership = try await fetchMembership(userID: userID, creatorID: community.id)
                
                let item = CommunityListItem(
                    id: community.id,
                    creatorUsername: community.creatorUsername,
                    creatorDisplayName: community.creatorDisplayName,
                    creatorTier: community.creatorTier,
                    profileImageURL: community.profileImageURL,
                    memberCount: community.memberCount,
                    userLevel: membership?.level ?? 1,
                    userXP: membership?.localXP ?? 0,
                    unreadCount: 0,     // TODO: Calculate from last read timestamp
                    lastActivityPreview: "",
                    lastActivityAt: community.updatedAt,
                    isCreatorLive: false, // TODO: Check live stream status
                    isVerified: community.creatorTier.crownBadge != nil
                )
                
                listItems.append(item)
            }
        }
        
        // Sort: live first, then by last activity
        listItems.sort { a, b in
            if a.isCreatorLive != b.isCreatorLive { return a.isCreatorLive }
            return a.lastActivityAt > b.lastActivityAt
        }
        
        self.myCommunities = listItems
        communityListCache = CachedItem(value: listItems, cachedAt: Date(), ttl: listTTL)
        
        print("✅ COMMUNITY: Loaded \(listItems.count) communities for \(userID)")
        return listItems
    }
    
    // MARK: - Fetch All Communities (Discovery)
    
    /// Fetches all active communities for discovery. Any user can browse.
    /// CACHING: 5-min TTL, separate from myCommunities cache.
    /// Cost: 1 read (collection query) + 0 membership reads (no user-specific data needed for browse)
    @Published var allCommunities: [CommunityListItem] = []
    private var allCommunitiesCache: CachedItem<[CommunityListItem]>?
    
    @MainActor
    func fetchAllCommunities() async throws -> [CommunityListItem] {
        
        if let cached = allCommunitiesCache, !cached.isExpired {
            self.allCommunities = cached.value
            return cached.value
        }
        
        let snapshot = try await db.collection(Collections.communities)
            .whereField("isActive", isEqualTo: true)
            .order(by: "memberCount", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        let items: [CommunityListItem] = snapshot.documents.compactMap { doc in
            guard let community = try? doc.data(as: Community.self) else { return nil }
            return CommunityListItem(
                id: community.id,
                creatorUsername: community.creatorUsername,
                creatorDisplayName: community.creatorDisplayName,
                creatorTier: community.creatorTier,
                profileImageURL: community.profileImageURL,
                memberCount: community.memberCount,
                userLevel: 0,
                userXP: 0,
                unreadCount: 0,
                lastActivityPreview: community.description,
                lastActivityAt: community.updatedAt,
                isCreatorLive: false,
                isVerified: community.creatorTier.crownBadge != nil
            )
        }
        
        self.allCommunities = items
        allCommunitiesCache = CachedItem(value: items, cachedAt: Date(), ttl: listTTL)
        
        print("✅ COMMUNITY: Loaded \(items.count) public communities")
        return items
    }
    
    // MARK: - Fetch Community Members (Paginated)
    
    func fetchMembers(
        creatorID: String,
        limit: Int = 20,
        afterDocument: DocumentSnapshot? = nil
    ) async throws -> (members: [CommunityMembership], lastDoc: DocumentSnapshot?) {
        
        var query = db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .order(by: "level", descending: true)
            .limit(to: limit)
        
        if let afterDoc = afterDocument {
            query = query.start(afterDocument: afterDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let members = snapshot.documents.compactMap { doc -> CommunityMembership? in
            try? doc.data(as: CommunityMembership.self)
        }
        
        let lastDoc = snapshot.documents.last
        return (members, lastDoc)
    }
    
    // MARK: - Ban/Unban Member (Creator Only)
    
    @MainActor
    func banMember(userID: String, creatorID: String) async throws {
        try await db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
            .updateData(["isBanned": true])
        
        // Invalidate caches
        let cacheKey = "\(userID)_\(creatorID)"
        membershipCache.removeValue(forKey: cacheKey)
        isMemberCache[cacheKey] = CachedItem(value: false, cachedAt: Date(), ttl: membershipTTL)
        
        print("🚫 COMMUNITY: Banned \(userID) from \(creatorID)")
    }
    
    @MainActor
    func unbanMember(userID: String, creatorID: String) async throws {
        try await db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
            .updateData(["isBanned": false])
        
        let cacheKey = "\(userID)_\(creatorID)"
        membershipCache.removeValue(forKey: cacheKey)
        isMemberCache.removeValue(forKey: cacheKey)
        
        print("✅ COMMUNITY: Unbanned \(userID) from \(creatorID)")
    }
    
    // MARK: - Set Moderator (Creator Only)
    
    @MainActor
    func setModerator(userID: String, creatorID: String, isMod: Bool) async throws {
        // Verify level requirement
        if isMod {
            guard let membership = try await fetchMembership(userID: userID, creatorID: creatorID),
                  membership.canBeNominatedMod else {
                throw CommunityError.levelTooLow
            }
        }
        
        try await db.collection(Collections.communities)
            .document(creatorID)
            .collection(Collections.members)
            .document(userID)
            .updateData(["isModerator": isMod])
        
        // Invalidate cache
        membershipCache.removeValue(forKey: "\(userID)_\(creatorID)")
        
        print("✅ COMMUNITY: \(userID) mod status = \(isMod) in \(creatorID)")
    }
    
    // MARK: - Feature Gate Check (Cached via Membership)
    
    /// Quick check if user can access a feature — uses cached membership
    func canAccess(
        feature: CommunityFeatureGate,
        userID: String,
        creatorID: String
    ) async throws -> Bool {
        guard let membership = try await fetchMembership(userID: userID, creatorID: creatorID) else {
            return false
        }
        return membership.isUnlocked(feature)
    }
    
    // MARK: - Check If Creator Has Community
    
    func hasCommunity(creatorID: String) async throws -> Bool {
        if let cached = communityCache[creatorID], !cached.isExpired {
            return true
        }
        
        let doc = try await db.collection(Collections.communities)
            .document(creatorID)
            .getDocument()
        
        return doc.exists
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches — call on logout
    func clearAllCaches() {
        communityCache.removeAll()
        membershipCache.removeAll()
        communityListCache = nil
        isMemberCache.removeAll()
        myCommunities = []
        currentCommunity = nil
        currentMembership = nil
    }
    
    /// Invalidate specific community caches — call after XP updates
    func invalidateMembershipCache(userID: String, creatorID: String) {
        let cacheKey = "\(userID)_\(creatorID)"
        membershipCache.removeValue(forKey: cacheKey)
    }
    
    /// Invalidate community list — call after join/leave/level-up
    func invalidateListCache() {
        communityListCache = nil
    }
    
    /// Prune expired entries — call periodically to prevent memory bloat
    func pruneExpiredCaches() {
        communityCache = communityCache.filter { !$0.value.isExpired }
        membershipCache = membershipCache.filter { !$0.value.isExpired }
        isMemberCache = isMemberCache.filter { !$0.value.isExpired }
        if let listCache = communityListCache, listCache.isExpired {
            communityListCache = nil
        }
    }
}

// MARK: - Community Status (For Creator Settings)

enum CommunityStatus {
    case notCreated                     // No community doc exists
    case inactive(Community)            // Auto-created but not activated
    case active(Community)              // Live and accepting members
    
    var exists: Bool {
        switch self {
        case .notCreated: return false
        case .inactive, .active: return true
        }
    }
    
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
    
    var community: Community? {
        switch self {
        case .notCreated: return nil
        case .inactive(let c), .active(let c): return c
        }
    }
}

// MARK: - Errors

enum CommunityError: LocalizedError, Equatable {
    case insufficientTier
    case communityAlreadyExists
    case communityNotFound
    case subscriptionRequired
    case alreadyMember
    case notMember
    case levelTooLow
    case banned
    case creatorOnly
    
    var errorDescription: String? {
        switch self {
        case .insufficientTier:
            return "You need Influencer tier or higher to create a community"
        case .communityAlreadyExists:
            return "You already have a community"
        case .communityNotFound:
            return "Community not found or inactive"
        case .subscriptionRequired:
            return "You need an active subscription to join this community"
        case .alreadyMember:
            return "You're already a member of this community"
        case .notMember:
            return "You're not a member of this community"
        case .levelTooLow:
            return "Level requirement not met"
        case .banned:
            return "You've been banned from this community"
        case .creatorOnly:
            return "Only the creator can perform this action"
        }
    }
}
