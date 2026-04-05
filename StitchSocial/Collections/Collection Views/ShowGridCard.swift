//
//  ShowGridCard.swift
//  StitchSocial
//
//  Created by James Garmon on 4/3/26.
//


//
//  ShowGridCard.swift
//  StitchSocial
//
//  Modern show card for grid layouts.
//  Gradient thumbnail, content type badge, episode count, progress bar.
//  Context menu: View, Edit Show, Delete.
//

import SwiftUI

struct ShowGridCard: View {
    
    let title: String
    let episodes: [VideoCollection]
    let color: Color
    var isOwnProfile: Bool = false
    let onTap: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    private var epCount: Int { episodes.count }
    private var totalSegments: Int { episodes.reduce(0) { $0 + $1.segmentCount } }
    private var contentType: CollectionContentType { episodes.first?.contentType ?? .series }
    private var coverURL: String? { episodes.first?.coverImageURL }
    private var seasonCount: Int {
        Set(episodes.compactMap { $0.seasonId }).count
    }
    private var seasonLabel: String {
        seasonCount <= 1 ? "Season 1" : "\(seasonCount) Seasons"
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail area
                ZStack {
                    // Cover image or gradient
                    if let cover = coverURL, !cover.isEmpty, let url = URL(string: cover) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                gradientPlaceholder
                            }
                        }
                    } else {
                        gradientPlaceholder
                    }
                    
                    // Content type badge — top left
                    VStack {
                        HStack {
                            Text(contentType.displayName.uppercased())
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(color.opacity(0.85))
                                .cornerRadius(8)
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(epCount) episode\(epCount == 1 ? "" : "s")")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.55))
                                .cornerRadius(8)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                // Info section
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "Untitled Show" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(seasonLabel) · \(totalSegments) segments")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                    
                    // Episode progress dots
                    HStack(spacing: 2) {
                        ForEach(0..<min(epCount, 8), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color)
                                .frame(height: 2)
                        }
                        if epCount < 8 {
                            ForEach(0..<(8 - min(epCount, 8)), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 2)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button { onTap() } label: {
                Label("View Episodes", systemImage: "play.rectangle.on.rectangle")
            }
            if isOwnProfile {
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Label("Edit Show", systemImage: "pencil")
                    }
                }
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Show", systemImage: "trash")
                    }
                }
            }
        }
    }
    
    // MARK: - Gradient Placeholder
    
    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.12), Color.black.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: contentType == .podcast ? "mic.fill" :
                    contentType == .series ? "play.rectangle.on.rectangle" :
                    contentType == .documentary ? "doc.text.image" :
                    "film")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.08))
        }
    }
}