//
//  CaptionEditorView.swift
//  StitchSocial
//
//  Layer 8: Views - Caption Editor with Text Overlay
//  Dependencies: VideoEditState
//  Features: Add captions, position, style, timing
//

import SwiftUI
import AVFoundation

struct CaptionEditorView: View {
    
    @ObservedObject var editState: VideoEditStateManager
    
    @State private var showingAddCaption = false
    @State private var editingCaption: VideoCaption?
    @State private var currentPlaybackTime: TimeInterval = 0
    
    @StateObject private var autoCaptionService = AutoCaptionService.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Auto-caption loading indicator
            if autoCaptionService.isTranscribing {
                autoCaptionLoadingView
            }
            // Instructions
            else if editState.state.captions.isEmpty {
                emptyStateView
            } else {
                // Caption list
                captionList
            }
            
            Spacer()
            
            // Add caption button
            Button {
                showingAddCaption = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    
                    Text("Add Caption")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showingAddCaption) {
            CaptionEditSheet(
                caption: nil,
                currentTime: currentPlaybackTime,
                maxDuration: editState.state.trimmedDuration,
                onSave: { caption in
                    editState.state.addCaption(caption)
                },
                onDelete: nil
            )
        }
        .sheet(item: $editingCaption) { caption in
            CaptionEditSheet(
                caption: caption,
                currentTime: currentPlaybackTime,
                maxDuration: editState.state.trimmedDuration,
                onSave: { updatedCaption in
                    editState.state.updateCaption(id: caption.id) { existing in
                        existing = updatedCaption
                    }
                },
                onDelete: {
                    editState.state.removeCaption(id: caption.id)
                }
            )
        }
    }
    
    // MARK: - Auto-Caption Loading
    
    private var autoCaptionLoadingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .blur(radius: 15)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(1.5)
            }
            .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("Auto-Generating Captions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Transcribing audio...")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                ProgressView(value: autoCaptionService.transcriptionProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                    .frame(width: 200)
                    .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .blur(radius: 15)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.cyan.opacity(0.8))
            }
            .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("No Captions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("No audio detected or transcription unavailable")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Caption List
    
    private var captionList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(editState.state.captions) { caption in
                    CaptionRow(
                        caption: caption,
                        onTap: {
                            editingCaption = caption
                        },
                        onSeek: {
                            seekToCaption(caption)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Actions
    
    private func seekToCaption(_ caption: VideoCaption) {
        let time = CMTime(seconds: caption.startTime, preferredTimescale: 600)
        editState.player.seek(to: time)
        editState.player.play()
    }
}

// MARK: - Caption Row

struct CaptionRow: View {
    
    let caption: VideoCaption
    let onTap: () -> Void
    let onSeek: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Play button
                Button(action: onSeek) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.cyan, Color(white: 0.2))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Caption info
                VStack(alignment: .leading, spacing: 6) {
                    Text(caption.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text(formatTime(caption.startTime))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.gray)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.system(size: 11))
                            Text(formatDuration(caption.duration))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.gray)
                        
                        Capsule()
                            .fill(positionColor(caption.position))
                            .frame(width: 6, height: 6)
                        
                        Text(caption.position.rawValue.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        return String(format: "%.1fs", duration)
    }
    
    private func positionColor(_ position: CaptionPosition) -> Color {
        switch position {
        case .top: return .cyan
        case .center: return .purple
        case .bottom: return .orange
        }
    }
}

// MARK: - Caption Edit Sheet

struct CaptionEditSheet: View {
    
    let caption: VideoCaption?
    let currentTime: TimeInterval
    let maxDuration: TimeInterval
    let onSave: (VideoCaption) -> Void
    let onDelete: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var text: String
    @State private var startTime: TimeInterval
    @State private var duration: TimeInterval
    @State private var position: CaptionPosition
    @State private var style: CaptionStyle
    
    init(
        caption: VideoCaption?,
        currentTime: TimeInterval,
        maxDuration: TimeInterval,
        onSave: @escaping (VideoCaption) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.caption = caption
        self.currentTime = currentTime
        self.maxDuration = maxDuration
        self.onSave = onSave
        self.onDelete = onDelete
        
        _text = State(initialValue: caption?.text ?? "")
        _startTime = State(initialValue: caption?.startTime ?? currentTime)
        _duration = State(initialValue: caption?.duration ?? 3.0)
        _position = State(initialValue: caption?.position ?? .center)
        _style = State(initialValue: caption?.style ?? .standard)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Text input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Caption Text")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            TextField("Enter caption text...", text: $text)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        
                        // Position picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Position")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                ForEach(CaptionPosition.allCases, id: \.self) { pos in
                                    Button {
                                        position = pos
                                    } label: {
                                        Text(pos.rawValue.capitalized)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(position == pos ? .white : .gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(position == pos ? Color.cyan : Color.white.opacity(0.1))
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Style picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Style")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            VStack(spacing: 8) {
                                ForEach(CaptionStyle.allCases, id: \.self) { captionStyle in
                                    Button {
                                        style = captionStyle
                                    } label: {
                                        HStack {
                                            Image(systemName: style == captionStyle ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(style == captionStyle ? .cyan : .gray)
                                            
                                            Text(captionStyle.rawValue.capitalized)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            Spacer()
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(style == captionStyle ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Timing controls
                        VStack(spacing: 16) {
                            // Start time
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start Time: \(formatTime(startTime))")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray)
                                
                                Slider(value: $startTime, in: 0...maxDuration)
                                    .accentColor(.cyan)
                            }
                            
                            // Duration
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Duration: \(String(format: "%.1fs", duration))")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray)
                                
                                Slider(value: $duration, in: 0.5...10.0)
                                    .accentColor(.cyan)
                            }
                        }
                        
                        // Delete button (if editing)
                        if let onDelete = onDelete {
                            Button {
                                onDelete()
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Delete Caption")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.15))
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(caption == nil ? "Add Caption" : "Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCaption()
                    }
                    .foregroundColor(.cyan)
                    .disabled(text.isEmpty)
                }
            }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
    
    private func saveCaption() {
        let newCaption = VideoCaption(
            text: text,
            startTime: startTime,
            duration: duration,
            position: position,
            style: style
        )
        
        onSave(newCaption)
        dismiss()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
