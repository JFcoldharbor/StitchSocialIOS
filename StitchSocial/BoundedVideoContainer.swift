//
//  BoundedVideoContainer.swift
//  StitchSocial
//
//  Created by James Garmon on 9/19/25.
//


//
//  BoundedVideoContainer.swift
//  StitchSocial
//
//  Layer 8: Views - Optimized Video Container for Thread Navigation
//  Dependencies: AVFoundation, CoreVideoMetadata, ThreadData
//  Features: Background/foreground handling, memory efficient, loop detection
//  Purpose: Lightweight video player for continuous scrolling experiences
//

import SwiftUI
import AVFoundation

// MARK: - BoundedVideoContainer

struct MyBoundedVideoContainer: UIViewRepresentable {
    let video: CoreVideoMetadata
    let thread: ThreadData
    let isActive: Bool
    let containerID: String
    let onVideoLoop: (String) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // Create coordinator
        let coordinator = context.coordinator
        coordinator.containerView = containerView
        coordinator.setupPlayer(for: video, isActive: isActive)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        
        // Update active state
        if coordinator.currentVideoID != video.id || coordinator.isActive != isActive {
            coordinator.setupPlayer(for: video, isActive: isActive)
        }
    }
    
    func makeCoordinator() -> VideoContainerCoordinator {
        VideoContainerCoordinator(onVideoLoop: onVideoLoop)
    }
}

// MARK: - Video Container Coordinator

class VideoContainerCoordinator: NSObject {
    var containerView: UIView?
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    var currentVideoID: String?
    var isActive: Bool = false
    var notificationObserver: NSObjectProtocol?
    let onVideoLoop: (String) -> Void
    
    init(onVideoLoop: @escaping (String) -> Void) {
        self.onVideoLoop = onVideoLoop
        super.init()
    }
    
    func setupPlayer(for video: CoreVideoMetadata, isActive: Bool) {
        guard let containerView = containerView else { return }
        
        self.isActive = isActive
        
        // Clean up existing player if different video
        if currentVideoID != video.id {
            cleanupCurrentPlayer()
            
            // Setup new player
            guard let url = URL(string: video.videoURL) else { return }
            
            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)
            
            // Setup player layer
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.frame = containerView.bounds
            playerLayer?.videoGravity = .resizeAspectFill
            
            if let playerLayer = playerLayer {
                containerView.layer.sublayers?.removeAll()
                containerView.layer.addSublayer(playerLayer)
            }
            
            currentVideoID = video.id
            
            // Setup loop notification
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                if self?.isActive == true {
                    self?.player?.play()
                    self?.onVideoLoop(video.id)
                }
            }
        }
        
        // Update playback state
        if isActive {
            player?.play()
        } else {
            player?.pause()
        }
        
        // Update layer frame
        playerLayer?.frame = containerView.bounds
    }
    
    private func cleanupCurrentPlayer() {
        player?.pause()
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentVideoID = nil
    }
    
    deinit {
        cleanupCurrentPlayer()
    }
}
