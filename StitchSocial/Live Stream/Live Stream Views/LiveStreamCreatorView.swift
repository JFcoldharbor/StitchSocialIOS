//
//  LiveStreamCreatorView.swift
//  StitchSocial
//
//  Layer 8: Views - Live Stream Creator Experience
//  Dependencies: LiveStreamService, StreamQueueService, StreamCoinService
//  Features: Stream controls, video comment queue, timer, viewer count,
//            coin total, end stream, duration progress
//

import SwiftUI
import AgoraRtcKit
import AVFoundation

struct LiveStreamCreatorView: View {
    
    // MARK: - Properties
    
    let creatorID: String
    let tier: StreamDurationTier
    
    @ObservedObject private var streamService = LiveStreamService.shared
    @ObservedObject private var queueService = StreamQueueService.shared
    @ObservedObject private var coinService = StreamCoinService.shared
    @ObservedObject private var agoraService = AgoraStreamService.shared
    @ObservedObject private var chatService = StreamChatService.shared
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var localViewHolder = AgoraVideoViewHolder()
    @State private var showingQueue = false
    @State private var showingEndConfirm = false
    @State private var isStarting = true
    @State private var streamStartError: String?
    @State private var creatorChatText = ""
    @State private var previewingComment: VideoComment?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // FULLSCREEN camera — edge to edge
            AgoraLocalVideoRepresentable(localView: localViewHolder.view)
                .ignoresSafeArea()
            
            if isStarting {
                startingView
            } else {
                // All overlays float on top of camera
                VStack(spacing: 0) {
                    // Top bar: LIVE pill, timer, viewers
                    topOverlay
                    
                    // Duration progress
                    durationProgressBar
                    
                    Spacer()
                    
                    // Chat messages (bottom left) + right side buttons
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(chatService.messages.suffix(6)) { msg in
                                creatorChatRow(msg)
                            }
                            
                            if chatService.messages.isEmpty {
                                chatBubble("System", streamService.viewerCount > 0
                                    ? "👋 \(streamService.viewerCount) watching"
                                    : "Waiting for viewers...")
                            }
                        }
                        .padding(.leading, 12)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.6, alignment: .leading)
                        
                        Spacer()
                        
                        // Right side buttons (vertical)
                        rightSideControls
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    
                    // Creator chat input + end button
                    creatorInputBar
                }
                
                // Active PiP overlay (top right)
                if let pip = queueService.activePiP {
                    pipOverlay(pip)
                }
                
                // Queue panel (slides up from bottom)
                if showingQueue {
                    queueOverlay
                }
            }
        }
        .statusBarHidden(true)
        .task {
            await startStream()
        }
        .alert("End Stream?", isPresented: $showingEndConfirm) {
            Button("Keep Streaming", role: .cancel) { }
            Button("End", role: .destructive) {
                Task { await endStream() }
            }
        } message: {
            let remaining = (streamService.activeStream?.durationTier.durationSeconds ?? 0) - streamService.elapsedSeconds
            if remaining > 0 {
                Text("You have \(remaining / 60) min left. Ending early won't count as a full completion for your next tier unlock.")
            } else {
                Text("Great stream! This will count as a full completion.")
            }
        }
        .sheet(item: $previewingComment) { comment in
            VideoPreviewSheet(comment: comment, onAccept: {
                Task {
                    try? await queueService.acceptComment(
                        commentID: comment.id,
                        communityID: creatorID,
                        streamID: streamService.activeStream?.id ?? ""
                    )
                }
                previewingComment = nil
            }, onReject: {
                Task {
                    try? await queueService.rejectComment(
                        commentID: comment.id,
                        communityID: creatorID,
                        streamID: streamService.activeStream?.id ?? ""
                    )
                }
                previewingComment = nil
            })
        }
    }
    
    // MARK: - Top Overlay
    
    private var topOverlay: some View {
        HStack {
            // Live pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                Text("LIVE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.red)
            .cornerRadius(10)
            
            // Timer
            Text(formatTime(streamService.elapsedSeconds))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
            
            Spacer()
            
            // Viewers
            HStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                Text(formatCount(streamService.viewerCount))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
            
            // Coins earned
            HStack(spacing: 4) {
                Text("🪙")
                    .font(.system(size: 10))
                Text(formatCount(streamService.collectiveCoinsTotal))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
            
            // Hype counter (aggregate from all viewers)
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.system(size: 10))
                Text(formatCount(streamService.activeStream?.hypeCount ?? 0))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }
    
    // MARK: - Right Side Controls (vertical stack like TikTok)
    
    private var rightSideControls: some View {
        VStack(spacing: 16) {
            // Flip camera
            Button { agoraService.flipCamera() } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            
            // Mute
            Button { agoraService.toggleMute() } label: {
                Image(systemName: agoraService.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 18))
                    .foregroundColor(agoraService.isMuted ? .red : .white)
                    .frame(width: 44, height: 44)
                    .background(agoraService.isMuted ? Color.red.opacity(0.3) : Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            
            // Queue
            Button {
                withAnimation(.spring(response: 0.3)) { showingQueue.toggle() }
            } label: {
                ZStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                    
                    if queueService.queueCount > 0 {
                        Text("\(queueService.queueCount)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.pink)
                            .clipShape(Circle())
                            .offset(x: 14, y: -14)
                    }
                }
            }
        }
    }
    
    // MARK: - Creator Chat Row
    
    private func creatorChatRow(_ msg: StreamChatMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if msg.isCreator {
                Text("👑")
                    .font(.system(size: 9))
            }
            
            Text("@\(msg.authorUsername)")
                .font(.system(size: 11, weight: msg.isCreator ? .heavy : .bold))
                .foregroundColor(msg.isCreator ? .cyan : .white)
            
            Text(msg.body)
                .font(.system(size: 11))
                .foregroundColor(msg.isGift ? .yellow : (msg.isFreeHype ? .orange : .white.opacity(0.7)))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            msg.isGift
                ? Color.yellow.opacity(0.15)
                : Color.black.opacity(0.5)
        )
        .cornerRadius(10)
    }
    
    // MARK: - Creator Input Bar (chat + end)
    
    private var creatorInputBar: some View {
        HStack(spacing: 10) {
            // Chat input
            TextField("Reply to chat...", text: $creatorChatText)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .cornerRadius(19)
                .onSubmit { sendCreatorChat() }
            
            if !creatorChatText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { sendCreatorChat() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                }
            }
            
            // End stream button
            Button { showingEndConfirm = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("End")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.8))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
    
    private func sendCreatorChat() {
        let text = creatorChatText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let stream = streamService.activeStream else { return }
        creatorChatText = ""
        
        chatService.sendMessage(
            communityID: creatorID,
            streamID: stream.id,
            authorID: creatorID,
            authorUsername: stream.creatorID,
            authorDisplayName: stream.creatorID,
            authorLevel: 0,
            isCreator: true,
            body: text
        )
    }
    
    // MARK: - PiP Overlay (real video playback)
    
    private func pipOverlay(_ pip: VideoComment) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack(alignment: .bottomLeading) {
                    // Real video player
                    if let url = URL(string: pip.videoURL) {
                        PiPVideoPlayer(url: url)
                            .frame(width: 130, height: 180)
                            .cornerRadius(14)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.12))
                            .frame(width: 130, height: 180)
                            .overlay(Text("📹").font(.system(size: 24)).opacity(0.5))
                    }
                    
                    // Author label
                    HStack(spacing: 4) {
                        Text("@\(pip.authorUsername)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Text("Lv\(pip.authorLevel)")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 8)
                // Tap to dismiss PiP
                .onTapGesture {
                    queueService.dismissPiP()
                }
                .padding(.trailing, 12)
                .padding(.bottom, 130)
            }
        }
    }
    
    // MARK: - Queue Overlay (slides up)
    
    private var queueOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)
                
                queuePanel
            }
            .background(Color.black.opacity(0.85))
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
        }
        .transition(.move(edge: .bottom))
    }
    
    // MARK: - Starting View
    
    private var startingView: some View {
        VStack(spacing: 20) {
            if let error = streamStartError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    
                    Text("Couldn't Start Stream")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    
                    Button { dismiss() } label: {
                        Text("Go Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(14)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.cyan)
                    
                    Text("Starting \(tier.displayName) Stream...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(tier.emoji) \(tier.durationDisplay) max")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    // MARK: - Duration Progress Bar
    
    private var durationProgressBar: some View {
        let progress = streamService.activeStream?.durationProgress ?? 0
        let tierSeconds = tier.durationSeconds
        let elapsed = streamService.elapsedSeconds
        let remaining = max(0, tierSeconds - elapsed)
        
        return HStack(spacing: 8) {
            Text(tier.emoji)
                .font(.system(size: 12))
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            progress >= 1.0
                                ? LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * min(progress, 1.0))
                        .animation(.easeInOut(duration: 1.0), value: progress)
                }
            }
            .frame(height: 5)
            
            Text(remaining > 0 ? "\(remaining / 60)m left" : "✅ Complete!")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(remaining > 0 ? .white.opacity(0.4) : .green)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Queue Panel
    
    private var queuePanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text("📹 Video Comments")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(queueService.queueCount) pending")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.pink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.pink.opacity(0.15))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // Queue items
            if queueService.pendingComments.isEmpty {
                VStack(spacing: 8) {
                    Text("No video comments yet")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queueService.pendingComments) { comment in
                            queueItemRow(comment)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(white: 0.06))
    }
    
    // MARK: - Queue Item Row
    
    private func queueItemRow(_ comment: VideoComment) -> some View {
        HStack(spacing: 10) {
            // Thumbnail — tap to preview video
            Button { previewingComment = comment } label: {
                ZStack {
                    if let thumbURL = comment.thumbnailURL, let url = URL(string: thumbURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(white: 0.12)
                        }
                    } else {
                        LinearGradient(colors: [Color(white: 0.1), Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    
                    // Play icon
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 48, height: 64)
                .cornerRadius(10)
                .overlay(
                    Text("0:\(String(format: "%02d", comment.durationSeconds))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.black.opacity(0.7)).cornerRadius(4)
                        .frame(maxWidth: 48, maxHeight: 64, alignment: .bottomTrailing)
                        .padding(3)
                )
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(comment.authorUsername)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Lv \(comment.authorLevel)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(4)
                    
                    if comment.isPriority {
                        Text("⚡ PRIORITY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                if !comment.caption.isEmpty {
                    Text(comment.caption)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
                
                Text(timeAgo(comment.submittedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 6) {
                // Accept
                Button {
                    Task {
                        try? await queueService.acceptComment(
                            commentID: comment.id,
                            communityID: creatorID,
                            streamID: streamService.activeStream?.id ?? ""
                        )
                    }
                } label: {
                    Text("✓")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(10)
                }
                
                // Reject
                Button {
                    Task {
                        try? await queueService.rejectComment(
                            commentID: comment.id,
                            communityID: creatorID,
                            streamID: streamService.activeStream?.id ?? ""
                        )
                    }
                } label: {
                    Text("✕")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(10)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    comment.isPriority
                        ? Color.yellow.opacity(0.05)
                        : Color.white.opacity(0.04)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            comment.isPriority
                                ? Color.yellow.opacity(0.2)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Helpers
    
    private func chatBubble(_ name: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("@\(name)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    private func startStream() async {
        do {
            // Check if already recovered an active stream (re-entering)
            if streamService.activeStream == nil {
                _ = try await streamService.startStream(
                    creatorID: creatorID,
                    tier: tier
                )
            }
            
            // Start/rejoin Agora broadcast — channel name = streamID
            if let stream = streamService.activeStream {
                // Start chat listener
                chatService.startListening(communityID: creatorID, streamID: stream.id)
                
                try await agoraService.startBroadcast(
                    channelName: stream.id,
                    localVideoView: localViewHolder.view
                )
                
                // Sync Agora viewer count → LiveStreamService
                agoraService.onViewerCountChanged = { count in
                    streamService.viewerCount = count
                }
                
                queueService.listenToQueue(
                    communityID: creatorID,
                    streamID: stream.id
                )
                coinService.startFlushTimer(
                    communityID: creatorID,
                    streamID: stream.id
                )
            }
            
            isStarting = false
        } catch {
            streamStartError = error.localizedDescription
        }
    }
    
    private func endStream() async {
        guard let stream = streamService.activeStream else { return }
        
        // Leave Agora channel
        agoraService.leaveChannel()
        
        chatService.cleanup()
        queueService.onStreamEnd()
        await coinService.onStreamEnd(communityID: creatorID, streamID: stream.id)
        
        _ = try? await streamService.endStream(creatorID: creatorID)
        dismiss()
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return "\(count)"
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

// MARK: - Agora Local Video UIViewRepresentable

struct AgoraLocalVideoRepresentable: UIViewRepresentable {
    let localView: UIView
    
    func makeUIView(context: Context) -> UIView {
        localView.backgroundColor = .black
        return localView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Video Preview Sheet (Creator previews before accept/reject)

struct VideoPreviewSheet: View {
    let comment: VideoComment
    let onAccept: () -> Void
    let onReject: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Video Reply Preview")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        Text("@\(comment.authorUsername) • Lv \(comment.authorLevel)")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                // Video player
                if let url = URL(string: comment.videoURL) {
                    PiPVideoPlayer(url: url)
                        .aspectRatio(9/16, contentMode: .fit)
                        .cornerRadius(18)
                        .padding(.horizontal, 40)
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(white: 0.1))
                        .aspectRatio(9/16, contentMode: .fit)
                        .overlay(Text("Video unavailable").foregroundColor(.white.opacity(0.3)))
                        .padding(.horizontal, 40)
                }
                
                // Caption
                if !comment.caption.isEmpty {
                    Text("\"\(comment.caption)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()
                }
                
                // Info
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("⏱").font(.system(size: 12))
                        Text("\(comment.durationSeconds)s").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    }
                    if comment.isPriority {
                        HStack(spacing: 4) {
                            Text("⚡").font(.system(size: 12))
                            Text("PRIORITY").font(.system(size: 10, weight: .bold)).foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.15)).cornerRadius(8)
                    }
                }
                
                Spacer()
                
                // Accept / Reject buttons
                HStack(spacing: 16) {
                    Button {
                        onReject()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            Text("Reject")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
                        .cornerRadius(16)
                    }
                    
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                            Text("Show on Stream")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - PiP Video Player (AVPlayer in UIViewRepresentable)

struct PiPVideoPlayer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PiPPlayerUIView {
        PiPPlayerUIView(url: url)
    }
    
    func updateUIView(_ uiView: PiPPlayerUIView, context: Context) {}
}

class PiPPlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        
        player = AVPlayer(url: url)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        playerLayer = layer
        player?.play()
        
        // Loop playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    deinit {
        player?.pause()
        NotificationCenter.default.removeObserver(self)
    }
}
