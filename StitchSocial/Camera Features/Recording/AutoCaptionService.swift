//
//  AutoCaptionService.swift
//  StitchSocial
//
//  Layer 4: Services - Auto Caption Generation
//  Dependencies: VideoEditState, Speech Framework
//  Features: Auto-transcribe audio to captions
//

import Foundation
import AVFoundation
import Speech

/// Automatically generates captions from video audio
@MainActor
class AutoCaptionService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AutoCaptionService()
    
    // MARK: - Published State
    
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0.0
    @Published var transcriptionError: String?
    
    // MARK: - Private Properties
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // MARK: - Public Interface
    
    /// Auto-generate captions from video audio
    func generateCaptions(from videoURL: URL) async throws -> [VideoCaption] {
        isTranscribing = true
        transcriptionProgress = 0.0
        transcriptionError = nil
        
        defer {
            isTranscribing = false
        }
        
        // Request authorization if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            await requestSpeechAuthorization()
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CaptionError.authorizationDenied
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw CaptionError.recognizerUnavailable
        }
        
        do {
            // Extract audio from video
            transcriptionProgress = 0.1
            let audioURL = try await extractAudio(from: videoURL)
            
            // Transcribe audio
            transcriptionProgress = 0.3
            let captions = try await transcribeAudio(audioURL: audioURL)
            
            transcriptionProgress = 1.0
            
            // Clean up temp audio file
            try? FileManager.default.removeItem(at: audioURL)
            
            print("✅ AUTO CAPTION: Generated \(captions.count) captions")
            
            return captions
            
        } catch {
            transcriptionError = error.localizedDescription
            print("❌ AUTO CAPTION: Failed - \(error)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    /// Request speech recognition authorization
    private func requestSpeechAuthorization() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume()
            }
        }
    }
    
    /// Extract audio from video
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        // Check if video has audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw CaptionError.noAudioTrack
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw CaptionError.exportFailed
        }
        
        // Configure output
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted_audio_\(UUID().uuidString).m4a")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Export audio
        await exportSession.export()
        
        if exportSession.status == .completed {
            return outputURL
        } else {
            throw CaptionError.exportFailed
        }
    }
    
    /// Transcribe audio to captions
    private func transcribeAudio(audioURL: URL) async throws -> [VideoCaption] {
        guard let recognizer = speechRecognizer else {
            throw CaptionError.recognizerUnavailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        // Perform transcription
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                
                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
        }
        
        // Convert transcription to captions
        return createCaptionsFromTranscription(result)
    }
    
    /// Create caption objects from transcription result
    private func createCaptionsFromTranscription(_ result: SFSpeechRecognitionResult) -> [VideoCaption] {
        var captions: [VideoCaption] = []
        
        // Group words into segments (max 10 words per caption)
        let segments = result.bestTranscription.segments
        var currentWords: [String] = []
        var currentStartTime: TimeInterval = 0
        var lastEndTime: TimeInterval = 0
        
        for segment in segments {
            let startTime = segment.timestamp
            let duration = segment.duration
            
            // Start new caption if empty
            if currentWords.isEmpty {
                currentStartTime = startTime
            }
            
            currentWords.append(segment.substring)
            lastEndTime = startTime + duration
            
            // Create caption every 10 words or at natural pauses
            if currentWords.count >= 10 || segment.substring.hasSuffix(".") ||
               segment.substring.hasSuffix("?") || segment.substring.hasSuffix("!") {
                
                let text = currentWords.joined(separator: " ")
                let captionDuration = lastEndTime - currentStartTime
                
                let caption = VideoCaption(
                    text: text,
                    startTime: currentStartTime,
                    duration: max(2.0, captionDuration), // Min 2 seconds
                    position: .bottom, // Default to bottom
                    style: .standard
                )
                
                captions.append(caption)
                
                currentWords = []
            }
        }
        
        // Add any remaining words as final caption
        if !currentWords.isEmpty {
            let text = currentWords.joined(separator: " ")
            let captionDuration = lastEndTime - currentStartTime
            
            let caption = VideoCaption(
                text: text,
                startTime: currentStartTime,
                duration: max(2.0, captionDuration),
                position: .bottom,
                style: .standard
            )
            
            captions.append(caption)
        }
        
        return captions
    }
    
    /// Check if device supports speech recognition
    func isSpeechRecognitionAvailable() -> Bool {
        return speechRecognizer?.isAvailable ?? false
    }
}

// MARK: - Errors

enum CaptionError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case noAudioTrack
    case exportFailed
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission denied"
        case .recognizerUnavailable:
            return "Speech recognizer not available"
        case .noAudioTrack:
            return "Video has no audio track"
        case .exportFailed:
            return "Failed to extract audio"
        case .transcriptionFailed:
            return "Failed to transcribe audio"
        }
    }
}
