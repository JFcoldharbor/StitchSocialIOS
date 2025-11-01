//
//  ThreadComposer.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Creation Interface
//  Dependencies: VideoCoordinator (Layer 6), CoreVideoMetadata (Layer 1), BoundedVideoContainer
//  Features: Working video preview, hashtag input, metadata editing, AI result integration
//  FIXED: Now passes manual title/description to VideoCoordinator
//  UPDATED: Added user tagging system
//  FIXED: Removed duplicate VideoPlayerContainer/VideoPlayerUIView declarations
//  WORKING: User-provided exact working version
//

import SwiftUI
import AVFoundation
import AVKit  // ADD THIS for VideoPlayer
import Combine

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
        userService: UserService(),
        aiAnalyzer: AIVideoAnalyzer(),
        videoProcessor: VideoProcessingService(),
        uploadService: VideoUploadService(),
        cachingService: nil
    )
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtags: [String] = []
    @State private var taggedUserIDs: [String] = []  // NEW: Tagged users
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Hashtag input state
    @State private var newHashtagText = ""
    
    // NEW: User tagging state
    @State private var showingUserTagSheet = false
    
    // Video preview state - FIXED: Single player reference
    @State private var sharedPlayer: AVPlayer?
    @State private var isPlaying = false
    
    // AI Analysis state
    @State private var isAnalyzing = false
    @State private var hasAnalyzed = false
    
    // Combine cancellables for player monitoring
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private let maxTitleLength = 100
    private let maxDescriptionLength = 300
    private let maxHashtags = 10
    private let maxTaggedUsers = 5  // NEW
    
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
        .sheet(isPresented: $showingUserTagSheet) {
            UserTagSheet(
                onSelectUsers: { userIDs in
                    taggedUserIDs = userIDs
                    showingUserTagSheet = false
                },
                onDismiss: {
                    showingUserTagSheet = false
                },
                alreadyTaggedIDs: taggedUserIDs
            )
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
                    userTagEditor  // NEW: User tagging section
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
    
    // MARK: - Video Preview (Simple inline player for composer)
    
    private var videoPreview: some View {
        ZStack {
            if let player = sharedPlayer {
                // Simple VideoPlayer for preview
                VideoPlayer(player: player)
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
                    .disabled(true) // Disable built-in controls
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
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .accentColor(.blue)
                .onChange(of: title) { _, newValue in
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
            
            ZStack(alignment: .topLeading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 100)
                
                // TextEditor
                TextEditor(text: $description)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.clear)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden) // Hide default white background
                    .onChange(of: description) { _, newValue in
                        if newValue.count > maxDescriptionLength {
                            description = String(newValue.prefix(maxDescriptionLength))
                        }
                    }
                
                // Placeholder text
                if description.isEmpty {
                    Text("Enter description...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
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
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .accentColor(.blue)
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
    
    // MARK: - NEW: User Tag Editor
    
    private var userTagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tag Users")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(taggedUserIDs.count)/\(maxTaggedUsers)")
                    .font(.caption)
                    .foregroundColor(taggedUserIDs.count >= maxTaggedUsers ? .orange : .gray)
            }
            
            // Show tagged users
            if !taggedUserIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(taggedUserIDs, id: \.self) { userID in
                            TaggedUserChip(userID: userID) {
                                removeTag(userID)
                            }
                        }
                    }
                }
            }
            
            // Tag users button
            Button {
                showingUserTagSheet = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16))
                    
                    Text(taggedUserIDs.isEmpty ? "Tag Users" : "Edit Tags")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(taggedUserIDs.count >= maxTaggedUsers && taggedUserIDs.isEmpty)
        }
    }
    
    // MARK: - Post Button
    
    private var postButton: some View {
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
        
        // Configure player for optimal autoplay
        player.isMuted = false
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false // Faster startup
        
        sharedPlayer = player
        
        // Start playing immediately
        player.play()
        isPlaying = true
        
        // Setup looping with proper notification handling
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard let player = self.sharedPlayer else { return }
                
                player.seek(to: .zero) { _ in
                    if self.isPlaying {
                        player.play()
                    }
                }
            }
        }
        
        // Monitor player status for debugging
        player.currentItem?.publisher(for: \.status)
            .sink { status in
                print("🎬 PLAYER STATUS: \(status)")
                switch status {
                case .readyToPlay:
                    print("🎬 READY TO PLAY: Player is ready")
                case .failed:
                    print("❌ PLAYER FAILED: \(player.currentItem?.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    print("🤔 PLAYER STATUS: Unknown")
                @unknown default:
                    print("🔄 PLAYER STATUS: Other")
                }
            }
            .store(in: &cancellables)
        
        // Monitor time control status
        player.publisher(for: \.timeControlStatus)
            .sink { status in
                DispatchQueue.main.async {
                    self.isPlaying = (status == .playing)
                    print("🎬 TIME CONTROL: \(status.rawValue) - isPlaying: \(self.isPlaying)")
                }
            }
            .store(in: &cancellables)
        
        print("🎬 SETUP: Player ready and should start playing")
    }
    
    private func togglePlayback() {
        guard let player = sharedPlayer else {
            print("❌ TOGGLE: No player available")
            return
        }
        
        if isPlaying {
            print("⏸️ PAUSING playback")
            player.pause()
            isPlaying = false
        } else {
            print("▶️ STARTING playback")
            player.play()
            isPlaying = true
        }
    }
    
    private func cleanupVideoPlayer() {
        print("🧹 CLEANUP: Cleaning up video player")
        sharedPlayer?.pause()
        sharedPlayer = nil
        isPlaying = false
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        print("🧹 CLEANUP: Player removed and observers cleared")
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
    
    // MARK: - NEW: User Tagging Methods
    
    private func removeTag(_ userID: String) {
        withAnimation(.spring(response: 0.3)) {
            taggedUserIDs.removeAll { $0 == userID }
        }
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
        print("⏭️ THREAD COMPOSER: AI analysis skipped by user")
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
    
    // MARK: - Thread Creation (UPDATED: Pass Tagged Users)
    
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
                
                print("✏️ MANUAL CONTENT: Passing to VideoCoordinator")
                print("✏️ TITLE: '\(trimmedTitle)'")
                print("✏️ DESCRIPTION: '\(trimmedDescription)'")
                print("🏷️ TAGGED USERS: \(taggedUserIDs.count) users")
                
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
                    manualTitle: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    manualDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    taggedUserIDs: taggedUserIDs  // NEW: Pass tagged users
                )
                
                await MainActor.run {
                    print("✅ THREAD CREATION: Success!")
                    print("✅ FINAL TITLE: '\(createdVideo.title)'")
                    print("✅ FINAL DESCRIPTION: '\(createdVideo.description)'")
                    print("✅ TAGGED USERS: \(createdVideo.taggedUserIDs.count)")
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
