//
//  ClipTrimView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/20/26.
//


//
//  ClipTrimView.swift
//  StitchSocial
//
//  Layer 8: Views - Clip Trim Editor for Thread Collage
//  Full video preview with audio, draggable start/end handles
//  Kills background playback on appear via BackgroundActivityManager
//

import SwiftUI
import AVKit
import AVFoundation

struct ClipTrimView: View {
    
    // MARK: - Properties
    
    @Binding var clip: CollageClip
    let onDone: () -> Void
    let onRemove: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Player State
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var isLoadingVideo = true
    @State private var loadError: String?
    
    // MARK: - Trim State
    
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 10
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var timeObserver: Any?
    
    // MARK: - Constants
    
    private let handleWidth: CGFloat = 14
    private let trackHeight: CGFloat = 56
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                trimHeader
                
                // Video Preview
                videoPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Trim Controls
                trimControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
                // Bottom Bar
                bottomBar
            }
        }
        .onAppear {
            // Kill all background video playback
            BackgroundActivityManager.shared.killAllBackgroundActivity(reason: "Clip trim editor")
            VideoPreloadingService.shared.pauseAllPlayback()
            
            // Init trim values from clip
            trimStart = clip.trimStart
            trimEnd = min(clip.trimStart + clip.allocatedDuration, clip.originalDuration)
            
            loadVideo()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
    }
    
    // MARK: - Header
    
    private var trimHeader: some View {
        HStack {
            Button {
                cleanupPlayer()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(clip.isMainClip ? "Main Video" : "Trim Clip")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text("@\(clip.videoMetadata.creatorName)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Remove button (not for main clip)
            if let onRemove = onRemove, !clip.isMainClip {
                Button {
                    cleanupPlayer()
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // Disable default controls
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                
                // Tap to play/pause
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        togglePlayback()
                    }
                
                // Play/pause indicator
                if !isPlaying {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                        .allowsHitTesting(false)
                }
            } else if isLoadingVideo {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    // MARK: - Trim Controls
    
    private var trimControls: some View {
        VStack(spacing: 12) {
            // Time labels
            HStack {
                Text(formatTime(trimStart))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                
                Spacer()
                
                Text("Using \(formatTime(trimEnd - trimStart)) of \(formatTime(clip.originalDuration))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(formatTime(trimEnd))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            
            // Scrubber track with handles
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let duration = max(clip.originalDuration, 0.1)
                let startX = (trimStart / duration) * totalWidth
                let endX = (trimEnd / duration) * totalWidth
                let playheadX = (currentTime / duration) * totalWidth
                
                ZStack(alignment: .leading) {
                    // Background track (full duration)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: trackHeight)
                    
                    // Dimmed left region
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: max(startX, 0), height: trackHeight)
                        .cornerRadius(6, corners: [.topLeft, .bottomLeft])
                    
                    // Dimmed right region
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: max(totalWidth - endX, 0), height: trackHeight)
                        .offset(x: endX)
                        .cornerRadius(6, corners: [.topRight, .bottomRight])
                    
                    // Selected region border
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.cyan, lineWidth: 2)
                        .frame(width: max(endX - startX, handleWidth * 2), height: trackHeight)
                        .offset(x: startX)
                    
                    // Playhead
                    if isPlaying || currentTime > trimStart {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: trackHeight + 10)
                            .offset(x: min(max(playheadX, startX), endX))
                            .shadow(color: .white.opacity(0.5), radius: 4)
                    }
                    
                    // Left handle (trim start)
                    trimHandle(isStart: true)
                        .offset(x: startX - handleWidth / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingStart = true
                                    let newStart = max(0, (value.location.x / totalWidth) * duration)
                                    // Don't let start pass end minus minimum
                                    let minDuration: TimeInterval = 2.0
                                    trimStart = min(newStart, trimEnd - minDuration)
                                    seekToTime(trimStart)
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                    applyTrimToClip()
                                }
                        )
                    
                    // Right handle (trim end)
                    trimHandle(isStart: false)
                        .offset(x: endX - handleWidth / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingEnd = true
                                    let newEnd = min(clip.originalDuration, (value.location.x / totalWidth) * duration)
                                    let minDuration: TimeInterval = 2.0
                                    trimEnd = max(newEnd, trimStart + minDuration)
                                    seekToTime(trimEnd - 0.5)
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                    applyTrimToClip()
                                }
                        )
                }
            }
            .frame(height: trackHeight + 10)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Trim Handle
    
    private func trimHandle(isStart: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.cyan)
                .frame(width: handleWidth, height: trackHeight + 8)
                .shadow(color: .cyan.opacity(0.4), radius: 6)
            
            // Grip lines
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 3, height: 1)
                }
            }
        }
        .contentShape(Rectangle().inset(by: -20)) // Bigger hit target
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Preview from start button
            Button {
                seekToTime(trimStart)
                if !isPlaying { togglePlayback() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Preview")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(.ultraThinMaterial))
            }
            
            Spacer()
            
            // Duration badge
            Text(formatTime(trimEnd - trimStart))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
            
            Spacer()
            
            // Done button
            Button {
                applyTrimToClip()
                cleanupPlayer()
                onDone()
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.cyan))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Video Loading
    
    private func loadVideo() {
        // Try cached asset first, then load from URL
        if let asset = clip.asset {
            setupPlayer(with: asset)
        } else if let url = URL(string: clip.videoMetadata.videoURL) {
            let asset = AVAsset(url: url)
            setupPlayer(with: asset)
        } else {
            loadError = "Could not load video"
            isLoadingVideo = false
        }
    }
    
    private func setupPlayer(with asset: AVAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        
        // Seek to trim start
        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        avPlayer.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Add periodic time observer for playhead
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            let t = time.seconds
            currentTime = t
            
            // Loop within trim range
            if t >= trimEnd {
                avPlayer.seek(
                    to: CMTime(seconds: trimStart, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
        }
        
        // Looping via notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            avPlayer.seek(
                to: CMTime(seconds: trimStart, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            avPlayer.play()
        }
        
        self.player = avPlayer
        self.isLoadingVideo = false
    }
    
    // MARK: - Playback Controls
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            // If at end of trim range, restart from trim start
            if currentTime >= trimEnd - 0.1 {
                seekToTime(trimStart)
            }
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func seekToTime(_ seconds: TimeInterval) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
    
    // MARK: - Apply Trim
    
    private func applyTrimToClip() {
        clip.trimStart = trimStart
        // allocatedDuration = how much of the clip we're using
        clip.allocatedDuration = trimEnd - trimStart
    }
    
    // MARK: - Cleanup
    
    private func cleanupPlayer() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    // MARK: - Formatting
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, tenths)
        }
        return String(format: "%d.%d", secs, tenths)
    }
}

// MARK: - Corner Radius Helper

extension View {
    func newcornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
