//
//  LiveStreamViewerView.swift
//  StitchSocial
//
//  Layer 8: Views - Live Stream Viewer Experience
//  Dependencies: LiveStreamService, StreamCoinService, StreamXPService,
//                StreamQueueService, CommunityTypes
//  Features: Stream player placeholder, chat overlay, hype storm,
//            PiP video comment, coin goal bar, idle warning, bottom bar
//

import SwiftUI
import AgoraRtcKit
import FirebaseFirestore
import AVFoundation

struct LiveStreamViewerView: View {
    
    // MARK: - Properties
    
    let userID: String
    let communityID: String
    let streamID: String
    let userLevel: Int
    
    @ObservedObject private var streamService = LiveStreamService.shared
    @ObservedObject private var coinService = StreamCoinService.shared
    @ObservedObject private var xpService = StreamXPService.shared
    @ObservedObject private var queueService = StreamQueueService.shared
    @ObservedObject private var agoraService = AgoraStreamService.shared
    @ObservedObject private var chatService = StreamChatService.shared
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var remoteViewHolder = AgoraVideoViewHolder()
    @State private var chatText = ""
    @State private var showingRecordSheet = false
    @State private var showingGiftTray = false
    @State private var showingRecap = false
    @State private var xpPopup: String?
    @State private var hypeAlerts: [HypeAlertItem] = []
    @State private var lastFreeHypeAt: Date = .distantPast
    @State private var freeHypeCount = 0
    @State private var pendingHypeTaps = 0
    @State private var isHypeFlushScheduled = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // FULLSCREEN remote video — edge to edge
            AgoraRemoteVideoRepresentable(remoteView: remoteViewHolder.view)
                .ignoresSafeArea()
            
            // Connecting state
            if !agoraService.remoteUserJoined {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 10) {
                            ProgressView().tint(.cyan)
                            Text("Connecting to stream...")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    )
            }
            
            // All overlays float on top
            VStack(spacing: 0) {
                // Top bar
                viewerTopOverlay
                
                // XP multiplier badge
                if coinService.activeMultiplier.isActive {
                    xpMultiplierBadge
                }
                
                // Coin goal bar (under top)
                if coinService.currentGoal != nil {
                    viewerCoinGoalBar
                        .padding(.top, 6)
                }
                
                Spacer()
                
                // Hype storm alerts (left side, middle area)
                hypeStormOverlay
                
                Spacer()
                
                // Chat + right side buttons
                HStack(alignment: .bottom, spacing: 0) {
                    // Chat messages (bottom left)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(chatService.messages.suffix(5)) { msg in
                            viewerChatRow(msg)
                        }
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.6, alignment: .leading)
                    
                    Spacer()
                    
                    // Right side action buttons (vertical)
                    viewerRightSideButtons
                        .padding(.trailing, 12)
                }
                .padding(.bottom, 8)
                
                // Bottom input bar
                viewerBottomInputBar
            }
            
            // PiP overlay
            if let pip = queueService.activePiP {
                pipOverlay(pip)
            }
            
            // XP popup
            if let popup = xpPopup {
                xpPopupView(popup)
            }
            
            // Idle warning
            if xpService.isIdle {
                idleWarningOverlay
            }
        }
        .statusBarHidden(true)
        .task {
            await joinStream()
        }
        .onDisappear {
            Task { await leaveStream() }
        }
        .sheet(isPresented: $showingRecordSheet) {
            VideoCommentRecordSheet(
                userID: userID,
                communityID: communityID,
                streamID: streamID,
                userLevel: userLevel
            )
        }
        .sheet(isPresented: $showingGiftTray) {
            GiftTrayView(
                userID: userID,
                communityID: communityID,
                streamID: streamID,
                userLevel: userLevel
            )
        }
        .sheet(isPresented: $showingRecap) {
            if let recap = xpService.postStreamRecap {
                PostStreamRecapView(recap: recap)
            }
        }
        .onChange(of: streamService.isStreaming) { _, isLive in
            if !isLive {
                Task {
                    _ = await xpService.viewerLeftStream(streamEnded: true)
                    showingRecap = true
                }
            }
        }
        .onChange(of: coinService.lastHypeAlert) { _, alert in
            if let alert {
                addHypeAlert(alert)
            }
        }
    }
    
    // MARK: - Viewer Top Overlay
    
    private var viewerTopOverlay: some View {
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
            
            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }
    
    // MARK: - XP Multiplier Badge
    
    private var xpMultiplierBadge: some View {
        HStack(spacing: 6) {
            Text("⚡")
                .font(.system(size: 12))
            Text("\(coinService.activeMultiplier.multiplier)x XP")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)
            Text("(\(coinService.activeMultiplier.remainingSeconds)s)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.cyan.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.top, 6)
    }
    
    // MARK: - Coin Goal Bar (floating)
    
    private var viewerCoinGoalBar: some View {
        Group {
            if let goal = coinService.currentGoal {
                VStack(spacing: 4) {
                    HStack {
                        Text("🪙 \(goal.displayName)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.yellow)
                        Spacer()
                        Text("\(streamService.collectiveCoinsTotal) / \(goal.threshold)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * coinService.goalProgress)
                                .animation(.easeInOut(duration: 0.5), value: coinService.goalProgress)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(10)
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Right Side Action Buttons (vertical, TikTok-style)
    
    private var viewerRightSideButtons: some View {
        VStack(spacing: 16) {
            // FREE HYPE — rapid tap, no cooldown, 0.12 XP per tap
            Button {
                sendFreeHype()
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.red.opacity(0.4))
                            .clipShape(Circle())
                            .scaleEffect(freeHypeCount > 0 && freeHypeCount % 5 == 0 ? 1.15 : 1.0)
                            .animation(.spring(response: 0.15), value: freeHypeCount)
                        
                        if freeHypeCount > 0 {
                            Text("\(freeHypeCount)")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .offset(x: 16, y: -16)
                        }
                    }
                    Text("Hype")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // GIFTS — long press or tap to open gift tray
            Button { showingGiftTray = true } label: {
                VStack(spacing: 4) {
                    Text("🎁")
                        .font(.system(size: 22))
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [.yellow.opacity(0.4), .orange.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(Circle())
                    Text("Gifts")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Video comment button
            Button { showingRecordSheet = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.5)
                        )
                        .clipShape(Circle())
                    Text("Reply")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .disabled(userLevel < VideoComment.minimumLevel)
            .opacity(userLevel < VideoComment.minimumLevel ? 0.4 : 1.0)
            
            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Free Hype (Rapid Tap)
    
    /// No cooldown. Tap as fast as you want. 0.12 XP per tap.
    /// Taps accumulate locally, batch-flushed every 5 seconds to avoid write spam.
    private var canFreeHype: Bool { true }
    
    private func sendFreeHype() {
        freeHypeCount += 1
        pendingHypeTaps += 1
        
        // 0.12 XP per tap — accumulated locally
        xpService.recordMicroInteraction(xp: 0.12)
        
        // Haptic — light for spam tapping
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Schedule batch flush if not already pending
        if !isHypeFlushScheduled {
            isHypeFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
                flushHypeTaps()
            }
        }
    }
    
    /// Batch flush accumulated hype taps to stream doc as atomic increment.
    /// Cost: 1 write per flush per viewer. No chat writes.
    /// 500 viewers × 1 write/5sec = 100 writes/sec — Firestore handles this fine.
    private func flushHypeTaps() {
        let taps = pendingHypeTaps
        guard taps > 0 else {
            isHypeFlushScheduled = false
            return
        }
        pendingHypeTaps = 0
        isHypeFlushScheduled = false
        
        // Atomic increment on stream doc — NOT chat
        let db = FirebaseConfig.firestore
        if let stream = streamService.activeStream {
            db.collection("communities")
                .document(communityID)
                .collection("streams")
                .document(stream.id)
                .updateData([
                    "hypeCount": FieldValue.increment(Int64(taps))
                ])
        }
    }
    
    // MARK: - Bottom Input Bar (floating)
    
    private var viewerBottomInputBar: some View {
        HStack(spacing: 10) {
            // Real chat input
            TextField("Say something...", text: $chatText)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 19)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(19)
                .onSubmit {
                    sendChat()
                }
            
            // Send button (visible when typing)
            if !chatText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    sendChat()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                }
            }
            
            // Coins total
            HStack(spacing: 4) {
                Text("🪙")
                    .font(.system(size: 11))
                Text(formatCount(streamService.collectiveCoinsTotal))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(16)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
    
    private func sendChat() {
        let text = chatText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        xpService.recordInteraction()
        chatText = ""
        
        chatService.sendMessage(
            communityID: communityID,
            streamID: streamID,
            authorID: userID,
            authorUsername: "You",
            authorDisplayName: "You",
            authorLevel: userLevel,
            isCreator: false,
            body: text
        )
    }
    
    // MARK: - Hype Storm Overlay
    
    private var hypeStormOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(hypeAlerts) { alert in
                HStack(spacing: 6) {
                    Text(alert.emoji)
                        .font(.system(size: 14))
                    Text("@\(alert.username)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text(alert.typeName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 16)
        .padding(.top, 100)
    }
    
    // MARK: - XP Popup
    
    private func xpPopupView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.green)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 16)
            .padding(.top, 110)
            .transition(.opacity)
    }
    
    // MARK: - PiP Overlay
    
    private func pipOverlay(_ comment: VideoComment) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.1), Color(white: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 175)
                        .overlay(
                            VStack {
                                Text("🧑")
                                    .font(.system(size: 32))
                                    .opacity(0.5)
                            }
                        )
                    
                    // ON AIR badge
                    Text("ON AIR")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2))
                        .cornerRadius(6)
                        .frame(maxWidth: 130, maxHeight: 175, alignment: .topLeading)
                        .padding(6)
                    
                    // Username
                    HStack(spacing: 4) {
                        Text("@\(comment.authorUsername)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Lv \(comment.authorLevel)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .frame(maxWidth: 130, maxHeight: 175, alignment: .bottomLeading)
                    .padding(8)
                }
                .frame(width: 130, height: 175)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan, lineWidth: 2.5)
                )
                .shadow(color: .cyan.opacity(0.3), radius: 12)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 80)
        }
    }
    
    
    private func viewerChatRow(_ msg: StreamChatMessage) -> some View {
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
                .foregroundColor(
                    msg.isGift ? .yellow :
                    msg.isFreeHype ? .orange :
                    msg.isSystem ? .white.opacity(0.4) :
                    .white.opacity(0.7)
                )
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            msg.isGift ? Color.yellow.opacity(0.15) : Color.black.opacity(0.5)
        )
        .cornerRadius(10)
    }
    
    private func chatBubble(name: String, text: String, isCreator: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("@\(name)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isCreator ? .purple : .white)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    
    // MARK: - Idle Warning Overlay
    
    private var idleWarningOverlay: some View {
        VStack(spacing: 16) {
            Text("👋 Still watching?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text("Tap anywhere to keep earning XP")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            
            Button {
                xpService.recordInteraction()
            } label: {
                Text("I'm here!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.cyan)
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
        .onTapGesture {
            xpService.recordInteraction()
        }
    }
    
    // MARK: - Actions
    
    private func joinStream() async {
        // Listen to stream updates
        streamService.listenToStream(creatorID: communityID, streamID: streamID)
        
        // Start chat listener
        chatService.startListening(communityID: communityID, streamID: streamID)
        
        // Join Agora as viewer — channel name = streamID
        try? await agoraService.joinAsViewer(
            channelName: streamID,
            remoteVideoView: remoteViewHolder.view
        )
        
        // Join as viewer in Firestore
        try? await streamService.viewerJoined(
            creatorID: communityID,
            streamID: streamID,
            userID: userID,
            userLevel: userLevel
        )
        
        // Send "joined" system message so creator sees it
        chatService.sendSystemMessage(
            communityID: communityID,
            streamID: streamID,
            body: "👋 Someone joined!"
        )
        
        // Start XP tracking
        if let stream = streamService.activeStream {
            await xpService.viewerJoinedStream(
                userID: userID,
                communityID: communityID,
                streamID: streamID,
                tier: stream.durationTier
            )
            
            showXPPopup("+\(stream.durationTier.baseXP) XP 🎯 Attending Live")
        }
        
        // Start coin flush timer
        coinService.startFlushTimer(communityID: communityID, streamID: streamID)
    }
    
    private func leaveStream() async {
        // Flush any pending hype taps
        flushHypeTaps()
        
        // Leave Agora channel
        agoraService.leaveChannel()
        
        chatService.cleanup()
        
        try? await streamService.viewerLeft(
            creatorID: communityID,
            streamID: streamID,
            userID: userID
        )
        
        _ = await xpService.viewerLeftStream()
        
        await coinService.onStreamEnd(communityID: communityID, streamID: streamID)
        streamService.removeStreamListener()
    }
    
    // MARK: - Helpers
    
    private func addHypeAlert(_ event: StreamHypeEvent) {
        let alert = HypeAlertItem(
            id: event.id,
            emoji: event.hypeType.emoji,
            username: event.senderUsername,
            typeName: event.hypeType.displayName
        )
        
        withAnimation(.spring(response: 0.4)) {
            hypeAlerts.append(alert)
        }
        
        // Remove after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                hypeAlerts.removeAll { $0.id == alert.id }
            }
        }
    }
    
    private func showXPPopup(_ text: String) {
        xpPopup = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            xpPopup = nil
        }
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
}

// MARK: - Hype Alert Item

struct HypeAlertItem: Identifiable {
    let id: String
    let emoji: String
    let username: String
    let typeName: String
}

// MARK: - Video Comment Record Sheet

struct VideoCommentRecordSheet: View {
    let userID: String
    let communityID: String
    let streamID: String
    let userLevel: Int
    
    @StateObject private var uploadService = VideoUploadService()
    @ObservedObject private var queueService = StreamQueueService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isPriority = false
    @State private var caption = ""
    @State private var recordedVideoURL: URL?
    @State private var isRecording = false
    @State private var recordingSeconds = 0
    @State private var recordTimer: Timer?
    @State private var submissionState: SubmissionState = .idle
    @State private var useFrontCamera = true
    
    private var maxClip: Int { VideoComment.maxClipSeconds(forLevel: userLevel) }
    
    enum SubmissionState: Equatable {
        case idle
        case recording
        case recorded
        case uploading
        case submitted
        case error(String)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header
                    Text("📹 Video Reply")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Record a clip to show on stream")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    
                    // Level gate
                    HStack(spacing: 6) {
                        Text("⭐").font(.system(size: 12))
                        Text("Lv \(userLevel) — Max \(maxClip)s")
                            .font(.system(size: 11)).foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(12)
                    
                    // Camera / Preview area
                    ZStack {
                        if let videoURL = recordedVideoURL {
                            // Show recorded video preview
                            VideoPreviewPlayer(url: videoURL)
                                .frame(height: 280)
                                .cornerRadius(18)
                        } else {
                            // Live camera preview
                            CameraPreviewView(useFrontCamera: useFrontCamera)
                                .frame(height: 280)
                                .cornerRadius(18)
                        }
                        
                        // Recording timer overlay
                        if submissionState == .recording {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.red).frame(width: 8, height: 8)
                                        Text("0:\(String(format: "%02d", recordingSeconds)) / 0:\(String(format: "%02d", maxClip))")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.red.opacity(0.7))
                                    .cornerRadius(8)
                                    .padding(10)
                                }
                                Spacer()
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(submissionState == .recording ? Color.red.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 2)
                    )
                    
                    // Controls
                    switch submissionState {
                    case .idle:
                        recordControls
                    case .recording:
                        recordingControls
                    case .recorded:
                        reviewControls
                    case .uploading:
                        uploadingView
                    case .submitted:
                        submittedView
                    case .error(let msg):
                        errorView(msg)
                    }
                    
                    Spacer()
                }
                .padding(20)
                .padding(.top, 16)
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Record Controls (idle)
    
    private var recordControls: some View {
        HStack(spacing: 24) {
            Button { dismiss() } label: {
                Text("✕").font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06)).clipShape(Circle())
                    .foregroundColor(.white)
            }
            
            Button { startRecording() } label: {
                ZStack {
                    Circle().stroke(Color.pink.opacity(0.4), lineWidth: 2.5).frame(width: 68, height: 68)
                    Circle().fill(Color.pink).frame(width: 60, height: 60)
                        .shadow(color: .pink.opacity(0.4), radius: 12)
                    Image(systemName: "video.fill").font(.system(size: 20)).foregroundColor(.white)
                }
            }
            
            Button { useFrontCamera.toggle() } label: {
                Image(systemName: "camera.rotate.fill").font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06)).clipShape(Circle())
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Recording Controls (active)
    
    private var recordingControls: some View {
        Button { stopRecording() } label: {
            ZStack {
                Circle().stroke(Color.red.opacity(0.6), lineWidth: 3).frame(width: 68, height: 68)
                RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 28, height: 28)
            }
        }
    }
    
    // MARK: - Review Controls (recorded, ready to submit)
    
    private var reviewControls: some View {
        VStack(spacing: 12) {
            // Caption input
            TextField("Add a caption...", text: $caption)
                .font(.system(size: 13)).foregroundColor(.white)
                .padding(.horizontal, 14).frame(height: 38)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            
            // Priority toggle
            Button { isPriority.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPriority ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isPriority ? .yellow : .white.opacity(0.3))
                    Text("Skip the queue")
                        .foregroundColor(.white.opacity(0.6))
                    Text("10 🪙")
                        .foregroundColor(.yellow).fontWeight(.bold)
                }
                .font(.system(size: 12))
                .padding(12).frame(maxWidth: .infinity)
                .background(isPriority ? Color.yellow.opacity(0.08) : Color.white.opacity(0.04))
                .cornerRadius(14)
            }
            
            HStack(spacing: 12) {
                // Retake
                Button {
                    recordedVideoURL = nil
                    submissionState = .idle
                } label: {
                    Text("Retake")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.white.opacity(0.08)).cornerRadius(14)
                }
                
                // Submit
                Button { submitVideo() } label: {
                    Text("Submit Reply")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.cyan).cornerRadius(14)
                }
            }
        }
    }
    
    // MARK: - Uploading
    
    private var uploadingView: some View {
        VStack(spacing: 12) {
            ProgressView(value: uploadService.uploadProgress)
                .tint(.cyan)
            Text("Uploading... \(Int(uploadService.uploadProgress * 100))%")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Submitted
    
    private var submittedView: some View {
        VStack(spacing: 12) {
            Text("✅ Submitted!")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.green)
            Text("Your video reply is in the queue. The creator will review it.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Color.white.opacity(0.08)).cornerRadius(14)
            }
        }
    }
    
    // MARK: - Error
    
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("❌ Upload Failed")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.red)
            Text(msg).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
            Button {
                submissionState = .recorded
            } label: {
                Text("Retry").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Color.white.opacity(0.08)).cornerRadius(14)
            }
        }
    }
    
    // MARK: - Recording Logic
    
    private func startRecording() {
        submissionState = .recording
        recordingSeconds = 0
        
        // Start recording via AVCaptureSession (handled by CameraPreviewView)
        NotificationCenter.default.post(name: .startVideoRecording, object: nil)
        
        recordTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                recordingSeconds += 1
                if recordingSeconds >= maxClip {
                    stopRecording()
                }
            }
        }
    }
    
    private func stopRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        
        // Stop recording — CameraPreviewView posts back the file URL
        NotificationCenter.default.post(name: .stopVideoRecording, object: nil)
        
        // CameraPreviewView will call back with URL via notification
        // For now set state — the URL gets set by the camera callback
        submissionState = .recorded
        
        // Temp file URL from camera (set by CameraPreviewView callback)
        // If CameraPreviewView isn't wired yet, use a temp placeholder
        if recordedVideoURL == nil {
            let tempDir = FileManager.default.temporaryDirectory
            recordedVideoURL = tempDir.appendingPathComponent("recorded_\(UUID().uuidString).mp4")
        }
    }
    
    // MARK: - Submit
    
    private func submitVideo() {
        guard let videoURL = recordedVideoURL else { return }
        submissionState = .uploading
        
        let commentID = UUID().uuidString
        
        Task {
            do {
                let duration = await VideoUploadService.clipDuration(url: videoURL)
                
                let (remoteVideoURL, thumbnailURL) = try await uploadService.uploadStreamClip(
                    localVideoURL: videoURL,
                    communityID: communityID,
                    streamID: streamID,
                    commentID: commentID
                )
                
                var comment = try await queueService.submitVideoComment(
                    streamID: streamID,
                    communityID: communityID,
                    authorID: userID,
                    authorUsername: "",
                    authorDisplayName: "",
                    authorLevel: userLevel,
                    videoURL: remoteVideoURL,
                    durationSeconds: duration > 0 ? duration : recordingSeconds,
                    caption: caption,
                    isPriority: isPriority,
                    priorityCoinsCost: isPriority ? 10 : 0
                )
                
                // Update thumbnail if generated
                if let thumb = thumbnailURL {
                    comment.thumbnailURL = thumb
                    try? await FirebaseConfig.firestore
                        .collection("communities/\(communityID)/streams/\(streamID)/videoComments")
                        .document(comment.id)
                        .updateData(["thumbnailURL": thumb])
                }
                
                submissionState = .submitted
            } catch {
                submissionState = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Camera + Video Player components in StreamVideoComponents.swift

// MARK: - Gift Tray View (replaces HypePickerSheet)
// Paid gifts only — free hype is handled by the main hype button tap

struct GiftTrayView: View {
    let userID: String
    let communityID: String
    let streamID: String
    let userLevel: Int
    
    @ObservedObject private var coinService = StreamCoinService.shared
    @ObservedObject private var hypeCoinService = HypeCoinService.shared
    @ObservedObject private var chatService = StreamChatService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var selectedGift: StreamHypeType?
    @State private var showConfirm = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Balance
                    HStack {
                        Text("Your Balance")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        HStack(spacing: 4) {
                            Text("🪙")
                                .font(.system(size: 14))
                            Text("\(hypeCoinService.balance?.availableCoins ?? 0)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(StreamHypeType.allCases, id: \.rawValue) { gift in
                                let canAfford = (hypeCoinService.balance?.availableCoins ?? 0) >= gift.coinCost
                                
                                Button {
                                    selectedGift = gift
                                    showConfirm = true
                                } label: {
                                    HStack(spacing: 14) {
                                        // Gift emoji
                                        Text(gift.emoji)
                                            .font(.system(size: 30))
                                            .frame(width: 50, height: 50)
                                            .background(giftColor(gift).opacity(0.15))
                                            .clipShape(Circle())
                                        
                                        // Info
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(gift.displayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text(giftDescription(gift))
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                        
                                        Spacer()
                                        
                                        // Cost
                                        HStack(spacing: 4) {
                                            Text("\(gift.coinCost)")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(canAfford ? .yellow : .red)
                                            Text("🪙")
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(canAfford ? Color.yellow.opacity(0.1) : Color.red.opacity(0.08))
                                        .cornerRadius(12)
                                    }
                                    .padding(14)
                                    .background(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(giftColor(gift).opacity(0.15), lineWidth: 1)
                                    )
                                    .cornerRadius(16)
                                }
                                .disabled(isSending || !canAfford)
                                .opacity(canAfford ? 1.0 : 0.5)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Send a Gift 🎁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .alert("Send Gift?", isPresented: $showConfirm) {
                Button("Cancel", role: .cancel) { selectedGift = nil }
                Button("Send \(selectedGift?.emoji ?? "") for \(selectedGift?.coinCost ?? 0) 🪙") {
                    if let gift = selectedGift {
                        sendGift(gift)
                    }
                }
            } message: {
                if let gift = selectedGift {
                    Text("Send \(gift.displayName) to the creator for \(gift.coinCost) HypeCoins?")
                }
            }
        }
    }
    
    private func giftDescription(_ gift: StreamHypeType) -> String {
        switch gift {
        case .superHype:    return "\(gift.xpMultiplier)x XP boost for 10 min"
        case .megaHype:     return "\(gift.xpMultiplier)x XP boost for 10 min"
        case .ultraHype:    return "\(gift.xpMultiplier)x XP boost for 15 min"
        case .giftSub:      return "+100 bonus XP for creator"
        case .spotlight:    return "Pin your message for 5 min"
        case .boostStream:  return "+500 XP, push stream to discovery"
        }
    }
    
    private func giftColor(_ gift: StreamHypeType) -> Color {
        switch gift {
        case .superHype:    return .orange
        case .megaHype:     return .purple
        case .ultraHype:    return .cyan
        case .giftSub:      return .pink
        case .spotlight:    return .yellow
        case .boostStream:  return .green
        }
    }
    
    private func sendGift(_ gift: StreamHypeType) {
        isSending = true
        Task {
            do {
                _ = try await coinService.sendHype(
                    hypeType: gift,
                    streamID: streamID,
                    communityID: communityID,
                    senderID: userID,
                    senderUsername: "",
                    senderLevel: userLevel
                )
                
                // Announce in chat
                chatService.sendGiftMessage(
                    communityID: communityID,
                    streamID: streamID,
                    username: "You",
                    giftName: gift.displayName,
                    emoji: gift.emoji
                )
                
                dismiss()
            } catch {
                // Show error
            }
            isSending = false
        }
    }
}

// MARK: - Post Stream Recap View

struct PostStreamRecapView: View {
    let recap: StreamRecap
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text(recap.tier.emoji)
                                .font(.system(size: 48))
                            
                            Text("Stream Complete!")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("\(recap.tier.displayName) — \(recap.durationFormatted)")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                            
                            if recap.wasFullCompletion {
                                Text("✅ FULL COMPLETION")
                                    .font(.system(size: 12, weight: .heavy))
                                    .tracking(1)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.12))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 20)
                        
                        // XP Breakdown
                        VStack(spacing: 10) {
                            recapRow("🎯 Attendance", "+\(recap.viewerXPEarned) XP")
                            
                            if recap.fullStayBonus > 0 {
                                recapRow("⭐ Full Stay Bonus", "+\(recap.fullStayBonus) XP")
                            }
                            
                            if recap.xpFromCoins > 0 {
                                recapRow("🪙 Coin Spending", "+\(recap.xpFromCoins) XP")
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            HStack {
                                Text("Total XP")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("+\(recap.totalXP)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                            
                            if recap.cloutBonus > 0 {
                                recapRow("👑 Permanent Clout", "+\(recap.cloutBonus)")
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(16)
                        
                        // Badges earned
                        if !recap.badgesEarned.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("🏅 Badges Earned")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                
                                ForEach(recap.badgesEarned, id: \.id) { badge in
                                    HStack(spacing: 12) {
                                        Text(badge.emoji)
                                            .font(.system(size: 24))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(badge.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                            Text(badge.description)
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.yellow.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                                    )
                                    .cornerRadius(14)
                                }
                            }
                        }
                        
                        // Goals reached
                        if !recap.goalsReached.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🎯 Community Goals Hit")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                
                                ForEach(recap.goalsReached) { goal in
                                    HStack(spacing: 8) {
                                        Text("✅")
                                        Text(goal.displayName)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(14)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
    }
    
    private func recapRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.yellow)
        }
    }
}

// MARK: - Agora Remote Video UIViewRepresentable

struct AgoraRemoteVideoRepresentable: UIViewRepresentable {
    let remoteView: UIView
    
    func makeUIView(context: Context) -> UIView {
        remoteView.backgroundColor = .black
        return remoteView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
