//
//  ContextualVideoOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Universal Contextual Video Overlay with Fixed Engagement Updates
//  Dependencies: EngagementService, UserService, AuthService, FollowManager
//  Features: Context-aware design, real-time UI updates, proper engagement flow
//

import SwiftUI

/// Universal overlay that adapts to different viewing contexts with HomeFeedOverlay design
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
    @State private var showingProfileSheet = false
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
    
    private var shouldShowEngagement: Bool {
        switch context {
        case .homeFeed, .discovery, .profileOther:
            return !isUserVideo
        case .profileOwn:
            return false
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
    
    // Dynamic thread position indicator showing current/total format
    private var threadIndicatorText: String {
        // This would need to be passed in from parent component showing current position
        // For now showing placeholder - parent should pass currentPosition and totalCount
        let currentPosition = 1 // TODO: Pass from parent component
        let totalCount = video.conversationDepth + 1 // This is just fallback
        return "\(currentPosition)/\(totalCount)"
    }
    
    private var hasMultipleVideos: Bool {
        // This should be determined by parent component
        return video.conversationDepth > 0 // Placeholder logic
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
                // Top Section
                VStack {
                    topSection
                    Spacer()
                }
                
                // Bottom Section - Moved down closer to tab bar
                VStack {
                    Spacer()
                    bottomSection
                        .padding(.bottom, geometry.size.height * 0.10)
                }
                
                // Right Side Engagement - Smaller and more compact
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        engagementSection
                            .padding(.bottom, geometry.size.height * 0.11)
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
        .sheet(isPresented: $showingProfileSheet) {
            if let userID = selectedUserID {
                CreatorProfileView(userID: userID)
            }
        }
        .sheet(isPresented: $showingThreadView) {
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                // Thread Creator (5% bigger)
                if context != .profileOwn {
                    creatorPill(
                        creator: threadCreator,
                        isThread: true,
                        colors: [.blue, .purple]
                    )
                    .scaleEffect(0.95) // 5% smaller instead of 10%
                }
                
                // Content Indicators
                HStack(spacing: 8) {
                    unifiedThreadIndicator
                    contextSpecificIndicator
                }
            }
            
            Spacer()
            
            // Context-specific top right
            topRightSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }
    
    // MARK: - Bottom Section
    
    private var bottomSection: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // Current Creator (if different or if own profile)
                if context == .profileOwn || video.creatorID != threadVideo?.creatorID {
                    creatorPill(
                        creator: video,
                        isThread: context == .profileOwn,
                        colors: context == .profileOwn ? [.purple, .pink] : [.cyan, .blue]
                    )
                }
                
                // Video Title - FIXED: Removed bubble/background
                if !video.title.isEmpty {
                    videoTitleView
                }
                
                // Metadata Row
                HStack(spacing: 12) {
                    metadataRow
                    
                    // Follow button next to stitches - same size and style
                    if shouldShowFollow {
                        metadataStyleFollowButton
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
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
    
    // MARK: - Engagement Section
    
    private var engagementSection: some View {
        VStack(spacing: 12) {
            if shouldShowEngagement {
                // Progressive Hype Button
                VStack(spacing: 6) {
                    ProgressiveHypeButton(
                        videoID: video.id,
                        currentHypeCount: videoEngagement?.hypeCount ?? 0,
                        onProgressiveTap: {
                            Task {
                                await handleEngagement(type: .hype)
                            }
                        },
                        engagementCoordinator: engagementCoordinator
                    )
                    
                    Text(formatCount(videoEngagement?.hypeCount ?? 0))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
                
                // Progressive Cool Button
                VStack(spacing: 6) {
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
                    
                    Text(formatCount(videoEngagement?.coolCount ?? 0))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
                
                // Reply button (only if it can reply)
                if canReply {
                    engagementButton(
                        type: .reply,
                        icon: "arrowshape.turn.up.left.fill",
                        count: videoEngagement?.replyCount ?? 0,
                        color: .green
                    )
                }
                
                // Share button (always show, positioned under reply if reply exists)
                engagementButton(
                    type: .share,
                    icon: "paperplane.fill",
                    count: videoEngagement?.shareCount ?? 0,
                    color: .purple
                )
            }
            
            // Profile management for own content
            if context == .profileOwn {
                profileManagementButton
            }
            
            // Thread View
            threadButton
            
            // Stitch
            engagementButton(
                type: .stitch,
                icon: "plus.rectangle.on.rectangle",
                count: 0,
                color: .orange
            )
        }
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
            selectedUserID = creator.creatorID
            showingProfileSheet = true
            onAction?(.profile(creator.creatorID))
        } label: {
            HStack(spacing: isThread ? 8 : 6) {
                // Avatar with subtle glow
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: isThread ? 28 : 22, height: isThread ? 28 : 22)
                    
                    Text(displayName.prefix(2).uppercased())
                        .font(.system(size: isThread ? 12 : 9, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Name with tier indicator
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: isThread ? 14 : 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        tierBadge(isThread: isThread)
                    }
                    
                    if isThread {
                        Text("Thread")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(colors[0].opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, isThread ? 12 : 8)
            .padding(.vertical, isThread ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                            .stroke(
                                LinearGradient(colors: colors.map { $0.opacity(0.8) },
                                             startPoint: .leading,
                                             endPoint: .trailing),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func tierBadge(isThread: Bool) -> some View {
        Text("★")
            .font(.system(size: isThread ? 10 : 8, weight: .bold))
            .foregroundColor(.yellow)
    }
    
    // Dynamic thread position indicator with current/total format
    private var unifiedThreadIndicator: some View {
        HStack(spacing: 0) {
            // Current position number (purple for thread, orange for children)
            Text("\(1)") // TODO: Replace with actual currentPosition from parent
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.purple) // Purple for thread position
            
            Text("/")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
            
            // Total count: orange if multiple videos, purple if standalone
            Text("\(video.conversationDepth + 1)") // TODO: Replace with actual totalCount
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(hasMultipleVideos ? .orange : .purple)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var metadataStyleFollowButton: some View {
        SwiftUI.Button {
            Task {
                await handleFollowToggle()
            }
        } label: {
            HStack(spacing: 4) {
                if isFollowLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.gray)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isFollowing ? .green.opacity(0.7) : .blue.opacity(0.7))
                }
                
                Text(isFollowLoading ? "Loading" : (isFollowing ? "Following" : "Follow"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isFollowing ? .green.opacity(0.7) : .blue.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.2))
            )
        }
        .disabled(isFollowLoading)
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    @ViewBuilder
    private var contextSpecificIndicator: some View {
        if video.temperature != "neutral" {
            HStack(spacing: 4) {
                Image(systemName: "thermometer")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(temperatureColor)
                
                Text(video.temperature.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(temperatureColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(temperatureColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(temperatureColor.opacity(0.5), lineWidth: 1)
                    )
            )
        } else {
            EmptyView()
        }
    }
    
    private var compactFollowButton: some View {
        SwiftUI.Button {
            Task {
                await handleFollowToggle()
            }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isFollowing ? .purple : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFollowing ? Color.purple.opacity(0.2) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isFollowing ? .purple : Color.white.opacity(0.4), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var followButton: some View {
        SwiftUI.Button {
            Task {
                await handleFollowToggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isFollowing ? .green : .white)
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isFollowing ? .green : .white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFollowing ? Color.green.opacity(0.2) : Color.blue.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isFollowing ? .green : .blue, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
    
    private var profileManagementButton: some View {
        SwiftUI.Button {
            onAction?(.profileManagement)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
                
                Text("Settings")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.purple.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.purple, lineWidth: 1.5)
                    )
            )
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
    
    // MARK: - FIXED: Video Title View - No Bubble/Background
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
    
    // MARK: - Methods
    
    private func setupOverlay() {
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
    
    /// Load real user data for current display names
    private func loadRealUserData() async {
        isLoadingUserData = true
        
        print("DEBUG: Loading user data for video creator: \(video.creatorID)")
        
        // Load video creator data
        if let user = try? await userService.getUser(id: video.creatorID) {
            await MainActor.run {
                realCreatorName = user.displayName
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
                }
                print("DEBUG: Loaded thread creator name: \(threadUser.displayName)")
            }
        }
        
        await MainActor.run {
            isLoadingUserData = false
        }
    }
    
    private func loadEngagementData() async {
        // Get fresh video data from database
        if let updatedVideo = try? await VideoService().getVideo(id: video.id) {
            let engagement = VideoEngagement(
                videoID: updatedVideo.id,
                creatorID: updatedVideo.creatorID,
                hypeCount: updatedVideo.hypeCount,
                coolCount: updatedVideo.coolCount,
                shareCount: updatedVideo.shareCount,
                replyCount: updatedVideo.replyCount,
                viewCount: updatedVideo.viewCount,
                lastEngagementAt: Date()
            )
            
            await MainActor.run {
                videoEngagement = engagement
            }
            
            print("✅ CONTEXTUAL OVERLAY: Loaded fresh engagement data - \(engagement.hypeCount) hypes, \(engagement.coolCount) cools")
        } else {
            // Fallback to original video data if database fetch fails
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
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct ContextualVideoOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ContextualVideoOverlay(
                video: CoreVideoMetadata(
                    id: "1",
                    title: "Sample Video",
                    videoURL: "url",
                    thumbnailURL: "thumb",
                    creatorID: "creator1",
                    creatorName: "testuser",
                    createdAt: Date(),
                    threadID: nil,
                    replyToVideoID: nil,
                    conversationDepth: 0,
                    viewCount: 1234,
                    hypeCount: 89,
                    coolCount: 12,
                    replyCount: 23,
                    shareCount: 45,
                    temperature: "hot",
                    qualityScore: 85,
                    engagementRatio: 0.88,
                    velocityScore: 0.75,
                    trendingScore: 0.82,
                    duration: 30.0,
                    aspectRatio: 9.0/16.0,
                    fileSize: 5242880,
                    discoverabilityScore: 0.79,
                    isPromoted: false,
                    lastEngagementAt: Date()
                ),
                context: .homeFeed,
                currentUserID: "user123",
                threadVideo: nil,
                isVisible: true,
                onAction: { _ in }
            )
        }
    }
}
