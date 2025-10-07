//
//  DiscoveryGridView.swift
//  StitchSocial
//
//  Clean Instagram-style grid with native pull-to-refresh
//

import SwiftUI

struct DiscoveryGridView: View {
    
    // MARK: - Props
    let videos: [CoreVideoMetadata]
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onLoadMore: () -> Void
    let onRefresh: () -> Void
    let isLoadingMore: Bool
    
    // MARK: - Grid Configuration
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    GridVideoThumbnail(
                        video: video,
                        onTap: { onVideoTap(video) }
                    )
                    .onAppear {
                        // Load more when near the end - adjusted for 2-column layout
                        if index >= videos.count - 8 {
                            onLoadMore()
                        }
                    }
                }
                
                // Loading indicator at bottom
                if isLoadingMore && !videos.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                                .scaleEffect(0.8)
                            
                            Text("Loading more...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 2)
        }
        .refreshable {
            onRefresh()
        }
        .background(Color.black)
    }
}

// MARK: - Grid Video Thumbnail

struct GridVideoThumbnail: View {
    let video: CoreVideoMetadata
    let onTap: () -> Void
    
    @State private var imageLoaded = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Thumbnail Image
                AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .onAppear { imageLoaded = true }
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            if !imageLoaded {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                                    .scaleEffect(0.7)
                            }
                        }
                }
                
                // Top overlay with duration
                VStack {
                    HStack {
                        Spacer()
                        Text(formatDuration(video.duration))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    
                    Spacer()
                }
                
                // Bottom overlay with stats
                VStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        if video.hypeCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(formatCount(video.hypeCount))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        if video.viewCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Text(formatCount(video.viewCount))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                // Tap overlay
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
        .clipped()
    }
    
    // MARK: - Helper Functions
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    DiscoveryGridView(
        videos: [],
        onVideoTap: { _ in },
        onLoadMore: { },
        onRefresh: { },
        isLoadingMore: false
    )
    .background(Color.black)
}
