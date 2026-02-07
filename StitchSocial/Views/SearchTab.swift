//
//  SearchTab.swift
//  StitchSocial
//
//  Layer 8: Views - Modern Search Interface with People You May Know
//  REDESIGNED: Dark modern theme matching TaggedUsersRow styling
//  FIXED: Proper FollowManager integration with persistent state
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - User Presentation for Item-Based Sheet

struct UserPresentation: Identifiable {
    let id: String
}


enum SearchTab: String, CaseIterable {
    case all = "all"
    case users = "users"
    case videos = "videos"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .users: return "Users"
        case .videos: return "Videos"
        }
    }
}

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var userResults: [BasicUserInfo] = []
    @Published var videoResults: [CoreVideoMetadata] = []
    @Published var selectedTab: SearchTab = .all
    @Published var hasSearched = false
    @Published var selectedUser: BasicUserInfo?
    @Published var suggestedUsers: [BasicUserInfo] = []
    @Published var isLoadingSuggestions = false
    @AppStorage("recentUserIDs") private var recentUserIDsData = ""
    @Published var recentUsers: [BasicUserInfo] = []
    
    // MARK: - Hashtag State
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var isLoadingHashtags = false
    @Published var selectedHashtag: TrendingHashtag?
    @Published var hashtagVideos: [CoreVideoMetadata] = []
    
    private let hashtagService = HashtagService()
    
    var recentUserIDs: [String] {
        recentUserIDsData.split(separator: "|").map(String.init).reversed()
    }
    
    func addRecentUser(_ user: BasicUserInfo) {
        var ids = recentUserIDs
        ids.removeAll { $0 == user.id }
        ids.insert(user.id, at: 0)
        recentUserIDsData = ids.prefix(10).joined(separator: "|")
        loadRecentUsers()
    }
    
    func clearRecentSearches() {
        recentUserIDsData = ""
        recentUsers = []
    }
    
    func loadRecentUsers() {
        recentUsers = suggestedUsers.filter { user in
            recentUserIDs.contains(user.id)
        }.sorted { id1, id2 in
            guard let idx1 = recentUserIDs.firstIndex(of: id1.id),
                  let idx2 = recentUserIDs.firstIndex(of: id2.id) else { return false }
            return idx1 < idx2
        }
    }
    
    // FIXED: Use shared FollowManager instance
    let followManager = FollowManager.shared
    
    private let searchService = SearchService()
    private var searchTask: Task<Void, Never>?
    
    init() {
        Task {
            await loadSuggestedUsers()
            await loadTrendingHashtags()
        }
    }
    
    // MARK: - Hashtag Methods
    
    func loadTrendingHashtags() async {
        isLoadingHashtags = true
        await hashtagService.loadTrendingHashtags(limit: 15)
        trendingHashtags = hashtagService.trendingHashtags
        isLoadingHashtags = false
    }
    
    func selectHashtag(_ hashtag: TrendingHashtag) async {
        selectedHashtag = hashtag
        isSearching = true
        
        do {
            let result = try await hashtagService.getVideosForHashtag(hashtag.tag, limit: 30)
            hashtagVideos = result.videos
        } catch {
            print("❌ SEARCH: Failed to load hashtag videos: \(error)")
        }
        
        isSearching = false
    }
    
    func clearHashtagSelection() {
        selectedHashtag = nil
        hashtagVideos = []
    }
    
    func performSearch() {
        guard !searchText.isEmpty else {
            clearResults()
            return
        }
        
        searchTask?.cancel()
        
        searchTask = Task {
            await MainActor.run {
                isSearching = true
                hasSearched = true
            }
            
            do {
                let users = try await searchService.searchUsers(query: searchText, limit: 30)
                let videos = try await searchService.searchVideos(query: searchText, limit: 20)
                
                await MainActor.run {
                    self.userResults = users
                    self.videoResults = videos
                    self.isSearching = false
                }
                
                // Load follow states for search results
                await followManager.loadFollowStatesForUsers(users)
                
            } catch {
                await MainActor.run {
                    self.isSearching = false
                    print("âŒ SEARCH: Search failed: \(error)")
                }
            }
        }
    }
    
    func loadSuggestedUsers() async {
        await MainActor.run {
            isLoadingSuggestions = true
        }
        
        do {
            // Use the new personalized suggestions from SearchService
            let users = try await searchService.getSuggestedUsers(limit: 20)
            
            await MainActor.run {
                suggestedUsers = users
                isLoadingSuggestions = false
                loadRecentUsers()
            }
            
            // Load follow states for suggested users
            await followManager.loadFollowStatesForUsers(users)
            print("âœ… SEARCH: Loaded \(users.count) personalized suggestions")
            
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
            }
            print("âŒ SEARCH: Failed to load suggestions: \(error)")
        }
    }
    

    func clearResults() {
        userResults = []
        videoResults = []
        hasSearched = false
    }
}

// MARK: - Hashtag Presentation for Navigation

struct HashtagPresentation: Identifiable {
    let id: String
    let hashtag: TrendingHashtag
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @Environment(\.dismiss) private var dismiss
    
    // Hashtag navigation state
    @State private var selectedHashtagPresentation: HashtagPresentation?
    
    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color.black, Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Search")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Invisible spacer for balance
                    Color.clear
                        .frame(width: 37, height: 37)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Modern search bar
                searchBar
                    .padding(.top, 4)
                
                // Tab selector
                if viewModel.hasSearched {
                    tabSelector
                }
                
                // Content
                if viewModel.searchText.isEmpty && !viewModel.hasSearched {
                    emptyState
                } else {
                    resultsSection
                }
            }
        }
        .sheet(item: Binding(
            get: { viewModel.selectedUser.map { UserPresentation(id: $0.id) } },
            set: { _ in viewModel.selectedUser = nil }
        )) { presentation in
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService,
                viewingUserID: presentation.id
            )
        }
        .sheet(item: $selectedHashtagPresentation) { presentation in
            HashtagView(initialHashtag: presentation.hashtag)
        }
        .onAppear {
            // Load follow states on appear
            Task {
                await viewModel.followManager.refreshFollowStates(
                    for: viewModel.suggestedUsers.map { $0.id }
                )
            }
        }
    }
    
    // MARK: - Modern Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray)
            
            TextField("Search users...", text: $viewModel.searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: viewModel.searchText) { _, newValue in
                    if newValue.isEmpty {
                        viewModel.clearResults()
                    } else {
                        viewModel.performSearch()
                    }
                }
            
            if !viewModel.searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray, Color(white: 0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(viewModel.selectedTab == tab ? .cyan : .gray)
                        
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    // MARK: - Results Section
    
    private var resultsSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.isSearching {
                    loadingView
                        .padding(.top, 40)
                } else {
                    if viewModel.selectedTab == .all || viewModel.selectedTab == .users {
                        userResultsSection
                    }
                    
                    if viewModel.selectedTab == .all || viewModel.selectedTab == .videos {
                        videoResultsSection
                    }
                    
                    if viewModel.hasSearched && viewModel.userResults.isEmpty && viewModel.videoResults.isEmpty {
                        noResultsView
                    }
                }
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - User Results with Modern Styling
    
    private var userResultsSection: some View {
        ForEach(viewModel.userResults, id: \.id) { user in
            ModernUserRow(
                user: user,
                followManager: viewModel.followManager,
                onTap: {
                    viewModel.addRecentUser(user)
                    viewModel.selectedUser = user
                }
            )
        }
    }
    
    private var videoResultsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(viewModel.videoResults, id: \.id) { video in
                VideoSearchCardView(video: video)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Empty State with Suggestions
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.2), Color.purple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                        
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 56, weight: .thin))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text("Discover Amazing Creators")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Find people to follow and connect with")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 40)
                
                
                // Recent Users section
                if !viewModel.recentUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            Text("Recently Viewed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                viewModel.clearRecentSearches()
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.recentUsers.prefix(5), id: \.id) { user in
                                ModernUserRow(
                                    user: user,
                                    followManager: viewModel.followManager,
                                    onTap: {
                                        viewModel.addRecentUser(user)
                                        viewModel.selectedUser = user
                                    }
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                
                // MARK: - Trending Hashtags Section
                if !viewModel.trendingHashtags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "number")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.pink)
                                
                                Text("Trending Hashtags")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        // Horizontal scrolling hashtag chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.trendingHashtags) { hashtag in
                                    TrendingHashtagChip(hashtag: hashtag) {
                                        selectedHashtagPresentation = HashtagPresentation(
                                            id: hashtag.id,
                                            hashtag: hashtag
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 8)
                } else if viewModel.isLoadingHashtags {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                        Text("Loading hashtags...")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                // People You May Know section
                if !viewModel.suggestedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.cyan)
                                
                                Text("People You May Know")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.suggestedUsers, id: \.id) { user in
                                ModernUserRow(
                                    user: user,
                                    followManager: viewModel.followManager,
                                    onTap: {
                                        viewModel.addRecentUser(user)
                                        viewModel.selectedUser = user
                                    }
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                } else if viewModel.isLoadingSuggestions {
                    loadingView
                }
                
                Spacer(minLength: 40)
            }
        }
    }
    
    // MARK: - State Views
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(1.5)
            }
            
            Text("Searching...")
                .font(.system(size: 15))
                .foregroundColor(.gray)
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .blur(radius: 15)
                
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.orange.opacity(0.8))
            }
            
            VStack(spacing: 8) {
                Text("No Results")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Try a different search term")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - Modern User Row Component

struct ModernUserRow: View {
    let user: BasicUserInfo
    @ObservedObject var followManager: FollowManager
    let onTap: () -> Void
    
    @State private var currentUserID = Auth.auth().currentUser?.uid
    @State private var isPressed = false
    
    private var isCurrentUser: Bool {
        currentUserID == user.id
    }
    
    private var isFollowing: Bool {
        followManager.isFollowing(user.id)
    }
    
    private var isLoading: Bool {
        followManager.isLoading(user.id)
    }
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                avatarView
                userInfoView
                Spacer()
                followButtonView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(rowBackground)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
        .padding(.horizontal, 16)
        .id("\(user.id)_\(isFollowing ? "following" : "not_following")")
    }
    
    // MARK: - Avatar View
    
    private var avatarView: some View {
        AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            avatarPlaceholder
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(avatarBorder)
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.3), Color(white: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            )
    }
    
    private var avatarBorder: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: tierColors(for: user.tier),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
    }
    
    // MARK: - User Info View
    
    private var userInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if user.isVerified {
                    verifiedBadge
                }
            }
            
            Text("@\(user.username)")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .lineLimit(1)
            
            tierBadgeView
        }
    }
    
    private var verifiedBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 14))
            .foregroundStyle(.cyan, .cyan.opacity(0.3))
    }
    
    private var tierBadgeView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tierColor(user.tier))
                .frame(width: 8, height: 8)
            
            Text(user.tier.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tierColor(user.tier))
        }
    }
    
    // MARK: - Row Background
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    // MARK: - Follow Button View
    
    @ViewBuilder
    private var followButtonView: some View {
        if !isCurrentUser {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(0.8)
                    .frame(width: 90, height: 36)
            } else {
                Button {
                    Task {
                        await followManager.toggleFollow(for: user.id)
                    }
                } label: {
                    followButtonLabel
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var followButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 12, weight: .bold))
            
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(isFollowing ? .gray : .white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isFollowing ? Color.white.opacity(0.1) : Color.cyan)
        )
        .overlay(
            Capsule()
                .stroke(isFollowing ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private func tierColors(for tier: UserTier) -> [Color] {
        switch tier {
        case .founder, .coFounder: return [.yellow, .orange]
        case .topCreator: return [.cyan, .blue]
        case .legendary: return [.red, .orange]
        case .partner: return [.green, .mint]
        case .elite: return [.purple, .pink]
        case .ambassador: return [.indigo, .purple]
        case .influencer: return [.orange, .red]
        case .veteran: return [.blue, .cyan]
        case .rising: return [.green, .yellow]
        case .rookie: return [.gray, .white]
        }
    }
    
    private func tierColor(_ tier: UserTier) -> Color {
        tierColors(for: tier).first ?? .gray
    }
}

// MARK: - Video Search Card (Keep existing implementation)

struct VideoSearchCardView: View {
    let video: CoreVideoMetadata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video thumbnail
            AsyncThumbnailView(url: video.thumbnailURL ?? "")
                .aspectRatio(9/16, contentMode: .fill)
                .clipped()
            
            // Video info overlay
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    
                    Text("\(video.hypeCount)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.6))
        }
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}

// MARK: - Trending Hashtag Chip

struct TrendingHashtagChip: View {
    let hashtag: TrendingHashtag
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Velocity indicator
                Text(hashtag.velocityTier.emoji)
                    .font(.system(size: 14))
                
                // Hashtag name
                Text(hashtag.displayTag)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                // Video count
                Text("\(hashtag.videoCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderColor.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var gradientColors: [Color] {
        switch hashtag.velocityTier {
        case .blazing: return [Color.orange.opacity(0.3), Color.red.opacity(0.2)]
        case .hot: return [Color.pink.opacity(0.3), Color.orange.opacity(0.2)]
        case .rising: return [Color.purple.opacity(0.3), Color.pink.opacity(0.2)]
        case .steady: return [Color.gray.opacity(0.2), Color.gray.opacity(0.15)]
        }
    }
    
    private var borderColor: Color {
        switch hashtag.velocityTier {
        case .blazing: return .orange
        case .hot: return .pink
        case .rising: return .purple
        case .steady: return .gray
        }
    }
}

// MARK: - HashtagView

struct HashtagView: View {
    let initialHashtag: TrendingHashtag
    
    @StateObject private var viewModel = HashtagViewModel()
    @Environment(\.dismiss) private var dismiss
    
    // Video presentation state
    @State private var selectedVideo: CoreVideoMetadata?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [Color.black, Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar for hashtags
                    hashtagSearchBar
                    
                    // Trending hashtags horizontal scroll
                    if !viewModel.trendingHashtags.isEmpty {
                        trendingHashtagsRow
                    }
                    
                    // Current hashtag header
                    if let current = viewModel.currentHashtag {
                        currentHashtagHeader(current)
                    }
                    
                    // Videos grid
                    if viewModel.isLoading && viewModel.videos.isEmpty {
                        loadingView
                    } else if viewModel.videos.isEmpty {
                        emptyView
                    } else {
                        videosGrid
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Hashtags")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await viewModel.initialize(with: initialHashtag)
        }
        .fullScreenCover(item: $selectedVideo) { video in
            FullscreenVideoView(
                video: video,
                overlayContext: .fullscreen,
                onDismiss: {
                    selectedVideo = nil
                }
            )
        }
    }
    
    // MARK: - Search Bar
    
    private var hashtagSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "number")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.pink)
            
            TextField("Search hashtags...", text: $viewModel.searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: viewModel.searchText) { _, newValue in
                    viewModel.filterHashtags(query: newValue)
                }
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.filterHashtags(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Trending Row
    
    private var trendingHashtagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.filteredHashtags) { hashtag in
                    HashtagPill(
                        hashtag: hashtag,
                        isSelected: viewModel.currentHashtag?.id == hashtag.id
                    ) {
                        Task {
                            await viewModel.selectHashtag(hashtag)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Current Hashtag Header
    
    private func currentHashtagHeader(_ hashtag: TrendingHashtag) -> some View {
        HStack(spacing: 12) {
            Text(hashtag.velocityTier.emoji)
                .font(.system(size: 24))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(hashtag.displayTag)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(hashtag.videoCount) videos • \(hashtag.recentVideoCount) today")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Velocity badge
            Text(hashtag.velocityTier.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(velocityColor(hashtag.velocityTier))
                .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
    }
    
    private func velocityColor(_ tier: HashtagVelocityTier) -> Color {
        switch tier {
        case .blazing: return .orange
        case .hot: return .pink
        case .rising: return .purple
        case .steady: return .gray
        }
    }
    
    // MARK: - Videos Grid
    
    private var videosGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(viewModel.videos) { video in
                    VideoThumbnailView(
                        video: video,
                        showEngagementBadge: true
                    ) {
                        selectedVideo = video
                    }
                }
            }
            .padding(.top, 2)
            
            // Load more trigger
            if viewModel.hasMore {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                    .padding()
                    .onAppear {
                        Task {
                            await viewModel.loadMoreVideos()
                        }
                    }
            }
        }
    }
    
    // MARK: - States
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                .scaleEffect(1.2)
            
            Text("Loading videos...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.square")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No videos found")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
            
            if let hashtag = viewModel.currentHashtag {
                Text("No videos with \(hashtag.displayTag) yet")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            // Debug: Show backfill button for admins
            #if DEBUG
            Button {
                Task {
                    await viewModel.runBackfill()
                }
            } label: {
                Text("Run Hashtag Backfill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.yellow)
                    .cornerRadius(8)
            }
            .padding(.top, 8)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - HashtagViewModel

@MainActor
class HashtagViewModel: ObservableObject {
    @Published var currentHashtag: TrendingHashtag?
    @Published var videos: [CoreVideoMetadata] = []
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var filteredHashtags: [TrendingHashtag] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var hasMore = false
    
    private let hashtagService = HashtagService()
    private var lastDocument: DocumentSnapshot?
    
    func initialize(with hashtag: TrendingHashtag) async {
        // Load trending hashtags
        await hashtagService.loadTrendingHashtags(limit: 20)
        trendingHashtags = hashtagService.trendingHashtags
        filteredHashtags = trendingHashtags
        
        // If initial hashtag not in trending, add it
        if !trendingHashtags.contains(where: { $0.id == hashtag.id }) {
            trendingHashtags.insert(hashtag, at: 0)
            filteredHashtags = trendingHashtags
        }
        
        // Load videos for initial hashtag
        await selectHashtag(hashtag)
    }
    
    func selectHashtag(_ hashtag: TrendingHashtag) async {
        currentHashtag = hashtag
        videos = []
        lastDocument = nil
        isLoading = true
        
        do {
            let result = try await hashtagService.getVideosForHashtag(hashtag.tag, limit: 30)
            videos = result.videos
            lastDocument = result.lastDoc
            hasMore = result.hasMore
        } catch {
            print("❌ HASHTAG VIEW: Failed to load videos: \(error)")
        }
        
        isLoading = false
    }
    
    func loadMoreVideos() async {
        guard let current = currentHashtag, hasMore, !isLoading else { return }
        isLoading = true
        
        do {
            let result = try await hashtagService.getVideosForHashtag(
                current.tag,
                limit: 30,
                lastDocument: lastDocument
            )
            videos.append(contentsOf: result.videos)
            lastDocument = result.lastDoc
            hasMore = result.hasMore
        } catch {
            print("❌ HASHTAG VIEW: Failed to load more: \(error)")
        }
        
        isLoading = false
    }
    
    func filterHashtags(query: String) {
        if query.isEmpty {
            filteredHashtags = trendingHashtags
        } else {
            let q = query.lowercased().replacingOccurrences(of: "#", with: "")
            filteredHashtags = trendingHashtags.filter { $0.tag.contains(q) }
        }
    }
    
    // MARK: - Debug: Backfill
    
    func runBackfill() async {
        print("🏷️ BACKFILL: Starting from HashtagView...")
        let result = await hashtagService.backfillAllHashtags()
        print("🏷️ BACKFILL: Complete! Updated: \(result.updated), Failed: \(result.failed)")
        
        // Reload trending after backfill
        await hashtagService.loadTrendingHashtags(limit: 20)
        trendingHashtags = hashtagService.trendingHashtags
        filteredHashtags = trendingHashtags
        
        // Reload current hashtag videos
        if let current = currentHashtag {
            await selectHashtag(current)
        }
    }
}

// MARK: - Hashtag Pill (for horizontal scroll)

struct HashtagPill: View {
    let hashtag: TrendingHashtag
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(hashtag.velocityTier.emoji)
                    .font(.system(size: 12))
                
                Text(hashtag.displayTag)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .black : .white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.pink : Color.white.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
