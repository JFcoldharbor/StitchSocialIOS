//
//  AllCollectionsView.swift
//  StitchSocial
//
//  Layer 6: Views - All Collections (show-level grid)
//  Uses pre-loaded data — NO Firestore re-fetch.
//  Shows only. Tap a show → opens ShowDetailView for episodes.
//  Context menu: View Episodes, Edit Show, Delete Show.
//

import SwiftUI

struct AllCollectionsView: View {
    
    @State var collections: [VideoCollection]
    let isOwnProfile: Bool
    let onShowTap: (String) -> Void
    var onEditShow: ((String) -> Void)? = nil
    var onDeleteShow: ((String) -> Void)? = nil
    var onCreateShow: (() -> Void)? = nil
    let onDismiss: () -> Void
    
    @State private var showToDelete: String?
    @State private var showDeleteConfirm = false
    
    private var showGroups: [(showId: String, title: String, episodes: [VideoCollection])] {
        let withShow = collections.filter { $0.showId != nil && !($0.showId?.isEmpty ?? true) }
        let grouped = Dictionary(grouping: withShow) { $0.showId! }
        return grouped.map { key, value in
            let sorted = value.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
            let title = ShowCard.inferTitle(from: sorted)
            return (showId: key, title: title, episodes: sorted)
        }
        .sorted { $0.episodes.first?.createdAt ?? Date() > $1.episodes.first?.createdAt ?? Date() }
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        ScrollView {
            if showGroups.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(showGroups, id: \.showId) { group in
                        ShowGridCard(
                            title: group.title,
                            episodes: group.episodes,
                            color: ShowCard.colorFor(group.episodes.first?.contentType ?? .series),
                            isOwnProfile: isOwnProfile,
                            onTap: { onShowTap(group.showId) },
                            onEdit: { onEditShow?(group.showId) },
                            onDelete: {
                                showToDelete = group.showId
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
                .padding(14)
            }
            
            // Hint
            if !showGroups.isEmpty {
                Text("Long press to manage · Tap to view episodes")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.black)
        .navigationTitle("My Shows")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { onDismiss() }
                    .foregroundColor(.cyan)
            }
            if isOwnProfile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { onCreateShow?() } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.pink)
                    }
                }
            }
        }
        .confirmationDialog("Delete Show?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = showToDelete {
                    onDeleteShow?(id)
                    collections.removeAll { $0.showId == id }
                }
                showToDelete = nil
            }
            Button("Cancel", role: .cancel) { showToDelete = nil }
        } message: {
            Text("This will delete the show and all its episodes. This cannot be undone.")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            
            Image(systemName: "film.stack")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.08))
            
            Text("No Shows Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            
            Text("Create your first show to start\nadding episodes and segments.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
            
            if isOwnProfile {
                Button { onCreateShow?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Create Show")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
    }
}
