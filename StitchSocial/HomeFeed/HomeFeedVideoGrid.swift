//
//  HomeFeedVideoGrid.swift
//  StitchSocial
//
//  MINIMAL MEMORY-SAFE VERSION - Only 1 player at a time
//

import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

// MARK: - Debug Helper
private let debug = HomeFeedDebugger.shared

// MARK: - HomeFeedVideoGrid

struct HomeFeedVideoGrid: View {
    
    let threads: [ThreadData]
    let currentThreadIndex: Int
    let currentStitchIndex: Int
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat
    let dragOffset: CGSize
    let onVideoLoop: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                ZStack {
                    ForEach(Array(threads.enumerated()), id: \.offset) { threadIndex, thread in
                        threadContainer(
                            thread: thread,
                            threadIndex: threadIndex,
                            geometry: geometry
                        )
                    }
                }
                .offset(
                    x: horizontalOffset + dragOffset.width,
                    y: verticalOffset + dragOffset.height
                )
            }
            .onAppear {
                debug.gridAppeared(threadCount: threads.count)
            }
        }
    }
    
    // MARK: - Thread Container
    
    @ViewBuilder
    private func threadContainer(
        thread: ThreadData,
        threadIndex: Int,
        geometry: GeometryProxy
    ) -> some View {
        // Parent video
        let isParentActive = threadIndex == currentThreadIndex && currentStitchIndex == 0
        
        MinimalVideoCell(
            video: thread.parentVideo,
            isActive: isParentActive
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        .position(
            x: geometry.size.width / 2,
            y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height)
        )
        
        // Child videos
        ForEach(Array(thread.childVideos.enumerated()), id: \.offset) { childIndex, childVideo in
            let isChildActive = threadIndex == currentThreadIndex && currentStitchIndex == (childIndex + 1)
            
            MinimalVideoCell(
                video: childVideo,
                isActive: isChildActive
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .position(
                x: geometry.size.width / 2 + (CGFloat(childIndex + 1) * geometry.size.width),
                y: geometry.size.height / 2 + (CGFloat(threadIndex) * geometry.size.height)
            )
        }
    }
}

// MARK: - Minimal Video Cell (No extra wrapper)

struct MinimalVideoCell: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    
    var body: some View {
        ZStack {
            Color.black
            
            // Player component
            SinglePlayerComponent(
                video: video,
                isActive: isActive
            )
            
            // Overlay only when active
            if isActive {
                ContextualVideoOverlay(
                    video: video,
                    context: .homeFeed,
                    currentUserID: Auth.auth().currentUser?.uid,
                    threadVideo: nil,
                    isVisible: true,
                    actualReplyCount: 0,
                    onAction: { _ in }
                )
            }
        }
    }
}

// MARK: - SinglePlayerComponent (ONLY creates player when active)

struct SinglePlayerComponent: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var hasError = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if isActive {
                    if hasError {
                        errorView
                    } else if let player = player, isReady {
                        VideoPlayer(player: player)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .ignoresSafeArea(.all)
                    } else {
                        loadingView
                    }
                } else {
                    // Inactive: just show black or thumbnail
                    thumbnailView
                }
            }
        }
        .onChange(of: isActive) { oldValue, newValue in
            handleActiveChange(newValue)
        }
        .onAppear {
            if isActive {
                createPlayer()
            }
        }
        .onDisappear {
            destroyPlayer()
        }
    }
    
    // MARK: - State Changes
    
    private func handleActiveChange(_ nowActive: Bool) {
        debug.activeStateChanged(videoID: video.id, from: !nowActive, to: nowActive)
        
        if nowActive {
            createPlayer()
        } else {
            destroyPlayer()
        }
    }
    
    // MARK: - Player Lifecycle
    
    private func createPlayer() {
        // Don't create if already have one
        guard player == nil else {
            player?.seek(to: .zero)
            player?.play()
            debug.log(.playback, "Reusing player: \(video.id.prefix(8))")
            return
        }
        
        debug.playerSetupStarted(videoID: video.id, isActive: true)
        
        guard let url = URL(string: video.videoURL), !video.videoURL.isEmpty else {
            debug.error("Invalid URL: \(video.id.prefix(8))")
            hasError = true
            return
        }
        
        debug.playerCreating(videoID: video.id, url: video.videoURL)
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        
        // Observe ready state
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                if status == .readyToPlay {
                    debug.playerReady(videoID: video.id, isActive: isActive)
                    isReady = true
                    if isActive {
                        newPlayer.play()
                        debug.playbackStarted(videoID: video.id, source: "ready")
                    }
                } else if status == .failed {
                    debug.playerFailed(videoID: video.id, error: playerItem.error)
                    hasError = true
                }
            }
            .store(in: &cancellables)
        
        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            if isActive {
                newPlayer.play()
            }
        }
        
        player = newPlayer
        debug.playerCreated(videoID: video.id)
    }
    
    private func destroyPlayer() {
        guard player != nil else { return }
        
        debug.log(.player, "Destroying: \(video.id.prefix(8))")
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isReady = false
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Views
    
    private var loadingView: some View {
        ZStack {
            Color.black
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }
    
    private var thumbnailView: some View {
        Color.black
    }
    
    private var errorView: some View {
        ZStack {
            Color.black
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text("Failed to load")
                    .foregroundColor(.white)
            }
        }
    }
}
