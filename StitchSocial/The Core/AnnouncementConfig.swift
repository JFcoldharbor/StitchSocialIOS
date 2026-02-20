//
//  AnnouncementConfig.swift
//  StitchSocial
//
//  Created by James Garmon on 2/9/26.
//


//
//  BackgroundPostManager.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Background Video Posting
//  Dependencies: VideoCoordinator, AuthService, NotificationService
//  Features: Queues posts, runs upload in background, tracks progress
//
//  User taps Post → ThreadComposer dismisses immediately
//  This manager picks up the work and runs compress+upload+integrate in background
//

import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Announcement Config (passed from ThreadComposer)

struct AnnouncementConfig {
    let priority: AnnouncementPriority
    let type: AnnouncementType
    let minimumWatchSeconds: Int
    let startDate: Date
    let endDate: Date?
    let repeatMode: AnnouncementRepeatMode
    let maxDailyShows: Int
    let minHoursBetweenShows: Double
    let maxTotalShows: Int?
    let creatorEmail: String
}

// MARK: - Pending Post

struct PendingPost: Identifiable {
    let id: String = UUID().uuidString
    let videoURL: URL
    let recordingContext: RecordingContext
    let title: String
    let description: String
    let hashtags: [String]
    let taggedUserIDs: [String]
    let recordingSource: String
    let isAnnouncement: Bool
    let announcementConfig: AnnouncementConfig?
    let queuedAt: Date = Date()
}

// MARK: - Post Status

enum PostStatus: String {
    case queued = "Queued"
    case compressing = "Compressing..."
    case uploading = "Uploading..."
    case integrating = "Finishing up..."
    case complete = "Posted!"
    case failed = "Failed"
}

// MARK: - Background Post Manager

@MainActor
class BackgroundPostManager: ObservableObject {
    
    static let shared = BackgroundPostManager()
    
    // MARK: - Published State
    
    @Published var currentPost: PendingPost?
    @Published var status: PostStatus = .queued
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var isPosting: Bool = false
    @Published var lastError: String?
    @Published var showCompletionBanner: Bool = false
    
    // Queue for multiple posts (rare but possible)
    @Published var postQueue: [PendingPost] = []
    
    // MARK: - Private
    
    private var currentTask: Task<Void, Never>?
    
    private init() {
        print("📮 BACKGROUND POST: Manager initialized")
    }
    
    // MARK: - Queue Post
    
    func queuePost(
        videoURL: URL,
        recordingContext: RecordingContext,
        title: String,
        description: String,
        hashtags: [String],
        taggedUserIDs: [String],
        recordingSource: String,
        isAnnouncement: Bool,
        announcementConfig: AnnouncementConfig?
    ) {
        let post = PendingPost(
            videoURL: videoURL,
            recordingContext: recordingContext,
            title: title,
            description: description,
            hashtags: hashtags,
            taggedUserIDs: taggedUserIDs,
            recordingSource: recordingSource,
            isAnnouncement: isAnnouncement,
            announcementConfig: announcementConfig
        )
        
        postQueue.append(post)
        print("📮 BACKGROUND POST: Queued '\(title)' (\(postQueue.count) in queue)")
        
        // Start processing if not already
        if !isPosting {
            processNextPost()
        }
    }
    
    // MARK: - Process Queue
    
    private func processNextPost() {
        guard !postQueue.isEmpty else {
            isPosting = false
            currentPost = nil
            return
        }
        
        let post = postQueue.removeFirst()
        currentPost = post
        isPosting = true
        status = .queued
        progress = 0.0
        lastError = nil
        
        currentTask = Task {
            await executePost(post)
        }
    }
    
    // MARK: - Execute Post
    
    private func executePost(_ post: PendingPost) async {
        print("🚀 BACKGROUND POST: Starting '\(post.title)'")
        
        do {
            // Get auth
            let authService = AuthService()
            let currentUserID = authService.currentUser?.id ?? Auth.auth().currentUser?.uid ?? "unknown"
            let currentUserTier = authService.currentUser?.tier ?? .rookie
            
            // Create a fresh VideoCoordinator for this post
            let coordinator = VideoCoordinator(
                videoService: VideoService(),
                userService: UserService(),
                aiAnalyzer: AIVideoAnalyzer.shared,
                uploadService: VideoUploadService()
            )
            
            // Observe coordinator progress
            let progressTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    
                    await MainActor.run {
                        let phase = coordinator.currentPhase
                        self.progress = coordinator.overallProgress
                        
                        switch phase {
                        case .parallelProcessing:
                            self.status = .compressing
                            self.statusMessage = coordinator.currentTask
                        case .uploading:
                            self.status = .uploading
                            self.statusMessage = "Uploading video..."
                        case .integrating:
                            self.status = .integrating
                            self.statusMessage = "Creating post..."
                        case .complete:
                            self.status = .complete
                        default:
                            break
                        }
                    }
                }
            }
            
            status = .compressing
            statusMessage = "Processing video..."
            
            let createdVideo = try await coordinator.processVideoCreation(
                recordedVideoURL: post.videoURL,
                recordingContext: post.recordingContext,
                userID: currentUserID,
                userTier: currentUserTier,
                manualTitle: post.title.isEmpty ? nil : post.title,
                manualDescription: post.description.isEmpty ? nil : post.description,
                taggedUserIDs: post.taggedUserIDs,
                recordingSource: post.recordingSource,
                hashtags: post.hashtags
            )
            
            progressTask.cancel()
            
            // Handle announcement if needed
            if post.isAnnouncement, let config = post.announcementConfig {
                await createAnnouncement(for: createdVideo, config: config)
            }
            
            // Success
            status = .complete
            progress = 1.0
            statusMessage = "Posted!"
            
            print("✅ BACKGROUND POST: '\(post.title)' posted successfully as \(createdVideo.id)")
            
            // Show completion banner briefly
            showCompletionBanner = true
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            showCompletionBanner = false
            
            // Process next in queue
            processNextPost()
            
        } catch {
            print("❌ BACKGROUND POST: Failed - \(error.localizedDescription)")
            
            status = .failed
            lastError = error.localizedDescription
            statusMessage = "Failed to post"
            isPosting = false
            
            // Keep the post for retry
            postQueue.insert(post, at: 0)
        }
    }
    
    // MARK: - Retry
    
    func retryFailed() {
        guard status == .failed, !postQueue.isEmpty else { return }
        lastError = nil
        processNextPost()
    }
    
    // MARK: - Cancel
    
    func cancelCurrentPost() {
        currentTask?.cancel()
        currentTask = nil
        currentPost = nil
        isPosting = false
        status = .queued
        progress = 0.0
    }
    
    // MARK: - Announcement Helper
    
    private func createAnnouncement(for video: CoreVideoMetadata, config: AnnouncementConfig) async {
        do {
            let announcement = try await AnnouncementService.shared.createAnnouncement(
                videoId: video.id,
                creatorEmail: config.creatorEmail,
                creatorId: video.creatorID,
                title: video.title,
                message: video.description.isEmpty ? nil : video.description,
                priority: config.priority,
                type: config.type,
                targetAudience: .all,
                startDate: config.startDate,
                endDate: config.endDate,
                minimumWatchSeconds: config.minimumWatchSeconds,
                isDismissable: true,
                requiresAcknowledgment: false,
                repeatMode: config.repeatMode,
                maxDailyShows: config.maxDailyShows,
                minHoursBetweenShows: config.minHoursBetweenShows,
                maxTotalShows: config.maxTotalShows
            )
            print("📢 BACKGROUND POST: Announcement created - \(announcement.id)")
        } catch {
            print("⚠️ BACKGROUND POST: Announcement failed - \(error)")
        }
    }
}
