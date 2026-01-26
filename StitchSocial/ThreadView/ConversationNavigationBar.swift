//
//  ConversationNavigationBar.swift
//  StitchSocial
//
//  Bottom navigation showing direct replies to current video
//  Replaces play/pause controls when video has replies
//

import SwiftUI

struct ConversationNavigationBar: View {
    let parentVideo: CoreVideoMetadata
    let directReplies: [CoreVideoMetadata]
    let currentConversationPartner: String?  // Currently viewing conversation with this person
    let onSelectReply: (CoreVideoMetadata) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("Direct Replies (\(directReplies.count))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            // Horizontal scrollable thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(directReplies) { reply in
                        ReplyThumbnailButton(
                            video: reply,
                            isSelected: currentConversationPartner == reply.creatorID,
                            messageCount: getMessageCount(for: reply)
                        )
                        .onTapGesture {
                            print("🎬 NAV BAR: Selected reply from \(reply.creatorName)")
                            onSelectReply(reply)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 100)
        }
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Blur background
                Color.black.opacity(0.6)
                    .blur(radius: 20)
                
                // Glass effect
                Color.white.opacity(0.05)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private func getMessageCount(for reply: CoreVideoMetadata) -> Int {
        // For now, return reply count
        // Later could be enhanced to count full conversation depth
        return reply.replyCount
    }
}

// MARK: - Reply Thumbnail Button

private struct ReplyThumbnailButton: View {
    let video: CoreVideoMetadata
    let isSelected: Bool
    let messageCount: Int
    
    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with border
            ZStack {
                // Thumbnail
                if let thumbnailURL = URL(string: video.thumbnailURL) {
                    AsyncImage(url: thumbnailURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                } else {
                    Color.gray.opacity(0.3)
                }
                
                // Selected indicator overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan, lineWidth: 3)
                }
            }
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                // Selection ring
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.cyan : Color.white.opacity(0.3), lineWidth: isSelected ? 3 : 1)
            )
            
            // Creator name
            Text(video.creatorName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .cyan : .white.opacity(0.9))
                .lineLimit(1)
            
            // Message count badge
            if messageCount > 0 {
                Text("\(messageCount) msg\(messageCount == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.cyan : Color.purple.opacity(0.8))
                    )
            }
        }
        .frame(width: 80)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview

struct ConversationNavigationBar_Previews: PreviewProvider {
    static var previews: some View {
        ConversationNavigationBar(
            parentVideo: CoreVideoMetadata(
                id: "parent",
                title: "Parent Video",
                description: "",
                taggedUserIDs: [],
                videoURL: "",
                thumbnailURL: "",
                creatorID: "user1",
                creatorName: "User",
                createdAt: Date(),
                threadID: nil,
                replyToVideoID: nil,
                conversationDepth: 1,
                viewCount: 100,
                hypeCount: 10,
                coolCount: 0,
                replyCount: 3,
                shareCount: 5,
                temperature: "hot",
                qualityScore: 80,
                engagementRatio: 0.5,
                velocityScore: 10.0,
                trendingScore: 50.0,
                duration: 15.0,
                aspectRatio: 9/16,
                fileSize: 1024000,
                discoverabilityScore: 0.8,
                isPromoted: false,
                lastEngagementAt: Date()
            ),
            directReplies: [
                CoreVideoMetadata(
                    id: "reply1",
                    title: "Reply",
                    description: "",
                    taggedUserIDs: [],
                    videoURL: "",
                    thumbnailURL: "",
                    creatorID: "person_a",
                    creatorName: "Person A",
                    createdAt: Date(),
                    threadID: "parent",
                    replyToVideoID: "parent",
                    conversationDepth: 2,
                    viewCount: 50,
                    hypeCount: 5,
                    coolCount: 0,
                    replyCount: 4,
                    shareCount: 2,
                    temperature: "warm",
                    qualityScore: 70,
                    engagementRatio: 0.4,
                    velocityScore: 5.0,
                    trendingScore: 30.0,
                    duration: 10.0,
                    aspectRatio: 9/16,
                    fileSize: 512000,
                    discoverabilityScore: 0.6,
                    isPromoted: false,
                    lastEngagementAt: Date()
                ),
                CoreVideoMetadata(
                    id: "reply2",
                    title: "Reply",
                    description: "",
                    taggedUserIDs: [],
                    videoURL: "",
                    thumbnailURL: "",
                    creatorID: "person_b",
                    creatorName: "Person B",
                    createdAt: Date(),
                    threadID: "parent",
                    replyToVideoID: "parent",
                    conversationDepth: 2,
                    viewCount: 25,
                    hypeCount: 3,
                    coolCount: 0,
                    replyCount: 2,
                    shareCount: 1,
                    temperature: "warm",
                    qualityScore: 60,
                    engagementRatio: 0.3,
                    velocityScore: 3.0,
                    trendingScore: 20.0,
                    duration: 10.0,
                    aspectRatio: 9/16,
                    fileSize: 512000,
                    discoverabilityScore: 0.5,
                    isPromoted: false,
                    lastEngagementAt: Date()
                )
            ],
            currentConversationPartner: "person_a",
            onSelectReply: { _ in }
        )
        .preferredColorScheme(.dark)
    }
}
