//
//  ThreadViewModel.swift
//  StitchSocial
//
//  Layer 7: ViewModels - Thread Management with Service Integration
//  Dependencies: VideoService, UserService (Layer 4)
//  Features: Thread loading, hierarchy management, statistics calculation
//  ARCHITECTURE COMPLIANT: Only imports Layer 4 services
//

import Foundation
import SwiftUI

/// Thread view model following ProfileViewModel pattern
@MainActor
class ThreadViewModel: ObservableObject {
    
    // MARK: - Dependencies (Layer 4 Only)
    
    private let videoService: VideoService
    private let userService: UserService
    
    // MARK: - Published State
    
    @Published var currentThread: ThreadContext?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var threadVideos: [CoreVideoMetadata] = []
    @Published var threadStarter: CoreVideoMetadata?
    @Published var childVideos: [CoreVideoMetadata] = []
    @Published var threadParticipants: [BasicUserInfo] = []
    
    // MARK: - Private Properties
    
    private var currentThreadID: String?
    private var loadingTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    var hasThread: Bool {
        currentThread != nil
    }
    
    var collectiveHype: Int {
        threadVideos.reduce(0) { $0 + $1.hypeCount }
    }
    
    var totalVideoCount: Int {
        threadVideos.count
    }
    
    var participantCount: Int {
        threadParticipants.count
    }
    
    var threadHealth: Double {
        guard !threadVideos.isEmpty else { return 0.0 }
        
        let totalEngagement = threadVideos.reduce(0) { $0 + $1.hypeCount + $1.coolCount + $1.replyCount }
        let totalViews = threadVideos.reduce(0) { $0 + $1.viewCount }
        
        guard totalViews > 0 else { return 0.0 }
        
        let engagementRate = Double(totalEngagement) / Double(totalViews)
        return min(1.0, engagementRate * 10) // Scale to 0-1 range
    }
    
    // MARK: - Initialization
    
    init(videoService: VideoService, userService: UserService) {
        self.videoService = videoService
        self.userService = userService
    }
    
    // MARK: - Core Operations
    
    /// Load complete thread with all videos and participants
    func loadThread(_ threadID: String) async {
        // Cancel any existing loading task
        loadingTask?.cancel()
        
        loadingTask = Task {
            await MainActor.run {
                self.isLoading = true
                self.errorMessage = nil
                self.currentThreadID = threadID
            }
            
            do {
                // Load thread starter video - FIXED: Remove conditional binding
                let starterVideo = try await videoService.getVideo(id: threadID)
                
                // Load all videos in this thread using available method
                let allThreadVideos = try await loadThreadVideosManually(threadID: threadID)
                
                // Create thread context
                let threadContext = createThreadContext(
                    starter: starterVideo,
                    allVideos: allThreadVideos
                )
                
                // Load participant information
                let participants = await loadParticipants(from: allThreadVideos)
                
                await MainActor.run {
                    self.currentThread = threadContext
                    self.threadStarter = starterVideo
                    self.threadVideos = allThreadVideos
                    self.childVideos = self.getActualChildren()
                    self.threadParticipants = participants
                    self.isLoading = false
                }
                
                print("✅ THREAD VIEWMODEL: Loaded thread \(threadID) with \(allThreadVideos.count) videos")
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
                print("❌ THREAD VIEWMODEL: Failed to load thread: \(error)")
            }
        }
    }
    
    /// Refresh current thread data
    func refreshThread() async {
        guard let threadID = currentThreadID else { return }
        await loadThread(threadID)
    }
    
    // MARK: - Data Filtering Methods
    
    /// Get direct children (replies to thread starter)
    func getActualChildren() -> [CoreVideoMetadata] {
        return threadVideos.filter { $0.conversationDepth == 1 && $0.replyToVideoID == nil }
    }
    
    /// Get stepchildren for specific parent video
    func getStepchildren(for parentID: String) -> [CoreVideoMetadata] {
        return threadVideos.filter {
            $0.conversationDepth == 2 && $0.replyToVideoID == parentID
        }
    }
    
    /// Get all videos at specific conversation depth
    func getVideosAtDepth(_ depth: Int) -> [CoreVideoMetadata] {
        return threadVideos.filter { $0.conversationDepth == depth }
    }
    
    /// Check if video has replies
    func hasReplies(videoID: String) -> Bool {
        return threadVideos.contains { $0.replyToVideoID == videoID }
    }
    
    /// Get reply count for specific video
    func getReplyCount(for videoID: String) -> Int {
        return threadVideos.filter { $0.replyToVideoID == videoID }.count
    }
    
    // MARK: - Private Helper Methods
    
    /// Manual thread video loading using available VideoService methods
    private func loadThreadVideosManually(threadID: String) async throws -> [CoreVideoMetadata] {
        var threadVideos: [CoreVideoMetadata] = []
        
        // Load thread starter - FIXED: Remove conditional binding
        let starter = try await videoService.getVideo(id: threadID)
        threadVideos.append(starter)
        
        // Load children and stepchildren by querying Firebase directly
        // This implementation uses the available methods to reconstruct thread hierarchy
        let allVideos = try await getAllVideosInThread(threadID: threadID)
        threadVideos.append(contentsOf: allVideos)
        
        return threadVideos
    }
    
    /// Get all videos in thread using Firebase query - TEST DATA VERSION
    private func getAllVideosInThread(threadID: String) async throws -> [CoreVideoMetadata] {
        print("🧪 THREAD VIEWMODEL: Loading TEST DATA - 20 children + 10 stepchildren")
        
        var testVideos: [CoreVideoMetadata] = []
        
        // Create 20 child videos (direct replies to thread starter)
        for i in 1...20 {
            let childVideo = CoreVideoMetadata(
                id: "test_child_\(i)",
                title: "Child Reply #\(i): Testing thread display",
                videoURL: "https://sample-videos.com/zip/10/mp4/720/SampleVideo_720x480_1mb.mp4",
                thumbnailURL: "",
                creatorID: "test_creator_\(i)",
                creatorName: "TestCreator\(i)",
                createdAt: Date().addingTimeInterval(-Double(i) * 300), // Spaced 5 minutes apart
                threadID: threadID,
                replyToVideoID: nil, // Direct reply to thread starter
                conversationDepth: 1, // Child level
                viewCount: Int.random(in: 50...500),
                hypeCount: Int.random(in: 5...50),
                coolCount: Int.random(in: 0...10),
                replyCount: Int.random(in: 0...5),
                shareCount: Int.random(in: 0...10),
                temperature: ["cold", "cool", "warm", "hot", "blazing"].randomElement() ?? "warm",
                qualityScore: Int.random(in: 60...95),
                engagementRatio: Double.random(in: 0.02...0.15),
                velocityScore: Double.random(in: 0.1...0.8),
                trendingScore: Double.random(in: 0.0...0.6),
                duration: Double.random(in: 15...60),
                aspectRatio: 9.0/16.0,
                fileSize: Int64.random(in: 500000...2000000),
                discoverabilityScore: Double.random(in: 0.3...0.9),
                isPromoted: false,
                lastEngagementAt: Date().addingTimeInterval(-Double.random(in: 60...3600))
            )
            testVideos.append(childVideo)
        }
        
        // Create 10 stepchild videos (replies to first few children)
        let parentChildIDs = Array(testVideos.prefix(5).map { $0.id }) // First 5 children can have stepchildren
        
        for i in 1...10 {
            let parentChildID = parentChildIDs.randomElement() ?? "test_child_1"
            
            let stepchildVideo = CoreVideoMetadata(
                id: "test_stepchild_\(i)",
                title: "Stepchild Reply #\(i): Response to child",
                videoURL: "https://sample-videos.com/zip/10/mp4/720/SampleVideo_720x480_1mb.mp4",
                thumbnailURL: "",
                creatorID: "test_stepchild_creator_\(i)",
                creatorName: "StepCreator\(i)",
                createdAt: Date().addingTimeInterval(-Double(i) * 180), // Spaced 3 minutes apart
                threadID: threadID,
                replyToVideoID: parentChildID, // Reply to specific child
                conversationDepth: 2, // Stepchild level
                viewCount: Int.random(in: 20...200),
                hypeCount: Int.random(in: 2...25),
                coolCount: Int.random(in: 0...5),
                replyCount: 0, // Stepchildren can't have replies
                shareCount: Int.random(in: 0...5),
                temperature: ["cold", "cool", "warm", "hot"].randomElement() ?? "warm",
                qualityScore: Int.random(in: 50...85),
                engagementRatio: Double.random(in: 0.01...0.10),
                velocityScore: Double.random(in: 0.05...0.5),
                trendingScore: Double.random(in: 0.0...0.3),
                duration: Double.random(in: 10...45),
                aspectRatio: 9.0/16.0,
                fileSize: Int64.random(in: 300000...1500000),
                discoverabilityScore: Double.random(in: 0.2...0.7),
                isPromoted: false,
                lastEngagementAt: Date().addingTimeInterval(-Double.random(in: 30...1800))
            )
            testVideos.append(stepchildVideo)
        }
        
        print("🧪 TEST DATA: Generated \(testVideos.count) videos (20 children + 10 stepchildren)")
        return testVideos
    }
    
    /// Create ThreadContext from loaded videos
    private func createThreadContext(starter: CoreVideoMetadata, allVideos: [CoreVideoMetadata]) -> ThreadContext {
        
        // Calculate metrics
        let totalEngagement = allVideos.reduce(0) { $0 + $1.hypeCount + $1.coolCount + $1.replyCount }
        let totalViews = allVideos.reduce(0) { $0 + $1.viewCount }
        let avgEngagementRate = totalViews > 0 ? Double(totalEngagement) / Double(totalViews) : 0.0
        
        let metrics = ThreadMetrics(
            totalViews: totalViews,
            totalEngagement: totalEngagement,
            avgEngagementRate: avgEngagementRate,
            threadHealth: threadHealth,
            responseTime: calculateAvgResponseTime(videos: allVideos),
            diversityScore: calculateDiversityScore(videos: allVideos)
        )
        
        // Get unique participant IDs
        let participantIDs = Set(allVideos.map { $0.creatorID })
        
        return ThreadContext(
            id: starter.id,
            threadStarter: starter,
            allVideos: allVideos,
            participants: Array(participantIDs),
            metrics: metrics,
            createdAt: starter.createdAt,
            lastActivity: allVideos.map { $0.createdAt }.max() ?? starter.createdAt
        )
    }
    
    /// Load participant user information
    private func loadParticipants(from videos: [CoreVideoMetadata]) async -> [BasicUserInfo] {
        let uniqueCreatorIDs = Set(videos.map { $0.creatorID })
        var participants: [BasicUserInfo] = []
        
        for creatorID in uniqueCreatorIDs {
            do {
                if let user = try await userService.getUser(id: creatorID) {
                    participants.append(user)
                }
            } catch {
                print("⚠️ THREAD VIEWMODEL: Failed to load participant \(creatorID): \(error)")
            }
        }
        
        return participants.sorted { $0.displayName < $1.displayName }
    }
    
    /// Calculate average response time between videos
    private func calculateAvgResponseTime(videos: [CoreVideoMetadata]) -> TimeInterval {
        guard videos.count > 1 else { return 0 }
        
        let sortedVideos = videos.sorted { $0.createdAt < $1.createdAt }
        var totalTime: TimeInterval = 0
        
        for i in 1..<sortedVideos.count {
            totalTime += sortedVideos[i].createdAt.timeIntervalSince(sortedVideos[i-1].createdAt)
        }
        
        return totalTime / Double(videos.count - 1)
    }
    
    /// Calculate thread diversity score based on unique participants
    private func calculateDiversityScore(videos: [CoreVideoMetadata]) -> Double {
        let uniqueCreators = Set(videos.map { $0.creatorID }).count
        let totalVideos = videos.count
        
        guard totalVideos > 0 else { return 0.0 }
        
        return Double(uniqueCreators) / Double(totalVideos)
    }
    
    // MARK: - Cleanup
    
    deinit {
        loadingTask?.cancel()
    }
}

// MARK: - Supporting Data Structures

/// Thread context data structure
struct ThreadContext {
    let id: String
    let threadStarter: CoreVideoMetadata
    let allVideos: [CoreVideoMetadata]
    let participants: [String]
    let metrics: ThreadMetrics
    let createdAt: Date
    let lastActivity: Date
}

/// Thread performance metrics
struct ThreadMetrics {
    let totalViews: Int
    let totalEngagement: Int
    let avgEngagementRate: Double
    let threadHealth: Double
    let responseTime: TimeInterval
    let diversityScore: Double
}
