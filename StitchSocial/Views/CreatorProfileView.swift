//
//  CreatorProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - External User Profile Display (View-Only)
//  Dependencies: UserService, FollowManager, VideoService (Layer 4-7)
//  Features: Follow/unfollow, share, report, IDENTICAL layout to ProfileView
//  VISUAL PARITY: Hype meter, badges, verification, same layout as ProfileView
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CreatorProfileView: View {
    
    // MARK: - Properties
    
    let userID: String
    
    // MARK: - Dependencies
    
    @StateObject private var followManager = FollowManager()
    private let userService = UserService()
    private let videoService = VideoService()
    
    // MARK: - State
    
    @State private var user: BasicUserInfo?
    @State private var userVideos: [CoreVideoMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // MARK: - Video Player State
    
    @State private var showingVideoPlayer = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var selectedVideoIndex = 0
    
    // MARK: - UI State
    
    @State private var scrollOffset: CGFloat = 0
    @State private var showStickyTabBar = false
    @State private var selectedTab = 0
    @State private var showingShareSheet = false
    @State private var showingReportSheet = false
    @State private var showingFollowingList = false
    @State private var showingFollowersList = false
    @State private var isShowingFullBio = false
    
    // MARK: - Animation State (Matching ProfileView)
    
    @State private var shimmerOffset: CGFloat = 0
    @State private var hypeProgress: CGFloat = 0
    
    // MARK: - Dismiss
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let user = user {
                    profileContent(user: user)
                } else {
                    errorView
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await loadUserProfile()
                    await loadUserVideos()
                    await followManager.loadFollowState(for: userID)
                }
                startAnimations()
            }
            .sheet(isPresented: $showingVideoPlayer) {
                if let selectedVideo = selectedVideo {
                    VideoPlayerView(
                        video: selectedVideo,
                        isActive: true,
                        onEngagement: { engagement in
                            print("Engagement: \(engagement)")
                        }
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let user = user {
                    shareSheet(for: user)
                }
            }
            .sheet(isPresented: $showingReportSheet) {
                if let user = user {
                    reportSheet(for: user)
                }
            }
            .sheet(isPresented: $showingFollowingList) {
                followingListSheet
            }
            .sheet(isPresented: $showingFollowersList) {
                followersListSheet
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            
            Text("Loading Profile...")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Profile Not Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(errorMessage ?? "This profile could not be loaded.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Try Again") {
                Task {
                    await loadUserProfile()
                }
            }
            .foregroundColor(.cyan)
            .padding(.top, 10)
        }
    }
    
    // MARK: - Profile Content
    
    private func profileContent(user: BasicUserInfo) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    optimizedProfileHeader(user: user)
                    tabBarSection
                    videoGridSection
                }
                .background(scrollTracker)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(CreatorScrollOffsetPreferenceKey.self) { value in
                handleScrollChange(value)
            }
            .overlay(alignment: .top) {
                if showStickyTabBar {
                    stickyTabBar
                }
            }
        }
    }
    
    // MARK: - Optimized Profile Header (IDENTICAL to ProfileView)
    
    private func optimizedProfileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
            // Top Navigation
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                
                Spacer()
                
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                
                Button(action: { showingReportSheet = true }) {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Section 1: Profile Image & Basic Info
            HStack(spacing: 16) {
                enhancedProfileImage(user: user)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Name and verification
                    HStack(spacing: 8) {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.red) // RED VERIFIED BADGE
                        }
                    }
                    
                    // Username
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Tier badge
                    tierBadge(user: user)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Section 2: Bio (Full Width) - MATCHING ProfileView
            if shouldShowBio(user: user) {
                VStack(alignment: .leading, spacing: 8) {
                    bioSection(user: user)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            
            // Section 3: PROMINENT HYPE METER (Full Width) - MATCHING ProfileView
            VStack(spacing: 12) {
                hypeMeterSection(user: user)
            }
            .padding(.horizontal, 20)
            
            // Section 4: Stats Row
            statsRow(user: user)
            
            // Section 5: Action Buttons
            actionButtonsRow(user: user)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Enhanced Profile Image (IDENTICAL to ProfileView)
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            // Main profile image with tier-colored border
            AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
                .frame(width: 90, height: 90)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: tierColors(for: user.tier),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
            
            // Stacked badges in top-right corner (MATCHING ProfileView)
            VStack {
                HStack {
                    Spacer()
                    
                    CreatorStackedBadges(
                        badges: getBadgesForUser(user),
                        maxVisible: 3
                    ) {
                        // Badge tap action - could show badge details
                        print("Badges tapped for \(user.username)")
                    }
                    .offset(x: 15, y: -15)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Hype Meter Section (IDENTICAL to ProfileView)
    
    private func hypeMeterSection(user: BasicUserInfo) -> some View {
        let hypeRating = calculateHypeRating(user: user)
        let progress = CGFloat(hypeRating / 100.0)
        
        return VStack(spacing: 8) {
            // Title and percentage
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Hype Rating")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(hypeRating))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Progress bar with shimmer
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 12)
                        .overlay(
                            // Shimmer effect
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.6), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .offset(x: shimmerOffset)
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            print("🔥 HYPE METER SECTION APPEARED: Rating \(Int(hypeRating))%")
            withAnimation(.linear(duration: 2.0)) {
                hypeProgress = progress
            }
        }
    }
    
    // MARK: - Bio Section (MATCHING ProfileView)
    
    private func bioSection(user: BasicUserInfo) -> some View {
        Group {
            if let bio = getBioForUser(user), !bio.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bio)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(isShowingFullBio ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if bio.count > 80 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isShowingFullBio.toggle()
                            }
                        }) {
                            Text(isShowingFullBio ? "Show Less" : "Show More")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Tier Badge (MATCHING ProfileView)
    
    private func tierBadge(user: BasicUserInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tierIcon(for: user.tier))
                .font(.caption)
                .foregroundColor(tierColors(for: user.tier)[0])
            
            Text(user.tier.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(tierColors(for: user.tier)[0])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tierColors(for: user.tier)[0].opacity(0.2))
        )
    }
    
    // MARK: - Stats Row
    
    private func statsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 30) {
            CreatorStatView(title: "Videos", count: userVideos.count)
            
            Button(action: { showingFollowersList = true }) {
                CreatorStatView(title: "Followers", count: 0) // TODO: Load actual follower count
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showingFollowingList = true }) {
                CreatorStatView(title: "Following", count: 0) // TODO: Load actual following count
            }
            .buttonStyle(PlainButtonStyle())
            
            CreatorStatView(title: "Clout", count: user.clout)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Action Buttons Row (MATCHING ProfileView)
    
    private func actionButtonsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 12) {
            // Follow/Following Button
            Button(action: {
                Task {
                    await followManager.toggleFollow(for: user.id)
                }
            }) {
                HStack(spacing: 6) {
                    if followManager.isLoading(user.id) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(followManager.isFollowing(user.id) ? .black : .white)
                    } else {
                        Text(followManager.isFollowing(user.id) ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(followManager.isFollowing(user.id) ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(followManager.isFollowing(user.id) ? Color.white : Color.cyan)
                .cornerRadius(8)
            }
            .disabled(followManager.isLoading(user.id))
            
            // Message Button
            Button(action: {
                // TODO: Implement messaging
                print("Message user: \(user.id)")
            }) {
                Text("Message")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.gray.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Bar Section
    
    private var tabBarSection: some View {
        HStack(spacing: 0) {
            CreatorTabButton(
                title: "Videos",
                count: userVideos.count,
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            
            CreatorTabButton(
                title: "Threads",
                count: getThreadCount(),
                isSelected: selectedTab == 1
            ) {
                selectedTab = 1
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.black)
    }
    
    // MARK: - Sticky Tab Bar
    
    private var stickyTabBar: some View {
        VStack(spacing: 0) {
            CreatorBlurView(style: .dark)
                .frame(height: 80)
                .overlay(
                    HStack(spacing: 0) {
                        CreatorTabButton(
                            title: "Videos",
                            count: userVideos.count,
                            isSelected: selectedTab == 0
                        ) {
                            selectedTab = 0
                        }
                        
                        CreatorTabButton(
                            title: "Threads",
                            count: getThreadCount(),
                            isSelected: selectedTab == 1
                        ) {
                            selectedTab = 1
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                )
        }
        .opacity(showStickyTabBar ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showStickyTabBar)
    }
    
    // MARK: - Video Grid Section
    
    private var videoGridSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(filteredVideos(), id: \.id) { video in
                Button(action: {
                    selectedVideo = video
                    selectedVideoIndex = filteredVideos().firstIndex(where: { $0.id == video.id }) ?? 0
                    showingVideoPlayer = true
                }) {
                    CreatorVideoThumbnailView(video: video)
                        .aspectRatio(9/16, contentMode: .fill)
                        .clipped()
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Helper Methods
    
    private func loadUserProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            user = try await userService.getUser(id: userID)
            isLoading = false
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func loadUserVideos() async {
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            
            // Load user videos directly from Firestore (same approach as ProfileViewModel)
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: userID)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 50)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { doc -> CoreVideoMetadata? in
                let data = doc.data()
                return CoreVideoMetadata(
                    id: doc.documentID,
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
                    temperature: data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral",
                    qualityScore: data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50,
                    engagementRatio: (data["engagementRatio"] as? Double) ?? 0.0,
                    velocityScore: (data["velocityScore"] as? Double) ?? 0.0,
                    trendingScore: (data["trendingScore"] as? Double) ?? 0.0,
                    duration: data[FirebaseSchema.VideoDocument.duration] as? Double ?? 0.0,
                    aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? (9.0/16.0),
                    fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
                    discoverabilityScore: (data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double) ?? 0.5,
                    isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
                    lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            await MainActor.run {
                self.userVideos = videos
            }
            
            print("CREATOR PROFILE: Loaded \(videos.count) videos for user \(userID)")
            
        } catch {
            print("Failed to load user videos: \(error)")
        }
    }
    
    private func startAnimations() {
        // Start shimmer animation
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 300
        }
    }
    
    // MARK: - Hype Rating Calculation (MATCHING ProfileView)
    
    private func calculateHypeRating(user: BasicUserInfo) -> Double {
        // Use same calculation as ProfileView
        let engagementScore: Double = {
            guard !userVideos.isEmpty else { return 0.0 }
            
            let totalHypes = userVideos.reduce(0) { $0 + $1.hypeCount }
            let totalCools = userVideos.reduce(0) { $0 + $1.coolCount }
            let totalViews = userVideos.reduce(0) { $0 + $1.viewCount }
            let totalReplies = userVideos.reduce(0) { $0 + $1.replyCount }
            
            let totalReactions = totalHypes + totalCools
            let engagementRatio = totalReactions > 0 ? Double(totalHypes) / Double(totalReactions) : 0.5
            let engagementPoints = engagementRatio * 10.0 * 1.5
            
            let viewEngagementRatio = totalViews > 0 ? Double(totalReactions) / Double(totalViews) : 0.0
            let viewPoints = min(10.0, viewEngagementRatio * 1000.0)
            
            let replyBonus = min(5.0, Double(totalReplies) / 60.0 * 5.0)
            
            return engagementPoints + viewPoints + replyBonus
        }()
        
        let activityScore: Double = {
            let recentVideos = userVideos.filter {
                Date().timeIntervalSince($0.createdAt) < 24 * 3600
            }
            return min(15.0, Double(recentVideos.count) * 2.5)
        }()
        
        let cloutBonus = min(10.0, Double(user.clout) / 1000.0 * 10.0)
        let verificationBonus: Double = user.isVerified ? 5.0 : 0.0
        
        let baseRating = tierBaseRating(for: user.tier)
        let bonusPoints = engagementScore + activityScore + cloutBonus + verificationBonus
        let finalRating = (baseRating / 100.0 * 50.0) + bonusPoints
        
        return min(100.0, max(0.0, finalRating))
    }
    
    // MARK: - Badge System (MATCHING ProfileView)
    
    private func getBadgesForUser(_ user: BasicUserInfo) -> [CreatorBadgeInfo] {
        var badges: [CreatorBadgeInfo] = []
        
        // Verification badge
        if user.isVerified {
            badges.append(CreatorBadgeInfo(
                id: "verified",
                iconName: "checkmark.seal.fill",
                colors: [.cyan, .blue],
                title: "Verified"
            ))
        }
        
        // Tier badges
        if let crownBadge = user.tier.crownBadge {
            badges.append(CreatorBadgeInfo(
                id: "tier",
                iconName: "crown.fill",
                colors: tierColors(for: user.tier),
                title: user.tier.displayName
            ))
        }
        
        // Special user badges based on email (if available)
        // TODO: Implement special user lookup
        
        return badges
    }
    
    private func shouldShowBio(user: BasicUserInfo) -> Bool {
        return getBioForUser(user) != nil
    }
    
    private func getBioForUser(_ user: BasicUserInfo) -> String? {
        // Generate contextual bio for special users
        if user.isVerified {
            return generateContextualBio(for: user)
        }
        
        if user.tier.isFounderTier {
            return generateSampleBio(for: user)
        }
        
        return nil
    }
    
    private func generateContextualBio(for user: BasicUserInfo) -> String? {
        switch user.tier {
        case .founder:
            return "Founder of Stitch Social 🎬 | Building the future of social video"
        case .coFounder:
            return "Co-Founder of Stitch Social 🎬 | Creating authentic connections"
        case .topCreator:
            return "Top Creator ⭐ | Inspiring millions through video storytelling"
        case .legendary:
            return "Legendary Creator 👑 | Pushing the boundaries of social media"
        default:
            return "Verified Creator ✓ | Sharing authentic moments and stories"
        }
    }
    
    private func generateSampleBio(for user: BasicUserInfo) -> String? {
        return "Welcome to my profile! Check out my latest videos and join the conversation."
    }
    
    private func tierBaseRating(for tier: UserTier) -> Double {
        switch tier {
        case .rookie: return 10.0
        case .rising: return 25.0
        case .veteran: return 40.0
        case .influencer: return 55.0
        case .elite: return 70.0
        case .partner: return 80.0
        case .legendary: return 90.0
        case .topCreator: return 95.0
        case .founder, .coFounder: return 100.0
        }
    }
    
    private func filteredVideos() -> [CoreVideoMetadata] {
        if selectedTab == 0 {
            // All videos
            return userVideos
        } else {
            // Thread starter videos only
            return userVideos.filter { $0.replyToVideoID == nil }
        }
    }
    
    private func getThreadCount() -> Int {
        return userVideos.filter { $0.replyToVideoID == nil }.count
    }
    
    private func handleScrollChange(_ offset: CGFloat) {
        scrollOffset = offset
        
        // Show sticky tab bar when scrolled past header
        let shouldShowSticky = offset > 200
        if shouldShowSticky != showStickyTabBar {
            showStickyTabBar = shouldShowSticky
        }
    }
    
    private func tierColors(for tier: UserTier) -> [Color] {
        switch tier {
        case .rookie: return [.green, .mint]
        case .rising: return [.blue, .cyan]
        case .veteran: return [.purple, .pink]
        case .influencer: return [.orange, .yellow]
        case .elite: return [.red, .orange]
        case .partner: return [.yellow, .orange]
        case .legendary: return [.red, .purple]
        case .topCreator: return [Color(red: 1.0, green: 0.84, blue: 0.0), .yellow]
        case .founder: return [.red, .orange]
        case .coFounder: return [Color(red: 1.0, green: 0.84, blue: 0.0), .orange]
        }
    }
    
    private func tierIcon(for tier: UserTier) -> String {
        switch tier {
        case .rookie: return "leaf.fill"
        case .rising: return "arrow.up.circle.fill"
        case .veteran: return "star.fill"
        case .influencer: return "flame.fill"
        case .elite: return "crown.fill"
        case .partner: return "handshake.fill"
        case .legendary: return "trophy.fill"
        case .topCreator: return "diamond.fill"
        case .founder: return "diamond.fill"
        case .coFounder: return "diamond.fill"
        }
    }
    
    // MARK: - Scroll Tracker
    
    private var scrollTracker: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CreatorScrollOffsetPreferenceKey.self,
                value: geometry.frame(in: .named("scroll")).minY
            )
        }
    }
    
    // MARK: - Sheet Views
    
    private func shareSheet(for user: BasicUserInfo) -> some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Share Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text("Share @\(user.username)'s profile with others")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                // Share options would go here
                Button("Copy Link") {
                    // TODO: Implement copy profile link
                    showingShareSheet = false
                }
                .foregroundColor(.cyan)
                .padding()
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingShareSheet = false }
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func reportSheet(for user: BasicUserInfo) -> some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Report User")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text("Help us understand what's happening")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                // Report options would go here
                VStack(spacing: 15) {
                    CreatorReportOptionButton(title: "Spam", icon: "exclamationmark.triangle")
                    CreatorReportOptionButton(title: "Inappropriate Content", icon: "eye.slash")
                    CreatorReportOptionButton(title: "Harassment", icon: "person.badge.minus")
                    CreatorReportOptionButton(title: "Other", icon: "ellipsis.circle")
                }
                .padding()
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showingReportSheet = false }
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var followingListSheet: some View {
        NavigationView {
            CreatorUserListView(
                title: "Following",
                users: [], // TODO: Load following list
                isLoading: false
            )
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowingList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
    
    private var followersListSheet: some View {
        NavigationView {
            CreatorUserListView(
                title: "Followers",
                users: [], // TODO: Load followers list
                isLoading: false
            )
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowersList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
}

// MARK: - Supporting Views (RENAMED to avoid conflicts)

struct CreatorStatView: View {
    let title: String
    let count: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text(formatCount(count))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
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

struct CreatorTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .gray)
                    
                    Text("(\(count))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Rectangle()
                    .fill(isSelected ? Color.cyan : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CreatorVideoThumbnailView: View {
    let video: CoreVideoMetadata
    
    var body: some View {
        AsyncThumbnailView.videoThumbnail(url: video.thumbnailURL)
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        // View count overlay
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                            Text(formatCount(video.viewCount))
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)
                    }
                }
            )
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

struct CreatorReportOptionButton: View {
    let title: String
    let icon: String
    
    var body: some View {
        Button(action: {
            // TODO: Handle report option selection
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(width: 30)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct CreatorUserListView: View {
    let title: String
    let users: [BasicUserInfo]
    let isLoading: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if users.isEmpty {
                VStack {
                    Text("No \(title)")
                        .foregroundColor(.white)
                }
            } else {
                ScrollView {
                    LazyVStack {
                        ForEach(users, id: \.id) { user in
                            CreatorUserRowView(user: user)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct CreatorUserRowView: View {
    let user: BasicUserInfo
    
    var body: some View {
        HStack {
            AsyncThumbnailView.avatar(url: user.profileImageURL ?? "")
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            VStack(alignment: .leading) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Creator Stacked Badges Component

struct CreatorStackedBadges: View {
    let badges: [CreatorBadgeInfo]
    let maxVisible: Int
    let onTap: () -> Void
    
    init(badges: [CreatorBadgeInfo] = [], maxVisible: Int = 3, onTap: @escaping () -> Void = {}) {
        self.badges = badges
        self.maxVisible = maxVisible
        self.onTap = onTap
    }
    
    var body: some View {
        ZStack {
            // Default badges if none provided
            if badges.isEmpty {
                defaultBadgeStack
            } else {
                userBadgeStack
            }
        }
        .onTapGesture {
            onTap()
        }
    }
    
    private var defaultBadgeStack: some View {
        ZStack {
            // Badge 3 (back)
            CreatorBadgeCircle(
                gradient: [.blue, .purple],
                icon: "star.fill",
                offset: CGSize(width: 16, height: 16)
            )
            
            // Badge 2 (middle)
            CreatorBadgeCircle(
                gradient: [.cyan, .blue],
                icon: "checkmark",
                offset: CGSize(width: 8, height: 8)
            )
            
            // Badge 1 (front)
            CreatorBadgeCircle(
                gradient: [.yellow, .orange],
                icon: "crown.fill",
                offset: .zero
            )
        }
    }
    
    private var userBadgeStack: some View {
        ZStack {
            ForEach(Array(badges.prefix(maxVisible).enumerated()), id: \.element.id) { index, badge in
                CreatorBadgeCircle(
                    gradient: badge.colors,
                    icon: badge.iconName,
                    offset: CGSize(width: CGFloat(index * 8), height: CGFloat(index * 8))
                )
                .zIndex(Double(maxVisible - index))
            }
        }
    }
}

struct CreatorBadgeCircle: View {
    let gradient: [Color]
    let icon: String
    let offset: CGSize
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .bold))
            )
            .offset(offset)
            .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)
    }
}

struct CreatorBadgeInfo {
    let id: String
    let iconName: String
    let colors: [Color]
    let title: String
}

struct CreatorScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CreatorBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
