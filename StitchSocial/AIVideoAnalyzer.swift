//
//  AIVideoAnalyzer.swift
//  CleanBeta
//
//  Layer 5: Business Logic - AI Video Content Analysis
//  Dependencies: Layer 4 (Services), Layer 3 (Firebase), Layer 2 (Protocols), Layer 1 (Foundation)
//  OpenAI Whisper + GPT integration for auto-generating video metadata
//  FIXED: Added timeout protection, connection testing, and comprehensive debugging
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
    
    // MARK: - Debug State
    
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastConnectionTest: Date?
    @Published var analysisStepDetails: String = ""
    
    // MARK: - Configuration
    
    private let openAIAPIKey: String
    private let maxRetries = 3
    private let timeoutInterval: TimeInterval = 45.0
    private let connectionTimeoutInterval: TimeInterval = 10.0
    
    // Public access to check if AI is available
    var isAIAvailable: Bool {
        return !openAIAPIKey.isEmpty && !openAIAPIKey.hasPrefix("sk-your-") && connectionStatus == .connected
    }
    
    // MARK: - Analytics
    
    @Published var totalAnalysesPerformed: Int = 0
    @Published var successRate: Double = 100.0
    private var analysisHistory: [AnalysisMetrics] = []
    
    // MARK: - Initialization
    
    init() {
        // Get OpenAI API key from Config
        self.openAIAPIKey = Config.API.OpenAI.apiKey
        
        print("🚨🚨🚨 AI ANALYZER INITIALIZATION 🚨🚨🚨")
        print("📊 API KEY LENGTH: \(openAIAPIKey.count)")
        print("🔑 API KEY PREFIX: \(String(openAIAPIKey.prefix(10)))...")
        print("⚠️ PLACEHOLDER CHECK: hasPrefix('sk-your-') = \(openAIAPIKey.hasPrefix("sk-your-"))")
        
        if openAIAPIKey.isEmpty {
            print("❌ AI ANALYZER: API key is EMPTY")
            connectionStatus = .notConfigured
        } else if openAIAPIKey.hasPrefix("sk-your-") ||
                  openAIAPIKey.hasPrefix("sk-proj-your-") ||
                  openAIAPIKey.contains("YOUR_API_KEY") {
            print("❌ AI ANALYZER: API key is PLACEHOLDER")
            connectionStatus = .notConfigured
        } else if !openAIAPIKey.hasPrefix("sk-") && !openAIAPIKey.hasPrefix("sk-proj-") {
            print("❌ AI ANALYZER: API key has INVALID FORMAT")
            connectionStatus = .notConfigured
        } else {
            print("✅ AI ANALYZER: API key appears valid - testing connection...")
            connectionStatus = .testing
            
            // Test connection on initialization
            Task {
                await testConnection()
            }
        }
    }
    
    // MARK: - Connection Testing
    
    /// Test OpenAI API connection
    func testConnection() async {
        print("🔧 AI ANALYZER: Testing OpenAI connection...")
        
        await MainActor.run {
            connectionStatus = .testing
            lastConnectionTest = Date()
            analysisStepDetails = "Testing OpenAI API connection..."
        }
        
        do {
            let url = URL(string: "\(Config.API.OpenAI.baseURL)/models")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = connectionTimeoutInterval
            
            print("🌐 CONNECTION TEST: Sending request to \(url)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.configurationError("Invalid response type")
            }
            
            print("📡 CONNECTION TEST: HTTP Status \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                await MainActor.run {
                    connectionStatus = .connected
                    analysisStepDetails = "OpenAI API connected successfully"
                }
                print("✅ CONNECTION TEST: OpenAI API is accessible")
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ CONNECTION TEST: HTTP \(httpResponse.statusCode) - \(responseString)")
                
                await MainActor.run {
                    connectionStatus = .error
                    analysisStepDetails = "Connection failed: HTTP \(httpResponse.statusCode)"
                }
            }
            
        } catch {
            print("❌ CONNECTION TEST: Failed - \(error.localizedDescription)")
            
            await MainActor.run {
                connectionStatus = .error
                analysisStepDetails = "Connection error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Analyzes video content and generates title, description, and hashtags
    /// Falls back gracefully when API key is not configured, allowing manual content creation
    /// - Parameter videoURL: Local URL of recorded video
    /// - Returns: VideoAnalysisResult with generated content or nil if API unavailable (user creates own content)
    func analyzeVideo(url videoURL: URL, userID: String) async -> VideoAnalysisResult? {
        print("🚨🚨🚨 ANALYZE VIDEO CALLED 🚨🚨🚨")
        print("👤 USER: \(userID)")
        print("📱 VIDEO: \(videoURL.lastPathComponent)")
        print("🔑 API KEY LENGTH: \(openAIAPIKey.count)")
        print("🔗 CONNECTION STATUS: \(connectionStatus)")
        
        let startTime = Date()
        
        // Enhanced API key validation
        guard !openAIAPIKey.isEmpty else {
            print("❌ API KEY: Empty - returning nil for manual creation")
            await updateDebugStatus("API key not configured - manual mode")
            return nil
        }
        
        guard !openAIAPIKey.hasPrefix("sk-your-") else {
            print("❌ API KEY: Placeholder detected - returning nil for manual creation")
            await updateDebugStatus("API key is placeholder - manual mode")
            return nil
        }
        
        // Check connection status and test if needed
        if connectionStatus != .connected {
            print("❌ CONNECTION: Not connected (\(connectionStatus)) - testing connection...")
            await testConnection()
            
            if connectionStatus != .connected {
                print("❌ CONNECTION: Failed to connect - returning nil for manual creation")
                await updateDebugStatus("Connection failed - manual mode")
                return nil
            }
            
            print("✅ CONNECTION: Established during test - proceeding")
        }
        
        print("✅ VALIDATION: All checks passed - proceeding with AI analysis")
        
        // Use timeout wrapper for the entire analysis process
        return await withTaskGroup(of: VideoAnalysisResult?.self) { group in
            
            // Main analysis task
            group.addTask {
                return await self.performAnalysisWithRetry(url: videoURL, userID: userID, startTime: startTime)
            }
            
            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.timeoutInterval * 1_000_000_000))
                print("⏰ TIMEOUT: Analysis timed out after \(self.timeoutInterval) seconds")
                await self.updateDebugStatus("Analysis timed out - manual mode")
                return nil
            }
            
            // Return first completed result
            for await result in group {
                group.cancelAll()
                return result
            }
            
            return nil
        }
    }
    
    // MARK: - Analysis Implementation
    
    private func performAnalysisWithRetry(url videoURL: URL, userID: String, startTime: Date) async -> VideoAnalysisResult? {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            print("🔄 ATTEMPT \(attempt)/\(maxRetries): Starting analysis attempt")
            
            do {
                let result = try await performAnalysis(url: videoURL, userID: userID, startTime: startTime)
                print("✅ SUCCESS: Analysis completed on attempt \(attempt)")
                return result
                
            } catch {
                lastError = error
                print("❌ ATTEMPT \(attempt) FAILED: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt * 2) // Exponential backoff
                    print("⏳ RETRY: Waiting \(delay) seconds before attempt \(attempt + 1)")
                    await updateDebugStatus("Attempt \(attempt) failed, retrying in \(Int(delay))s...")
                    
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        print("❌ ALL ATTEMPTS FAILED: Final error - \(lastError?.localizedDescription ?? "Unknown")")
        await updateDebugStatus("All attempts failed - manual mode")
        
        await MainActor.run {
            self.isAnalyzing = false
            self.analysisError = lastError as? AIAnalysisError ?? .unknown(lastError?.localizedDescription ?? "Analysis failed")
            self.showingError = false // Don't show error UI, just log and allow manual creation
        }
        
        return nil
    }
    
    private func performAnalysis(url videoURL: URL, userID: String, startTime: Date) async throws -> VideoAnalysisResult {
        await MainActor.run {
            self.isAnalyzing = true
            self.analysisProgress = 0.0
            self.analysisError = nil
        }
        
        do {
            // Step 1: Extract audio from video (25% progress)
            await updateDebugStatus("Extracting audio from video...")
            await updateProgress(0.25)
            let audioData = try await extractAudioFromVideo(videoURL)
            print("🎵 AUDIO: Extracted successfully, size: \(audioData.count) bytes")
            
            // Step 2: Transcribe audio to text (60% progress)
            await updateDebugStatus("Transcribing audio with Whisper...")
            await updateProgress(0.6)
            let transcript = try await transcribeAudio(audioData)
            print("📝 TRANSCRIPT: Generated, length: \(transcript.count) characters")
            print("📝 PREVIEW: '\(String(transcript.prefix(100)))...'")
            
            // Step 3: Generate content using GPT (90% progress)
            await updateDebugStatus("Generating content with GPT...")
            await updateProgress(0.9)
            let result = try await generateContentFromTranscript(transcript)
            print("🎯 CONTENT: Generated successfully")
            print("🎯 TITLE: '\(result.title)'")
            print("🎯 DESCRIPTION: '\(result.description)'")
            print("🎯 HASHTAGS: \(result.hashtags)")
            
            // Step 4: Complete analysis (100% progress)
            await updateDebugStatus("Analysis complete!")
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
            
            print("🎉 SUCCESS: Video analysis completed in \(Date().timeIntervalSince(startTime).formatted())s")
            return result
            
        } catch {
            print("💥 ANALYSIS ERROR: \(error)")
            print("💥 ERROR TYPE: \(type(of: error))")
            print("💥 DESCRIPTION: \(error.localizedDescription)")
            
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisError = error as? AIAnalysisError ?? .unknown(error.localizedDescription)
            }
            
            // Record failed analysis
            recordAnalysisMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: false,
                transcriptLength: 0,
                error: error
            )
            
            throw error
        }
    }
    
    // MARK: - Audio Processing
    
    /// Extracts audio track from video for transcription
    private func extractAudioFromVideo(_ videoURL: URL) async throws -> Data {
        print("🎵 AUDIO EXTRACTION: Starting for \(videoURL.lastPathComponent)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let asset = AVAsset(url: videoURL)
                    let preset = AVAssetExportPresetAppleM4A
                    
                    guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                        print("❌ AUDIO EXTRACTION: Failed to create export session")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to create export session"))
                        return
                    }
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                    
                    exportSession.outputURL = tempURL
                    exportSession.outputFileType = .m4a
                    
                    print("🎵 AUDIO EXTRACTION: Starting export to \(tempURL.lastPathComponent)")
                    
                    await exportSession.export()
                    
                    switch exportSession.status {
                    case .completed:
                        print("🎵 AUDIO EXTRACTION: Export completed successfully")
                        
                        do {
                            let audioData = try Data(contentsOf: tempURL)
                            try? FileManager.default.removeItem(at: tempURL)
                            print("🎵 AUDIO EXTRACTION: Data loaded, size: \(audioData.count) bytes")
                            continuation.resume(returning: audioData)
                        } catch {
                            print("❌ AUDIO EXTRACTION: Failed to read audio data: \(error)")
                            continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to read audio data"))
                        }
                        
                    case .failed:
                        let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
                        print("❌ AUDIO EXTRACTION: Export failed: \(errorMessage)")
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Export failed: \(errorMessage)"))
                        
                    default:
                        print("❌ AUDIO EXTRACTION: Unexpected status: \(exportSession.status.rawValue)")
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
        print("🎤 TRANSCRIPTION: Starting with \(audioData.count) bytes")
        
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/audio/transcriptions")!
        print("🎤 URL: \(url)")
        
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
        
        print("🎤 TRANSCRIPTION: Sending request, body size: \(body.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("🎤 TRANSCRIPTION: Response received")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.transcriptionFailed("Invalid response type")
        }
        
        print("🎤 HTTP STATUS: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ TRANSCRIPTION ERROR: HTTP \(httpResponse.statusCode) - \(responseString)")
            throw AIAnalysisError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(responseString)")
        }
        
        guard let transcript = String(data: data, encoding: .utf8),
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ TRANSCRIPTION: Empty transcript - \(responseString)")
            throw AIAnalysisError.transcriptionFailed("Empty transcript")
        }
        
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ TRANSCRIPTION SUCCESS: \(cleanTranscript.count) characters")
        return cleanTranscript
    }
    
    /// Generates content using OpenAI GPT
    private func generateContentFromTranscript(_ transcript: String) async throws -> VideoAnalysisResult {
        print("🧠 CONTENT GENERATION: Starting with transcript (\(transcript.count) chars)")
        print("🧠 PREVIEW: '\(String(transcript.prefix(50)))...'")
        
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/chat/completions")!
        print("🧠 URL: \(url)")
        
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
        
        print("🧠 CONTENT GENERATION: Sending request to GPT")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("🧠 CONTENT GENERATION: Response received")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.contentGenerationFailed("Invalid response type")
        }
        
        print("🧠 HTTP STATUS: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ CONTENT ERROR: HTTP \(httpResponse.statusCode) - \(responseString)")
            throw AIAnalysisError.contentGenerationFailed("HTTP \(httpResponse.statusCode): \(responseString)")
        }
        
        // Parse OpenAI response
        let responseString = String(data: data, encoding: .utf8) ?? "No response"
        print("🧠 RAW RESPONSE: \(responseString)")
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let choice = openAIResponse.choices.first,
              let contentJSON = choice.message.content.data(using: .utf8) else {
            print("❌ CONTENT: Invalid response format")
            throw AIAnalysisError.contentGenerationFailed("Invalid response format")
        }
        
        print("🧠 CONTENT JSON: \(choice.message.content)")
        
        // Parse generated content
        let result = try JSONDecoder().decode(VideoAnalysisResult.self, from: contentJSON)
        
        // Validate result
        guard !result.title.isEmpty,
              !result.description.isEmpty,
              !result.hashtags.isEmpty,
              result.title.count <= 100,
              result.description.count <= 300,
              result.hashtags.count <= 10 else {
            print("❌ VALIDATION FAILED:")
            print("   Title: '\(result.title)' (\(result.title.count) chars)")
            print("   Description: '\(result.description)' (\(result.description.count) chars)")
            print("   Hashtags: \(result.hashtags) (\(result.hashtags.count) tags)")
            throw AIAnalysisError.contentGenerationFailed("Generated content validation failed")
        }
        
        print("✅ CONTENT SUCCESS: Valid content generated")
        return result
    }
    
    // MARK: - Helper Methods
    
    /// Updates analysis progress
    private func updateProgress(_ progress: Double) async {
        await MainActor.run {
            self.analysisProgress = progress
        }
    }
    
    /// Updates debug status message
    private func updateDebugStatus(_ message: String) async {
        await MainActor.run {
            self.analysisStepDetails = message
        }
        print("📊 DEBUG: \(message)")
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
        
        // Keep only last 50 metrics
        if analysisHistory.count > 50 {
            analysisHistory.removeFirst()
        }
        
        // Update success rate
        let recentSuccesses = analysisHistory.filter { $0.success }.count
        successRate = Double(recentSuccesses) / Double(analysisHistory.count) * 100.0
        
        print("📊 METRICS: Duration: \(duration.formatted())s, Success: \(success), Rate: \(successRate.formatted())%")
    }
    
    /// Get analytics statistics
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

/// Connection status for debugging
enum ConnectionStatus: String, CaseIterable {
    case unknown = "unknown"
    case notConfigured = "notConfigured"
    case testing = "testing"
    case connected = "connected"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .notConfigured: return "Not Configured"
        case .testing: return "Testing..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
    
    var color: String {
        switch self {
        case .unknown: return "gray"
        case .notConfigured: return "orange"
        case .testing: return "blue"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

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
