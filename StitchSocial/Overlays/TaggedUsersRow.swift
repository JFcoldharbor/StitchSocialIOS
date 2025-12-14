//
//  TaggedUsersRow.swift
//  StitchSocial
//
//  Layer 8: Views - Compact Tagged Users Display Component
//  Dependencies: CoreVideoMetadata, UserService
//  Features: Stacked avatar circles with expandable sheet
//  FIXED: Now fetches user data directly when not cached
//

import SwiftUI

// MARK: - Main Component

struct TaggedUsersRow: View {
    
    // MARK: - Properties
    
    let taggedUserIDs: [String]
    let getCachedUserData: (String) -> CachedUserData?
    let onUserTap: (String) -> Void
    
    // MARK: - State
    
    @State private var showingFullList = false
    @State private var loadedUsers: [String: CachedUserData] = [:]
    
    // MARK: - Services
    
    @StateObject private var userService = UserService()
    
    // MARK: - Constants
    
    private let maxVisibleAvatars = 3
    private let avatarSize: CGFloat = 24
    private let avatarOverlap: CGFloat = 8
    
    // MARK: - Body
    
    var body: some View {
        Button(action: { showingFullList = true }) {
            HStack(spacing: 6) {
                // Purple person icon
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple)
                
                // Stacked avatars (first 3)
                ZStack(alignment: .leading) {
                    ForEach(Array(taggedUserIDs.prefix(maxVisibleAvatars).enumerated()), id: \.offset) { index, userID in
                        SmartCompactAvatar(
                            userID: userID,
                            size: avatarSize,
                            getCachedUserData: getCachedUserData,
                            loadedUsers: $loadedUsers
                        )
                        .offset(x: CGFloat(index) * avatarOverlap)
                        .zIndex(Double(maxVisibleAvatars - index))
                    }
                }
                .frame(width: CGFloat(min(taggedUserIDs.count, maxVisibleAvatars)) * avatarOverlap + (avatarSize - avatarOverlap))
                
                // Count badge (if more than 3)
                if taggedUserIDs.count > maxVisibleAvatars {
                    Text("+\(taggedUserIDs.count - maxVisibleAvatars)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.9))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingFullList) {
            SmartTaggedUsersSheet(
                taggedUserIDs: taggedUserIDs,
                getCachedUserData: getCachedUserData,
                loadedUsers: $loadedUsers,
                onUserTap: { userID in
                    showingFullList = false
                    onUserTap(userID)
                },
                onDismiss: { showingFullList = false }
            )
        }
        .task {
            // Pre-load user data for all tagged users
            await loadMissingUserData()
        }
    }
    
    // MARK: - Load Missing User Data
    
    private func loadMissingUserData() async {
        for userID in taggedUserIDs {
            // Skip if already cached
            if getCachedUserData(userID) != nil || loadedUsers[userID] != nil {
                continue
            }
            
            // Fetch from UserService
            do {
                if let user = try await userService.getUser(id: userID) {
                    await MainActor.run {
                        loadedUsers[userID] = CachedUserData(
                            displayName: user.displayName,
                            profileImageURL: user.profileImageURL,
                            tier: user.tier,
                            cachedAt: Date()
                        )
                    }
                }
            } catch {
                print("❌ TAGGED USERS: Failed to load user \(userID): \(error)")
            }
        }
    }
}

// MARK: - Smart Compact Avatar (Fetches if needed)

struct SmartCompactAvatar: View {
    let userID: String
    let size: CGFloat
    let getCachedUserData: (String) -> CachedUserData?
    @Binding var loadedUsers: [String: CachedUserData]
    
    @StateObject private var userService = UserService()
    @State private var localUserData: CachedUserData?
    @State private var isLoading = true
    
    private var userData: CachedUserData? {
        // Check all sources: passed cache, shared loaded, local
        getCachedUserData(userID) ?? loadedUsers[userID] ?? localUserData
    }
    
    var body: some View {
        Group {
            if let data = userData, let url = data.profileImageURL {
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: size, height: size)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.purple.opacity(0.8), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .task {
            await loadUserIfNeeded()
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.5), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white.opacity(0.7))
            )
    }
    
    private func loadUserIfNeeded() async {
        // Skip if we already have data
        if userData != nil {
            isLoading = false
            return
        }
        
        do {
            if let user = try await userService.getUser(id: userID) {
                await MainActor.run {
                    let cached = CachedUserData(
                        displayName: user.displayName,
                        profileImageURL: user.profileImageURL,
                        tier: user.tier,
                        cachedAt: Date()
                    )
                    localUserData = cached
                    loadedUsers[userID] = cached
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ SMART AVATAR: Failed to load user \(userID): \(error)")
        }
    }
}

// MARK: - Smart Tagged Users Sheet

struct SmartTaggedUsersSheet: View {
    let taggedUserIDs: [String]
    let getCachedUserData: (String) -> CachedUserData?
    @Binding var loadedUsers: [String: CachedUserData]
    let onUserTap: (String) -> Void
    let onDismiss: () -> Void
    
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
                
                if taggedUserIDs.isEmpty {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 100, height: 100)
                                .blur(radius: 15)
                            
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundColor(.purple.opacity(0.5))
                        }
                        
                        Text("No Tagged Users")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(taggedUserIDs, id: \.self) { userID in
                                SmartTaggedUserRow(
                                    userID: userID,
                                    getCachedUserData: getCachedUserData,
                                    loadedUsers: $loadedUsers,
                                    onTap: { onUserTap(userID) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tagged People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.purple)
                }
            }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Smart Tagged User Row

struct SmartTaggedUserRow: View {
    let userID: String
    let getCachedUserData: (String) -> CachedUserData?
    @Binding var loadedUsers: [String: CachedUserData]
    let onTap: () -> Void
    
    @StateObject private var userService = UserService()
    @State private var localUserData: CachedUserData?
    @State private var isLoading = true
    @State private var isPressed = false
    
    private var userData: CachedUserData? {
        getCachedUserData(userID) ?? loadedUsers[userID] ?? localUserData
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    if let data = userData, let url = data.profileImageURL {
                        AsyncImage(url: URL(string: url)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            avatarPlaceholder
                        }
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple, Color.purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                
                // User info
                VStack(alignment: .leading, spacing: 6) {
                    if let cached = userData {
                        HStack(spacing: 6) {
                            Text(cached.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            // Verified badge would go here if we had it
                        }
                        
                        if let tier = cached.tier {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(tierColor(tier))
                                    .frame(width: 8, height: 8)
                                
                                Text(tier.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(tierColor(tier))
                            }
                        }
                    } else if isLoading {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 120, height: 16)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 80, height: 14)
                        }
                    } else {
                        Text("Unknown User")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // View Profile button
                HStack(spacing: 4) {
                    Text("View")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.purple.opacity(0.15))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
        .task {
            await loadUserIfNeeded()
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.4), Color.purple.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
    
    private func loadUserIfNeeded() async {
        if userData != nil {
            isLoading = false
            return
        }
        
        do {
            if let user = try await userService.getUser(id: userID) {
                await MainActor.run {
                    let cached = CachedUserData(
                        displayName: user.displayName,
                        profileImageURL: user.profileImageURL,
                        tier: user.tier,
                        cachedAt: Date()
                    )
                    localUserData = cached
                    loadedUsers[userID] = cached
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ TAGGED ROW: Failed to load user \(userID): \(error)")
        }
    }
    
    private func tierColor(_ tier: UserTier) -> Color {
        switch tier {
        case .founder, .coFounder: return .cyan
        case .topCreator: return .yellow
        case .legendary: return .red
        case .partner: return .pink
        case .elite: return .orange
        case .ambassador: return .indigo
        case .influencer: return .purple
        case .veteran: return .blue
        case .rising: return .green
        case .rookie: return .gray
        }
    }
}

// MARK: - Legacy Support (Keep old components for backward compatibility)

struct CompactAvatar: View {
    let userID: String
    let size: CGFloat
    let getCachedUserData: (String) -> CachedUserData?
    
    private var cachedData: CachedUserData? {
        getCachedUserData(userID)
    }
    
    var body: some View {
        AsyncThumbnailView.avatar(url: cachedData?.profileImageURL ?? "")
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.purple.opacity(0.8), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .onAppear {
                _ = getCachedUserData(userID)
            }
    }
}

struct TaggedUsersSheet: View {
    let taggedUserIDs: [String]
    let getCachedUserData: (String) -> CachedUserData?
    let onUserTap: (String) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if taggedUserIDs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Tagged Users")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(taggedUserIDs, id: \.self) { userID in
                                TaggedUserRow(
                                    userID: userID,
                                    getCachedUserData: getCachedUserData,
                                    onTap: { onUserTap(userID) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tagged Users (\(taggedUserIDs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
        }
    }
}

struct TaggedUserRow: View {
    let userID: String
    let getCachedUserData: (String) -> CachedUserData?
    let onTap: () -> Void
    
    private var cachedData: CachedUserData? {
        getCachedUserData(userID)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncThumbnailView.avatar(url: cachedData?.profileImageURL ?? "")
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.purple.opacity(0.6), lineWidth: 2)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    if let cached = cachedData {
                        Text(cached.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if let tier = cached.tier {
                            HStack(spacing: 4) {
                                Image(systemName: tierIcon(tier))
                                    .font(.system(size: 11))
                                Text(tier.rawValue.capitalized)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(tierColor(tier))
                        }
                    } else {
                        Text("Loading...")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func tierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .founder, .coFounder: return "crown.fill"
        case .topCreator: return "star.fill"
        case .legendary: return "bolt.fill"
        case .partner: return "handshake.fill"
        case .elite: return "diamond.fill"
        case .influencer: return "megaphone.fill"
        case .veteran: return "shield.fill"
        case .rising: return "arrow.up.circle.fill"
        case .rookie: return "person.circle.fill"
        case .ambassador: return "sparkles"
        }
    }
    
    private func tierColor(_ tier: UserTier) -> Color {
        switch tier {
        case .founder, .coFounder: return .yellow
        case .topCreator: return .orange
        case .legendary: return .purple
        case .partner: return .cyan
        case .elite: return .pink
        case .influencer: return .red
        case .veteran: return .blue
        case .rising: return .green
        case .rookie: return .gray
        case .ambassador: return .indigo
        }
    }
}

// MARK: - Preview

struct TaggedUsersRow_Previews: PreviewProvider {
    
    static func mockGetCachedUserData(userID: String) -> CachedUserData? {
        return CachedUserData(
            displayName: "User\(userID.suffix(3))",
            profileImageURL: nil,
            tier: .rookie,
            cachedAt: Date()
        )
    }
    
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                TaggedUsersRow(
                    taggedUserIDs: ["user001", "user002"],
                    getCachedUserData: mockGetCachedUserData,
                    onUserTap: { userID in
                        print("Tapped: \(userID)")
                    }
                )
                
                TaggedUsersRow(
                    taggedUserIDs: ["user001", "user002", "user003", "user004", "user005"],
                    getCachedUserData: mockGetCachedUserData,
                    onUserTap: { userID in
                        print("Tapped: \(userID)")
                    }
                )
                
                Spacer()
            }
            .padding()
        }
    }
}
