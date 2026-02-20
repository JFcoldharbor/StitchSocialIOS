//
//  CollectionService.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Collection Management Service
//  Dependencies: Firebase Firestore, FirebaseSchema, CoreCollectionMetadata, CollectionDraft, CollectionProgress
//  Features: Draft management, publishing, segment ordering, progress tracking
//  CREATED: Collections feature for long-form segmented content
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Complete collection management service
/// Handles drafts, publishing, segments, and watch progress
@MainActor
class CollectionService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Published State
    
    @Published var isLoading: Bool = false
    @Published var lastError: CollectionServiceError?
    
    // MARK: - Constants
    
    private let maxSegmentsPerCollection = 50
    private let minSegmentsPerCollection = 2
    private let maxDraftsPerUser = 10
    private let draftExpirationDays = 30
    
    // MARK: - Initialization
    
    init() {
        print("📚 COLLECTION SERVICE: Initialized")
    }
    
    // MARK: - Draft Management
    
    /// Creates a new collection draft
    func createDraft(
        creatorID: String,
        title: String? = nil,
        description: String? = nil,
        visibility: CollectionVisibility = .publicVisible,
        allowReplies: Bool = true
    ) async throws -> CollectionDraft {
        
        isLoading = true
        defer { isLoading = false }
        
        // Check draft limit
        let existingDrafts = try await loadUserDrafts(creatorID: creatorID)
        guard existingDrafts.count < maxDraftsPerUser else {
            throw CollectionServiceError.draftLimitReached(maxDraftsPerUser)
        }
        
        let draftID = generateDraftID(creatorID: creatorID)
        
        let draft = CollectionDraft(
            id: draftID,
            creatorID: creatorID,
            title: title,
            description: description,
            visibility: visibility,
            allowReplies: allowReplies,
            segments: [],
            createdAt: Date(),
            lastModifiedAt: Date(),
            autoSavedAt: Date()
        )
        
        // Save to Firestore
        let draftData = encodeDraft(draft)
        try await db.collection("collectionDrafts").document(draftID).setData(draftData)
        
        print("📝 COLLECTION SERVICE: Draft created - \(draftID)")
        return draft
    }
    
    /// Saves/updates a draft
    func saveDraft(_ draft: CollectionDraft) async throws {
        isLoading = true
        defer { isLoading = false }
        
        var updatedDraft = draft
        updatedDraft.lastModifiedAt = Date()
        updatedDraft.autoSavedAt = Date()
        
        let draftData = encodeDraft(updatedDraft)
        try await db.collection("collectionDrafts").document(draft.id).setData(draftData, merge: true)
        
        print("💾 COLLECTION SERVICE: Draft saved - \(draft.id)")
    }
    
    /// Loads a specific draft
    func loadDraft(draftID: String) async throws -> CollectionDraft? {
        let document = try await db.collection("collectionDrafts").document(draftID).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return decodeDraft(from: data, id: draftID)
    }
    
    /// Loads all drafts for a user
    func loadUserDrafts(creatorID: String) async throws -> [CollectionDraft] {
        let snapshot = try await db.collection("collectionDrafts")
            .whereField("creatorID", isEqualTo: creatorID)
            .order(by: "lastModifiedAt", descending: true)
            .getDocuments()
        
        let drafts = snapshot.documents.compactMap { doc -> CollectionDraft? in
            decodeDraft(from: doc.data(), id: doc.documentID)
        }
        
        print("📂 COLLECTION SERVICE: Loaded \(drafts.count) drafts for user \(creatorID)")
        return drafts
    }
    
    /// Deletes a draft
    func deleteDraft(draftID: String) async throws {
        try await db.collection("collectionDrafts").document(draftID).delete()
        print("🗑️ COLLECTION SERVICE: Draft deleted - \(draftID)")
    }
    
    // MARK: - Segment Management
    
    /// Adds a segment to a draft
    func addSegmentToDraft(
        draftID: String,
        segment: SegmentDraft
    ) async throws -> CollectionDraft {
        
        guard var draft = try await loadDraft(draftID: draftID) else {
            throw CollectionServiceError.draftNotFound(draftID)
        }
        
        guard draft.segments.count < maxSegmentsPerCollection else {
            throw CollectionServiceError.segmentLimitReached(maxSegmentsPerCollection)
        }
        
        draft.addSegment(segment)
        try await saveDraft(draft)
        
        print("➕ COLLECTION SERVICE: Segment added to draft \(draftID)")
        return draft
    }
    
    /// Updates a segment in a draft
    func updateSegmentInDraft(
        draftID: String,
        segment: SegmentDraft
    ) async throws -> CollectionDraft {
        
        guard var draft = try await loadDraft(draftID: draftID) else {
            throw CollectionServiceError.draftNotFound(draftID)
        }
        
        draft.updateSegment(segment)
        try await saveDraft(draft)
        
        print("✏️ COLLECTION SERVICE: Segment updated in draft \(draftID)")
        return draft
    }
    
    /// Removes a segment from a draft
    func removeSegmentFromDraft(
        draftID: String,
        segmentID: String
    ) async throws -> CollectionDraft {
        
        guard var draft = try await loadDraft(draftID: draftID) else {
            throw CollectionServiceError.draftNotFound(draftID)
        }
        
        draft.removeSegment(id: segmentID)
        try await saveDraft(draft)
        
        print("➖ COLLECTION SERVICE: Segment removed from draft \(draftID)")
        return draft
    }
    
    /// Reorders segments in a draft
    func reorderSegments(
        draftID: String,
        newOrder: [String]
    ) async throws -> CollectionDraft {
        
        guard var draft = try await loadDraft(draftID: draftID) else {
            throw CollectionServiceError.draftNotFound(draftID)
        }
        
        draft.reorderSegments(newOrder)
        try await saveDraft(draft)
        
        print("🔄 COLLECTION SERVICE: Segments reordered in draft \(draftID)")
        return draft
    }
    
    // MARK: - Publishing
    
    /// Publishes a collection from draft - CREATES VIDEO DOCUMENTS FOR EACH SEGMENT
    func publishCollection(
        draft: CollectionDraft,
        segmentVideoIDs: [String],
        totalDuration: TimeInterval,
        creatorName: String,
        coverImageData: Data? = nil,
        coverImageUploader: ((Data, String) async throws -> String)? = nil
    ) async throws -> VideoCollection {
        
        isLoading = true
        defer { isLoading = false }
        
        // Validate draft
        let validation = draft.validateForPublishing()
        guard validation.isValid else {
            throw CollectionServiceError.validationFailed(validation.errors)
        }
        
        // Generate collection ID FIRST so we can use it for cover upload
        let collectionID = generateCollectionID()
        
        // Upload cover image if provided
        var uploadedCoverURL: String? = nil
        if let coverData = coverImageData, let uploader = coverImageUploader {
            do {
                uploadedCoverURL = try await uploader(coverData, collectionID)
                print("📸 COLLECTION SERVICE: Cover photo uploaded for \(collectionID)")
            } catch {
                print("⚠️ COLLECTION SERVICE: Cover upload failed, using fallback: \(error)")
            }
        }
        
        var createdVideoIDs: [String] = []
        
        print("📚 COLLECTION SERVICE: Publishing collection with \(draft.segments.count) segments")
        
        // Create video documents for each segment
        for (index, segment) in draft.segments.enumerated() {
            // Ensure segment has uploaded URLs
            guard let videoURL = segment.uploadedVideoURL, !videoURL.isEmpty else {
                print("⚠️ COLLECTION SERVICE: Segment \(index) missing video URL")
                throw CollectionServiceError.validationFailed(["Segment \(index + 1) not uploaded"])
            }
            
            let videoID = UUID().uuidString
            let segmentNumber = index + 1
            
            // Create video document data
            let videoData: [String: Any] = [
                "id": videoID,
                "title": segment.title ?? "Part \(segmentNumber)",
                "description": "",
                "videoURL": videoURL,
                "thumbnailURL": segment.thumbnailURL ?? "",
                "creatorID": draft.creatorID,
                "creatorName": creatorName,
                "createdAt": Timestamp(date: Date()),
                
                // Collection-specific fields - IMPORTANT: marks this as a collection segment
                "collectionID": collectionID,
                "segmentNumber": segmentNumber,
                "segmentTitle": segment.title ?? "Part \(segmentNumber)",
                "isCollectionSegment": true,  // KEY: Distinguishes from regular threads/stitches
                
                // Thread fields - each segment can have replies
                "threadID": videoID,
                "conversationDepth": 0,
                "replyToVideoID": NSNull(),  // Not a reply to anything
                
                // Engagement (start at 0)
                "viewCount": 0,
                "hypeCount": 0,
                "coolCount": 0,
                "replyCount": 0,
                "shareCount": 0,
                
                // Milestone tracking
                "firstHypeReceived": false,
                "firstCoolReceived": false,
                "milestone10Reached": false,
                "milestone400Reached": false,
                "milestone1000Reached": false,
                "milestone15000Reached": false,
                
                // Metadata
                "duration": segment.duration ?? 0,
                "aspectRatio": segment.aspectRatio ?? 9.0/16.0,
                "fileSize": segment.fileSize ?? 0,
                "qualityScore": 50,
                "temperature": "neutral",
                "discoverabilityScore": 0.5,
                "isPromoted": false,
                "isDeleted": false
            ]
            
            // Save to Firestore videos collection
            try await db.collection("videos").document(videoID).setData(videoData)
            createdVideoIDs.append(videoID)
            
            print("✅ COLLECTION SERVICE: Created segment video \(segmentNumber)/\(draft.segments.count) - \(videoID)")
        }
        
        // Determine cover image priority:
        // 1. Uploaded cover photo (user selected)
        // 2. Draft's existing cover URL (if editing)
        // 3. First segment thumbnail (fallback)
        let finalCoverImageURL: String?
        if let uploaded = uploadedCoverURL, !uploaded.isEmpty {
            finalCoverImageURL = uploaded
            print("📸 COLLECTION SERVICE: Using uploaded cover photo")
        } else if let draftCover = draft.coverImageURL, !draftCover.isEmpty {
            finalCoverImageURL = draftCover
            print("📸 COLLECTION SERVICE: Using draft cover photo")
        } else {
            finalCoverImageURL = draft.segments.first?.thumbnailURL
            print("📸 COLLECTION SERVICE: Using first segment thumbnail as cover")
        }
        
        // Create the collection document
        let collection = VideoCollection(
            id: collectionID,
            title: draft.title ?? "Untitled Collection",
            description: draft.description ?? "",
            creatorID: draft.creatorID,
            creatorName: creatorName,
            coverImageURL: finalCoverImageURL,
            segmentIDs: createdVideoIDs, // Use the actual video document IDs we just created
            segmentCount: draft.segments.count,
            totalDuration: totalDuration,
            status: .published,
            visibility: draft.visibility,
            allowReplies: draft.allowReplies,
            publishedAt: Date(),
            createdAt: draft.createdAt,
            updatedAt: Date(),
            totalViews: 0,
            totalHypes: 0,
            totalCools: 0,
            totalReplies: 0,
            totalShares: 0
        )
        
        // Save collection
        let collectionData = encodeCollection(collection)
        try await db.collection("videoCollections").document(collectionID).setData(collectionData)
        
        // Delete the draft
        try await deleteDraft(draftID: draft.id)
        
        print("🎉 COLLECTION SERVICE: Collection published - \(collectionID) with \(createdVideoIDs.count) video documents")
        return collection
    }
    
    /// Unpublishes a collection (archives it)
    func unpublishCollection(collectionID: String) async throws {
        try await db.collection("videoCollections").document(collectionID).updateData([
            "status": CollectionStatus.archived.rawValue,
            "updatedAt": Timestamp()
        ])
        
        print("📦 COLLECTION SERVICE: Collection archived - \(collectionID)")
    }
    
    /// Archives a collection
    func archiveCollection(collectionID: String) async throws {
        try await unpublishCollection(collectionID: collectionID)
    }
    
    /// Soft-delete a collection — sets status to deleted, hides from all feeds.
    /// Does NOT delete segment videos (they remain as standalone videos).
    func deleteCollection(collectionID: String) async throws {
        try await db.collection("videoCollections").document(collectionID).updateData([
            "status": "deleted",
            "updatedAt": FieldValue.serverTimestamp()
        ])
        print("🗑️ COLLECTION SERVICE: Collection deleted - \(collectionID)")
    }
    
    // MARK: - Reading Collections
    
    /// Gets a single collection by ID
    func getCollection(id: String) async throws -> VideoCollection? {
        let document = try await db.collection("videoCollections").document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return decodeCollection(from: data, id: id)
    }
    
    /// Gets all segments (videos) for a collection
    func getCollectionSegments(collectionID: String) async throws -> [CoreVideoMetadata] {
        let snapshot = try await db.collection("videos")
            .whereField("collectionID", isEqualTo: collectionID)
            .order(by: "segmentNumber")
            .getDocuments()
        
        // This would need VideoService to decode, so we return the raw data
        // In practice, you'd inject VideoService or have a shared decoder
        print("📼 COLLECTION SERVICE: Found \(snapshot.documents.count) segments for collection \(collectionID)")
        
        // Return empty for now - actual implementation would decode videos
        return []
    }
    
    /// Gets collections for a specific user
    func getUserCollections(
        userID: String,
        includeArchived: Bool = false,
        limit: Int = 20
    ) async throws -> [VideoCollection] {
        
        var query = db.collection("videoCollections")
            .whereField("creatorID", isEqualTo: userID)
        
        if !includeArchived {
            query = query.whereField("status", isEqualTo: CollectionStatus.published.rawValue)
        }
        
        let snapshot = try await query
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let collections = snapshot.documents.compactMap { doc -> VideoCollection? in
            decodeCollection(from: doc.data(), id: doc.documentID)
        }
        
        print("📚 COLLECTION SERVICE: Loaded \(collections.count) collections for user \(userID)")
        return collections
    }
    
    /// Gets collections for discovery feed
    func getDiscoveryCollections(limit: Int = 50) async throws -> [VideoCollection] {
        let snapshot = try await db.collection("videoCollections")
            .whereField("status", isEqualTo: CollectionStatus.published.rawValue)
            .whereField("visibility", isEqualTo: CollectionVisibility.publicVisible.rawValue)
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let collections = snapshot.documents.compactMap { doc -> VideoCollection? in
            decodeCollection(from: doc.data(), id: doc.documentID)
        }
        
        print("🔍 COLLECTION SERVICE: Loaded \(collections.count) discovery collections")
        return collections
    }
    
    // MARK: - Progress Tracking
    
    /// Gets watch progress for a user and collection
    func getWatchProgress(
        userID: String,
        collectionID: String
    ) async throws -> CollectionProgress? {
        
        let progressID = "\(userID)_\(collectionID)"
        let document = try await db.collection("collectionProgress").document(progressID).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        return decodeProgress(from: data, id: progressID)
    }
    
    /// Updates watch progress
    func updateWatchProgress(_ progress: CollectionProgress) async throws {
        let progressData = encodeProgress(progress)
        try await db.collection("collectionProgress").document(progress.id).setData(progressData, merge: true)
        
        print("📊 COLLECTION SERVICE: Progress updated for \(progress.collectionID)")
    }
    
    /// Marks a segment as complete
    func markSegmentComplete(
        userID: String,
        collectionID: String,
        segmentID: String,
        totalSegments: Int
    ) async throws -> CollectionProgress {
        
        var progress = try await getWatchProgress(userID: userID, collectionID: collectionID)
        
        if progress == nil {
            progress = CollectionProgress.startWatching(
                userID: userID,
                collectionID: collectionID,
                firstSegmentID: segmentID
            )
        }
        
        progress!.markSegmentCompleted(segmentID)
        progress!.updatePercentComplete(totalSegments: totalSegments)
        
        try await updateWatchProgress(progress!)
        
        print("✅ COLLECTION SERVICE: Segment marked complete - \(segmentID)")
        return progress!
    }
    
    // MARK: - Encoding/Decoding
    
    private func encodeDraft(_ draft: CollectionDraft) -> [String: Any] {
        var data: [String: Any] = [
            "id": draft.id,
            "creatorID": draft.creatorID,
            "visibility": draft.visibility.rawValue,
            "allowReplies": draft.allowReplies,
            "createdAt": Timestamp(date: draft.createdAt),
            "lastModifiedAt": Timestamp(date: draft.lastModifiedAt),
            "autoSavedAt": Timestamp(date: draft.autoSavedAt)
        ]
        
        if let title = draft.title { data["title"] = title }
        if let description = draft.description { data["description"] = description }
        if let coverImageURL = draft.coverImageURL { data["coverImageURL"] = coverImageURL }
        
        // Encode segments
        let segmentsData = draft.segments.map { segment -> [String: Any] in
            var segmentData: [String: Any] = [
                "id": segment.id,
                "order": segment.order,
                "uploadProgress": segment.uploadProgress,
                "uploadStatus": segment.uploadStatus.rawValue,
                "addedAt": Timestamp(date: segment.addedAt)
            ]
            
            if let localVideoPath = segment.localVideoPath { segmentData["localVideoPath"] = localVideoPath }
            if let uploadedVideoURL = segment.uploadedVideoURL { segmentData["uploadedVideoURL"] = uploadedVideoURL }
            if let thumbnailURL = segment.thumbnailURL { segmentData["thumbnailURL"] = thumbnailURL }
            if let title = segment.title { segmentData["title"] = title }
            if let description = segment.description { segmentData["description"] = description }
            if let duration = segment.duration { segmentData["duration"] = duration }
            if let fileSize = segment.fileSize { segmentData["fileSize"] = fileSize }
            if let uploadError = segment.uploadError { segmentData["uploadError"] = uploadError }
            
            return segmentData
        }
        
        data["segments"] = segmentsData
        
        return data
    }
    
    private func decodeDraft(from data: [String: Any], id: String) -> CollectionDraft? {
        guard let creatorID = data["creatorID"] as? String,
              let visibilityRaw = data["visibility"] as? String,
              let visibility = CollectionVisibility(rawValue: visibilityRaw) else {
            return nil
        }
        
        let title = data["title"] as? String
        let description = data["description"] as? String
        let coverImageURL = data["coverImageURL"] as? String
        let allowReplies = data["allowReplies"] as? Bool ?? true
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let lastModifiedAt = (data["lastModifiedAt"] as? Timestamp)?.dateValue() ?? Date()
        let autoSavedAt = (data["autoSavedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        // Decode segments
        var segments: [SegmentDraft] = []
        if let segmentsData = data["segments"] as? [[String: Any]] {
            for segmentData in segmentsData {
                if let segment = decodeSegmentDraft(from: segmentData) {
                    segments.append(segment)
                }
            }
        }
        
        return CollectionDraft(
            id: id,
            creatorID: creatorID,
            title: title,
            description: description,
            coverImageURL: coverImageURL,
            visibility: visibility,
            allowReplies: allowReplies,
            segments: segments,
            createdAt: createdAt,
            lastModifiedAt: lastModifiedAt,
            autoSavedAt: autoSavedAt
        )
    }
    
    private func decodeSegmentDraft(from data: [String: Any]) -> SegmentDraft? {
        guard let id = data["id"] as? String,
              let order = data["order"] as? Int,
              let statusRaw = data["uploadStatus"] as? String,
              let status = SegmentUploadStatus(rawValue: statusRaw) else {
            return nil
        }
        
        return SegmentDraft(
            id: id,
            order: order,
            localVideoPath: data["localVideoPath"] as? String,
            uploadedVideoURL: data["uploadedVideoURL"] as? String,
            thumbnailURL: data["thumbnailURL"] as? String,
            uploadProgress: data["uploadProgress"] as? Double ?? 0.0,
            uploadStatus: status,
            uploadError: data["uploadError"] as? String,
            title: data["title"] as? String,
            description: data["description"] as? String,
            duration: data["duration"] as? TimeInterval,
            fileSize: data["fileSize"] as? Int64,
            addedAt: (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func encodeCollection(_ collection: VideoCollection) -> [String: Any] {
        var data: [String: Any] = [
            "id": collection.id,
            "title": collection.title,
            "description": collection.description,
            "creatorID": collection.creatorID,
            "creatorName": collection.creatorName,
            "segmentIDs": collection.segmentIDs,
            "segmentCount": collection.segmentCount,
            "totalDuration": collection.totalDuration,
            "status": collection.status.rawValue,
            "visibility": collection.visibility.rawValue,
            "allowReplies": collection.allowReplies,
            "createdAt": Timestamp(date: collection.createdAt),
            "updatedAt": Timestamp(date: collection.updatedAt),
            "totalViews": collection.totalViews,
            "totalHypes": collection.totalHypes,
            "totalCools": collection.totalCools,
            "totalReplies": collection.totalReplies,
            "totalShares": collection.totalShares
        ]
        
        if let coverImageURL = collection.coverImageURL {
            data["coverImageURL"] = coverImageURL
        }
        
        if let publishedAt = collection.publishedAt {
            data["publishedAt"] = Timestamp(date: publishedAt)
        }
        
        return data
    }
    
    private func decodeCollection(from data: [String: Any], id: String) -> VideoCollection? {
        guard let title = data["title"] as? String,
              let creatorID = data["creatorID"] as? String,
              let creatorName = data["creatorName"] as? String,
              let segmentIDs = data["segmentIDs"] as? [String],
              let statusRaw = data["status"] as? String,
              let status = CollectionStatus(rawValue: statusRaw),
              let visibilityRaw = data["visibility"] as? String,
              let visibility = CollectionVisibility(rawValue: visibilityRaw) else {
            return nil
        }
        
        return VideoCollection(
            id: id,
            title: title,
            description: data["description"] as? String ?? "",
            creatorID: creatorID,
            creatorName: creatorName,
            coverImageURL: data["coverImageURL"] as? String,
            segmentIDs: segmentIDs,
            segmentCount: data["segmentCount"] as? Int ?? segmentIDs.count,
            totalDuration: data["totalDuration"] as? TimeInterval ?? 0,
            status: status,
            visibility: visibility,
            allowReplies: data["allowReplies"] as? Bool ?? true,
            publishedAt: (data["publishedAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            totalViews: data["totalViews"] as? Int ?? 0,
            totalHypes: data["totalHypes"] as? Int ?? 0,
            totalCools: data["totalCools"] as? Int ?? 0,
            totalReplies: data["totalReplies"] as? Int ?? 0,
            totalShares: data["totalShares"] as? Int ?? 0
        )
    }
    
    private func encodeProgress(_ progress: CollectionProgress) -> [String: Any] {
        return [
            "id": progress.id,
            "userID": progress.userID,
            "collectionID": progress.collectionID,
            "currentSegmentID": progress.currentSegmentID,
            "currentSegmentIndex": progress.currentSegmentIndex,
            "currentTimestamp": progress.currentTimestamp,
            "completedSegmentIDs": progress.completedSegmentIDs,
            "segmentProgress": progress.segmentProgress,
            "percentComplete": progress.percentComplete,
            "totalWatchTime": progress.totalWatchTime,
            "startedAt": Timestamp(date: progress.startedAt),
            "lastWatchedAt": Timestamp(date: progress.lastWatchedAt)
        ]
    }
    
    private func decodeProgress(from data: [String: Any], id: String) -> CollectionProgress? {
        guard let userID = data["userID"] as? String,
              let collectionID = data["collectionID"] as? String,
              let currentSegmentID = data["currentSegmentID"] as? String else {
            return nil
        }
        
        return CollectionProgress(
            userID: userID,
            collectionID: collectionID,
            currentSegmentID: currentSegmentID,
            currentSegmentIndex: data["currentSegmentIndex"] as? Int ?? 0,
            currentTimestamp: data["currentTimestamp"] as? TimeInterval ?? 0,
            completedSegmentIDs: data["completedSegmentIDs"] as? [String] ?? [],
            segmentProgress: data["segmentProgress"] as? [String: TimeInterval] ?? [:],
            percentComplete: data["percentComplete"] as? Double ?? 0,
            totalWatchTime: data["totalWatchTime"] as? TimeInterval ?? 0,
            startedAt: (data["startedAt"] as? Timestamp)?.dateValue() ?? Date(),
            lastWatchedAt: (data["lastWatchedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    // MARK: - ID Generation
    
    private func generateDraftID(creatorID: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let prefix = String(creatorID.prefix(4))
        return "draft_\(prefix)_\(timestamp)"
    }
    
    private func generateCollectionID() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "collection_\(timestamp)_\(random)"
    }
}

// MARK: - Collection Service Errors

enum CollectionServiceError: LocalizedError {
    case draftNotFound(String)
    case collectionNotFound(String)
    case draftLimitReached(Int)
    case segmentLimitReached(Int)
    case validationFailed([String])
    case publishingFailed(String)
    case unauthorized(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .draftNotFound(let id):
            return "Draft not found: \(id)"
        case .collectionNotFound(let id):
            return "Collection not found: \(id)"
        case .draftLimitReached(let limit):
            return "Maximum drafts reached (\(limit))"
        case .segmentLimitReached(let limit):
            return "Maximum segments reached (\(limit))"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.joined(separator: ", "))"
        case .publishingFailed(let message):
            return "Publishing failed: \(message)"
        case .unauthorized(let message):
            return "Unauthorized: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Extensions

extension CollectionService {
    
    /// Test service functionality
    func helloWorldTest() {
        print("📚 COLLECTION SERVICE: Hello World - Ready for collection management!")
        print("📚 Features: Draft CRUD, Segment management, Publishing, Progress tracking")
    }
}
