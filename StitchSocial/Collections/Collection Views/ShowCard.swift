//
//  ShowCard.swift
//  StitchSocial
//
//  Created by James Garmon on 4/2/26.
//


//
//  ShowCard.swift
//  StitchSocial
//
//  Reusable show card for profile collections row and discovery.
//  Shows content type badge, title, episode count, mini episode strip.
//

import SwiftUI

struct ShowCard: View {
    
    let episodes: [VideoCollection]
    let onTap: () -> Void
    
    private var firstEp: VideoCollection? { episodes.first }
    private var contentType: CollectionContentType { firstEp?.contentType ?? .series }
    private var color: Color { Self.colorFor(contentType) }
    private var title: String { Self.inferTitle(from: episodes) }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Badge + title + count
                VStack(alignment: .leading, spacing: 3) {
                    Text(contentType.displayName.uppercased())
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(color.opacity(0.2))
                        .cornerRadius(3)
                    
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(episodes.count) episode\(episodes.count == 1 ? "" : "s")")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 5)
                
                // Mini episode strip
                HStack(spacing: 2) {
                    ForEach(Array(episodes.prefix(4).enumerated()), id: \.element.id) { idx, ep in
                        MiniEpisodeCell(
                            label: "EP\(ep.episodeNumber ?? (idx + 1))",
                            color: color,
                            isNewest: idx == episodes.count - 1 && episodes.count > 1
                        )
                    }
                    if episodes.count > 4 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 28)
                            .overlay(
                                Text("+\(episodes.count - 4)")
                                    .font(.system(size: 7, weight: .medium))
                                    .foregroundColor(.white.opacity(0.35))
                            )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(width: 130)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helpers
    
    static func colorFor(_ type: CollectionContentType) -> Color {
        switch type {
        case .podcast: return .orange
        case .shortFilm, .documentary: return .purple
        case .series: return .pink
        case .interview: return .cyan
        case .tutorial: return .green
        case .standard: return .blue
        }
    }
    
    static func inferTitle(from episodes: [VideoCollection]) -> String {
        // Try to find a common show title from episode titles
        // e.g., "House Drama · Ep 1" → "House Drama"
        if let first = episodes.first {
            let t = first.title
            if let dotRange = t.range(of: " · ") ?? t.range(of: " - Ep") ?? t.range(of: ": Ep") {
                return String(t[t.startIndex..<dotRange.lowerBound])
            }
            // Fallback: use first episode title or content type
            if !t.isEmpty { return t }
        }
        return episodes.first?.contentType.displayName ?? "Show"
    }
}

// MARK: - Mini Episode Cell

struct MiniEpisodeCell: View {
    let label: String
    let color: Color
    let isNewest: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isNewest ? color.opacity(0.15) : Color.white.opacity(0.06))
            .frame(height: 28)
            .overlay(
                Text(isNewest ? "NEW" : label)
                    .font(.system(size: 6, weight: isNewest ? .bold : .medium))
                    .foregroundColor(isNewest ? color : .white.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isNewest ? color.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
    }
}