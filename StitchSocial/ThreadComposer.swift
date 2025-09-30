//
//  ThreadComposer.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Creation Interface
//  Dependencies: VideoCoordinator (Layer 6), CoreVideoMetadata (Layer 1), BoundedVideoContainer
//  Features: Working video preview, hashtag input, metadata editing, AI result integration
//  FIXED: Now passes manual title/description to VideoCoordinator
//

import SwiftUI
import AVFoundation

struct ThreadComposer: View {
    
    // MARK: - Properties
    
    let recordedVideoURL: URL
    let recordingContext: RecordingContext
    let aiResult: VideoAnalysisResult?
    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void
    
    // MARK: - State
    
    @StateObject private var videoCoordinator = VideoCoordinator(
        videoService: VideoService(),
        aiAnalyzer: AIVideoAnalyzer(),
        videoProcessor: VideoProcessingService(),
        uploadService: VideoUploadService(),
        cachingService: nil
    )
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtags: [String] = []
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Hashtag input state
    @State private var newHashtagText = ""
    
    // Video preview state - FIXED: Single player reference
    @State private var sharedPlayer: AVPlayer?
    @State private var isPlaying = false
    
    // AI Analysis state
    @State private var isAnalyzing = false
    @State private var hasAnalyzed = false
    
    // MARK: - Constants
    
    private let maxTitleLength = 100
    private let maxDescriptionLength = 300
    private let maxHashtags = 10
    
    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.05, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isCreating {
                creationProgressView
            } else if isAnalyzing {
                aiAnalysisView
            } else {
                composerInterface
            }
        }
        .onAppear {
            setupSharedVideoPlayer()
            performInitialAIAnalysis()
        }
        .onDisappear {
            cleanupVideoPlayer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Composer Interface
    
    private var composerInterface: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Video Preview - SMALLER SIZE
            videoPreview
                .frame(height: 200)
            
            // Content Editor
            ScrollView {
                VStack(spacing: 20) {
                    titleEditor
                    descriptionEditor
                    hashtagEditor
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            
            Spacer(minLength: 0)
            
            // Post Button
            postButton
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.white)
            
            Spacer()
            
            Text(recordingContext.contextDisplayTitle)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Hidden placeholder for symmetry
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.white)
            .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    // MARK: - Video Preview (FIXED: Single Player)
    
    private var videoPreview: some View {
        ZStack {
            if let player = sharedPlayer {
                VideoPlayerContainer(player: player, isPlaying: $isPlaying)
                    .aspectRatio(9/16, contentMode: .fit)
                    .background(Color.black)
                    .clipped()
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(9/16, contentMode: .fit)
                    .cornerRadius(16)
            }
            
            // Play/Pause Overlay
            if !isPlaying {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Content Editors
    
    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(title.count)/\(maxTitleLength)")
                    .font(.caption)
                    .foregroundColor(title.count > maxTitleLength ? .red : .gray)
            }
            
            TextField("Enter video title...", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: title) { newValue in
                    if newValue.count > maxTitleLength {
                        title = String(newValue.prefix(maxTitleLength))
                    }
                }
        }
    }
    
    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(description.count)/\(maxDescriptionLength)")
                    .font(.caption)
                    .foregroundColor(description.count > maxDescriptionLength ? .red : .gray)
            }
            
            TextEditor(text: $description)
                .frame(height: 100)
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .onChange(of: description) { newValue in
                    if newValue.count > maxDescriptionLength {
                        description = String(newValue.prefix(maxDescriptionLength))
                    }
                }
        }
    }
    
    private var hashtagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hashtags")
                .font(.headline)
                .foregroundColor(.white)
            
            // Existing hashtags
            if !hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hashtags, id: \.self) { hashtag in
                            HStack(spacing: 4) {
                                Text("#\(hashtag)")
                                    .foregroundColor(.white)
                                
                                Button {
                                    removeHashtag(hashtag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(16)
                        }
                    }
                }
            }
            
            // Add new hashtag
            if hashtags.count < maxHashtags {
                HStack {
                    TextField("Add hashtag...", text: $newHashtagText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addHashtag()
                        }
                    
                    Button("Add") {
                        addHashtag()
                    }
                    .disabled(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Post Button
    
    private var postButton: some View {
        VStack(spacing: 12) {
            Button("Post Thread") {
                createThread()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Group {
                    if canPost {
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
            )
            .cornerRadius(20)
            .disabled(!canPost)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Creation Progress View
    
    private var creationProgressView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            VStack(spacing: 8) {
                Text("Creating your thread...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(videoCoordinator.currentTask)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            ProgressView(value: videoCoordinator.overallProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var canPost: Bool {
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               title.count <= maxTitleLength &&
               description.count <= maxDescriptionLength &&
               !isCreating
    }
    
    // MARK: - Video Player Setup
    
    private func setupSharedVideoPlayer() {
        print("🎬 SETUP: Creating shared video player")
        let player = AVPlayer(url: recordedVideoURL)
        player.isMuted = false
        player.actionAtItemEnd = .none
        
        sharedPlayer = player
        isPlaying = true
        player.play()
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            if self.isPlaying {
                player.play()
            }
        }
        
        print("🎬 SETUP: Player ready and playing")
    }
    
    private func togglePlayback() {
        guard let player = sharedPlayer else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    private func cleanupVideoPlayer() {
        print("🧹 CLEANUP: Cleaning up video player")
        sharedPlayer?.pause()
        sharedPlayer = nil
        isPlaying = false
        NotificationCenter.default.removeObserver(self)
        print("🧹 CLEANUP: Player removed")
    }
    
    // MARK: - Hashtag Methods
    
    private func addHashtag() {
        let cleanedText = newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        
        guard !cleanedText.isEmpty,
              !hashtags.contains(cleanedText),
              hashtags.count < maxHashtags else { return }
        
        hashtags.append(cleanedText)
        newHashtagText = ""
    }
    
    private func removeHashtag(_ hashtag: String) {
        hashtags.removeAll { $0 == hashtag }
    }
    
    // MARK: - AI Analysis View
    
    private var aiAnalysisView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(isAnalyzing ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnalyzing)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Analyzing your video...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Generating title and description with AI")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            Button("Skip Analysis") {
                skipAIAnalysis()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - AI Analysis Methods
    
    private func performInitialAIAnalysis() {
        if aiResult != nil {
            setupInitialContent()
            return
        }
        
        print("🤖 AI ANALYSIS: Starting - pausing video player")
        sharedPlayer?.pause()
        isPlaying = false
        isAnalyzing = true
        
        Task {
            do {
                let aiAnalyzer = AIVideoAnalyzer()
                let result = await aiAnalyzer.analyzeVideo(
                    url: recordedVideoURL,
                    userID: AuthService().currentUser?.id ?? "unknown"
                )
                
                await MainActor.run {
                    isAnalyzing = false
                    hasAnalyzed = true
                    
                    if let result = result {
                        title = result.title
                        description = result.description
                        hashtags = Array(result.hashtags.prefix(maxHashtags))
                        print("✅ THREAD COMPOSER: AI analysis successful - '\(result.title)'")
                    } else {
                        setupInitialContent()
                        print("⚠️ THREAD COMPOSER: AI analysis failed - using defaults")
                    }
                    
                    print("🎬 AI ANALYSIS: Complete - resuming video player")
                    isPlaying = true
                    sharedPlayer?.play()
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    hasAnalyzed = true
                    setupInitialContent()
                    print("❌ THREAD COMPOSER: AI analysis error - \(error.localizedDescription)")
                    
                    print("🎬 AI ANALYSIS: Error - resuming video player")
                    isPlaying = true
                    sharedPlayer?.play()
                }
            }
        }
    }
    
    private func skipAIAnalysis() {
        print("⏭ THREAD COMPOSER: AI analysis skipped by user")
        isAnalyzing = false
        hasAnalyzed = true
        setupInitialContent()
        isPlaying = true
        sharedPlayer?.play()
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialContent() {
        if let aiResult = aiResult {
            title = aiResult.title
            description = aiResult.description
            hashtags = Array(aiResult.hashtags.prefix(maxHashtags))
        } else {
            title = getDefaultTitle()
            description = ""
            hashtags = []
        }
    }
    
    private func getDefaultTitle() -> String {
        switch recordingContext {
        case .newThread:
            return "New Thread"
        case .stitchToThread(_, let info):
            return "Stitching to \(info.creatorName)"
        case .replyToVideo(_, let info):
            return "Reply to \(info.creatorName)"
        case .continueThread(_, let info):
            return "Continuing \(info.title)"
        }
    }
    
    private func getContextDescription() -> String {
        switch recordingContext {
        case .newThread:
            return "Starting a new conversation"
        case .stitchToThread(_, let info):
            return "Stitching to thread by \(info.creatorName)"
        case .replyToVideo(_, let info):
            return "Replying to video by \(info.creatorName)"
        case .continueThread(_, let info):
            return "Continuing thread: \(info.title)"
        }
    }
    
    // MARK: - Thread Creation (FIXED: Pass Manual Title/Description)
    
    private func createThread() {
        guard !isCreating else { return }
        
        print("🎬 CREATION: Starting - pausing video player")
        sharedPlayer?.pause()
        isPlaying = false
        isCreating = true
        
        Task {
            do {
                // CRITICAL FIX: Pass user-edited title and description to VideoCoordinator
                // These will override AI results in Firebase
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("✍️ MANUAL CONTENT: Passing to VideoCoordinator")
                print("✍️ TITLE: '\(trimmedTitle)'")
                print("✍️ DESCRIPTION: '\(trimmedDescription)'")
                
                // Get current user info from AuthService
                let authService = AuthService()
                let currentUserID = authService.currentUser?.id ?? "unknown"
                let currentUserTier = authService.currentUser?.tier ?? .rookie
                
                print("🔐 AUTH: User ID = '\(currentUserID)'")
                print("🔐 AUTH: User Tier = '\(currentUserTier.rawValue)'")
                
                let createdVideo = try await videoCoordinator.processVideoCreation(
                    recordedVideoURL: recordedVideoURL,
                    recordingContext: recordingContext,
                    userID: currentUserID,
                    userTier: currentUserTier,
                    manualTitle: trimmedTitle.isEmpty ? nil : trimmedTitle,        // NEW: Pass manual title
                    manualDescription: trimmedDescription.isEmpty ? nil : trimmedDescription  // NEW: Pass manual description
                )
                
                await MainActor.run {
                    print("✅ THREAD CREATION: Success!")
                    print("✅ FINAL TITLE: '\(createdVideo.title)'")
                    print("✅ FINAL DESCRIPTION: '\(createdVideo.description)'")
                    isCreating = false
                    onVideoCreated(createdVideo)
                }
                
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create thread: \(error.localizedDescription)"
                    showError = true
                    print("❌ THREAD CREATION: Failed - \(error.localizedDescription)")
                    
                    // Resume video on error
                    isPlaying = true
                    sharedPlayer?.play()
                }
            }
        }
    }
}

// MARK: - Video Player Container

struct VideoPlayerContainer: UIViewRepresentable {
    let player: AVPlayer
    @Binding var isPlaying: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        
        context.coordinator.playerLayer = playerLayer
        context.coordinator.containerView = view
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator {
        var parent: VideoPlayerContainer
        var playerLayer: AVPlayerLayer?
        var containerView: UIView?
        
        init(_ parent: VideoPlayerContainer) {
            self.parent = parent
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Supporting Extensions

extension RecordingContext {
    var contextDisplayTitle: String {
        switch self {
        case .newThread:
            return "New Thread"
        case .stitchToThread:
            return "Stitch"
        case .replyToVideo:
            return "Reply"
        case .continueThread:
            return "Continue Thread"
        }
    }
}
