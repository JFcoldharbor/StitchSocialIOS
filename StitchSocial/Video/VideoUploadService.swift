//
//  VideoUploadService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Video Upload Management
//
//  ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED: Removed hard 100MB rejection - now auto-compresses
//  ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED: Uses FastVideoCompressor as fallback
//  ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED: Better error messages for file size issues
//  ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED: Added spin-off support
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import AVFoundation
import UIKit

/// Dedicated service for handling video uploads to Firebase
/// Now with automatic compression fallback for large files
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
    
    /// Maximum upload size (100 MB)
    static let maxUploadSize: Int64 = 100 * 1024 * 1024
    
    /// Target size when compression is needed (50 MB for safe margin)
    static let targetCompressedSize: Int64 = 50 * 1024 * 1024
    
    // MARK: - Analytics
    
    @Published var totalUploads: Int = 0
    @Published var successfulUploads: Int = 0
    private var uploadMetrics: [UploadMetrics] = []
    
    // MARK: - Public Interface
    
    /// Uploads video with metadata to Firebase
    /// ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â§ UPDATED: Now auto-compresses if file exceeds 100MB limit
    func uploadVideo(
        videoURL: URL,
        metadata: VideoUploadMetadata,
        recordingContext: RecordingContext,
        customThumbnailTime: TimeInterval? = nil
    ) async throws -> VideoUploadResult {
        
        let startTime = Date()
        
        await MainActor.run {
            self.isUploading = true
            self.uploadProgress = 0.0
            self.currentTask = "Preparing upload..."
            self.lastUploadError = nil
        }
        
        do {
            // Step 1: Check file size and compress if needed
            await updateProgress(0.05, task: "Checking video size...")
            let finalVideoURL = try await ensureUploadableSize(videoURL: videoURL)
            
            // Step 2: Validate video file
            await updateProgress(0.1, task: "Validating video...")
            let videoData = try await loadVideoData(finalVideoURL)
            
            // Step 3: Generate thumbnail
            await updateProgress(0.2, task: "Generating thumbnail...")
            let thumbnailData = try await generateThumbnail(from: finalVideoURL, at: customThumbnailTime)
            
            // Step 4: Upload video to Storage
            await updateProgress(0.3, task: "Uploading video...")
            let videoStorageURL = try await uploadVideoToStorage(
                videoData: videoData,
                metadata: metadata
            )
            
            // Step 5: Upload thumbnail to Storage
            await updateProgress(0.7, task: "Uploading thumbnail...")
            let thumbnailStorageURL = try await uploadThumbnailToStorage(
                thumbnailData: thumbnailData,
                videoID: metadata.videoID
            )
            
            // Step 6: Get video technical metadata
            await updateProgress(0.9, task: "Processing metadata...")
            let technicalMetadata = try await extractTechnicalMetadata(from: finalVideoURL)
            
            // Step 7: Complete upload
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
            
            // Cleanup compressed file if we created one
            if finalVideoURL != videoURL {
                try? FileManager.default.removeItem(at: finalVideoURL)
            }
            
            recordUploadMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: true,
                fileSize: technicalMetadata.fileSize,
                error: nil
            )
            
            let orientation = VideoOrientation.from(aspectRatio: technicalMetadata.aspectRatio)
            print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ UPLOAD SERVICE: Video uploaded successfully - \(metadata.title)")
            print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â UPLOAD SERVICE: \(orientation.displayName) video (aspect ratio: \(String(format: "%.3f", technicalMetadata.aspectRatio)))")
            
            return result
            
        } catch {
            await MainActor.run {
                self.isUploading = false
                self.lastUploadError = error as? UploadError ?? .unknown(error.localizedDescription)
                self.totalUploads += 1
            }
            
            recordUploadMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: false,
                fileSize: 0,
                error: error
            )
            
            print("ÃƒÂ¢Ã‚ÂÃ…â€™ UPLOAD SERVICE: Upload failed - \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ NEW: Smart Size Check with Auto-Compression
    
    /// Ensures video is under upload size limit, compressing if necessary
    private func ensureUploadableSize(videoURL: URL) async throws -> URL {
        let fileSize = try getFileSize(videoURL)
        
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¦ UPLOAD: File size is \(formatFileSize(fileSize))")
        
        // If under limit, use as-is
        if fileSize <= Self.maxUploadSize {
            print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ UPLOAD: File is within size limit")
            return videoURL
        }
        
        // Need to compress
        print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â UPLOAD: File exceeds \(formatFileSize(Self.maxUploadSize)), compressing...")
        await updateProgress(0.05, task: "Compressing large video...")
        
        let compressor = FastVideoCompressor.shared
        
        do {
            let result = try await compressor.compress(
                sourceURL: videoURL,
                targetSizeMB: Double(Self.targetCompressedSize) / 1024.0 / 1024.0,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        // Map compression progress to 5-10% of overall progress
                        self?.uploadProgress = 0.05 + (progress * 0.05)
                        self?.currentTask = "Compressing: \(Int(progress * 100))%"
                    }
                }
            )
            
            print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ UPLOAD: Compressed \(formatFileSize(fileSize)) ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ \(formatFileSize(result.compressedSize))")
            
            // Verify it's now under limit
            if result.compressedSize <= Self.maxUploadSize {
                return result.outputURL
            } else {
                // Still too big after compression - this is rare but possible for very long videos
                throw UploadError.fileTooLarge(
                    "Video is still \(formatFileSize(result.compressedSize)) after compression. " +
                    "Try trimming the video to under 2 minutes or recording at lower quality."
                )
            }
            
        } catch let compressionError as CompressionError {
            throw UploadError.compressionFailed(compressionError.localizedDescription)
        }
    }
    
    // MARK: - File Loading
    
    /// Loads video data (without hard size rejection)
    private func loadVideoData(_ videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard FileManager.default.fileExists(atPath: videoURL.path) else {
                        continuation.resume(throwing: UploadError.fileNotFound("Video file not found"))
                        return
                    }
                    
                    let videoData = try Data(contentsOf: videoURL)
                    continuation.resume(returning: videoData)
                    
                } catch {
                    continuation.resume(throwing: UploadError.fileLoadFailed("Failed to load video: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    // MARK: - Creates video document in Firestore
    
    func createVideoDocument(
        uploadResult: VideoUploadResult,
        metadata: VideoUploadMetadata,
        recordingContext: RecordingContext,
        videoService: VideoService,
        userService: UserService,
        notificationService: NotificationService,
        taggedUserIDs: [String] = [],
        recordingSource: String = "unknown",
        hashtags: [String] = []
    ) async throws -> CoreVideoMetadata {
        
        await updateProgress(0.95, task: "Creating video document...")
        
        let createdVideo: CoreVideoMetadata
        
        let orientation = VideoOrientation.from(aspectRatio: uploadResult.aspectRatio)
        print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â UPLOAD SERVICE: Creating \(orientation.displayName) video document")
        
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
                fileSize: uploadResult.fileSize,
                aspectRatio: uploadResult.aspectRatio,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // Notify followers
            Task {
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
                        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ UPLOAD SERVICE: Notified \(followerIDs.count) followers")
                    }
                } catch {
                    print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â UPLOAD SERVICE: Failed to notify followers - \(error)")
                }
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
                fileSize: uploadResult.fileSize,
                aspectRatio: uploadResult.aspectRatio,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // Stitch notification handled by VideoCoordinator (PHASE 4)
            // Only handle hype regen here
            Task {
                do {
                    let threadVideo = try await videoService.getVideo(id: threadID)
                    if threadVideo.creatorID != metadata.creatorID {
                        await HypeRatingService.shared.queueEngagementRegen(
                            source: .receivedStitch,
                            amount: HypeRegenSource.receivedStitch.baseRegenAmount
                        )
                    }
                } catch {
                    print("UPLOAD SERVICE: Failed to award stitch regen - \(error)")
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
                fileSize: uploadResult.fileSize,
                aspectRatio: uploadResult.aspectRatio,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // Reply notification handled by VideoCoordinator (PHASE 4)
            // Only handle hype regen here
            Task {
                do {
                    let parentVideo = try await videoService.getVideo(id: videoID)
                    if parentVideo.creatorID != metadata.creatorID {
                        await HypeRatingService.shared.queueEngagementRegen(
                            source: .receivedReply,
                            amount: HypeRegenSource.receivedReply.baseRegenAmount
                        )
                    }
                } catch {
                    print("UPLOAD SERVICE: Failed to award reply regen - \(error)")
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
                fileSize: uploadResult.fileSize,
                aspectRatio: uploadResult.aspectRatio,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // Continue thread notification handled by VideoCoordinator (PHASE 4)
            
        case .spinOffFrom(let videoID, let threadID, _):
            createdVideo = try await videoService.createSpinOffThread(
                originalVideoID: videoID,
                originalThreadID: threadID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize,
                aspectRatio: uploadResult.aspectRatio,
                recordingSource: recordingSource,
                hashtags: hashtags
            )
            
            // Spin-off notification handled by VideoCoordinator (PHASE 4)
        }
        
        // Handle tagged users
        if !taggedUserIDs.isEmpty {
            try await videoService.updateVideoTags(
                videoID: createdVideo.id,
                taggedUserIDs: taggedUserIDs
            )
            print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…â€™ UPLOAD SERVICE: Saved \(taggedUserIDs.count) tagged users")
            
            // Mention notifications handled by VideoCoordinator (PHASE 4)
        }
        await updateProgress(1.0, task: "Video created successfully!")
        print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ UPLOAD SERVICE: Video document created - \(createdVideo.id)")
        
        // MARK: - Hype Rating Regen for posting
        Task {
            let isInApp = recordingSource.lowercased() == "in_app" || recordingSource.lowercased() == "in-app"
            switch recordingContext {
            case .newThread:
                HypeRatingService.shared.didPostOriginalContent(isInApp: isInApp)
            case .stitchToThread:
                HypeRatingService.shared.didStitchContent()
            case .replyToVideo:
                HypeRatingService.shared.didReplyToContent()
            case .continueThread:
                HypeRatingService.shared.didStitchContent()
            case .spinOffFrom:
                HypeRatingService.shared.didPostOriginalContent(isInApp: isInApp)
            }
        }
        
        return createdVideo
    }
    
    // MARK: - Private Upload Methods
    
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
            
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                
                Task { @MainActor in
                    let mappedProgress = 0.3 + (percentComplete * 0.4)
                    self?.uploadProgress = mappedProgress
                }
            }
        }
    }
    
    private func uploadThumbnailToStorage(
        thumbnailData: Data,
        videoID: String
    ) async throws -> String {
        
        let storageRef = storage.reference().child("thumbnails/\(videoID).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(thumbnailData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    private func generateThumbnail(from videoURL: URL, at thumbnailTime: TimeInterval? = nil) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: videoURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 1080, height: 1920)
                
                // Use custom thumbnail time if set, otherwise default to 0.5s
                let time = CMTime(seconds: thumbnailTime ?? 0.5, preferredTimescale: 600)
                
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    let image = UIImage(cgImage: cgImage)
                    
                    guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
                        continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Failed to convert to JPEG"))
                        return
                    }
                    
                    continuation.resume(returning: jpegData)
                    
                } catch {
                    continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func extractTechnicalMetadata(from videoURL: URL) async throws -> TechnicalMetadata {
        let asset = AVAsset(url: videoURL)
        
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        
        let fileSize = try getFileSize(videoURL)
        
        var aspectRatio: Double = 9.0/16.0
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
            
            let orientation = VideoOrientation.from(aspectRatio: aspectRatio)
            print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â METADATA: \(orientation.displayName) - \(Int(width))x\(Int(height))")
        }
        
        return TechnicalMetadata(
            duration: seconds,
            fileSize: fileSize,
            aspectRatio: aspectRatio
        )
    }
    
    // MARK: - Helper Methods
    
    private func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func updateProgress(_ progress: Double, task: String) async {
        await MainActor.run {
            self.uploadProgress = progress
            self.currentTask = task
        }
    }
    
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
        
        if uploadMetrics.count > 50 {
            uploadMetrics.removeFirst()
        }
    }
    
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
    
    func clearError() {
        lastUploadError = nil
    }
}

// MARK: - Data Models

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

struct VideoUploadResult {
    let videoURL: String
    let thumbnailURL: String
    let duration: TimeInterval
    let fileSize: Int64
    let aspectRatio: Double
    let videoID: String
}

struct TechnicalMetadata {
    let duration: TimeInterval
    let fileSize: Int64
    let aspectRatio: Double
}

enum UploadError: Error, LocalizedError {
    case fileNotFound(String)
    case fileTooLarge(String)
    case fileLoadFailed(String)
    case uploadFailed(String)
    case thumbnailGenerationFailed(String)
    case metadataExtractionFailed(String)
    case compressionFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let msg): return "File Not Found: \(msg)"
        case .fileTooLarge(let msg): return "File Too Large: \(msg)"
        case .fileLoadFailed(let msg): return "File Load Failed: \(msg)"
        case .uploadFailed(let msg): return "Upload Failed: \(msg)"
        case .thumbnailGenerationFailed(let msg): return "Thumbnail Failed: \(msg)"
        case .metadataExtractionFailed(let msg): return "Metadata Failed: \(msg)"
        case .compressionFailed(let msg): return "Compression Failed: \(msg)"
        case .unknown(let msg): return msg
        }
    }
}

struct UploadMetrics {
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let fileSize: Int64
    let error: String?
}

struct UploadStats {
    let totalUploads: Int
    let successfulUploads: Int
    let successRate: Double
    let averageDuration: TimeInterval
}
