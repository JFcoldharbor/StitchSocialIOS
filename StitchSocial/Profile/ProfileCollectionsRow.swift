//
//  ProfileCollectionsRow.swift
//  StitchSocial
//
//  Layer 6: Views - Profile Collections Horizontal Row
//  Composes: ShowCard, CollectionThumbnailCard, DraftThumbnailCard
//  Groups collections by showId into show cards, standalone collections separate.
//

import SwiftUI

struct ProfileCollectionsRow: View {
    
    let collections: [VideoCollection]
    let drafts: [CollectionDraft]
    let isOwnProfile: Bool
    let isEligible: Bool
    let onAddTap: () -> Void
    let onCollectionTap: (VideoCollection) -> Void
    let onDraftTap: (CollectionDraft) -> Void
    var onDraftDelete: ((CollectionDraft) -> Void)? = nil
    var onCollectionDelete: ((VideoCollection) -> Void)? = nil
    let onSeeAllTap: () -> Void
    var onShowTap: ((String) -> Void)? = nil
    
    @State private var draftToDelete: CollectionDraft?
    @State private var collectionToDelete: VideoCollection?
    @State private var showDeleteDraft = false
    @State private var showDeleteCollection = false
    
    // MARK: - Grouping
    
    private var showGroups: [(showId: String, episodes: [VideoCollection])] {
        let withShow = collections.filter { $0.showId != nil && !($0.showId?.isEmpty ?? true) }
        let grouped = Dictionary(grouping: withShow) { $0.showId! }
        return grouped.map { (showId: $0.key, episodes: $0.value.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) }
            .sorted { $0.episodes.first?.createdAt ?? Date() > $1.episodes.first?.createdAt ?? Date() }
    }
    
    private var standaloneCollections: [VideoCollection] {
        collections.filter { $0.showId == nil || $0.showId?.isEmpty == true }
    }
    
    private var shouldShowRow: Bool {
        !collections.isEmpty || (isOwnProfile && !drafts.isEmpty) || (isOwnProfile && isEligible)
    }
    
    // MARK: - Body
    
    var body: some View {
        if shouldShowRow {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Collections")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onSeeAllTap) {
                        Text("See all")
                            .font(.system(size: 11))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 16)
                
                // Horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Add button
                        if isOwnProfile && isEligible {
                            addButton
                        }
                        
                        // Show-grouped cards
                        ForEach(showGroups, id: \.showId) { group in
                            ShowCard(episodes: group.episodes) {
                                if let handler = onShowTap {
                                    handler(group.showId)
                                } else if let first = group.episodes.first {
                                    onCollectionTap(first)
                                }
                            }
                        }
                        
                        // Standalone collections
                        ForEach(standaloneCollections) { collection in
                            CollectionThumbnailCard(
                                collection: collection,
                                isOwnProfile: isOwnProfile,
                                onTap: { onCollectionTap(collection) },
                                onDelete: {
                                    collectionToDelete = collection
                                    showDeleteCollection = true
                                }
                            )
                        }
                        
                        // Drafts
                        if isOwnProfile {
                            ForEach(drafts) { draft in
                                DraftThumbnailCard(
                                    draft: draft,
                                    onTap: { onDraftTap(draft) },
                                    onDelete: {
                                        draftToDelete = draft
                                        showDeleteDraft = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .confirmationDialog("Delete Draft?", isPresented: $showDeleteDraft, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let d = draftToDelete { onDraftDelete?(d) }
                    draftToDelete = nil
                }
                Button("Cancel", role: .cancel) { draftToDelete = nil }
            } message: { Text("This will permanently delete this draft.") }
            .confirmationDialog("Delete Collection?", isPresented: $showDeleteCollection, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let c = collectionToDelete { onCollectionDelete?(c) }
                    collectionToDelete = nil
                }
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
            } message: { Text("This will delete this collection.") }
        }
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button(action: onAddTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .frame(width: 80, height: 100)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.7))
                }
                Text("New")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
