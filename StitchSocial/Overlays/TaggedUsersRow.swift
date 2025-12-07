//
//  TaggedUsersRow.swift
//  StitchSocial
//
//  Layer 8: Views - Compact Tagged Users Display Component
//  Dependencies: CoreVideoMetadata
//  Features: Stacked avatar circles with expandable sheet
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
                        CompactAvatar(
                            userID: userID,
                            size: avatarSize,
                            getCachedUserData: getCachedUserData
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
            TaggedUsersSheet(
                taggedUserIDs: taggedUserIDs,
                getCachedUserData: getCachedUserData,
                onUserTap: { userID in
                    showingFullList = false
                    onUserTap(userID)
                },
                onDismiss: { showingFullList = false }
            )
        }
    }
}

// MARK: - Compact Avatar

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

// MARK: - Expandable Sheet

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

// MARK: - Tagged User Row (Sheet Item)

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
                // Avatar using AsyncThumbnailView
                AsyncThumbnailView.avatar(url: cachedData?.profileImageURL ?? "")
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.purple.opacity(0.6), lineWidth: 2)
                    )
                
                // User info
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
                
                // Chevron
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
        case .ambassador: return "sparkles.fill"
        @unknown default: return "person.circle"
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
        @unknown default: return .gray
        }
    }
}

// MARK: - Supporting Types
// Note: CachedUserData is defined in ContextualVideoOverlay.swift

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
                // 2 tagged users
                TaggedUsersRow(
                    taggedUserIDs: ["user001", "user002"],
                    getCachedUserData: mockGetCachedUserData,
                    onUserTap: { userID in
                        print("Tapped: \(userID)")
                    }
                )
                
                // 5 tagged users (shows +2)
                TaggedUsersRow(
                    taggedUserIDs: ["user001", "user002", "user003", "user004", "user005"],
                    getCachedUserData: mockGetCachedUserData,
                    onUserTap: { userID in
                        print("Tapped: \(userID)")
                    }
                )
                
                // 10 tagged users (shows +7)
                TaggedUsersRow(
                    taggedUserIDs: Array(repeating: "user", count: 10).enumerated().map { "user00\($0.offset)" },
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
