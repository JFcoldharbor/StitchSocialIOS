//
//  DraftThumbnailCard.swift
//  StitchSocial
//
//  Created by James Garmon on 4/2/26.
//


//
//  DraftThumbnailCard.swift
//  StitchSocial
//
//  Reusable draft collection thumbnail for profile row.
//  Gray border, draft indicator, context menu for edit/delete.
//

import SwiftUI

struct DraftThumbnailCard: View {
    
    let draft: CollectionDraft
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 80, height: 80)
                    
                    if let firstSeg = draft.segments.first,
                       let thumbURL = firstSeg.thumbnailURL,
                       let url = URL(string: thumbURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            draftPlaceholder
                        }
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        draftPlaceholder
                            .frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Draft badge
                    VStack {
                        HStack {
                            Text("DRAFT")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.gray.opacity(0.7))
                                .cornerRadius(3)
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(draft.segments.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(3)
                        }
                    }
                    .padding(5)
                    .frame(width: 80, height: 80)
                }
                
                Text(draft.title ?? "Untitled")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .frame(width: 80)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Draft", systemImage: "trash")
                }
            }
            Button(action: onTap) {
                Label("Edit Draft", systemImage: "pencil")
            }
        }
    }
    
    private var draftPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 18))
                .foregroundColor(.gray.opacity(0.4))
        }
    }
}