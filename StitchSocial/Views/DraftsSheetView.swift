//
//  DraftsSheetView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/8/26.
//


//
//  DraftsSheetView.swift
//  StitchSocial
//
//  Layer 8: Views - Drafts & Failed Uploads Management Sheet
//  Dependencies: LocalDraftManager, BackgroundUploadManager, VideoEditState
//  Features: 3-column grid, status overlays, tap to resume/retry, long-press to delete
//
//  Presented as a half-sheet from the camera/recording view.
//  Instagram-style: open camera → see your drafts.
//

import SwiftUI

struct DraftsSheetView: View {
    
    @ObservedObject private var draftManager = LocalDraftManager.shared
    @ObservedObject private var uploadManager = BackgroundUploadManager.shared
    
    let onDraftSelected: (VideoEditState) -> Void
    let onDismiss: () -> Void
    
    @State private var showingDeleteConfirmation = false
    @State private var draftToDelete: VideoEditState?
    
    // MARK: - Grid Layout
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if draftManager.incompleteDrafts.isEmpty {
                    emptyState
                } else {
                    draftsGrid
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(.cyan)
                }
                
                if draftManager.hasFailedUploads {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            uploadManager.retryAllFailed()
                        } label: {
                            Text("Retry All")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Delete Draft?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { draftToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let draft = draftToDelete {
                        deleteDraft(draft)
                    }
                }
            } message: {
                Text("This will permanently delete this draft and its video file.")
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Drafts Grid
    
    private var draftsGrid: some View {
        ScrollView {
            // Status summary header
            if draftManager.hasFailedUploads {
                failedUploadsBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(draftManager.incompleteDrafts, id: \.draftID) { draft in
                    draftCell(draft: draft)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Draft Cell
    
    private func draftCell(draft: VideoEditState) -> some View {
        Button {
            handleDraftTap(draft)
        } label: {
            ZStack {
                // Thumbnail
                draftThumbnail(draft: draft)
                
                // Status overlay
                statusOverlay(draft: draft)
                
                // Duration badge (bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        Text(formatDuration(draft.trimmedDuration))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                            .padding(6)
                        Spacer()
                    }
                }
            }
            .aspectRatio(3/4, contentMode: .fill)
            .clipped()
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            contextMenuItems(draft: draft)
        }
    }
    
    // MARK: - Thumbnail
    
    @ViewBuilder
    private func draftThumbnail(draft: VideoEditState) -> some View {
        if let thumbnailURL = draft.processedThumbnailURL {
            AsyncImage(url: thumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                thumbnailPlaceholder
            }
        } else {
            thumbnailPlaceholder
        }
    }
    
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "video.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray.opacity(0.5))
            )
    }
    
    // MARK: - Status Overlay
    
    @ViewBuilder
    private func statusOverlay(draft: VideoEditState) -> some View {
        switch draft.uploadStatus {
        case .draft:
            // Pencil icon — saved draft, not yet posted
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding(6)
                }
                Spacer()
            }
            
        case .readyToUpload:
            // Queued — clock icon
            Color.black.opacity(0.3)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                        Text("Queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                )
            
        case .uploading:
            // Uploading — spinner
            Color.black.opacity(0.4)
                .overlay(
                    VStack(spacing: 6) {
                        ProgressView()
                            .tint(.cyan)
                            .scaleEffect(1.2)
                        Text("Posting...")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                )
            
        case .failed:
            // Failed — red overlay with retry icon
            Color.red.opacity(0.25)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.red)
                        Text("Failed")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                )
            
        case .complete:
            // Shouldn't appear in incompleteDrafts, but just in case
            EmptyView()
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private func contextMenuItems(draft: VideoEditState) -> some View {
        switch draft.uploadStatus {
        case .draft:
            Button {
                handleDraftTap(draft)
            } label: {
                Label("Edit & Post", systemImage: "pencil")
            }
            
        case .failed:
            Button {
                uploadManager.retryUpload(draftID: draft.draftID)
            } label: {
                Label("Retry Upload", systemImage: "arrow.clockwise")
            }
            
        case .readyToUpload, .uploading:
            Button {
                // Just informational
            } label: {
                Label("Uploading...", systemImage: "arrow.up.circle")
            }
            .disabled(true)
            
        case .complete:
            EmptyView()
        }
        
        Divider()
        
        Button(role: .destructive) {
            draftToDelete = draft
            showingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(draft.uploadStatus == .uploading)
    }
    
    // MARK: - Failed Uploads Banner
    
    private var failedUploadsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(draftManager.failedUploads.count) upload\(draftManager.failedUploads.count == 1 ? "" : "s") failed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Tap a video to retry or use Retry All")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Drafts")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray)
            
            Text("Videos you save as drafts or\nfailed uploads will appear here")
                .font(.system(size: 14))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Actions
    
    private func handleDraftTap(_ draft: VideoEditState) {
        switch draft.uploadStatus {
        case .draft:
            // Resume editing — pass back to RecordingView to load into VideoReviewView
            onDraftSelected(draft)
            
        case .failed:
            // Retry upload directly
            uploadManager.retryUpload(draftID: draft.draftID)
            
        case .readyToUpload, .uploading:
            // Already in progress, do nothing
            break
            
        case .complete:
            break
        }
    }
    
    private func deleteDraft(_ draft: VideoEditState) {
        Task {
            // Cancel upload if in progress
            if uploadManager.isQueued(draftID: draft.draftID) {
                // Remove from queue by marking as draft first, then deleting
            }
            
            try? await draftManager.deleteDraft(id: draft.draftID)
            draftToDelete = nil
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}