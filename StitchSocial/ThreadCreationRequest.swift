//
//  ThreadService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Thread Management and Hierarchy
//  Dependencies: Layer 3 (Firebase), Layer 2 (Protocols, EventBus), Layer 1 (Foundation)
//  Single responsibility: Thread CRUD operations and parent-child relationship validation
//  Consolidates multiple thread managers under single ThreadManaging protocol
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - Thread Service Types

/// Thread creation request with validation
struct ThreadCreationRequest {
    let title: String
    let videoURL: String
    let thumbnailURL: String
    let creatorID: String
    let creatorName: String
    let duration: TimeInterval
    let fileSize: Int64
    let temperature: Temperature
    let tags: [String]
    
    // Validation computed properties
    var isValid: Bool {
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               title.count >= OptimizationConfig.Threading.minThreadTitleLength &&
               title.count <= OptimizationConfig.Threading.maxThreadTitleLength &&
               !videoURL.isEmpty &&
               !thumbnailURL.isEmpty &&
               !creatorID.isEmpty &&
               duration > 0 &&
               fileSize > 0
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title cannot be empty")
        }
        if title.count < OptimizationConfig.Threading.minThreadTitleLength {
            errors.append("Title too short (minimum \(OptimizationConfig.Threading.minThreadTitleLength) characters)")
        }
        if title.count > OptimizationConfig.Threading.maxThreadTitleLength {
            errors.append("Title too long (maximum \(OptimizationConfig.Threading.maxThreadTitleLength) characters)")
        }
        if videoURL.isEmpty {
            errors.append("Video URL is required")
        }
        if thumbnailURL.isEmpty {
            errors.append("Thumbnail URL is required")
        }
        if creatorID.isEmpty {
            errors.append("Creator ID is required")
        }
        if duration <= 0 {
            errors.append("Duration must be greater than 0")
        }
        if fileSize <= 0 {
            errors.append("File size must be greater than 0")
        }
        
        return errors
    }
}

/// Reply creation request for child/stepchild videos
struct ReplyCreationRequest {
    let parentVideoID: String
    let threadID: String
    let videoURL: String
    let thumbnailURL: String
    let creatorID: String
    let creatorName: String
    let duration: TimeInterval
    let fileSize: Int64
    let temperature: Temperature
    
    var isValid: Bool {
        return !parentVideoID.isEmpty &&
               !threadID.isEmpty &&
               !videoURL.isEmpty &&
               !thumbnailURL.isEmpty &&
               !creatorID.isEmpty &&
               duration > 0 &&
               fileSize > 0
    }
}

/// Thread hierarchy information
struct ThreadHierarchy {
    let threadID: String
    let parentVideo: CoreVideoMetadata
    let childVideos: [CoreVideoMetadata]
    let totalDepth: Int
    let canAddReplies: Bool
    
    var totalVideos: Int {
        return 1 + childVideos.count // 1 for parent + children
    }
    
    var hasReachedMaxDepth: Bool {
        return totalDepth >= OptimizationConfig.Threading.maxConversationDepth
    }
}

/// Thread query filters
struct ThreadQueryFilters {
    let creatorID: String?
    let temperature: Temperature?
    let minEngagement: Int?
    let isActive: Bool?
    let orderBy: ThreadSortOrder
    let limit: Int
    
    static let defaultHomeFeed = ThreadQueryFilters(
        creatorID: nil,
        temperature: nil,
        minEngagement: nil,
        isActive: true,
        orderBy: .chronological,
        limit: 20
    )
    
    static let defaultDiscovery = ThreadQueryFilters(
        creatorID: nil,
        temperature: nil,
        minEngagement: 10,
        isActive: true,
        orderBy: .engagement, // Use engagement sorting for discovery
        limit: 50
    )
}

/// Thread sorting options
enum ThreadSortOrder {
    case chronological
    case trending
    case engagement
    case temperature
    
    var firestoreField: String {
        switch self {
        case .chronological:
            return FirebaseSchema.VideoDocument.createdAt
        case .trending:
            return FirebaseSchema.VideoDocument.hypeCount // Use hype count as trending indicator
        case .engagement:
            return FirebaseSchema.VideoDocument.hypeCount // Use hypeCount instead of engagementRatio
        case .temperature:
            return FirebaseSchema.VideoDocument.temperature
        }
    }
    
    var isDescending: Bool {
        switch self {
        case .chronological:
            return true // Newest first
        case .trending, .engagement, .temperature:
            return true // Highest first
        }
    }
}

/// Thread service errors
enum ThreadServiceError: LocalizedError {
    case threadNotFound(String)
    case parentNotFound(String)
    case maxDepthExceeded(Int)
    case maxRepliesExceeded(Int)
    case invalidHierarchy(String)
    case creationFailed(String)
    case updateFailed(String)
    case deleteFailed(String)
    case validationFailed([String])
    case permissionDenied(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .threadNotFound(let id):
            return "Thread not found: \(id)"
        case .parentNotFound(let id):
            return "Parent video not found: \(id)"
        case .maxDepthExceeded(let depth):
            return "Maximum conversation depth exceeded: \(depth)"
        case .maxRepliesExceeded(let count):
            return "Maximum replies exceeded: \(count)"
        case .invalidHierarchy(let message):
            return "Invalid thread hierarchy: \(message)"
        case .creationFailed(let message):
            return "Thread creation failed: \(message)"
        case .updateFailed(let message):
            return "Thread update failed: \(message)"
        case .deleteFailed(let message):
            return "Thread deletion failed: \(message)"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.joined(separator: ", "))"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Thread Service Implementation

/// Firebase-based thread management service implementing ThreadManaging protocol
/// Handles thread hierarchy, parent-child relationships, and conversation depth limits
/// Consolidates multiple thread managers under clean architecture
@MainActor
class ThreadService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var lastError: ThreadServiceError?
    @Published var operationInProgress = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Analytics
    
    @Published var totalThreadsCreated = 0
    @Published var totalRepliesCreated = 0
    @Published var successfulOperations = 0
    @Published var failedOperations = 0
    
    private var operationMetrics: [ThreadOperationMetrics] = []
    
    // MARK: - Initialization
    
    init() {
        print("🧵 THREAD SERVICE: Initialized thread management with hierarchy validation")
    }
    
    // MARK: - Thread Creation Operations
    
    /// Create new thread (original video that starts conversation)
    func createThread(request: ThreadCreationRequest) async throws -> CoreVideoMetadata {
        let startTime = Date()
        
        // Validate request
        guard request.isValid else {
            let error = ThreadServiceError.validationFailed(request.validationErrors)
            await recordFailure(error)
            throw error
        }
        
        await setOperationState(loading: true)
        
        do {
            let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
            
            // Create thread document
            let threadData: [String: Any] = [
                FirebaseSchema.VideoDocument.id: videoID,
                FirebaseSchema.VideoDocument.title: request.title,
                FirebaseSchema.VideoDocument.videoURL: request.videoURL,
                FirebaseSchema.VideoDocument.thumbnailURL: request.thumbnailURL,
                FirebaseSchema.VideoDocument.creatorID: request.creatorID,
                FirebaseSchema.VideoDocument.creatorName: request.creatorName,
                FirebaseSchema.VideoDocument.createdAt: Timestamp(),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
                
                // Thread hierarchy
                FirebaseSchema.VideoDocument.threadID: videoID, // Thread ID = Video ID for parent
                FirebaseSchema.VideoDocument.replyToVideoID: NSNull(),
                FirebaseSchema.VideoDocument.contentType: ContentType.thread.rawValue,
                FirebaseSchema.VideoDocument.conversationDepth: 0,
                
                // Content metadata
                FirebaseSchema.VideoDocument.duration: request.duration,
                FirebaseSchema.VideoDocument.fileSize: request.fileSize,
                FirebaseSchema.VideoDocument.temperature: request.temperature.rawValue,
                FirebaseSchema.VideoDocument.aspectRatio: 9.0/16.0,
                
                // Engagement counters
                FirebaseSchema.VideoDocument.hypeCount: 0,
                FirebaseSchema.VideoDocument.coolCount: 0,
                FirebaseSchema.VideoDocument.shareCount: 0,
                FirebaseSchema.VideoDocument.replyCount: 0,
                FirebaseSchema.VideoDocument.viewCount: 0,
                
                // Calculated fields
                FirebaseSchema.VideoDocument.qualityScore: 50.0,
                FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
                
                // Status
                FirebaseSchema.VideoDocument.isPromoted: false,
                FirebaseSchema.VideoDocument.isDeleted: false
            ]
            
            try await db.collection(FirebaseSchema.Collections.videos).document(videoID).setData(threadData)
            
            // Create thread metadata
            let thread = CoreVideoMetadata(
                id: videoID,
                title: request.title,
                videoURL: request.videoURL,
                thumbnailURL: request.thumbnailURL,
                creatorID: request.creatorID,
                creatorName: request.creatorName,
                createdAt: Date(),
                threadID: videoID,
                replyToVideoID: nil,
                conversationDepth: 0,
                viewCount: 0,
                hypeCount: 0,
                coolCount: 0,
                replyCount: 0,
                shareCount: 0,
                temperature: request.temperature.rawValue,
                qualityScore: 50,
                engagementRatio: 0.0,
                velocityScore: 0.0,
                trendingScore: 0.0,
                duration: request.duration,
                aspectRatio: 9.0/16.0,
                fileSize: request.fileSize,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil
            )
            
            await setOperationState(loading: false)
            await recordSuccess(.threadCreated, duration: Date().timeIntervalSince(startTime))
            
            totalThreadsCreated += 1
            
            print("✅ THREAD SERVICE: Thread created successfully - \(request.title)")
            
            return thread
            
        } catch {
            await setOperationState(loading: false)
            let threadError = ThreadServiceError.creationFailed(error.localizedDescription)
            await recordFailure(threadError)
            
            print("❌ THREAD SERVICE: Thread creation failed - \(error)")
            
            throw threadError
        }
    }
    
    /// Create reply to existing video (child or stepchild)
    func createReply(request: ReplyCreationRequest) async throws -> CoreVideoMetadata {
        let startTime = Date()
        
        // Validate request
        guard request.isValid else {
            let error = ThreadServiceError.validationFailed(["Invalid reply request"])
            await recordFailure(error)
            throw error
        }
        
        await setOperationState(loading: true)
        
        do {
            // Get parent video to validate hierarchy
            let parentVideo = try await getVideo(id: request.parentVideoID)
            
            // Validate depth limits
            let newDepth = parentVideo.conversationDepth + 1
            guard newDepth <= OptimizationConfig.Threading.maxConversationDepth else {
                throw ThreadServiceError.maxDepthExceeded(newDepth)
            }
            
            // Validate reply count limits
            let currentReplies = try await getReplyCount(parentVideoID: request.parentVideoID)
            let maxReplies = parentVideo.contentType == .thread ?
                OptimizationConfig.Threading.maxChildrenPerThread :
                OptimizationConfig.Threading.maxStepchildrenPerChild
            
            guard currentReplies < maxReplies else {
                throw ThreadServiceError.maxRepliesExceeded(currentReplies)
            }
            
            // Determine content type based on parent
            let contentType: ContentType
            switch parentVideo.conversationDepth {
            case 0:
                contentType = .child
            case 1:
                contentType = .stepchild
            default:
                throw ThreadServiceError.maxDepthExceeded(newDepth)
            }
            
            let videoID = FirebaseSchema.DocumentIDPatterns.generateVideoID()
            
            // Create reply document
            let replyData: [String: Any] = [
                FirebaseSchema.VideoDocument.id: videoID,
                FirebaseSchema.VideoDocument.title: "", // Replies don't have titles
                FirebaseSchema.VideoDocument.videoURL: request.videoURL,
                FirebaseSchema.VideoDocument.thumbnailURL: request.thumbnailURL,
                FirebaseSchema.VideoDocument.creatorID: request.creatorID,
                FirebaseSchema.VideoDocument.creatorName: request.creatorName,
                FirebaseSchema.VideoDocument.createdAt: Timestamp(),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp(),
                
                // Thread hierarchy
                FirebaseSchema.VideoDocument.threadID: request.threadID,
                FirebaseSchema.VideoDocument.replyToVideoID: request.parentVideoID,
                FirebaseSchema.VideoDocument.contentType: contentType.rawValue,
                FirebaseSchema.VideoDocument.conversationDepth: newDepth,
                
                // Content metadata
                FirebaseSchema.VideoDocument.duration: request.duration,
                FirebaseSchema.VideoDocument.fileSize: request.fileSize,
                FirebaseSchema.VideoDocument.temperature: request.temperature.rawValue,
                FirebaseSchema.VideoDocument.aspectRatio: 9.0/16.0,
                
                // Engagement counters
                FirebaseSchema.VideoDocument.hypeCount: 0,
                FirebaseSchema.VideoDocument.coolCount: 0,
                FirebaseSchema.VideoDocument.shareCount: 0,
                FirebaseSchema.VideoDocument.replyCount: 0,
                FirebaseSchema.VideoDocument.viewCount: 0,
                
                // Calculated fields
                FirebaseSchema.VideoDocument.qualityScore: 50.0,
                FirebaseSchema.VideoDocument.discoverabilityScore: 0.5,
                
                // Status
                FirebaseSchema.VideoDocument.isPromoted: false,
                FirebaseSchema.VideoDocument.isDeleted: false
            ]
            
            // Use batch to create reply and update parent reply count
            let batch = db.batch()
            
            // Add reply document
            let replyRef = db.collection(FirebaseSchema.Collections.videos).document(videoID)
            batch.setData(replyData, forDocument: replyRef)
            
            // Update parent reply count
            let parentRef = db.collection(FirebaseSchema.Collections.videos).document(request.parentVideoID)
            batch.updateData([
                FirebaseSchema.VideoDocument.replyCount: FieldValue.increment(Int64(1)),
                FirebaseSchema.VideoDocument.updatedAt: Timestamp()
            ], forDocument: parentRef)
            
            try await batch.commit()
            
            // Create reply metadata
            let reply = CoreVideoMetadata(
                id: videoID,
                title: "",
                videoURL: request.videoURL,
                thumbnailURL: request.thumbnailURL,
                creatorID: request.creatorID,
                creatorName: request.creatorName,
                createdAt: Date(),
                threadID: request.threadID,
                replyToVideoID: request.parentVideoID,
                conversationDepth: newDepth,
                viewCount: 0,
                hypeCount: 0,
                coolCount: 0,
                replyCount: 0,
                shareCount: 0,
                temperature: request.temperature.rawValue,
                qualityScore: 50,
                engagementRatio: 0.0,
                velocityScore: 0.0,
                trendingScore: 0.0,
                duration: request.duration,
                aspectRatio: 9.0/16.0,
                fileSize: request.fileSize,
                discoverabilityScore: 0.5,
                isPromoted: false,
                lastEngagementAt: nil
            )
            
            await setOperationState(loading: false)
            await recordSuccess(.replyCreated, duration: Date().timeIntervalSince(startTime))
            
            totalRepliesCreated += 1
            
            print("✅ THREAD SERVICE: Reply created successfully - \(contentType.displayName)")
            
            return reply
            
        } catch {
            await setOperationState(loading: false)
            
            let threadError: ThreadServiceError
            if let existingError = error as? ThreadServiceError {
                threadError = existingError
            } else {
                threadError = ThreadServiceError.creationFailed(error.localizedDescription)
            }
            
            await recordFailure(threadError)
            
            print("❌ THREAD SERVICE: Reply creation failed - \(error)")
            
            throw threadError
        }
    }
    
    // MARK: - Thread Query Operations
    
    /// Get single video by ID
    func getVideo(id: String) async throws -> CoreVideoMetadata {
        do {
            let document = try await db.collection(FirebaseSchema.Collections.videos).document(id).getDocument()
            
            guard document.exists, let data = document.data() else {
                throw ThreadServiceError.threadNotFound(id)
            }
            
            return try parseVideoDocument(data)
            
        } catch {
            if let threadError = error as? ThreadServiceError {
                throw threadError
            }
            throw ThreadServiceError.networkError(error.localizedDescription)
        }
    }
    
    /// Get thread hierarchy (parent + all children)
    func getThreadHierarchy(threadID: String) async throws -> ThreadHierarchy {
        do {
            // Get all videos in thread
            let query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
                .whereField(FirebaseSchema.VideoDocument.isDeleted, isEqualTo: false)
                .order(by: FirebaseSchema.VideoDocument.conversationDepth)
                .order(by: FirebaseSchema.VideoDocument.createdAt)
            
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                throw ThreadServiceError.threadNotFound(threadID)
            }
            
            var parentVideo: CoreVideoMetadata?
            var childVideos: [CoreVideoMetadata] = []
            var maxDepth = 0
            
            for document in snapshot.documents {
                let video = try parseVideoDocument(document.data())
                maxDepth = max(maxDepth, video.conversationDepth)
                
                if video.conversationDepth == 0 {
                    parentVideo = video
                } else {
                    childVideos.append(video)
                }
            }
            
            guard let parent = parentVideo else {
                throw ThreadServiceError.invalidHierarchy("No thread parent found")
            }
            
            let canAddReplies = maxDepth < OptimizationConfig.Threading.maxConversationDepth
            
            return ThreadHierarchy(
                threadID: threadID,
                parentVideo: parent,
                childVideos: childVideos,
                totalDepth: maxDepth,
                canAddReplies: canAddReplies
            )
            
        } catch {
            if let threadError = error as? ThreadServiceError {
                throw threadError
            }
            throw ThreadServiceError.networkError(error.localizedDescription)
        }
    }
    
    /// Get threads with filtering and pagination
    func getThreads(
        filters: ThreadQueryFilters,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [CoreVideoMetadata], lastDocument: DocumentSnapshot?) {
        
        do {
            var query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0) // Only threads (not replies)
            
            // Apply filters
            if let creatorID = filters.creatorID {
                query = query.whereField(FirebaseSchema.VideoDocument.creatorID, isEqualTo: creatorID)
            }
            
            if let temperature = filters.temperature {
                query = query.whereField(FirebaseSchema.VideoDocument.temperature, isEqualTo: temperature.rawValue)
            }
            
            if let minEngagement = filters.minEngagement {
                query = query.whereField(FirebaseSchema.VideoDocument.hypeCount, isGreaterThanOrEqualTo: minEngagement)
            }
            
            if let isActive = filters.isActive {
                query = query.whereField(FirebaseSchema.VideoDocument.isDeleted, isEqualTo: !isActive)
            }
            
            // Apply sorting
            query = query.order(by: filters.orderBy.firestoreField, descending: filters.orderBy.isDescending)
            
            // Apply pagination
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            query = query.limit(to: filters.limit)
            
            let snapshot = try await query.getDocuments()
            
            let threads = try snapshot.documents.map { document in
                try parseVideoDocument(document.data())
            }
            
            let newLastDocument = snapshot.documents.last
            
            return (threads: threads, lastDocument: newLastDocument)
            
        } catch {
            throw ThreadServiceError.networkError(error.localizedDescription)
        }
    }
    
    /// Get replies to a specific video
    func getReplies(parentVideoID: String, limit: Int = 50) async throws -> [CoreVideoMetadata] {
        do {
            let query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.replyToVideoID, isEqualTo: parentVideoID)
                .whereField(FirebaseSchema.VideoDocument.isDeleted, isEqualTo: false)
                .order(by: FirebaseSchema.VideoDocument.createdAt)
                .limit(to: limit)
            
            let snapshot = try await query.getDocuments()
            
            return try snapshot.documents.map { document in
                try parseVideoDocument(document.data())
            }
            
        } catch {
            throw ThreadServiceError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Thread Management Operations
    
    /// Update thread metadata (title, tags, etc.)
    func updateThread(threadID: String, updates: [String: Any]) async throws {
        let startTime = Date()
        
        await setOperationState(loading: true)
        
        do {
            var validUpdates = updates
            validUpdates[FirebaseSchema.VideoDocument.updatedAt] = Timestamp()
            
            try await db.collection(FirebaseSchema.Collections.videos)
                .document(threadID)
                .updateData(validUpdates)
            
            await setOperationState(loading: false)
            await recordSuccess(.threadUpdated, duration: Date().timeIntervalSince(startTime))
            
            print("✅ THREAD SERVICE: Thread updated successfully - \(threadID)")
            
        } catch {
            await setOperationState(loading: false)
            let threadError = ThreadServiceError.updateFailed(error.localizedDescription)
            await recordFailure(threadError)
            
            print("❌ THREAD SERVICE: Thread update failed - \(error)")
            
            throw threadError
        }
    }
    
    /// Delete thread and all its replies
    func deleteThread(threadID: String, creatorID: String) async throws {
        let startTime = Date()
        
        await setOperationState(loading: true)
        
        do {
            // Get all videos in thread for batch deletion
            let query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            
            let snapshot = try await query.getDocuments()
            
            // Verify creator ownership of thread parent
            if let threadDoc = snapshot.documents.first(where: {
                ($0.data()[FirebaseSchema.VideoDocument.conversationDepth] as? Int) == 0
            }) {
                let threadCreatorID = threadDoc.data()[FirebaseSchema.VideoDocument.creatorID] as? String
                guard threadCreatorID == creatorID else {
                    throw ThreadServiceError.permissionDenied("Only thread creator can delete")
                }
            }
            
            // Batch delete all videos in thread
            let batch = db.batch()
            
            for document in snapshot.documents {
                batch.updateData([
                    FirebaseSchema.VideoDocument.isDeleted: true,
                    FirebaseSchema.VideoDocument.updatedAt: Timestamp()
                ], forDocument: document.reference)
            }
            
            try await batch.commit()
            
            await setOperationState(loading: false)
            await recordSuccess(.threadDeleted, duration: Date().timeIntervalSince(startTime))
            
            print("✅ THREAD SERVICE: Thread deleted successfully - \(threadID)")
            
        } catch {
            await setOperationState(loading: false)
            
            let threadError: ThreadServiceError
            if let existingError = error as? ThreadServiceError {
                threadError = existingError
            } else {
                threadError = ThreadServiceError.deleteFailed(error.localizedDescription)
            }
            
            await recordFailure(threadError)
            
            print("❌ THREAD SERVICE: Thread deletion failed - \(error)")
            
            throw threadError
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get reply count for a video
    private func getReplyCount(parentVideoID: String) async throws -> Int {
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.replyToVideoID, isEqualTo: parentVideoID)
            .whereField(FirebaseSchema.VideoDocument.isDeleted, isEqualTo: false)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.count
    }
    
    /// Parse Firestore document to CoreVideoMetadata
    private func parseVideoDocument(_ data: [String: Any]) throws -> CoreVideoMetadata {
        guard let id = data[FirebaseSchema.VideoDocument.id] as? String,
              let videoURL = data[FirebaseSchema.VideoDocument.videoURL] as? String,
              let thumbnailURL = data[FirebaseSchema.VideoDocument.thumbnailURL] as? String,
              let creatorID = data[FirebaseSchema.VideoDocument.creatorID] as? String,
              let creatorName = data[FirebaseSchema.VideoDocument.creatorName] as? String,
              let createdTimestamp = data[FirebaseSchema.VideoDocument.createdAt] as? Timestamp,
              let updatedTimestamp = data[FirebaseSchema.VideoDocument.updatedAt] as? Timestamp,
              let threadID = data[FirebaseSchema.VideoDocument.threadID] as? String,
              let conversationDepth = data[FirebaseSchema.VideoDocument.conversationDepth] as? Int else {
            
            throw ThreadServiceError.invalidHierarchy("Invalid video document structure")
        }
        
        let title = data[FirebaseSchema.VideoDocument.title] as? String ?? ""
        let replyToVideoID = data[FirebaseSchema.VideoDocument.replyToVideoID] as? String
        let duration = data[FirebaseSchema.VideoDocument.duration] as? TimeInterval ?? 0
        let fileSize = data[FirebaseSchema.VideoDocument.fileSize] as? Int64 ?? 0
        let temperatureString = data[FirebaseSchema.VideoDocument.temperature] as? String ?? Temperature.warm.rawValue
        let aspectRatio = data[FirebaseSchema.VideoDocument.aspectRatio] as? Double ?? 9.0/16.0
        
        // Engagement metrics
        let hypeCount = data[FirebaseSchema.VideoDocument.hypeCount] as? Int ?? 0
        let coolCount = data[FirebaseSchema.VideoDocument.coolCount] as? Int ?? 0
        let shareCount = data[FirebaseSchema.VideoDocument.shareCount] as? Int ?? 0
        let replyCount = data[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0
        let viewCount = data[FirebaseSchema.VideoDocument.viewCount] as? Int ?? 0
        
        // Calculated metrics
        let qualityScore = data[FirebaseSchema.VideoDocument.qualityScore] as? Int ?? 50
        let discoverabilityScore = data[FirebaseSchema.VideoDocument.discoverabilityScore] as? Double ?? 0.5
        
        // Status flags
        let isPromoted = data[FirebaseSchema.VideoDocument.isPromoted] as? Bool ?? false
        let isDeleted = data[FirebaseSchema.VideoDocument.isDeleted] as? Bool ?? false
        
        return CoreVideoMetadata(
            id: id,
            title: title,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL,
            creatorID: creatorID,
            creatorName: creatorName,
            createdAt: createdTimestamp.dateValue(),
            threadID: threadID,
            replyToVideoID: replyToVideoID,
            conversationDepth: conversationDepth,
            viewCount: viewCount,
            hypeCount: hypeCount,
            coolCount: coolCount,
            replyCount: replyCount,
            shareCount: shareCount,
            temperature: temperatureString,
            qualityScore: qualityScore,
            engagementRatio: 0.0, // Calculate from counts
            velocityScore: 0.0,
            trendingScore: 0.0,
            duration: duration,
            aspectRatio: aspectRatio,
            fileSize: fileSize,
            discoverabilityScore: discoverabilityScore,
            isPromoted: isPromoted,
            lastEngagementAt: nil
        )
    }
    
    // MARK: - State Management
    
    /// Update operation state
    private func setOperationState(loading: Bool) async {
        isLoading = loading
        operationInProgress = loading
    }
    
    /// Record successful operation
    private func recordSuccess(_ operation: ThreadOperation, duration: TimeInterval) async {
        successfulOperations += 1
        
        let metrics = ThreadOperationMetrics(
            operation: operation,
            duration: duration,
            success: true,
            error: nil,
            timestamp: Date()
        )
        
        operationMetrics.append(metrics)
        
        // Keep only last 100 metrics
        if operationMetrics.count > 100 {
            operationMetrics.removeFirst(operationMetrics.count - 100)
        }
    }
    
    /// Record failed operation
    private func recordFailure(_ error: ThreadServiceError) async {
        failedOperations += 1
        lastError = error
        
        let metrics = ThreadOperationMetrics(
            operation: .unknown,
            duration: 0,
            success: false,
            error: error.localizedDescription,
            timestamp: Date()
        )
        
        operationMetrics.append(metrics)
        
        // Keep only last 100 metrics
        if operationMetrics.count > 100 {
            operationMetrics.removeFirst(operationMetrics.count - 100)
        }
    }
    
    // MARK: - Analytics
    
    /// Get thread service statistics
    func getThreadStats() -> ThreadStats {
        let totalOperations = successfulOperations + failedOperations
        let successRate = totalOperations > 0 ? (Double(successfulOperations) / Double(totalOperations)) * 100 : 100.0
        
        let recentErrors = operationMetrics
            .suffix(10)
            .compactMap { $0.error }
        
        return ThreadStats(
            totalThreadsCreated: totalThreadsCreated,
            totalRepliesCreated: totalRepliesCreated,
            successfulOperations: successfulOperations,
            failedOperations: failedOperations,
            successRate: successRate,
            averageOperationDuration: calculateAverageOperationDuration(),
            recentErrors: recentErrors
        )
    }
    
    /// Calculate average operation duration
    private func calculateAverageOperationDuration() -> TimeInterval {
        let successfulMetrics = operationMetrics.filter { $0.success }
        guard !successfulMetrics.isEmpty else { return 0.0 }
        
        let totalDuration = successfulMetrics.reduce(0.0) { $0 + $1.duration }
        return totalDuration / Double(successfulMetrics.count)
    }
    
    /// Print thread service status
    func printThreadStatus() {
        let stats = getThreadStats()
        print("🧵 THREAD SERVICE STATUS:")
        print("  Threads Created: \(stats.totalThreadsCreated)")
        print("  Replies Created: \(stats.totalRepliesCreated)")
        print("  Success Rate: \(String(format: "%.1f%%", stats.successRate))")
        print("  Avg Duration: \(String(format: "%.1fs", stats.averageOperationDuration))")
        print("  Current Operation: \(operationInProgress ? "Active" : "Idle")")
        if let error = lastError {
            print("  Last Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

/// Thread operation types for metrics
enum ThreadOperation {
    case threadCreated
    case replyCreated
    case threadUpdated
    case threadDeleted
    case hierarchyQueried
    case unknown
}

/// Thread operation metrics for analytics
struct ThreadOperationMetrics {
    let operation: ThreadOperation
    let duration: TimeInterval
    let success: Bool
    let error: String?
    let timestamp: Date
}

/// Thread service statistics
struct ThreadStats {
    let totalThreadsCreated: Int
    let totalRepliesCreated: Int
    let successfulOperations: Int
    let failedOperations: Int
    let successRate: Double
    let averageOperationDuration: TimeInterval
    let recentErrors: [String]
}
