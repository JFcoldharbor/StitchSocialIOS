//
//  VideoMetadataRow.swift
//  StitchSocial
//
//  Layer 8: Views - Extracted Video Stats Display Component
//  Dependencies: ContextualVideoEngagement
//  Features: Views, stitches, engagement stats with optional viewers tap (creator-only)
//  UPDATED: Added edit button for creators to update title, description, hashtags
//           Edit only available when canEdit == true (profileOwn context)
//

import SwiftUI
import FirebaseFirestore

// MARK: - VideoMetadataRow

struct VideoMetadataRow: View {
    
    // MARK: - Properties
    
    let engagement: ContextualVideoEngagement?
    let isUserVideo: Bool
    let canEdit: Bool
    let onViewersTap: () -> Void
    let onEditTap: (() -> Void)?
    
    // MARK: - Initializer
    
    init(
        engagement: ContextualVideoEngagement?,
        isUserVideo: Bool,
        canEdit: Bool = false,
        onViewersTap: @escaping () -> Void,
        onEditTap: (() -> Void)? = nil
    ) {
        self.engagement = engagement
        self.isUserVideo = isUserVideo
        self.canEdit = canEdit
        self.onViewersTap = onViewersTap
        self.onEditTap = onEditTap
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 8) {
            if let engagement = engagement {
                // Views count (TAPPABLE for creator only)
                if isUserVideo {
                    Button(action: onViewersTap) {
                        viewsButton(count: engagement.viewCount)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    viewsStat(count: engagement.viewCount)
                }
                
                separator
                stitchesStat(count: engagement.replyCount)
                
                // Edit button - ONLY when canEdit is true (profileOwn + creator)
                if canEdit {
                    separator
                    editButton
                }
                
            } else {
                loadingState
            }
        }
    }
    
    // MARK: - Edit Button
    
    private var editButton: some View {
        Button {
            onEditTap?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Edit")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Component Views
    
    private func viewsButton(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text("\(formatCount(count)) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    private func viewsStat(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text("\(formatCount(count)) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private func stitchesStat(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.cyan.opacity(0.7))
            Text("\(formatCount(count)) stitches")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.cyan.opacity(0.9))
        }
    }
    
    private var separator: some View {
        Text("•")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
    }
    
    private var loadingState: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text("Loading...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    // MARK: - Utility
    
    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1000000:
            return String(format: "%.1fK", Double(count) / 1000.0).replacingOccurrences(of: ".0", with: "")
        case 1000000..<1000000000:
            return String(format: "%.1fM", Double(count) / 1000000.0).replacingOccurrences(of: ".0", with: "")
        default:
            return String(format: "%.1fB", Double(count) / 1000000000.0).replacingOccurrences(of: ".0", with: "")
        }
    }
}

// MARK: - Video Edit Sheet

struct VideoEditSheet: View {
    
    let video: CoreVideoMetadata
    let onSave: (CoreVideoMetadata) -> Void
    let onDismiss: () -> Void
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtagsText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var videoService = VideoService()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        thumbnailPreview
                        titleSection
                        descriptionSection
                        hashtagsSection
                        
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    } else {
                        Button("Save") {
                            Task { await saveChanges() }
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadCurrentValues() }
    }
    
    // MARK: - Thumbnail Preview
    
    private var thumbnailPreview: some View {
        VStack(spacing: 12) {
            if let thumbnailURL = URL(string: video.thumbnailURL), !video.thumbnailURL.isEmpty {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(9/16, contentMode: .fit)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure, .empty:
                        thumbnailPlaceholder
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
    }
    
    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .frame(height: 180)
            .frame(maxWidth: 120)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)
            )
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Title", systemImage: "textformat")
                .font(.headline)
                .foregroundColor(.white)
            
            TextField("Enter video title...", text: $title)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .foregroundColor(.white)
            
            Text("\(title.count)/100 characters")
                .font(.caption)
                .foregroundColor(title.count > 100 ? .red : .gray)
        }
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Description", systemImage: "text.alignleft")
                .font(.headline)
                .foregroundColor(.white)
            
            TextEditor(text: $description)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
            
            Text("\(description.count)/500 characters")
                .font(.caption)
                .foregroundColor(description.count > 500 ? .red : .gray)
        }
    }
    
    // MARK: - Hashtags Section
    
    private var hashtagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hashtags", systemImage: "number")
                .font(.headline)
                .foregroundColor(.white)
            
            TextField("#trending #viral #fyp", text: $hashtagsText)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            
            Text("Separate hashtags with spaces")
                .font(.caption)
                .foregroundColor(.gray)
            
            if !extractedHashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(extractedHashtags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.cyan.opacity(0.2)))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.subheadline).foregroundColor(.white)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.3)))
    }
    
    // MARK: - Computed Properties
    
    private var extractedHashtags: [String] {
        hashtagsText.split(separator: " ").compactMap { word -> String? in
            var tag = String(word).trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty else { return nil }
            if !tag.hasPrefix("#") { tag = "#\(tag)" }
            return tag.dropFirst().isEmpty ? nil : tag
        }
    }
    
    // MARK: - Actions
    
    private func loadCurrentValues() {
        title = video.title
        description = video.description
        
        if let regex = try? NSRegularExpression(pattern: "#\\w+") {
            let range = NSRange(video.description.startIndex..., in: video.description)
            let matches = regex.matches(in: video.description, range: range)
            let hashtags = matches.compactMap { match -> String? in
                if let range = Range(match.range, in: video.description) {
                    return String(video.description[range])
                }
                return nil
            }
            hashtagsText = hashtags.joined(separator: " ")
            
            var cleanDescription = video.description
            for tag in hashtags {
                cleanDescription = cleanDescription.replacingOccurrences(of: tag, with: "")
            }
            description = cleanDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func saveChanges() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title cannot be empty"
            return
        }
        guard trimmedTitle.count <= 100 else {
            errorMessage = "Title must be 100 characters or less"
            return
        }
        guard description.count <= 500 else {
            errorMessage = "Description must be 500 characters or less"
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        do {
            var finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let hashtags = extractedHashtags
            if !hashtags.isEmpty {
                let hashtagString = hashtags.joined(separator: " ")
                finalDescription = finalDescription.isEmpty ? hashtagString : "\(finalDescription)\n\n\(hashtagString)"
            }
            
            try await videoService.updateVideoMetadata(
                videoID: video.id,
                title: trimmedTitle,
                description: finalDescription
            )
            
            print("✅ VIDEO EDIT: Updated video \(video.id)")
            
            let updatedVideo = CoreVideoMetadata(
                id: video.id,
                title: trimmedTitle,
                description: finalDescription,
                taggedUserIDs: video.taggedUserIDs,
                videoURL: video.videoURL,
                thumbnailURL: video.thumbnailURL,
                creatorID: video.creatorID,
                creatorName: video.creatorName,
                createdAt: video.createdAt,
                threadID: video.threadID,
                replyToVideoID: video.replyToVideoID,
                conversationDepth: video.conversationDepth,
                viewCount: video.viewCount,
                hypeCount: video.hypeCount,
                coolCount: video.coolCount,
                replyCount: video.replyCount,
                shareCount: video.shareCount,
                temperature: video.temperature,
                qualityScore: video.qualityScore,
                engagementRatio: video.engagementRatio,
                velocityScore: video.velocityScore,
                trendingScore: video.trendingScore,
                duration: video.duration,
                aspectRatio: video.aspectRatio,
                fileSize: video.fileSize,
                discoverabilityScore: video.discoverabilityScore,
                isPromoted: video.isPromoted,
                lastEngagementAt: video.lastEngagementAt,
                collectionID: video.collectionID,
                segmentNumber: video.segmentNumber,
                segmentTitle: video.segmentTitle,
                isCollectionSegment: video.isCollectionSegment,
                replyTimestamp: video.replyTimestamp
            )
            
            await MainActor.run {
                isSaving = false
                onSave(updatedVideo)
                onDismiss()
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = "Failed to save: \(error.localizedDescription)"
                print("❌ VIDEO EDIT: Failed - \(error)")
            }
        }
    }
}

// MARK: - VideoService Extension for Metadata Update

extension VideoService {
    func updateVideoMetadata(videoID: String, title: String, description: String) async throws {
        let updateData: [String: Any] = [
            FirebaseSchema.VideoDocument.title: title,
            FirebaseSchema.VideoDocument.description: description,
            FirebaseSchema.VideoDocument.updatedAt: Timestamp()
        ]
        
        try await db.collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .updateData(updateData)
        
        print("✅ VIDEO SERVICE: Updated metadata for \(videoID)")
    }
}

// MARK: - Preview

struct VideoMetadataRow_Previews: PreviewProvider {
    static let mockEngagement = ContextualVideoEngagement(
        videoID: "video1",
        creatorID: "user1",
        hypeCount: 245,
        coolCount: 78,
        shareCount: 12,
        replyCount: 34,
        viewCount: 1523,
        lastEngagementAt: Date()
    )
    
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 20) {
                // Creator on own profile (CAN edit)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator on Own Profile (Can Edit)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: mockEngagement,
                        isUserVideo: true,
                        canEdit: true,
                        onViewersTap: { print("👁️ Tapped viewers") },
                        onEditTap: { print("✏️ Tapped edit") }
                    )
                }
                
                // Creator from HomeFeed (CANNOT edit)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator from HomeFeed (No Edit)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: mockEngagement,
                        isUserVideo: true,
                        canEdit: false,
                        onViewersTap: { print("👁️ Tapped viewers") }
                    )
                }
                
                // Viewer (CANNOT edit)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Viewer (No Edit)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    VideoMetadataRow(
                        engagement: mockEngagement,
                        isUserVideo: false,
                        canEdit: false,
                        onViewersTap: { }
                    )
                }
            }
            .padding()
        }
    }
}
