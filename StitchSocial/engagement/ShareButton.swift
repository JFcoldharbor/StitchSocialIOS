//
//  ShareButton.swift
//  StitchSocial
//
//  Layer 8: Views/Components - Share Button
//  Tap = regular share, Long press = sheet to pick regular or promo
//  FIXED: UserTier passed from EnvironmentObject, not from AuthService()
//

import SwiftUI
import FirebaseAuth

// MARK: - Share Mode Picker Sheet

struct ShareModeSheet: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    let userTier: UserTier
    @ObservedObject var shareService: ShareService
    @Environment(\.dismiss) private var dismiss
    
    private var isFounder: Bool {
        userTier == .founder || userTier == .coFounder
    }
    
    private var isCreator: Bool {
        video.creatorID == (Auth.auth().currentUser?.uid ?? "")
    }
    
    private var canPromo: Bool {
        (isFounder || isCreator) && (isFounder || video.hypeCount >= 100)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
            
            Text("Share Video")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 16)
                .padding(.bottom, 20)
            
            // Regular share
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    shareService.shareVideo(
                        video: video,
                        creatorUsername: creatorUsername,
                        threadID: threadID,
                        promoMode: false
                    )
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.cyan)
                        .frame(width: 44, height: 44)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Regular Share")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Watermark only · Clean for reposting")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            
            Divider().background(Color.gray.opacity(0.2)).padding(.horizontal, 20)
            
            // Promo share
            Button {
                guard canPromo else { return }
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    shareService.shareVideo(
                        video: video,
                        creatorUsername: creatorUsername,
                        threadID: threadID,
                        promoMode: true
                    )
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 22))
                        .foregroundColor(canPromo ? .orange : .gray)
                        .frame(width: 44, height: 44)
                        .background((canPromo ? Color.orange : Color.gray).opacity(0.12))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Promo Share")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(canPromo ? .white : .gray)
                            
                            if !canPromo {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange.opacity(0.6))
                            }
                        }
                        
                        Text(promoSubtext)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .disabled(!canPromo)
            
            Spacer()
        }
        .frame(height: 260)
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }
    
    private var promoSubtext: String {
        if isFounder { return "30s promo · Stats overlay · Founder access" }
        if canPromo { return "30s promo · Views · Hype · Temperature" }
        return "Unlocks at 100 🔥 on your videos"
    }
}

// MARK: - Share Button

struct ShareButton: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    let size: ButtonSize
    let userTier: UserTier
    
    @ObservedObject private var shareService = ShareService.shared
    @State private var showShareSheet = false
    
    enum ButtonSize {
        case small, medium, large
        
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
        size: ButtonSize = .medium,
        userTier: UserTier = .founder
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
        self.size = size
        self.userTier = userTier
    }
    
    var body: some View {
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
        .contentShape(Rectangle())
        .disabled(shareService.isExporting)
        .onTapGesture {
            guard !shareService.isExporting else { return }
            shareService.shareVideo(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                promoMode: false
            )
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showShareSheet = true
        }
        .sheet(isPresented: $showShareSheet) {
            ShareModeSheet(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                userTier: userTier,
                shareService: shareService
            )
        }
    }
}

// MARK: - Share Button with Label

struct ShareButtonWithLabel: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    let userTier: UserTier
    
    @ObservedObject private var shareService = ShareService.shared
    @State private var showShareSheet = false
    
    init(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil,
        userTier: UserTier = .founder
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
        self.userTier = userTier
    }
    
    var body: some View {
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
        .disabled(shareService.isExporting)
        .onTapGesture {
            guard !shareService.isExporting else { return }
            shareService.shareVideo(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                promoMode: false
            )
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showShareSheet = true
        }
        .sheet(isPresented: $showShareSheet) {
            ShareModeSheet(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                userTier: userTier,
                shareService: shareService
            )
        }
    }
}

// MARK: - Compact Share Button

struct CompactShareButton: View {
    let video: CoreVideoMetadata
    let creatorUsername: String
    let threadID: String?
    let userTier: UserTier
    
    @ObservedObject private var shareService = ShareService.shared
    @State private var showShareSheet = false
    
    init(
        video: CoreVideoMetadata,
        creatorUsername: String,
        threadID: String? = nil,
        userTier: UserTier = .founder
    ) {
        self.video = video
        self.creatorUsername = creatorUsername
        self.threadID = threadID
        self.userTier = userTier
    }
    
    var body: some View {
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
        .disabled(shareService.isExporting)
        .onTapGesture {
            guard !shareService.isExporting else { return }
            shareService.shareVideo(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                promoMode: false
            )
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showShareSheet = true
        }
        .sheet(isPresented: $showShareSheet) {
            ShareModeSheet(
                video: video,
                creatorUsername: creatorUsername,
                threadID: threadID,
                userTier: userTier,
                shareService: shareService
            )
        }
    }
}

// MARK: - Share Export Overlay

struct ShareExportOverlay: View {
    @ObservedObject var shareService = ShareService.shared
    
    var body: some View {
        ZStack {
            if shareService.isExporting {
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
                .transition(.opacity)
            }
            
            if shareService.promoLocked {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                        Text("Promo share unlocks at 100 🔥")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .overlay(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shareService.promoLocked)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shareService.isExporting)
    }
}

// MARK: - View Modifier

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
