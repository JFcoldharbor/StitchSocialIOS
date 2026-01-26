//
//  SwipeForRepliesBanner.swift
//  StitchSocial
//
//  Simple banner indicating video has replies - floats on right side of screen
//  UPDATED: Shows thumbnail of first reply instead of just count
//

import SwiftUI

/// Banner that appears on right side of screen for videos with replies
/// Shows thumbnail of first reply with reply count indicator
struct SwipeForRepliesBanner: View {
    
    let replyCount: Int
    let firstReplyThumbnailURL: String?  // ⭐ NEW: First reply thumbnail
    
    /// Only show if video has at least one reply
    var shouldShow: Bool {
        replyCount > 0
    }
    
    /// Check if we have a thumbnail to display
    private var hasThumbnail: Bool {
        return firstReplyThumbnailURL != nil && !firstReplyThumbnailURL!.isEmpty
    }
    
    var body: some View {
        if shouldShow {
            VStack(spacing: 6) {
                // Thumbnail or fallback
                thumbnailBubble
                
                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                
                // Reply count
                Text("\(replyCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
    
    // MARK: - Thumbnail Bubble
    
    @ViewBuilder
    private var thumbnailBubble: some View {
        if hasThumbnail {
            // ⭐ NEW: Show thumbnail version
            ZStack {
                // Thumbnail image
                AsyncImage(url: URL(string: firstReplyThumbnailURL ?? "")) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.3)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.gray.opacity(0.3)
                    @unknown default:
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 44, height: 58)
                .clipped()
                .cornerRadius(6)
                
                // Overlay gradient for depth
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.2),
                                Color.clear,
                                Color.black.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 58)
            }
            .frame(width: 44, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.8),
                                Color.purple.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            // ⭐ FIXED: Badge positioned in top-right corner OUTSIDE thumbnail
            .overlay(alignment: .topTrailing) {
                if replyCount > 1 {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("\(replyCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 22, height: 22)
                    .shadow(color: .orange.opacity(0.5), radius: 3, x: 0, y: 2)
                    .offset(x: 8, y: -8)
                }
            }
            .shadow(color: .cyan.opacity(0.3), radius: 6, x: 0, y: 3)
        } else {
            // Fallback: Show count bubble if no thumbnail
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.9),
                                Color.pink.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                
                VStack(spacing: 0) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(replyCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .shadow(color: .purple.opacity(0.5), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        // Simulate right-side positioning
        HStack {
            Spacer()
            VStack {
                Spacer()
                SwipeForRepliesBanner(
                    replyCount: 3,
                    firstReplyThumbnailURL: "https://via.placeholder.com/44x58"
                )
                Spacer()
            }
            .padding(.trailing, 12)
        }
    }
}
