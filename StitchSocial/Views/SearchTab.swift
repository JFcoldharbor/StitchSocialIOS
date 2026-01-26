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
    @Published var showingProfile = false
    @Published var suggestedUsers: [BasicUserInfo] = []
    @Published var isLoadingSuggestions = false
    
    // FIXED: Use shared FollowManager instance
    let followManager = FollowManager.shared
    
    private let searchService = SearchService()
    private var searchTask: Task<Void, Never>?
    
    init() {
        Task {
            await loadSuggestedUsers()
        }
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
                    print("❌ SEARCH: Search failed: \(error)")
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
            }
            
            // Load follow states for suggested users
            await followManager.loadFollowStatesForUsers(users)
            print("✅ SEARCH: Loaded \(users.count) personalized suggestions")
            
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
            }
            print("❌ SEARCH: Failed to load suggestions: \(error)")
        }
    }
    
    func showProfile(for user: BasicUserInfo) {
        selectedUser = user
        showingProfile = true
    }
    
    func clearResults() {
        userResults = []
        videoResults = []
        hasSearched = false
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @Environment(\.dismiss) private var dismiss
    
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
                // Modern search bar
                searchBar
                    .padding(.top, 8)
                
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
        .sheet(isPresented: $viewModel.showingProfile) {
            if let user = viewModel.selectedUser {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService
                )
            }
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
                    viewModel.showProfile(for: user)
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
                                        viewModel.showProfile(for: user)
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

// MARK: - Preview

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
