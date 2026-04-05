//
//  CollectionThumbnailCard.swift
//  StitchSocial
//
//  Reusable standalone collection thumbnail for profile row.
//  Cover image, segment count badge, title. Context menu for play/delete.
//

import SwiftUI

struct CollectionThumbnailCard: View {
    
    let collection: VideoCollection
    let isOwnProfile: Bool
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    // Cover image or placeholder
                    if let coverURL = collection.coverImageURL, let url = URL(string: coverURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            placeholder
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        placeholder
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Segment count badge
                    Text("\(collection.segmentCount) seg")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(3)
                        .padding(4)
                }
                .frame(width: 100, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                
                Text(collection.title.isEmpty ? "Untitled" : collection.title)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 100)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if isOwnProfile {
                Button { onTap() } label: {
                    Label("Play", systemImage: "play.fill")
                }
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.15))
        }
    }
}
