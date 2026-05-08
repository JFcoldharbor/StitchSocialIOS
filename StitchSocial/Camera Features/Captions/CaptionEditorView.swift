//
//  CaptionEditorView.swift
//  StitchSocial
//
//  Standard caption controls — intentionally minimal:
//    • On/off toggle
//    • Position picker (top / center / bottom)
//    • Generated-segment timeline (tap a chip to seek the player)
//
//  No style/preset/color/size pickers — captions render in one hardcoded
//  style that matches the export 1:1.

import SwiftUI
import AVFoundation

struct CaptionEditorView: View {
    @ObservedObject var editState: VideoEditStateManager
    @StateObject private var autoCaptionService = AutoCaptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            if autoCaptionService.isTranscribing {
                transcribingView
            } else if editState.state.captions.isEmpty {
                emptyView
            } else {
                mainContent
            }
        }
    }

    // MARK: - Transcribing

    private var transcribingView: some View {
        VStack(spacing: 10) {
            ProgressView(value: autoCaptionService.transcriptionProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                .frame(width: 160)
            Text("Generating captions…")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 26)).foregroundColor(.white.opacity(0.25))
            Text("No speech detected")
                .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            toggleRow.padding(.horizontal, 16).padding(.vertical, 12)

            if editState.state.captionsEnabled {
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.1))
                    positionControl.padding(.horizontal, 16).padding(.vertical, 14)
                    Divider().background(Color.white.opacity(0.1))
                    captionTimeline.padding(.top, 10).padding(.bottom, 6)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editState.state.captionsEnabled)
    }

    // MARK: - Toggle Row

    private var toggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Captions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(editState.state.captions.count) segments")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { editState.state.captionsEnabled },
                set: { editState.state.captionsEnabled = $0; editState.state.lastModified = Date() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .labelsHidden()
            .scaleEffect(0.85)
        }
    }

    // MARK: - Position

    private var positionControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))

            HStack(spacing: 8) {
                ForEach(CaptionPosition.allCases, id: \.self) { pos in
                    let isSelected = editState.state.globalCaptionPosition == pos
                    Button {
                        editState.state.globalCaptionPosition = pos
                        editState.state.lastModified = Date()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: positionIcon(pos))
                                .font(.system(size: 14))
                                .foregroundColor(isSelected ? .black : .white)
                            Text(pos.rawValue.capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.white : Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func positionIcon(_ pos: CaptionPosition) -> String {
        switch pos {
        case .top:    return "text.aligntop"
        case .center: return "text.aligncenter"
        case .bottom: return "text.alignbottom"
        }
    }

    // MARK: - Caption Timeline

    private var captionTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Segments")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .padding(.leading, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(editState.state.captions) { caption in
                        captionChip(caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func captionChip(_ caption: VideoCaption) -> some View {
        Button {
            let t = CMTime(seconds: caption.startTime, preferredTimescale: 600)
            editState.player.seek(to: t)
            editState.player.play()
        } label: {
            HStack(spacing: 6) {
                Text(formatTime(caption.startTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Text(caption.text.prefix(20) + (caption.text.count > 20 ? "…" : ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Button {
                    editState.state.removeCaption(id: caption.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
