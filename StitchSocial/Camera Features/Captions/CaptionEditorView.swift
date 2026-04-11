//
//  CaptionEditorView.swift
//  StitchSocial
//
//  TikTok/Instagram-style caption editor.
//  - Toggle on/off at top
//  - Global preset strip (one style for all captions)
//  - Color override row
//  - Position picker
//  - Size slider
//  - Caption timeline chips at bottom

import SwiftUI
import AVFoundation

struct CaptionEditorView: View {
    @ObservedObject var editState: VideoEditStateManager
    @StateObject private var autoCaptionService = AutoCaptionService.shared
    @State private var showColorPicker = false

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

            // ── Toggle row ─────────────────────────────────────────────
            toggleRow.padding(.horizontal, 16).padding(.vertical, 12)

            if editState.state.captionsEnabled {
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.1))

                    // ── Preset strip ───────────────────────────────────
                    presetStrip.padding(.top, 14).padding(.bottom, 8)

                    Divider().background(Color.white.opacity(0.1))

                    // ── Controls row (color · position · size) ─────────
                    controlsRow.padding(.horizontal, 16).padding(.vertical, 12)

                    Divider().background(Color.white.opacity(0.1))

                    // ── Caption timeline chips ─────────────────────────
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
                Text("\(editState.state.captions.count) segments generated")
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

    // MARK: - Preset Strip

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.leading, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CaptionStylePreset.all) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func presetChip(_ preset: CaptionStylePreset) -> some View {
        let isSelected = editState.state.globalCaptionPreset.id == preset.id
        return Button {
            editState.state.globalCaptionPreset = preset
            editState.state.lastModified = Date()
        } label: {
            VStack(spacing: 5) {
                // Styled "Aa" preview
                let bg: Color = preset.bgType == .none
                    ? Color.white.opacity(0.08)
                    : preset.bgSwiftUIColor
                Text("Aa")
                    .font(.custom(preset.fontName, size: 15).weight(preset.isBold ? .bold : .regular))
                    .foregroundColor(preset.textSwiftUIColor)
                    .frame(width: 58, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(bg))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.2), value: isSelected)

                Text(preset.name)
                    .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 0) {
            // Color
            colorControl
            Spacer()
            // Position
            positionControl
            Spacer()
            // Size
            sizeControl
        }
    }

    // Color dot row
    private var colorControl: some View {
        VStack(spacing: 6) {
            Text("Color").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 6) {
                ForEach(colorPalette.indices, id: \.self) { i in
                    let c = colorPalette[i]
                    let isSelected = Color(editState.state.globalCaptionPreset.textUIColor) == c
                    Circle()
                        .fill(c)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(
                            isSelected ? Color.white : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 2.5 : 1
                        ))
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .animation(.spring(response: 0.2), value: isSelected)
                        .onTapGesture {
                            editState.state.globalCaptionPreset.textColorR = Double(c.cgColor?.components?[0] ?? 1)
                            editState.state.globalCaptionPreset.textColorG = Double(c.cgColor?.components?[1] ?? 1)
                            editState.state.globalCaptionPreset.textColorB = Double(c.cgColor?.components?[2] ?? 1)
                            editState.state.globalCaptionPreset.textColorA = 1
                            editState.state.lastModified = Date()
                        }
                }
            }
        }
    }

    private let colorPalette: [Color] = [
        .white, .yellow, Color(red: 1, green: 0.85, blue: 0),
        .cyan, Color(red: 1, green: 0.2, blue: 0.6),
        Color(red: 0.4, green: 0.8, blue: 1), .orange
    ]

    // Position selector
    private var positionControl: some View {
        VStack(spacing: 6) {
            Text("Position").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 5) {
                ForEach(CaptionPosition.allCases, id: \.self) { pos in
                    let isSelected = editState.state.globalCaptionPosition == pos
                    Button {
                        editState.state.globalCaptionPosition = pos
                        editState.state.lastModified = Date()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: positionIcon(pos))
                                .font(.system(size: 11))
                                .foregroundColor(isSelected ? .black : .white)
                            Text(pos.rawValue.prefix(3).capitalized)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(isSelected ? .black : .white.opacity(0.6))
                        }
                        .frame(width: 36, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.white : Color.white.opacity(0.1)))
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

    // Size stepper
    private var sizeControl: some View {
        VStack(spacing: 6) {
            Text("Size").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            HStack(spacing: 8) {
                Button {
                    let s = max(14, editState.state.globalCaptionPreset.fontSize - 2)
                    editState.state.globalCaptionPreset.fontSize = s
                    editState.state.lastModified = Date()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())

                Text("\(Int(editState.state.globalCaptionPreset.fontSize))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 28)

                Button {
                    let s = min(42, editState.state.globalCaptionPreset.fontSize + 2)
                    editState.state.globalCaptionPreset.fontSize = s
                    editState.state.lastModified = Date()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
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
                // Timestamp
                Text(formatTime(caption.startTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                // Text preview
                Text(caption.text.prefix(20) + (caption.text.count > 20 ? "…" : ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                // Delete
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
