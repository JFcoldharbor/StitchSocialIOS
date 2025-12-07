//
//  HypeLeaderboardSection.swift
//  StitchSocial
//
//  Created by James Garmon on 11/1/25.
//


//
//  HypeLeaderboardSection.swift
//  StitchSocial
//
//  Layer 8: Views - Hype Leaderboard Section
//  Dependencies: LeaderboardModels, SwiftUI
//  Features: Top 10 videos by hype, thread navigation
//

import SwiftUI

/// Section showing top videos by hype count from last 7 days
struct HypeLeaderboardSection: View {
    
    let leaderboardVideos: [LeaderboardVideo]
    let onVideoTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Section Header
            HStack {
                Text("🔥 Hype Leaderboard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("Last 7 Days")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal)
            
            // Leaderboard Cards
            if leaderboardVideos.isEmpty {
                Text("No videos with hype yet")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(leaderboardVideos.enumerated()), id: \.element.id) { index, video in
                        LeaderboardCard(
                            video: video,
                            rank: index + 1,
                            onTap: onVideoTap
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Leaderboard Card Component

private struct LeaderboardCard: View {
    
    let video: LeaderboardVideo
    let rank: Int
    let onTap: (String) -> Void
    
    var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .white.opacity(0.3)
        }
    }
    
    var body: some View {
        Button(action: { onTap(video.id) }) {
            HStack(spacing: 12) {
                
                // Rank Badge
                ZStack {
                    Circle()
                        .fill(rankColor)
                        .frame(width: 32, height: 32)
                    
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                }
                
                // Thumbnail
                if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                    }
                } else {
                    // Fallback thumbnail
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.5))
                        }
                }
                
                // Video Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(video.creatorName)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Hype Count & Temperature
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(video.hypeCount)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }
                    
                    // Temperature Badge
                    Text(video.temperatureEmoji)
                        .font(.system(size: 12))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        ScrollView {
            HypeLeaderboardSection(
                leaderboardVideos: [
                    LeaderboardVideo(
                        id: "1",
                        title: "Amazing skateboard trick compilation",
                        creatorID: "creator1",
                        creatorName: "SkateKing",
                        thumbnailURL: nil,
                        hypeCount: 1523,
                        coolCount: 42,
                        temperature: "fire",
                        createdAt: Date().addingTimeInterval(-86400)
                    ),
                    LeaderboardVideo(
                        id: "2",
                        title: "Cooking the perfect steak",
                        creatorID: "creator2",
                        creatorName: "ChefMaster",
                        thumbnailURL: nil,
                        hypeCount: 987,
                        coolCount: 23,
                        temperature: "hot",
                        createdAt: Date().addingTimeInterval(-172800)
                    ),
                    LeaderboardVideo(
                        id: "3",
                        title: "Piano performance of Moonlight Sonata",
                        creatorID: "creator3",
                        creatorName: "PianoWhiz",
                        thumbnailURL: nil,
                        hypeCount: 654,
                        coolCount: 15,
                        temperature: "warm",
                        createdAt: Date().addingTimeInterval(-259200)
                    )
                ],
                onVideoTap: { videoID in
                    print("Tapped video: \(videoID)")
                }
            )
        }
    }
}