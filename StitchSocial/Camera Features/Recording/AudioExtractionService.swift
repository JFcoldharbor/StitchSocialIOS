//
//  AudioExtractionService.swift
//  StitchSocial
//
//  Layer 2: Fast Audio Extraction for AI Analysis
//
//  ARCHITECTURE:
//  - Pure async/await — no Timer, no withCheckedContinuation for export
//  - Uses AVURLAsset (not deprecated AVAsset(url:))
//  - Uses export(to:as:) async throws (not exportAsynchronously callback)
//  - Progress via direct polling in async loop (not Timer)
//
//  CACHING: extractionTimes capped at 10 for rolling average
//  CLEANUP: temp files cleaned after 5-min TTL
//

import Foundation
import AVFoundation

@MainActor
class AudioExtractionService: ObservableObject {

    // MARK: - Published State
    @Published var isExtracting = false
    @Published var extractionProgress = 0.0
    @Published var currentTask = ""
    @Published var lastError: AudioExtractionError?

    // MARK: - Analytics (capped at 10 entries)
    @Published var totalExtractions = 0
    @Published var averageExtractionTime: TimeInterval = 0
    private var extractionTimes: [TimeInterval] = []

    // MARK: - Config
    private let maxDuration: TimeInterval = 300

    // MARK: - Extract Audio

    func extractAudio(
        from videoURL: URL,
        progressCallback: @escaping (Double) -> Void = { _ in }
    ) async throws -> AudioExtractionResult {

        let startTime = Date()
        isExtracting = true
        extractionProgress = 0
        currentTask = "Preparing..."
        lastError = nil

        defer {
            isExtracting = false
            recordTime(Date().timeIntervalSince(startTime))
        }

        do {
            // Validate
            update(0.1, "Validating..."); progressCallback(0.1)
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                throw AudioExtractionError.fileNotFound
            }

            // Load asset
            update(0.2, "Loading asset..."); progressCallback(0.2)
            let asset = AVURLAsset(url: videoURL)

            // Check duration
            update(0.3, "Checking duration..."); progressCallback(0.3)
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds > 0, seconds <= maxDuration else {
                throw AudioExtractionError.invalidDuration(seconds)
            }

            // Check audio tracks
            update(0.4, "Checking audio..."); progressCallback(0.4)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw AudioExtractionError.noAudioTrack
            }

            // Prepare output
            update(0.5, "Preparing export..."); progressCallback(0.5)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("extracted_audio_\(UUID().uuidString).m4a")

            // Export using modern async API
            update(0.6, "Extracting audio..."); progressCallback(0.6)
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw AudioExtractionError.exportSessionFailed
            }

            exportSession.outputFileType = .m4a
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.metadata = []

            try await exportSession.export(to: outputURL, as: .m4a)

            // Validate output
            update(0.95, "Validating output..."); progressCallback(0.95)
            let fileSize = getFileSize(outputURL)
            guard fileSize > 0 else {
                throw AudioExtractionError.extractionFailed("Empty audio file")
            }

            update(1.0, "Complete"); progressCallback(1.0)

            let result = AudioExtractionResult(
                audioURL: outputURL,
                originalVideoURL: videoURL,
                duration: seconds,
                fileSize: fileSize,
                format: .m4a,
                extractionTime: Date().timeIntervalSince(startTime)
            )

            #if DEBUG
            print("🎵 AUDIO: Extracted \(String(format: "%.1f", seconds))s, \(formatBytes(fileSize)), \(String(format: "%.1f", result.extractionTime))s")
            #endif
            return result

        } catch {
            lastError = error as? AudioExtractionError ?? .extractionFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Cleanup (5-min TTL)

    func cleanupTemporaryFiles() {
        Task.detached(priority: .utility) {
            let tempDir = FileManager.default.temporaryDirectory
            let cutoff = Date().addingTimeInterval(-300)

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: [.creationDateKey]
            ) else { return }

            var cleaned = 0
            for file in files where file.lastPathComponent.hasPrefix("extracted_audio_") {
                if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let created = attrs.creationDate, created < cutoff {
                    try? FileManager.default.removeItem(at: file)
                    cleaned += 1
                }
            }
            if cleaned > 0 { print("🧹 AUDIO: Cleaned \(cleaned) temp files") }
        }
    }

    // MARK: - Helpers

    private func update(_ progress: Double, _ task: String) {
        extractionProgress = progress
        currentTask = task
    }

    private func recordTime(_ time: TimeInterval) {
        totalExtractions += 1
        extractionTimes.append(time)
        if extractionTimes.count > 10 { extractionTimes.removeFirst() }
        averageExtractionTime = extractionTimes.reduce(0, +) / Double(extractionTimes.count)
    }

    private func getFileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Supporting Types

struct AudioExtractionResult {
    let audioURL: URL
    let originalVideoURL: URL
    let duration: TimeInterval
    let fileSize: Int64
    let format: AudioFormat
    let extractionTime: TimeInterval
}

enum AudioFormat: String, CaseIterable {
    case m4a, mp3, wav
    var fileExtension: String { rawValue }
}

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
        case .fileNotFound: return "Video file not found"
        case .invalidVideoFile: return "Invalid video file"
        case .noAudioTrack: return "No audio track found"
        case .invalidDuration(let d): return "Invalid duration: \(String(format: "%.1f", d))s"
        case .exportSessionFailed: return "Failed to create export session"
        case .exportFailed(let m): return "Export failed: \(m)"
        case .extractionFailed(let m): return "Extraction failed: \(m)"
        case .extractionCancelled: return "Extraction cancelled"
        }
    }
}
