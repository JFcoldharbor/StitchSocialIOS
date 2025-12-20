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
    
    // MARK: - Caching for Performance
    private var cachedUserProfile: BasicUserInfo?
    private var profileCacheTime: Date?
    private let profileCacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService) {
        self.authService = authService
        self.userService = userService
        self.videoService = videoService
        self.animationController = ProfileAnimationController()
        
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
        
        print("PROFILE VIEWMODEL: NotificationCenter observers setup complete")
    }
    
    /// Handle profile refresh notifications from EditProfileView
    private func handleProfileRefreshNotification(_ notification: Notification) async {
        print("PROFILE VIEWMODEL: Received RefreshProfile notification - triggering refresh")
        
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
                print("PROFILE VIEWMODEL: Profile refresh confirmed for user \(currentUserID)")
            } else {
                print("PROFILE VIEWMODEL: Profile refresh notification for different user, ignoring")
            }
        }
    }
    
    /// Cleanup NotificationCenter observers
    private nonisolated func cleanupNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
        print("PROFILE VIEWMODEL: NotificationCenter observers cleaned up")
    }
    
    // MARK: - Deinitialization
    
    deinit {
        cleanupNotificationObservers()
        print("PROFILE VIEWMODEL: Deinitializing with proper cleanup")
    }
    
    // MARK: - INSTANT LOADING IMPLEMENTATION
    
    /// Load profile instantly with placeholder, then enhance with real data
    func loadProfile() async {
        guard let currentUserID = authService.currentUserID else {
            errorMessage = "Authentication required"
            return
        }
        
        print("PROFILE: Starting instant load for user \(currentUserID)")
        
        // STEP 1: Check cache for instant display
        if let cached = getCachedProfile(userID: currentUserID) {
            currentUser = cached
            isShowingPlaceholder = false
            print("PROFILE CACHE HIT: Instant display")
            
            // Load enhancements in background
            Task {
                await loadEnhancementsInBackground(userID: currentUserID)
            }
            return
        }
        
        // STEP 2: Show placeholder profile immediately
        showPlaceholderProfile(userID: currentUserID)
        
        // STEP 3: Load real profile in background
        Task {
            await loadRealProfileInBackground(userID: currentUserID)
        }
        
        print("PROFILE: UI ready with placeholder")
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
        print("PROFILE PLACEHOLDER: Showing placeholder")
    }
    
    /// Load real profile data in background
    private func loadRealProfileInBackground(userID: String) async {
        do {
            print("PROFILE BACKGROUND: Loading real profile data...")
            
            if let userProfile = try await userService.getUser(id: userID) {
                await MainActor.run {
                    self.currentUser = userProfile
                    self.isShowingPlaceholder = false
                    print("PROFILE BACKGROUND: UI updated with fresh profile data - \(userProfile.displayName)")
                }
                
                // Cache for future instant loads
                cacheProfile(userProfile)
                
                // Load extended profile data (bio, privacy settings)
                await loadExtendedProfileData(userID: userID)
                
                // Load additional content in background
                Task {
                    await loadEnhancementsInBackground(userID: userID)
                }
                
                print("PROFILE BACKGROUND: Real profile loaded and cached")
            } else {
                await MainActor.run {
                    self.errorMessage = "Profile not found"
                    self.isShowingPlaceholder = false
                }
                print("PROFILE BACKGROUND: Profile not found in database")
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isShowingPlaceholder = false
            }
            print("PROFILE ERROR: Failed to load profile - \(error.localizedDescription)")
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
                print("PROFILE EXTENDED: Loaded bio and privacy settings")
            }
        } catch {
            print("PROFILE EXTENDED ERROR: Failed to load extended data - \(error.localizedDescription)")
        }
    }
    
    /// Load profile enhancements in background (videos, social data)
    private func loadEnhancementsInBackground(userID: String) async {
        print("PROFILE ENHANCEMENTS: Loading additional data...")
        
        // Load all enhancements concurrently
        await withTaskGroup(of: Void.self) { group in
            
            // Load pinned videos first (NEW)
            group.addTask {
                await self.loadPinnedVideos(userID: userID)
            }
            
            // Load user videos with pagination
            group.addTask {
                await self.loadUserVideosLazily()
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
        
        print("PROFILE ENHANCEMENTS: Background loading complete")
    }
    
    // MARK: - Pinned Videos Methods (NEW)
    
    /// Load pinned videos for a user
    func loadPinnedVideos(userID: String? = nil) async {
        let targetUserID = userID ?? currentUser?.id
        guard let targetUserID = targetUserID else { return }
        
        print("📌 PINNED: Loading pinned videos for user \(targetUserID)")
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Get user document to read pinnedVideoIDs
            let userDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(targetUserID)
                .getDocument()
            
            guard let userData = userDoc.data() else {
                print("📌 PINNED: No user data found")
                return
            }
            
            // Read pinnedVideoIDs array
            let pinnedIDs = userData[FirebaseSchema.UserDocument.pinnedVideoIDs] as? [String] ?? []
            
            await MainActor.run {
                self.pinnedVideoIDs = pinnedIDs
            }
            
            guard !pinnedIDs.isEmpty else {
                print("📌 PINNED: No pinned videos")
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
            
            print("📌 PINNED: Loaded \(orderedVideos.count) pinned videos")
            
        } catch {
            print("📌 PINNED ERROR: \(error.localizedDescription)")
        }
    }
    
    /// Pin a video to profile (threads only, max 3)
    func pinVideo(_ video: CoreVideoMetadata) async -> Bool {
        guard let userID = currentUser?.id else {
            print("📌 PIN ERROR: No current user")
            return false
        }
        
        // Validation: threads only
        guard video.conversationDepth == 0 else {
            print("📌 PIN ERROR: Only threads can be pinned (depth must be 0)")
            errorMessage = "Only threads can be pinned to your profile"
            return false
        }
        
        // Validation: max 3 pinned
        guard pinnedVideoIDs.count < Self.maxPinnedVideos else {
            print("📌 PIN ERROR: Maximum \(Self.maxPinnedVideos) pinned videos allowed")
            errorMessage = "You can only pin up to \(Self.maxPinnedVideos) videos"
            return false
        }
        
        // Validation: not already pinned
        guard !pinnedVideoIDs.contains(video.id) else {
            print("📌 PIN ERROR: Video already pinned")
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
            
            print("📌 PIN SUCCESS: Pinned video \(video.id)")
            return true
            
        } catch {
            print("📌 PIN ERROR: \(error.localizedDescription)")
            errorMessage = "Failed to pin video: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Unpin a video from profile
    func unpinVideo(_ video: CoreVideoMetadata) async -> Bool {
        guard let userID = currentUser?.id else {
            print("📌 UNPIN ERROR: No current user")
            return false
        }
        
        guard pinnedVideoIDs.contains(video.id) else {
            print("📌 UNPIN ERROR: Video not pinned")
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
            
            print("📌 UNPIN SUCCESS: Unpinned video \(video.id)")
            return true
            
        } catch {
            print("📌 UNPIN ERROR: \(error.localizedDescription)")
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
    private func loadUserVideosLazily() async {
        guard let user = currentUser else { return }
        
        await MainActor.run {
            self.isLoadingVideos = true
            self.lastVideoDocument = nil
            self.hasMoreVideos = true
        }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Load user videos directly from Firestore with initial limit
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: user.id)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: initialVideoLimit)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { doc -> CoreVideoMetadata? in
                return createVideoMetadata(from: doc.data(), documentID: doc.documentID)
            }
            
            // Filter out pinned videos from the main list
            let filteredVideos = videos.filter { !pinnedVideoIDs.contains($0.id) }
            
            // Store last document for pagination
            let lastDoc = snapshot.documents.last
            let hasMore = snapshot.documents.count >= initialVideoLimit
            
            await MainActor.run {
                self.userVideos = filteredVideos
                self.lastVideoDocument = lastDoc
                self.hasMoreVideos = hasMore
                self.isLoadingVideos = false
            }
            
            print("PROFILE VIDEOS: Loaded \(filteredVideos.count) videos (hasMore: \(hasMore))")
            
        } catch {
            await MainActor.run {
                self.isLoadingVideos = false
                self.hasMoreVideos = false
            }
            print("PROFILE VIDEOS ERROR: \(error.localizedDescription)")
        }
    }
    
    /// Load more videos (pagination)
    func loadMoreVideos() async {
        guard let user = currentUser else { return }
        guard hasMoreVideos && !isLoadingMoreVideos else {
            print("PROFILE PAGINATION: Skipping - hasMore: \(hasMoreVideos), isLoading: \(isLoadingMoreVideos)")
            return
        }
        guard let lastDoc = lastVideoDocument else {
            print("PROFILE PAGINATION: No cursor document")
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
            let filteredNewVideos = newVideos.filter { !pinnedVideoIDs.contains($0.id) }
            
            // Update state
            let newLastDoc = snapshot.documents.last
            let hasMore = snapshot.documents.count >= paginationBatchSize
            
            await MainActor.run {
                self.userVideos.append(contentsOf: filteredNewVideos)
                self.lastVideoDocument = newLastDoc ?? self.lastVideoDocument
                self.hasMoreVideos = hasMore
                self.isLoadingMoreVideos = false
            }
            
            print("PROFILE PAGINATION: Loaded \(filteredNewVideos.count) more videos, total: \(userVideos.count)")
            
        } catch {
            await MainActor.run {
                self.isLoadingMoreVideos = false
            }
            print("PROFILE PAGINATION ERROR: \(error.localizedDescription)")
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
            lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
        )
    }
    
    // MARK: - Social Data Loading
    
    /// Load following list with reduced limit
    private func loadFollowingLazily(userID: String, limit: Int) async {
        await MainActor.run {
            self.isLoadingFollowing = true
        }
        
        do {
            // Get following IDs and convert to BasicUserInfo objects
            let followingIDs = try await userService.getFollowingIDs(userID: userID)
            let limitedFollowingIDs = Array(followingIDs.prefix(limit))
            let followingUsers = try await userService.getUsers(ids: limitedFollowingIDs)
            
            await MainActor.run {
                self.followingList = followingUsers
                self.isLoadingFollowing = false
            }
            
            print("PROFILE FOLLOWING: Loaded \(followingUsers.count) following users")
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowing = false
            }
            print("PROFILE FOLLOWING ERROR: \(error.localizedDescription)")
        }
    }
    
    /// Load followers list with reduced limit
    private func loadFollowersLazily(userID: String, limit: Int) async {
        await MainActor.run {
            self.isLoadingFollowers = true
        }
        
        do {
            // Get follower IDs and convert to BasicUserInfo objects
            let followerIDs = try await userService.getFollowerIDs(userID: userID)
            let limitedFollowerIDs = Array(followerIDs.prefix(limit))
            let followers = try await userService.getUsers(ids: limitedFollowerIDs)

            await MainActor.run {
                self.followersList = followers
                self.isLoadingFollowers = false
            }
            
            print("PROFILE FOLLOWERS: Loaded \(followers.count) followers")
            
        } catch {
            await MainActor.run {
                self.isLoadingFollowers = false
            }
            print("PROFILE FOLLOWERS ERROR: \(error.localizedDescription)")
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
        print("PROFILE CACHE: Stored profile for \(profile.username)")
    }
    
    // MARK: - Data Loading (Original Methods for Compatibility)
    
    func loadFollowing() async {
        guard let user = currentUser else { return }
        await loadFollowingLazily(userID: user.id, limit: 50)
    }
    
    func loadFollowers() async {
        guard let user = currentUser else { return }
        await loadFollowersLazily(userID: user.id, limit: 50)
    }
    
    func loadUserVideos() async {
        await loadUserVideosLazily()
    }
    
    // MARK: - Profile Actions
    
    func refreshProfile() async {
        guard let currentUserID = authService.currentUserID else { return }
        
        print("PROFILE: Manual refresh triggered - clearing cache")
        
        // Clear cache to force fresh data
        cachedUserProfile = nil
        profileCacheTime = nil
        
        // Reset pagination state
        lastVideoDocument = nil
        hasMoreVideos = true
        
        // Reload profile completely
        await loadProfile()
        print("PROFILE: Refresh complete with fresh data")
    }
    
    func deleteVideo(_ video: CoreVideoMetadata) async -> Bool {
        do {
            try await videoService.deleteVideo(videoID: video.id)
            
            // Remove from local arrays
            userVideos.removeAll { $0.id == video.id }
            pinnedVideos.removeAll { $0.id == video.id }
            pinnedVideoIDs.removeAll { $0 == video.id }
            
            print("PROFILE: Video deleted successfully")
            return true
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            print("PROFILE ERROR: Delete failed - \(error.localizedDescription)")
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
        switch tab {
        case 0:
            // Threads tab: exclude pinned videos
            return userVideos.filter { $0.conversationDepth == 0 && !pinnedVideoIDs.contains($0.id) }
        case 1:
            return userVideos.filter { $0.conversationDepth == 1 }
        case 2:
            return userVideos.filter { $0.conversationDepth >= 2 }
        default:
            return userVideos
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
                print("PROFILE: Unfollowed user \(user.username)")
            } else {
                try await userService.followUser(followerID: currentUserID, followingID: user.id)
                isFollowing = true
                print("PROFILE: Followed user \(user.username)")
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
        print("PROFILE VIEW MODEL: Hello World - Ready for instant profile loading!")
        print("PROFILE Features: Instant display, lazy content loading, cached profiles")
        print("PROFILE Performance: <50ms profile display, background enhancements")
        print("PROFILE Notifications: NotificationCenter integration active")
        print("PROFILE Pinning: Up to \(Self.maxPinnedVideos) threads can be pinned")
        print("PROFILE Pagination: Infinite scroll with \(initialVideoLimit) initial + \(paginationBatchSize) per batch")
    }
}
