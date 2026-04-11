//
//  VideoTrimmerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Trimmer with Filmstrip & Playhead
//  Dependencies: VideoEditStateManager (provides player + currentPlaybackTime)
//
//  Three interactive elements on the filmstrip:
//    1. Left trim handle  — drags to set start point
//    2. Right trim handle — drags to set end point
//    3. Playhead cursor   — thin white line that moves with playback,
//                           also draggable to scrub through video
//
//  CACHING: Filmstrip frames extracted ONCE on appear, cleared on disappear (~3MB).
//

import SwiftUI
import AVFoundation
import UIKit

struct VideoTrimmerView: View {
    
    @ObservedObject var editState: VideoEditStateManager
    
    // Trim handle state
    @State private var localStartTime: TimeInterval
    @State private var localEndTime: TimeInterval
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false
    
    // Filmstrip
    @State private var filmstripFrames: [CGImage] = []
    @State private var isExtractingFrames = false
    
    // Haptic
    @State private var lastHapticSecond: Int = -1
    
    // Layout constants
    private let handleWidth: CGFloat = 16
    private let trackHeight: CGFloat = 56
    private let playheadWidth: CGFloat = 3
    private let frameCount = 20
    private let frameStep: TimeInterval = 1.0 / 30.0
    
    private var duration: TimeInterval {
        max(editState.state.videoDuration, 0.01)
    }
    
    init(editState: VideoEditStateManager) {
        self.editState = editState
        _localStartTime = State(initialValue: editState.state.trimStartTime)
        _localEndTime = State(initialValue: editState.state.trimEndTime)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 16) {
            trimmerTrack
            timeRow
            fineAdjustControls
            resetButton
            Spacer()
        }
        .padding(.top, 16)
        .onAppear {
            localStartTime = editState.state.trimStartTime
            localEndTime = editState.state.trimEndTime
            extractFilmstripFrames()
        }
        .onDisappear { filmstripFrames.removeAll() }
        .onChange(of: editState.state.trimStartTime) { _, v in if !isDraggingStart { localStartTime = v } }
        .onChange(of: editState.state.trimEndTime) { _, v in if !isDraggingEnd { localEndTime = v } }
    }
    
    // MARK: - Trimmer Track (filmstrip + handles + playhead)
    
    private var trimmerTrack: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let usableWidth = totalWidth - handleWidth * 2
            
            ZStack(alignment: .leading) {
                // 1. Filmstrip frames
                filmstrip(totalWidth: totalWidth)
                
                // 2. Dim outside trim region
                dimOverlay(totalWidth: totalWidth)
                
                // 3. Left trim handle
                trimHandleView(isStart: true)
                    .position(
                        x: xForTime(localStartTime, totalWidth: totalWidth) + handleWidth / 2,
                        y: trackHeight / 2
                    )
                    .gesture(trimDrag(isStart: true, usableWidth: usableWidth, totalWidth: totalWidth))
                
                // 4. Right trim handle
                trimHandleView(isStart: false)
                    .position(
                        x: xForTime(localEndTime, totalWidth: totalWidth) + handleWidth / 2,
                        y: trackHeight / 2
                    )
                    .gesture(trimDrag(isStart: false, usableWidth: usableWidth, totalWidth: totalWidth))
                
                // 5. Top/bottom border on selected region
                selectedBorder(totalWidth: totalWidth)
                
                // 6. Playhead cursor
                playheadCursor(totalWidth: totalWidth, usableWidth: usableWidth)
            }
        }
        .frame(height: trackHeight)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Filmstrip
    
    private func filmstrip(totalWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if filmstripFrames.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: totalWidth, height: trackHeight)
                    .overlay(
                        isExtractingFrames
                        ? AnyView(ProgressView().scaleEffect(0.6).progressViewStyle(CircularProgressViewStyle(tint: .cyan)))
                        : AnyView(EmptyView())
                    )
            } else {
                let frameWidth = totalWidth / CGFloat(filmstripFrames.count)
                ForEach(Array(filmstripFrames.enumerated()), id: \.offset) { _, frame in
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: frameWidth, height: trackHeight)
                        .clipped()
                }
            }
        }
        .cornerRadius(6)
    }
    
    // MARK: - Dim Overlay
    
    private func dimOverlay(totalWidth: CGFloat) -> some View {
        let startX = xForTime(localStartTime, totalWidth: totalWidth) + handleWidth
        let endX = xForTime(localEndTime, totalWidth: totalWidth)
        
        return ZStack(alignment: .leading) {
            // Left dim
            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: max(0, startX - handleWidth), height: trackHeight)
                .cornerRadius(6, corners: [.topLeft, .bottomLeft])
            
            // Right dim
            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(width: max(0, totalWidth - endX - handleWidth), height: trackHeight)
                .offset(x: endX + handleWidth)
                .cornerRadius(6, corners: [.topRight, .bottomRight])
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Selected Region Border (top + bottom lines)
    
    private func selectedBorder(totalWidth: CGFloat) -> some View {
        let startX = xForTime(localStartTime, totalWidth: totalWidth) + handleWidth
        let endX = xForTime(localEndTime, totalWidth: totalWidth)
        let regionWidth = max(0, endX - startX)
        
        return VStack {
            Rectangle().fill(Color.cyan).frame(width: regionWidth, height: 2)
            Spacer()
            Rectangle().fill(Color.cyan).frame(width: regionWidth, height: 2)
        }
        .frame(height: trackHeight)
        .offset(x: startX + regionWidth / 2 - totalWidth / 2)
        .allowsHitTesting(false)
    }
    
    // MARK: - Trim Handle
    
    private func trimHandleView(isStart: Bool) -> some View {
        let isDragging = isStart ? isDraggingStart : isDraggingEnd
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.cyan)
            .frame(width: handleWidth, height: trackHeight)
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: 8, height: 2)
                    }
                }
            )
            .shadow(color: .cyan.opacity(isDragging ? 0.9 : 0.4), radius: isDragging ? 8 : 4)
            .scaleEffect(y: isDragging ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }
    
    // MARK: - Trim Handle Drag
    
    private func trimDrag(isStart: Bool, usableWidth: CGFloat, totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let frac = clampFrac((value.location.x - handleWidth) / usableWidth)
                let newTime = frac * duration
                
                if isStart {
                    isDraggingStart = true
                    localStartTime = max(0, min(newTime, localEndTime - 0.5))
                    seekFrame(localStartTime)
                    hapticTick(at: localStartTime)
                } else {
                    isDraggingEnd = true
                    localEndTime = min(duration, max(newTime, localStartTime + 0.5))
                    seekFrame(localEndTime)
                    hapticTick(at: localEndTime)
                }
            }
            .onEnded { _ in
                isDraggingStart = false
                isDraggingEnd = false
                lastHapticSecond = -1
                commitChanges()
            }
    }
    
    // MARK: - Playhead Cursor
    
    private func playheadCursor(totalWidth: CGFloat, usableWidth: CGFloat) -> some View {
        let playTime: TimeInterval
        if isDraggingPlayhead {
            playTime = editState.currentPlaybackTime
        } else {
            // Clamp playhead between trim handles
            playTime = min(max(editState.currentPlaybackTime, localStartTime), localEndTime)
        }
        let x = xForTime(playTime, totalWidth: totalWidth) + handleWidth / 2
        
        return Rectangle()
            .fill(Color.white)
            .frame(width: playheadWidth, height: trackHeight + 12)
            .shadow(color: .white.opacity(0.6), radius: 3)
            .position(x: x, y: trackHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingPlayhead = true
                        editState.player.pause()
                        let frac = clampFrac((value.location.x - handleWidth) / usableWidth)
                        let newTime = max(localStartTime, min(frac * duration, localEndTime))
                        seekFrame(newTime)
                        hapticTick(at: newTime)
                    }
                    .onEnded { _ in
                        isDraggingPlayhead = false
                        lastHapticSecond = -1
                    }
            )
    }
    
    // MARK: - Position Helpers
    
    private func xForTime(_ time: TimeInterval, totalWidth: CGFloat) -> CGFloat {
        let frac = time / duration
        let usable = totalWidth - handleWidth * 2
        return handleWidth + usable * frac - handleWidth / 2
    }
    
    private func clampFrac(_ f: CGFloat) -> CGFloat { max(0, min(1, f)) }
    
    // MARK: - Seek (frame-accurate)
    
    private func seekFrame(_ time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        editState.player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    // MARK: - Haptic
    
    private func hapticTick(at time: TimeInterval) {
        let sec = Int(time)
        if sec != lastHapticSecond {
            lastHapticSecond = sec
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // MARK: - Commit & Reset
    
    private func commitChanges() {
        editState.state.updateTrimRange(start: localStartTime, end: localEndTime)
    }
    
    private func resetTrim() {
        withAnimation(.easeInOut(duration: 0.3)) {
            localStartTime = 0
            localEndTime = duration
        }
        commitChanges()
        seekFrame(0)
    }
    
    // MARK: - Time Row
    
    private var timeRow: some View {
        HStack(spacing: 0) {
            timeLabel("Start", localStartTime, "arrow.down.to.line")
            Spacer()
            timeLabel("Duration", localEndTime - localStartTime, "clock")
            Spacer()
            timeLabel("End", localEndTime, "arrow.up.to.line")
        }
        .padding(.horizontal, 20)
    }
    
    private func timeLabel(_ label: String, _ time: TimeInterval, _ icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(.gray)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
            }
            Text(formatTime(time))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }
    
    // MARK: - Fine Adjust Controls
    
    private var fineAdjustControls: some View {
        HStack(spacing: 24) {
            fineAdjustGroup("Start", time: localStartTime) { delta in
                let t = max(0, min(localStartTime + delta, localEndTime - 0.5))
                localStartTime = t; seekFrame(t); commitChanges()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            
            Divider().frame(height: 36).background(Color.gray.opacity(0.3))
            
            fineAdjustGroup("End", time: localEndTime) { delta in
                let t = min(duration, max(localEndTime + delta, localStartTime + 0.5))
                localEndTime = t; seekFrame(t); commitChanges()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func fineAdjustGroup(_ label: String, time: TimeInterval, adjust: @escaping (TimeInterval) -> Void) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption2).foregroundColor(.gray)
            HStack(spacing: 14) {
                Button { adjust(-frameStep) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundColor(.cyan.opacity(0.8))
                }
                Text(formatTimePrecise(time))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white).frame(width: 72)
                Button { adjust(frameStep) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundColor(.cyan.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Reset Button
    
    private var resetButton: some View {
        Button { resetTrim() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold))
                Text("Reset").font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
        }
    }
    
    // MARK: - Filmstrip Extraction
    
    private func extractFilmstripFrames() {
        guard filmstripFrames.isEmpty && !isExtractingFrames else { return }
        guard editState.state.videoDuration > 0 else { return }
        
        isExtractingFrames = true
        let url = editState.state.videoURL
        let dur = editState.state.videoDuration
        let count = frameCount
        
        Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 160, height: 284)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
            
            let interval = dur / Double(count)
            var frames: [CGImage] = []
            
            for i in 0..<count {
                let t = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
                if let (img, _) = try? await gen.image(at: t) {
                    frames.append(img)
                }
            }
            
            await MainActor.run {
                filmstripFrames = frames
                isExtractingFrames = false
            }
        }
    }
    
    // MARK: - Formatting
    
    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d.%d", Int(t) / 60, Int(t) % 60, Int((t.truncatingRemainder(dividingBy: 1)) * 10))
    }
    
    private func formatTimePrecise(_ t: TimeInterval) -> String {
        String(format: "%d:%02d.%02d", Int(t) / 60, Int(t) % 60, Int((t.truncatingRemainder(dividingBy: 1)) * 100))
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
