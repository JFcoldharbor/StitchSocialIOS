//
//  SearchView.swift
//  StitchSocial
//
//  Simple search interface with "People You May Know" using centralized FollowManager
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
    
    // UPDATED: People You May Know suggestions
    @Published var suggestedUsers: [BasicUserInfo] = []
    @Published var isLoadingSuggestions = false
    
    // UPDATED: Use centralized FollowManager instead of local follow logic
    @StateObject var followManager = FollowManager()
    
    private let searchService = SearchService()
    private var searchTask: Task<Void, Never>?
    
    init() {
        setupFollowCallbacks()
        Task {
            await loadSuggestedUsers()
        }
    }
    
    // UPDATED: Setup follow callbacks for better integration
    private func setupFollowCallbacks() {
        followManager.onFollowStateChanged = { [weak self] userID, isFollowing in
            print("🔗 SEARCH: User \(userID) follow state changed to \(isFollowing)")
        }
        
        followManager.onFollowError = { [weak self] userID, error in
            print("❌ SEARCH: Follow error for user \(userID): \(error)")
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
                let users = try await searchService.searchUsers(query: searchText, limit: 20)
                let videos = try await searchService.searchVideos(query: searchText, limit: 20)
                
                await MainActor.run {
                    self.userResults = users
                    self.videoResults = videos
                    self.isSearching = false
                }
                
                // UPDATED: Use FollowManager to load follow states
                await followManager.loadFollowStatesForUsers(users)
                
            } catch {
                await MainActor.run {
                    self.isSearching = false
                    print("Search failed: \(error)")
                }
            }
        }
    }
    
    // UPDATED: Load suggested users from special users config
    func loadSuggestedUsers() async {
        await MainActor.run {
            isLoadingSuggestions = true
        }
        
        do {
            // Get special users sorted by priority (founders, celebrities, verified)
            let specialUserEntries = SpecialUsersConfig.getUsersByPriority().prefix(10)
            
            var users: [BasicUserInfo] = []
            for entry in specialUserEntries {
                // Convert SpecialUserEntry to BasicUserInfo by searching Firebase
                let emailPrefix = entry.email.components(separatedBy: "@").first ?? ""
                if let foundUsers = try? await searchService.searchUsers(query: emailPrefix, limit: 1),
                   let user = foundUsers.first {
                    users.append(user)
                }
            }
            
            await MainActor.run {
                suggestedUsers = users
                isLoadingSuggestions = false
            }
            
            // UPDATED: Use FollowManager to load follow states for suggested users
            await followManager.loadFollowStatesForUsers(users)
            
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
            }
            print("Failed to load suggested users: \(error)")
        }
    }
    
    // REMOVED: toggleFollow - now handled by FollowManager
    // REMOVED: loadFollowStates - now handled by FollowManager
    // REMOVED: loadFollowStatesForSuggested - now handled by FollowManager
    
    func showProfile(for user: BasicUserInfo) {
        selectedUser = user
        showingProfile = true
    }
    
    private func clearResults() {
        userResults = []
        videoResults = []
        hasSearched = false
        // Note: Don't clear FollowManager state as it's shared across the app
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            
            if !viewModel.searchText.isEmpty {
                tabSelector
                resultsSection
            } else {
                emptyState
            }
        }
        .background(Color.black)
        .onChange(of: viewModel.searchText) { _, newValue in
            if !newValue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if viewModel.searchText == newValue {
                        viewModel.performSearch()
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showingProfile) {
            if let user = viewModel.selectedUser {
                CreatorProfileView(userID: user.id)
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search users and videos...", text: $viewModel.searchText)
                .foregroundColor(.white)
                .tint(.cyan)
            
            if !viewModel.searchText.isEmpty {
                Button("Clear") {
                    viewModel.searchText = ""
                }
                .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.displayName)
                            .font(.system(size: 16, weight: .medium))
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
        .padding(.top)
    }
    
    private var resultsSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isSearching {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        .padding(.top, 40)
                } else {
                    if viewModel.selectedTab == .all || viewModel.selectedTab == .users {
                        userResultsSection
                    }
                    
                    if viewModel.selectedTab == .all || viewModel.selectedTab == .videos {
                        videoResultsSection
                    }
                    
                    if viewModel.hasSearched && viewModel.userResults.isEmpty && viewModel.videoResults.isEmpty {
                        Text("No results found")
                            .foregroundColor(.gray)
                            .padding(.top, 60)
                    }
                }
            }
        }
    }
    
    // UPDATED: Use FollowManager for user results
    private var userResultsSection: some View {
        ForEach(viewModel.userResults, id: \.id) { user in
            UserSearchRowView(
                user: user,
                followManager: viewModel.followManager,
                onTap: {
                    viewModel.showProfile(for: user)
                }
            )
        }
    }
    
    private var videoResultsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(viewModel.videoResults, id: \.id) { video in
                VideoSearchCardView(video: video)
            }
        }
        .padding(.horizontal)
    }
    
    // UPDATED: Enhanced empty state with "People You May Know" using FollowManager
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    
                    Text("Search Stitch Social")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Find users, videos, and threads")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // UPDATED: People You May Know section using FollowManager
                if !viewModel.suggestedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("People You May Know")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.suggestedUsers, id: \.id) { user in
                                UserSearchRowView(
                                    user: user,
                                    followManager: viewModel.followManager,
                                    onTap: {
                                        viewModel.showProfile(for: user)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.top, 20)
                } else if viewModel.isLoadingSuggestions {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        
                        Text("Loading suggestions...")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                }
                
                Spacer()
            }
        }
    }
}

// UPDATED: UserSearchRowView now uses FollowManager instead of local follow logic
struct UserSearchRowView: View {
    let user: BasicUserInfo
    @ObservedObject var followManager: FollowManager
    let onTap: () -> Void
    
    @State private var currentUserID = Auth.auth().currentUser?.uid
    
    private var isCurrentUser: Bool {
        return currentUserID == user.id
    }
    
    // UPDATED: Use FollowManager for all follow state
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
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray)
                        .overlay {
                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.cyan)
                        }
                        
                        Text(user.tier.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                    
                    Text("@\(user.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !isCurrentUser {
                    // UPDATED: Use FollowManager for follow button
                    Button {
                        Task {
                            await followManager.toggleFollow(for: user.id)
                        }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text(followManager.followButtonText(for: user.id))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(isFollowing ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isFollowing ? Color.white : Color.cyan)
                        .cornerRadius(20)
                    }
                    .disabled(isLoading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VideoSearchCardView: View {
    let video: CoreVideoMetadata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "play.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(video.creatorName)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(video.viewCount)", systemImage: "eye")
                    Label("\(video.hypeCount)", systemImage: "flame")
                }
                .font(.system(size: 10))
                .foregroundColor(.gray)
            }
        }
    }
}
