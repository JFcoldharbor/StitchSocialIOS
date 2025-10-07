//
//  VideoService+Discovery.swift
//  StitchSocial
//
//  Fast Discovery-specific methods for parent-only loading
//

import Foundation
import FirebaseFirestore

// MARK: - VideoService Discovery Extension

extension VideoService {
    
    // MARK: - Fast Discovery Loading (Parent Videos Only)
    
    /// Get discovery parent threads only - ULTRA FAST for Discovery feed
    func getDiscoveryParentThreadsOnly(
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        print("🚀 DISCOVERY SERVICE: Loading \(limit) parent threads only")
        
        // Query for parent threads only (conversationDepth = 0)
        var query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        // Convert documents to ThreadData - PARENT ONLY (no children loading)
        for document in snapshot.documents {
            let data = document.data()
            let parentVideo = createCoreVideoMetadata(from: data, id: document.documentID)
            
            // Create ThreadData with NO CHILDREN (instant loading)
            let thread = ThreadData(
                id: parentVideo.id,
                parentVideo: parentVideo,
                childVideos: [] // Empty - load lazily if needed
            )
            
            threads.append(thread)
        }
        
        let hasMore = snapshot.documents.count >= limit
        
        print("✅ DISCOVERY SERVICE: Loaded \(threads.count) parent threads in fast mode")
        return (threads: threads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }
    
    /// Get trending discovery threads (fallback for empty feeds)
    func getTrendingDiscoveryThreads(limit: Int = 20) async throws -> [ThreadData] {
        
        print("📈 DISCOVERY SERVICE: Loading trending threads")
        
        // Query for hot/trending parent threads
        let query = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
            .whereField(FirebaseSchema.VideoDocument.temperature, in: ["hot", "blazing", "warm"])
            .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let parentVideo = createCoreVideoMetadata(from: data, id: document.documentID)
            
            let thread = ThreadData(
                id: parentVideo.id,
                parentVideo: parentVideo,
                childVideos: [] // Empty - load lazily if needed
            )
            
            threads.append(thread)
        }
        
        print("✅ DISCOVERY SERVICE: Loaded \(threads.count) trending threads")
        return threads
    }
    
    /// Get recent discovery threads by category
    func getDiscoveryThreadsByCategory(
        category: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (threads: [ThreadData], lastDocument: DocumentSnapshot?, hasMore: Bool) {
        
        print("🎯 DISCOVERY SERVICE: Loading \(category) category threads")
        
        var query: Query
        
        switch category.lowercased() {
        case "trending":
            query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .whereField(FirebaseSchema.VideoDocument.temperature, in: ["hot", "blazing"])
                .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
                .limit(to: limit)
            
        case "recent":
            query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
            
        case "popular":
            query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
                .limit(to: limit)
            
        default: // "all"
            query = db.collection(FirebaseSchema.Collections.videos)
                .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
                .limit(to: limit)
        }
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        var threads: [ThreadData] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let parentVideo = createCoreVideoMetadata(from: data, id: document.documentID)
            
            let thread = ThreadData(
                id: parentVideo.id,
                parentVideo: parentVideo,
                childVideos: []
            )
            
            threads.append(thread)
        }
        
        let hasMore = snapshot.documents.count >= limit
        
        print("✅ DISCOVERY SERVICE: Loaded \(threads.count) \(category) threads")
        return (threads: threads, lastDocument: snapshot.documents.last, hasMore: hasMore)
    }
    
    // MARK: - Lazy Child Loading for Discovery
    
    /// Load children for a specific thread when needed (for fullscreen mode)
    func loadDiscoveryThreadChildren(threadID: String) async throws -> [CoreVideoMetadata] {
        
        print("🔄 DISCOVERY SERVICE: Loading children for thread \(threadID)")
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.threadID, isEqualTo: threadID)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isGreaterThan: 0)
            .order(by: FirebaseSchema.VideoDocument.createdAt)
            .getDocuments()
        
        let children = snapshot.documents.map { document in
            createCoreVideoMetadata(from: document.data(), id: document.documentID)
        }
        
        print("✅ DISCOVERY SERVICE: Loaded \(children.count) children for thread \(threadID)")
        return children
    }
    
    // MARK: - Discovery Performance Optimizations
    
    /// Get discovery feed with smart batching
    func getOptimizedDiscoveryFeed(
        batchSize: Int = 10,
        totalVideos: Int = 50
    ) async throws -> [CoreVideoMetadata] {
        
        print("⚡ DISCOVERY SERVICE: Loading optimized feed (\(totalVideos) videos in \(batchSize)-video batches)")
        
        var allVideos: [CoreVideoMetadata] = []
        var lastDoc: DocumentSnapshot?
        
        let batches = (totalVideos + batchSize - 1) / batchSize // Ceiling division
        
        for batchNum in 1...batches {
            let remainingVideos = totalVideos - allVideos.count
            let currentBatchSize = min(batchSize, remainingVideos)
            
            guard currentBatchSize > 0 else { break }
            
            print("📦 DISCOVERY SERVICE: Loading batch \(batchNum)/\(batches) (\(currentBatchSize) videos)")
            
            let result = try await getDiscoveryParentThreadsOnly(
                limit: currentBatchSize,
                lastDocument: lastDoc
            )
            
            let batchVideos = result.threads.map { $0.parentVideo }
            allVideos.append(contentsOf: batchVideos)
            lastDoc = result.lastDocument
            
            if !result.hasMore {
                print("📭 DISCOVERY SERVICE: No more content available")
                break
            }
        }
        
        print("✅ DISCOVERY SERVICE: Optimized feed complete - \(allVideos.count) videos loaded")
        return allVideos
    }
    
    // MARK: - Discovery Cache Integration
    
    /// Load discovery feed with cache fallback
    func getCachedDiscoveryFeed(
        cacheKey: String,
        limit: Int = 20,
        maxCacheAge: TimeInterval = 300 // 5 minutes
    ) async throws -> [CoreVideoMetadata] {
        
        // TODO: Integrate with CachingService when available
        // For now, just load fresh content
        
        print("🗄️ DISCOVERY SERVICE: Cache integration pending - loading fresh content")
        
        let result = try await getDiscoveryParentThreadsOnly(limit: limit)
        return result.threads.map { $0.parentVideo }
    }
}

// MARK: - Discovery Helper Extensions

extension VideoService {
    
    /// Convert discovery category to optimized query
    private func getQueryForDiscoveryCategory(_ category: String) -> Query {
        let baseQuery = db.collection(FirebaseSchema.Collections.videos)
            .whereField(FirebaseSchema.VideoDocument.conversationDepth, isEqualTo: 0)
        
        switch category.lowercased() {
        case "trending":
            return baseQuery
                .whereField(FirebaseSchema.VideoDocument.temperature, in: ["hot", "blazing"])
                .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
        case "recent":
            return baseQuery
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
        case "popular":
            return baseQuery
                .order(by: FirebaseSchema.VideoDocument.hypeCount, descending: true)
        default:
            return baseQuery
                .order(by: FirebaseSchema.VideoDocument.createdAt, descending: true)
        }
    }
    
    /// Create lightweight ThreadData for discovery
    private func createDiscoveryThread(from document: DocumentSnapshot) -> ThreadData {
        let data = document.data() ?? [:]
        let parentVideo = createCoreVideoMetadata(from: data, id: document.documentID)
        
        return ThreadData(
            id: parentVideo.id,
            parentVideo: parentVideo,
            childVideos: [] // Always empty for discovery
        )
    }
}
