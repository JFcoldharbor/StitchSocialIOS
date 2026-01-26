//
//  TopVideosView.swift
//  StitchSocial
//
//  Full screen view for browsing top trending videos
//  Features: Video grid with thumbnails, engagement stats, video playback
//

import SwiftUI

struct TopVideosView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var discoveryService = DiscoveryService()
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var videos: [LeaderboardVideo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedThreadID: String?
    @State private var targetVideoID: String?
    @State private var showingVideoThread = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading && videos.isEmpty {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if videos.isEmpty {
                    emptyView
                } else {
                    videoGrid
                }
            }
            .navigationTitle("Top Videos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
        }
        .task {
            await loadVideos()
        }
        .fullScreenCover(isPresented: $showingVideoThread) {
            if let threadID = selectedThreadID {
                ThreadView(
                    threadID: threadID,
                    videoService: VideoService(),
                    userService: UserService(),
                    targetVideoID: targetVideoID
                )
            }
        }
    }
    
    // MARK: - Video Grid
    
    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    TopVideoCard(
                        video: video,
                        rank: index + 1,
                        onTap: {
                            selectedThreadID = video.id
                            targetVideoID = video.id
                            showingVideoThread = true
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Loading & Error States
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.purple)
                .scaleEffect(1.5)
            
            Text("Loading top videos...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task { await loadVideos() }
            }
            .foregroundColor(.purple)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No trending videos yet")
                .font(.system(size: 16))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadVideos() async {
        isLoading = true
        errorMessage = nil
        
        do {
            videos = try await discoveryService.getHypeLeaderboard(limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Top Video Card Component

struct TopVideoCard: View {
    
    let video: LeaderboardVideo
    let rank: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var cardContent: some View {
        ZStack(alignment: .topLeading) {
            videoCardBody
            rankBadge
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(rankColor.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var videoCardBody: some View {
        VStack(spacing: 8) {
            thumbnailView
            infoSection
        }
    }
    
    private var thumbnailView: some View {
        AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure, .empty:
                placeholderView
            @unknown default:
                placeholderView
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.creatorName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            statsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
    
    private var statsRow: some View {
        HStack(spacing: 8) {
            hypeCount
        }
    }
    
    private var hypeCount: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(formatCount(video.hypeCount))
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
    
    private var rankBadge: some View {
        ZStack {
            Circle()
                .fill(rankColor)
                .frame(width: 32, height: 32)
            
            Text("#\(rank)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: rankColor.opacity(0.5), radius: 8)
        .padding(8)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .purple
        }
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

// MARK: - Preview

#Preview {
    TopVideosView()
}
