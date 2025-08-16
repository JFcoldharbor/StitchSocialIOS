//
//  AIVideoAnalyzer.swift
//  CleanBeta
//
//  Created by James Garmon on 8/10/25.
//


//
//  AIVideoAnalyzer.swift
//  CleanBeta
//
//  Layer 5: Business Logic - AI Video Content Analysis
//  Dependencies: Layer 4 (Services), Layer 3 (Firebase), Layer 2 (Protocols), Layer 1 (Foundation)
//  OpenAI Whisper + GPT integration for auto-generating video metadata
//

import Foundation
import AVFoundation

/// OpenAI speech-to-text video analysis for auto-generating titles, descriptions, and hashtags
/// Premium feature that provides seamless content creation assistance with manual fallback
/// Integrates with recording flow to enhance user experience
@MainActor
class AIVideoAnalyzer: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isAnalyzing: Bool = false
    @Published var analysisProgress: Double = 0.0
    @Published var lastAnalysisResult: VideoAnalysisResult?
    @Published var analysisError: AIAnalysisError?
    @Published var showingError: Bool = false
    
    // MARK: - Configuration
    
    private let openAIAPIKey: String
    private let maxRetries = 2
    private let timeoutInterval: TimeInterval = 30.0
    
    // Public access to check if AI is available
    var isAIAvailable: Bool {
        return !openAIAPIKey.isEmpty && !openAIAPIKey.hasPrefix("sk-your-")
    }
    
    // MARK: - Analytics
    
    @Published var totalAnalysesPerformed: Int = 0
    @Published var successRate: Double = 100.0
    private var analysisHistory: [AnalysisMetrics] = []
    
    // MARK: - Initialization
    
    init() {
        // Get OpenAI API key from Config
        self.openAIAPIKey = Config.API.OpenAI.apiKey
        
        print("🚨🚨🚨 TESTING NEW CODE - API KEY LENGTH: \(openAIAPIKey.count) 🚨🚨🚨")
        
        if openAIAPIKey.isEmpty || openAIAPIKey.hasPrefix("sk-your-") {
            print("⚠️ AI ANALYZER: OpenAI API key not configured - manual content creation will be used")
        } else {
            print("🤖 AI ANALYZER: Initialized with OpenAI integration")
        }
    }
    
    // MARK: - Public Interface
    
    /// Analyzes video content and generates title, description, and hashtags
    /// Falls back gracefully when API key is not configured, allowing manual content creation
    /// - Parameter videoURL: Local URL of recorded video
    /// - Returns: VideoAnalysisResult with generated content or nil if API unavailable (user creates own content)
    func analyzeVideo(url videoURL: URL, userID: String) async -> VideoAnalysisResult? {
        print("🚨🚨🚨 ANALYZE VIDEO CALLED - USER: \(userID) 🚨🚨🚨")
        print("🚨 API KEY LENGTH: \(openAIAPIKey.count)")
        print("🚨 API KEY STARTS WITH sk-your-: \(openAIAPIKey.hasPrefix("sk-your-"))")
        
        let startTime = Date()
        
        print("🤖 AI ANALYZER: Starting analysis for user: \(userID)")
        print("🤖 AI ANALYZER: Video URL: \(videoURL)")
        print("🤖 AI ANALYZER: API key length: \(openAIAPIKey.count)")
        print("🤖 AI ANALYZER: API key starts with 'sk-your-': \(openAIAPIKey.hasPrefix("sk-your-"))")
        print("🤖 AI ANALYZER: API key first 10 chars: '\(String(openAIAPIKey.prefix(10)))...'")
        
        // Check if API key is properly configured (not a placeholder)
        guard !openAIAPIKey.isEmpty && !openAIAPIKey.hasPrefix("sk-your-") else {
            print("🚨🚨🚨 API KEY GUARD FAILED - RETURNING NIL 🚨🚨🚨")
            print("🚨 isEmpty: \(openAIAPIKey.isEmpty)")
            print("🚨 hasPrefix sk-your-: \(openAIAPIKey.hasPrefix("sk-your-"))")
            print("🤖 AI ANALYZER: API key not configured - user will create content manually")
            print("🤖 AI ANALYZER: isEmpty: \(openAIAPIKey.isEmpty), hasPrefix: \(openAIAPIKey.hasPrefix("sk-your-"))")
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 0.0
            }
            // Return nil so user can create their own content
            return nil
        }
        
        print("🤖 AI ANALYZER: API key validation passed - proceeding with analysis")
        
        await MainActor.run {
            self.isAnalyzing = true
            self.analysisProgress = 0.0
            self.analysisError = nil
        }
        
        do {
            print("🤖 AI ANALYZER: Step 1 - Extracting audio from video")
            // Step 1: Extract audio from video (20% progress)
            await updateProgress(0.2)
            let audioData = try await extractAudioFromVideo(videoURL)
            print("🤖 AI ANALYZER: Audio extracted successfully, size: \(audioData.count) bytes")
            
            print("🤖 AI ANALYZER: Step 2 - Transcribing audio to text")
            // Step 2: Transcribe audio to text (60% progress)
            await updateProgress(0.6)
            let transcript = try await transcribeAudio(audioData)
            print("🤖 AI ANALYZER: Transcript generated, length: \(transcript.count) characters")
            print("🤖 AI ANALYZER: Transcript preview: '\(String(transcript.prefix(100)))...'")
            
            print("🤖 AI ANALYZER: Step 3 - Generating content from transcript")
            // Step 3: Generate content using custom prompt (90% progress)
            await updateProgress(0.9)
            let result = try await generateContentFromTranscript(transcript)
            print("🤖 AI ANALYZER: Content generated successfully")
            print("🤖 AI ANALYZER: Generated title: '\(result.title)'")
            print("🤖 AI ANALYZER: Generated description: '\(result.description)'")
            print("🤖 AI ANALYZER: Generated hashtags: \(result.hashtags)")
            
            // Step 4: Complete analysis (100% progress)
            await updateProgress(1.0)
            
            await MainActor.run {
                self.lastAnalysisResult = result
                self.isAnalyzing = false
                self.totalAnalysesPerformed += 1
            }
            
            // Record successful analysis
            recordAnalysisMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: true,
                transcriptLength: transcript.count,
                error: nil
            )
            
            print("🤖 AI ANALYZER: Successfully analyzed video - Title: '\(result.title)'")
            return result
            
        } catch {
            print("❌ AI ANALYZER: Analysis failed with error: \(error)")
            print("❌ AI ANALYZER: Error type: \(type(of: error))")
            print("❌ AI ANALYZER: Error description: \(error.localizedDescription)")
            
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisError = error as? AIAnalysisError ?? .unknown(error.localizedDescription)
                self.showingError = false // Don't show error UI, just log and allow manual creation
            }
            
            // Record failed analysis
            recordAnalysisMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: false,
                transcriptLength: 0,
                error: error
            )
            
            print("🤖 AI ANALYZER: Analysis failed - \(error.localizedDescription) - allowing manual content creation")
            // Return nil so user can create their own content instead of showing error
            return nil
        }
    }
    
    // MARK: - Audio Processing
    
    /// Extracts audio track from video for transcription
    private func extractAudioFromVideo(_ videoURL: URL) async throws -> Data {
        print("🎵 AUDIO EXTRACTION: Starting for video: \(videoURL.lastPathComponent)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let asset = AVAsset(url: videoURL)
                    
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !audioTracks.isEmpty else {
                        print("❌ AUDIO EXTRACTION: No audio track found")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("No audio track found"))
                        return
                    }
                    
                    print("🎵 AUDIO EXTRACTION: Found \(audioTracks.count) audio track(s)")
                    
                    let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
                    exportSession?.outputFileType = .m4a
                    
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("temp_audio_\(UUID().uuidString).m4a")
                    
                    exportSession?.outputURL = tempURL
                    
                    guard let session = exportSession else {
                        print("❌ AUDIO EXTRACTION: Failed to create export session")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to create export session"))
                        return
                    }
                    
                    print("🎵 AUDIO EXTRACTION: Starting audio export...")
                    await session.export()
                    
                    switch session.status {
                    case .completed:
                        print("🎵 AUDIO EXTRACTION: Export completed successfully")
                        do {
                            let audioData = try Data(contentsOf: tempURL)
                            print("🎵 AUDIO EXTRACTION: Audio data size: \(audioData.count) bytes")
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(returning: audioData)
                        } catch {
                            print("❌ AUDIO EXTRACTION: Failed to read audio data: \(error)")
                            continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to read audio data"))
                        }
                        
                    case .failed:
                        let errorMessage = session.error?.localizedDescription ?? "Unknown export error"
                        print("❌ AUDIO EXTRACTION: Export failed: \(errorMessage)")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Export failed: \(errorMessage)"))
                        
                    default:
                        print("❌ AUDIO EXTRACTION: Unexpected export status: \(session.status.rawValue)")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Unexpected export status"))
                    }
                    
                } catch {
                    print("❌ AUDIO EXTRACTION: General error: \(error)")
                    continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Audio extraction failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// Transcribes audio data to text using OpenAI Whisper
    private func transcribeAudio(_ audioData: Data) async throws -> String {
        print("🎤 TRANSCRIPTION: Starting with \(audioData.count) bytes of audio data")
        
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/audio/transcriptions")!
        print("🎤 TRANSCRIPTION: Using URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutInterval
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("🎤 TRANSCRIPTION: Sending request to OpenAI, body size: \(body.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("🎤 TRANSCRIPTION: Received response")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ TRANSCRIPTION: Invalid response type")
            throw AIAnalysisError.transcriptionFailed("Invalid response type")
        }
        
        print("🎤 TRANSCRIPTION: HTTP status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ TRANSCRIPTION: HTTP error \(httpResponse.statusCode): \(responseString)")
            throw AIAnalysisError.transcriptionFailed("HTTP error: \(httpResponse.statusCode)")
        }
        
        guard let transcript = String(data: data, encoding: .utf8),
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ TRANSCRIPTION: Empty or invalid transcript: '\(responseString)'")
            throw AIAnalysisError.transcriptionFailed("Empty or invalid transcript")
        }
        
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🎤 TRANSCRIPTION: Success! Transcript length: \(cleanTranscript.count) characters")
        return cleanTranscript
    }
    
    /// Generates content using OpenAI GPT
    private func generateContentFromTranscript(_ transcript: String) async throws -> VideoAnalysisResult {
        print("🧠 CONTENT GENERATION: Starting with transcript: '\(String(transcript.prefix(50)))...'")
        
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/chat/completions")!
        print("🧠 CONTENT GENERATION: Using URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        // Create content generation request
        let contentRequest = OpenAIContentRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(
                    role: "system",
                    content: "You are a social media content expert for Stitch, a video conversation platform. Based on the video transcript, generate an engaging title, description, and relevant hashtags for a short-form video. The title should be catchy and encourage responses. The description should explain what the video is about and invite discussion. Hashtags should be relevant and trending. Respond only with valid JSON in the exact format: {\"title\": \"string\", \"description\": \"string\", \"hashtags\": [\"tag1\", \"tag2\", \"tag3\"]}"
                ),
                ChatMessage(
                    role: "user",
                    content: "Video transcript: \(transcript)"
                )
            ],
            max_tokens: 500,
            temperature: 0.7,
            response_format: ResponseFormat(type: "json_object")
        )
        
        let requestData = try JSONEncoder().encode(contentRequest)
        request.httpBody = requestData
        
        print("🧠 CONTENT GENERATION: Sending request to OpenAI")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("🧠 CONTENT GENERATION: Received response")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ CONTENT GENERATION: Invalid response type")
            throw AIAnalysisError.contentGenerationFailed("Invalid response type")
        }
        
        print("🧠 CONTENT GENERATION: HTTP status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ CONTENT GENERATION: HTTP error \(httpResponse.statusCode): \(responseString)")
            throw AIAnalysisError.contentGenerationFailed("HTTP error: \(httpResponse.statusCode)")
        }
        
        // Parse OpenAI response
        let responseString = String(data: data, encoding: .utf8) ?? "No response"
        print("🧠 CONTENT GENERATION: Raw response: \(responseString)")
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let choice = openAIResponse.choices.first,
              let contentJSON = choice.message.content.data(using: .utf8) else {
            print("❌ CONTENT GENERATION: Invalid response format - no choices or content")
            throw AIAnalysisError.contentGenerationFailed("Invalid response format")
        }
        
        print("🧠 CONTENT GENERATION: Content JSON: \(choice.message.content)")
        
        // Parse generated content
        let result = try JSONDecoder().decode(VideoAnalysisResult.self, from: contentJSON)
        
        // Validate result
        guard !result.title.isEmpty,
              !result.description.isEmpty,
              !result.hashtags.isEmpty,
              result.title.count <= 100,
              result.description.count <= 300,
              result.hashtags.count <= 10 else {
            print("❌ CONTENT GENERATION: Generated content validation failed")
            print("❌ CONTENT GENERATION: Title: '\(result.title)' (length: \(result.title.count))")
            print("❌ CONTENT GENERATION: Description: '\(result.description)' (length: \(result.description.count))")
            print("❌ CONTENT GENERATION: Hashtags: \(result.hashtags) (count: \(result.hashtags.count))")
            throw AIAnalysisError.contentGenerationFailed("Generated content exceeds limits or is incomplete")
        }
        
        print("🧠 CONTENT GENERATION: Success! Generated valid content")
        return result
    }
    
    // MARK: - Helper Methods
    
    /// Updates analysis progress
    private func updateProgress(_ progress: Double) async {
        await MainActor.run {
            self.analysisProgress = progress
        }
    }
    
    /// Records analysis metrics for performance tracking
    private func recordAnalysisMetrics(duration: TimeInterval, success: Bool, transcriptLength: Int, error: Error?) {
        let metrics = AnalysisMetrics(
            timestamp: Date(),
            duration: duration,
            success: success,
            transcriptLength: transcriptLength,
            error: error?.localizedDescription
        )
        
        analysisHistory.append(metrics)
        
        // Keep only last 100 analyses
        if analysisHistory.count > 100 {
            analysisHistory.removeFirst()
        }
        
        // Update success rate
        let recentSuccesses = analysisHistory.suffix(20).filter { $0.success }.count
        successRate = Double(recentSuccesses) / Double(min(analysisHistory.count, 20)) * 100
        
        print("📊 AI ANALYZER: Metrics - Duration: \(String(format: "%.2f", duration))s, Success: \(success), Success Rate: \(String(format: "%.1f", successRate))%")
    }
    
    /// Clears current error
    func clearError() {
        analysisError = nil
        showingError = false
    }
    
    /// Gets analysis statistics
    func getAnalyticsStats() -> AnalyticsStats {
        let avgDuration = analysisHistory.isEmpty ? 0 : analysisHistory.reduce(0) { $0 + $1.duration } / Double(analysisHistory.count)
        
        return AnalyticsStats(
            totalAnalyses: totalAnalysesPerformed,
            successRate: successRate,
            averageDuration: avgDuration,
            lastAnalysisDate: analysisHistory.last?.timestamp
        )
    }
}

// MARK: - Data Models

/// OpenAI chat completion request
struct OpenAIContentRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let max_tokens: Int
    let temperature: Double
    let response_format: ResponseFormat
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ResponseFormat: Codable {
    let type: String
}

/// OpenAI API response
struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: ChatMessage
    }
}

/// Video analysis result from AI
struct VideoAnalysisResult: Codable {
    let title: String
    let description: String
    let hashtags: [String]
    
    /// Validates the analysis result
    var isValid: Bool {
        return !title.isEmpty &&
               !description.isEmpty &&
               !hashtags.isEmpty &&
               title.count <= 100 &&
               description.count <= 300 &&
               hashtags.count <= 10
    }
}

/// AI analysis error types
enum AIAnalysisError: Error, LocalizedError {
    case configurationError(String)
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case contentGenerationFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration Error: \(message)"
        case .audioExtractionFailed(let message):
            return "Audio Extraction Failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription Failed: \(message)"
        case .contentGenerationFailed(let message):
            return "Content Generation Failed: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
        }
    }
}

/// Analysis performance metrics
struct AnalysisMetrics {
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let transcriptLength: Int
    let error: String?
}

/// Analytics statistics
struct AnalyticsStats {
    let totalAnalyses: Int
    let successRate: Double
    let averageDuration: TimeInterval
    let lastAnalysisDate: Date?
}
