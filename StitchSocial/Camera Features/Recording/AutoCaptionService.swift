//
//  AutoCaptionService.swift
//  StitchSocial
//
//  Layer 2.5: Auto Caption Generation via Speech Recognition
//
//  ARCHITECTURE:
//  - Extracts audio to temp file using modern async export
//  - Runs SFSpeechRecognizer on extracted audio
//  - Returns timed captions with word-level timestamps
//  - Pure async/await — no callbacks, no deprecated APIs
//
//  CACHING: None needed — captions generated once per video
//  CLEANUP: Temp audio file deleted after recognition
//

import Foundation
import AVFoundation
import Speech

enum CaptionError: LocalizedError {
    case noAudioTrack
    case authorizationDenied
    case recognitionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "No audio track found"
        case .authorizationDenied: return "Speech recognition not authorized"
        case .recognitionFailed(let m): return "Recognition failed: \(m)"
        case .exportFailed(let m): return "Audio export failed: \(m)"
        }
    }
}

@MainActor
class AutoCaptionService: ObservableObject {

    static let shared = AutoCaptionService()

    // MARK: - Published State (used by CaptionEditorView)
    @Published var isTranscribing = false
    @Published var transcriptionProgress = 0.0

    // MARK: - Generate Captions

    func generateCaptions(from videoURL: URL) async throws -> [VideoCaption] {

        isTranscribing = true
        transcriptionProgress = 0
        defer { isTranscribing = false; transcriptionProgress = 1.0 }

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            throw CaptionError.authorizationDenied
        }

        if authStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else { throw CaptionError.authorizationDenied }
        }

        // Extract audio
        transcriptionProgress = 0.2
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw CaptionError.noAudioTrack }

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("caption_audio_\(UUID().uuidString).m4a")

        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw CaptionError.exportFailed("Cannot create export session")
        }

        exportSession.outputFileType = .m4a
        try await exportSession.export(to: audioURL, as: .m4a)

        // Run speech recognition
        transcriptionProgress = 0.5
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw CaptionError.recognitionFailed("Speech recognizer unavailable")
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: CaptionError.recognitionFailed(error.localizedDescription))
                } else if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        // Build captions from transcription segments
        let captions = buildCaptions(from: result)
        #if DEBUG
        print("✅ AUTO CAPTION: Generated \(captions.count) captions")
        #endif
        return captions
    }

    // MARK: - Build Captions

    private func buildCaptions(from result: SFSpeechRecognitionResult) -> [VideoCaption] {
        let fullText = result.bestTranscription.formattedString
        guard !fullText.isEmpty else { return [] }

        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else {
            return [VideoCaption(text: fullText, startTime: 0, duration: 3.0)]
        }

        // Group segments into ~3 second chunks. Per-word timestamps are
        // preserved on each chunk so word-highlight presets can animate
        // word-by-word in both preview and export.
        var captions: [VideoCaption] = []
        var currentWords: [WordTiming] = []
        var chunkStart: TimeInterval = segments.first?.timestamp ?? 0
        let targetChunkDuration: TimeInterval = 3.0

        for segment in segments {
            let elapsed = segment.timestamp - chunkStart
            currentWords.append(WordTiming(
                text: segment.substring,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration
            ))

            if elapsed >= targetChunkDuration || segment == segments.last {
                let text = currentWords.map { $0.text }.joined(separator: " ")
                let duration = max(segment.timestamp + segment.duration - chunkStart, 1.0)

                captions.append(VideoCaption(
                    text: text,
                    startTime: chunkStart,
                    duration: min(duration, 5.0),
                    words: currentWords
                ))

                currentWords = []
                chunkStart = segment.timestamp + segment.duration
            }
        }

        return captions
    }
}
