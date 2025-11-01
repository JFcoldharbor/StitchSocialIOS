//
//  VideoUploadService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video Upload Management
//  Handles Firebase Storage uploads and metadata persistence
//  UPDATED: Added follower notification trigger for new video uploads
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import AVFoundation
import UIKit

/// Dedicated service for handling video uploads to Firebase
/// Manages file uploads, thumbnail generation, and metadata persistence
@MainActor
class VideoUploadService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var uploadProgress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var isUploading: Bool = false
    @Published var lastUploadError: UploadError?
    
    // MARK: - Configuration
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore(database: "stitchfin")
    private let maxRetries = 2
    private let timeoutInterval: TimeInterval = 60.0
    
    // MARK: - Analytics
    
    @Published var totalUploads: Int = 0
    @Published var successfulUploads: Int = 0
    private var uploadMetrics: [UploadMetrics] = []
    
    // MARK: - Public Interface
    
    /// Uploads video with metadata to Firebase
    /// Returns complete upload result with all URLs and metadata
    func uploadVideo(
        videoURL: URL,
        metadata: VideoUploadMetadata,
        recordingContext: RecordingContext
    ) async throws -> VideoUploadResult {
        
        let startTime = Date()
        
        await MainActor.run {
            self.isUploading = true
            self.uploadProgress = 0.0
            self.currentTask = "Preparing upload..."
            self.lastUploadError = nil
        }
        
        do {
            // Step 1: Validate video file
            await updateProgress(0.1, task: "Validating video...")
            let videoData = try await validateAndLoadVideo(videoURL)
            
            // Step 2: Generate thumbnail
            await updateProgress(0.2, task: "Generating thumbnail...")
            let thumbnailData = try await generateThumbnail(from: videoURL)
            
            // Step 3: Upload video to Storage
            await updateProgress(0.3, task: "Uploading video...")
            let videoStorageURL = try await uploadVideoToStorage(
                videoData: videoData,
                metadata: metadata
            )
            
            // Step 4: Upload thumbnail to Storage
            await updateProgress(0.7, task: "Uploading thumbnail...")
            let thumbnailStorageURL = try await uploadThumbnailToStorage(
                thumbnailData: thumbnailData,
                videoID: metadata.videoID
            )
            
            // Step 5: Get video technical metadata
            await updateProgress(0.9, task: "Processing metadata...")
            let technicalMetadata = try await extractTechnicalMetadata(from: videoURL)
            
            // Step 6: Complete upload
            await updateProgress(1.0, task: "Upload complete!")
            
            let result = VideoUploadResult(
                videoURL: videoStorageURL,
                thumbnailURL: thumbnailStorageURL,
                duration: technicalMetadata.duration,
                fileSize: technicalMetadata.fileSize,
                aspectRatio: technicalMetadata.aspectRatio,
                videoID: metadata.videoID
            )
            
            await MainActor.run {
                self.isUploading = false
                self.totalUploads += 1
                self.successfulUploads += 1
            }
            
            // Record successful upload metrics
            recordUploadMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: true,
                fileSize: technicalMetadata.fileSize,
                error: nil
            )
            
            print("✅ UPLOAD SERVICE: Video uploaded successfully - \(metadata.title)")
            return result
            
        } catch {
            await MainActor.run {
                self.isUploading = false
                self.lastUploadError = error as? UploadError ?? .unknown(error.localizedDescription)
                self.totalUploads += 1
            }
            
            // Record failed upload metrics
            recordUploadMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: false,
                fileSize: 0,
                error: error
            )
            
            print("❌ UPLOAD SERVICE: Upload failed - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Creates video document in Firestore using VideoService
    /// UPDATED: Now triggers follower notifications for new videos and sends mention notifications
    func createVideoDocument(
        uploadResult: VideoUploadResult,
        metadata: VideoUploadMetadata,
        recordingContext: RecordingContext,
        videoService: VideoService,
        userService: UserService,
        notificationService: NotificationService,
        taggedUserIDs: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        await updateProgress(0.95, task: "Creating video document...")
        
        let createdVideo: CoreVideoMetadata
        
        switch recordingContext {
        case .newThread:
            createdVideo = try await videoService.createThread(
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
            // 🎬 NEW VIDEO NOTIFICATION: Notify followers for new thread videos
            // IMPORTANT: Use createdVideo.creatorID (corrected Firebase UID) not metadata.creatorID
            // Send synchronously to preserve auth context
            do {
                let followerIDs = try await userService.getFollowerIDs(userID: createdVideo.creatorID)
                
                if !followerIDs.isEmpty {
                    try await notificationService.sendNewVideoNotification(
                        creatorID: createdVideo.creatorID,
                        creatorUsername: metadata.creatorName,
                        videoID: createdVideo.id,
                        videoTitle: createdVideo.title,
                        followerIDs: followerIDs
                    )
                    print("✅ UPLOAD SERVICE: Notified \(followerIDs.count) followers of new video")
                } else {
                    print("ℹ️ UPLOAD SERVICE: No followers to notify for user \(createdVideo.creatorID)")
                }
            } catch {
                print("⚠️ UPLOAD SERVICE: Failed to send follower notifications - \(error)")
                // Don't fail upload if notification fails
            }
            
        case .stitchToThread(let threadID, _):
            createdVideo = try await videoService.createChildReply(
                parentID: threadID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
            // 🎬 STITCH NOTIFICATION: Trigger stitch notification
            Task {
                do {
                    // Get thread details for notification
                    let threadVideo = try await videoService.getVideo(id: threadID)
                    let threadUserIDs: [String] = [] // Get from thread if available
                    
                    try await notificationService.sendStitchNotification(
                        videoID: createdVideo.id,
                        videoTitle: metadata.title,
                        originalCreatorID: threadVideo.creatorID,
                        parentCreatorID: nil,
                        threadUserIDs: threadUserIDs
                    )
                    print("✅ UPLOAD SERVICE: Sent stitch notification")
                } catch {
                    print("⚠️ UPLOAD SERVICE: Failed to send stitch notification - \(error)")
                }
            }
            
        case .replyToVideo(let videoID, _):
            createdVideo = try await videoService.createChildReply(
                parentID: videoID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
            // 🎬 STITCH NOTIFICATION: Trigger stitch notification for reply
            Task {
                do {
                    let parentVideo = try await videoService.getVideo(id: videoID)
                    let threadUserIDs: [String] = [] // Get from thread if available
                    
                    try await notificationService.sendStitchNotification(
                        videoID: createdVideo.id,
                        videoTitle: metadata.title,
                        originalCreatorID: parentVideo.creatorID,
                        parentCreatorID: parentVideo.creatorID,
                        threadUserIDs: threadUserIDs
                    )
                    print("✅ UPLOAD SERVICE: Sent reply notification")
                } catch {
                    print("⚠️ UPLOAD SERVICE: Failed to send reply notification - \(error)")
                }
            }
            
        case .continueThread(let threadID, _):
            createdVideo = try await videoService.createChildReply(
                parentID: threadID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
            // 🎬 STITCH NOTIFICATION: Trigger stitch notification for thread continuation
            Task {
                do {
                    let threadVideo = try await videoService.getVideo(id: threadID)
                    let threadUserIDs: [String] = [] // Get from thread if available
                    
                    try await notificationService.sendStitchNotification(
                        videoID: createdVideo.id,
                        videoTitle: metadata.title,
                        originalCreatorID: threadVideo.creatorID,
                        parentCreatorID: nil,
                        threadUserIDs: threadUserIDs
                    )
                    print("✅ UPLOAD SERVICE: Sent thread continuation notification")
                } catch {
                    print("⚠️ UPLOAD SERVICE: Failed to send thread notification - \(error)")
                }
            }
        }
        
        // 📌 MENTION NOTIFICATIONS: Send to tagged users if any
        if !taggedUserIDs.isEmpty {
            try await videoService.updateVideoTags(
                videoID: createdVideo.id,
                taggedUserIDs: taggedUserIDs
            )
            print("📌 UPLOAD SERVICE: Saved \(taggedUserIDs.count) tagged users to video \(createdVideo.id)")
            
            // Send mention notifications
            for taggedUserID in taggedUserIDs {
                Task {
                    do {
                        try await notificationService.sendMentionNotification(
                            to: taggedUserID,
                            videoTitle: metadata.title,
                            mentionContext: "tagged in video"
                        )
                    } catch {
                        print("⚠️ UPLOAD SERVICE: Failed to send mention notification to \(taggedUserID) - \(error)")
                        // Don't fail upload if notification fails
                    }
                }
            }
            print("📬 UPLOAD SERVICE: Sent \(taggedUserIDs.count) mention notifications")
        }
        
        await updateProgress(1.0, task: "Video created successfully!")
        
        print("✅ UPLOAD SERVICE: Video document created - \(createdVideo.id)")
        return createdVideo
    }
    
    // MARK: - Private Upload Methods
    
    /// Validates video file and loads data
    private func validateAndLoadVideo(_ videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Check file exists
                    guard FileManager.default.fileExists(atPath: videoURL.path) else {
                        continuation.resume(throwing: UploadError.fileNotFound("Video file not found"))
                        return
                    }
                    
                    // Get file size
                    let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = resourceValues.fileSize ?? 0
                    
                    // Validate file size (max 100MB)
                    guard fileSize <= 100 * 1024 * 1024 else {
                        continuation.resume(throwing: UploadError.fileTooLarge("File size exceeds 100MB limit"))
                        return
                    }
                    
                    // Load video data
                    let videoData = try Data(contentsOf: videoURL)
                    continuation.resume(returning: videoData)
                    
                } catch {
                    continuation.resume(throwing: UploadError.fileLoadFailed("Failed to load video: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// Uploads video data to Firebase Storage with progress tracking
    private func uploadVideoToStorage(
        videoData: Data,
        metadata: VideoUploadMetadata
    ) async throws -> String {
        
        let storageRef = storage.reference().child("videos/\(metadata.videoID).mp4")
        
        let storageMetadata = StorageMetadata()
        storageMetadata.contentType = "video/mp4"
        storageMetadata.customMetadata = [
            "title": metadata.title,
            "creatorID": metadata.creatorID,
            "uploadedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putData(videoData, metadata: storageMetadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: UploadError.uploadFailed("Video upload failed: \(error.localizedDescription)"))
                    return
                }
                
                storageRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: UploadError.uploadFailed("Failed to get download URL: \(error.localizedDescription)"))
                        return
                    }
                    
                    guard let downloadURL = url else {
                        continuation.resume(throwing: UploadError.uploadFailed("Invalid download URL"))
                        return
                    }
                    
                    continuation.resume(returning: downloadURL.absoluteString)
                }
            }
            
            // Track upload progress
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                
                Task { @MainActor in
                    // Map video upload progress to 30-70% of total progress
                    let mappedProgress = 0.3 + (percentComplete * 0.4)
                    self?.uploadProgress = mappedProgress
                }
            }
        }
    }
    
    /// Uploads thumbnail to Firebase Storage
    private func uploadThumbnailToStorage(
        thumbnailData: Data,
        videoID: String
    ) async throws -> String {
        
        let storageRef = storage.reference().child("thumbnails/\(videoID).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await storageRef.putDataAsync(thumbnailData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    /// Generates thumbnail from video
    private func generateThumbnail(from videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: videoURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 1080, height: 1920)
                
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    let image = UIImage(cgImage: cgImage)
                    
                    guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
                        continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Failed to convert thumbnail to JPEG"))
                        return
                    }
                    
                    continuation.resume(returning: jpegData)
                    
                } catch {
                    continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Failed to generate thumbnail: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// Extracts technical metadata from video
    private func extractTechnicalMetadata(from videoURL: URL) async throws -> TechnicalMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    do {
                        let asset = AVAsset(url: videoURL)
                        
                        // Get duration
                        let duration = try await asset.load(.duration)
                        let seconds = CMTimeGetSeconds(duration)
                        
                        // Get file size
                        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
                        let fileSize = Int64(resourceValues.fileSize ?? 0)
                        
                        // Get aspect ratio from video track
                        var aspectRatio: Double = 9.0/16.0 // Default
                        let videoTracks = try await asset.loadTracks(withMediaType: .video)
                        if let videoTrack = videoTracks.first {
                            let naturalSize = try await videoTrack.load(.naturalSize)
                            let preferredTransform = try await videoTrack.load(.preferredTransform)
                            let size = naturalSize.applying(preferredTransform)
                            let width = abs(size.width)
                            let height = abs(size.height)
                            if height > 0 {
                                aspectRatio = Double(width / height)
                            }
                        }
                        
                        let metadata = TechnicalMetadata(
                            duration: seconds,
                            fileSize: fileSize,
                            aspectRatio: aspectRatio
                        )
                        
                        continuation.resume(returning: metadata)
                        
                    } catch {
                        continuation.resume(throwing: UploadError.metadataExtractionFailed("Failed to extract metadata: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Updates upload progress and current task
    private func updateProgress(_ progress: Double, task: String) async {
        await MainActor.run {
            self.uploadProgress = progress
            self.currentTask = task
        }
    }
    
    /// Records upload metrics for analytics
    private func recordUploadMetrics(
        duration: TimeInterval,
        success: Bool,
        fileSize: Int64,
        error: Error?
    ) {
        let metrics = UploadMetrics(
            timestamp: Date(),
            duration: duration,
            success: success,
            fileSize: fileSize,
            error: error?.localizedDescription
        )
        
        uploadMetrics.append(metrics)
        
        // Keep only last 50 uploads
        if uploadMetrics.count > 50 {
            uploadMetrics.removeFirst()
        }
        
        print("📊 UPLOAD SERVICE: Metrics - Duration: \(String(format: "%.2f", duration))s, Success: \(success), File Size: \(fileSize) bytes")
    }
    
    /// Gets upload statistics
    func getUploadStats() -> UploadStats {
        let avgDuration = uploadMetrics.isEmpty ? 0 : uploadMetrics.reduce(0) { $0 + $1.duration } / Double(uploadMetrics.count)
        let successRate = totalUploads > 0 ? Double(successfulUploads) / Double(totalUploads) * 100 : 100.0
        
        return UploadStats(
            totalUploads: totalUploads,
            successfulUploads: successfulUploads,
            successRate: successRate,
            averageDuration: avgDuration
        )
    }
    
    /// Clears upload error
    func clearError() {
        lastUploadError = nil
    }
}

// MARK: - Data Models

/// Input metadata for video upload
struct VideoUploadMetadata {
    let videoID: String
    let title: String
    let description: String
    let hashtags: [String]
    let creatorID: String
    let creatorName: String
    
    init(
        title: String,
        description: String = "",
        hashtags: [String] = [],
        creatorID: String,
        creatorName: String
    ) {
        self.videoID = UUID().uuidString
        self.title = title
        self.description = description
        self.hashtags = hashtags
        self.creatorID = creatorID
        self.creatorName = creatorName
    }
}

/// Result of successful video upload
struct VideoUploadResult {
    let videoURL: String
    let thumbnailURL: String
    let duration: TimeInterval
    let fileSize: Int64
    let aspectRatio: Double
    let videoID: String
}

/// Technical metadata extracted from video
struct TechnicalMetadata {
    let duration: TimeInterval
    let fileSize: Int64
    let aspectRatio: Double
}

/// Upload error types
enum UploadError: Error, LocalizedError {
    case fileNotFound(String)
    case fileTooLarge(String)
    case fileLoadFailed(String)
    case uploadFailed(String)
    case thumbnailGenerationFailed(String)
    case metadataExtractionFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message):
            return "File Not Found: \(message)"
        case .fileTooLarge(let message):
            return "File Too Large: \(message)"
        case .fileLoadFailed(let message):
            return "File Load Failed: \(message)"
        case .uploadFailed(let message):
            return "Upload Failed: \(message)"
        case .thumbnailGenerationFailed(let message):
            return "Thumbnail Generation Failed: \(message)"
        case .metadataExtractionFailed(let message):
            return "Metadata Extraction Failed: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
        }
    }
}

/// Upload performance metrics
struct UploadMetrics {
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let fileSize: Int64
    let error: String?
}

/// Upload statistics
struct UploadStats {
    let totalUploads: Int
    let successfulUploads: Int
    let successRate: Double
    let averageDuration: TimeInterval
}
