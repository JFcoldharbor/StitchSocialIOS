//
//  CollectionRowView.swift
//  StitchSocial
//
//  Layer 6: Views - Collection Card Display
//  Dependencies: CollectionRowViewModel, VideoCollection
//  Features: Thumbnail strip, engagement stats, duration display, tap to play
//  CREATED: Phase 5 - Collections feature UI Components
//

import SwiftUI

/// Card view for displaying a collection in feeds and profile grids
/// Shows cover image, segment preview strip, title, creator, and engagement stats
struct CollectionRowView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: CollectionRowViewModel
    
    /// Tap action when card is selected
    let onTap: () -> Void
    
    /// Optional action for creator tap
    var onCreatorTap: (() -> Void)?
    
    /// Display style
    var style: CollectionRowStyle
    
    // MARK: - Initialization
    
    init(
        collection: VideoCollection,
        style: CollectionRowStyle = .card,
        onTap: @escaping () -> Void,
        onCreatorTap: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: CollectionRowViewModel(collection: collection))
        self.style = style
        self.onTap = onTap
        self.onCreatorTap = onCreatorTap
    }
    
    // MARK: - Body
    
    var body: some View {
        Button(action: {
            print("📚 COLLECTION ROW: Tapped collection '\(viewModel.title)' (ID: \(viewModel.collection.id))")
            onTap()
        }) {
            switch style {
            case .card:
                cardLayout
            case .compact:
                compactLayout
            case .grid:
                gridLayout
            }
        }
        .buttonStyle(CollectionCardButtonStyle())
        .task {
            await viewModel.loadSegmentPreviews()
        }
    }
    
    // MARK: - Card Layout (Full width)
    
    private var cardLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover/Preview Image
            coverImageSection
            
            // Segment Preview Strip
            if !viewModel.segmentPreviews.isEmpty {
                segmentPreviewStrip
            }
            
            // Info Section
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(viewModel.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Creator & Meta
                HStack(spacing: 8) {
                    // Creator
                    if let onCreatorTap = onCreatorTap {
                        Button(action: onCreatorTap) {
                            creatorLabel
                        }
                        .buttonStyle(.plain)
                    } else {
                        creatorLabel
                    }
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    // Summary (parts + duration)
                    Text(viewModel.summaryText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Engagement Stats
                engagementRow
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Compact Layout (List row)
    
    private var compactLayout: some View {
        HStack(spacing: 12) {
            // Thumbnail
            compactThumbnail
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(viewModel.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label(viewModel.hypeCountText, systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Label(viewModel.viewCountText, systemImage: "eye.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Play indicator
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Grid Layout (Square thumbnail)
    
    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Square thumbnail with overlay
            ZStack(alignment: .bottomLeading) {
                // Cover image
                if let coverURL = viewModel.coverImageURL {
                    AsyncImage(url: URL(string: coverURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        gridPlaceholder
                    }
                } else {
                    gridPlaceholder
                }
            }
            .frame(height: 160)
            .clipped()
            .cornerRadius(12)
            .overlay(alignment: .bottomLeading) {
                // Duration badge
                durationBadge
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                // Segment count badge
                segmentCountBadge
                    .padding(8)
            }
            
            // Title
            Text(viewModel.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            // Stats row
            HStack(spacing: 8) {
                Label(viewModel.hypeCountText, systemImage: "flame.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                Spacer()
                
                Text(viewModel.timeAgoText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Cover Image Section
    
    private var coverImageSection: some View {
        ZStack {
            if let coverURL = viewModel.coverImageURL {
                AsyncImage(url: URL(string: coverURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    case .failure(_):
                        coverPlaceholder
                    case .empty:
                        coverPlaceholder
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(height: 180)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            durationBadge
                .padding(12)
        }
        .overlay(alignment: .topLeading) {
            if let statusText = viewModel.statusBadgeText {
                statusBadge(text: statusText, color: viewModel.statusBadgeColor)
                    .padding(12)
            }
        }
    }
    
    // MARK: - Segment Preview Strip
    
    private var segmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.segmentPreviews) { preview in
                    segmentThumbnail(preview)
                }
                
                // "More" indicator
                if viewModel.showMoreSegmentsIndicator {
                    moreSegmentsIndicator
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 60)
    }
    
    private func segmentThumbnail(_ preview: SegmentPreview) -> some View {
        ZStack {
            if let thumbnailURL = preview.thumbnailURL {
                AsyncImage(url: URL(string: thumbnailURL)) { image in
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
        .frame(width: 80, height: 60)
        .clipped()
        .cornerRadius(8)
        .overlay(alignment: .bottomTrailing) {
            if let duration = preview.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .cornerRadius(4)
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("P\(preview.segmentNumber)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(4)
        }
    }
    
    private var moreSegmentsIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
            
            VStack(spacing: 2) {
                Text(viewModel.additionalSegmentsText ?? "+")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("more")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .frame(width: 60, height: 60)
    }
    
    // MARK: - Engagement Row
    
    private var engagementRow: some View {
        HStack(spacing: 16) {
            // Hype count
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text(viewModel.hypeCountText)
            }
            .font(.subheadline)
            
            // Cool count
            HStack(spacing: 4) {
                Image(systemName: "snowflake")
                    .foregroundColor(.blue)
                Text(viewModel.coolCountText)
            }
            .font(.subheadline)
            
            // Reply count
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .foregroundColor(.purple)
                Text("\(viewModel.collection.totalReplies)")
            }
            .font(.subheadline)
            
            Spacer()
            
            // Time ago
            Text(viewModel.timeAgoText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .foregroundColor(.secondary)
    }
    
    // MARK: - Creator Label
    
    private var creatorLabel: some View {
        Text(viewModel.creatorDisplayName)
            .font(.subheadline)
            .foregroundColor(.accentColor)
    }
    
    // MARK: - Badges
    
    private var durationBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.caption2)
            Text(viewModel.durationText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75))
        .cornerRadius(6)
    }
    
    private var segmentCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.fill")
                .font(.caption2)
            Text(viewModel.segmentCountText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.75))
        .cornerRadius(6)
    }
    
    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
    
    // MARK: - Placeholders
    
    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.largeTitle)
                Text("Collection")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var gridPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title)
                .foregroundColor(.secondary)
        }
    }
    
    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            
            Image(systemName: "play.rectangle.fill")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }
    
    private var compactThumbnail: some View {
        ZStack {
            if let coverURL = viewModel.coverImageURL {
                AsyncImage(url: URL(string: coverURL)) { image in
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
        .frame(width: 80, height: 60)
        .clipped()
        .cornerRadius(8)
        .overlay(alignment: .bottomTrailing) {
            Text(viewModel.segmentCountText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.7))
                .cornerRadius(4)
                .padding(4)
        }
    }
}

// MARK: - Display Style

/// Display styles for collection row
enum CollectionRowStyle {
    /// Full card with cover image and preview strip
    case card
    
    /// Compact horizontal layout for lists
    case compact
    
    /// Square grid item
    case grid
}

// MARK: - Button Style

/// Custom button style for collection cards
struct CollectionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
struct CollectionRowView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Card Style
                CollectionRowView(
                    collection: mockCollection,
                    style: .card,
                    onTap: { print("Tapped card") }
                )
                .padding(.horizontal)
                
                // Compact Style
                CollectionRowView(
                    collection: mockCollection,
                    style: .compact,
                    onTap: { print("Tapped compact") }
                )
                .padding(.horizontal)
                
                // Grid Style
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CollectionRowView(
                        collection: mockCollection,
                        style: .grid,
                        onTap: { print("Tapped grid 1") }
                    )
                    
                    CollectionRowView(
                        collection: mockDraftCollection,
                        style: .grid,
                        onTap: { print("Tapped grid 2") }
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    static var mockCollection: VideoCollection {
        VideoCollection(
            id: "preview_1",
            title: "SwiftUI Tutorial Series - Complete Guide",
            description: "Learn SwiftUI from basics to advanced",
            creatorID: "creator_123",
            creatorName: "SwiftDev",
            coverImageURL: nil,
            segmentIDs: ["s1", "s2", "s3", "s4", "s5"],
            segmentCount: 5,
            totalDuration: 1845,
            status: .published,
            visibility: .publicVisible,
            allowReplies: true,
            publishedAt: Date().addingTimeInterval(-86400 * 2),
            createdAt: Date().addingTimeInterval(-86400 * 5),
            updatedAt: Date(),
            totalViews: 12500,
            totalHypes: 890,
            totalCools: 45,
            totalReplies: 67,
            totalShares: 23
        )
    }
    
    static var mockDraftCollection: VideoCollection {
        VideoCollection(
            id: "preview_draft",
            title: "Work in Progress",
            description: "",
            creatorID: "creator_123",
            creatorName: "Creator",
            coverImageURL: nil,
            segmentIDs: ["s1", "s2"],
            segmentCount: 2,
            totalDuration: 600,
            status: .draft,
            visibility: .privateOnly,
            allowReplies: true,
            publishedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            totalViews: 0,
            totalHypes: 0,
            totalCools: 0,
            totalReplies: 0,
            totalShares: 0
        )
    }
}
#endif
