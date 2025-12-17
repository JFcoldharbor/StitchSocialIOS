//
//  CreatorPill.swift
//  StitchSocial
//
//  Layer 8: Views - Extracted Creator Profile Pill Component
//  Dependencies: CoreVideoMetadata
//  Features: Tappable creator profile with context indicators, thread creator differentiation
//

import SwiftUI

struct CreatorPill: View {
    
    // MARK: - Properties
    
    let creator: CoreVideoMetadata
    let isThread: Bool
    let colors: [Color]
    let displayName: String
    let profileImageURL: String?
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Profile Image - with error handling
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                    
                    if let urlString = profileImageURL,
                       let url = URL(string: urlString),
                       !urlString.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: isThread ? 28 : 24, height: isThread ? 28 : 24)
                                    .clipShape(Circle())
                            case .failure:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: isThread ? 12 : 10))
                                            .foregroundColor(.white.opacity(0.6))
                                    )
                            case .empty:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                            @unknown default:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                        }
                        .frame(width: isThread ? 28 : 24, height: isThread ? 28 : 24)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: isThread ? 12 : 10))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    }
                }
                .frame(width: isThread ? 28 : 24, height: isThread ? 28 : 24)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                
                // Creator Name and Context
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: isThread ? 13 : 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if isThread {
                            Text("thread creator")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, isThread ? 12 : 8)
            .padding(.vertical, isThread ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: isThread ? 16 : 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ContextualScaleButtonStyle())
    }
}

// Note: ContextualScaleButtonStyle is defined in ContextualVideoOverlay.swift

// MARK: - Preview

struct CreatorPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 16) {
                // Video creator pill (hot video)
                CreatorPill(
                    creator: CoreVideoMetadata.newThread(
                        title: "Test",
                        videoURL: "",
                        thumbnailURL: "",
                        creatorID: "user1",
                        creatorName: "JohnDoe",
                        duration: 30,
                        fileSize: 1024
                    ),
                    isThread: false,
                    colors: [.red, .orange],
                    displayName: "JohnDoe",
                    profileImageURL: nil,
                    onTap: { print("Tapped video creator") }
                )
                
                // Thread creator pill
                CreatorPill(
                    creator: CoreVideoMetadata.newThread(
                        title: "Test",
                        videoURL: "",
                        thumbnailURL: "",
                        creatorID: "user2",
                        creatorName: "JaneDoe",
                        duration: 30,
                        fileSize: 1024
                    ),
                    isThread: true,
                    colors: [.purple, .pink],
                    displayName: "JaneDoe",
                    profileImageURL: nil,
                    onTap: { print("Tapped thread creator") }
                )
                
                // Cool video creator pill
                CreatorPill(
                    creator: CoreVideoMetadata.newThread(
                        title: "Test",
                        videoURL: "",
                        thumbnailURL: "",
                        creatorID: "user3",
                        creatorName: "AlexSmith",
                        duration: 30,
                        fileSize: 1024
                    ),
                    isThread: false,
                    colors: [.cyan, .blue],
                    displayName: "AlexSmith",
                    profileImageURL: nil,
                    onTap: { print("Tapped cool video creator") }
                )
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}
