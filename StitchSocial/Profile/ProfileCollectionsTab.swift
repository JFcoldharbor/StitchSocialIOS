//
//  ProfileCollectionsTab.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  ProfileCollectionsTab.swift
//  StitchSocial
//
//  Layer 6: Views - Profile Collections Tab
//  Dependencies: CollectionRowView, CollectionCoordinator, CollectionService
//  Features: Grid/list toggle, drafts section, empty states, create button
//  CREATED: Phase 6 - Collections feature Full Screens
//

import SwiftUI

/// Collections tab for user profile view
/// Shows user's published collections and drafts (if own profile)
struct ProfileCollectionsTab: View {
    
    // MARK: - Properties
    
    let profileUserID: String
    let isOwnProfile: Bool
    let coordinator: CollectionCoordinator
    
    // MARK: - State
    
    @StateObject private var viewModel: ProfileCollectionsViewModel
    @State private var displayMode: CollectionDisplayMode = .grid
    @State private var showDrafts: Bool = false
    
    // MARK: - Initialization
    
    init(
        profileUserID: String,
        isOwnProfile: Bool,
        coordinator: CollectionCoordinator
    ) {
        self.profileUserID = profileUserID
        self.isOwnProfile = isOwnProfile
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: ProfileCollectionsViewModel(userID: profileUserID))
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with toggle
            if !viewModel.collections.isEmpty || isOwnProfile {
                headerBar
            }
            
            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.collections.isEmpty && viewModel.drafts.isEmpty {
                emptyStateView
            } else {
                collectionsContent
            }
        }
        .task {
            await viewModel.load(includesDrafts: isOwnProfile)
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Drafts toggle (own profile only)
            if isOwnProfile && !viewModel.drafts.isEmpty {
                Picker("View", selection: $showDrafts) {
                    Text("Published").tag(false)
                    Text("Drafts (\(viewModel.drafts.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            
            Spacer()
            
            // Display mode toggle
            HStack(spacing: 4) {
                displayModeButton(mode: .grid, icon: "square.grid.2x2")
                displayModeButton(mode: .list, icon: "list.bullet")
            }
            .padding(4)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            // Create button (own profile only)
            if isOwnProfile {
                Button {
                    coordinator.startNewCollection()
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    private func displayModeButton(mode: CollectionDisplayMode, icon: String) -> some View {
        Button {
            withAnimation {
                displayMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(displayMode == mode ? .accentColor : .secondary)
                .frame(width: 32, height: 28)
        }
    }
    
    // MARK: - Collections Content
    
    private var collectionsContent: some View {
        ScrollView {
            if showDrafts && isOwnProfile {
                draftsSection
            } else {
                publishedSection
            }
        }
    }
    
    // MARK: - Published Section
    
    private var publishedSection: some View {
        Group {
            switch displayMode {
            case .grid:
                gridLayout
            case .list:
                listLayout
            }
        }
    }
    
    private var gridLayout: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 16
        ) {
            ForEach(viewModel.collections) { collection in
                CollectionRowView(
                    collection: collection,
                    style: .grid,
                    onTap: {
                        coordinator.playCollection(collection)
                    }
                )
            }
        }
        .padding()
    }
    
    private var listLayout: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.collections) { collection in
                CollectionRowView(
                    collection: collection,
                    style: .compact,
                    onTap: {
                        coordinator.playCollection(collection)
                    }
                )
            }
        }
        .padding()
    }
    
    // MARK: - Drafts Section
    
    private var draftsSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.drafts, id: \.id) { draft in
                DraftRowView(
                    draft: draft,
                    onTap: {
                        coordinator.editDraft(draft)
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteDraft(draft)
                        }
                    }
                )
            }
        }
        .padding()
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading collections...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if isOwnProfile {
                Text("No Collections Yet")
                    .font(.headline)
                
                Text("Create your first collection to share multi-part video content")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button {
                    coordinator.startNewCollection()
                } label: {
                    Label("Create Collection", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No Collections")
                    .font(.headline)
                
                Text("This user hasn't created any collections yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding()
    }
}

// MARK: - Display Mode

enum CollectionDisplayMode {
    case grid
    case list
}

// MARK: - Draft Row View

/// Row view for displaying a draft collection
struct DraftRowView: View {
    let draft: CollectionDraft
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                    
                    VStack(spacing: 4) {
                        Image(systemName: "doc.badge.ellipsis")
                            .font(.title3)
                        
                        Text("\(draft.segments.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(width: 80, height: 60)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title ?? "Untitled Draft")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        // Segment count
                        Label("\(draft.segments.count) segments", systemImage: "square.stack")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Upload status
                        if draft.uploadingSegmentCount > 0 {
                            Label("Uploading", systemImage: "arrow.up.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if draft.failedSegmentCount > 0 {
                            Label("\(draft.failedSegmentCount) failed", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Last modified
                    Text("Edited \(formattedDate(draft.lastModifiedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Progress indicator
                if !draft.segments.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        CircularProgressView(
                            progress: draft.overallUploadProgress,
                            size: 32
                        )
                        
                        Text(draft.canPublish ? "Ready" : "\(Int(draft.overallUploadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(draft.canPublish ? .green : .secondary)
                    }
                }
                
                // Delete button
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete Draft?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your draft and any uploaded segments.")
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 3)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress >= 1.0 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            // Checkmark when complete
            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Profile Collections ViewModel

@MainActor
class ProfileCollectionsViewModel: ObservableObject {
    
    // MARK: - Properties
    
    private let collectionService: CollectionService
    private let userID: String
    
    // MARK: - Published State
    
    @Published var collections: [VideoCollection] = []
    @Published var drafts: [CollectionDraft] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Initialization
    
    init(userID: String, collectionService: CollectionService) {
        self.userID = userID
        self.collectionService = collectionService
    }
    
    convenience init(userID: String) {
        self.init(userID: userID, collectionService: CollectionService())
    }
    
    // MARK: - Loading
    
    func load(includesDrafts: Bool) async {
        isLoading = true
        
        do {
            // Load published collections
            collections = try await collectionService.getUserCollections(userID: userID)
            
            // Load drafts if own profile
            if includesDrafts {
                drafts = try await collectionService.loadUserDrafts(creatorID: userID)
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func deleteDraft(_ draft: CollectionDraft) async {
        do {
            try await collectionService.deleteDraft(draftID: draft.id)
            drafts.removeAll { $0.id == draft.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

