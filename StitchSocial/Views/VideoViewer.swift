//
//  VideoViewer.swift
//  StitchSocial
//
//  Video Viewer Analytics and Who Viewed Sheet
//  UPDATED: Merged with viewer tracking improvements - added tier support, better UI
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - VideoViewer Model (UPDATED with tier)
struct VideoViewer: Identifiable, Codable {
    let id = UUID()
    let userID: String
    let username: String
    let displayName: String
    let profileImageURL: String?
    let viewedAt: Date
    let watchTime: TimeInterval
    let isVerified: Bool
    let tier: String  // NEW: User tier for display
    
    // Computed property for time ago display
    var timeAgo: String {
        let interval = Date().timeIntervalSince(viewedAt)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        }
    }
}

// MARK: - WhoViewedSheet (UPDATED UI)
struct WhoViewedSheet: View {
    let videoID: String
    let onDismiss: () -> Void
    
    @StateObject private var videoService = VideoService()
    @State private var viewers: [VideoViewer] = []
    @State private var isLoading = true
    @State private var totalViews = 0
    @State private var uniqueViewers = 0
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if viewers.isEmpty {
                    emptyView
                } else {
                    viewersList
                }
            }
            .navigationTitle("Viewers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            await loadViewerData()
        }
    }
    
    // MARK: - Viewers List (IMPROVED UI)
    
    private var viewersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Stats header
                statsHeader
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Viewer rows
                ForEach(viewers) { viewer in
                    ViewerRow(viewer: viewer)
                    
                    if viewer.id != viewers.last?.id {
                        Divider()
                            .background(Color.gray.opacity(0.2))
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Text("\(totalViews)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Total Views")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 4) {
                Text("\(uniqueViewers)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.purple)
                
                Text("Unique Viewers")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            
            Text("Loading viewers...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Views Yet")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Be patient! Views will appear here once people watch your video.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Error Loading Viewers")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                Task { await loadViewerData() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.purple)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    
    // MARK: - Load Data
    
    private func loadViewerData() async {
        isLoading = true
        errorMessage = nil
        
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
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Viewer Row (UPDATED with tier badge)

struct ViewerRow: View {
    let viewer: VideoViewer
    
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
            // Profile image
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
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewer.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if viewer.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    
                    // NEW: Tier badge
                    if viewer.tier != "rookie" {
                        Text(viewer.tier.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text("@\(viewer.username)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // View info
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewer.timeAgo)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7))
                    
                    Text(watchTimeText)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black)
    }
}

// MARK: - VideoService Extension (UPDATED to include tier)

extension VideoService {
    
    /// Get list of users who viewed a video
    func getVideoViewers(videoID: String) async throws -> [VideoViewer] {
        print("📊 VIDEO SERVICE: Fetching viewers for video \(videoID)")
        
        // Get interactions for this video
        let snapshot = try await db.collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .whereField(FirebaseSchema.InteractionDocument.engagementType, isEqualTo: "view")
            .order(by: FirebaseSchema.InteractionDocument.timestamp, descending: true)
            .limit(to: 100) // Limit for performance
            .getDocuments()
        
        print("📊 VIDEO SERVICE: Found \(snapshot.documents.count) view interactions")
        
        // Extract unique user IDs and their view data
        var viewerMap: [String: (date: Date, watchTime: TimeInterval)] = [:]
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            guard let userID = data[FirebaseSchema.InteractionDocument.userID] as? String,
                  let timestamp = data[FirebaseSchema.InteractionDocument.timestamp] as? Timestamp else {
                continue
            }
            
            let watchTime = data["watchTime"] as? TimeInterval ?? 0
            let viewDate = timestamp.dateValue()
            
            // Keep only the most recent view per user
            if viewerMap[userID] == nil || viewDate > viewerMap[userID]!.date {
                viewerMap[userID] = (date: viewDate, watchTime: watchTime)
            }
        }
        
        print("📊 VIDEO SERVICE: Found \(viewerMap.count) unique viewers")
        
        var viewers: [VideoViewer] = []
        
        // Fetch user details for each viewer
        for (userID, viewData) in viewerMap {
            do {
                if let user = try await UserService().getUser(id: userID) {
                    let viewer = VideoViewer(
                        userID: userID,
                        username: user.username,
                        displayName: user.displayName,
                        profileImageURL: user.profileImageURL,
                        viewedAt: viewData.date,
                        watchTime: viewData.watchTime,
                        isVerified: user.isVerified,
                        tier: user.tier.rawValue
                    )
                    viewers.append(viewer)
                }
            } catch {
                print("⚠️ VIDEO SERVICE: Error fetching user \(userID): \(error)")
                continue
            }
        }
        
        // Sort by most recent views
        viewers.sort { $0.viewedAt > $1.viewedAt }
        
        print("✅ VIDEO SERVICE: Returning \(viewers.count) viewers")
        return viewers
    }
}

// MARK: - Preview

#Preview {
    WhoViewedSheet(
        videoID: "sample_video_id",
        onDismiss: {}
    )
}
