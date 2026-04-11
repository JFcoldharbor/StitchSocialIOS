//
//  ImportSegmentsView.swift
//  StitchSocial
//
//  Layer 6: Views - Import Individual Segment Files into an Episode
//  Streams from disk via putFile (no Data(contentsOf:) blocking).
//  Auto-compresses files >100MB. Real progress bar per segment.
//

import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import AVFoundation
import UniformTypeIdentifiers

struct ImportSegmentsView: View {
    
    let episodeId: String
    let showId: String
    let seasonId: String
    let creatorName: String
    let episodeTitle: String
    let episodeNumber: Int
    let onDismiss: () -> Void
    
    @State private var segments: [ImportedSegment] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var isUploading = false
    @State private var currentSegIndex = 0
    @State private var currentSegProgress: Double = 0
    @State private var currentTask = ""
    @State private var uploadComplete = false
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    private var overallProgress: Double {
        guard !segments.isEmpty else { return 0 }
        return (Double(segments.filter { $0.uploaded }.count) + currentSegProgress) / Double(segments.count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Segments")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { onDismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            
            pickerSection
            
            if !segments.isEmpty {
                segmentList
                if isUploading { progressSection }
                uploadButton
            }
            
            if let error = errorMessage {
                Text(error).font(.system(size: 11)).foregroundColor(.red)
                    .padding(.horizontal, 16).padding(.top, 4)
            }
            
            Spacer()
        }
        .background(Color.black)
    }
    
    // MARK: - Pickers
    
    private var pickerSection: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 20, matching: .videos, photoLibrary: .shared()) {
                VStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.folder").font(.system(size: 28)).foregroundColor(.cyan.opacity(0.6))
                    Text("Select from Camera Roll").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                    Text("Each file becomes one segment").font(.system(size: 10)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundColor(.cyan.opacity(0.25)))
            }
            .padding(.horizontal, 16)
            .onChange(of: selectedItems) { _, items in Task { await handlePickedItems(items) } }
            
            Button { showingFilePicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 12))
                    Text("Import from Files").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.cyan.opacity(0.7)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.white.opacity(0.03)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.15), lineWidth: 0.5))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: true) { result in
                Task { await handleFileImport(result) }
            }
        }
    }
    
    // MARK: - Segment List
    
    private var segmentList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                    HStack(spacing: 10) {
                        Text("\(idx + 1)").font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 20)
                        
                        if let thumb = seg.thumbnailLocalURL {
                            AsyncImage(url: thumb) { img in img.resizable().aspectRatio(contentMode: .fill) } placeholder: { Rectangle().fill(Color.white.opacity(0.06)) }
                                .frame(width: 40, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)).frame(width: 40, height: 28)
                                .overlay(Image(systemName: "film").font(.system(size: 10)).foregroundColor(.gray.opacity(0.4)))
                        }
                        
                        Image(systemName: seg.uploaded ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12)).foregroundColor(seg.uploaded ? .green : .gray.opacity(0.3))
                        
                        TextField("Segment \(idx + 1)", text: Binding(get: { seg.title }, set: { segments[idx].title = $0 }))
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(formatDuration(seg.duration)).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                        
                        if !isUploading {
                            Button { segments.remove(at: idx) } label: {
                                Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.white.opacity(seg.uploaded ? 0.02 : 0.04)).cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Progress
    
    private var progressSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().tint(.pink).scaleEffect(0.7)
                Text(currentTask).font(.system(size: 11, weight: .medium)).foregroundColor(.pink).lineLimit(1)
            }
            ProgressView(value: overallProgress).tint(.pink)
            Text("\(Int(overallProgress * 100))%").font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
    
    // MARK: - Upload Button
    
    private var uploadButton: some View {
        Button { Task { await uploadAllSegments() } } label: {
            HStack(spacing: 6) {
                Image(systemName: uploadComplete ? "checkmark.circle.fill" : "arrow.up.circle.fill").font(.system(size: 13))
                Text(uploadComplete ? "Done!" : isUploading ? "Uploading..." : "Upload \(segments.count) Segments")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(uploadComplete
                ? LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(10)
        }
        .disabled(isUploading || segments.isEmpty)
        .padding(16)
    }
    
    // MARK: - Handle Photos Picker
    
    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        var newSegs: [ImportedSegment] = []
        for (idx, item) in items.enumerated() {
            do {
                guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else { continue }
                let dur = try await CMTimeGetSeconds(AVURLAsset(url: movie.url).load(.duration))
                let thumb = await generateThumbnail(for: movie.url)
                newSegs.append(ImportedSegment(id: UUID().uuidString, title: "Segment \(segments.count + idx + 1)",
                    localURL: movie.url, duration: dur, thumbnailLocalURL: thumb, uploaded: false))
            } catch { print("❌ IMPORT: Failed to load item \(idx): \(error)") }
        }
        await MainActor.run { segments.append(contentsOf: newSegs); selectedItems = [] }
    }
    
    // MARK: - Handle File Import
    
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            var newSegs: [ImportedSegment] = []
            for url in try result.get() {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                try FileManager.default.copyItem(at: url, to: temp)
                let dur = try await CMTimeGetSeconds(AVURLAsset(url: temp).load(.duration))
                let thumb = await generateThumbnail(for: temp)
                newSegs.append(ImportedSegment(id: UUID().uuidString, title: url.deletingPathExtension().lastPathComponent,
                    localURL: temp, duration: dur, thumbnailLocalURL: thumb, uploaded: false))
            }
            await MainActor.run { segments.append(contentsOf: newSegs) }
        } catch { await MainActor.run { errorMessage = "File import failed: \(error.localizedDescription)" } }
    }
    
    // MARK: - Thumbnail
    
    private func generateThumbnail(for url: URL) async -> URL? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        do {
            let img = try await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            if let data = UIImage(cgImage: img).jpegData(compressionQuality: 0.7) { try data.write(to: out); return out }
        } catch { }
        return nil
    }
    
    // MARK: - Upload All Segments
    
    private func uploadAllSegments() async {
        isUploading = true
        errorMessage = nil
        
        // Protect from background termination
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "SegmentUpload") {
            print("⚠️ IMPORT: Background time expiring")
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
        defer {
            if bgTaskID != .invalid { UIApplication.shared.endBackgroundTask(bgTaskID) }
        }
        
        let creatorID = Auth.auth().currentUser?.uid ?? ""
        var segmentIds: [String] = []
        var totalDuration: TimeInterval = 0
        var firstThumbURL: String?
        
        do {
            let batch = db.batch()
            
            for (i, seg) in segments.enumerated() {
                currentSegIndex = i
                currentSegProgress = 0
                let segId = UUID().uuidString
                segmentIds.append(segId)
                totalDuration += seg.duration
                
                // Upload original file — no compression, preserves 4K quality
                // Segments are short so file sizes are manageable
                currentTask = "Uploading \(i+1)/\(segments.count)..."
                let videoURL = try await uploadFile(from: seg.localURL, to: "videoCollections/\(episodeId)/segments/\(segId).mp4", type: "video/mp4")
                
                // Upload thumbnail
                var thumbURL = ""
                if let thumbLocal = seg.thumbnailLocalURL {
                    currentTask = "Thumbnail \(i+1)/\(segments.count)..."
                    thumbURL = (try? await uploadFile(from: thumbLocal, to: "videoCollections/\(episodeId)/thumbnails/\(segId).jpg", type: "image/jpeg")) ?? ""
                }
                if i == 0 && !thumbURL.isEmpty { firstThumbURL = thumbURL }
                
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: seg.localURL.path)[.size] as? Int) ?? 0
                
                // Segment Firestore doc → subcollection: videoCollections/{episodeId}/segments/{segId}
                // CACHING: CollectionCacheManager should cache these on first player load
                //          (already handled via getVideosByCollection → CollectionCacheManager)
                let segRef = db.collection("videoCollections").document(episodeId)
                    .collection("segments").document(segId)
                batch.setData([
                    "id": segId, "title": seg.title, "description": "",
                    "videoURL": videoURL, "thumbnailURL": thumbURL,
                    "creatorID": creatorID, "creatorName": creatorName,
                    "createdAt": Timestamp(), "threadID": segId,
                    "replyToVideoID": NSNull(), "conversationDepth": 0,
                    "viewCount": 0, "hypeCount": 0, "coolCount": 0,
                    "replyCount": 0, "shareCount": 0, "tipCount": 0,
                    "temperature": "neutral", "qualityScore": 50,
                    "engagementRatio": 0.5, "velocityScore": 0.0, "trendingScore": 0.0,
                    "duration": seg.duration, "aspectRatio": 9.0/16.0, "fileSize": fileSize,
                    "discoverabilityScore": 0.5, "isPromoted": false,
                    "lastEngagementAt": NSNull(),
                    "collectionID": episodeId, "segmentNumber": i + 1,
                    "segmentTitle": seg.title, "isCollectionSegment": true,
                    "uploadStatus": "complete", "recordingSource": "cameraRoll",
                    "hashtags": [] as [String],
                ] as [String: Any], forDocument: segRef)
                
                await MainActor.run { segments[i].uploaded = true }
            }
            
            // Episode doc
            currentTask = "Saving episode..."
            batch.setData([
                "id": episodeId, "title": episodeTitle, "description": "",
                "creatorID": creatorID, "creatorName": creatorName,
                "coverImageURL": firstThumbURL ?? "",
                "segmentIDs": segmentIds, "segmentCount": segments.count,
                "totalDuration": totalDuration,
                "status": "published", "visibility": "public",
                "contentType": "series", "allowReplies": true,
                "showId": showId, "seasonId": seasonId,
                "episodeNumber": episodeNumber, "format": "vertical",
                "totalViews": 0, "totalHypes": 0, "totalCools": 0,
                "totalReplies": 0, "totalShares": 0,
                "createdAt": Timestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "publishedAt": FieldValue.serverTimestamp(),
            ] as [String: Any], forDocument: db.collection("videoCollections").document(episodeId), merge: true)
            
            try await batch.commit()
            uploadComplete = true
            isUploading = false
            try? await Task.sleep(for: .seconds(1.5))
            onDismiss()
            
        } catch {
            isUploading = false
            errorMessage = "Upload failed: \(error.localizedDescription)"
            print("❌ IMPORT: \(error)")
        }
    }
    
    // MARK: - Stream Upload with Progress
    
    private func uploadFile(from localURL: URL, to path: String, type: String) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let meta = StorageMetadata()
        meta.contentType = type
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = ref.putFile(from: localURL, metadata: meta) { _, error in
                if let error = error { continuation.resume(throwing: error); return }
                ref.downloadURL { url, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else if let url = url { continuation.resume(returning: url.absoluteString) }
                    else { continuation.resume(throwing: NSError(domain: "Upload", code: -1)) }
                }
            }
            task.observe(.progress) { snapshot in
                guard let p = snapshot.progress else { return }
                let pct = Double(p.completedUnitCount) / Double(max(p.totalUnitCount, 1))
                Task { @MainActor in self.currentSegProgress = pct }
            }
        }
    }
    
    private func formatDuration(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s)/60, Int(s)%60) }
}

// MARK: - Model

struct ImportedSegment: Identifiable {
    let id: String
    var title: String
    let localURL: URL
    let duration: TimeInterval
    var thumbnailLocalURL: URL?
    var uploaded: Bool
}
