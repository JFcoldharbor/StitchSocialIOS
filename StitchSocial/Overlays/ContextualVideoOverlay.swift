//
//  ContextualVideoOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Universal Contextual Video Overlay with Viewer Tracking
//  Dependencies: EngagementService, UserService, AuthService, FollowManager, VideoService
//  Features: Static overlay, special user permissions, context-aware profile navigation, viewer tracking
//  UPDATED: Added eye icon button to view who watched the video
//

import SwiftUI

/// Universal overlay that adapts to different viewing contexts with viewer tracking
struct ContextualVideoOverlay: View {
    
    // MARK: - Properties
    
    let video: CoreVideoMetadata
    let context: OverlayContext
    let currentUserID: String?
    let threadVideo: CoreVideoMetadata?
    let isVisible: Bool
    let onAction: ((ContextualOverlayAction) -> Void)?
    
    // MARK: - State
    
    @StateObject private var userService = UserService()
    @StateObject private var authService = AuthService()
    @StateObject private var followManager = FollowManager()
    @StateObject private var engagementManager = EngagementManager(
        videoService: VideoService(),
        userService: UserService()
    )
    @StateObject private var floatingIconManager = FloatingIconManager()
    @StateObject private var videoService = VideoService()
    
    // MARK: - Cached User Data (Static Cache Shared Across All Overlays)
    
    private static var userDataCache: [String: CachedUserData] = [:]
    private static var cacheTimestamps: [String: Date] = [:]
    private static let cacheExpiration: TimeInterval = 300 // 5 minutes
    private static let batchSize = 10
    private static var pendingBatchRequests: Set<String> = []
    private static var batchTimer: Timer?
    
    private struct CachedUserData {
        let displayName: String
        let profileImageURL: String?
        let tier: UserTier?
        let cachedAt: Date
    }
    
    // MARK: - UI State
    
    @State private var showingProfileFullscreen = false
    @State private var showingThreadView = false
    @State private var showingViewers = false  // NEW: Viewers sheet
    @State private var selectedUserID: String? {
        didSet {
            print("🔍 STATE: selectedUserID changed from \(oldValue ?? "nil") to \(selectedUserID ?? "nil")")
        }
    }
    
    // Engagement data
    @State private var videoEngagement: ContextualVideoEngagement?
    @State private var showingHypeParticles = false
    @State private var showingCoolParticles = false
    
    // Real user data lookup - Now uses cache
    @State private var isLoadingUserData = false
    @State private var videoDescription: String?
    
    // Recording state
    @State private var showingStitchRecording = false
    
    // MARK: - Convenience Initializers for Backwards Compatibility
    
    init(
        video: CoreVideoMetadata,
        context: OverlayContext,
        currentUserID: String?,
        threadVideo: CoreVideoMetadata? = nil,
        isVisible: Bool = true,
        onAction: ((ContextualOverlayAction) -> Void)? = nil
    ) {
        self.video = video
        self.context = context
        self.currentUserID = currentUserID
        self.threadVideo = threadVideo
        self.isVisible = isVisible
        self.onAction = onAction
    }
    
    // MARK: - Minimal Discovery Overlay
    
    private var minimalDiscoveryOverlay: some View {
        VStack {
            // Top: Creator name only
            HStack {
                Button {
                    selectedUserID = video.creatorID
                    
                    // Comprehensive video kill - hit all possible notification patterns
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingProfileFullscreen = true
                        onAction?(.profile(video.creatorID))
                    }
                } label: {
                    HStack(spacing: 4) {
                        // Small temperature indicator
                        Circle()
                            .fill(temperatureColor)
                            .frame(width: 4, height: 4)
                        
                        Text(displayCreatorName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.4))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Bottom: Video title only (no engagement buttons, no metadata)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if !video.title.isEmpty {
                        Text(video.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.8), radius: 1, x: 0, y: 1)
                    }
                }
                
                Spacer()
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Full Contextual Overlay
    
    private func fullContextualOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Top Section - ALWAYS VISIBLE
            VStack {
                topSection
                Spacer()
            }
            .opacity(1.0)
            
            // Bottom Section - ALWAYS VISIBLE (adjusted padding)
            VStack {
                Spacer()
                bottomSection
                    .padding(.bottom, geometry.size.height * 0.08)
            }
            .opacity(1.0)
            
            // Right Side - ALWAYS VISIBLE when content exists
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    
                    // Right side navigation indicator
                    if video.conversationDepth <= 1 && video.replyCount > 0 {
                        Button {
                            showingThreadView = true
                            onAction?(.thread(video.threadID ?? video.id))
                        } label: {
                            Circle()
                                .fill(Color.cyan.opacity(0.8))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Text("\(video.replyCount)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
            }
            .padding(.trailing, 12)
            .opacity(1.0)
            
            // Center Effects - ALWAYS VISIBLE when active
            centerEffects
                .opacity(1.0)
        }
    }
    
    // MARK: - Computed Properties
    
    private var threadCreator: CoreVideoMetadata {
        threadVideo ?? video
    }
    
    private var isUserVideo: Bool {
        video.creatorID == currentUserID
    }
    
    private var canReply: Bool {
        video.conversationDepth <= 1 && !isUserVideo
    }
    
    // MARK: - Context-Aware Display Logic
    
    private var shouldShowMinimalDisplay: Bool {
        return context == .discovery
    }
    
    private var shouldShowFullDisplay: Bool {
        return context != .discovery
    }
    
    // MARK: - Special user detection for enhanced permissions
    private var currentUserIsSpecial: Bool {
        guard let currentUserID = currentUserID,
              let userEmail = authService.currentUserEmail else { return false }
        let user = authService.currentUser
        return user?.tier == .founder || user?.tier == .coFounder ||
               SpecialUsersConfig.isSpecialUser(userEmail)
    }
    
    private var currentUserIsFounder: Bool {
        guard let user = authService.currentUser else { return false }
        return user.tier == .founder || user.tier == .coFounder
    }
    
    // MARK: - Cached User Data Management
    
    /// Get cached user data with automatic batching for missing users
    private static func getCachedUserData(userID: String) -> CachedUserData? {
        // Check if we have cached data that's still valid
        if let cached = userDataCache[userID],
           let timestamp = cacheTimestamps[userID],
           Date().timeIntervalSince(timestamp) < cacheExpiration {
            return cached
        }
        
        // Missing or expired - add to pending batch
        pendingBatchRequests.insert(userID)
        
        // If batch is full or timer expired, trigger batch load
        if pendingBatchRequests.count >= batchSize {
            scheduleBatchLoad()
        } else if batchTimer == nil {
            // Start timer for partial batches
            batchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                scheduleBatchLoad()
            }
        }
        
        return nil
    }
    
    /// Schedule batch loading of user data
    private static func scheduleBatchLoad() {
        guard !pendingBatchRequests.isEmpty else { return }
        
        let userIDs = Array(pendingBatchRequests)
        pendingBatchRequests.removeAll()
        batchTimer?.invalidate()
        batchTimer = nil
        
        Task {
            await loadUserDataBatch(userIDs: userIDs)
        }
    }
    
    /// Load user data in batch and update cache
    private static func loadUserDataBatch(userIDs: [String]) async {
        let userService = UserService()
        
        for userID in userIDs {
            do {
                if let user = try await userService.getUser(id: userID) {
                    let cached = CachedUserData(
                        displayName: user.displayName,
                        profileImageURL: user.profileImageURL,
                        tier: user.tier,
                        cachedAt: Date()
                    )
                    
                    await MainActor.run {
                        userDataCache[userID] = cached
                        cacheTimestamps[userID] = Date()
                    }
                }
            } catch {
                print("Failed to load user data for \(userID): \(error)")
            }
        }
        
        // Notify UI to refresh
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("UserDataCacheUpdated"), object: nil)
        }
    }
    
    /// Clear expired cache entries
    private static func clearExpiredCache() {
        let now = Date()
        for (userID, timestamp) in cacheTimestamps {
            if now.timeIntervalSince(timestamp) > cacheExpiration {
                userDataCache.removeValue(forKey: userID)
                cacheTimestamps.removeValue(forKey: userID)
            }
        }
    }
    
    /// Get creator display name with cached lookup
    private var displayCreatorName: String {
        if let cached = Self.getCachedUserData(userID: video.creatorID) {
            return cached.displayName
        }
        return "Loading..."
    }
    
    /// Get thread creator display name with cached lookup
    private var displayThreadCreatorName: String {
        if let threadVideo = threadVideo,
           let cached = Self.getCachedUserData(userID: threadVideo.creatorID) {
            return cached.displayName
        }
        return displayCreatorName
    }
    
    /// Get creator profile image URL with cached lookup
    private var displayCreatorProfileImageURL: String? {
        if let cached = Self.getCachedUserData(userID: video.creatorID) {
            return cached.profileImageURL
        }
        return nil
    }
    
    /// Get thread creator profile image URL with cached lookup
    private var displayThreadCreatorProfileImageURL: String? {
        if let threadVideo = threadVideo,
           let cached = Self.getCachedUserData(userID: threadVideo.creatorID) {
            return cached.profileImageURL
        }
        return nil
    }
    
    private var temperatureColor: Color {
        switch video.temperature.lowercased() {
        case "hot", "blazing": return .red
        case "warm": return .orange
        case "cool": return .blue
        case "cold", "frozen": return .cyan
        default: return .gray
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if shouldShowMinimalDisplay {
                    // MINIMAL DISCOVERY OVERLAY
                    minimalDiscoveryOverlay
                } else {
                    // FULL OVERLAY FOR OTHER CONTEXTS
                    fullContextualOverlay(geometry: geometry)
                }
                
                // Floating Icons Overlay - render on top of everything
                ForEach(floatingIconManager.activeIcons, id: \.id) { icon in
                    icon
                }
            }
        }
        .onAppear {
            setupOverlay()
            setupNotificationObservers()
            
            // Clear expired cache periodically
            Self.clearExpiredCache()
        }
        .onDisappear {
            removeNotificationObservers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserDataCacheUpdated"))) { _ in
            // Force UI refresh when cache updates - trigger state change
            isLoadingUserData.toggle()
            isLoadingUserData.toggle()
        }
        .fullScreenCover(isPresented: $showingProfileFullscreen) {
            // Use selectedUserID if available, otherwise fallback to video creator
            let userIDToShow = selectedUserID ?? video.creatorID
            
            CreatorProfileView(userID: userIDToShow)
                .onAppear {
                    print("📱 FULLSCREEN: CreatorProfileView appeared for userID: \(userIDToShow)")
                    // Comprehensive background activity stopping
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("FullscreenProfileOpened"), object: nil)
                }
                .onDisappear {
                    print("📱 FULLSCREEN: CreatorProfileView disappeared")
                    // Reset state when profile closes
                    selectedUserID = nil
                    // Resume video activity when profile closes
                    NotificationCenter.default.post(name: NSNotification.Name("FullscreenProfileClosed"), object: nil)
                }
        }
        .fullScreenCover(isPresented: $showingThreadView) {
            ThreadView(
                threadID: video.threadID ?? video.id,
                videoService: VideoService(),
                userService: userService
            )
        }
        .sheet(isPresented: $showingViewers) {
            WhoViewedSheet(
                videoID: video.id,
                onDismiss: {
                    showingViewers = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingStitchRecording) {
            RecordingView(
                recordingContext: getStitchRecordingContext(),
                onVideoCreated: { videoMetadata in
                    showingStitchRecording = false
                    
                    // Kill videos again after recording completion
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
                    
                    // Refresh engagement data after stitch creation
                    Task { await loadVideoEngagement() }
                },
                onCancel: {
                    showingStitchRecording = false
                    
                    // Kill videos again after recording cancellation
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
                }
            )
            .onAppear {
                // Ensure videos stay killed when recording view appears
                NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
            }
            .onDisappear {
                // Kill videos again when recording view disappears
                NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
            }
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        HStack {
            // Creator Pills
            VStack(alignment: .leading, spacing: 8) {
                // Video creator pill
                creatorPill(
                    creator: video,
                    isThread: false,
                    colors: temperatureColor == .red ?
                        [.red, .orange] : temperatureColor == .blue ?
                        [.blue, .cyan] : temperatureColor == .orange ?
                        [.orange, .yellow] : temperatureColor == .cyan ?
                        [.cyan, .blue] : [.gray, .white]
                )
                
                // Thread creator pill (only when thread exists)
                if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
                    creatorPill(
                        creator: threadVideo,
                        isThread: true,
                        colors: [.purple, .pink]
                    )
                }
            }
            
            Spacer()
            
            // Top-right action buttons
            VStack(spacing: 8) {
                // Special user actions
                if currentUserIsSpecial || currentUserIsFounder {
                    moreOptionsButton
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
    }
    
    // MARK: - NEW: Viewers Button
    
    private var viewersButton: some View {
        Button {
            print("👁️ VIEWERS: Button tapped")
            print("👁️ VIEWERS: showingViewers = \(showingViewers)")
            print("👁️ VIEWERS: videoID = \(video.id)")
            showingViewers = true
            print("👁️ VIEWERS: showingViewers set to true")
            onAction?(.viewers)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 36, height: 36)
                
                // Eye icon with badge
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    // View count badge
                    if let engagement = videoEngagement, engagement.viewCount > 0 {
                        Text("\(formatCountCompact(engagement.viewCount))")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.purple)
                            )
                            .offset(x: 8, y: -8)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            print("👁️ VIEWERS BUTTON: Appeared")
            print("👁️ VIEWERS BUTTON: isUserVideo = \(isUserVideo)")
            print("👁️ VIEWERS BUTTON: video.creatorID = \(video.creatorID)")
            print("👁️ VIEWERS BUTTON: currentUserID = \(currentUserID ?? "nil")")
        }
    }
    
    // MARK: - Creator Pill - Tappable with proper profile navigation
    
    private func creatorPill(creator: CoreVideoMetadata, isThread: Bool, colors: [Color]) -> some View {
        Button {
            print("🔍 CREATOR PILL: Button tapped for userID: \(creator.creatorID)")
            
            // Comprehensive video kill - hit all possible notification patterns
            NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("FullscreenModeActivated"), object: nil)
            NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterBackground"), object: nil)
            print("🛑 CREATOR PILL: Posted comprehensive video kill notifications")
            
            // Set selectedUserID and trigger fullscreen
            selectedUserID = creator.creatorID
            print("🔍 CREATOR PILL: Set selectedUserID to \(selectedUserID ?? "nil")")
            
            // Immediate fullscreen trigger to change app state
            showingProfileFullscreen = true
            onAction?(.profile(creator.creatorID))
        } label: {
            HStack(spacing: 8) {
                // Profile Image
                AsyncImage(url: URL(string: isThread ? displayThreadCreatorProfileImageURL ?? "" : displayCreatorProfileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: isThread ? 28 : 24, height: isThread ? 28 : 24)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                )
                
                // Creator Name and Context
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(isThread ? displayThreadCreatorName : displayCreatorName)
                            .font(.system(size: isThread ? 13 : 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if isThread {
                            Text("thread creator")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, isThread ? 12 : 8)
            .padding(.vertical, isThread ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    // MARK: - Follow Button
    
    private var followButton: some View {
        Button {
            Task {
                await handleFollowToggle()
            }
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isFollowing ? .purple : .clear)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .fill(Color.black.opacity(0.3))
                )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var isFollowing: Bool {
        followManager.isFollowing(video.creatorID)
    }
    
    private func handleFollowToggle() async {
        guard let currentUserID = currentUserID else { return }
        await followManager.toggleFollow(for: video.creatorID)
        onAction?(.followToggle)
    }
    
    private var moreOptionsButton: some View {
        Button {
            onAction?(.more)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    // MARK: - Metadata Row (UPDATED: Views tappable)
    
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let engagement = videoEngagement {
                // LIVE DATA - Views count (TAPPABLE - opens WhoViewedSheet - CREATOR ONLY)
                if isUserVideo {
                    Button {
                        print("👁️ VIEWS: Tapped views button")
                        showingViewers = true
                        onAction?(.viewers)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("\(formatCount(engagement.viewCount)) views")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        print("👁️ VIEWS BUTTON: Appeared (creator-only)")
                        print("👁️ VIEWS BUTTON: isUserVideo = \(isUserVideo)")
                    }
                } else {
                    // Non-creator view (not tappable)
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("\(formatCount(engagement.viewCount)) views")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // Separator
                Text("•")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                // LIVE DATA - Stitch count
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.7))
                    
                    Text("\(formatCount(engagement.replyCount)) stitches")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.9))
                }
                
                // Separator
                Text("•")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                // LIVE DATA - Total engagement
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                    
                    Text("\(formatCount(engagement.totalEngagements))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                }
            } else {
                // Loading state
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Loading...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
    
    // MARK: - NEW: Tagged Users Row
    
    private var taggedUsersRow: some View {
        HStack(spacing: 8) {
            // "Tagged:" label
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple.opacity(0.8))
                
                Text("Tagged:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Scrollable tagged users
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(video.taggedUserIDs.prefix(5), id: \.self) { userID in
                        taggedUserAvatar(userID: userID)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
    }
    
    // MARK: - Tagged User Avatar
    
    private func taggedUserAvatar(userID: String) -> some View {
        Button {
            // Navigate to tagged user profile
            selectedUserID = userID
            
            // Kill videos
            NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingProfileFullscreen = true
                onAction?(.profile(userID))
            }
        } label: {
            HStack(spacing: 4) {
                // Avatar
                AsyncImage(url: URL(string: Self.getCachedUserData(userID: userID)?.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.purple.opacity(0.6), lineWidth: 1.5)
                )
                
                // Username
                if let cached = Self.getCachedUserData(userID: userID) {
                    Text("@\(cached.displayName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Trigger cache load for this user
            _ = Self.getCachedUserData(userID: userID)
        }
    }
    
    // MARK: - Bottom Section (CORRECT ORDER: Title, Description, Tagged Users, Metadata, Buttons)
    
    private var bottomSection: some View {
        VStack(spacing: 12) {
            // Row 1: Video title
            HStack {
                Text(video.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                Spacer()
            }
            .padding(.horizontal, 12)
            
            // Row 2: Video description (if available)
            if let description = videoDescription, !description.isEmpty {
                HStack {
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            
            // Row 2.5: Tagged users (if available)
            if !video.taggedUserIDs.isEmpty {
                taggedUsersRow
            }
            
            // Row 3: Metadata and follow button (closer together)
            HStack(spacing: 12) {
                metadataRow
                followButton
                Spacer()
            }
            .padding(.horizontal, 12)
            
            // Row 4: Evenly distributed engagement buttons (aligned baseline)
            HStack(alignment: .center, spacing: 0) {
                // Thread Button
                VStack(spacing: 4) {
                    Button {
                        // Comprehensive video kill - hit all possible notification patterns
                        NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingThreadView = true
                            onAction?(.thread(video.threadID ?? video.id))
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 42, height: 42)
                            
                            Circle()
                                .stroke(Color.cyan.opacity(0.4), lineWidth: 1.2)
                                .frame(width: 42, height: 42)
                            
                            Image(systemName: "text.justify")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(ContextualScaleButtonStyle())
                    
                    Text("Thread")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                
                // Progressive Cool Button (allow proper display)
                VStack(spacing: 4) {
                    ProgressiveCoolButton(
                        videoID: video.id,
                        currentCoolCount: videoEngagement?.coolCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80) // Allow space for counts above button
                }
                .frame(maxWidth: .infinity)
                
                // Progressive Hype Button (allow proper display)
                VStack(spacing: 4) {
                    ProgressiveHypeButton(
                        videoID: video.id,
                        currentHypeCount: videoEngagement?.hypeCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80) // Allow space for counts above button
                }
                .frame(maxWidth: .infinity)
                
                // Conditionally add Stitch button only if it exists
                if canReply {
                    // Stitch Button
                    VStack(spacing: 4) {
                        Button {
                            // Comprehensive video kill - hit all possible notification patterns
                            NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showingStitchRecording = true
                                onAction?(.stitch)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 42, height: 42)
                                
                                Circle()
                                    .stroke(Color.purple.opacity(0.4), lineWidth: 1.2)
                                    .frame(width: 42, height: 42)
                                
                                Image(systemName: "scissors")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(ContextualScaleButtonStyle())
                        
                        Text("Stitch")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Center Effects (Particle Systems)
    
    private var centerEffects: some View {
        ZStack {
            // Hype particles
            if showingHypeParticles {
                HypeParticleEffect()
                    .allowsHitTesting(false)
            }
            
            // Cool particles
            if showingCoolParticles {
                CoolParticleEffect()
                    .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Setup and Lifecycle
    
    private func setupOverlay() {
        // Load video engagement data
        Task {
            await loadVideoEngagement()
        }
        
        // Start cache refresh for user data
        Self.getCachedUserData(userID: video.creatorID)
        if let threadVideo = threadVideo {
            Self.getCachedUserData(userID: threadVideo.creatorID)
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for engagement updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VideoEngagementUpdated"),
            object: nil,
            queue: .main
        ) { notification in
            if let videoID = notification.userInfo?["videoID"] as? String,
               videoID == video.id {
                Task {
                    await loadVideoEngagement()
                }
            }
        }
        
        // Listen for real-time engagement changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EngagementStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let videoID = notification.userInfo?["videoID"] as? String,
               videoID == video.id,
               let hypeCount = notification.userInfo?["hypeCount"] as? Int,
               let coolCount = notification.userInfo?["coolCount"] as? Int,
               let viewCount = notification.userInfo?["viewCount"] as? Int {
                
                // Update local engagement data immediately
                if var engagement = videoEngagement {
                    engagement.hypeCount = hypeCount
                    engagement.coolCount = coolCount
                    engagement.viewCount = viewCount
                    engagement.lastEngagementAt = Date()
                    videoEngagement = engagement
                    print("🔄 ENGAGEMENT: Updated counts - H:\(hypeCount) C:\(coolCount) V:\(viewCount)")
                }
            }
        }
        
        // Listen for view tracking
        Task {
            await trackVideoView()
        }
        
        // Load follow state
        Task {
            await loadFollowState()
        }
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("VideoEngagementUpdated"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("EngagementStateChanged"), object: nil)
    }
    
    // MARK: - Data Loading
    
    private func loadVideoEngagement() async {
        do {
            // Get live engagement data from VideoService
            let videoService = VideoService()
            let freshVideo = try await videoService.getVideo(id: video.id)
            
            await MainActor.run {
                videoEngagement = ContextualVideoEngagement(
                    videoID: freshVideo.id,
                    creatorID: freshVideo.creatorID,
                    hypeCount: freshVideo.hypeCount,
                    coolCount: freshVideo.coolCount,
                    shareCount: freshVideo.shareCount,
                    replyCount: freshVideo.replyCount,
                    viewCount: freshVideo.viewCount,
                    lastEngagementAt: freshVideo.lastEngagementAt ?? Date()
                )
                
                // Load video description from fresh data
                videoDescription = freshVideo.description.isEmpty ? nil : freshVideo.description
            }
            
            print("✅ CONTEXTUAL OVERLAY: Loaded fresh engagement data - \(freshVideo.hypeCount) hypes, \(freshVideo.coolCount) cools, \(freshVideo.viewCount) views")
            
        } catch {
            print("⚠️ CONTEXTUAL OVERLAY: Failed to load engagement data - \(error)")
            // Don't fall back to static data - let UI show loading state
        }
    }
    
    /// Track video view after 5 seconds (allows multiple views per user)
    private func trackVideoView() async {
        guard let currentUserID = currentUserID else { return }
        
        // Wait 5 seconds before recording view
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        do {
            // FORCE view recording without duplicate check
            try await VideoService().incrementViewCount(
                videoID: video.id,
                userID: currentUserID,
                watchTime: 5.0
            )
            print("CONTEXTUAL OVERLAY: View tracked after 5 seconds for video \(video.id)")
        } catch {
            print("CONTEXTUAL OVERLAY: Failed to track view - \(error)")
        }
    }
    
    private func loadFollowState() async {
        await followManager.loadFollowState(for: video.creatorID)
    }
    
    // MARK: - Recording Context Helper
    
    private func getStitchRecordingContext() -> RecordingContext {
        if let threadID = video.threadID {
            let threadInfo = ThreadInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL,
                participantCount: 1,
                stitchCount: video.replyCount
            )
            return .stitchToThread(threadID: threadID, threadInfo: threadInfo)
        } else {
            let videoInfo = CameraVideoInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL
            )
            return .replyToVideo(videoID: video.id, videoInfo: videoInfo)
        }
    }
    
    // MARK: - Utility Functions
    
    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1000000:
            return String(format: "%.1fK", Double(count) / 1000.0).replacingOccurrences(of: ".0", with: "")
        case 1000000..<1000000000:
            return String(format: "%.1fM", Double(count) / 1000000.0).replacingOccurrences(of: ".0", with: "")
        default:
            return String(format: "%.1fB", Double(count) / 1000000000.0).replacingOccurrences(of: ".0", with: "")
        }
    }
    
    // NEW: Compact format for badge
    private func formatCountCompact(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<10000:
            return String(format: "%.1fK", Double(count) / 1000.0).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(count / 1000)K"
        }
    }
}

// MARK: - Supporting Types

enum OverlayContext {
    case homeFeed
    case discovery
    case profileOwn
    case profileOther
    case thread
    case fullscreen
}

enum ContextualOverlayAction {
    case profile(String)
    case thread(String)
    case engagement(EngagementType)
    case follow
    case unfollow
    case followToggle
    case share
    case reply
    case stitch
    case more
    case profileManagement
    case profileSettings
    case viewers  // NEW
}

enum EngagementType {
    case hype
    case cool
    case view
}

// MARK: - ContextualVideoEngagement Model
struct ContextualVideoEngagement {
    let videoID: String
    let creatorID: String
    var hypeCount: Int
    var coolCount: Int
    var shareCount: Int
    var replyCount: Int
    var viewCount: Int
    var lastEngagementAt: Date
    
    /// Total engagement count
    var totalEngagements: Int {
        return hypeCount + coolCount
    }
    
    /// Engagement ratio (hype vs total)
    var engagementRatio: Double {
        let total = totalEngagements
        return total > 0 ? Double(hypeCount) / Double(total) : 0.5
    }
}

// MARK: - Particle Effects (Placeholder)
struct HypeParticleEffect: View {
    var body: some View {
        // Placeholder - will be implemented with real particle system
        EmptyView()
    }
}

struct CoolParticleEffect: View {
    var body: some View {
        // Placeholder - will be implemented with real particle system
        EmptyView()
    }
}

// MARK: - Contextual Button Style
struct ContextualScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Missing VideoService Extension

extension VideoService {
    /// ADDED: Missing method needed by ContextualVideoOverlay
    func incrementViewCount(videoID: String, userID: String, watchTime: TimeInterval) async throws {
        // Record view interaction
        try await recordUserInteraction(
            videoID: videoID,
            userID: userID,
            interactionType: .view,
            watchTime: watchTime
        )
        
        // Update video view count
        let video = try await getVideo(id: videoID)
        try await updateVideoEngagement(
            videoID: videoID,
            hypeCount: video.hypeCount,
            coolCount: video.coolCount,
            viewCount: video.viewCount + 1,
            temperature: video.temperature,
            lastEngagementAt: Date()
        )
    }
}
