//
//  UserTagSheet.swift
//  StitchSocial
//
//  Layer 8: Views - User Tagging Selection Sheet
//  Dependencies: UserService (Layer 4), BasicUserInfo (Layer 1)
//  Features: Search users, multi-select up to 5, returns selected userIDs
//  FIXED: ForEach syntax and selectedUsers computed property
//

import SwiftUI

struct UserTagSheet: View {
    
    // MARK: - Properties
    
    let onSelectUsers: ([String]) -> Void
    let onDismiss: () -> Void
    let alreadyTaggedIDs: [String]
    
    // MARK: - State
    
    @StateObject private var userService = UserService()
    @State private var searchQuery = ""
    @State private var searchResults: [BasicUserInfo] = []
    @State private var selectedUserIDs: Set<String> = []
    @State private var isSearching = false
    
    // MARK: - Constants
    
    private let maxTags = 5
    
    // MARK: - Computed Properties
    
    private var selectedUsers: [BasicUserInfo] {
        searchResults.filter { selectedUserIDs.contains($0.id) }
    }
    
    private var canSelectMore: Bool {
        selectedUserIDs.count < maxTags
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Selected users preview
                if !selectedUserIDs.isEmpty {
                    selectedUsersSection
                }
                
                // Search results or empty state
                if isSearching {
                    loadingView
                } else if searchQuery.isEmpty {
                    emptyStateView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Tag Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let finalIDs = Array(selectedUserIDs)
                        onSelectUsers(finalIDs)
                    }
                    .disabled(selectedUserIDs.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search users...", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchQuery) { _, newValue in
                    performSearch(query: newValue)
                }
            
            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }
    
    private var selectedUsersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected (\(selectedUserIDs.count)/\(maxTags))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if selectedUserIDs.count == maxTags {
                    Text("Maximum reached")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedUsers, id: \.id) { user in
                        SelectedUserChip(user: user) {
                            selectedUserIDs.remove(user.id)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5))
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.id) { user in
                    UserSearchRow(
                        user: user,
                        isSelected: selectedUserIDs.contains(user.id),
                        isDisabled: alreadyTaggedIDs.contains(user.id) || (!selectedUserIDs.contains(user.id) && !canSelectMore),
                        onTap: {
                            toggleSelection(userID: user.id)
                        }
                    )
                    
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Search for users to tag")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Type a username to get started")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No users found")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            do {
                let results = try await userService.searchUsers(query: query, limit: 20)
                
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                    print("Search error: \(error)")
                }
            }
        }
    }
    
    private func toggleSelection(userID: String) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.remove(userID)
        } else if canSelectMore && !alreadyTaggedIDs.contains(userID) {
            selectedUserIDs.insert(userID)
        }
    }
}

// MARK: - User Search Row

struct UserSearchRow: View {
    let user: BasicUserInfo
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile image
                AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                
                // User info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Text("@\(user.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    // Tier badge
                    Text(user.tier.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierColor(for: user.tier))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Selection indicator
                if isDisabled {
                    Text("Tagged")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .blue : .gray.opacity(0.3))
                }
            }
            .padding()
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Selected User Chip

struct SelectedUserChip: View {
    let user: BasicUserInfo
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Small profile image
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            
            // Username
            Text("@\(user.username)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue)
        .cornerRadius(20)
    }
}

// MARK: - Helper Functions

/// Get color for user tier
private func tierColor(for tier: UserTier) -> Color {
    switch tier {
    case .rookie: return .gray
    case .rising: return .green
    case .veteran: return .blue
    case .influencer: return .purple
    case .ambassador: return .indigo
    case .elite: return .orange
    case .partner: return .pink
    case .legendary: return .red
    case .topCreator: return .yellow
    case .founder, .coFounder: return .cyan
    }
}

// MARK: - Preview

#Preview {
    UserTagSheet(
        onSelectUsers: { ids in
            print("Selected user IDs: \(ids)")
        },
        onDismiss: {
            print("Dismissed")
        },
        alreadyTaggedIDs: []
    )
}
