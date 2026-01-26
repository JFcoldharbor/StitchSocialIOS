//
//  SpinOffPreviewCard.swift
//  StitchSocial
//
//  Created by James Garmon on 1/15/26.
//


//
//  SpinOffComponents.swift
//  StitchSocial
//
//  Layer 8: Views - Spin-off UI Components
//  Components for displaying spin-off relationships between threads
//  Features: SpinOffPreviewCard, SpinOffBadge, SpinOffCountIndicator
//

import SwiftUI

// MARK: - SpinOffPreviewCard

/// Shows the source video context when creating or viewing a spin-off
/// Used in ThreadComposer and feed items to show what video sparked this response
struct SpinOffPreviewCard: View {
    
    // MARK: - Properties
    
    let thumbnailURL: String
    let creatorName: String
    let title: String
    let onTapViewOriginal: (() -> Void)?
    
    // MARK: - Styling
    
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure(_):
                    thumbnailPlaceholder
                case .empty:
                    thumbnailPlaceholder
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.gray)
                        )
                @unknown default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: isCompact ? 50 : 60, height: isCompact ? 66 : 80)
            .cornerRadius(8)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Header with icon
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: isCompact ? 10 : 12))
                        .foregroundColor(.orange)
                    
                    Text("Responding to")
                        .font(.system(size: isCompact ? 11 : 12))
                        .foregroundColor(.gray)
                }
                
                // Creator name
                Text("@\(creatorName)")
                    .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Title
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: isCompact ? 11 : 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                // View original button
                if let onTap = onTapViewOriginal {
                    Button(action: onTap) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text("View original")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(isCompact ? 10 : 12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Thumbnail Placeholder
    
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "video.fill")
                    .font(.system(size: isCompact ? 16 : 20))
                    .foregroundColor(.gray.opacity(0.5))
            )
    }
}

// MARK: - SpinOffPreviewCard Convenience Initializers

extension SpinOffPreviewCard {
    
    /// Initialize from CameraVideoInfo (used in ThreadComposer)
    init(from videoInfo: CameraVideoInfo, onTapViewOriginal: (() -> Void)? = nil) {
        self.thumbnailURL = videoInfo.thumbnailURL ?? ""
        self.creatorName = videoInfo.creatorName
        self.title = videoInfo.title
        self.onTapViewOriginal = onTapViewOriginal
        self.isCompact = false
    }
    
    /// Initialize from CoreVideoMetadata (used when displaying in feed)
    init(from video: CoreVideoMetadata, onTapViewOriginal: (() -> Void)? = nil) {
        self.thumbnailURL = video.thumbnailURL
        self.creatorName = video.creatorName
        self.title = video.title
        self.onTapViewOriginal = onTapViewOriginal
        self.isCompact = false
    }
}

// MARK: - SpinOffBadge

/// Small badge overlay showing "Responding to @user"
/// Displayed on spin-off videos in the feed
struct SpinOffBadge: View {
    
    let creatorName: String
    let onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 5) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 9, weight: .semibold))
                
                Text("Responding to @\(creatorName)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - SpinOffCountIndicator

/// Engagement button showing how many spin-offs a video has spawned
/// Displayed in the engagement sidebar when spinOffCount > 0
struct SpinOffCountIndicator: View {
    
    let count: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.2)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(formatCount(count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(SpinOffScaleButtonStyle())
    }
    
    // MARK: - Format Count
    
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

// MARK: - SpinOffScaleButtonStyle

struct SpinOffScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - SpinOffsListSheet

/// Sheet showing all spin-offs from a video
struct SpinOffsListSheet: View {
    
    let sourceVideo: CoreVideoMetadata
    let spinOffs: [CoreVideoMetadata]
    let onSelectSpinOff: (CoreVideoMetadata) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if spinOffs.isEmpty {
                    emptyState
                } else {
                    spinOffsList
                }
            }
            .navigationTitle("Spin-offs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No Spin-offs Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            
            Text("When others create threads responding to this video, they'll appear here.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Spin-offs List
    
    private var spinOffsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(spinOffs) { spinOff in
                    SpinOffListItem(
                        video: spinOff,
                        onTap: { onSelectSpinOff(spinOff) }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - SpinOffListItem

/// Individual item in the spin-offs list
struct SpinOffListItem: View {
    
    let video: CoreVideoMetadata
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "video.fill")
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .frame(width: 70, height: 93)
                .cornerRadius(8)
                .clipped()
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title.isEmpty ? "Untitled" : video.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    Text("@\(video.creatorName)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
                        Label("\(video.hypeCount)", systemImage: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        Label("\(video.viewCount)", systemImage: "eye.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        Text(timeAgo(from: video.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Time Ago Helper
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            let weeks = Int(interval / 604800)
            return "\(weeks)w"
        }
    }
}

// MARK: - Previews

#Preview("SpinOffPreviewCard") {
    VStack(spacing: 20) {
        SpinOffPreviewCard(
            thumbnailURL: "",
            creatorName: "carol_smith",
            title: "Hot take: pineapple belongs on pizza",
            onTapViewOriginal: {}
        )
        
        SpinOffPreviewCard(
            thumbnailURL: "",
            creatorName: "john_doe",
            title: "Why I think AI will change everything",
            onTapViewOriginal: nil,
            isCompact: true
        )
    }
    .padding()
    .background(Color.black)
}

#Preview("SpinOffBadge") {
    VStack(spacing: 20) {
        SpinOffBadge(creatorName: "carol_smith", onTap: {})
        SpinOffBadge(creatorName: "very_long_username_here", onTap: nil)
    }
    .padding()
    .background(Color.black)
}

#Preview("SpinOffCountIndicator") {
    HStack(spacing: 30) {
        SpinOffCountIndicator(count: 5, onTap: {})
        SpinOffCountIndicator(count: 1234, onTap: {})
        SpinOffCountIndicator(count: 1500000, onTap: {})
    }
    .padding()
    .background(Color.black)
}