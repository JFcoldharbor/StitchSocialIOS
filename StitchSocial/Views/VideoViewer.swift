//
//  WhoViewedSheet.swift
//  StitchSocial
//
//  Layer 8: Views - Simple "Who Viewed" Analytics Sheet
//  Dependencies: SwiftUI, VideoService, UserService
//  Features: Basic viewer list, timestamps, minimal UI
//

import SwiftUI

// MARK: - Simple Viewer Data Model
struct VideoViewer {
    let userID: String
    let username: String
    let displayName: String
    let profileImageURL: String?
    let viewedAt: Date
    let watchTime: TimeInterval
    let isVerified: Bool
}

// MARK: - Who Viewed Sheet
struct WhoViewedSheet: View {
    
    // MARK: - Properties
    let videoID: String
    let videoTitle: String
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Services
    @StateObject private var videoService = VideoService()
    @StateObject private var userService = UserService()
    
    // MARK: - State
    @State private var viewers: [VideoViewer] = []
    @State private var isLoading = true
    @State private var totalViews = 0
    @State private var uniqueViewers = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Stats
                statsHeader
                
                // Viewer List
                if isLoading {
                    loadingView
                } else if viewers.isEmpty {
                    emptyStateView
                } else {
                    viewerList
                }
            }
            .navigationTitle("Who Viewed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadViewerData()
        }
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        VStack(spacing: 12) {
            // Video Title
            Text(videoTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // View Stats
            HStack(spacing: 24) {
                VStack {
                    Text("\(totalViews)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Total Views")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(uniqueViewers)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Unique Viewers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Viewer List
    private var viewerList: some View {
        List(viewers, id: \.userID) { viewer in
            ViewerRow(viewer: viewer)
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading viewers...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Views Yet")
                .font(.headline)
            
            Text("When people view your video, they'll appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load Data
    private func loadViewerData() async {
        do {
            // Get video analytics
            let analytics = try await videoService.getVideoAnalytics(videoID: videoID)
            
            // Get viewer details
            let viewerData = try await videoService.getVideoViewers(videoID: videoID)
            
            await MainActor.run {
                self.totalViews = analytics.totalViews
                self.uniqueViewers = analytics.uniqueViewers
                self.viewers = viewerData
                self.isLoading = false
            }
            
        } catch {
            print("Failed to load viewer data: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Viewer Row
struct ViewerRow: View {
    let viewer: VideoViewer
    
    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: viewer.viewedAt, relativeTo: Date())
    }
    
    private var watchTimeText: String {
        if viewer.watchTime < 60 {
            return "\(Int(viewer.watchTime))s"
        } else {
            let minutes = Int(viewer.watchTime / 60)
            let seconds = Int(viewer.watchTime.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image
            AsyncImage(url: URL(string: viewer.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(viewer.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if viewer.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                
                Text("@\(viewer.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // View Info
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeAgoText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(watchTimeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - VideoService Extension
extension VideoService {
    
    /// Get list of users who viewed a video
    func getVideoViewers(videoID: String) async throws -> [VideoViewer] {
        // Get interactions for this video
        let snapshot = try await db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .whereField(FirebaseSchema.InteractionDocument.engagementType, isEqualTo: "view")
            .order(by: FirebaseSchema.InteractionDocument.timestamp, descending: true)
            .limit(to: 100) // Limit for performance
            .getDocuments()
        
        var viewers: [VideoViewer] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            guard let userID = data[FirebaseSchema.InteractionDocument.userID] as? String,
                  let timestamp = data[FirebaseSchema.InteractionDocument.timestamp] as? Timestamp else {
                continue
            }
            
            let watchTime = data["watchTime"] as? TimeInterval ?? 0
            let viewedAt = timestamp.dateValue()
            
            // Get user details
            if let user = try? await UserService().getUser(id: userID) {
                let viewer = VideoViewer(
                    userID: userID,
                    username: user.username,
                    displayName: user.displayName,
                    profileImageURL: user.profileImageURL,
                    viewedAt: viewedAt,
                    watchTime: watchTime,
                    isVerified: user.isVerified
                )
                viewers.append(viewer)
            }
        }
        
        return viewers
    }
}

#Preview {
    WhoViewedSheet(
        videoID: "sample_video_id",
        videoTitle: "My Awesome Video"
    )
}