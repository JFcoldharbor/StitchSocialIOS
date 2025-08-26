//
//  AsyncThumbnailView.swift
//  StitchSocial
//
//  Created by James Garmon on 8/25/25.
//


//
//  AsyncThumbnailView.swift
//  CleanBeta
//
//  Layer 8: Views - Async Thumbnail Loading Component
//  Fixes main thread blocking by using background URLSession
//  Replaces all AsyncImage calls for Firebase Storage thumbnails
//

import SwiftUI
import Foundation

struct AsyncThumbnailView: View {
    let url: String
    let aspectRatio: CGFloat
    let contentMode: ContentMode
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadingFailed = false
    
    init(
        url: String, 
        aspectRatio: CGFloat = 9.0/16.0, 
        contentMode: ContentMode = .fill
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loadingFailed {
                // Error state
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.6))
                    )
            } else {
                // Loading state
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .scaleEffect(0.8)
                    )
            }
        }
        .task {
            await loadImageAsync()
        }
        .onChange(of: url) { _, newURL in
            // Reset state when URL changes
            image = nil
            isLoading = true
            loadingFailed = false
            
            Task {
                await loadImageAsync()
            }
        }
    }
    
    @MainActor
    private func loadImageAsync() {
        guard !url.isEmpty, let imageURL = URL(string: url) else {
            loadingFailed = true
            isLoading = false
            return
        }
        
        // Move network loading to background queue
        Task.detached(priority: .userInitiated) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                
                guard let uiImage = UIImage(data: data) else {
                    await MainActor.run {
                        self.loadingFailed = true
                        self.isLoading = false
                    }
                    return
                }
                
                // Update UI on main thread
                await MainActor.run {
                    self.image = uiImage
                    self.isLoading = false
                    self.loadingFailed = false
                }
                
            } catch {
                await MainActor.run {
                    self.loadingFailed = true
                    self.isLoading = false
                }
                print("THUMBNAIL LOAD ERROR: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Convenience Initializers

extension AsyncThumbnailView {
    
    /// Square thumbnail for profile grids
    static func profileGrid(url: String) -> AsyncThumbnailView {
        AsyncThumbnailView(url: url, aspectRatio: 1.0, contentMode: .fill)
    }
    
    /// Video thumbnail for feeds
    static func videoThumbnail(url: String) -> AsyncThumbnailView {
        AsyncThumbnailView(url: url, aspectRatio: 9.0/16.0, contentMode: .fill)
    }
    
    /// Circle avatar for user profiles
    static func avatar(url: String) -> some View {
        AsyncThumbnailView(url: url, aspectRatio: 1.0, contentMode: .fill)
            .clipShape(Circle())
    }
}