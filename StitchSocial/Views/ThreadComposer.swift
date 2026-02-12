//
//  ThreadComposer.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Creation Interface
//  Dependencies: VideoCoordinator, PostCompletionView, AnnouncementSection, ThumbnailPickerView
//  CLEANUP: Extracted PostCompletionEffects, PostCompletionView, AnnouncementSection, ThumbnailPickerView
//  FIXED: NotificationCenter observer leak, AuthService instantiation, batched video property detection
//

import SwiftUI
import AVFoundation
import AVKit
import Combine
import FirebaseAuth

struct ThreadComposer: View {
    
    let recordedVideoURL: URL
    let recordingContext: RecordingContext
    let aiResult: VideoAnalysisResult?
    let recordingSource: String
    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void
    
    @StateObject private var videoCoordinator = VideoCoordinator(
        videoService: VideoService(),
        userService: UserService(),
        aiAnalyzer: AIVideoAnalyzer(),
        uploadService: VideoUploadService(),
        cachingService: nil
    )
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtags: [String] = []
    @State private var taggedUserIDs: [String] = []
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var newHashtagText = ""
    @State private var showingUserTagSheet = false
    @State private var selectedThumbnailTime: TimeInterval? = nil
    @State private var videoDuration: TimeInterval = 0
    
    // Announcement
    @State private var isAnnouncement: Bool = false
    @State private var announcementPriority: AnnouncementPriority = .standard
    @State private var announcementType: AnnouncementType = .update
    @State private var minimumWatchSeconds: Int = 5
    @State private var announcementStartDate: Date = Date()
    @State private var announcementEndDate: Date? = nil
    @State private var hasEndDate: Bool = false
    @State private var repeatMode: AnnouncementRepeatMode = .once
    @State private var maxDailyShows: Int = 1
    @State private var minHoursBetweenShows: Double = 6.0
    @State private var maxTotalShows: Int? = nil
    @State private var hasMaxTotalShows: Bool = false
    
    // Auth
    @State private var capturedUserEmail: String = ""
    @State private var capturedUserId: String = ""
    
    // Video preview
    @State private var sharedPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var isAnalyzing = false
    @State private var hasAnalyzed = false
    @State private var videoAspectRatio: CGFloat = 9.0/16.0
    @State private var isLandscapeVideo: Bool = false
    
    private let maxTitleLength = 100
    private let maxDescriptionLength = 500
    private let maxHashtags = 10
    private let maxTaggedUsers = 10
    
    private var canCreateAnnouncement: Bool {
        AnnouncementVideoHelper.canCreateAnnouncement(email: capturedUserEmail)
    }
    
    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= maxTitleLength &&
        description.count <= maxDescriptionLength &&
        !isCreating
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isCreating {
                PostCompletionView(videoCoordinator: videoCoordinator, isAnnouncement: isAnnouncement)
            } else {
                mainContent
            }
        }
        .onAppear {
            captureAuthState()
            setupSharedVideoPlayer()
            detectVideoProperties()
            if aiResult == nil && !hasAnalyzed { runAIAnalysis() } else { setupInitialContent() }
        }
        .onDisappear { cleanupPlayer() }
        .alert("Error", isPresented: $showError) { Button("OK") { } } message: { Text(errorMessage) }
        .sheet(isPresented: $showingUserTagSheet) {
            UserTagSheet(
                onSelectUsers: { users in taggedUserIDs = users.map { $0.id }; showingUserTagSheet = false },
                onDismiss: { showingUserTagSheet = false },
                alreadyTaggedIDs: taggedUserIDs
            )
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            videoPreview.frame(height: isLandscapeVideo ? 150 : 200)
            ScrollView {
                VStack(spacing: 20) {
                    ThumbnailPickerView(videoURL: recordedVideoURL, videoDuration: videoDuration, selectedThumbnailTime: $selectedThumbnailTime)
                    titleEditor
                    descriptionEditor
                    hashtagEditor
                    userTagEditor
                    AnnouncementSection(
                        isAnnouncement: $isAnnouncement, announcementPriority: $announcementPriority,
                        announcementType: $announcementType, minimumWatchSeconds: $minimumWatchSeconds,
                        announcementStartDate: $announcementStartDate, announcementEndDate: $announcementEndDate,
                        hasEndDate: $hasEndDate, repeatMode: $repeatMode, maxDailyShows: $maxDailyShows,
                        minHoursBetweenShows: $minHoursBetweenShows, maxTotalShows: $maxTotalShows,
                        hasMaxTotalShows: $hasMaxTotalShows, canCreateAnnouncement: canCreateAnnouncement
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            Spacer(minLength: 0)
            postButton
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("Cancel") { cleanupPlayer(); onCancel() }
                .foregroundColor(.white)
            Spacer()
            VStack(spacing: 2) {
                Text(recordingContext.contextDisplayTitle).font(.headline).foregroundColor(.white)
                if isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6).progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        Text("Analyzing...").font(.caption).foregroundColor(.cyan)
                    }
                }
            }
            Spacer()
            if isAnalyzing {
                Button("Skip") { skipAIAnalysis() }.foregroundColor(.cyan)
            } else {
                Text("Cancel").foregroundColor(.clear)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }
    
    private var videoPreview: some View {
        ZStack {
            if let player = sharedPlayer {
                VideoPlayer(player: player)
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .onTapGesture { togglePlayback() }
                if !isPlaying {
                    Image(systemName: "play.circle.fill").font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.8)).onTapGesture { togglePlayback() }
                }
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3))
                    .overlay(ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)))
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Title Editor
    
    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title").font(.headline).foregroundColor(.white)
                Text("*").foregroundColor(.red)
                Spacer()
                Text("\(title.count)/\(maxTitleLength)").font(.caption)
                    .foregroundColor(title.count > maxTitleLength ? .red : .gray)
            }
            TextField("Enter video title...", text: $title)
                .padding(12).background(Color.white.opacity(0.1)).cornerRadius(8)
                .foregroundColor(.white).accentColor(.blue)
                .onChange(of: title) { _, newValue in
                    if newValue.count > maxTitleLength { title = String(newValue.prefix(maxTitleLength)) }
                }
        }
    }
    
    // MARK: - Description Editor
    
    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description").font(.headline).foregroundColor(.white)
                Spacer()
                Text("\(description.count)/\(maxDescriptionLength)").font(.caption)
                    .foregroundColor(description.count > maxDescriptionLength ? .red : .gray)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)).frame(height: 100)
                TextEditor(text: $description).frame(height: 100).padding(8)
                    .background(Color.clear).foregroundColor(.white).scrollContentBackground(.hidden)
                    .onChange(of: description) { _, newValue in
                        if newValue.count > maxDescriptionLength { description = String(newValue.prefix(maxDescriptionLength)) }
                    }
                if description.isEmpty {
                    Text("Enter description...").foregroundColor(.gray)
                        .padding(.horizontal, 12).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - Hashtag Editor
    
    private var hashtagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hashtags").font(.headline).foregroundColor(.white)
            if !hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hashtags, id: \.self) { hashtag in
                            HStack(spacing: 4) {
                                Text("#\(hashtag)").foregroundColor(.white)
                                Button { removeHashtag(hashtag) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.blue.opacity(0.3)).cornerRadius(16)
                        }
                    }
                }
            }
            if hashtags.count < maxHashtags {
                HStack {
                    TextField("Add hashtag...", text: $newHashtagText)
                        .padding(12).background(Color.white.opacity(0.1)).cornerRadius(8)
                        .foregroundColor(.white).accentColor(.blue).onSubmit { addHashtag() }
                    Button("Add") { addHashtag() }
                        .disabled(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        .foregroundColor(.white).cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - User Tag Editor
    
    private var userTagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tag Users").font(.headline).foregroundColor(.white)
                Spacer()
                Text("\(taggedUserIDs.count)/\(maxTaggedUsers)").font(.caption)
                    .foregroundColor(taggedUserIDs.count >= maxTaggedUsers ? .orange : .gray)
            }
            if !taggedUserIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(taggedUserIDs, id: \.self) { userID in
                            TaggedUserChip(userID: userID) { removeTag(userID) }
                        }
                    }
                }
            }
            Button { showingUserTagSheet = true } label: {
                HStack {
                    Image(systemName: "person.badge.plus").font(.system(size: 16))
                    Text(taggedUserIDs.isEmpty ? "Tag Users" : "Edit Tags").font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.cyan).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.white.opacity(0.1)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
            }
            .disabled(taggedUserIDs.count >= maxTaggedUsers && taggedUserIDs.isEmpty)
        }
    }
    
    // MARK: - Post Button
    
    private var postButton: some View {
        Button { createThread() } label: {
            HStack {
                if isAnnouncement { Image(systemName: "megaphone.fill") }
                Text(isAnnouncement ? "Post Announcement" : "Post Thread")
            }
            .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 50)
            .background(
                Group {
                    if canPost {
                        if isAnnouncement {
                            LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                        } else {
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        }
                    } else { Color.gray.opacity(0.3) }
                }
            )
            .cornerRadius(20)
        }
        .disabled(!canPost)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }
    
    // MARK: - Auth Capture
    
    private func captureAuthState() {
        capturedUserEmail = Auth.auth().currentUser?.email ?? ""
        capturedUserId = Auth.auth().currentUser?.uid ?? ""
    }
    
    // MARK: - Thread Creation
    
    private func createThread() {
        guard !isCreating else { return }
        
        let emailToUse = capturedUserEmail.isEmpty ? (Auth.auth().currentUser?.email ?? "") : capturedUserEmail
        let shouldCreateAnnouncement = isAnnouncement && AnnouncementVideoHelper.canCreateAnnouncement(email: emailToUse)
        
        sharedPlayer?.pause()
        isPlaying = false
        isCreating = true
        
        Task {
            do {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let extractedHashtags = HashtagService.extractHashtags(from: trimmedDescription)
                let currentUserID = capturedUserId.isEmpty ? (Auth.auth().currentUser?.uid ?? "unknown") : capturedUserId
                
                // OPTIMIZATION NOTE: VideoService.createThread also fetches user doc for duration
                // validation. If VideoCoordinator passes tier through, this read becomes redundant.
                // Consider caching user doc in a shared upload context to save 1 Firestore read.
                let userDoc = try? await VideoService().db.collection("users").document(currentUserID).getDocument()
                let tierRaw = userDoc?.data()?["tier"] as? String ?? "rookie"
                let currentUserTier = UserTier(rawValue: tierRaw) ?? .rookie
                
                let createdVideo = try await videoCoordinator.processVideoCreation(
                    recordedVideoURL: recordedVideoURL,
                    recordingContext: recordingContext,
                    userID: currentUserID,
                    userTier: currentUserTier,
                    manualTitle: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    manualDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    taggedUserIDs: taggedUserIDs,
                    recordingSource: recordingSource,
                    hashtags: extractedHashtags,
                    customThumbnailTime: selectedThumbnailTime
                )
                
                if shouldCreateAnnouncement {
                    await createAnnouncementForVideo(createdVideo, creatorEmail: emailToUse)
                }
                
                await MainActor.run { isCreating = false; onVideoCreated(createdVideo) }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create thread: \(error.localizedDescription)"
                    showError = true
                    isPlaying = true
                    sharedPlayer?.play()
                }
            }
        }
    }
    
    private func createAnnouncementForVideo(_ video: CoreVideoMetadata, creatorEmail: String) async {
        do {
            let _ = try await AnnouncementService.shared.createAnnouncement(
                videoId: video.id, creatorEmail: creatorEmail, creatorId: video.creatorID,
                title: video.title, message: video.description.isEmpty ? nil : video.description,
                priority: announcementPriority, type: announcementType, targetAudience: .all,
                startDate: announcementStartDate, endDate: hasEndDate ? announcementEndDate : nil,
                minimumWatchSeconds: minimumWatchSeconds, isDismissable: true, requiresAcknowledgment: false,
                repeatMode: repeatMode, maxDailyShows: maxDailyShows,
                minHoursBetweenShows: minHoursBetweenShows, maxTotalShows: maxTotalShows
            )
        } catch {
            print("⚠️ Announcement creation failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Video Player
    
    private func setupSharedVideoPlayer() {
        let player = AVPlayer(url: recordedVideoURL)
        player.isMuted = false
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        sharedPlayer = player
        
        if !isAnalyzing { player.play(); isPlaying = true }
        
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in
            Task { @MainActor in
                guard let p = self.sharedPlayer else { return }
                p.seek(to: .zero) { _ in if self.isPlaying { p.play() } }
            }
        }
    }
    
    private func togglePlayback() {
        if isPlaying { sharedPlayer?.pause() } else { sharedPlayer?.play() }
        isPlaying.toggle()
    }
    
    private func cleanupPlayer() {
        sharedPlayer?.pause()
        sharedPlayer = nil
        isPlaying = false
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
    
    // MARK: - Video Properties (batched: aspect ratio + duration in one asset load)
    
    private func detectVideoProperties() {
        let asset = AVAsset(url: recordedVideoURL)
        Task {
            do {
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else { return }
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let transformed = naturalSize.applying(transform)
                let w = abs(transformed.width), h = abs(transformed.height)
                guard h > 0 else { return }
                await MainActor.run {
                    videoAspectRatio = w / h
                    isLandscapeVideo = videoAspectRatio > 1.0
                    videoDuration = duration
                }
            } catch {
                print("⚠️ Failed to detect video properties: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - AI Analysis
    
    private func runAIAnalysis() {
        guard !hasAnalyzed else { return }
        isAnalyzing = true; sharedPlayer?.pause(); isPlaying = false
        Task {
            do {
                let result = try await AIVideoAnalyzer().analyzeVideo(
                    url: recordedVideoURL, userID: capturedUserId.isEmpty ? "unknown" : capturedUserId
                )
                await MainActor.run {
                    isAnalyzing = false; hasAnalyzed = true
                    if let result = result {
                        title = result.title; description = result.description
                        hashtags = Array(result.hashtags.prefix(maxHashtags))
                    } else { setupInitialContent() }
                    isPlaying = true; sharedPlayer?.play()
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false; hasAnalyzed = true; setupInitialContent()
                    isPlaying = true; sharedPlayer?.play()
                }
            }
        }
    }
    
    private func skipAIAnalysis() {
        isAnalyzing = false; hasAnalyzed = true; setupInitialContent()
        isPlaying = true; sharedPlayer?.play()
    }
    
    private func setupInitialContent() {
        if let aiResult = aiResult {
            title = aiResult.title; description = aiResult.description
            hashtags = Array(aiResult.hashtags.prefix(maxHashtags))
        } else {
            title = getDefaultTitle(); description = ""; hashtags = []
        }
    }
    
    private func getDefaultTitle() -> String {
        switch recordingContext {
        case .newThread: return "New Thread"
        case .stitchToThread(_, let info): return "Stitching to \(info.creatorName)"
        case .replyToVideo(_, let info): return "Reply to \(info.creatorName)"
        case .continueThread(_, let info): return "Continuing \(info.title)"
        case .spinOffFrom(_, _, let info): return "Responding to \(info.creatorName)"
        }
    }
    
    private func addHashtag() {
        let cleaned = newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, !hashtags.contains(cleaned), hashtags.count < maxHashtags else {
            newHashtagText = ""; return
        }
        hashtags.append(cleaned); newHashtagText = ""
    }
    
    private func removeHashtag(_ hashtag: String) { hashtags.removeAll { $0 == hashtag } }
    private func removeTag(_ userID: String) { taggedUserIDs.removeAll { $0 == userID } }
}

// MARK: - Recording Context Extension

extension RecordingContext {
    var contextDisplayTitle: String {
        switch self {
        case .newThread: return "New Thread"
        case .stitchToThread: return "Stitch"
        case .replyToVideo: return "Reply"
        case .continueThread: return "Continue Thread"
        case .spinOffFrom: return "Spin-off"
        }
    }
}

#Preview {
    ThreadComposer(
        recordedVideoURL: URL(string: "file://test.mp4")!,
        recordingContext: .newThread, aiResult: nil, recordingSource: "inApp",
        onVideoCreated: { _ in }, onCancel: { }
    )
}
