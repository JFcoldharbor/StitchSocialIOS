//
//  AIVideoAnalyzer.swift
//  StitchSocial
//
//  Layer 5: Business Logic - AI Video Content Analysis
//  Dependencies: Layer 4 (Services), Layer 3 (Firebase), Layer 2 (Protocols), Layer 1 (Foundation)
//  OpenAI Whisper + GPT integration for auto-generating video metadata
//
//  OPTIMIZED: Connection test cached per session (5 min TTL) — saves 1 API call per video
//  OPTIMIZED: AI results cached by video URL — prevents duplicate Whisper+GPT calls on re-open
//  OPTIMIZED: Singleton pattern — no more throwaway instances in ThreadComposer
//  UPDATED: Uses OpenAI dashboard tone-matching prompt (Stitch Dynamic)
//

import Foundation
import AVFoundation

/// OpenAI speech-to-text video analysis for auto-generating titles, descriptions, and hashtags
/// Premium feature that provides seamless content creation assistance with manual fallback
@MainActor
class AIVideoAnalyzer: ObservableObject {
    
    // MARK: - Singleton (prevents multiple instances + duplicate connection tests)
    
    static let shared = AIVideoAnalyzer()
    
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
    
    // MARK: - Caching: Connection test TTL (5 minutes)
    // Saves 1 API call per video — connection test result reused within TTL window
    
    private let connectionTestTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Caching: AI results by video URL
    // Prevents duplicate Whisper ($) + GPT ($) calls if user cancels and re-opens composer
    
    private var aiResultCache: [String: CachedAIResult] = [:]
    private let aiResultCacheTTL: TimeInterval = 600 // 10 minutes
    private let maxCachedResults = 10
    
    // Public access to check if AI is available
    var isAIAvailable: Bool {
        return !openAIAPIKey.isEmpty && !openAIAPIKey.hasPrefix("sk-your-") && connectionStatus == .connected
    }
    
    // MARK: - Analytics
    
    @Published var totalAnalysesPerformed: Int = 0
    @Published var successRate: Double = 100.0
    private var analysisHistory: [AnalysisMetrics] = []
    
    // MARK: - Initialization
    
    private init() {
        // Get OpenAI API key from Secrets.plist via Secrets.swift
        self.openAIAPIKey = Secrets.openAIKey
        
        print("🧠 AI ANALYZER: Initialized (singleton)")
        print("📊 API KEY LENGTH: \(openAIAPIKey.count)")
        
        if openAIAPIKey.isEmpty {
            print("❌ AI ANALYZER: API key is EMPTY — check Secrets.plist")
            connectionStatus = .notConfigured
        } else if openAIAPIKey.hasPrefix("sk-your-") ||
                  openAIAPIKey.hasPrefix("sk-proj-your-") ||
                  openAIAPIKey.contains("YOUR_API_KEY") ||
                  openAIAPIKey.contains("PASTE_YOUR") {
            print("❌ AI ANALYZER: API key is PLACEHOLDER")
            connectionStatus = .notConfigured
        } else if !openAIAPIKey.hasPrefix("sk-") && !openAIAPIKey.hasPrefix("sk-proj-") {
            print("❌ AI ANALYZER: API key has INVALID FORMAT")
            connectionStatus = .notConfigured
        } else {
            print("✅ AI ANALYZER: API key loaded from Secrets.plist")
            connectionStatus = .testing
            Task {
                await testConnection()
            }
        }
    }
    
    // MARK: - Connection Testing (CACHED — 5 min TTL)
    
    /// Test OpenAI API connection. Reuses cached result within TTL to avoid wasted calls.
    func testConnection() async {
        // Check if cached connection test is still valid
        if let lastTest = lastConnectionTest,
           Date().timeIntervalSince(lastTest) < connectionTestTTL,
           connectionStatus == .connected {
            print("✅ CONNECTION: Using cached result (TTL: \(Int(connectionTestTTL - Date().timeIntervalSince(lastTest)))s remaining)")
            return
        }
        
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIAnalysisError.configurationError("Invalid response type")
            }
            
            if httpResponse.statusCode == 200 {
                await MainActor.run {
                    connectionStatus = .connected
                    analysisStepDetails = "OpenAI API connected"
                }
                print("✅ CONNECTION: OpenAI API accessible (cached for \(Int(connectionTestTTL))s)")
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ CONNECTION: HTTP \(httpResponse.statusCode) - \(responseString)")
                await MainActor.run {
                    connectionStatus = .error
                    analysisStepDetails = "Connection failed: HTTP \(httpResponse.statusCode)"
                }
            }
            
        } catch {
            print("❌ CONNECTION: Failed - \(error.localizedDescription)")
            await MainActor.run {
                connectionStatus = .error
                analysisStepDetails = "Connection error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - AI Result Cache Management
    
    /// Check cache before calling Whisper + GPT (saves $$ on re-opens)
    private func getCachedResult(for videoURL: URL) -> VideoAnalysisResult? {
        let key = videoURL.lastPathComponent
        guard let cached = aiResultCache[key],
              Date().timeIntervalSince(cached.cachedAt) < aiResultCacheTTL else {
            return nil
        }
        print("💾 AI CACHE HIT: Reusing result for \(key) — saved 2 API calls")
        return cached.result
    }
    
    /// Store result in cache after successful analysis
    private func cacheResult(_ result: VideoAnalysisResult, for videoURL: URL) {
        let key = videoURL.lastPathComponent
        aiResultCache[key] = CachedAIResult(result: result, cachedAt: Date())
        
        // LRU eviction if over limit
        if aiResultCache.count > maxCachedResults {
            let oldest = aiResultCache.min { $0.value.cachedAt < $1.value.cachedAt }
            if let oldestKey = oldest?.key {
                aiResultCache.removeValue(forKey: oldestKey)
            }
        }
        print("💾 AI CACHE: Stored result for \(key) (\(aiResultCache.count)/\(maxCachedResults))")
    }
    
    /// Clear expired AI result cache entries
    func cleanupAICache() {
        let before = aiResultCache.count
        aiResultCache = aiResultCache.filter {
            Date().timeIntervalSince($0.value.cachedAt) < aiResultCacheTTL
        }
        let removed = before - aiResultCache.count
        if removed > 0 {
            print("💾 AI CACHE: Cleaned \(removed) expired entries")
        }
    }
    
    // MARK: - Public Interface
    
    /// Analyzes video content and generates title, description, and hashtags
    /// Checks cache first to avoid duplicate API calls on re-opens
    func analyzeVideo(url videoURL: URL, userID: String) async -> VideoAnalysisResult? {
        
        // CHECK CACHE FIRST — avoids Whisper + GPT calls if already analyzed
        if let cached = getCachedResult(for: videoURL) {
            await MainActor.run {
                self.lastAnalysisResult = cached
            }
            return cached
        }
        
        let startTime = Date()
        
        // API key validation
        guard !openAIAPIKey.isEmpty else {
            await updateDebugStatus("API key not configured - manual mode")
            return nil
        }
        
        guard !openAIAPIKey.hasPrefix("sk-your-") else {
            await updateDebugStatus("API key is placeholder - manual mode")
            return nil
        }
        
        // Check connection (uses cached result within TTL)
        if connectionStatus != .connected {
            await testConnection()
            if connectionStatus != .connected {
                await updateDebugStatus("Connection failed - manual mode")
                return nil
            }
        }
        
        // Run analysis with retry
        let result = await withTaskGroup(of: VideoAnalysisResult?.self) { group in
            
            group.addTask {
                return await self.performAnalysisWithRetry(url: videoURL, userID: userID, startTime: startTime)
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.timeoutInterval * 1_000_000_000))
                await self.updateDebugStatus("Analysis timed out - manual mode")
                return nil
            }
            
            for await result in group {
                group.cancelAll()
                return result
            }
            
            return nil
        }
        
        // CACHE successful result
        if let result = result {
            cacheResult(result, for: videoURL)
        }
        
        return result
    }
    
    // MARK: - Pre-extracted Audio Analysis (No Double Extraction)
    
    /// Analyzes video using pre-extracted audio data
    func analyzeWithExtractedAudio(audioData: Data, videoURL: URL? = nil, userID: String) async -> VideoAnalysisResult? {
        
        // Check cache if videoURL provided
        if let videoURL = videoURL, let cached = getCachedResult(for: videoURL) {
            await MainActor.run { self.lastAnalysisResult = cached }
            return cached
        }
        
        let startTime = Date()
        
        guard !openAIAPIKey.isEmpty, !openAIAPIKey.hasPrefix("sk-your-") else {
            return nil
        }
        
        if connectionStatus != .connected {
            await testConnection()
            if connectionStatus != .connected { return nil }
        }
        
        let result = await withTaskGroup(of: VideoAnalysisResult?.self) { group in
            
            group.addTask {
                return await self.performAnalysisWithExtractedAudio(audioData: audioData, userID: userID, startTime: startTime)
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.timeoutInterval * 1_000_000_000))
                return nil
            }
            
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
        
        // Cache if we have a URL key
        if let result = result, let videoURL = videoURL {
            cacheResult(result, for: videoURL)
        }
        
        return result
    }
    
    // MARK: - Analysis Implementation
    
    private func performAnalysisWithRetry(url videoURL: URL, userID: String, startTime: Date) async -> VideoAnalysisResult? {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let result = try await performAnalysis(url: videoURL, userID: userID, startTime: startTime)
                return result
            } catch {
                lastError = error
                print("❌ ATTEMPT \(attempt) FAILED: \(error.localizedDescription)")
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt * 2)
                    await updateDebugStatus("Attempt \(attempt) failed, retrying in \(Int(delay))s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        await MainActor.run {
            self.isAnalyzing = false
            self.analysisError = lastError as? AIAnalysisError ?? .unknown(lastError?.localizedDescription ?? "Analysis failed")
            self.showingError = false
        }
        
        return nil
    }
    
    private func performAnalysisWithExtractedAudio(audioData: Data, userID: String, startTime: Date) async -> VideoAnalysisResult? {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let result = try await performAnalysisFromAudioData(audioData: audioData, userID: userID, startTime: startTime)
                return result
            } catch {
                lastError = error
                print("❌ ATTEMPT \(attempt) FAILED: \(error.localizedDescription)")
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt * 2)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        await MainActor.run {
            self.isAnalyzing = false
            self.analysisError = lastError as? AIAnalysisError ?? .unknown(lastError?.localizedDescription ?? "Analysis failed")
            self.showingError = false
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
            // Step 1: Extract audio (25%)
            await updateDebugStatus("Extracting audio from video...")
            await updateProgress(0.25)
            let audioData = try await extractAudioFromVideo(videoURL)
            
            // Step 2: Transcribe with Whisper (60%)
            await updateDebugStatus("Transcribing audio with Whisper...")
            await updateProgress(0.6)
            let transcript = try await transcribeAudio(audioData)
            
            // Step 3: Generate content with GPT (90%)
            await updateDebugStatus("Generating content with GPT...")
            await updateProgress(0.9)
            let result = try await generateContentFromTranscript(transcript)
            
            // Step 4: Complete (100%)
            await updateProgress(1.0)
            
            await MainActor.run {
                self.lastAnalysisResult = result
                self.isAnalyzing = false
                self.totalAnalysesPerformed += 1
            }
            
            recordAnalysisMetrics(duration: Date().timeIntervalSince(startTime), success: true, transcriptLength: transcript.count, error: nil)
            return result
            
        } catch {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisError = error as? AIAnalysisError ?? .unknown(error.localizedDescription)
            }
            recordAnalysisMetrics(duration: Date().timeIntervalSince(startTime), success: false, transcriptLength: 0, error: error)
            throw error
        }
    }
    
    private func performAnalysisFromAudioData(audioData: Data, userID: String, startTime: Date) async throws -> VideoAnalysisResult {
        await MainActor.run {
            self.isAnalyzing = true
            self.analysisProgress = 0.0
            self.analysisError = nil
        }
        
        do {
            await updateProgress(0.25)
            
            // Step 2: Transcribe (60%)
            await updateDebugStatus("Transcribing audio with Whisper...")
            await updateProgress(0.6)
            let transcript = try await transcribeAudio(audioData)
            
            // Step 3: Generate content (90%)
            await updateDebugStatus("Generating content with GPT...")
            await updateProgress(0.9)
            let result = try await generateContentFromTranscript(transcript)
            
            await updateProgress(1.0)
            
            await MainActor.run {
                self.lastAnalysisResult = result
                self.isAnalyzing = false
                self.totalAnalysesPerformed += 1
            }
            
            recordAnalysisMetrics(duration: Date().timeIntervalSince(startTime), success: true, transcriptLength: transcript.count, error: nil)
            return result
            
        } catch {
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisError = error as? AIAnalysisError ?? .unknown(error.localizedDescription)
            }
            recordAnalysisMetrics(duration: Date().timeIntervalSince(startTime), success: false, transcriptLength: 0, error: error)
            throw error
        }
    }
    
    // MARK: - Audio Processing
    
    private func extractAudioFromVideo(_ videoURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let asset = AVAsset(url: videoURL)
                    let preset = AVAssetExportPresetAppleM4A
                    
                    guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to create export session"))
                        return
                    }
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                    
                    exportSession.outputURL = tempURL
                    exportSession.outputFileType = .m4a
                    
                    await exportSession.export()
                    
                    switch exportSession.status {
                    case .completed:
                        do {
                            let audioData = try Data(contentsOf: tempURL)
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(returning: audioData)
                        } catch {
                            continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Failed to read audio data"))
                        }
                        
                    case .failed:
                        let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Export failed: \(errorMessage)"))
                        
                    default:
                        continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Unexpected export status"))
                    }
                    
                } catch {
                    continuation.resume(throwing: AIAnalysisError.audioExtractionFailed("Audio extraction failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    // MARK: - Whisper Transcription
    
    private func transcribeAudio(_ audioData: Data) async throws -> String {
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/audio/transcriptions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutInterval
        
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.transcriptionFailed("Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            throw AIAnalysisError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(responseString)")
        }
        
        guard let transcript = String(data: data, encoding: .utf8),
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAnalysisError.transcriptionFailed("Empty transcript")
        }
        
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - GPT Content Generation (UPDATED: Stitch Dynamic tone-matching prompt)
    
    private func generateContentFromTranscript(_ transcript: String) async throws -> VideoAnalysisResult {
        let url = URL(string: "\(Config.API.OpenAI.baseURL)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        // UPDATED: Uses the Stitch Dynamic prompt from OpenAI dashboard
        let systemPrompt = """
        You are a social media assistant that adapts your tone based on the speaker's personality and dialect.

        You will receive a transcript and visual tags. Based on the transcript, infer the speaker's tone and personality. Choose from:
        - Urban Hype (bold, slang-heavy, energetic)
        - Motivational Coach (uplifting, powerful, inspiring)
        - Gen Z Trendsetter (casual, funny, trendy)
        - Chill Vibes (laid-back, poetic, smooth)
        - Comedy Vibes (funny, relatable, viral)
        - Fashionista (stylish, confident, aesthetic)
        - Neutral (professional, clear, informative)

        Then generate a JSON response:
        {
          "title": "short, tone-matching title (under 60 chars)",
          "description": "caption in the speaker's tone",
          "hashtags": ["relevant", "tone-matching", "hashtags"],
          "confidence": 0.95
        }

        Use the following style examples as tone anchors:
        - Urban Hype: "This fit is SENDING me 🔥💯 No cap, I understood the assignment fr"
        - Motivational Coach: "Your mindset determines your success! Keep grinding 💪✨"
        - Gen Z Trendsetter: "Not me absolutely serving looks today bestie ✨"
        - Chill Vibes: "Just embracing the soft life today 🌺"
        - Comedy Vibes: "POV: You thought you looked cute but the camera said 'try again' 😭💀"
        - Fashionista: "The way this outfit is absolutely eating... I know y'all see the vision 💅✨"
        """
        
        let contentRequest = OpenAIContentRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: "Video transcript: \(transcript)")
            ],
            max_tokens: 300,
            temperature: 0.7,
            response_format: ResponseFormat(type: "json_object")
        )
        
        let requestData = try JSONEncoder().encode(contentRequest)
        request.httpBody = requestData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAnalysisError.contentGenerationFailed("Invalid response type")
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            throw AIAnalysisError.contentGenerationFailed("HTTP \(httpResponse.statusCode): \(responseString)")
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let choice = openAIResponse.choices.first,
              let contentJSON = choice.message.content.data(using: .utf8) else {
            throw AIAnalysisError.contentGenerationFailed("Invalid response format")
        }
        
        let result = try JSONDecoder().decode(VideoAnalysisResult.self, from: contentJSON)
        
        guard !result.title.isEmpty,
              !result.description.isEmpty,
              !result.hashtags.isEmpty,
              result.title.count <= 100,
              result.description.count <= 300,
              result.hashtags.count <= 10 else {
            throw AIAnalysisError.contentGenerationFailed("Generated content validation failed")
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private func updateProgress(_ progress: Double) async {
        await MainActor.run { self.analysisProgress = progress }
    }
    
    private func updateDebugStatus(_ message: String) async {
        await MainActor.run { self.analysisStepDetails = message }
    }
    
    private func recordAnalysisMetrics(duration: TimeInterval, success: Bool, transcriptLength: Int, error: Error?) {
        let metrics = AnalysisMetrics(
            timestamp: Date(),
            duration: duration,
            success: success,
            transcriptLength: transcriptLength,
            error: error?.localizedDescription
        )
        
        analysisHistory.append(metrics)
        
        // Keep only last 50
        if analysisHistory.count > 50 {
            analysisHistory.removeFirst()
        }
        
        let recentSuccesses = analysisHistory.filter { $0.success }.count
        successRate = Double(recentSuccesses) / Double(analysisHistory.count) * 100.0
    }
    
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

// MARK: - Cached AI Result

struct CachedAIResult {
    let result: VideoAnalysisResult
    let cachedAt: Date
}

// MARK: - Data Models

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

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: ChatMessage
    }
}

struct VideoAnalysisResult: Codable {
    let title: String
    let description: String
    let hashtags: [String]
    
    var isValid: Bool {
        return !title.isEmpty &&
               !description.isEmpty &&
               !hashtags.isEmpty &&
               title.count <= 100 &&
               description.count <= 300 &&
               hashtags.count <= 10
    }
}

enum AIAnalysisError: Error, LocalizedError {
    case configurationError(String)
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case contentGenerationFailed(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .configurationError(let message): return "Configuration Error: \(message)"
        case .audioExtractionFailed(let message): return "Audio Extraction Failed: \(message)"
        case .transcriptionFailed(let message): return "Transcription Failed: \(message)"
        case .contentGenerationFailed(let message): return "Content Generation Failed: \(message)"
        case .unknown(let message): return "Unknown Error: \(message)"
        }
    }
}

struct AnalysisMetrics {
    let timestamp: Date
    let duration: TimeInterval
    let success: Bool
    let transcriptLength: Int
    let error: String?
}

struct AnalyticsStats {
    let totalAnalyses: Int
    let successRate: Double
    let averageDuration: TimeInterval
    let lastAnalysisDate: Date?
}
