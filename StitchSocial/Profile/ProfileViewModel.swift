//
//  ProfileViewModel.swift
//  CleanBeta
//
//  Layer 7: ViewModels - Profile Data Management
//  Dependencies: AuthService, UserService, VideoService (Layer 4)
//  Handles all business logic for ProfileView
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ProfileViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let authService: AuthService
    private let userService: UserService
    private let videoService: VideoService
    
    // MARK: - Profile State
    
    @Published var currentUser: BasicUserInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Social State
    
    @Published var followingList: [BasicUserInfo] = []
    @Published var followersList: [BasicUserInfo] = []
    @Published var isLoadingFollowing = false
    @Published var isLoadingFollowers = false
    @Published var isFollowing = false
    
    // MARK: - Video Grid State
    
    @Published var selectedTab = 0
    @Published var userVideos: [CoreVideoMetadata] = []
    @Published var isLoadingVideos = false
    
    // MARK: - Animation State (Reference existing ProfileAnimationController)
    
    @Published var animationController: ProfileAnimationController
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService) {
        self.authService = authService
        self.userService = userService
        self.videoService = videoService
        self.animationController = ProfileAnimationController()
    }
    
    // MARK: - Data Loading
    
    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let currentUserID = authService.currentUser?.id else {
                throw StitchError.authenticationError("No authenticated user")
            }
            
            if let userProfile = try await userService.getUser(id: currentUserID) {
                currentUser = userProfile
                await loadUserContent()
                animationController.startEntranceSequence(hypeProgress: calculateHypeProgress())
            } else {
                errorMessage = "Profile not found"
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadUserContent() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadUserVideos() }
            group.addTask { await self.loadFollowing() }
            group.addTask { await self.loadFollowers() }
        }
    }
    
    func loadUserVideos() async {
        guard let user = currentUser else { return }
        isLoadingVideos = true
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: user.id)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: 50)
                .getDocuments()
            
            userVideos = snapshot.documents.compactMap { doc in
                let data = doc.data()
                return CoreVideoMetadata(
                    id: doc.documentID,
                    title: data[FirebaseSchema.VideoDocument.title] as? String ?? "Untitled",
                    videoURL: data[FirebaseSchema.VideoDocument.videoURL] as? String ?? "",
                    thumbnailURL: data[FirebaseSchema.VideoDocument.thumbnailURL] as? String ?? "",
                    creatorID: data[FirebaseSchema.VideoDocument.creatorID] as? String ?? "",
                    creatorName: data[FirebaseSchema.VideoDocument.creatorName] as? String ?? "",
                    createdAt: (data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp)?.dateValue() ?? Date(),
                    threadID: data[FirebaseSchema.VideoDocument.threadID] as? String,
                    replyToVideoID: data[FirebaseSchema.VideoDocument.replyToVideoID] as? String,
                    conversationDepth: data[FirebaseSchema.VideoDocument.conversationDepth] as? Int ?? 0,
                    viewCount: data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0,
                    hypeCount: data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0,
                    coolCount: data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0,
                    replyCount: data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0,
                    shareCount: data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0,
                    temperature: data[FirebaseSchema.VideoDocument.temperature] as? String ?? "neutral",
                    qualityScore: data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 0,
                    engagementRatio: 0.0,
                    velocityScore: 0.0,
                    trendingScore: 0.0,
                    duration: data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0,
                    aspectRatio: data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 16.0/9.0,
                    fileSize: data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0,
                    discoverabilityScore: data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.0,
                    isPromoted: data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false,
                    lastEngagementAt: (data[FirebaseSchema.VideoDocument.lastEngagementAt] as? Timestamp)?.dateValue()
                )
            }
        } catch {
            userVideos = []
        }
        
        isLoadingVideos = false
    }
    
    func loadFollowing() async {
        guard let user = currentUser else { return }
        isLoadingFollowing = true
        
        do {
            followingList = try await userService.getFollowing(userID: user.id)
        } catch {
            followingList = []
        }
        
        isLoadingFollowing = false
    }
    
    func loadFollowers() async {
        guard let user = currentUser else { return }
        isLoadingFollowers = true
        
        do {
            followersList = try await userService.getFollowers(userID: user.id)
        } catch {
            followersList = []
        }
        
        isLoadingFollowers = false
    }
    
    // MARK: - Video Management (With implemented deletion methods)
    
    func deleteVideo(_ video: CoreVideoMetadata) async -> Bool {
        do {
            try await videoService.deleteVideo(videoID: video.id, creatorID: video.creatorID)
            await loadUserVideos() // Refresh video list
            return true
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            return false
        }
    }
    
    func deleteMultipleVideos(_ videoIDs: [String]) async -> Bool {
        guard let user = currentUser else { return false }
        
        do {
            try await videoService.deleteVideos(videoIDs: videoIDs, creatorID: user.id)
            await loadUserVideos() // Refresh video list
            return true
        } catch {
            errorMessage = "Failed to delete videos: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Social Features
    
    func toggleFollow() async {
        guard let user = currentUser, !isOwnProfile else { return }
        
        do {
            let currentUserID = authService.currentUser?.id ?? ""
            
            if isFollowing {
                try await userService.unfollowUser(followerID: currentUserID, followingID: user.id)
                isFollowing = false
            } else {
                try await userService.followUser(followerID: currentUserID, followingID: user.id)
                isFollowing = true
            }
            
            await loadFollowers()
            await loadFollowing()
            
        } catch {
            errorMessage = "Failed to update follow status: \(error.localizedDescription)"
        }
    }
    
    func shareProfile() {
        guard let user = currentUser else { return }
        
        let shareText = "Check out \(user.displayName)'s profile on Stitch Social!"
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Profile Editing
    
    func updateProfileImage() async {
        // Implementation for profile image update
    }
    
    func updateBio(_ newBio: String) async {
        guard let user = currentUser else { return }
        
        do {
            try await userService.updateProfile(
                userID: user.id,
                displayName: nil,
                bio: newBio,
                isPrivate: nil
            )
            
            await loadProfile()
        } catch {
            errorMessage = "Failed to update bio: \(error.localizedDescription)"
        }
    }
    
    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Business Logic Calculations
    
    func calculateHypeProgress() -> CGFloat {
        guard let user = currentUser else { return 0.5 }
        return CGFloat(calculateHypePercentage(user)) / 100.0
    }
    
    func calculateHypePercentage(_ user: BasicUserInfo) -> Int {
        let clout = user.clout
        let tierMultiplier: Double
        
        switch user.tier {
        case .founder, .coFounder: tierMultiplier = 1.0
        case .topCreator: tierMultiplier = 0.9
        case .partner: tierMultiplier = 0.8
        case .influencer: tierMultiplier = 0.7
        case .rising: tierMultiplier = 0.6
        case .rookie: tierMultiplier = 0.5
        default: tierMultiplier = 0.5
        }
        
        let basePercentage = min(100, (Double(clout) / 10000.0) * 100 * tierMultiplier)
        return Int(basePercentage)
    }
    
    func getUserInitials(_ user: BasicUserInfo) -> String {
        let name = user.displayName
        return String(name.prefix(2).uppercased())
    }
    
    func getBioForUser(_ user: BasicUserInfo) -> String? {
        switch user.tier {
        case .founder: return "Founder of Stitch Social"
        case .coFounder: return "Co-Founder of Stitch Social"
        case .topCreator: return "Top Creator on Stitch"
        default: return nil
        }
    }
    
    func getBadgesForUser(_ user: BasicUserInfo) -> [ProfileBadgeInfo] {
        var badges: [ProfileBadgeInfo] = []
        
        if user.isVerified {
            badges.append(ProfileBadgeInfo(id: "verified", iconName: "checkmark", colors: [.cyan, .blue], title: "Verified"))
        }
        
        switch user.tier {
        case .founder, .coFounder:
            badges.append(ProfileBadgeInfo(id: "founder", iconName: "crown.fill", colors: [.yellow, .orange], title: "Founder"))
        case .topCreator:
            badges.append(ProfileBadgeInfo(id: "top", iconName: "star.fill", colors: [.blue, .purple], title: "Top Creator"))
        default:
            break
        }
        
        return badges
    }
    
    func getTabCount(_ index: Int) -> Int {
        switch index {
        case 0: return userVideos.filter { $0.conversationDepth == 0 }.count
        case 1: return userVideos.filter { $0.conversationDepth == 1 }.count
        case 2: return userVideos.filter { $0.conversationDepth >= 2 }.count
        default: return 0
        }
    }
    
    func formatClout(_ clout: Int) -> String {
        if clout >= 1000000 {
            return String(format: "%.1fM", Double(clout) / 1000000.0)
        } else if clout >= 1000 {
            return String(format: "%.1fK", Double(clout) / 1000.0)
        } else {
            return "\(clout)"
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
    
    // MARK: - Computed Properties
    
    var isOwnProfile: Bool {
        guard let currentUserID = authService.currentUser?.id,
              let profileUserID = currentUser?.id else { return false }
        return currentUserID == profileUserID
    }
    
    var tabTitles: [String] {
        ["Threads", "Stitches", "Replies"]
    }
    
    var tabIcons: [String] {
        ["play.rectangle.fill", "link", "arrowshape.turn.up.left.fill"]
    }
    
    func filteredVideos(for tab: Int) -> [CoreVideoMetadata] {
        switch tab {
        case 0: return userVideos.filter { $0.conversationDepth == 0 }
        case 1: return userVideos.filter { $0.conversationDepth == 1 }
        case 2: return userVideos.filter { $0.conversationDepth >= 2 }
        default: return userVideos
        }
    }
}

// MARK: - Supporting Types

struct ProfileBadgeInfo {
    let id: String
    let iconName: String
    let colors: [Color]
    let title: String
}

// ProfileAnimationController is defined in ProfileAnimations.swift - using existing implementation
