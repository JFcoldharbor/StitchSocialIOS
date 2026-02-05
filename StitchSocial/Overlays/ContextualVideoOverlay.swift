//
//  ContextualVideoOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Universal Contextual Video Overlay with Viewer Tracking
//  Dependencies: EngagementService, UserService, AuthService, FollowManager, VideoService, VideoMetadataRow
//  Features: Static overlay, special user permissions, context-aware profile navigation, viewer tracking
//  UPDATED: Added self-stitching support - creators can now continue their own threads
//           Context-aware: profileOwn, homeFeed, thread, fullscreen allow self-stitch
//  UPDATED: Added video edit functionality - creators can edit title/description from profileOwn only
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
    let actualReplyCount: Int?
    
    /// For carousel participant detection - determines if user can reply vs spinoff
    let isConversationParticipant: Bool
    
    /// Computed reply count - uses actualReplyCount if available, otherwise video.replyCount
    private var displayReplyCount: Int {
        actualReplyCount ?? video.replyCount
    }
    
    // MARK: - State
    @StateObject private var userService = UserService()
    @StateObject private var authService = AuthService()
    @ObservedObject var followManager = FollowManager.shared
    @StateObject private var engagementManager = EngagementManager(
        videoService: VideoService(),
        userService: UserService()
    )
    @StateObject private var floatingIconManager = FloatingIconManager()
    @StateObject private var videoService = VideoService()
    
    // MARK: - Cached User Data (Static Cache Shared Across All Overlays)
    private static var userDataCache: [String: CachedUserData] = [:]
    private static var cacheTimestamps: [String: Date] = [:]
    private static let cacheExpiration: TimeInterval = 300
    private static let batchSize = 10
    private static var pendingBatchRequests: Set<String> = []
    private static var batchTimer: Timer?
    
    // MARK: - UI State
    @State private var showingProfileFullscreen = false
    @State private var showingThreadView = false
    @State private var showingViewers = false
    @State private var selectedUserID: String? {
        didSet {
            print("ðŸ” STATE: selectedUserID changed from \(oldValue ?? "nil") to \(selectedUserID ?? "nil")")
        }
    }
    
    // Engagement data
    @State private var videoEngagement: ContextualVideoEngagement?
    @State private var showingHypeParticles = false
    @State private var showingCoolParticles = false
    
    // Real user data lookup
    @State private var isLoadingUserData = false
    @State private var videoDescription: String?
    
    // Recording state
    @State private var showingStitchRecording = false
    
    // MARK: - Edit State
    @State private var showingEditSheet = false
    @State private var currentVideo: CoreVideoMetadata?
    @State private var currentTitle: String = ""
    
    // MARK: - Initializer
    init(
        video: CoreVideoMetadata,
        context: OverlayContext,
        currentUserID: String?,
        threadVideo: CoreVideoMetadata? = nil,
        isVisible: Bool = true,
        actualReplyCount: Int? = nil,
        isConversationParticipant: Bool = false,  // NEW: Default to false (not in conversation)
        onAction: ((ContextualOverlayAction) -> Void)? = nil
    ) {
        self.video = video
        self._currentVideo = State(initialValue: video)
        self._currentTitle = State(initialValue: video.title)
        self.context = context
        self.currentUserID = currentUserID
        self.threadVideo = threadVideo
        self.isVisible = isVisible
        self.actualReplyCount = actualReplyCount
        self.isConversationParticipant = isConversationParticipant  // NEW: Initialize property
        self.onAction = onAction
    }
    
    // MARK: - Minimal Discovery Overlay
    private var minimalDiscoveryOverlay: some View {
        ZStack {
            VStack {
                HStack {
                    Button {
                        selectedUserID = video.creatorID
                        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingProfileFullscreen = true
                            onAction?(.profile(video.creatorID))
                        }
                    } label: {
                        HStack(spacing: 4) {
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
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // ⭐ REMOVED: Top Spacer() - moves share button down
                    ShareButton(
                        video: video,
                        creatorUsername: displayCreatorName,
                        threadID: video.threadID ?? video.id,
                        size: .medium
                    )
                    Spacer()  // Keep bottom spacer but much smaller due to reduced spacing
                }
            }
            .padding(.trailing, 12)
        }
    }
    
    // MARK: - Full Contextual Overlay
    private func fullContextualOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            VStack {
                topSection
                Spacer()
            }
            .opacity(1.0)
            VStack {
                Spacer()
                bottomSection
                    .padding(.bottom, geometry.size.height * 0.08)
            }
            .opacity(1.0)
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // ⭐ REMOVED: Top Spacer() - moves share button down
                    ShareButton(
                        video: video,
                        creatorUsername: displayCreatorName,
                        threadID: video.threadID ?? video.id,
                        size: .medium
                    )
                    Spacer()  // Keep bottom spacer but much smaller due to reduced spacing
                }
            }
            .padding(.trailing, 12)
            .opacity(1.0)
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
    
    /// Can only edit from own profile grid
    private var canEditVideo: Bool {
        context == .profileOwn && isUserVideo
    }
    
    private var canReply: Bool {
        // Special handling for carousel context - participant-based logic
        if context == .carousel {
            // In carousel, can reply up to depth 19 (so reply creates depth 20 max)
            guard video.conversationDepth < 19 else {
                print("🚫 CAROUSEL: At max depth - show spinoff instead")
                return false
            }
            
            // PARTICIPANT CHECK: Only conversation participants can reply
            // Third parties should see spinoff, not reply
            if !isConversationParticipant {
                print("🚫 CAROUSEL: Not a participant - show spinoff instead")
                return false
            }
            
            // Participant CAN reply, but NOT to their own video
            if isUserVideo {
                print("🚫 CAROUSEL: Own video - no self-stitch in conversations")
                return false
            }
            
            return true
        }
        
        // Original logic for other contexts
        guard video.conversationDepth <= 1 else {
            print("🚫 STITCH: Blocked - depth \(video.conversationDepth) > 1")
            return false
        }
        if isUserVideo {
            let allowed = allowsSelfReply
            print("🎬 STITCH: Own video - context: \(context), allowsSelfReply: \(allowed)")
            return allowed
        }
        return true
    }
    
    private var allowsSelfReply: Bool {
        switch context {
        case .profileOwn: return true
        case .homeFeed: return true
        case .thread: return true
        case .fullscreen: return true
        case .discovery: return false
        case .profileOther: return false
        case .carousel: return false  // Never allow self-reply in carousel conversations
        }
    }
    
    private var stitchButtonIcon: String {
        if shouldShowSpinoff {
            return "arrow.triangle.branch"
        }
        return isUserVideo ? "plus.circle" : "scissors"
    }
    
    private var stitchButtonLabel: String {
        if shouldShowSpinoff {
            return "Spinoff"
        }
        return isUserVideo ? "Continue" : "Stitch"
    }
    
    private var stitchButtonRingColor: Color {
        if shouldShowSpinoff {
            return .orange
        }
        return isUserVideo ? .green : .purple
    }
    
    // NEW: Determine if we should show spinoff button
    private var shouldShowSpinoff: Bool {
        if context != .carousel {
            return false
        }
        
        // Show spinoff in carousel when:
        // 1. At depth 19+ (max depth limit), OR
        // 2. User is not a conversation participant (third party)
        return video.conversationDepth >= 19 || !isConversationParticipant
    }
    
    // NEW: Can show reply OR spinoff
    private var canShowReplyOrSpinoff: Bool {
        return canReply || shouldShowSpinoff
    }
    
    private var shouldShowMinimalDisplay: Bool {
        return context == .discovery || context == .carousel
    }
    
    private var shouldShowFullDisplay: Bool {
        return context != .discovery && context != .carousel
    }
    
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
    private static func getCachedUserData(userID: String) -> CachedUserData? {
        if let cached = userDataCache[userID],
           let timestamp = cacheTimestamps[userID],
           Date().timeIntervalSince(timestamp) < cacheExpiration {
            return cached
        }
        if !pendingBatchRequests.contains(userID) {
            pendingBatchRequests.insert(userID)
            if pendingBatchRequests.count == 1 {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await scheduleBatchLoad()
                }
            }
        }
        return nil
    }
    
    private static func scheduleBatchLoad() async {
        guard !pendingBatchRequests.isEmpty else { return }
        let userIDs = Array(pendingBatchRequests)
        pendingBatchRequests.removeAll()
        batchTimer?.invalidate()
        batchTimer = nil
        await loadUserDataBatch(userIDs: userIDs)
    }
    
    private static func loadUserDataBatch(userIDs: [String]) async {
        let userService = UserService()
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
                        print("âš ï¸ CACHE: Failed to load user \(userID): \(error)")
                    }
                    return nil
                }
            }
            for await result in group {
                if let (userID, cached) = result {
                    await MainActor.run {
                        userDataCache[userID] = cached
                        cacheTimestamps[userID] = Date()
                    }
                }
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("UserDataCacheUpdated"), object: nil)
        }
        print("âœ… CACHE: Loaded \(userIDs.count) users concurrently")
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
        return video.creatorName.isEmpty ? "Loading..." : video.creatorName
    }
    
    private var displayThreadCreatorName: String {
        if let threadVideo = threadVideo,
           let cached = Self.getCachedUserData(userID: threadVideo.creatorID) {
            return cached.displayName
        }
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
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService,
                viewingUserID: userIDToShow
            )
                .onAppear {
                    print("ðŸ“± FULLSCREEN: CreatorProfileView appeared for userID: \(userIDToShow)")
                    NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("FullscreenProfileOpened"), object: nil)
                }
                .onDisappear {
                    print("ðŸ“± FULLSCREEN: CreatorProfileView disappeared")
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
                    Task { await loadVideoEngagement() }
                },
                onCancel: {
                    showingStitchRecording = false
                }
            )
        }
        .shareOverlay()
        .sheet(isPresented: $showingEditSheet) {
            VideoEditSheet(
                video: currentVideo ?? video,
                onSave: { updatedVideo in
                    currentVideo = updatedVideo
                    currentTitle = updatedVideo.title
                    videoDescription = updatedVideo.description.isEmpty ? nil : updatedVideo.description
                    print("âœï¸ EDIT: Video updated - \(updatedVideo.title)")
                },
                onDismiss: {
                    showingEditSheet = false
                }
            )
        }
    }
    
    // MARK: - Top Section
    private var topSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
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
                        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterBackground"), object: nil)
                        selectedUserID = video.creatorID
                        showingProfileFullscreen = true
                        onAction?(.profile(video.creatorID))
                    }
                )
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
                            NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                            NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterBackground"), object: nil)
                            selectedUserID = threadVideo.creatorID
                            showingProfileFullscreen = true
                            onAction?(.profile(threadVideo.creatorID))
                        }
                    )
                }
            }
            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Follow Button
    private var followButton: some View {
        Group {
            if !isUserVideo {
                Button {
                    Task {
                        await followManager.toggleFollow(for: video.creatorID)
                        onAction?(.followToggle)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if followManager.isLoading(video.creatorID) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: followManager.isFollowing(video.creatorID) ? "checkmark" : "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text(followManager.isFollowing(video.creatorID) ? "Following" : "Follow")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(followManager.isFollowing(video.creatorID) ? Color.gray.opacity(0.4) : Color.cyan)
                    )
                }
                .buttonStyle(ContextualScaleButtonStyle())
            }
        }
    }
    
    // MARK: - Bottom Section
    private var bottomSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(currentTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                Spacer()
            }
            .padding(.horizontal, 12)
            
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
            
            HStack(spacing: 12) {
                VideoMetadataRow(
                    engagement: videoEngagement,
                    isUserVideo: isUserVideo,
                    canEdit: canEditVideo,
                    onViewersTap: {
                        print("ðŸ‘ï¸ VIEWS: Tapped views button")
                        showingViewers = true
                        onAction?(.viewers)
                    },
                    onEditTap: {
                        print("âœï¸ EDIT: Opening edit sheet from profile")
                        showingEditSheet = true
                        onAction?(.edit)
                    }
                )
                followButton
                Spacer()
            }
            .padding(.horizontal, 12)
            
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 4) {
                    Button {
                        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
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
                
                VStack(spacing: 4) {
                    ProgressiveCoolButton(
                        videoID: video.id,
                        creatorID: video.creatorID,
                        currentCoolCount: videoEngagement?.coolCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    ProgressiveHypeButton(
                        videoID: video.id,
                        creatorID: video.creatorID,
                        currentHypeCount: videoEngagement?.hypeCount ?? 0,
                        currentUserID: currentUserID ?? "",
                        userTier: authService.currentUser?.tier ?? .rookie,
                        engagementManager: engagementManager,
                        iconManager: floatingIconManager
                    )
                    .frame(height: 80)
                }
                .frame(maxWidth: .infinity)
                
                if canShowReplyOrSpinoff {
                    VStack(spacing: 4) {
                        Button {
                            showingStitchRecording = true
                            // Call appropriate action based on context
                            if shouldShowSpinoff {
                                onAction?(.spinOff)
                            } else {
                                onAction?(.stitch)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 42, height: 42)
                                Circle()
                                    .stroke(stitchButtonRingColor.opacity(0.4), lineWidth: 1.2)
                                    .frame(width: 42, height: 42)
                                Image(systemName: stitchButtonIcon)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(ContextualScaleButtonStyle())
                        Text(stitchButtonLabel)
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
        Task {
            await preloadUserData()
            await loadVideoEngagement()
        }
    }
    
    private func preloadUserData() async {
        var userIDsToLoad: [String] = [video.creatorID]
        if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
            userIDsToLoad.append(threadVideo.creatorID)
        }
        userIDsToLoad.append(contentsOf: video.taggedUserIDs.prefix(5))
        let uniqueUserIDs = Array(Set(userIDsToLoad))
        let usersToLoad = uniqueUserIDs.filter { userID in
            Self.getCachedUserData(userID: userID) == nil
        }
        guard !usersToLoad.isEmpty else {
            print("âœ… PRELOAD: All users already cached")
            return
        }
        print("ðŸŽ¬ PRELOAD: Loading \(usersToLoad.count) users eagerly")
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
                Task { await loadVideoEngagement() }
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
                    print("ðŸ”„ ENGAGEMENT: Updated counts - H:\(hypeCount) C:\(coolCount) V:\(viewCount)")
                }
            }
        }
        Task { await trackVideoView() }
        Task { await loadFollowState() }
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
                currentVideo = freshVideo
                currentTitle = freshVideo.title
            }
            print("âœ… CONTEXTUAL OVERLAY: Loaded fresh engagement data - \(freshVideo.hypeCount) hypes, \(freshVideo.coolCount) cools, \(freshVideo.viewCount) views")
        } catch {
            print("âš ï¸ CONTEXTUAL OVERLAY: Failed to load engagement data - \(error)")
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
    private func getStitchRecordingContext() -> RecordingContext {
        if video.conversationDepth == 0 {
            let threadInfo = ThreadInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL,
                participantCount: 1,
                stitchCount: video.replyCount
            )
            print("ðŸŽ¬ STITCH CONTEXT: Stitching to THREAD (depth 0) â†’ will create depth 1 child")
            return .stitchToThread(threadID: video.id, threadInfo: threadInfo)
        } else {
            let videoInfo = CameraVideoInfo(
                title: video.title,
                creatorName: video.creatorName,
                creatorID: video.creatorID,
                thumbnailURL: video.thumbnailURL
            )
            print("ðŸŽ¬ STITCH CONTEXT: Replying to CHILD (depth \(video.conversationDepth)) â†’ will create depth \(video.conversationDepth + 1)")
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
    case carousel  // NEW: For carousel conversation view
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
    case spinOff  // NEW: For creating spinoff threads at max depth
    case more
    case profileManagement
    case profileSettings
    case viewers
    case edit
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

// MARK: - VideoService Extension

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
