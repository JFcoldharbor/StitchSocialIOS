//
//  AIProcessingOverlay.swift
//  CleanBeta
//
//  Created by James Garmon on 8/10/25.
//
import SwiftUI
import Foundation
import AVFoundation
import FirebaseStorage
import UIKit
// MARK: - Thread Composer Plugin for RecordingView.swift

// MARK: - AI Processing Overlay

struct AIProcessingOverlay: View {
    let videoURL: URL
    let recordingContext: RecordingContext
    @StateObject private var aiAnalyzer = AIVideoAnalyzer()
    @StateObject private var videoProcessor = VideoProcessingService()
    @State private var processingProgress: Double = 0.0
    @State private var currentTask = "Preparing analysis..."
    @State private var isComplete = false
    
    let onAnalysisComplete: (VideoAnalysisResult?) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    StitchColors.primary.opacity(0.3),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                // Animated particles
                ForEach(0..<20, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 2...6))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                        .animation(
                            Animation.linear(duration: Double.random(in: 8...12))
                                .repeatForever(autoreverses: false),
                            value: isComplete
                        )
                }
            )
            
            VStack(spacing: 40) {
                Spacer()
                
                // AI Icon with glassmorphism
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(.ultraThinMaterial, in: Circle())
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0.2),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.8), radius: 3)
                }
                .scaleEffect(isComplete ? 1.1 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isComplete
                )
                
                // Processing text
                VStack(spacing: 16) {
                    Text("AI Analysis")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(currentTask)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Progress circle
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: processingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [StitchColors.primary, StitchColors.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: processingProgress)
                    
                    Text("\(Int(processingProgress * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Cancel button
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.white.opacity(0.1))
                        .background(.ultraThinMaterial)
                )
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            Task {
                await performAIAnalysis()
            }
        }
    }
    
    private func performAIAnalysis() async {
        guard let currentUser = AuthService().currentUser else {
            await MainActor.run {
                onAnalysisComplete(nil)
            }
            return
        }
        
        // Step 1: Video quality analysis (0-40%)
        await MainActor.run {
            currentTask = "Analyzing video quality..."
            processingProgress = 0.1
        }
        
        do {
            let qualityAnalysis = try await videoProcessor.analyzeVideoQuality(videoURL: videoURL)
            
            await MainActor.run {
                processingProgress = 0.4
                if qualityAnalysis.qualityScores.overall < 60 {
                    currentTask = "Video quality: \(Int(qualityAnalysis.qualityScores.overall))% - Processing..."
                } else {
                    currentTask = "High quality video detected - Processing..."
                }
            }
            
            print("📊 PROCESSING: Video quality score: \(qualityAnalysis.qualityScores.overall)%")
            
        } catch {
            print("⚠️ PROCESSING: Quality analysis failed - \(error.localizedDescription) - continuing with AI analysis")
            await MainActor.run {
                processingProgress = 0.4
                currentTask = "Processing video content..."
            }
        }
        
        // Small delay for UI feedback
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Step 2: AI content analysis (40-100%)
        await MainActor.run {
            currentTask = "Extracting audio..."
            processingProgress = 0.5
        }
        
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        await MainActor.run {
            currentTask = "Transcribing speech..."
            processingProgress = 0.7
        }
        
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        await MainActor.run {
            currentTask = "Generating content..."
            processingProgress = 0.9
        }
        
        // Perform actual AI analysis
        let result = await aiAnalyzer.analyzeVideo(url: videoURL, userID: currentUser.id)
        
        await MainActor.run {
            processingProgress = 1.0
            currentTask = "Complete!"
            isComplete = true
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            onAnalysisComplete(result)
        }
    }
}

// MARK: - Thread Composer

struct ThreadComposer: View {
    
    // MARK: - Core Properties
    let recordedVideoURL: URL
    let recordingContext: RecordingContext
    let aiResult: VideoAnalysisResult?
    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void
    
    // MARK: - State
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtags: Set<String> = []
    @State private var uploadState: UploadState = .ready
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var videoDuration: TimeInterval = 0
    @State private var videoFileSize: Int64 = 0
    
    // MARK: - Services
    @StateObject private var videoService = VideoService()
    @StateObject private var authService = AuthService()
    @StateObject private var uploadService = VideoUploadService()
    
    // MARK: - Configuration
    private let maxTitleLength = 100
    private let maxDescriptionLength = 300
    private let maxHashtags = 5
    
    // MARK: - Initialization
    init(
        recordedVideoURL: URL,
        recordingContext: RecordingContext,
        aiResult: VideoAnalysisResult?,
        onVideoCreated: @escaping (CoreVideoMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.recordedVideoURL = recordedVideoURL
        self.recordingContext = recordingContext
        self.aiResult = aiResult
        self.onVideoCreated = onVideoCreated
        self.onCancel = onCancel
        
        // Initialize with AI results
        if let result = aiResult {
            self._title = State(initialValue: result.title)
            self._description = State(initialValue: result.description)
            self._hashtags = State(initialValue: Set(result.hashtags))
        }
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                if uploadState.isUploading {
                    uploadOverlay
                } else {
                    mainContent
                }
                
                // Upload success alert replacement
                if uploadState.isComplete {
                    successOverlay
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear(perform: setup)
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Video preview
                videoPreviewSection
                
                // Content form
                contentFormSection
                
                // Hashtags
                hashtagSection
                
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
        }
        .disabled(uploadState.isUploading)
        .overlay(alignment: .bottom) {
            bottomActions
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(getContextTitle())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text(getContextSubtitle())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .disabled(uploadState.isUploading)
        }
        .padding(.top, 60)
    }
    
    // MARK: - Video Preview Section
    private var videoPreviewSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Video Preview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDuration(videoDuration))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(formatFileSize(videoFileSize))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(9/16, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: recordedVideoURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            VStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("Video Preview")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
            }
        }
    }
    
    // MARK: - Content Form Section
    private var contentFormSection: some View {
        VStack(spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Title")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(title.count)/\(maxTitleLength)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(title.count > maxTitleLength ? .red : .white.opacity(0.6))
                }
                
                TextField(getTitlePlaceholder(), text: $title)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .accentColor(.cyan)
                
                // AI suggestions
                if let aiResult = aiResult {
                    aiSuggestionsView(aiResult)
                }
            }
            
            // Description
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Description (Optional)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(description.count)/\(maxDescriptionLength)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(description.count > maxDescriptionLength ? .red : .white.opacity(0.6))
                }
                
                TextField(getDescriptionPlaceholder(), text: $description, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .lineLimit(3...6)
                    .accentColor(.cyan)
            }
        }
    }
    
    // MARK: - AI Suggestions View
    private func aiSuggestionsView(_ result: VideoAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✨ AI Suggestions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(StitchColors.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Alternative titles
                    let suggestions = [
                        result.title,
                        "\(result.title) 🔥",
                        "\(result.title) - What do you think?"
                    ]
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        if suggestion != title {
                            Button(suggestion) {
                                title = suggestion
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(StitchColors.primary.opacity(0.3))
                            )
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
    
    // MARK: - Hashtag Section
    private var hashtagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hashtags")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(hashtags.count)/\(maxHashtags)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(hashtags.count > maxHashtags ? .red : .white.opacity(0.6))
            }
            
            // Selected hashtags
            if !hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(hashtags).sorted(), id: \.self) { hashtag in
                            Button(action: {
                                hashtags.remove(hashtag)
                            }) {
                                HStack(spacing: 6) {
                                    Text("#\(hashtag)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.cyan.opacity(0.8))
                                )
                            }
                            .disabled(uploadState.isUploading)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            
            // Available hashtags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(getAvailableHashtags(), id: \.self) { hashtag in
                        Button(action: {
                            hashtags.insert(hashtag)
                        }) {
                            Text("#\(hashtag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        .disabled(hashtags.count >= maxHashtags || uploadState.isUploading)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
    
    // MARK: - Upload Overlay
    private var uploadOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Creating \(getContextActionText())...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                if uploadState.progressValue > 0 {
                    ProgressView(value: uploadService.uploadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .frame(width: 200)
                    
                    Text("\(Int(uploadService.uploadProgress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(uploadService.currentTask)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
    
    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("\(getContextActionText()) Created!")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Your content is now live")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                
                Button("Done") {
                    onCancel() // This will dismiss back to main
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(StitchColors.primary)
                )
            }
        }
    }
    
    // MARK: - Bottom Actions
    private var bottomActions: some View {
        VStack {
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                .disabled(uploadState.isUploading)
                
                Button(getActionButtonText()) {
                    Task {
                        await uploadVideo()
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            canPost ?
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                        )
                )
                .disabled(!canPost || uploadState.isUploading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Upload State
    enum UploadState {
        case ready
        case uploading(progress: Double)
        case complete
        case failed(Error)
        
        var isUploading: Bool {
            if case .uploading = self { return true }
            return false
        }
        
        var isComplete: Bool {
            if case .complete = self { return true }
            return false
        }
        
        var progressValue: Double {
            if case .uploading(let progress) = self { return progress }
            return 0.0
        }
    }
    
    // MARK: - Helper Properties & Methods
    
    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hashtags.isEmpty &&
        title.count <= maxTitleLength &&
        description.count <= maxDescriptionLength &&
        hashtags.count <= maxHashtags &&
        videoDuration > 0 &&
        !uploadState.isUploading
    }
    
    private func setup() {
        analyzeVideoMetadata()
    }
    
    private func analyzeVideoMetadata() {
        Task {
            do {
                let asset = AVAsset(url: recordedVideoURL)
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                
                // Get file size
                let resourceValues = try recordedVideoURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resourceValues.fileSize ?? 0)
                
                await MainActor.run {
                    videoDuration = seconds
                    videoFileSize = fileSize
                }
            } catch {
                print("Error analyzing video: \(error)")
            }
        }
    }
    
    private func uploadVideo() async {
        guard let currentUser = authService.currentUser else {
            return
        }
        
        uploadState = .uploading(progress: 0.1)
        
        do {
            // Create upload metadata
            let metadata = VideoUploadMetadata(
                title: title,
                description: description,
                hashtags: Array(hashtags),
                creatorID: currentUser.id,
                creatorName: currentUser.displayName
            )
            
            // Use VideoUploadService for clean upload handling
            let uploadResult = try await uploadService.uploadVideo(
                videoURL: recordedVideoURL,
                metadata: metadata,
                recordingContext: recordingContext
            )
            
            // Track upload progress from service
            uploadState = .uploading(progress: uploadService.uploadProgress)
            
            // Create video document using service
            let createdVideo = try await uploadService.createVideoDocument(
                uploadResult: uploadResult,
                metadata: metadata,
                recordingContext: recordingContext,
                videoService: videoService
            )
            
            uploadState = .uploading(progress: 1.0)
            
            // Brief delay then show success
            try? await Task.sleep(nanoseconds: 500_000_000)
            uploadState = .complete
            
            onVideoCreated(createdVideo)
            
        } catch {
            uploadState = .failed(error)
            print("❌ UPLOAD: Failed - \(error.localizedDescription)")
        }
    }
    
    // Include upload helper methods from RecordingView
    private func uploadVideoToStorage(videoData: Data) async throws -> String {
        let videoID = UUID().uuidString
        let storageRef = Storage.storage().reference().child("videos/\(videoID).mp4")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        let _ = try await storageRef.putDataAsync(videoData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
    }
    
    private func uploadThumbnailToStorage(thumbnailData: Data) async throws -> String {
        let thumbnailID = UUID().uuidString
        let storageRef = Storage.storage().reference().child("thumbnails/\(thumbnailID).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await storageRef.putDataAsync(thumbnailData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> Data {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let image = try await imageGenerator.image(at: time).image
        
        let uiImage = UIImage(cgImage: image)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ThreadComposer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"])
        }
        
        return jpegData
    }
    
    private func getAvailableHashtags() -> [String] {
        let contextHashtags = getContextHashtags()
        let suggestedHashtags = ["thread", "stitch", "reply", "community", "viral", "trending", "creative", "authentic"]
        let allSuggestions = Array(Set(contextHashtags + suggestedHashtags))
        return allSuggestions.filter { !hashtags.contains($0) }.prefix(6).map { $0 }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
    
    // Context-aware methods
    private func getContextTitle() -> String {
        switch recordingContext {
        case .newThread: return "Create Thread"
        case .stitchToThread: return "Create Stitch"
        case .replyToVideo: return "Create Reply"
        case .continueThread: return "Continue Thread"
        }
    }
    
    private func getContextSubtitle() -> String {
        switch recordingContext {
        case .newThread: return "Share your moment"
        case .stitchToThread(_, let info): return "Stitching to \(info.creatorName)'s thread"
        case .replyToVideo(_, let info): return "Replying to \(info.creatorName)"
        case .continueThread(_, let info): return "Continuing \(info.creatorName)'s thread"
        }
    }
    
    private func getActionButtonText() -> String {
        switch recordingContext {
        case .newThread: return "Create Thread"
        case .stitchToThread: return "Create Stitch"
        case .replyToVideo: return "Create Reply"
        case .continueThread: return "Continue Thread"
        }
    }
    
    private func getContextActionText() -> String {
        switch recordingContext {
        case .newThread: return "Thread"
        case .stitchToThread: return "Stitch"
        case .replyToVideo: return "Reply"
        case .continueThread: return "Thread"
        }
    }
    
    private func getTitlePlaceholder() -> String {
        switch recordingContext {
        case .newThread: return "What's your thread about?"
        case .stitchToThread: return "What's your stitch about?"
        case .replyToVideo: return "What's your reply?"
        case .continueThread: return "Continue the conversation..."
        }
    }
    
    private func getDescriptionPlaceholder() -> String {
        switch recordingContext {
        case .newThread: return "Add more details..."
        case .stitchToThread: return "Add context to your stitch..."
        case .replyToVideo: return "Explain your response..."
        case .continueThread: return "Add to the conversation..."
        }
    }
    
    private func getContextHashtags() -> [String] {
        switch recordingContext {
        case .newThread: return ["thread"]
        case .stitchToThread: return ["stitch", "thread"]
        case .replyToVideo: return ["reply"]
        case .continueThread: return ["thread", "continue"]
        }
    }
}
