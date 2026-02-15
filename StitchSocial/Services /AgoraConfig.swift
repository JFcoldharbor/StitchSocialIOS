//
//  AgoraStreamService.swift
//  StitchSocial
//
//  Layer 6: Services - Agora Live Stream Integration
//  Dependencies: AgoraRtcKit
//  Features: Join/leave channel, local camera preview, remote video view,
//            mute/unmute, flip camera, viewer count callback
//
//  CACHING: No Firestore reads. Agora SDK handles all real-time state internally.
//  Cost: 10,000 free min/month. Beyond that $0.99/1K min.
//  One channel per stream. Channel name = streamID for uniqueness.
//

import SwiftUI
import AgoraRtcKit

// MARK: - Agora Config

struct AgoraConfig {
    /// Testing mode — no token required
    static let appID = "a9f983979e42435f8d2000f06382ffc6"
    
    /// When you move to production, generate tokens server-side
    /// For testing mode, token is nil
    static let token: String? = nil
}

// MARK: - Agora Stream Service

class AgoraStreamService: NSObject, ObservableObject {
    static let shared = AgoraStreamService()
    
    // MARK: - Published State
    
    @Published var isJoined = false
    @Published var remoteUserJoined = false
    @Published var remoteUID: UInt = 0
    @Published var viewerCount: Int = 0
    @Published var isMuted = false
    @Published var isCameraOff = false
    @Published var isUsingFrontCamera = true
    @Published var connectionState: ConnectionState = .disconnected
    
    // MARK: - Agora Engine
    
    private(set) var agoraEngine: AgoraRtcEngineKit?
    private var localView: UIView?
    private var remoteView: UIView?
    private var currentChannel: String?
    
    // Track remote users for viewer count
    private var remoteUsers: Set<UInt> = []
    
    // Callback for viewer count changes (updates LiveStreamService)
    var onViewerCountChanged: ((Int) -> Void)?
    
    enum ConnectionState {
        case disconnected, connecting, connected, reconnecting, failed
    }
    
    // MARK: - Init
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup Engine
    
    private func setupEngine() {
        guard agoraEngine == nil else { return }
        
        let config = AgoraRtcEngineConfig()
        config.appId = AgoraConfig.appID
        
        agoraEngine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        agoraEngine?.setChannelProfile(.liveBroadcasting)
        agoraEngine?.enableVideo()
        agoraEngine?.enableAudio()
        
        // Video quality — 480p@24fps for smooth testing, lower bandwidth
        agoraEngine?.setVideoEncoderConfiguration(
            AgoraVideoEncoderConfiguration(
                size: CGSize(width: 480, height: 848),
                frameRate: 24,
                bitrate: AgoraVideoBitrateStandard,
                orientationMode: .fixedPortrait,
                mirrorMode: .auto
            )
        )
        
        // Low latency optimizations
        agoraEngine?.setParameters("{\"rtc.video.degradation_preference\": 0}")
        agoraEngine?.setAudioProfile(.default)
        
        print("✅ AGORA: Engine initialized (480p@24fps)")
    }
    
    // MARK: - Start Broadcasting (Creator)
    
    func startBroadcast(channelName: String, localVideoView: UIView) async throws {
        setupEngine()
        guard let engine = agoraEngine else {
            throw AgoraError.engineNotInitialized
        }
        
        self.localView = localVideoView
        self.currentChannel = channelName
        
        // Set as broadcaster
        engine.setClientRole(.broadcaster)
        
        // Setup local video canvas
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = 0
        canvas.view = localVideoView
        canvas.renderMode = .hidden
        engine.setupLocalVideo(canvas)
        engine.startPreview()
        
        // Join channel — no token in testing mode
        let result = engine.joinChannel(
            byToken: AgoraConfig.token,
            channelId: channelName,
            info: nil,
            uid: 0
        )
        
        if result != 0 {
            throw AgoraError.joinFailed(code: result)
        }
        
        await MainActor.run {
            connectionState = .connecting
        }
        
        print("✅ AGORA: Joining channel '\(channelName)' as broadcaster")
    }
    
    // MARK: - Join as Viewer
    
    func joinAsViewer(channelName: String, remoteVideoView: UIView) async throws {
        setupEngine()
        guard let engine = agoraEngine else {
            throw AgoraError.engineNotInitialized
        }
        
        self.remoteView = remoteVideoView
        self.currentChannel = channelName
        
        // Set as audience
        engine.setClientRole(.audience)
        
        let result = engine.joinChannel(
            byToken: AgoraConfig.token,
            channelId: channelName,
            info: nil,
            uid: 0
        )
        
        if result != 0 {
            throw AgoraError.joinFailed(code: result)
        }
        
        await MainActor.run {
            connectionState = .connecting
        }
        
        print("✅ AGORA: Joining channel '\(channelName)' as viewer")
    }
    
    // MARK: - Leave Channel
    
    func leaveChannel() {
        agoraEngine?.leaveChannel(nil)
        agoraEngine?.stopPreview()
        
        localView = nil
        remoteView = nil
        currentChannel = nil
        remoteUsers.removeAll()
        
        isJoined = false
        remoteUserJoined = false
        remoteUID = 0
        viewerCount = 0
        isMuted = false
        isCameraOff = false
        connectionState = .disconnected
        
        print("✅ AGORA: Left channel")
    }
    
    // MARK: - Controls
    
    func toggleMute() {
        isMuted.toggle()
        agoraEngine?.muteLocalAudioStream(isMuted)
    }
    
    func toggleCamera() {
        isCameraOff.toggle()
        agoraEngine?.muteLocalVideoStream(isCameraOff)
    }
    
    func flipCamera() {
        isUsingFrontCamera.toggle()
        agoraEngine?.switchCamera()
    }
    
    // MARK: - Cleanup
    
    func destroy() {
        leaveChannel()
        AgoraRtcEngineKit.destroy()
        agoraEngine = nil
        print("✅ AGORA: Engine destroyed")
    }
}

// MARK: - Agora Delegate

extension AgoraStreamService: AgoraRtcEngineDelegate {
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.isJoined = true
            self.connectionState = .connected
            print("✅ AGORA: Joined channel '\(channel)' uid=\(uid)")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.remoteUsers.insert(uid)
            self.viewerCount = self.remoteUsers.count
            self.onViewerCountChanged?(self.viewerCount)
            
            // If this is the broadcaster (first remote user for viewers)
            if self.remoteUID == 0 {
                self.remoteUID = uid
                self.remoteUserJoined = true
                
                // Setup remote video
                if let view = self.remoteView {
                    let canvas = AgoraRtcVideoCanvas()
                    canvas.uid = uid
                    canvas.view = view
                    canvas.renderMode = .hidden
                    engine.setupRemoteVideo(canvas)
                }
            }
            
            print("✅ AGORA: Remote user \(uid) joined (viewers: \(self.viewerCount))")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            self.remoteUsers.remove(uid)
            self.viewerCount = self.remoteUsers.count
            self.onViewerCountChanged?(self.viewerCount)
            
            if uid == self.remoteUID {
                self.remoteUserJoined = false
                self.remoteUID = 0
            }
            
            print("✅ AGORA: Remote user \(uid) left (viewers: \(self.viewerCount))")
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        DispatchQueue.main.async {
            switch state {
            case .disconnected:
                self.connectionState = .disconnected
            case .connecting:
                self.connectionState = .connecting
            case .connected:
                self.connectionState = .connected
            case .reconnecting:
                self.connectionState = .reconnecting
            case .failed:
                self.connectionState = .failed
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Agora Error

enum AgoraError: LocalizedError {
    case engineNotInitialized
    case joinFailed(code: Int32)
    
    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "Agora engine not initialized"
        case .joinFailed(let code):
            return "Failed to join channel (code: \(code))"
        }
    }
}

// MARK: - Agora Video View Holder (persists across SwiftUI re-renders)

class AgoraVideoViewHolder: ObservableObject {
    let view = UIView()
    
    init() {
        view.backgroundColor = .black
    }
}

// MARK: - SwiftUI Video Views

/// Creator's local camera preview
struct AgoraLocalVideoView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Viewer's remote video player
struct AgoraRemoteVideoView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
