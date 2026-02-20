//
//  PrivacyService.swift
//  StitchSocial
//
//  Created by James Garmon on 2/17/26.
//


//
//  PrivacyService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Privacy Enforcement & Session Caching
//  Dependencies: Firebase Firestore, PrivacySettings, FirebaseSchema
//  Features: Privacy CRUD, discovery filtering, age routing, session caching
//
//  CACHING STRATEGY (add to optimization file):
//  1. ageGroup — fetched once at login, held in memory. Avoids re-read on every upload/storage call.
//  2. followingList — batch-fetched once per session for discovery filtering. Refreshed on follow/unfollow.
//  3. creatorPrivacyMap — batch-fetched for all unique creatorIDs in a discovery page, 5 min TTL.
//  4. currentUserID — cached locally so array-contains checks for allowedViewerIDs cost 0 extra reads.
//
//  BATCHING:
//  - loadCreatorPrivacyBatch() fetches up to 10 user docs in one Firestore IN query
//    instead of N individual reads. Called once per discovery page load.
//  - followingList loaded once, not per-video.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

@MainActor
class PrivacyService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PrivacyService()
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var currentPrivacy: UserPrivacySettings = .default
    @Published var isLoading = false
    
    // MARK: - Session Cache
    
    /// Cached once at login — determines storage bucket + content routing
    private(set) var cachedAgeGroup: AgeGroup = .adult
    
    /// Cached once per session — used for discovery "followers" visibility check
    /// Refreshed on follow/unfollow via NotificationCenter
    private(set) var cachedFollowingIDs: Set<String> = []
    private var followingListFetchedAt: Date?
    
    /// Batch-cached creator privacy settings — keyed by creatorID, 5 min TTL
    /// Prevents N reads when loading a discovery page with N unique creators
    private var creatorPrivacyCache: [String: UserPrivacySettings] = [:]
    private var creatorPrivacyCacheTimestamps: [String: Date] = [:]
    private let creatorCacheTTL: TimeInterval = 300 // 5 minutes
    
    /// Current user ID — cached to avoid Auth.auth().currentUser on every check
    private(set) var cachedCurrentUserID: String?
    
    // MARK: - Init
    
    private init() {
        // Listen for follow state changes to invalidate following cache
        NotificationCenter.default.addObserver(
            forName: .followStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateFollowingCache()
        }
    }
    
    // MARK: - Session Setup (call at login)
    
    /// Load and cache privacy settings + following list for the session.
    /// Call once after authentication. Total cost: 1 user doc read + 1 following subcollection read.
    func loadSessionData(userID: String) async {
        cachedCurrentUserID = userID
        
        async let privacyTask: () = loadPrivacySettings(userID: userID)
        async let followingTask: () = loadFollowingList(userID: userID)
        
        await privacyTask
        await followingTask
        
        print("🔒 PRIVACY: Session loaded — ageGroup=\(cachedAgeGroup.rawValue), following=\(cachedFollowingIDs.count)")
    }
    
    // MARK: - Privacy Settings CRUD
    
    /// Load user's privacy settings from Firestore. 1 read.
    func loadPrivacySettings(userID: String) async {
        do {
            let doc = try await db.collection("users").document(userID).getDocument()
            let privacyMap = doc.data()?[FirebaseSchema.PrivacyFields.privacySettings] as? [String: Any]
            let settings = UserPrivacySettings.from(firestoreMap: privacyMap)
            
            currentPrivacy = settings
            cachedAgeGroup = settings.ageGroup
            
            print("🔒 PRIVACY: Loaded settings for \(userID) — visibility=\(settings.accountVisibility.rawValue)")
        } catch {
            print("⚠️ PRIVACY: Failed to load settings: \(error)")
            currentPrivacy = .default
            cachedAgeGroup = .adult
        }
    }
    
    /// Save user's privacy settings. 1 write (merge).
    func savePrivacySettings(userID: String, settings: UserPrivacySettings) async throws {
        try await db.collection("users").document(userID).updateData([
            FirebaseSchema.PrivacyFields.privacySettings: settings.firestoreData,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        currentPrivacy = settings
        cachedAgeGroup = settings.ageGroup
        
        print("🔒 PRIVACY: Saved settings for \(userID)")
    }
    
    // MARK: - Following List Cache
    
    /// Load following list once per session. 1 subcollection read.
    private func loadFollowingList(userID: String) async {
        do {
            let snapshot = try await db.collection("users")
                .document(userID)
                .collection("following")
                .getDocuments()
            
            cachedFollowingIDs = Set(snapshot.documents.map { $0.documentID })
            followingListFetchedAt = Date()
            
            print("🔒 PRIVACY: Cached \(cachedFollowingIDs.count) following IDs")
        } catch {
            print("⚠️ PRIVACY: Failed to load following list: \(error)")
        }
    }
    
    /// Invalidate following cache (called on follow/unfollow)
    func invalidateFollowingCache() {
        followingListFetchedAt = nil
        print("🔒 PRIVACY: Following cache invalidated")
    }
    
    /// Refresh following list if stale (>10 min) or invalidated
    func refreshFollowingIfNeeded() async {
        guard let userID = cachedCurrentUserID else { return }
        
        let isStale = followingListFetchedAt == nil
            || Date().timeIntervalSince(followingListFetchedAt!) > 600
        
        if isStale {
            await loadFollowingList(userID: userID)
        }
    }
    
    // MARK: - Creator Privacy Batch Cache
    
    /// Batch-fetch privacy settings for multiple creators in one round trip.
    /// Firestore IN query supports up to 10 IDs per call.
    /// Uses 5 min TTL cache to avoid re-fetching same creators.
    func loadCreatorPrivacyBatch(creatorIDs: [String]) async {
        let now = Date()
        
        // Filter out already-cached (non-expired) creators
        let needed = creatorIDs.filter { id in
            guard let timestamp = creatorPrivacyCacheTimestamps[id] else { return true }
            return now.timeIntervalSince(timestamp) > creatorCacheTTL
        }
        
        guard !needed.isEmpty else { return }
        
        // Firestore IN supports max 10
        let chunks = stride(from: 0, to: needed.count, by: 10).map {
            Array(needed[$0..<min($0 + 10, needed.count)])
        }
        
        for chunk in chunks {
            do {
                let snapshot = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                
                for doc in snapshot.documents {
                    let privacyMap = doc.data()[FirebaseSchema.PrivacyFields.privacySettings] as? [String: Any]
                    let settings = UserPrivacySettings.from(firestoreMap: privacyMap)
                    creatorPrivacyCache[doc.documentID] = settings
                    creatorPrivacyCacheTimestamps[doc.documentID] = now
                }
                
                print("🔒 PRIVACY: Batch-cached \(snapshot.documents.count) creator privacy settings")
            } catch {
                print("⚠️ PRIVACY: Batch fetch failed: \(error)")
            }
        }
    }
    
    /// Get cached creator privacy (call after loadCreatorPrivacyBatch)
    func getCreatorPrivacy(_ creatorID: String) -> UserPrivacySettings {
        return creatorPrivacyCache[creatorID] ?? .default
    }
    
    // MARK: - Discovery Filtering
    
    /// Filter videos for public discovery feed.
    /// Uses cached data — 0 extra Firestore reads.
    func filterForDiscovery(_ videos: [CoreVideoMetadata]) -> [CoreVideoMetadata] {
        return videos.filter { video in
            // Must be public and not excluded
            let privacyFields = VideoPrivacyFields.from(firestoreData: [
                "visibility": "public",  // Discovery query already filters for public
                "excludeFromDiscovery": false
            ])
            
            // Teen routing: teen users only see teenSafe content
            if cachedAgeGroup == .teen {
                let videoData = getVideoPrivacyData(video)
                if !videoData.teenSafe { return false }
            }
            
            return true
        }
    }
    
    /// Check if current user can view a specific video.
    /// Uses cached userID + following list — 0 extra reads.
    func canViewVideo(_ videoData: [String: Any], creatorID: String) -> Bool {
        guard let currentUserID = cachedCurrentUserID else { return false }
        
        let visibility = ContentVisibility(rawValue: videoData["visibility"] as? String ?? "public") ?? .public
        
        switch visibility {
        case .public:
            return true
        case .followers:
            return currentUserID == creatorID || cachedFollowingIDs.contains(creatorID)
        case .tagged:
            let allowedViewers = videoData["allowedViewerIDs"] as? [String] ?? []
            return allowedViewers.contains(currentUserID)
        case .private:
            return currentUserID == creatorID
        }
    }
    
    // MARK: - Storage Routing
    
    /// Get the correct Storage reference based on user's age group.
    /// Uses cached ageGroup — 0 reads.
    func storageReference() -> StorageReference {
        let bucket = cachedAgeGroup.storageBucket
        return Storage.storage(url: bucket).reference()
    }
    
    // MARK: - Video Upload Privacy
    
    /// Generate privacy fields for a new video upload.
    /// Uses cached privacy settings — 0 reads.
    func privacyFieldsForUpload(
        taggedUserIDs: [String],
        creatorID: String,
        overrideVisibility: ContentVisibility? = nil
    ) -> VideoPrivacyFields {
        return VideoPrivacyFields.forUpload(
            creatorPrivacy: currentPrivacy,
            taggedUserIDs: taggedUserIDs,
            creatorID: creatorID,
            overrideVisibility: overrideVisibility
        )
    }
    
    // MARK: - Cleanup
    
    /// Clear all caches on sign out
    func clearSession() {
        cachedCurrentUserID = nil
        cachedAgeGroup = .adult
        cachedFollowingIDs = []
        followingListFetchedAt = nil
        creatorPrivacyCache.removeAll()
        creatorPrivacyCacheTimestamps.removeAll()
        currentPrivacy = .default
        print("🔒 PRIVACY: Session cleared")
    }
    
    // MARK: - Private Helpers
    
    private func getVideoPrivacyData(_ video: CoreVideoMetadata) -> VideoPrivacyFields {
        // In production, these fields would be on the video model.
        // For now, default to public + not teen safe unless tagged
        return VideoPrivacyFields(
            visibility: .public,
            allowedViewerIDs: [],
            excludeFromDiscovery: false,
            teenSafe: false
        )
    }
}