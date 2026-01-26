//
//  CollectionDetailView.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionDetailView.swift
//  StitchSocial
//
//  Layer 6: Views - Collection Detail / Pre-Play Screen
//  Dependencies: CollectionRowViewModel, CollectionCoordinator, VideoCollection
//  Features: Cover image, description, segment list, creator info, engagement, play button
//  CREATED: Phase 6 - Collections feature Full Screens
//

import SwiftUI

/// Detail view for a collection shown before playing
/// Displays full info, segment list, creator, and engagement stats
struct CollectionDetailView: View {
    
    // MARK: - Properties
    
    let collection: VideoCollection
    let coordinator: CollectionCoordinator
    
    /// Dismiss action
    let onDismiss: () -> Void
    
    // MARK: - State
    
    @StateObject private var viewModel: CollectionDetailViewModel
    @State private var selectedSegmentIndex: Int? = nil
    @State private var showShareSheet: Bool = false
    
    // MARK: - Initialization
    
    init(
        collection: VideoCollection,
        coordinator: CollectionCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.collection = collection
        self.coordinator = coordinator
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: CollectionDetailViewModel(collection: collection))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero Section
                        heroSection
                        
                        // Content
                        VStack(spacing: 20) {
                            // Info Card
                            infoCard
                            
                            // Engagement Card
                            engagementCard
                            
                            // Segments Card
                            segmentsCard
                            
                            // Creator Card
                            creatorCard
                            
                            // Bottom spacing for play button
                            Spacer(minLength: 100)
                        }
                        .padding()
                    }
                }
                
                // Floating Play Button
                VStack {
                    Spacer()
                    playButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    closeButton
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    menuButton
                }
            }
            .task {
                await viewModel.loadSegments()
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareURL])
            }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Cover Image
            if let coverURL = collection.coverImageURL {
                AsyncImage(url: URL(string: coverURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_), .empty:
                        coverPlaceholder
                    @unknown default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
            
            // Gradient Overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Title Overlay
            VStack(alignment: .leading, spacing: 8) {
                // Badges
                HStack(spacing: 8) {
                    // Segment count badge
                    Label("\(collection.segmentCount) parts", systemImage: "square.stack.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    
                    // Duration badge
                    Label(collection.formattedTotalDuration, systemImage: "clock.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    
                    Spacer()
                }
                
                // Title
                Text(collection.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding()
        }
        .frame(height: 280)
        .clipped()
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 48))
                
                Text("Collection")
                    .font(.headline)
            }
            .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Info Card
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            if !collection.description.isEmpty {
                Text(collection.description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Meta info
            HStack(spacing: 16) {
                // Visibility
                Label(collection.visibility.displayName, systemImage: collection.visibility.iconName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Replies status
                if collection.allowReplies {
                    Label("Replies enabled", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Published date
                if let publishedAt = collection.publishedAt {
                    Text(formattedDate(publishedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Engagement Card
    
    private var engagementCard: some View {
        HStack(spacing: 0) {
            engagementStat(
                value: formatCount(collection.totalViews),
                label: "Views",
                icon: "eye.fill",
                color: .blue
            )
            
            Divider()
                .frame(height: 40)
            
            engagementStat(
                value: formatCount(collection.totalHypes),
                label: "Hypes",
                icon: "flame.fill",
                color: .orange
            )
            
            Divider()
                .frame(height: 40)
            
            engagementStat(
                value: formatCount(collection.totalCools),
                label: "Cools",
                icon: "snowflake",
                color: .cyan
            )
            
            Divider()
                .frame(height: 40)
            
            engagementStat(
                value: formatCount(collection.totalReplies),
                label: "Replies",
                icon: "bubble.left.fill",
                color: .purple
            )
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func engagementStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Segments Card
    
    private var segmentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Segments")
                    .font(.headline)
                
                Spacer()
                
                Text(collection.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Segment List
            if viewModel.isLoadingSegments {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                        segmentRow(segment: segment, index: index)
                        
                        if index < viewModel.segments.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func segmentRow(segment: CoreVideoMetadata, index: Int) -> some View {
        Button {
            // Play from this segment
            coordinator.playCollection(collection)
            // Would need to pass starting segment index
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    AsyncImage(url: URL(string: segment.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(.tertiarySystemBackground)
                    }
                    
                    // Part number overlay
                    VStack {
                        Spacer()
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(4)
                            Spacer()
                        }
                    }
                    .padding(4)
                }
                .frame(width: 64, height: 48)
                .clipped()
                .cornerRadius(8)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.segmentDisplayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(segment.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if segment.replyCount > 0 {
                            Label("\(segment.replyCount)", systemImage: "bubble.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Play indicator
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Creator Card
    
    private var creatorCard: some View {
        Button {
            // Navigate to creator profile
        } label: {
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(String(collection.creatorName.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.creatorName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("View Profile")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Play Button
    
    private var playButton: some View {
        Button {
            coordinator.playCollection(collection)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.headline)
                
                Text("Play Collection")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: .accentColor.opacity(0.4), radius: 8, y: 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
        .background(
            LinearGradient(
                colors: [.clear, Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Toolbar Buttons
    
    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.body)
                .fontWeight(.semibold)
        }
    }
    
    private var menuButton: some View {
        Menu {
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button {
                // Bookmark/save action
            } label: {
                Label("Save", systemImage: "bookmark")
            }
            
            Divider()
            
            Button(role: .destructive) {
                // Report action
            } label: {
                Label("Report", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
    }
    
    // MARK: - Helpers
    
    private var shareURL: URL {
        URL(string: "https://stitchsocial.app/collection/\(collection.id)")!
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Collection Detail ViewModel

@MainActor
class CollectionDetailViewModel: ObservableObject {
    
    // MARK: - Properties
    
    private let collectionService: CollectionService
    private let videoService: VideoService
    let collection: VideoCollection
    
    // MARK: - Published State
    
    @Published var segments: [CoreVideoMetadata] = []
    @Published var isLoadingSegments: Bool = false
    @Published var errorMessage: String?
    @Published var watchProgress: CollectionProgress?
    
    // MARK: - Initialization
    
    init(
        collection: VideoCollection,
        collectionService: CollectionService,
        videoService: VideoService
    ) {
        self.collection = collection
        self.collectionService = collectionService
        self.videoService = videoService
    }
    
    convenience init(collection: VideoCollection) {
        // Services are created here in MainActor context
        let collectionService = CollectionService()
        let videoService = VideoService()
        
        self.init(
            collection: collection,
            collectionService: collectionService,
            videoService: videoService
        )
    }
    
    // MARK: - Loading
    
    func loadSegments() async {
        isLoadingSegments = true
        
        do {
            segments = try await videoService.getVideosByCollection(collectionID: collection.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoadingSegments = false
    }
}

// MARK: - Share Sheet

struct CollectShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
