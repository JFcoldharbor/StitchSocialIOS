//
//  ContextualVideoOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Universal Contextual Video Overlay with Viewer Tracking
//  Dependencies: EngagementService, UserService, AuthService, FollowManager, VideoService
//  Features: Static overlay, special user permissions, context-aware profile navigation, viewer tracking
//  UPDATED: Uses external TaggedUsersRow component, removed embedded implementation
//

import SwiftUI

// MARK: - Shared Types (Used by extracted components)

/// Cached user data structure (shared across components)
struct CachedUserData {
    let displayName: String
    let profileImageURL: String?
    let tier: UserTier?
    let cachedAt: Date
}

/// Video engagement data model (shared across components)
struct ContextualVideoEngagement {
    let videoID: String
    let creatorID: String
    var hypeCount: Int
    var coolCount: Int
    var shareCount: Int
    var replyCount: Int
    var viewCount: Int
    var lastEngagementAt: Date
    
    var totalEngagements: Int {
        return hypeCount + coolCount
    }
    
    var engagementRatio: Double {
        let total = totalEngagements
        return total > 0 ? Double(hypeCount) / Double(total) : 0.5
    }
}

/// Contextual button style (shared across components)
struct ContextualScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Universal overlay that adapts to different viewing contexts with viewer tracking
struct ContextualVideoOverlay: View {
    
    // MARK: - Properties
    
    let video: CoreVideoMetadata
    let context: OverlayContext
    let currentUserID: String?
    let threadVideo: CoreVideoMetadata?
    let isVisible: Bool
    let onAction: ((ContextualOverlayAction) -> Void)?
    
    /// Actual reply count from ThreadData - overrides video.replyCount when provided
    /// Use this when you have access to thread.childVideos.count for accurate count
    let actualReplyCount: Int?
    
    /// Computed reply count - uses actualReplyCount if available, otherwise video.replyCount
    private var displayReplyCount: Int {
        actualReplyCount ?? video.replyCount
    }
    
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
    
    // MARK: - UI State
    
    @State private var showingProfileFullscreen = false
    @State private var showingThreadView = false
    @State private var showingViewers = false
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
        actualReplyCount: Int? = nil,
        onAction: ((ContextualOverlayAction) -> Void)? = nil
    ) {
        self.video = video
        self.context = context
        self.currentUserID = currentUserID
        self.threadVideo = threadVideo
        self.isVisible = isVisible
        self.actualReplyCount = actualReplyCount
        self.onAction = onAction
    }
    
    // MARK: - Minimal Discovery Overlay
    
    private var minimalDiscoveryOverlay: some View {
        ZStack {
            // Main content
            VStack {
                // Top: Creator name only
                HStack {
                    Button {
                        selectedUserID = video.creatorID
                        
                        // Comprehensive video kill
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
                
                // Bottom: Video title only
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
            
            // Right Side - Swipe for replies indicator
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    
                    // Show swipe banner for parent videos with replies
                    if video.conversationDepth == 0 && displayReplyCount > 0 {
                        SwipeForRepliesBanner(replyCount: displayReplyCount)
                    }
                    
                    Spacer()
                }
            }
            .padding(.trailing, 12)
        }
    }
    
    // MARK: - Full Contextual Overlay
    
    private func fullContextualOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Top Section
            VStack {
                topSection
                Spacer()
            }
            .opacity(1.0)
            
            // Bottom Section
            VStack {
                Spacer()
                bottomSection
                    .padding(.bottom, geometry.size.height * 0.08)
            }
            .opacity(1.0)
            
            // Right Side - Swipe for replies indicator
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    
                    // Show swipe banner for parent videos with replies
                    if video.conversationDepth == 0 && displayReplyCount > 0 {
                        SwipeForRepliesBanner(replyCount: displayReplyCount)
                    }
                    
                    Spacer()
                }
            }
            .padding(.trailing, 12)
            .opacity(1.0)
            
            // Center Effects
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
    
    // MARK: - Special user detection
    
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
    
    /// Get cached user data - returns immediately if cached, triggers load if missing
    private static func getCachedUserData(userID: String) -> CachedUserData? {
        // Check if we have valid cached data
        if let cached = userDataCache[userID],
           let timestamp = cacheTimestamps[userID],
           Date().timeIntervalSince(timestamp) < cacheExpiration {
            return cached
        }
        
        // Missing or expired - trigger immediate load in background
        if !pendingBatchRequests.contains(userID) {
            pendingBatchRequests.insert(userID)
            
            // Trigger immediate load for first request
            if pendingBatchRequests.count == 1 {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                    await scheduleBatchLoad()
                }
            }
        }
        
        // Return placeholder immediately
        return nil
    }
    
    /// Schedule batch loading
    private static func scheduleBatchLoad() async {
        guard !pendingBatchRequests.isEmpty else { return }
        
        let userIDs = Array(pendingBatchRequests)
        pendingBatchRequests.removeAll()
        batchTimer?.invalidate()
        batchTimer = nil
        
        await loadUserDataBatch(userIDs: userIDs)
    }
    
    /// Load user data in batch - OPTIMIZED
    private static func loadUserDataBatch(userIDs: [String]) async {
        let userService = UserService()
        
        // Load all users concurrently
        await withTaskGroup(of: (String, CachedUserData?)?.self) { group in
            for userID in userIDs {
                group.addTask {
                    do {
                        if let user = try await userService.getUser(id: userID) {
                            return (userID, CachedUserData(
                                displayName: user.displayName,
                                profileImageURL: user.profileImageURL,
                                tier: user.tier,
                                cachedAt: Date()
                            ))
                        }
                    } catch {
                        print("⚠️ CACHE: Failed to load user \(userID): \(error)")
                    }
                    return nil
                }
            }
            
            // Collect results
            for await result in group {
                if let (userID, cached) = result {
                    await MainActor.run {
                        userDataCache[userID] = cached
                        cacheTimestamps[userID] = Date()
                    }
                }
            }
        }
        
        // Notify UI to refresh
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("UserDataCacheUpdated"), object: nil)
        }
        
        print("✅ CACHE: Loaded \(userIDs.count) users concurrently")
    }
    
    private static func clearExpiredCache() {
        let now = Date()
        for (userID, timestamp) in cacheTimestamps {
            if now.timeIntervalSince(timestamp) > cacheExpiration {
                userDataCache.removeValue(forKey: userID)
                cacheTimestamps.removeValue(forKey: userID)
            }
        }
    }
    
    private var displayCreatorName: String {
        if let cached = Self.getCachedUserData(userID: video.creatorID) {
            return cached.displayName
        }
        // Fallback to video metadata while loading
        return video.creatorName.isEmpty ? "Loading..." : video.creatorName
    }
    
    private var displayThreadCreatorName: String {
        if let threadVideo = threadVideo,
           let cached = Self.getCachedUserData(userID: threadVideo.creatorID) {
            return cached.displayName
        }
        // Fallback to thread video metadata
        return threadVideo?.creatorName ?? displayCreatorName
    }
    
    private var displayCreatorProfileImageURL: String? {
        if let cached = Self.getCachedUserData(userID: video.creatorID) {
            return cached.profileImageURL
        }
        return nil
    }
    
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
                    minimalDiscoveryOverlay
                } else {
                    fullContextualOverlay(geometry: geometry)
                }
                
                // Floating Icons Overlay
                ForEach(floatingIconManager.activeIcons, id: \.id) { icon in
                    icon
                }
            }
        }
        .onAppear {
            setupOverlay()
            setupNotificationObservers()
            Self.clearExpiredCache()
        }
        .onDisappear {
            removeNotificationObservers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserDataCacheUpdated"))) { _ in
            isLoadingUserData.toggle()
            isLoadingUserData.toggle()
        }
        .fullScreenCover(isPresented: $showingProfileFullscreen) {
            let userIDToShow = selectedUserID ?? video.creatorID
            
            CreatorProfileView(userID: userIDToShow)
                .onAppear {
                    print("📱 FULLSCREEN: CreatorProfileView appeared for userID: \(userIDToShow)")
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("FullscreenProfileOpened"), object: nil)
                }
                .onDisappear {
                    print("📱 FULLSCREEN: CreatorProfileView disappeared")
                    selectedUserID = nil
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
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                    Task { await loadVideoEngagement() }
                },
                onCancel: {
                    showingStitchRecording = false
                    NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                }
            )
            .onAppear {
                NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
            }
            .onDisappear {
                NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
            }
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        HStack {
            // Creator Pills (USING EXTRACTED COMPONENT)
            VStack(alignment: .leading, spacing: 8) {
                // Video creator pill
                CreatorPill(
                    creator: video,
                    isThread: false,
                    colors: temperatureColor == .red ?
                        [.red, .orange] : temperatureColor == .blue ?
                        [.blue, .cyan] : temperatureColor == .orange ?
                        [.orange, .yellow] : temperatureColor == .cyan ?
                        [.cyan, .blue] : [.gray, .white],
                    displayName: displayCreatorName,
                    profileImageURL: displayCreatorProfileImageURL,
                    onTap: {
                        NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("FullscreenModeActivated"), object: nil)
                        NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterBackground"), object: nil)
                        
                        selectedUserID = video.creatorID
                        showingProfileFullscreen = true
                        onAction?(.profile(video.creatorID))
                    }
                )
                
                // Thread creator pill
                if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
                    CreatorPill(
                        creator: threadVideo,
                        isThread: true,
                        colors: [.purple, .pink],
                        displayName: displayThreadCreatorName,
                        profileImageURL: displayThreadCreatorProfileImageURL,
                        onTap: {
                            NotificationCenter.default.post(name: NSNotification.Name("DisableVideoAutoRestart"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("FullscreenModeActivated"), object: nil)
                            NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("StopAllBackgroundActivity"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("DeactivateAllPlayers"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterBackground"), object: nil)
                            
                            selectedUserID = threadVideo.creatorID
                            showingProfileFullscreen = true
                            onAction?(.profile(threadVideo.creatorID))
                        }
                    )
                }
            }
            
            Spacer()
            
            // Top-right section: Tagged users + action buttons
            VStack(alignment: .trailing, spacing: 8) {
                // Tagged Users (USING EXTERNAL COMPONENT)
                if !video.taggedUserIDs.isEmpty {
                    TaggedUsersRow(
                        taggedUserIDs: video.taggedUserIDs,
                        getCachedUserData: { userID in
                            Self.getCachedUserData(userID: userID)
                        },
                        onUserTap: { userID in
                            selectedUserID = userID
                            
                            NotificationCenter.default.post(name: .RealkillAllVideoPlayers, object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("killAllVideoPlayers"), object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("PauseAllVideos"), object: nil)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showingProfileFullscreen = true
                                onAction?(.profile(userID))
                            }
                        }
                    )
                }
                
                // More options button
                if currentUserIsSpecial || currentUserIsFounder {
                    moreOptionsButton
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Follow Button
    
    private var followButton: some View {
        FollowButton(
            userID: video.creatorID,
            isFollowing: isFollowing,
            onToggle: handleFollowToggle,
            isHidden: isUserVideo,
            style: .standard
        )
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
    
    // MARK: - Bottom Section
    
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
            
            // Row 2: Video description
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
            
            // Row 3: Metadata and follow button (USING EXTRACTED COMPONENT)
            HStack(spacing: 12) {
                VideoMetadataRow(
                    engagement: videoEngagement,
                    isUserVideo: isUserVideo,
                    onViewersTap: {
                        print("👁️ VIEWS: Tapped views button")
                        showingViewers = true
                        onAction?(.viewers)
                    }
                )
                followButton
                Spacer()
            }
            .padding(.horizontal, 12)
            
            // Row 4: Engagement buttons
            HStack(alignment: .center, spacing: 0) {
                // Thread Button
                VStack(spacing: 4) {
                    Button {
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
                
                // Progressive Cool Button
                VStack(spacing: 4) {
                    ProgressiveCoolButton(
                        videoID: video.id,
                        currentCoolCount: videoEngagement?.coolCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80)
                }
                .frame(maxWidth: .infinity)
                
                // Progressive Hype Button
                VStack(spacing: 4) {
                    ProgressiveHypeButton(
                        videoID: video.id,
                        currentHypeCount: videoEngagement?.hypeCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80)
                }
                .frame(maxWidth: .infinity)
                
                // Stitch Button
                if canReply {
                    VStack(spacing: 4) {
                        Button {
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
    
    // MARK: - Center Effects
    
    private var centerEffects: some View {
        ZStack {
            if showingHypeParticles {
                HypeParticleEffect()
                    .allowsHitTesting(false)
            }
            
            if showingCoolParticles {
                CoolParticleEffect()
                    .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Setup and Lifecycle
    
    private func setupOverlay() {
        // EAGER PRELOAD: Load user data immediately when overlay appears
        Task {
            await preloadUserData()
            await loadVideoEngagement()
        }
    }
    
    /// Preload user data for video and thread creators
    private func preloadUserData() async {
        var userIDsToLoad: [String] = [video.creatorID]
        
        // Add thread creator if different
        if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
            userIDsToLoad.append(threadVideo.creatorID)
        }
        
        // Add tagged users
        userIDsToLoad.append(contentsOf: video.taggedUserIDs.prefix(5))
        
        // Remove duplicates
        let uniqueUserIDs = Array(Set(userIDsToLoad))
        
        // Check which ones need loading
        let usersToLoad = uniqueUserIDs.filter { userID in
            Self.getCachedUserData(userID: userID) == nil
        }
        
        guard !usersToLoad.isEmpty else {
            print("✅ PRELOAD: All users already cached")
            return
        }
        
        print("🎬 PRELOAD: Loading \(usersToLoad.count) users eagerly")
        
        // Load immediately (don't wait for batch timer)
        await Self.loadUserDataBatch(userIDs: usersToLoad)
    }
    
    private func setupNotificationObservers() {
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
        
        Task {
            await trackVideoView()
        }
        
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
                
                videoDescription = freshVideo.description.isEmpty ? nil : freshVideo.description
            }
            
            print("✅ CONTEXTUAL OVERLAY: Loaded fresh engagement data - \(freshVideo.hypeCount) hypes, \(freshVideo.coolCount) cools, \(freshVideo.viewCount) views")
            
        } catch {
            print("⚠️ CONTEXTUAL OVERLAY: Failed to load engagement data - \(error)")
        }
    }
    
    private func trackVideoView() async {
        guard let currentUserID = currentUserID else { return }
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        do {
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
    
    /// Returns the appropriate recording context based on video depth
    /// - Depth 0 (thread): Returns .stitchToThread → creates depth 1 child
    /// - Depth 1 (child): Returns .replyToVideo → creates depth 2 grandchild
    private func getStitchRecordingContext() -> RecordingContext {
        // FIXED: Check conversationDepth instead of threadID presence
        // threadID is ALWAYS set (it's the root thread's ID for all videos)
        // We need to distinguish between replying to a thread vs replying to a child
        
        if video.conversationDepth == 0 {
            // This IS a thread (parent video) - stitch creates a child (depth 1)
            let threadInfo = ThreadInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL,
                participantCount: 1,
                stitchCount: video.replyCount
            )
            print("🎬 STITCH CONTEXT: Stitching to THREAD (depth 0) → will create depth 1 child")
            return .stitchToThread(threadID: video.id, threadInfo: threadInfo)
        } else {
            // This is a child/reply (depth 1+) - reply creates a grandchild (depth 2)
            let videoInfo = CameraVideoInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL
            )
            print("🎬 STITCH CONTEXT: Replying to CHILD (depth \(video.conversationDepth)) → will create depth \(video.conversationDepth + 1)")
            return .replyToVideo(videoID: video.id, videoInfo: videoInfo)
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
    case viewers
}

enum EngagementType {
    case hype
    case cool
    case view
}

// MARK: - Particle Effects
struct HypeParticleEffect: View {
    var body: some View {
        EmptyView()
    }
}

struct CoolParticleEffect: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - Missing VideoService Extension

extension VideoService {
    func incrementViewCount(videoID: String, userID: String, watchTime: TimeInterval) async throws {
        try await recordUserInteraction(
            videoID: videoID,
            userID: userID,
            interactionType: .view,
            watchTime: watchTime
        )
        
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
