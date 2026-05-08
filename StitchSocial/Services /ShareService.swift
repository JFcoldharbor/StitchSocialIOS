//
//  ShareService.swift
//  StitchSocial
//
//  Created by James Garmon on 12/8/25.
//


//
//  ShareService.swift
//  StitchSocial
//
//  Layer 4: Services - Video Sharing
//  Features: Share watermarked videos, promo clips, and thread collages to other apps
//  UPDATED: Added collage mode — presents ThreadCollageSelectionView via published state
//

import Foundation
import UIKit
import SwiftUI

/// Service to handle sharing videos to other apps
class ShareService: ObservableObject {
    
    static let shared = ShareService()
    
    @Published var isExporting: Bool = false
    @Published var exportProgress: String = ""
    @Published var showShareSheet: Bool = false
    @Published var promoLocked: Bool = false
    
    /// Collage mode — set threadData and flip to true to present ThreadCollageSelectionView
    @Published var showCollageSelection: Bool = false
    @Published var collageThreadData: ThreadData?
    
    private var currentShareURL: URL?
    private var currentShareItems: [Any] = []
    
    private let watermarkService = VideoWatermarkService.shared
    private let promoExporter = PromoVideoExporter.shared
    
    private init() {}
    
    // MARK: - Share Video
    
    func shareVideo(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil,
        promoMode: Bool = false,
        from viewController: UIViewController? = nil
    ) {
        guard let videoURL = URL(string: video.videoURL) else {
            #if DEBUG
            print("❌ SHARE: Invalid video URL")
            #endif
            return
        }
        
        isExporting = true
        exportProgress = promoMode ? "Building promo..." : "Preparing video..."
        
        // Download first (checks disk cache)
        downloadVideoIfNeeded(from: videoURL) { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.exportProgress = ""
                }
                return
            }
            
            if promoMode {
                // Promo mode → 30s clip with stats via PromoVideoExporter
                DispatchQueue.main.async {
                    self.exportProgress = "Building 30s promo..."
                }
                
                let stats = PromoVideoExporter.PromoStats(
                    viewCount: video.viewCount,
                    hypeCount: video.hypeCount,
                    coolCount: video.coolCount,
                    temperature: video.temperature
                )
                
                self.promoExporter.exportPromo(
                    sourceURL: localURL,
                    creatorUsername: creatorUsername,
                    stats: stats
                ) { [weak self] result in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isExporting = false
                        self.exportProgress = ""
                        
                        switch result {
                        case .success(let promoURL):
                            self.presentShareSheet(
                                videoURL: promoURL,
                                video: video,
                                creatorUsername: creatorUsername,
                                threadID: threadID,
                                from: viewController
                            )
                        case .failure(let error):
                            #if DEBUG
                            print("❌ SHARE: Promo export failed — \(error.localizedDescription)")
                            #endif
                            // Fallback to regular share
                            self.shareRegular(
                                localURL: localURL,
                                video: video,
                                creatorUsername: creatorUsername,
                                threadID: threadID,
                                viewController: viewController
                            )
                        }
                    }
                }
            } else {
                // Regular share → watermark only
                self.shareRegular(
                    localURL: localURL,
                    video: video,
                    creatorUsername: creatorUsername,
                    threadID: threadID,
                    viewController: viewController
                )
            }
        }
    }
    
    private func shareRegular(
        localURL: URL,
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String?,
        viewController: UIViewController?
    ) {
        DispatchQueue.main.async {
            self.exportProgress = "Adding watermark..."
        }
        
        watermarkService.exportWithWatermark(
            sourceURL: localURL,
            creatorUsername: creatorUsername
        ) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isExporting = false
                self.exportProgress = ""
                
                switch result {
                case .success(let watermarkedURL):
                    self.presentShareSheet(
                        videoURL: watermarkedURL,
                        video: video,
                        creatorUsername: creatorUsername,
                        threadID: threadID,
                        from: viewController
                    )
                    
                case .failure(let error):
                    #if DEBUG
                    print("❌ SHARE: Watermark failed - \(error.localizedDescription)")
                    #endif
                    self.presentShareSheet(
                        videoURL: localURL,
                        video: video,
                        creatorUsername: creatorUsername,
                        threadID: threadID,
                        from: viewController
                    )
                }
            }
        }
    }
    
    // MARK: - Share Thread Collage
    
    /// Launch collage selection UI for a thread
    /// CACHING: Uses pre-loaded ThreadData — zero extra Firestore reads.
    /// If ThreadData isn't loaded yet, caller should fetch via VideoService.getCompleteThread()
    /// and cache the result before calling this.
    func shareCollage(threadData: ThreadData) {
        self.collageThreadData = threadData
        self.showCollageSelection = true
        #if DEBUG
        print("🎬 SHARE: Launching collage selection for thread \(threadData.id) (\(threadData.childVideos.count) replies)")
        #endif
    }
    
    /// Share a completed collage video file
    /// Called by ThreadCollageSelectionView after build completes
    func shareCompletedCollage(
        collageURL: URL,
        creatorUsername: String,
        threadID: String,
        from viewController: UIViewController? = nil
    ) {
        let shareText = "Check out this thread collage by @\(creatorUsername) on StitchSocial!"
            + "\n\nstitch://thread/\(threadID)"
            + "\n\nDownload StitchSocial: https://apps.apple.com/app/stitchsocial"
        
        currentShareURL = collageURL
        currentShareItems = [collageURL, shareText]
        
        let activityVC = UIActivityViewController(
            activityItems: currentShareItems,
            applicationActivities: nil
        )
        
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .print
        ]
        
        activityVC.completionWithItemsHandler = { [weak self] activityType, completed, _, _ in
            if completed {
                #if DEBUG
                print("✅ SHARE: Collage shared via \(activityType?.rawValue ?? "unknown")")
                #endif
            }
            if let url = self?.currentShareURL {
                try? FileManager.default.removeItem(at: url)
            }
            self?.currentShareURL = nil
            self?.currentShareItems = []
        }
        
        let presenter = viewController ?? Self.topViewController()
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presenter?.present(activityVC, animated: true)
        #if DEBUG
        print("📤 SHARE: Presenting collage share sheet")
        #endif
    }
    
    /// Dismiss collage selection
    func dismissCollageSelection() {
        showCollageSelection = false
        collageThreadData = nil
    }
    
    // MARK: - Download Video
    
    private func downloadVideoIfNeeded(from url: URL, completion: @escaping (URL?) -> Void) {
        // If it's already a local file, use it directly
        if url.isFileURL {
            completion(url)
            return
        }
        
        // Check disk cache — avoid re-downloading videos we already played
        if let cachedURL = VideoDiskCache.shared.getCachedURL(for: url.absoluteString) {
            #if DEBUG
            print("✅ SHARE: Using disk-cached video")
            #endif
            completion(cachedURL)
            return
        }
        
        #if DEBUG
        print("📥 SHARE: Downloading video...")
        #endif
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                #if DEBUG
                print("❌ SHARE: Download failed - \(error.localizedDescription)")
                #endif
                completion(nil)
                return
            }
            
            guard let localURL = localURL else {
                #if DEBUG
                print("❌ SHARE: No local URL after download")
                #endif
                completion(nil)
                return
            }
            
            // Move to temp location with proper extension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("download_\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            
            do {
                try FileManager.default.moveItem(at: localURL, to: tempURL)
                #if DEBUG
                print("✅ SHARE: Video downloaded to \(tempURL)")
                #endif
                completion(tempURL)
            } catch {
                #if DEBUG
                print("❌ SHARE: Failed to move downloaded file - \(error)")
                #endif
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    // MARK: - Present Share Sheet
    
    private func presentShareSheet(
        videoURL: URL,
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String?,
        from viewController: UIViewController?
    ) {
        currentShareURL = videoURL
        
        // Create share text with deep link
        var shareText = "Check out this video by @\(creatorUsername) on StitchSocial!"
        
        if let threadID = threadID {
            // Add deep link (you'll need to configure your URL scheme)
            shareText += "\n\nstitch://thread/\(threadID)"
        }
        
        // Add App Store link (replace with actual link when published)
        shareText += "\n\nDownload StitchSocial: https://apps.apple.com/app/stitchsocial"
        
        currentShareItems = [videoURL, shareText]
        
        // Present share sheet
        let activityVC = UIActivityViewController(
            activityItems: currentShareItems,
            applicationActivities: nil
        )
        
        // Exclude some activity types that don't make sense
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .print
        ]
        
        // Completion handler
        activityVC.completionWithItemsHandler = { [weak self] activityType, completed, items, error in
            if completed {
                #if DEBUG
                print("✅ SHARE: Shared via \(activityType?.rawValue ?? "unknown")")
                #endif
            }
            
            // Cleanup temp file
            if let url = self?.currentShareURL {
                try? FileManager.default.removeItem(at: url)
            }
            self?.currentShareURL = nil
            self?.currentShareItems = []
        }
        
        // Get the presenting view controller
        let presenter = viewController ?? Self.topViewController()
        
        // iPad support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presenter?.present(activityVC, animated: true)
        #if DEBUG
        print("📤 SHARE: Presenting share sheet")
        #endif
    }
    
    // MARK: - Helper to get top view controller
    
    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        
        return topController
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        watermarkService.cleanupTempFiles()
        promoExporter.cleanupTempFiles()
        
        if let url = currentShareURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentShareURL = nil
        currentShareItems = []
    }
}
