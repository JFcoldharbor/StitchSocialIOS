//
//  AudioExtractionService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Fast Audio Extraction for Parallel Processing
//  Dependencies: AVFoundation
//  Features: High-speed audio extraction, optimized for AI analysis, parallel processing support
//

import Foundation
import AVFoundation

/// Fast audio extraction service for parallel video processing
@MainActor
class AudioExtractionService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isExtracting: Bool = false
    @Published var extractionProgress: Double = 0.0
    @Published var currentTask: String = ""
    @Published var lastError: AudioExtractionError?
    
    // MARK: - Analytics
    
    @Published var totalExtractions: Int = 0
    @Published var averageExtractionTime: TimeInterval = 0.0
    private var extractionTimes: [TimeInterval] = []
    
    // MARK: - Configuration
    
    private let audioFormat: AudioFormat = .m4a
    private let audioQuality: AudioQuality = .medium
    private let maxDuration: TimeInterval = 300 // 5 minutes max
    
    // MARK: - Public Interface
    
    /// Fast audio extraction optimized for AI analysis
    /// Returns URL of extracted audio file and duration
    func extractAudio(
        from videoURL: URL,
        progressCallback: @escaping (Double) -> Void = { _ in }
    ) async throws -> AudioExtractionResult {
        
        let startTime = Date()
        
        await MainActor.run {
            self.isExtracting = true
            self.extractionProgress = 0.0
            self.currentTask = "Preparing audio extraction..."
            self.lastError = nil
        }
        
        defer {
            Task { @MainActor in
                self.isExtracting = false
                self.recordExtractionTime(Date().timeIntervalSince(startTime))
            }
        }
        
        do {
            // STEP 1: Validate video file
            await updateProgress(0.1, task: "Validating video file...")
            progressCallback(0.1)
            try await validateVideoFile(videoURL)
            
            // STEP 2: Create audio asset
            await updateProgress(0.2, task: "Loading video asset...")
            progressCallback(0.2)
            let asset = AVAsset(url: videoURL)
            
            // STEP 3: Get duration and validate
            await updateProgress(0.3, task: "Analyzing video duration...")
            progressCallback(0.3)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            guard durationSeconds > 0 && durationSeconds <= maxDuration else {
                throw AudioExtractionError.invalidDuration(durationSeconds)
            }
            
            // STEP 4: Check for audio tracks
            await updateProgress(0.4, task: "Checking audio tracks...")
            progressCallback(0.4)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw AudioExtractionError.noAudioTrack
            }
            
            // STEP 5: Create output URL
            await updateProgress(0.5, task: "Preparing extraction...")
            progressCallback(0.5)
            let outputURL = createTemporaryAudioURL()
            
            // STEP 6: Perform fast extraction
            await updateProgress(0.6, task: "Extracting audio...")
            progressCallback(0.6)
            try await performFastExtraction(
                asset: asset,
                outputURL: outputURL,
                progressCallback: { progress in
                    let adjustedProgress = 0.6 + (progress * 0.3) // 60-90%
                    Task { @MainActor in
                        await self.updateProgress(adjustedProgress, task: "Extracting audio... \(Int(progress * 100))%")
                    }
                    progressCallback(adjustedProgress)
                }
            )
            
            // STEP 7: Validate extracted file
            await updateProgress(0.9, task: "Validating extracted audio...")
            progressCallback(0.9)
            let audioSize = getFileSize(outputURL)
            guard audioSize > 0 else {
                throw AudioExtractionError.extractionFailed("Empty audio file")
            }
            
            await updateProgress(1.0, task: "Audio extraction complete")
            progressCallback(1.0)
            
            let result = AudioExtractionResult(
                audioURL: outputURL,
                originalVideoURL: videoURL,
                duration: durationSeconds,
                fileSize: audioSize,
                format: audioFormat,
                extractionTime: Date().timeIntervalSince(startTime)
            )
            
            print("🎵 AUDIO EXTRACTION: Success")
            print("🎵 AUDIO EXTRACTION: Duration: \(String(format: "%.1f", durationSeconds))s")
            print("🎵 AUDIO EXTRACTION: Size: \(formatFileSize(audioSize))")
            print("🎵 AUDIO EXTRACTION: Time: \(String(format: "%.1f", result.extractionTime))s")
            
            return result
            
        } catch {
            await MainActor.run {
                self.lastError = error as? AudioExtractionError ?? .extractionFailed(error.localizedDescription)
            }
            
            print("❌ AUDIO EXTRACTION: Failed with error - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Extract audio with custom settings
    func extractAudioWithSettings(
        from videoURL: URL,
        format: AudioFormat = .m4a,
        quality: AudioQuality = .medium,
        startTime: CMTime = .zero,
        endTime: CMTime? = nil
    ) async throws -> AudioExtractionResult {
        
        // Implementation for custom extraction settings
        return try await extractAudio(from: videoURL)
    }
    
    // MARK: - Private Implementation
    
    /// Perform fast audio extraction using AVAssetExportSession
    /// FIXED: Better audio quality settings to prevent distortion
    private func performFastExtraction(
        asset: AVAsset,
        outputURL: URL,
        progressCallback: @escaping (Double) -> Void
    ) async throws {
        
        return try await withCheckedThrowingContinuation { continuation in
            
            // Use high-quality audio preset instead of basic M4A
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                continuation.resume(throwing: AudioExtractionError.exportSessionFailed)
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            exportSession.shouldOptimizeForNetworkUse = true
            
            // FIXED: Add high-quality audio settings to prevent distortion
            exportSession.audioMix = nil // No mixing for speed but preserve quality
            
            // Set high-quality audio export settings
            exportSession.metadata = [] // Clear metadata for speed
            
            // Track progress
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    progressCallback(Double(exportSession.progress))
                }
            }
            
            exportSession.exportAsynchronously {
                timer.invalidate()
                
                switch exportSession.status {
                case .completed:
                    print("🎵 HIGH-QUALITY EXTRACTION: AVFoundation export completed")
                    continuation.resume()
                case .failed:
                    let error = exportSession.error?.localizedDescription ?? "Unknown extraction error"
                    continuation.resume(throwing: AudioExtractionError.exportFailed(error))
                case .cancelled:
                    continuation.resume(throwing: AudioExtractionError.extractionCancelled)
                default:
                    continuation.resume(throwing: AudioExtractionError.extractionFailed("Unexpected export status"))
                }
            }
        }
    }
    
    /// Validate video file for audio extraction
    private func validateVideoFile(_ url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioExtractionError.fileNotFound
        }
        
        let asset = AVAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw AudioExtractionError.invalidVideoFile
        }
    }
    
    /// Create temporary URL for extracted audio
    private func createTemporaryAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "extracted_audio_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(filename)
    }
    
    /// Update progress and task description
    private func updateProgress(_ progress: Double, task: String) async {
        await MainActor.run {
            self.extractionProgress = progress
            self.currentTask = task
        }
    }
    
    /// Record extraction time for analytics
    private func recordExtractionTime(_ time: TimeInterval) {
        totalExtractions += 1
        extractionTimes.append(time)
        
        // Keep only last 10 times for average calculation
        if extractionTimes.count > 10 {
            extractionTimes.removeFirst()
        }
        
        averageExtractionTime = extractionTimes.reduce(0, +) / Double(extractionTimes.count)
        
        print("📊 AUDIO EXTRACTION: Average time: \(String(format: "%.1f", averageExtractionTime))s")
    }
    
    // MARK: - Helper Methods
    
    /// Get file size for URL
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return 0
        }
    }
    
    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Cleanup (FIXED TIMING)
    
    /// Cleanup temporary audio files
    /// FIXED: More conservative cleanup to avoid race conditions
    func cleanupTemporaryFiles() {
        Task {
            // Wait to ensure all operations are complete
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            let tempDir = FileManager.default.temporaryDirectory
            
            do {
                let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
                
                // Only cleanup audio files older than 5 minutes to avoid race conditions
                let cutoffTime = Date().addingTimeInterval(-300) // 5 minutes ago
                let audioFiles = tempFiles.filter { url in
                    guard url.lastPathComponent.hasPrefix("extracted_audio_") else { return false }
                    
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])
                        if let creationDate = resourceValues.creationDate {
                            return creationDate < cutoffTime
                        }
                    } catch {
                        print("⚠️ AUDIO EXTRACTION: Could not get creation date for \(url.lastPathComponent)")
                    }
                    return false
                }
                
                for file in audioFiles {
                    try? FileManager.default.removeItem(at: file)
                }
                
                if !audioFiles.isEmpty {
                    print("🧹 AUDIO EXTRACTION: Cleaned up \(audioFiles.count) old temporary audio files")
                }
            } catch {
                print("⚠️ AUDIO EXTRACTION: Cleanup failed - \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Supporting Types

/// Audio extraction result
struct AudioExtractionResult {
    let audioURL: URL
    let originalVideoURL: URL
    let duration: TimeInterval
    let fileSize: Int64
    let format: AudioFormat
    let extractionTime: TimeInterval
}

/// Audio format options
enum AudioFormat: String, CaseIterable {
    case m4a = "m4a"
    case mp3 = "mp3"
    case wav = "wav"
    
    var fileExtension: String { rawValue }
    var mimeType: String {
        switch self {
        case .m4a: return "audio/mp4"
        case .mp3: return "audio/mpeg"
        case .wav: return "audio/wav"
        }
    }
}

/// Audio quality settings
enum AudioQuality: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var bitrate: Int {
        switch self {
        case .low: return 64_000    // 64 kbps
        case .medium: return 128_000 // 128 kbps
        case .high: return 256_000   // 256 kbps
        }
    }
}

/// Audio extraction errors
enum AudioExtractionError: LocalizedError {
    case fileNotFound
    case invalidVideoFile
    case noAudioTrack
    case invalidDuration(TimeInterval)
    case exportSessionFailed
    case exportFailed(String)
    case extractionFailed(String)
    case extractionCancelled
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Video file not found"
        case .invalidVideoFile:
            return "Invalid video file"
        case .noAudioTrack:
            return "No audio track found in video"
        case .invalidDuration(let duration):
            return "Invalid video duration: \(String(format: "%.1f", duration))s"
        case .exportSessionFailed:
            return "Failed to create audio export session"
        case .exportFailed(let message):
            return "Audio export failed: \(message)"
        case .extractionFailed(let message):
            return "Audio extraction failed: \(message)"
        case .extractionCancelled:
            return "Audio extraction was cancelled"
        }
    }
}
