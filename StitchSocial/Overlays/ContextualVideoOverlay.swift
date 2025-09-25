//
//  ContextualVideoOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Universal Contextual Video Overlay with All Fixes Applied
//  Dependencies: EngagementService, UserService, AuthService, FollowManager
//  Features: Static overlay, special user permissions, context-aware profile navigation
//

import SwiftUI

/// Universal overlay that adapts to different viewing contexts with all fixes applied
struct ContextualVideoOverlay: View {
    
    // MARK: - Properties
    
    let video: CoreVideoMetadata
    let context: OverlayContext
    let currentUserID: String?
    let threadVideo: CoreVideoMetadata?
    let isVisible: Bool
    let onAction: ((ContextualOverlayAction) -> Void)?
    
    // MARK: - State
    
    @StateObject private var engagementCoordinator = EngagementCoordinator(
        videoService: VideoService(),
        notificationService: NotificationService()
    )
    @StateObject private var userService = UserService()
    @StateObject private var authService = AuthService()
    @StateObject private var followManager = FollowManager()
    
    // FIXED: EngagementManager initialized in onAppear to avoid property initializer issue
    @State private var engagementManager: EngagementManager?
    
    // FIXED: Dual presentation states for context-aware navigation
    @State private var showingProfileSheet = false
    @State private var showingProfileFullscreen = false
    @State private var showingThreadView = false
    @State private var selectedUserID: String?
    
    // Engagement data
    @State private var videoEngagement: VideoEngagement?
    @State private var showingHypeParticles = false
    @State private var showingCoolParticles = false
    
    // Real user data lookup
    @State private var realCreatorName: String?
    @State private var realThreadCreatorName: String?
    @State private var isLoadingUserData = false
    
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
    
    // FIXED: Special user detection for enhanced permissions
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
    
    // FIXED: Enhanced engagement logic for special users
    private var shouldShowEngagement: Bool {
        switch context {
        case .homeFeed, .discovery, .profileOther:
            if isUserVideo && currentUserIsSpecial {
                return true  // Special users can engage with own content
            }
            return !isUserVideo
        case .profileOwn:
            return currentUserIsSpecial  // Special users see engagement on own profile
        }
    }
    
    private var shouldShowFollow: Bool {
        switch context {
        case .homeFeed, .discovery, .profileOther:
            return !isUserVideo
        case .profileOwn:
            return false
        }
    }
    
    // FIXED: Context-aware presentation selection - Force fullscreen to stop background videos
    private var shouldUseFullscreenPresentation: Bool {
        // Always use fullscreen for profiles to stop background videos
        return true
    }
    
    // Follow state managed by FollowManager
    private var isFollowing: Bool {
        followManager.isFollowing(video.creatorID)
    }
    
    private var isFollowLoading: Bool {
        followManager.isLoading(video.creatorID)
    }
    
    /// Get display name with real-time user lookup fallback
    private var displayCreatorName: String {
        realCreatorName ?? video.creatorName
    }

    /// Get thread creator display name with real-time lookup fallback
    private var displayThreadCreatorName: String {
        realThreadCreatorName ?? threadCreator.creatorName
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
    
    // MARK: - Body (FIXED: Static overlay with bottom engagement layout)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Top Section
                VStack {
                    topSection
                    Spacer()
                }
                
                // Bottom Section - Adjusted spacing for new engagement layout
                VStack {
                    Spacer()
                    bottomSection
                        .padding(.bottom, geometry.size.height * 0.05)
                }
                
                // Right Side - FIXED: Reduced to minimal space since engagement moved to bottom
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        
                        // Right side navigation indicator using FloatingBubbleNotification
                        if video.conversationDepth <= 1 && video.replyCount > 0 {
                            FloatingBubbleNotification(
                                replyCount: video.replyCount,
                                context: .homeFeed,
                                onDismiss: {
                                    print("STITCH INDICATOR: Bubble dismissed")
                                },
                                onAction: {
                                    showingThreadView = true
                                    onAction?(.thread(video.threadID ?? video.id))
                                }
                            )
                        }
                        
                        Spacer()
                    }
                }
                .padding(.trailing, 12)
                
                // Center Effects
                centerEffects
            }
        }
        .onAppear {
            setupOverlay()
            setupNotificationObservers()
        }
        .onDisappear {
            removeNotificationObservers()
        }
        .onChange(of: video.id) { oldVideoID, newVideoID in
            // Clear cached data when video changes
            realCreatorName = nil
            realThreadCreatorName = nil
            isLoadingUserData = false
            
            // Reload for new video
            Task {
                await loadRealUserData()
                await loadEngagementData()
            }
        }
        .onChange(of: threadVideo?.id) { oldThreadID, newThreadID in
            // Reload when thread video changes
            Task {
                await loadRealUserData()
            }
        }
        // FIXED: Always use fullscreen to stop background videos - sheet removed
        .fullScreenCover(isPresented: $showingProfileFullscreen) {
            if let userID = selectedUserID {
                CreatorProfileView(userID: userID)
                    .onAppear {
                        print("📱 FULLSCREEN: CreatorProfileView appeared for userID: \(userID)")
                        // Stop all background videos when profile opens
                        NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
                    }
            } else {
                Text("Error: No user selected")
                    .onAppear {
                        print("❌ FULLSCREEN: selectedUserID is nil!")
                    }
            }
        }
        .onChange(of: showingProfileFullscreen) { _, isShowing in
            if isShowing, let userID = selectedUserID {
                print("📱 FULLSCREEN: Presenting CreatorProfileView for userID: \(userID)")
            }
        }
        .fullScreenCover(isPresented: $showingThreadView) {
            ThreadView(
                threadID: video.threadID ?? video.id,
                videoService: VideoService(),
                userService: userService
            )
        }
        .fullScreenCover(isPresented: $showingStitchRecording) {
            RecordingView(
                recordingContext: getStitchRecordingContext(),
                onVideoCreated: { videoMetadata in
                    showingStitchRecording = false
                    // Refresh engagement data after stitch creation
                    Task { await loadEngagementData() }
                },
                onCancel: {
                    showingStitchRecording = false
                }
            )
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        HStack {
            // Creator Pills - FIXED: Moved to top section
            VStack(alignment: .leading, spacing: 8) {
                // Video creator pill (FIXED: Always tappable)
                creatorPill(
                    creator: video,
                    isThread: false,
                    colors: temperatureColor == .red ?
                        [.red, .orange] : temperatureColor == .blue ?
                        [.blue, .cyan] : temperatureColor == .orange ?
                        [.orange, .yellow] : temperatureColor == .cyan ?
                        [.cyan, .blue] : [.purple, .pink]
                )
                
                // Thread creator pill (if different, FIXED: Always tappable)
                if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                        
                        creatorPill(
                            creator: threadVideo,
                            isThread: true,
                            colors: [.purple, .pink]
                        )
                    }
                }
            }
            
            Spacer()
            
            // Context-specific top right
            topRightSection
        }
        .padding(.top, 50)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Bottom Section
    
    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thread indicator (if part of thread)
            if let threadVideo = threadVideo, threadVideo.id != video.id {
                threadIndicator
            }
            
            // Video Title - FIXED: Static text, no background
            if !video.title.isEmpty {
                videoTitleView
            }
            
            // Metadata Row with Follow Button
            HStack(spacing: 12) {
                metadataRow
                
                // Follow button next to stitches - same size and style
                if shouldShowFollow {
                    metadataStyleFollowButton
                }
                
                Spacer()
            }
            
            // FIXED: Bottom Engagement Button Layout
            bottomEngagementButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
    
    // MARK: - Top Right Section
    
    private var topRightSection: some View {
        VStack(spacing: 12) {
            // Only show more button for own profile
            if context == .profileOwn {
                moreButton
            }
        }
    }
    
    // MARK: - Engagement Section (FIXED: Right side vertical layout removed)
    
    private var engagementSection: some View {
        // Right side engagement moved to bottom - keeping this for compatibility
        EmptyView()
    }
    
    // MARK: - Bottom Engagement Layout (FIXED: Using Enhanced Progressive Buttons)
    
    private var bottomEngagementButtons: some View {
        HStack {
            // Left side buttons
            HStack(spacing: 20) {
                // Thread View Button (static)
                VStack(spacing: 4) {
                    Button {
                        showingThreadView = true
                        onAction?(.thread(video.threadID ?? video.id))
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 50, height: 50)
                            
                            Circle()
                                .stroke(Color.cyan.opacity(0.4), lineWidth: 1.2)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "link")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("Thread")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }
                
                // Enhanced Cool Button with EngagementManager
                if shouldShowEngagement {
                    VStack(spacing: 4) {
                        if let engagementManager = engagementManager {
                            ProgressiveCoolButton(
                                videoID: video.id,
                                currentCoolCount: videoEngagement?.coolCount ?? 0,
                                currentHypeCount: videoEngagement?.hypeCount ?? 0,
                                onCoolTap: {
                                    Task {
                                        await handleEngagement(type: .cool)
                                    }
                                },
                                engagementCoordinator: engagementCoordinator
                            )
                        } else {
                            // Fallback static button while EngagementManager initializes
                            Button {
                                Task {
                                    await handleEngagement(type: .cool)
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                    
                                    Circle()
                                        .stroke(Color.cyan.opacity(0.4), lineWidth: 1.2)
                                        .frame(width: 50, height: 50)
                                    
                                    Image(systemName: "snowflake")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Text(formatCount(videoEngagement?.coolCount ?? 0))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                }
            }
            
            Spacer()
            
            // Right side buttons
            HStack(spacing: 20) {
                // Enhanced Hype Button with EngagementManager
                if shouldShowEngagement {
                    VStack(spacing: 4) {
                        if let engagementManager = engagementManager {
                            ProgressiveHypeButton(
                                videoID: video.id,
                                currentHypeCount: videoEngagement?.hypeCount ?? 0,
                                currentCoolCount: videoEngagement?.coolCount ?? 0,
                                currentUserID: currentUserID ?? "",
                                userTier: authService.currentUser?.tier ?? .rookie,
                                onEngagementResult: { result in
                                    // Handle engagement result
                                    if result.success {
                                        // Reload engagement data to update UI
                                        Task { await loadEngagementData() }
                                    }
                                },
                                engagementManager: engagementManager
                            )
                        } else {
                            // Fallback static button while EngagementManager initializes
                            Button {
                                Task {
                                    await handleEngagement(type: .hype)
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                    
                                    Circle()
                                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.2)
                                        .frame(width: 50, height: 50)
                                    
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Text(formatCount(videoEngagement?.hypeCount ?? 0))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                
                // Stitch Button (static)
                VStack(spacing: 4) {
                    Button {
                        Task {
                            await handleEngagement(type: .stitch)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 50, height: 50)
                            
                            Circle()
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1.2)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("Stitch")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Center Effects
    
    private var centerEffects: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                // Live engagement effects
                ZStack {
                    if showingHypeParticles {
                        particleEffect(color: .orange, icon: "flame.fill")
                    }
                    
                    if showingCoolParticles {
                        particleEffect(color: .cyan, icon: "snowflake")
                    }
                }
                
                Spacer()
            }
            
            Spacer()
        }
    }
    
    // MARK: - UI Components
    
    // FIXED: Enhanced creator pill with universal tap navigation and profile pictures
    private func creatorPill(creator: CoreVideoMetadata, isThread: Bool, colors: [Color]) -> some View {
        // Determine correct display name based on which creator this pill represents
        let displayName: String
        if creator.creatorID == video.creatorID {
            // This is the video creator
            displayName = displayCreatorName
        } else if let threadVideo = threadVideo, creator.creatorID == threadVideo.creatorID {
            // This is the thread creator
            displayName = displayThreadCreatorName
        } else {
            // Fallback to creator's stored name
            displayName = creator.creatorName
        }
        
        return SwiftUI.Button {
            print("🔍 CREATOR PILL: Tapped creator pill for userID: \(creator.creatorID)")
            print("🔍 CREATOR PILL: Context: \(context)")
            print("🔍 CREATOR PILL: Should use fullscreen: \(shouldUseFullscreenPresentation)")
            
            selectedUserID = creator.creatorID
            
            // FIXED: Context-aware presentation selection with debugging
            if shouldUseFullscreenPresentation {
                print("📱 CREATOR PILL: Setting showingProfileFullscreen = true")
                showingProfileFullscreen = true
            } else {
                // Fallback - should not be used since we always use fullscreen now
                print("📋 CREATOR PILL: Setting showingProfileSheet = true")
                showingProfileFullscreen = true // Force fullscreen even in fallback
            }
            
            onAction?(.profile(creator.creatorID))
        } label: {
            HStack(spacing: isThread ? 8 : 6) {
                // FIXED: Profile picture avatar with border and debugging
                Button {
                    // Same action as pill - navigate to profile
                    print("🔍 PROFILE PICTURE: Tapped profile picture for userID: \(creator.creatorID)")
                    selectedUserID = creator.creatorID
                    if shouldUseFullscreenPresentation {
                        print("📱 PROFILE: Using fullscreen presentation")
                        showingProfileFullscreen = true
                    } else {
                        // Fallback - should not be used since we always use fullscreen now
                        print("📋 PROFILE: Using fullscreen presentation (forced)")
                        showingProfileFullscreen = true // Force fullscreen even in fallback
                    }
                    onAction?(.profile(creator.creatorID))
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: isThread ? 28 : 22, height: isThread ? 28 : 22)
                            .shadow(color: colors.first?.opacity(0.5) ?? .clear, radius: 6, x: 0, y: 2)
                        
                        // Profile picture - Load from user data when available
                        AsyncThumbnailView.avatar(url: "")
                            .frame(width: isThread ? 24 : 18, height: isThread ? 24 : 18)
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Name and context
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
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
            .padding(.horizontal, isThread ? 12 : 8)
            .padding(.vertical, isThread ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                            .stroke(
                                LinearGradient(colors: colors.map { $0.opacity(0.6) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var threadIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cyan)
            
            Text("Part of thread")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.cyan.opacity(0.8))
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func particleEffect(color: Color, icon: String) -> some View {
        ForEach(0..<8, id: \.self) { index in
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .offset(
                    x: CGFloat.random(in: -60...60),
                    y: CGFloat.random(in: -60...60)
                )
                .opacity(0.8)
                .scaleEffect(Double.random(in: 0.8...1.5))
                .animation(
                    .easeOut(duration: Double.random(in: 1.2...2.0))
                    .delay(Double(index) * 0.1),
                    value: true
                )
        }
    }
    
    private var profileManagementButton: some View {
        SwiftUI.Button {
            onAction?(.profileManagement)
        } label: {
            VStack(spacing: 6) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 42, height: 42)
                    
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: "gear")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Label
                Text("Settings")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var threadButton: some View {
        SwiftUI.Button {
            showingThreadView = true
            onAction?(.thread(video.threadID ?? video.id))
        } label: {
            VStack(spacing: 6) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 42, height: 42)
                    
                    Circle()
                        .stroke(Color.cyan.opacity(0.4), lineWidth: 1.2)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Label
                Text("Thread")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var moreButton: some View {
        SwiftUI.Button {
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
    
    // MARK: - FIXED: Video Title View - Static text, no background
    private var videoTitleView: some View {
        Text(video.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
    }
    
    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Views
            metadataItem(
                icon: "eye.fill",
                count: videoEngagement?.viewCount ?? video.viewCount,
                label: "views",
                color: .white
            )
            
            // Context-specific metadata
            if context != .profileOwn {
                SwiftUI.Button {
                    showingThreadView = true
                    onAction?(.thread(video.threadID ?? video.id))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.7))
                        
                        Text("\(formatCount(videoEngagement?.shareCount ?? 0)) stitches")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.7))
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.2))
                    )
                }
                .buttonStyle(ContextualScaleButtonStyle())
            }
        }
    }
    
    private func metadataItem(icon: String, count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color.opacity(0.7))
            
            Text("\(formatCount(count)) \(label)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
        )
    }
    
    private func engagementButton(
        type: ContextualEngagementType,
        icon: String,
        count: Int,
        color: Color,
        isEngaged: Bool = false
    ) -> some View {
        SwiftUI.Button {
            Task {
                await handleEngagement(type: type)
            }
        } label: {
            VStack(spacing: 6) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isEngaged ? color.opacity(0.3) : Color.black.opacity(0.5))
                        .frame(width: 42, height: 42)
                    
                    Circle()
                        .stroke(isEngaged ? color : color.opacity(0.4), lineWidth: isEngaged ? 2 : 1.2)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isEngaged ? color : .white)
                }
                
                // Count
                Text(formatCount(count))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isEngaged ? color : .white)
            }
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var metadataStyleFollowButton: some View {
        SwiftUI.Button {
            Task {
                await handleFollowToggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isFollowing ? .green : .cyan.opacity(0.7))
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isFollowing ? .green : .cyan.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isFollowing ? Color.green.opacity(0.3) : Color.cyan.opacity(0.3), lineWidth: 1)
                    )
            )
            .disabled(isFollowLoading)
            .opacity(isFollowLoading ? 0.6 : 1.0)
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    // MARK: - Methods
    
    private func setupOverlay() {
        // FIXED: Initialize EngagementManager here after engagementCoordinator is available
        if engagementManager == nil {
            engagementManager = EngagementManager(
                videoService: VideoService(),
                userService: userService,
                engagementCoordinator: engagementCoordinator
            )
        }
        
        Task {
            await loadRealUserData()
            await loadEngagementData()
            await trackVideoView()
            await checkUserEngagementStatus()
            if shouldShowFollow {
                await loadFollowState()
            }
        }
    }
    
    /// Load real user data for current display names and profile images
    private func loadRealUserData() async {
        isLoadingUserData = true
        
        print("DEBUG: Loading user data for video creator: \(video.creatorID)")
        
        // Load video creator data
        if let user = try? await userService.getUser(id: video.creatorID) {
            await MainActor.run {
                realCreatorName = user.displayName
                // TODO: Add realCreatorImageURL state variable and set it here
                // realCreatorImageURL = user.profileImageURL
            }
            print("DEBUG: Loaded creator name: \(user.displayName) for video: \(video.title)")
        } else {
            print("DEBUG: Failed to load user for creatorID: \(video.creatorID)")
        }
        
        // Load thread creator data if different
        if let threadVideo = threadVideo, threadVideo.creatorID != video.creatorID {
            if let threadUser = try? await userService.getUser(id: threadVideo.creatorID) {
                await MainActor.run {
                    realThreadCreatorName = threadUser.displayName
                    // TODO: Add realThreadCreatorImageURL state variable and set it here
                    // realThreadCreatorImageURL = threadUser.profileImageURL
                }
                print("DEBUG: Loaded thread creator name: \(threadUser.displayName)")
            }
        }
        
        await MainActor.run {
            isLoadingUserData = false
        }
    }
    
    private func loadEngagementData() async {
        print("ℹ️ CONTEXTUAL OVERLAY: Loading engagement data for video \(video.id)")
        
        do {
            // FIXED: Try to get fresh engagement data from VideoService first
            let freshVideo = try await VideoService().getVideo(id: video.id)
            
            let engagement = VideoEngagement(
                videoID: video.id,
                creatorID: video.creatorID,
                hypeCount: freshVideo.hypeCount,
                coolCount: freshVideo.coolCount,
                shareCount: freshVideo.shareCount,
                replyCount: freshVideo.replyCount,
                viewCount: freshVideo.viewCount,
                lastEngagementAt: freshVideo.lastEngagementAt ?? Date()
            )
            
            await MainActor.run {
                videoEngagement = engagement
            }
            print("✅ CONTEXTUAL OVERLAY: Loaded FRESH engagement data - \(engagement.hypeCount) hypes, \(engagement.coolCount) cools")
            
        } catch {
            print("❌ CONTEXTUAL OVERLAY: Failed to load fresh engagement data - \(error)")
            
            // Fallback to video metadata if fresh fetch fails
            let engagement = VideoEngagement(
                videoID: video.id,
                creatorID: video.creatorID,
                hypeCount: video.hypeCount,
                coolCount: video.coolCount,
                shareCount: video.shareCount,
                replyCount: video.replyCount,
                viewCount: video.viewCount,
                lastEngagementAt: Date()
            )
            
            await MainActor.run {
                videoEngagement = engagement
            }
            
            print("⚠️ CONTEXTUAL OVERLAY: Using fallback engagement data - \(engagement.hypeCount) hypes, \(engagement.coolCount) cools")
        }
    }
    
    private func checkUserEngagementStatus() async {
        print("ℹ️ CONTEXTUAL OVERLAY: Progressive buttons managing engagement state")
    }
    
    private func trackVideoView() async {
        guard let currentUserID = currentUserID else { return }
        
        do {
            try await VideoService().incrementViewCount(
                videoID: video.id,
                userID: currentUserID,
                watchTime: 0
            )
            print("CONTEXTUAL OVERLAY: View tracked for video \(video.id)")
        } catch {
            print("CONTEXTUAL OVERLAY: Failed to track view - \(error)")
        }
    }
    
    private func loadFollowState() async {
        await followManager.loadFollowState(for: video.creatorID)
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .killAllVideoPlayers,
            object: nil,
            queue: .main
        ) { _ in
            print("CONTEXTUAL OVERLAY: Received killAllVideoPlayers notification")
        }
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: .killAllVideoPlayers, object: nil)
    }
    
    // MARK: - Engagement Handling with UI Updates
    
    private func handleEngagement(type: ContextualEngagementType) async {
        guard let currentUserID = currentUserID else { return }
        
        // Notify parent component of engagement action
        onAction?(.engagement(type))
        
        // Convert to EngagementCoordinator InteractionType
        let interactionType: InteractionType
        switch type {
        case .hype:
            interactionType = .hype
            // Show particle effect immediately for responsiveness
            await MainActor.run {
                showingHypeParticles = true
            }
        case .cool:
            interactionType = .cool
            // Show particle effect immediately for responsiveness
            await MainActor.run {
                showingCoolParticles = true
            }
        case .share:
            interactionType = .share
            onAction?(.share)
            return
        case .reply:
            onAction?(.reply)
            return
        case .stitch:
            // CRITICAL: Stop current video and all background videos BEFORE opening recording
            NotificationCenter.default.post(name: .killAllVideoPlayers, object: nil)
            
            // Brief delay to ensure video stops before camera starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingStitchRecording = true
                onAction?(.stitch)
            }
            return
        }
        
        do {
            try await engagementCoordinator.processEngagement(
                videoID: video.id,
                engagementType: interactionType,
                userID: currentUserID,
                userTier: authService.currentUser?.tier ?? UserTier.rookie
            )
            
            // 🔥 KEY FIX: Reload engagement data to refresh UI counts
            await loadEngagementData()
            
            print("✅ CONTEXTUAL OVERLAY: \(type.rawValue) processed and UI updated!")
            
            // Clear particle effects after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if type == .hype {
                        showingHypeParticles = false
                    } else if type == .cool {
                        showingCoolParticles = false
                    }
                }
            }
            
        } catch {
            print("❌ CONTEXTUAL OVERLAY: Engagement failed - \(error)")
            
            // Clear particle effects on error too
            await MainActor.run {
                showingHypeParticles = false
                showingCoolParticles = false
            }
        }
    }
    
    private func handleFollowToggle() async {
        await followManager.toggleFollow(for: video.creatorID)
        
        // Notify parent component
        if followManager.isFollowing(video.creatorID) {
            onAction?(.follow)
        } else {
            onAction?(.unfollow)
        }
    }
    
    // MARK: - Helper Methods
    
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
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return String(count)
        }
    }
}

// MARK: - Supporting Types

enum OverlayContext {
    case homeFeed
    case discovery
    case profileOwn
    case profileOther
}

enum ContextualOverlayAction {
    case profile(String)           // profile(userID)
    case thread(String)            // thread(threadID)
    case engagement(ContextualEngagementType)  // engagement(type)
    case follow                    // follow user
    case unfollow                  // unfollow user
    case share                     // share video
    case reply                     // reply to video
    case stitch                    // stitch video
    case profileManagement         // profile settings
    case more                      // more options menu
    case followToggle              // toggle follow state
    case profileSettings           // profile settings (alias)
}

enum ContextualEngagementType: String {
    case hype
    case cool
    case share
    case reply
    case stitch
}

// MARK: - Button Styles

struct ContextualScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
