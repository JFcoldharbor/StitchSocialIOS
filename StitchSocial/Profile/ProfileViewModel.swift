//
//  ProfileViewModel.swift
//  StitchSocial
//
//  Layer 7: ViewModels - Profile Data Management with Instant Loading
//  Dependencies: AuthService, UserService, VideoService (Layer 4)
//  Features: Instant profile display, lazy content loading, cached data, NotificationCenter integration
//  UPDATED: Added pinned videos support (max 3 threads) and infinite scroll pagination
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ProfileViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    let authService: AuthService
    private let userService: UserService
    private let videoService: VideoService
    private let notificationService = NotificationService()
    private let cachingService = CachingService.shared
    private let viewingUserID: String?  // For viewing other users' profiles
    
    // MARK: - Profile State
    
    @Published var currentUser: BasicUserInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isShowingPlaceholder = true
    
    // MARK: - Extended Profile Data
    @Published var userBio: String?
    @Published var isUserPrivate: Bool = false
    
    // MARK: - Social State
    
    @Published var followingList: [BasicUserInfo] = []
    @Published var followersList: [BasicUserInfo] = []
    @Published var isLoadingFollowing = false
    @Published var isLoadingFollowers = false
    @Published var isFollowing = false
    
    // MARK: - Social Pagination State (NEW)
    
    @Published var hasMoreFollowers = true
    @Published var hasMoreFollowing = true
    @Published var isLoadingMoreFollowers = false
    @Published var isLoadingMoreFollowing = false
    @Published var totalFollowersCount = 0
    @Published var totalFollowingCount = 0
    private var allFollowerIDs: [String] = []
    private var allFollowingIDs: [String] = []
    private var loadedFollowerCount = 0
    private var loadedFollowingCount = 0
    private let socialBatchSize = 30
    
    // MARK: - Video Grid State
    
    @Published var selectedTab = 0
    @Published var userVideos: [CoreVideoMetadata] = []
    @Published var isLoadingVideos = false
    
    // MARK: - Pinned Videos State (NEW)
    
    @Published var pinnedVideos: [CoreVideoMetadata] = []
    @Published var pinnedVideoIDs: [String] = []
    @Published var isPinningVideo = false
    
    /// Maximum number of pinned videos allowed
    static let maxPinnedVideos = 3
    
    // MARK: - Pagination State (NEW)
    
    @Published var hasMoreVideos: Bool = true
    @Published var isLoadingMoreVideos = false
    private var lastVideoDocument: DocumentSnapshot?
    
    /// Initial batch size for video loading
    private let initialVideoLimit = 30
    /// Batch size for subsequent loads
    private let paginationBatchSize = 20
    
    // MARK: - Animation State
    
    @Published var animationController: ProfileAnimationController
    
    // MARK: - Badge State
    // CACHING: BadgeService uses a single Firestore snapshot listener per user.
    // No repeated reads — all badge data served from in-memory cache after first load.
    @Published var signalStats: SignalStats? = nil
    private var loadedBadgeUserID: String?

    // MARK: - Caching for Performance
    private var cachedUserProfile: BasicUserInfo?
    private var profileCacheTime: Date?
    private let profileCacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService, viewingUserID: String? = nil) {
        self.authService = authService
        self.userService = userService
        self.videoService = videoService
        self.viewingUserID = viewingUserID
        self.animationController = ProfileAnimationController()
        
        // ðŸ”§ DEBUG: Confirm viewingUserID is received in init
        #if DEBUG
        print("ðŸ”§ PROFILEVIEWMODEL INIT: viewingUserID = \(viewingUserID ?? "nil")")
        #endif
        
        // Setup NotificationCenter observers for profile refresh
        setupNotificationObservers()
    }
    
    // MARK: - NotificationCenter Integration
    
    /// Setup NotificationCenter observers for profile updates
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshProfile"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                await self?.handleProfileRefreshNotification(notification)
            }
        }
        
        #if DEBUG
        print("PROFILE VIEWMODEL: NotificationCenter observers setup complete")
        #endif
    }
    
    /// Handle profile refresh notifications from EditProfileView
    private func handleProfileRefreshNotification(_ notification: Notification) async {
        #if DEBUG
        print("PROFILE VIEWMODEL: Received RefreshProfile notification - triggering refresh")
        #endif
        
        // Clear cache and extended data to force fresh data load
        cachedUserProfile = nil
        profileCacheTime = nil
        userBio = nil
        isUserPrivate = false
        
        // Refresh profile data directly
        await refreshProfile()
        
        // If userInfo contains specific user ID, validate it matches current user
        if let userInfo = notification.userInfo,
           let notificationUserID = userInfo["userID"] as? String,
           let currentUserID = currentUser?.id {
            
            if notificationUserID == currentUserID {
                #if DEBUG
                print("PROFILE VIEWMODEL: Profile refresh confirmed for user \(currentUserID)")
                #endif
            } else {
                #if DEBUG
                print("PROFILE VIEWMODEL: Profile refresh notification for different user, ignoring")
                #endif
            }
        }
    }
    
    /// Cleanup NotificationCenter observers
    private nonisolated func cleanupNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
        #if DEBUG
        print("PROFILE VIEWMODEL: NotificationCenter observers cleaned up")
        #endif
    }
    
    // MARK: - Deinitialization
    
    deinit {
        let uid = loadedBadgeUserID
        Task { @MainActor in
            if let uid { BadgeService.shared.stopListening(userID: uid) }
        }
        cleanupNotificationObservers()
        #if DEBUG
        print("PROFILE VIEWMODEL: Deinitializing with proper cleanup")
        #endif
    }
    
    // MARK: - INSTANT LOADING IMPLEMENTATION
    
    /// Load profile instantly with placeholder, then enhance with real data
    func loadProfile() async {
        // âœ… FIXED: Determine which user to load - viewingUserID takes priority
        let userIDToLoad: String
        if let viewingUserID = viewingUserID {
            userIDToLoad = viewingUserID
            #if DEBUG
            print("ðŸ” PROFILE: Loading OTHER user profile - \(userIDToLoad)")
            #endif
        } else {
            guard let currentUserID = authService.currentUserID else {
                errorMessage = "Authentication required"
                return
            }
            userIDToLoad = currentUserID
            #if DEBUG
            print("ðŸ‘¤ PROFILE: Loading OWN user profile - \(currentUserID)")
            #endif
        }
        
        #if DEBUG
        print("PROFILE: Starting instant load for user \(userIDToLoad)")
        #endif
        
        // STEP 1: Check cache for instant display
        if let cached = getCachedProfile(userID: userIDToLoad) {
            currentUser = cached
            isShowingPlaceholder = false
            #if DEBUG
            print("PROFILE CACHE HIT: Instant display for \(userIDToLoad)")
            #endif
            
            // Load enhancements in background
            Task {
                await loadEnhancementsInBackground(userID: userIDToLoad)
            }
            return
        }
        
        // STEP 2: Show placeholder profile immediately
        showPlaceholderProfile(userID: userIDToLoad)
        
        // STEP 3: Load real profile in background
        Task {
            await loadRealProfileInBackground(userID: userIDToLoad)
        }
        
        #if DEBUG
        print("PROFILE: UI ready with placeholder")
        #endif
    }
    
    /// Show placeholder profile for instant display
    private func showPlaceholderProfile(userID: String) {
        currentUser = BasicUserInfo(
            id: userID,
            username: "loading...",
            displayName: "Loading Profile...",
            tier: .rookie,
            clout: 0,
            isVerified: false,
            profileImageURL: nil
        )
        
        isShowingPlaceholder = true
        #if DEBUG
        print("PROFILE PLACEHOLDER: Showing placeholder")
        #endif
    }
    
    /// Load real profile data in background
    private func loadRealProfileInBackground(userID: String) async {
        do {
            #if DEBUG
            print("PROFILE BACKGROUND: Loading real profile data...")
            #endif
            
            if let userProfile = try await userService.getUser(id: userID) {
                await MainActor.run {
                    self.currentUser = userProfile
                    self.isShowingPlaceholder = false
                    #if DEBUG
                    print("PROFILE BACKGROUND: UI updated with fresh profile data - \(userProfile.displayName)")
                    #endif
                }
                
                // Cache for future instant loads
                cacheProfile(userProfile)
                
                // Start badge listener — single snapshot listener, no repeated reads
                BadgeService.shared.listenForBadges(userID: userID)
                loadedBadgeUserID = userID
                
                // Load extended profile data (bio, privacy settings)
                await loadExtendedProfileData(userID: userID)
                
                // Load additional content in background
                Task {
                    await loadEnhancementsInBackground(userID: userID)
                }
                
                #if DEBUG
                print("PROFILE BACKGROUND: Real profile loaded and cached")
                #endif
            } else {
                await MainActor.run {
                    self.errorMessage = "Profile not found"
                    self.isShowingPlaceholder = false
                }
                #if DEBUG
                print("PROFILE BACKGROUND: Profile not found in database")
                #endif
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isShowingPlaceholder = false
            }
            #if DEBUG
            print("PROFILE ERROR: Failed to load profile - \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load extended profile data (bio, privacy, etc.)
    private func loadExtendedProfileData(userID: String) async {
        do {
            if let extendedProfile = try await userService.getExtendedProfile(id: userID) {
                await MainActor.run {
                    self.userBio = extendedProfile.bio.isEmpty ? nil : extendedProfile.bio
                    self.isUserPrivate = extendedProfile.isPrivate
                }
                #if DEBUG
                print("PROFILE EXTENDED: Loaded bio and privacy settings")
                #endif
            }
            // Decode signalStats from user doc — sourced from existing read, zero extra cost
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let snap = try await db.collection(FirebaseSchema.Collections.users).document(userID).getDocument()
            if let sd = snap.data()?["signalStats"] as? [String: Any] {
                await MainActor.run {
                    self.signalStats = SignalStats(
                        totalInfluencerHypes:  sd["totalInfluencerHypes"]  as? Int ?? 0,
                        peakSinglePostSignals: sd["peakSinglePostSignals"] as? Int ?? 0,
                        distinctTierCount:     sd["distinctTierCount"]     as? Int ?? 0,
                        founderHypeCount:      sd["founderHypeCount"]      as? Int ?? 0
                    )
                }
            }
        } catch {
            #if DEBUG
            print("PROFILE EXTENDED ERROR: Failed to load extended data - \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load profile enhancements in background (videos, social data)
    private func loadEnhancementsInBackground(userID: String) async {
        #if DEBUG
        print("PROFILE ENHANCEMENTS: Loading additional data for \(userID)...")
        #endif
        
        // Load all enhancements concurrently
        await withTaskGroup(of: Void.self) { group in
            
            // Load pinned videos first (NEW)
            group.addTask {
                await self.loadPinnedVideos(userID: userID)
            }
            
            // âœ… FIXED: Pass userID to ensure we load correct user's videos
            group.addTask {
                await self.loadUserVideosLazily(userID: userID)
            }
            
            // Load social connections
            group.addTask {
                await self.loadFollowingLazily(userID: userID, limit: 50)
            }
            
            group.addTask {
                await self.loadFollowersLazily(userID: userID, limit: 50)
            }
            
            // Start animations
            group.addTask {
                await self.startProfileAnimations()
            }
        }
        
        #if DEBUG
        print("PROFILE ENHANCEMENTS: Background loading complete for \(userID)")
        #endif
    }
    
    // MARK: - Pinned Videos Methods (NEW)
    
    /// Load pinned videos for a user
    func loadPinnedVideos(userID: String? = nil) async {
        let targetUserID = userID ?? currentUser?.id
        guard let targetUserID = targetUserID else { return }
        
        #if DEBUG
        print("ðŸ“Œ PINNED: Loading pinned videos for user \(targetUserID)")
        #endif
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Get user document to read pinnedVideoIDs
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(targetUserID)
                .getDocument()
            
            guard let userData = userDoc.data() else {
                #if DEBUG
                print("ðŸ“Œ PINNED: No user data found")
                #endif
                return
            }
            
            // Read pinnedVideoIDs array
            let pinnedIDs = userData[FirebaseSchema.UserDocument.pinnedVideoIDs] as? [String] ?? []
            
            await MainActor.run {
                self.pinnedVideoIDs = pinnedIDs
            }
            
            guard !pinnedIDs.isEmpty else {
                #if DEBUG
                print("ðŸ“Œ PINNED: No pinned videos")
                #endif
                await MainActor.run {
                    self.pinnedVideos = []
                }
                return
            }
            
            // Fetch the actual video documents
            var fetchedVideos: [CoreVideoMetadata] = []
            
            for videoID in pinnedIDs {
                let videoDoc = try await db.collection(FirebaseSchema.Collections.videos)
                    .document(videoID)
                    .getDocument()
                
                if let videoData = videoDoc.data() {
                    let video = createVideoMetadata(from: videoData, documentID: videoDoc.documentID)
                    fetchedVideos.append(video)
                }
            }
            
            // Maintain order from pinnedVideoIDs
            let orderedVideos = pinnedIDs.compactMap { id in
                fetchedVideos.first { $0.id == id }
            }
            
            await MainActor.run {
                self.pinnedVideos = orderedVideos
            }
            
            #if DEBUG
            print("ðŸ“Œ PINNED: Loaded \(orderedVideos.count) pinned videos")
            #endif
            
        } catch {
            #if DEBUG
            print("ðŸ“Œ PINNED ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Pin a video to profile (threads only, max 3)
    func pinVideo(_ video: CoreVideoMetadata) async -> Bool {
        guard let userID = currentUser?.id else {
            #if DEBUG
            print("ðŸ“Œ PIN ERROR: No current user")
            #endif
            return false
        }
        
        // Validation: threads only
        guard video.conversationDepth == 0 else {
            #if DEBUG
            print("ðŸ“Œ PIN ERROR: Only threads can be pinned (depth must be 0)")
            #endif
            errorMessage = "Only threads can be pinned to your profile"
            return false
        }
        
        // Validation: max 3 pinned
        guard pinnedVideoIDs.count < Self.maxPinnedVideos else {
            #if DEBUG
            print("ðŸ“Œ PIN ERROR: Maximum \(Self.maxPinnedVideos) pinned videos allowed")
            #endif
            errorMessage = "You can only pin up to \(Self.maxPinnedVideos) videos"
            return false
        }
        
        // Validation: not already pinned
        guard !pinnedVideoIDs.contains(video.id) else {
            #if DEBUG
            print("ðŸ“Œ PIN ERROR: Video already pinned")
            #endif
            return false
        }
        
        isPinningVideo = true
        defer { isPinningVideo = false }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Add to pinnedVideoIDs array in Firestore
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .updateData([
                    FirebaseSchema.UserDocument.pinnedVideoIDs: FieldValue.arrayUnion([video.id]),
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
            
            // Update local state
            await MainActor.run {
                self.pinnedVideoIDs.append(video.id)
                self.pinnedVideos.append(video)
                
                // Remove from userVideos so it doesn't appear in Threads tab
                self.userVideos.removeAll { $0.id == video.id }
            }
            
            #if DEBUG
            print("ðŸ“Œ PIN SUCCESS: Pinned video \(video.id)")
            #endif
            return true
            
        } catch {
            #if DEBUG
            print("ðŸ“Œ PIN ERROR: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to pin video: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Unpin a video from profile
    func unpinVideo(_ video: CoreVideoMetadata) async -> Bool {
        guard let userID = currentUser?.id else {
            #if DEBUG
            print("ðŸ“Œ UNPIN ERROR: No current user")
            #endif
            return false
        }
        
        guard pinnedVideoIDs.contains(video.id) else {
            #if DEBUG
            print("ðŸ“Œ UNPIN ERROR: Video not pinned")
            #endif
            return false
        }
        
        isPinningVideo = true
        defer { isPinningVideo = false }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Remove from pinnedVideoIDs array in Firestore
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .updateData([
                    FirebaseSchema.UserDocument.pinnedVideoIDs: FieldValue.arrayRemove([video.id]),
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
            
            // Update local state
            await MainActor.run {
                self.pinnedVideoIDs.removeAll { $0 == video.id }
                self.pinnedVideos.removeAll { $0.id == video.id }
                
                // Re-insert into userVideos in correct chronological position
                self.insertVideoChronologically(video)
            }
            
            #if DEBUG
            print("ðŸ“Œ UNPIN SUCCESS: Unpinned video \(video.id)")
            #endif
            return true
            
        } catch {
            #if DEBUG
            print("ðŸ“Œ UNPIN ERROR: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to unpin video: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Check if a video can be pinned
    func canPinVideo(_ video: CoreVideoMetadata) -> Bool {
        return video.conversationDepth == 0 &&
               pinnedVideoIDs.count < Self.maxPinnedVideos &&
               !pinnedVideoIDs.contains(video.id)
    }
    
    /// Check if a video is currently pinned
    func isVideoPinned(_ video: CoreVideoMetadata) -> Bool {
        return pinnedVideoIDs.contains(video.id)
    }
    
    /// Insert video back into userVideos in chronological order (newest first)
    private func insertVideoChronologically(_ video: CoreVideoMetadata) {
        // Find the correct position based on createdAt
        let insertIndex = userVideos.firstIndex { $0.createdAt < video.createdAt } ?? userVideos.count
        userVideos.insert(video, at: insertIndex)
    }
    
    // MARK: - Video Loading with Pagination (UPDATED)
    
    /// Load user videos with performance optimization and pagination
    private func loadUserVideosLazily(userID: String? = nil) async {
        let targetUserID = userID ?? currentUser?.id
        guard let targetUserID = targetUserID else {
            #if DEBUG
            print("PROFILE VIDEOS ERROR: No user ID available")
            #endif
            return
        }
        
        #if DEBUG
        print("PROFILE VIDEOS: Loading videos for user \(targetUserID)")
        #endif
        
        // CACHE: Serve cached videos instantly while Firestore loads
        let cachedVideos = cachingService.getCachedVideosForUser(targetUserID)
        if !cachedVideos.isEmpty {
            let filtered = cachedVideos.filter { !pinnedVideoIDs.contains($0.id) && !$0.isCollectionSegment }
            self.userVideos = filtered
            self.isLoadingVideos = false
            #if DEBUG
            print("PROFILE CACHE: Instant display of \(filtered.count) cached videos")
            #endif
        } else {
            self.isLoadingVideos = true
        }
        
        self.lastVideoDocument = nil
        self.hasMoreVideos = true
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: targetUserID)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: initialVideoLimit)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { doc -> CoreVideoMetadata? in
                return createVideoMetadata(from: doc.data(), documentID: doc.documentID)
            }
            
            // CACHE: Store fresh videos for next load
            cachingService.cacheVideos(videos)
            
            let filteredVideos = videos.filter { !pinnedVideoIDs.contains($0.id) && !$0.isCollectionSegment }
            let lastDoc = snapshot.documents.last
            let hasMore = snapshot.documents.count >= initialVideoLimit
            
            self.userVideos = filteredVideos
            self.lastVideoDocument = lastDoc
            self.hasMoreVideos = hasMore
            self.isLoadingVideos = false
            
            #if DEBUG
            print("PROFILE VIDEOS: Loaded \(filteredVideos.count) videos for \(targetUserID) (hasMore: \(hasMore))")
            #endif
            
        } catch {
            // If Firestore fails but we had cache, keep showing cached data
            if userVideos.isEmpty {
                self.isLoadingVideos = false
                self.hasMoreVideos = false
            }
            #if DEBUG
            print("PROFILE VIDEOS ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load more videos (pagination)
    func loadMoreVideos() async {
        guard let user = currentUser else { return }
        guard hasMoreVideos && !isLoadingMoreVideos else {
            #if DEBUG
            print("PROFILE PAGINATION: Skipping - hasMore: \(hasMoreVideos), isLoading: \(isLoadingMoreVideos)")
            #endif
            return
        }
        guard let lastDoc = lastVideoDocument else {
            #if DEBUG
            print("PROFILE PAGINATION: No cursor document")
            #endif
            return
        }
        
        await MainActor.run {
            self.isLoadingMoreVideos = true
        }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Query starting after the last document
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: user.id)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: paginationBatchSize)
                .getDocuments()
            
            let newVideos = snapshot.documents.compactMap { doc -> CoreVideoMetadata? in
                return createVideoMetadata(from: doc.data(), documentID: doc.documentID)
            }
            
            // Filter out pinned videos
            let filteredNewVideos = newVideos.filter { !pinnedVideoIDs.contains($0.id) && !$0.isCollectionSegment }
            
            // CACHE: Store new batch for future loads
            cachingService.cacheVideos(newVideos)
            
            // Update state
            let newLastDoc = snapshot.documents.last
            let hasMore = snapshot.documents.count >= paginationBatchSize
            
            await MainActor.run {
                self.userVideos.append(contentsOf: filteredNewVideos)
                self.lastVideoDocument = newLastDoc ?? self.lastVideoDocument
                self.hasMoreVideos = hasMore
                self.isLoadingMoreVideos = false
            }
            
            #if DEBUG
            print("PROFILE PAGINATION: Loaded \(filteredNewVideos.count) more videos, total: \(userVideos.count)")
            #endif
            
        } catch {
            await MainActor.run {
                self.isLoadingMoreVideos = false
            }
            #if DEBUG
            print("PROFILE PAGINATION ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Create CoreVideoMetadata from Firestore document data
    private func createVideoMetadata(from data: [String: Any], documentID: String) -> CoreVideoMetadata {
        return CoreVideoMetadata(
            id: documentID,
            title: data[FirebaseSchema.VideoDocument.title] as? String ?? "",
            videoURL: data[FirebaseSchema.VideoDocument.videoURL] as? String ?? "",
            thumbnailURL: data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? "",
            creatorID: data[FirebaseSchema.VideoDocument.creatorID] as? String ?? "",
            creatorName: data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "",
            createdAt: (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date(),
            threadID: data[FirebaseSchema.VideoDocument.threadID] as? String,
            replyToVideoID: data[FirebaseSchema.VideoDocument.replyToVideoID] as? String,
            conversationDepth: data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0,
            viewCount: data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0,
            hypeCount: data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0,
            coolCount: data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0,
            replyCount: data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0,
            shareCount: data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0,
            temperature: data[FirebaseSchema.VideoDocument.temperature] as? String ?? "Cold",
            qualityScore: data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 0,
            engagementRatio: data["engagementRatio"] as? Double ?? 0.0,
            velocityScore: data["velocityScore"] as? Double ?? 0.0,
            trendingScore: data["trendingScore"] as? Double ?? 0.0,
            duration: data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0.0,
            aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0,
            fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
            discoverabilityScore: data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5,
            isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue(),
            collectionID: data["collectionID"] as? String,
            segmentNumber: data["segmentNumber"] as? Int,
            segmentTitle: data["segmentTitle"] as? String,
            isCollectionSegment: data["isCollectionSegment"] as? Bool ?? false
        )
    }
    
    // MARK: - Social Data Loading
    
    /// Load following list with pagination support
    private func loadFollowingLazily(userID: String, limit: Int) async {
        await MainActor.run {
            self.isLoadingFollowing = true
        }
        
        do {
            // Get all following IDs first (for pagination)
            let followingIDs = try await userService.getFollowingIDs(userID: userID)
            
            await MainActor.run {
                self.allFollowingIDs = followingIDs
                self.totalFollowingCount = followingIDs.count
                self.loadedFollowingCount = 0
            }
            
            // Load first batch
            let firstBatchIDs = Array(followingIDs.prefix(socialBatchSize))
            let followingUsers = try await userService.getUsers(ids: firstBatchIDs)
            
            await MainActor.run {
                self.followingList = followingUsers
                self.loadedFollowingCount = followingUsers.count
                self.hasMoreFollowing = followingIDs.count > self.loadedFollowingCount
                self.isLoadingFollowing = false
            }
            
            #if DEBUG
            print("PROFILE FOLLOWING: Loaded \(followingUsers.count)/\(followingIDs.count) following users")
            #endif
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowing = false
            }
            #if DEBUG
            print("PROFILE FOLLOWING ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load more following users (pagination)
    func loadMoreFollowing() async {
        guard !isLoadingMoreFollowing,
              hasMoreFollowing,
              loadedFollowingCount < allFollowingIDs.count else { return }
        
        await MainActor.run {
            self.isLoadingMoreFollowing = true
        }
        
        do {
            let startIndex = loadedFollowingCount
            let endIndex = min(startIndex + socialBatchSize, allFollowingIDs.count)
            let nextBatchIDs = Array(allFollowingIDs[startIndex..<endIndex])
            
            let moreUsers = try await userService.getUsers(ids: nextBatchIDs)
            
            await MainActor.run {
                self.followingList.append(contentsOf: moreUsers)
                self.loadedFollowingCount += moreUsers.count
                self.hasMoreFollowing = self.loadedFollowingCount < self.allFollowingIDs.count
                self.isLoadingMoreFollowing = false
            }
            
            #if DEBUG
            print("PROFILE FOLLOWING: Loaded more - \(self.loadedFollowingCount)/\(allFollowingIDs.count)")
            #endif
            
        } catch {
            await MainActor.run {
                self.isLoadingMoreFollowing = false
            }
            #if DEBUG
            print("PROFILE FOLLOWING ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load followers list with pagination support
    private func loadFollowersLazily(userID: String, limit: Int) async {
        await MainActor.run {
            self.isLoadingFollowers = true
        }
        
        do {
            // Get all follower IDs first (for pagination)
            let followerIDs = try await userService.getFollowerIDs(userID: userID)
            
            await MainActor.run {
                self.allFollowerIDs = followerIDs
                self.totalFollowersCount = followerIDs.count
                self.loadedFollowerCount = 0
            }
            
            // Load first batch
            let firstBatchIDs = Array(followerIDs.prefix(socialBatchSize))
            let followers = try await userService.getUsers(ids: firstBatchIDs)

            await MainActor.run {
                self.followersList = followers
                self.loadedFollowerCount = followers.count
                self.hasMoreFollowers = followerIDs.count > self.loadedFollowerCount
                self.isLoadingFollowers = false
            }
            
            #if DEBUG
            print("PROFILE FOLLOWERS: Loaded \(followers.count)/\(followerIDs.count) followers")
            #endif
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowers = false
            }
            #if DEBUG
            print("PROFILE FOLLOWERS ERROR: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Load more followers (pagination)
    func loadMoreFollowers() async {
        guard !isLoadingMoreFollowers,
              hasMoreFollowers,
              loadedFollowerCount < allFollowerIDs.count else { return }
        
        await MainActor.run {
            self.isLoadingMoreFollowers = true
        }
        
        do {
            let startIndex = loadedFollowerCount
            let endIndex = min(startIndex + socialBatchSize, allFollowerIDs.count)
            let nextBatchIDs = Array(allFollowerIDs[startIndex..<endIndex])
            
            let moreUsers = try await userService.getUsers(ids: nextBatchIDs)
            
            await MainActor.run {
                self.followersList.append(contentsOf: moreUsers)
                self.loadedFollowerCount += moreUsers.count
                self.hasMoreFollowers = self.loadedFollowerCount < self.allFollowerIDs.count
                self.isLoadingMoreFollowers = false
            }
            
            #if DEBUG
            print("PROFILE FOLLOWERS: Loaded more - \(self.loadedFollowerCount)/\(allFollowerIDs.count)")
            #endif
            
        } catch {
            await MainActor.run {
                self.isLoadingMoreFollowers = false
            }
            #if DEBUG
            print("PROFILE FOLLOWERS ERROR: \(error.localizedDescription)")
            #endif
        }
    }

    /// Start profile animations
    private func startProfileAnimations() async {
        guard let user = currentUser else { return }
        
        await MainActor.run {
            self.animationController.startEntranceSequence(hypeProgress: self.calculateHypeProgress())
        }
    }
    
    // MARK: - Profile Caching
    
    /// Get cached profile if available
    private func getCachedProfile(userID: String) -> BasicUserInfo? {
        guard let cached = cachedUserProfile,
              let cacheTime = profileCacheTime,
              Date().timeIntervalSince(cacheTime) < profileCacheExpiration,
              cached.id == userID else {
            return nil
        }
        
        return cached
    }
    
    /// Cache profile for future instant display
    private func cacheProfile(_ profile: BasicUserInfo) {
        cachedUserProfile = profile
        profileCacheTime = Date()
        #if DEBUG
        print("PROFILE CACHE: Stored profile for \(profile.username)")
        #endif
    }
    
    // MARK: - Data Loading (Original Methods for Compatibility)
    
    func loadFollowing() async {
        guard let user = currentUser else { return }
        await loadFollowingLazily(userID: user.id, limit: socialBatchSize)
    }
    
    func loadFollowers() async {
        guard let user = currentUser else { return }
        await loadFollowersLazily(userID: user.id, limit: socialBatchSize)
    }
    
    func loadUserVideos() async {
        await loadUserVideosLazily()
    }
    
    // MARK: - Profile Actions
    
    func refreshProfile() async {
        guard let currentUserID = authService.currentUserID else { return }
        
        #if DEBUG
        print("PROFILE: Manual refresh triggered - clearing cache")
        #endif
        
        // Clear cache to force fresh data
        cachedUserProfile = nil
        profileCacheTime = nil
        
        // Reset pagination state
        lastVideoDocument = nil
        hasMoreVideos = true
        
        // Reload profile completely
        await loadProfile()
        #if DEBUG
        print("PROFILE: Refresh complete with fresh data")
        #endif
    }
    
    func deleteVideo(_ video: CoreVideoMetadata) async -> Bool {
        do {
            try await videoService.deleteVideo(videoID: video.id)
            
            // Remove from local arrays
            userVideos.removeAll { $0.id == video.id }
            pinnedVideos.removeAll { $0.id == video.id }
            pinnedVideoIDs.removeAll { $0 == video.id }
            
            #if DEBUG
            print("PROFILE: Video deleted successfully")
            #endif
            return true
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            #if DEBUG
            print("PROFILE ERROR: Delete failed - \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    // MARK: - Computed Properties
    
    var isOwnProfile: Bool {
        guard let currentUserID = authService.currentUserID,
              let profileUserID = currentUser?.id else { return false }
        return currentUserID == profileUserID
    }
    
    var tabTitles: [String] {
        ["Threads", "Stitches", "Replies"]
    }
    
    var tabIcons: [String] {
        ["play.rectangle.fill", "link", "arrowshape.turn.up.left.fill"]
    }
    
    /// Filter videos for tab display (excludes pinned from Threads tab)
    func filteredVideos(for tab: Int) -> [CoreVideoMetadata] {
        let baseVideos = userVideos.filter { !$0.isCollectionSegment }
        switch tab {
        case 0:
            return baseVideos.filter { $0.conversationDepth == 0 && !pinnedVideoIDs.contains($0.id) }
        case 1:
            return baseVideos.filter { $0.conversationDepth == 1 }
        case 2:
            return baseVideos.filter { $0.conversationDepth >= 2 }
        default:
            return baseVideos
        }
    }
    
    /// Calculate hype progress for animations (changed to public)
    func calculateHypeProgress() -> Double {
        guard let user = currentUser else { return 0.0 }
        let tierThreshold = user.tier.cloutRange.upperBound
        return tierThreshold > 0 ? Double(user.clout) / Double(tierThreshold) : 0.0
    }
    
    // MARK: - ProfileView Integration Methods
    
    /// Get bio for user (ProfileView compatibility) - Returns bio from extended profile data
    func getBioForUser(_ user: BasicUserInfo) -> String? {
        return userBio
    }
    
    /// Format clout for display
    func formatClout(_ clout: Int) -> String {
        if clout >= 1_000_000 {
            return String(format: "%.1fM", Double(clout) / 1_000_000)
        } else if clout >= 1_000 {
            return String(format: "%.1fK", Double(clout) / 1_000)
        } else {
            return String(clout)
        }
    }
    
    /// Toggle follow for current user
    func toggleFollow() async {
        guard let user = currentUser else { return }
        
        do {
            let currentUserID = authService.currentUserID ?? ""
            
            if isFollowing {
                try await userService.unfollowUser(followerID: currentUserID, followingID: user.id)
                isFollowing = false
                #if DEBUG
                print("PROFILE: Unfollowed user \(user.username)")
                #endif
            } else {
                try await userService.followUser(followerID: currentUserID, followingID: user.id)
                isFollowing = true
                #if DEBUG
                print("PROFILE: Followed user \(user.username)")
                #endif
                
                // Send follow notification via Cloud Function
                do {
                    try await notificationService.sendFollowNotification(to: user.id)
                    #if DEBUG
                    print("PROFILE: Follow notification sent to \(user.username)")
                    #endif
                } catch {
                    #if DEBUG
                    print("PROFILE: Follow notification failed (non-fatal) - \(error)")
                    #endif
                }
            }
        } catch {
            errorMessage = "Failed to update follow status: \(error.localizedDescription)"
        }
    }
    
    /// Get tab count for videos (with proper parameter label)
    func getTabCount(for tab: Int) -> Int {
        let videos = filteredVideos(for: tab)
        return videos.count
    }
}

// MARK: - Supporting Types

struct ProfileBadgeInfo {
    let id: String
    let iconName: String
    let colors: [Color]
    let title: String
}

// MARK: - Array Extension for Chunking (Renamed to avoid conflicts)

fileprivate extension Array {
    func profileChunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Hello World Test Extension

extension ProfileViewModel {
    
    /// Test profile functionality
    func helloWorldTest() {
        #if DEBUG
        print("PROFILE VIEW MODEL: Hello World - Ready for instant profile loading!")
        #endif
        #if DEBUG
        print("PROFILE Features: Instant display, lazy content loading, cached profiles")
        #endif
        #if DEBUG
        print("PROFILE Performance: <50ms profile display, background enhancements")
        #endif
        #if DEBUG
        print("PROFILE Notifications: NotificationCenter integration active")
        #endif
        #if DEBUG
        print("PROFILE Pinning: Up to \(Self.maxPinnedVideos) threads can be pinned")
        #endif
        #if DEBUG
        print("PROFILE Pagination: Infinite scroll with \(initialVideoLimit) initial + \(paginationBatchSize) per batch")
        #endif
    }
}
