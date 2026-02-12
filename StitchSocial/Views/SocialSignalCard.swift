//
//  SocialSignalCard.swift
//  StitchSocial
//
//  Created by James Garmon on 2/7/26.
//


//
//  SocialSignalCard.swift
//  StitchSocial
//
//  Layer 8: Views - Social Signal Feed Card
//  Dependencies: SocialSignal model, AsyncImage
//  Features: Shows "X hyped this" in feed, tap to view fullscreen
//

import SwiftUI

struct SocialSignalCard: View {
    let signal: SocialSignal
    let onTapToWatch: () -> Void
    let onDismiss: () -> Void
    let onAppear: () -> Void        // Fires impression tracking
    
    // Tier color mapping
    private var tierColor: Color {
        switch signal.engagerTier {
        case "founder":     return Color(red: 1.0, green: 0.84, blue: 0.0)   // Gold
        case "coFounder":   return Color(red: 0.85, green: 0.65, blue: 1.0)  // Purple
        case "topCreator":  return Color(red: 1.0, green: 0.42, blue: 0.21)  // Orange
        case "legendary":   return Color(red: 0.0, green: 0.87, blue: 1.0)   // Cyan
        case "ambassador":  return Color(red: 0.0, green: 0.78, blue: 0.35)  // Green
        case "elite":       return Color(red: 0.0, green: 0.48, blue: 1.0)   // Blue
        case "partner":     return Color(red: 0.6, green: 0.6, blue: 0.6)    // Silver
        default:            return .white
        }
    }
    
    private var tierLabel: String {
        switch signal.engagerTier {
        case "founder":     return "👑"
        case "coFounder":   return "⭐"
        case "topCreator":  return "🔥"
        case "legendary":   return "💎"
        case "ambassador":  return "🏆"
        case "elite":       return "⚡"
        case "partner":     return "🤝"
        default:            return ""
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Megaphone banner
            HStack(spacing: 8) {
                // Engager profile pic
                if let url = signal.engagerProfileImageURL, !url.isEmpty {
                    AsyncImage(url: URL(string: url)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(tierColor.opacity(0.3))
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(tierColor, lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(tierColor.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(signal.engagerName.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(tierColor)
                        )
                        .overlay(Circle().stroke(tierColor, lineWidth: 1.5))
                }
                
                // "X hyped this"
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(tierLabel)
                            .font(.system(size: 12))
                        
                        Text(signal.engagerName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("hyped this")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Text("+\(signal.hypeWeight) hype")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(tierColor)
                }
                
                Spacer()
                
                // Time ago
                Text(timeAgo(signal.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [tierColor.opacity(0.15), Color.black.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            
            // Video preview area — tap to watch
            Button(action: onTapToWatch) {
                ZStack {
                    // Thumbnail
                    if let thumbURL = signal.videoThumbnailURL, !thumbURL.isEmpty {
                        AsyncImage(url: URL(string: thumbURL)) { image in
                            image.resizable().aspectRatio(9/16, contentMode: .fill)
                        } placeholder: {
                            Color.black
                        }
                    } else {
                        Color.black
                    }
                    
                    // Play overlay
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                        
                        Text("Tap to watch")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Video title bottom
                    VStack {
                        Spacer()
                        HStack {
                            Text(signal.videoTitle)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("by @\(signal.videoCreatorName)")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(9/16, contentMode: .fit)
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tierColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            onAppear() // Track impression
        }
    }
    
    // MARK: - Helpers
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}