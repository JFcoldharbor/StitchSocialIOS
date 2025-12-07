//
//  SwipeForRepliesBanner.swift
//  StitchSocial
//
//  Simple banner indicating video has replies - floats on right side of screen
//

import SwiftUI

/// Simple banner that appears on right side of screen for videos with replies
/// Shows "X replies →" to indicate horizontal navigation available
struct SwipeForRepliesBanner: View {
    
    let replyCount: Int
    
    /// Only show if video has at least one reply
    var shouldShow: Bool {
        replyCount > 0
    }
    
    private var message: String {
        if replyCount == 1 {
            return "1"
        } else {
            return "\(replyCount)"
        }
    }
    
    var body: some View {
        if shouldShow {
            VStack(spacing: 4) {
                // Reply count bubble
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
                        
                        Text(message)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: .purple.opacity(0.5), radius: 6, x: 0, y: 3)
                
                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("replies")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
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
                SwipeForRepliesBanner(replyCount: 3)
                Spacer()
            }
            .padding(.trailing, 12)
        }
    }
}
