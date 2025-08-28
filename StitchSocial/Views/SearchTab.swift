//
//  SearchView.swift
//  StitchSocial
//
//  Simple search interface
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
    @Published var followingStates: [String: Bool] = [:]
    @Published var followingLoading: Set<String> = []
    @Published var selectedUser: BasicUserInfo?
    @Published var showingProfile = false
    
    private let searchService = SearchService()
    private let userService = UserService()
    private var searchTask: Task<Void, Never>?
    
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
                
                await loadFollowStates()
                
            } catch {
                await MainActor.run {
                    self.isSearching = false
                    print("Search failed: \(error)")
                }
            }
        }
    }
    
    func loadFollowStates() async {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        var states: [String: Bool] = [:]
        for user in userResults {
            do {
                let isFollowing = try await userService.isFollowing(followerID: currentUserID, followingID: user.id)
                states[user.id] = isFollowing
            } catch {
                states[user.id] = false
            }
        }
        
        await MainActor.run {
            followingStates = states
        }
    }
    
    func toggleFollow(for userID: String) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        await MainActor.run {
            followingLoading.insert(userID)
        }
        
        do {
            let wasFollowing = followingStates[userID] ?? false
            
            await MainActor.run {
                followingStates[userID] = !wasFollowing
            }
            
            if wasFollowing {
                try await userService.unfollowUser(followerID: currentUserID, followingID: userID)
            } else {
                try await userService.followUser(followerID: currentUserID, followingID: userID)
            }
            
        } catch {
            await MainActor.run {
                let wasFollowing = followingStates[userID] ?? false
                followingStates[userID] = !wasFollowing
            }
        }
        
        await MainActor.run {
            followingLoading.remove(userID)
        }
    }
    
    func showProfile(for user: BasicUserInfo) {
        selectedUser = user
        showingProfile = true
    }
    
    private func clearResults() {
        userResults = []
        videoResults = []
        hasSearched = false
        followingStates = [:]
        followingLoading = []
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
                ProfileView(
                    authService: AuthService(),
                    userService: UserService(),
                    videoService: VideoService()
                )
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
    
    private var userResultsSection: some View {
        ForEach(viewModel.userResults, id: \.id) { user in
            UserSearchRowView(
                user: user,
                isFollowing: viewModel.followingStates[user.id] ?? false,
                isLoading: viewModel.followingLoading.contains(user.id),
                onTap: {
                    viewModel.showProfile(for: user)
                },
                onFollowTap: {
                    Task {
                        await viewModel.toggleFollow(for: user.id)
                    }
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
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("Search Stitch Social")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Find users, videos, and threads")
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
        }
    }
}

struct UserSearchRowView: View {
    let user: BasicUserInfo
    let isFollowing: Bool
    let isLoading: Bool
    let onTap: () -> Void
    let onFollowTap: () -> Void
    
    @State private var currentUserID = Auth.auth().currentUser?.uid
    
    private var isCurrentUser: Bool {
        return currentUserID == user.id
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
                    Button {
                        onFollowTap()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text(isFollowing ? "Following" : "Follow")
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
