//
//  VideoUploadService.swift
//  CleanBeta
//
//  Layer 4: Core Services - Video Upload Management
//  FIXED: Added description parameter to all video creation calls
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import AVFoundation
import UIKit

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
            await updateProgress(0.1, task: "Validating video...")
            let videoData = try await validateAndLoadVideo(videoURL)
            
            await updateProgress(0.2, task: "Generating thumbnail...")
            let thumbnailData = try await generateThumbnail(from: videoURL)
            
            await updateProgress(0.3, task: "Uploading video...")
            let videoStorageURL = try await uploadVideoToStorage(
                videoData: videoData,
                metadata: metadata
            )
            
            await updateProgress(0.7, task: "Uploading thumbnail...")
            let thumbnailStorageURL = try await uploadThumbnailToStorage(
                thumbnailData: thumbnailData,
                videoID: metadata.videoID
            )
            
            await updateProgress(0.9, task: "Processing metadata...")
            let technicalMetadata = try await extractTechnicalMetadata(from: videoURL)
            
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
    
    // MARK: - FIXED: Video Document Creation with Description
    
    func createVideoDocument(
        uploadResult: VideoUploadResult,
        metadata: VideoUploadMetadata,
        recordingContext: RecordingContext,
        videoService: VideoService
    ) async throws -> CoreVideoMetadata {
        
        await updateProgress(0.95, task: "Creating video document...")
        
        let createdVideo: CoreVideoMetadata
        
        switch recordingContext {
        case .newThread:
            // FIXED: Added description parameter
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
            
        case .stitchToThread(let threadID, _):
            // FIXED: Added description parameter
            createdVideo = try await videoService.createChildReply(
                to: threadID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
        case .replyToVideo(let videoID, _):
            // FIXED: Added description parameter
            createdVideo = try await videoService.createChildReply(
                to: videoID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
            
        case .continueThread(let threadID, _):
            // FIXED: Added description parameter
            createdVideo = try await videoService.createChildReply(
                to: threadID,
                title: metadata.title,
                description: metadata.description,
                videoURL: uploadResult.videoURL,
                thumbnailURL: uploadResult.thumbnailURL,
                creatorID: metadata.creatorID,
                creatorName: metadata.creatorName,
                duration: uploadResult.duration,
                fileSize: uploadResult.fileSize
            )
        }
        
        await updateProgress(1.0, task: "Video created successfully!")
        
        print("✅ UPLOAD SERVICE: Video document created - \(createdVideo.id)")
        return createdVideo
    }
    
    // MARK: - Private Upload Methods
    
    private func validateAndLoadVideo(_ videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard FileManager.default.fileExists(atPath: videoURL.path) else {
                        continuation.resume(throwing: UploadError.fileNotFound("Video file not found"))
                        return
                    }
                    
                    let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = resourceValues.fileSize ?? 0
                    
                    guard fileSize <= 100 * 1024 * 1024 else {
                        continuation.resume(throwing: UploadError.fileTooLarge("File size exceeds 100MB limit"))
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
                        continuation.resume(throwing: UploadError.uploadFailed("Download URL is nil"))
                        return
                    }
                    
                    continuation.resume(returning: downloadURL.absoluteString)
                }
            }
            
            uploadTask.observe(.progress) { snapshot in
                let percentComplete = Double(snapshot.progress?.fractionCompleted ?? 0)
                let adjustedProgress = 0.3 + (percentComplete * 0.4)
                Task { @MainActor in
                    self.uploadProgress = adjustedProgress
                }
            }
        }
    }
    
    private func uploadThumbnailToStorage(
        thumbnailData: Data,
        videoID: String
    ) async throws -> String {
        
        let storageRef = storage.reference().child("thumbnails/\(videoID).jpg")
        
        let storageMetadata = StorageMetadata()
        storageMetadata.contentType = "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            storageRef.putData(thumbnailData, metadata: storageMetadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: UploadError.uploadFailed("Thumbnail upload failed: \(error.localizedDescription)"))
                    return
                }
                
                storageRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: UploadError.uploadFailed("Failed to get thumbnail URL: \(error.localizedDescription)"))
                        return
                    }
                    
                    guard let downloadURL = url else {
                        continuation.resume(throwing: UploadError.uploadFailed("Thumbnail URL is nil"))
                        return
                    }
                    
                    continuation.resume(returning: downloadURL.absoluteString)
                }
            }
        }
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let asset = AVAsset(url: videoURL)
                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                    imageGenerator.appliesPreferredTrackTransform = true
                    imageGenerator.maximumSize = CGSize(width: 720, height: 1280)
                    
                    let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    
                    let uiImage = UIImage(cgImage: cgImage)
                    guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
                        continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Failed to generate JPEG data"))
                        return
                    }
                    
                    continuation.resume(returning: jpegData)
                    
                } catch {
                    continuation.resume(throwing: UploadError.thumbnailGenerationFailed("Thumbnail generation failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func extractTechnicalMetadata(from videoURL: URL) async throws -> TechnicalMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let asset = AVAsset(url: videoURL)
                    
                    let duration = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    
                    let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = Int64(resourceValues.fileSize ?? 0)
                    
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
    
    // MARK: - Helper Methods
    
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
        
        print("📊 UPLOAD SERVICE: Metrics - Duration: \(String(format: "%.2f", duration))s, Success: \(success), File Size: \(fileSize) bytes")
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
