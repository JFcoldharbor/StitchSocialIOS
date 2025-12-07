//
//  VideoMetadataRow.swift
//  StitchSocial
//
//  Layer 8: Views - Extracted Video Stats Display Component
//  Dependencies: ContextualVideoEngagement
//  Features: Views, stitches, engagement stats with optional viewers tap (creator-only)
//

import SwiftUI

struct VideoMetadataRow: View {
    
    // MARK: - Properties
    
    let engagement: ContextualVideoEngagement?
    let isUserVideo: Bool
    let onViewersTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 8) {
            if let engagement = engagement {
                // LIVE DATA - Views count (TAPPABLE for creator only)
                if isUserVideo {
                    Button(action: onViewersTap) {
                        viewsButton(count: engagement.viewCount)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Non-creator view (not tappable)
                    viewsStat(count: engagement.viewCount)
                }
                
                // Separator
                separator
                
                // LIVE DATA - Stitch count
                stitchesStat(count: engagement.replyCount)
                
            } else {
                // Loading state
                loadingState
            }
        }
    }
    
    // MARK: - Component Views
    
    private func viewsButton(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            Text("\(formatCount(count)) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    private func viewsStat(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            Text("\(formatCount(count)) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private func stitchesStat(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.cyan.opacity(0.7))
            
            Text("\(formatCount(count)) stitches")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.cyan.opacity(0.9))
        }
    }
    
    private func engagementStat(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.red.opacity(0.7))
            
            Text("\(formatCount(count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.red.opacity(0.9))
        }
    }
    
    private var separator: some View {
        Text("•")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
    }
    
    private var loadingState: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            Text("Loading...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    // MARK: - Utility Functions
    
    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1000000:
            return String(format: "%.1fK", Double(count) / 1000.0).replacingOccurrences(of: ".0", with: "")
        case 1000000..<1000000000:
            return String(format: "%.1fM", Double(count) / 1000000.0).replacingOccurrences(of: ".0", with: "")
        default:
            return String(format: "%.1fB", Double(count) / 1000000000.0).replacingOccurrences(of: ".0", with: "")
        }
    }
}

// Note: ContextualVideoEngagement is defined in ContextualVideoOverlay.swift

// MARK: - Preview

struct VideoMetadataRow_Previews: PreviewProvider {
    
    static let mockEngagement = ContextualVideoEngagement(
        videoID: "video1",
        creatorID: "user1",
        hypeCount: 245,
        coolCount: 78,
        shareCount: 12,
        replyCount: 34,
        viewCount: 1523,
        lastEngagementAt: Date()
    )
    
    static let highEngagement = ContextualVideoEngagement(
        videoID: "video2",
        creatorID: "user2",
        hypeCount: 12500,
        coolCount: 3400,
        shareCount: 890,
        replyCount: 456,
        viewCount: 125000,
        lastEngagementAt: Date()
    )
    
    static let lowEngagement = ContextualVideoEngagement(
        videoID: "video3",
        creatorID: "user3",
        hypeCount: 5,
        coolCount: 2,
        shareCount: 0,
        replyCount: 1,
        viewCount: 47,
        lastEngagementAt: Date()
    )
    
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 20) {
                // Normal engagement - creator view (tappable views)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator View (Tappable)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: mockEngagement,
                        isUserVideo: true,
                        onViewersTap: {
                            print("👁️ Tapped viewers - showing sheet")
                        }
                    )
                }
                
                // Normal engagement - non-creator view (not tappable)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Viewer View (Not Tappable)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: mockEngagement,
                        isUserVideo: false,
                        onViewersTap: { }
                    )
                }
                
                // High engagement
                VStack(alignment: .leading, spacing: 4) {
                    Text("High Engagement")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: highEngagement,
                        isUserVideo: true,
                        onViewersTap: {
                            print("👁️ High engagement viewers")
                        }
                    )
                }
                
                // Low engagement
                VStack(alignment: .leading, spacing: 4) {
                    Text("Low Engagement")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: lowEngagement,
                        isUserVideo: false,
                        onViewersTap: { }
                    )
                }
                
                // Loading state
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading State")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: nil,
                        isUserVideo: false,
                        onViewersTap: { }
                    )
                }
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}
