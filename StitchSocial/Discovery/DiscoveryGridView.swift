//
//  DiscoveryGridView.swift
//  StitchSocial
//
//  Layer 8: Views - Grid-style Discovery Layout
//  Dependencies: VideoThumbnailView, CoreVideoMetadata
//  Features: 3-column grid, thumbnail previews, engagement badges
//

import SwiftUI

struct DiscoveryGridView: View {
    
    // MARK: - Props
    
    let videos: [CoreVideoMetadata]
    let onVideoTap: (CoreVideoMetadata) -> Void
    let onEngagement: (InteractionType, CoreVideoMetadata) -> Void
    let onProfileTap: (String) -> Void
    
    // MARK: - State
    
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var showingVideoPlayer = false
    
    // MARK: - Configuration
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    private let spacing: CGFloat = 1
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    gridThumbnailItem(video: video, index: index)
                }
            }
            .padding(.horizontal, 0)
        }
        .background(Color.black)
    }
    
    // MARK: - Grid Thumbnail Item
    
    private func gridThumbnailItem(video: CoreVideoMetadata, index: Int) -> some View {
        GeometryReader { geometry in
            AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
            .overlay(gridOverlay(video: video))
            .contentShape(Rectangle())
            .onTapGesture {
                onVideoTap(video)
            }
        }
        .aspectRatio(9/16, contentMode: .fit)
    }
    
    // MARK: - Grid Overlay
    
    private func gridOverlay(video: CoreVideoMetadata) -> some View {
        ZStack {
            // Gradient overlay for readability
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack {
                Spacer()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        // Creator info
                        Button {
                            onProfileTap(video.creatorID)
                        } label: {
                            HStack(spacing: 4) {
                                // Creator profile placeholder (no profile image in video metadata)
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Text(video.creatorName.prefix(1).uppercased())
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                                
                                Text(video.creatorName)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        
                        // Video stats
                        HStack(spacing: 8) {
                            statItem(
                                icon: "eye.fill",
                                count: video.viewCount,
                                color: .white.opacity(0.8)
                            )
                            
                            statItem(
                                icon: "flame.fill",
                                count: video.hypeCount,
                                color: .orange
                            )
                        }
                    }
                    
                    Spacer()
                    
                    // Engagement quick actions
                    VStack(spacing: 6) {
                        Button {
                            onEngagement(.hype, video)
                        } label: {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Button {
                            onEngagement(.share, video)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            
            // Play indicator
            if video.duration > 0 {
                VStack {
                    HStack {
                        Spacer()
                        
                        Text(formatDuration(video.duration))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(.trailing, 6)
                            .padding(.top, 6)
                    }
                    
                    Spacer()
                }
            }
            
            // Temperature indicator
            if !video.temperature.isEmpty && video.temperature.lowercased() != "normal" {
                VStack {
                    HStack {
                        temperatureIndicator(video.temperature)
                            .padding(.leading, 6)
                            .padding(.top, 6)
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Helper Components
    
    private func statItem(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            Text(formatCount(count))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private func temperatureIndicator(_ temperature: String) -> some View {
        let color: Color = {
            switch temperature.lowercased() {
            case "hot", "blazing": return .red
            case "warm": return .orange
            case "cool": return .blue
            case "cold", "frozen": return .cyan
            default: return .gray
            }
        }()
        
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
    
    // MARK: - Helper Methods
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return String(count)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: ":%02d", seconds)
        }
    }
}
