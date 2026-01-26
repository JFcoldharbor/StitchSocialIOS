//
//  StitchFullscreenThumbnail.swift
//  StitchSocial
//
//  Reusable inline thumbnail navigator for fullscreen video playback
//  Shows previous/next videos on left/right edges + Facebook Stories-style progress bars
//  Works in: DiscoveryView, FullscreenVideoView, HomeFeedView
//

import SwiftUI

// MARK: - Main Navigator Container

struct FullscreenThumbnailNavigator: View {
    let videos: [CoreVideoMetadata]
    let currentIndex: Int
    let offsetX: CGFloat  // Horizontal drag/animation offset
    let videoProgress: Double = 0.0  // Current video playback progress (0.0 to 1.0)
    
    var videoCount: Int { videos.count }
    
    var previousVideo: CoreVideoMetadata? {
        guard currentIndex > 0 else { return nil }
        return videos[currentIndex - 1]
    }
    
    var nextVideo: CoreVideoMetadata? {
        guard currentIndex < videoCount - 1 else { return nil }
        return videos[currentIndex + 1]
    }
    
    var body: some View {
        guard videoCount > 1 else { return AnyView(EmptyView()) }
        
        return AnyView(
            ZStack(alignment: .top) {
                // Left: Previous video preview
                if let prevVideo = previousVideo {
                    PreviousThumbnailPreview(
                        video: prevVideo,
                        offsetX: offsetX
                    )
                }
                
                // Right: Next video preview
                if let nextVideo = nextVideo {
                    NextThumbnailPreview(
                        video: nextVideo,
                        offsetX: offsetX
                    )
                }
                
                // Top Center: Facebook Stories-style progress bars
                ProgressIndicatorBars(
                    videoCount: videoCount,
                    currentIndex: currentIndex,
                    currentProgress: videoProgress
                )
                .padding(.top, 12)
                .padding(.horizontal, 8)
            }
        )
    }
}

// MARK: - Previous Video Preview (Left Edge)

struct PreviousThumbnailPreview: View {
    let video: CoreVideoMetadata
    let offsetX: CGFloat
    
    var body: some View {
        ZStack {
            // Placeholder background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
            
            // Thumbnail image
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white.opacity(0.5))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo.fill")
                        .foregroundColor(.white.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .clipped()
        }
        .frame(width: 60, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(0.6)
        .offset(x: offsetX)  // Animate with drag
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.leading, 8)
    }
}

// MARK: - Next Video Preview (Right Edge)

struct NextThumbnailPreview: View {
    let video: CoreVideoMetadata
    let offsetX: CGFloat
    
    var body: some View {
        ZStack {
            // Placeholder background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
            
            // Thumbnail image
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white.opacity(0.5))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo.fill")
                        .foregroundColor(.white.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .clipped()
        }
        .frame(width: 60, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(0.6)
        .offset(x: offsetX)  // Animate with drag
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 8)
    }
}

// MARK: - Progress Indicator Bars (Facebook Stories Style)

struct ProgressIndicatorBars: View {
    let videoCount: Int
    let currentIndex: Int
    let currentProgress: Double  // 0.0 to 1.0 for current video playback
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<min(videoCount, 20), id: \.self) { index in
                ProgressBar(
                    isCurrent: index == currentIndex,
                    isCompleted: index < currentIndex,
                    progress: index == currentIndex ? currentProgress : (index < currentIndex ? 1.0 : 0.0)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // Calculate spacing based on video count
    private var barSpacing: CGFloat {
        switch videoCount {
        case 1...3: return 6
        case 4...6: return 4
        case 7...10: return 3
        default: return 2
        }
    }
}

// MARK: - Individual Progress Bar

struct ProgressBar: View {
    let isCurrent: Bool
    let isCompleted: Bool
    let progress: Double
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background (unfilled)
            Capsule()
                .fill(Color.white.opacity(0.3))
            
            // Foreground (filled)
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.85, blue: 0.95),  // Cyan
                            Color(red: 0.4, green: 0.95, blue: 0.8)    // Mint
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: progress, y: 1, anchor: .leading)
                .opacity(isCurrent || isCompleted ? 1.0 : 0.3)
        }
        .frame(height: barHeight)
        .animation(.linear(duration: 0.1), value: progress)
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }
    
    private var barHeight: CGFloat {
        isCurrent ? 3 : 2
    }
}
