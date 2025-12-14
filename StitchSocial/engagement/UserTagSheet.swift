//
//  UserTagSheet.swift
//  StitchSocial
//
//  Layer 8: Views - User Tagging Selection Sheet
//  Dependencies: SearchService (Layer 4), BasicUserInfo (Layer 1)
//  Features: Search users, multi-select up to 5, stylish dark UI
//  REDESIGNED: Modern dark theme with gradients and animations
//

import SwiftUI

struct UserTagSheet: View {
    
    // MARK: - Properties
    
    let onSelectUsers: ([String]) -> Void
    let onDismiss: () -> Void
    let alreadyTaggedIDs: [String]
    let initiallySelectedIDs: [String]
    
    // MARK: - State
    
    @StateObject private var searchService = SearchService()
    @State private var searchQuery = ""
    @State private var searchResults: [BasicUserInfo] = []
    @State private var selectedUsers: [BasicUserInfo] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var appearAnimation = false
    
    // MARK: - Constants
    
    private let maxTags = 5
    
    // MARK: - Computed Properties
    
    private var selectedUserIDs: Set<String> {
        Set(selectedUsers.map { $0.id })
    }
    
    private var canSelectMore: Bool {
        selectedUsers.count < maxTags
    }
    
    // MARK: - Initializer
    
    init(
        onSelectUsers: @escaping ([String]) -> Void,
        onDismiss: @escaping () -> Void,
        alreadyTaggedIDs: [String],
        initiallySelectedIDs: [String] = []
    ) {
        self.onSelectUsers = onSelectUsers
        self.onDismiss = onDismiss
        self.alreadyTaggedIDs = alreadyTaggedIDs
        self.initiallySelectedIDs = initiallySelectedIDs
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.top, 8)
                    
                    // Selected users preview
                    if !selectedUsers.isEmpty {
                        selectedUsersSection
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Content area
                    Group {
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
                    .animation(.easeInOut(duration: 0.2), value: isSearching)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Tag People")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.gray, Color(white: 0.2))
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let finalIDs = selectedUsers.map { $0.id }
                        onSelectUsers(finalIDs)
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedUsers.isEmpty ? .gray : .cyan)
                    }
                    .disabled(selectedUsers.isEmpty)
                }
            }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await loadInitiallySelectedUsers()
                withAnimation(.easeOut(duration: 0.3)) {
                    appearAnimation = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray)
            
            TextField("Search users...", text: $searchQuery)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchQuery) { _, newValue in
                    performSearch(query: newValue)
                }
            
            if !searchQuery.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        searchQuery = ""
                        searchResults = []
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
    
    // MARK: - Selected Users Section
    
    private var selectedUsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with count
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                    
                    Text("Tagged")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<maxTags, id: \.self) { index in
                        Circle()
                            .fill(index < selectedUsers.count ? Color.cyan : Color(white: 0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                if selectedUsers.count == maxTags {
                    Text("MAX")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            
            // Selected user chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(selectedUsers, id: \.id) { user in
                        StylishSelectedChip(user: user) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedUsers.removeAll { $0.id == user.id }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color.cyan.opacity(0.1), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedUsers.count)
    }
    
    // MARK: - Search Results List
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, user in
                    StylishUserRow(
                        user: user,
                        isSelected: selectedUserIDs.contains(user.id),
                        isDisabled: alreadyTaggedIDs.contains(user.id) || (!selectedUserIDs.contains(user.id) && !canSelectMore),
                        isAlreadyTagged: alreadyTaggedIDs.contains(user.id),
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                toggleSelection(user: user)
                            }
                        }
                    )
                    .opacity(appearAnimation ? 1 : 0)
                    .offset(y: appearAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: appearAnimation)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
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
                
                Image(systemName: "at.badge.plus")
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
                Text("Tag Someone")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Search by username or display name")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - No Results View
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            
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
            
            Spacer()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
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
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isSearching = true
            }
            
            do {
                let results = try await searchService.searchUsers(query: query, limit: 30)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                    appearAnimation = false
                    withAnimation {
                        appearAnimation = true
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                    print("❌ TAG SEARCH: Search error: \(error)")
                }
            }
        }
    }
    
    private func toggleSelection(user: BasicUserInfo) {
        if selectedUserIDs.contains(user.id) {
            selectedUsers.removeAll { $0.id == user.id }
        } else if canSelectMore && !alreadyTaggedIDs.contains(user.id) {
            selectedUsers.append(user)
        }
    }
    
    private func loadInitiallySelectedUsers() async {
        guard !initiallySelectedIDs.isEmpty else { return }
        
        for userID in initiallySelectedIDs {
            do {
                let results = try await searchService.searchUsers(query: userID, limit: 5)
                if let user = results.first(where: { $0.id == userID }) {
                    await MainActor.run {
                        if !selectedUserIDs.contains(user.id) {
                            selectedUsers.append(user)
                        }
                    }
                }
            } catch {
                print("❌ TAG SHEET: Failed to load user \(userID): \(error)")
            }
        }
    }
}

// MARK: - Stylish User Row

struct StylishUserRow: View {
    let user: BasicUserInfo
    let isSelected: Bool
    let isDisabled: Bool
    let isAlreadyTagged: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Profile image with glow when selected
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.cyan.opacity(0.3))
                            .frame(width: 56, height: 56)
                            .blur(radius: 8)
                    }
                    
                    AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
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
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
                    )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.cyan, .cyan.opacity(0.3))
                        }
                    }
                    
                    Text("@\(user.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    // Tier badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tierColor(for: user.tier))
                            .frame(width: 6, height: 6)
                        
                        Text(user.tier.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(tierColor(for: user.tier))
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isAlreadyTagged {
                    Text("Already Tagged")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.2))
                        .cornerRadius(12)
                } else {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.cyan : Color(white: 0.3), lineWidth: 2)
                            .frame(width: 26, height: 26)
                        
                        if isSelected {
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 26, height: 26)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.cyan.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.5 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
}

// MARK: - Stylish Selected Chip

struct StylishSelectedChip: View {
    let user: BasicUserInfo
    let onRemove: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Profile image
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color(white: 0.3))
                    .overlay(
                        Text(String(user.username.prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    )
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            
            // Username
            Text("@\(user.username)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan, Color.cyan.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.cyan.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
}

// MARK: - Helper Functions

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
        alreadyTaggedIDs: [],
        initiallySelectedIDs: []
    )
}
