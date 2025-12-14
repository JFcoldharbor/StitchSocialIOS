//
//  VideoTrimmerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Trimmer with Slider Handles
//  Dependencies: VideoEditState
//  Features: Dual-handle slider for start/end trim
//

import SwiftUI
import AVFoundation

struct VideoTrimmerView: View {
    
    @ObservedObject var editState: VideoEditStateManager
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var localStartTime: TimeInterval
    @State private var localEndTime: TimeInterval
    
    private let handleWidth: CGFloat = 24
    private let trackHeight: CGFloat = 60
    
    init(editState: VideoEditStateManager) {
        self.editState = editState
        _localStartTime = State(initialValue: editState.state.trimStartTime)
        _localEndTime = State(initialValue: editState.state.trimEndTime)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Instructions
            Text("Drag the handles to trim your video")
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .padding(.top, 20)
            
            // Timeline with handles
            GeometryReader { geometry in
                let trackWidth = geometry.size.width - 40
                
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: trackHeight)
                        .padding(.horizontal, 20)
                    
                    // Selected region
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: selectedRegionWidth(trackWidth: trackWidth),
                            height: trackHeight
                        )
                        .offset(x: startHandleOffset(trackWidth: trackWidth) + 20)
                    
                    // Start handle
                    trimHandle(isStart: true)
                        .offset(x: startHandleOffset(trackWidth: trackWidth))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleStartDrag(value: value, trackWidth: trackWidth)
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                    commitChanges()
                                }
                        )
                    
                    // End handle
                    trimHandle(isStart: false)
                        .offset(x: endHandleOffset(trackWidth: trackWidth))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleEndDrag(value: value, trackWidth: trackWidth)
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                    commitChanges()
                                }
                        )
                }
                .onAppear {
                    // Force initial state sync
                    localStartTime = editState.state.trimStartTime
                    localEndTime = editState.state.trimEndTime
                    print("🎬 TRIMMER: Initial load - Start: \(localStartTime), End: \(localEndTime)")
                }
            }
            .frame(height: trackHeight)
            .padding(.horizontal, 20)
            .id("\(localStartTime)_\(localEndTime)") // Force view refresh when times change
            
            // Time display
            HStack(spacing: 32) {
                timeDisplay(
                    label: "Start",
                    time: localStartTime,
                    icon: "arrow.down.to.line"
                )
                
                Divider()
                    .frame(height: 30)
                    .background(Color.gray.opacity(0.3))
                
                timeDisplay(
                    label: "End",
                    time: localEndTime,
                    icon: "arrow.up.to.line"
                )
                
                Divider()
                    .frame(height: 30)
                    .background(Color.gray.opacity(0.3))
                
                timeDisplay(
                    label: "Duration",
                    time: localEndTime - localStartTime,
                    icon: "clock"
                )
            }
            .padding(.horizontal, 40)
            
            // Reset button
            Button {
                resetTrim()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Reset")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
            }
            
            Spacer()
        }
        .onChange(of: editState.state.trimStartTime) { _, newValue in
            if !isDraggingStart {
                localStartTime = newValue
            }
        }
        .onChange(of: editState.state.trimEndTime) { _, newValue in
            if !isDraggingEnd {
                localEndTime = newValue
            }
        }
    }
    
    // MARK: - Trim Handle
    
    private func trimHandle(isStart: Bool) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: handleWidth, height: trackHeight)
                .overlay(
                    VStack(spacing: 2) {
                        ForEach(0..<3) { _ in
                            Capsule()
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 12, height: 2)
                        }
                    }
                )
                .shadow(color: .cyan.opacity(0.5), radius: 8, x: 0, y: 0)
        }
    }
    
    // MARK: - Time Display
    
    private func timeDisplay(label: String, time: TimeInterval, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Text(formatTime(time))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }
    
    // MARK: - Calculations
    
    private func startHandleOffset(trackWidth: CGFloat) -> CGFloat {
        let progress = localStartTime / editState.state.videoDuration
        return 20 + (trackWidth * progress) - handleWidth / 2
    }
    
    private func endHandleOffset(trackWidth: CGFloat) -> CGFloat {
        let progress = localEndTime / editState.state.videoDuration
        return 20 + (trackWidth * progress) - handleWidth / 2
    }
    
    private func selectedRegionWidth(trackWidth: CGFloat) -> CGFloat {
        let startProgress = localStartTime / editState.state.videoDuration
        let endProgress = localEndTime / editState.state.videoDuration
        return trackWidth * (endProgress - startProgress)
    }
    
    // MARK: - Drag Handling
    
    private func handleStartDrag(value: DragGesture.Value, trackWidth: CGFloat) {
        isDraggingStart = true
        
        let dragPosition = value.location.x - 20
        let progress = max(0, min(1, dragPosition / trackWidth))
        let newTime = progress * editState.state.videoDuration
        
        // Ensure minimum duration of 0.5 seconds
        localStartTime = min(newTime, localEndTime - 0.5)
    }
    
    private func handleEndDrag(value: DragGesture.Value, trackWidth: CGFloat) {
        isDraggingEnd = true
        
        let dragPosition = value.location.x - 20
        let progress = max(0, min(1, dragPosition / trackWidth))
        let newTime = progress * editState.state.videoDuration
        
        // Ensure minimum duration of 0.5 seconds
        localEndTime = max(newTime, localStartTime + 0.5)
    }
    
    private func commitChanges() {
        editState.state.updateTrimRange(start: localStartTime, end: localEndTime)
        
        // Update player
        let startCMTime = CMTime(seconds: localStartTime, preferredTimescale: 600)
        editState.player.seek(to: startCMTime)
    }
    
    private func resetTrim() {
        withAnimation(.easeInOut(duration: 0.3)) {
            localStartTime = 0
            localEndTime = editState.state.videoDuration
        }
        commitChanges()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, milliseconds)
    }
}
