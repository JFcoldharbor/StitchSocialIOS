//
//  ThreadComposer.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Creation Interface
//  Dependencies: VideoCoordinator (Layer 6), CoreVideoMetadata (Layer 1)
//  Features: Video metadata editing, thread creation, AI result integration
//  FIXED: All compilation errors resolved
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
    
    // MARK: - Constants
    
    private let maxTitleLength = 100
    private let maxDescriptionLength = 300
    private let maxHashtags = 5
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isCreating {
                creationProgressView
            } else {
                composerInterface
            }
        }
        .onAppear {
            setupInitialContent()
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
            
            // Video Preview
            videoPreview
                .frame(height: 300)
            
            // Content Editor
            ScrollView {
                VStack(spacing: 24) {
                    titleEditor
                    descriptionEditor
                    hashtagEditor
                    contextInfo
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            
            // Action Buttons
            actionButtons
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
            
            Text("Create Thread")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Post") {
                createThread()
            }
            .foregroundColor(canPost ? .blue : .gray)
            .disabled(!canPost)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Video Preview (FIXED - No VideoPlayer dependency)
    
    private var videoPreview: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    Text("Video Preview")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            )
            .cornerRadius(12)
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
                    .foregroundColor(.gray)
            }
            
            TextField("What's this thread about?", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
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
                    .foregroundColor(.gray)
            }
            
            TextField("Add more details...", text: $description, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(5)
                .onChange(of: description) { _, newValue in
                    if newValue.count > maxDescriptionLength {
                        description = String(newValue.prefix(maxDescriptionLength))
                    }
                }
        }
    }
    
    private var hashtagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hashtags")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(hashtags.count)/\(maxHashtags)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(hashtags, id: \.self) { hashtag in
                    hashtagChip(hashtag)
                }
                
                if hashtags.count < maxHashtags {
                    addHashtagButton
                }
            }
        }
    }
    
    private func hashtagChip(_ hashtag: String) -> some View {
        HStack(spacing: 4) {
            Text("#\(hashtag)")
                .font(.caption)
                .foregroundColor(.white)
            
            Button {
                hashtags.removeAll { $0 == hashtag }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.3))
        .cornerRadius(8)
    }
    
    private var addHashtagButton: some View {
        Button {
            // Add hashtag input logic
            let newHashtag = "tag\(hashtags.count + 1)"
            if hashtags.count < maxHashtags {
                hashtags.append(newHashtag)
            }
        } label: {
            HStack {
                Image(systemName: "plus")
                Text("Add Tag")
            }
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Context Info
    
    private var contextInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(recordingContext.displayTitle)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                onCancel()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Button("Create Thread") {
                createThread()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(canPost ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(!canPost)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Creation Progress
    
    private var creationProgressView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Creating your thread...")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(videoCoordinator.currentTask)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count >= 3 &&
        !isCreating
    }
    
    // MARK: - Methods
    
    private func setupInitialContent() {
        // Use AI results if available
        if let aiResult = aiResult {
            title = aiResult.title
            description = aiResult.description
            hashtags = Array(aiResult.hashtags.prefix(maxHashtags))
        } else {
            // Set default values based on context
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
    
    // MARK: - Thread Creation (FIXED - No immutable property assignments)
    
    private func createThread() {
        guard !isCreating else { return }
        
        isCreating = true
        
        Task {
            do {
                // Create a custom VideoAnalysisResult with user input
                let customAnalysisResult = VideoAnalysisResult(
                    title: title,
                    description: description,
                    hashtags: hashtags
                )
                
                // Inject the custom result into the coordinator
                videoCoordinator.aiAnalysisResult = customAnalysisResult
                
                // Create video through VideoCoordinator
                let createdVideo = try await videoCoordinator.processVideoCreation(
                    recordedVideoURL: recordedVideoURL,
                    recordingContext: recordingContext,
                    userID: AuthService().currentUser?.id ?? "",
                    userTier: .rookie
                )
                
                await MainActor.run {
                    onVideoCreated(createdVideo)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                }
            }
        }
    }
}
