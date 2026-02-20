//
//  ProfileCollectionsRow.swift
//  StitchSocial
//
//  Layer 6: Views - Profile Collections Horizontal Row
//  Dependencies: VideoCollection, CollectionDraft, CollectionCoordinator
//  Features: Horizontal scroll, Add button, collection thumbnails, draft indicators, DELETE DRAFTS
//  Design: Matches Instagram-style collections row on profile
//  FIXED: Added long-press to delete drafts, X button on drafts
//

import SwiftUI

/// Horizontal scrollable collections row for profile view
/// Shows Add button (own profile + eligible), published collections, and drafts
struct ProfileCollectionsRow: View {
    
    // MARK: - Properties
    
    let collections: [VideoCollection]
    let drafts: [CollectionDraft]
    let isOwnProfile: Bool
    let isEligible: Bool  // Ambassador+ tier (only affects Add button now)
    let onAddTap: () -> Void
    let onCollectionTap: (VideoCollection) -> Void
    let onDraftTap: (CollectionDraft) -> Void
    var onDraftDelete: ((CollectionDraft) -> Void)? = nil
    var onCollectionDelete: ((VideoCollection) -> Void)? = nil  // NEW: Delete published collection
    let onSeeAllTap: () -> Void
    
    // MARK: - State
    
    @State private var draftToDelete: CollectionDraft?
    @State private var collectionToDelete: VideoCollection?
    @State private var showDeleteConfirmation = false
    @State private var showCollectionDeleteConfirmation = false
    
    // MARK: - Constants
    
    private let thumbnailSize: CGFloat = 80
    private let spacing: CGFloat = 12
    
    // MARK: - Computed
    
    /// Whether to show the row at all
    private var shouldShowRow: Bool {
        if !collections.isEmpty { return true }
        if isOwnProfile && !drafts.isEmpty { return true }
        if isOwnProfile && isEligible { return true }
        return false
    }
    
    /// Whether to show Add button
    private var showAddButton: Bool {
        isOwnProfile && isEligible
    }
    
    // MARK: - Body
    
    var body: some View {
        if shouldShowRow {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                headerRow
                
                // Scrollable content
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        // Add button (own profile + eligible only)
                        if showAddButton {
                            addButton
                        }
                        
                        // Published collections
                        ForEach(collections) { collection in
                            collectionThumbnail(collection)
                        }
                        
                        // Drafts (own profile only)
                        if isOwnProfile {
                            ForEach(drafts) { draft in
                                draftThumbnail(draft)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .confirmationDialog(
                "Delete Draft?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let draft = draftToDelete {
                        onDraftDelete?(draft)
                    }
                    draftToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    draftToDelete = nil
                }
            } message: {
                Text("This will permanently delete this draft. This cannot be undone.")
            }
            .confirmationDialog(
                "Delete Collection?",
                isPresented: $showCollectionDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let collection = collectionToDelete {
                        onCollectionDelete?(collection)
                    }
                    collectionToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
            } message: {
                Text("This will remove this collection from your profile. Segment videos will remain.")
            }
        }
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Collections")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                // Show draft count if has drafts
                if isOwnProfile && !drafts.isEmpty {
                    Text("(\(drafts.count) drafts)")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if collections.count + drafts.count > 3 {
                Button(action: onSeeAllTap) {
                    Text("See All")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button(action: onAddTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundColor(.gray.opacity(0.6))
                        .frame(width: thumbnailSize, height: thumbnailSize)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Text("New")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(width: thumbnailSize)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Collection Thumbnail
    
    private func collectionThumbnail(_ collection: VideoCollection) -> some View {
        Button {
            onCollectionTap(collection)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Gradient ring
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: thumbnailSize, height: thumbnailSize)
                    
                    // Cover image
                    if let coverURL = collection.coverImageURL, let url = URL(string: coverURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            collectionPlaceholder
                        }
                        .frame(width: thumbnailSize - 6, height: thumbnailSize - 6)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        collectionPlaceholder
                            .frame(width: thumbnailSize - 6, height: thumbnailSize - 6)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Segment count badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 2) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text("\(collection.segmentCount)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(4)
                        }
                    }
                    .frame(width: thumbnailSize, height: thumbnailSize)
                }
                
                // Title
                Text(collection.title)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: thumbnailSize)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if isOwnProfile {
                Button {
                    onCollectionTap(collection)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                
                Button(role: .destructive) {
                    collectionToDelete = collection
                    showCollectionDeleteConfirmation = true
                } label: {
                    Label("Delete Collection", systemImage: "trash")
                }
            }
        }
    }
    
    private func draftThumbnail(_ draft: CollectionDraft) -> some View {
        Button {
            onDraftTap(draft)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Gray ring for drafts
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: thumbnailSize, height: thumbnailSize)
                    
                    // Cover image or placeholder
                    if let firstSegment = draft.segments.first,
                       let thumbnailURL = firstSegment.thumbnailURL,
                       let url = URL(string: thumbnailURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            draftPlaceholder
                        }
                        .frame(width: thumbnailSize - 6, height: thumbnailSize - 6)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        draftPlaceholder
                            .frame(width: thumbnailSize - 6, height: thumbnailSize - 6)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Draft overlay with segment count
                    VStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text("DRAFT")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(draft.segments.count) seg")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.9))
                    }
                    .frame(width: thumbnailSize - 6, height: thumbnailSize - 6)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // Delete button overlay (top-right X button)
                    if onDraftDelete != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    draftToDelete = draft
                                    showDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white, .red)
                                }
                                .offset(x: 6, y: -6)
                            }
                            Spacer()
                        }
                        .frame(width: thumbnailSize, height: thumbnailSize)
                    }
                }
                
                // Title
                Text(draft.title ?? "Untitled")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .frame(width: thumbnailSize)
            }
        }
        .buttonStyle(PlainButtonStyle())
        // Long press context menu to delete
        .contextMenu {
            if onDraftDelete != nil {
                Button(role: .destructive) {
                    draftToDelete = draft
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Draft", systemImage: "trash")
                }
                
                Button {
                    onDraftTap(draft)
                } label: {
                    Label("Edit Draft", systemImage: "pencil")
                }
            }
        }
    }
    
    // MARK: - Placeholders
    
    private var collectionPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.gray)
        }
    }
    
    private var draftPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 20))
                .foregroundColor(.gray.opacity(0.6))
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ProfileCollectionsRow_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ProfileCollectionsRow(
                collections: [],
                drafts: [],
                isOwnProfile: true,
                isEligible: true,
                onAddTap: { },
                onCollectionTap: { _ in },
                onDraftTap: { _ in },
                onDraftDelete: { _ in },
                onSeeAllTap: { }
            )
        }
    }
}
#endif
