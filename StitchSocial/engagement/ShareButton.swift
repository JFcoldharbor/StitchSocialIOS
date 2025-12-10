//
//  ShareButton.swift
//  StitchSocial
//
//  Layer 8: Views/Components - Share Button
//  Features: Share current video with watermark to other apps
//

import SwiftUI

// MARK: - Share Button

struct ShareButton: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    let size: ButtonSize
    
    @ObservedObject private var shareService = ShareService.shared
    
    enum ButtonSize {
        case small   // 24pt icon
        case medium  // 28pt icon (default)
        case large   // 32pt icon
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 28
            case .large: return 32
            }
        }
        
        var spinnerScale: CGFloat {
            switch self {
            case .small: return 0.8
            case .medium: return 1.0
            case .large: return 1.2
            }
        }
    }
    
    init(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil,
        size: ButtonSize = .medium
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
        self.size = size
    }
    
    var body: some View {
        Button(action: shareVideo) {
            ZStack {
                if shareService.isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(size.spinnerScale)
                } else {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .font(.system(size: size.iconSize))
                        .foregroundColor(.white)
                }
            }
            .frame(width: size.iconSize + 16, height: size.iconSize + 16)
        }
        .disabled(shareService.isExporting)
        .contentShape(Rectangle())
    }
    
    private func shareVideo() {
        shareService.shareVideo(
            video: video,
            creatorUsername: creatorUsername,
            threadID: threadID
        )
    }
}

// MARK: - Share Button with Label

struct ShareButtonWithLabel: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    
    @ObservedObject private var shareService = ShareService.shared
    
    init(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
    }
    
    var body: some View {
        Button(action: shareVideo) {
            VStack(spacing: 4) {
                ZStack {
                    if shareService.isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                
                Text(shareService.isExporting ? "..." : "Share")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .disabled(shareService.isExporting)
    }
    
    private func shareVideo() {
        shareService.shareVideo(
            video: video,
            creatorUsername: creatorUsername,
            threadID: threadID
        )
    }
}

// MARK: - Compact Share Button (for tight spaces)

struct CompactShareButton: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    
    @ObservedObject private var shareService = ShareService.shared
    
    init(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
    }
    
    var body: some View {
        Button(action: shareVideo) {
            Group {
                if shareService.isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.black.opacity(0.4))
            .clipShape(Circle())
        }
        .disabled(shareService.isExporting)
    }
    
    private func shareVideo() {
        shareService.shareVideo(
            video: video,
            creatorUsername: creatorUsername,
            threadID: threadID
        )
    }
}

// MARK: - Share Export Overlay

struct ShareExportOverlay: View {
    @ObservedObject var shareService = ShareService.shared
    
    var body: some View {
        Group {
            if shareService.isExporting {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text(shareService.exportProgress)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("This may take a moment...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(40)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shareService.isExporting)
    }
}

// MARK: - View Modifier for Share Overlay

struct ShareOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            ShareExportOverlay()
        }
    }
}

extension View {
    func shareOverlay() -> some View {
        modifier(ShareOverlayModifier())
    }
}

