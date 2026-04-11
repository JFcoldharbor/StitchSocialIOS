//
//  CaptionOverlayView.swift
//  StitchSocial
//
//  Renders captions live over video using CaptionStylePreset.
//  Falls back to legacy CaptionStyle when no preset is set.
//  Safe zone positioning prevents overlap with ContextualVideoOverlay metadata.

import SwiftUI

// MARK: - Caption Overlay View

struct CaptionOverlayView: View {
    let captions: [VideoCaption]
    let currentTime: TimeInterval
    let videoSize: CGSize
    var enabled: Bool = true
    var globalPreset: CaptionStylePreset = .instaBoldStacked
    var globalPosition: CaptionPosition = .bottom

    private var activeCaptions: [VideoCaption] {
        guard enabled else { return [] }
        return captions.filter { currentTime >= $0.startTime && currentTime <= $0.endTime }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(activeCaptions) { caption in
                    // Use per-caption override if set, else global preset
                    let preset = caption.preset ?? globalPreset
                    let position = globalPosition
                    PresetCaptionView(caption: captionWithGlobals(caption, preset: preset, position: position))
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * position.safeOffset
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func captionWithGlobals(_ c: VideoCaption, preset: CaptionStylePreset, position: CaptionPosition) -> VideoCaption {
        var copy = c
        copy.preset = preset
        copy.position = position
        return copy
    }
}

// MARK: - Preset Caption View

struct PresetCaptionView: View {
    let caption: VideoCaption

    var body: some View {
        if let preset = caption.preset {
            PresetStyledText(text: caption.text, preset: preset)
        } else {
            LegacyCaptionText(caption: caption)
        }
    }
}

// MARK: - Preset Styled Text

struct PresetStyledText: View {
    let text: String
    let preset: CaptionStylePreset
    @State private var size: CGSize = .zero

    var body: some View {
        switch preset.bgType {
        case .none:
            textView.shadow(color: .black.opacity(0.7), radius: 2, x: 1, y: 1)

        case .pill:
            textView
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(
                    Capsule().fill(preset.bgSwiftUIColor)
                )

        case .fullBar:
            textView
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(preset.bgSwiftUIColor)

        case .highlightWord:
            // Word-by-word highlight — each word gets its own colored pill
            WordHighlightView(text: text, preset: preset)

        case .outline:
            ZStack {
                // Stroke layer
                Text(text)
                    .font(preset.swiftUIFont)
                    .foregroundColor(preset.bgSwiftUIColor)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                // Text layer on top
                textView
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }

        case .blur:
            textView
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(preset.bgSwiftUIColor)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                )
        }
    }

    private var textView: some View {
        Text(text)
            .font(preset.swiftUIFont)
            .foregroundColor(preset.textSwiftUIColor)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .overlay(
                preset.strokeWidth > 0
                ? AnyView(strokeOverlay) : AnyView(EmptyView())
            )
    }

    private var strokeOverlay: some View {
        Text(text)
            .font(preset.swiftUIFont)
            .foregroundColor(.clear)
            .overlay(
                Text(text)
                    .font(preset.swiftUIFont)
                    .foregroundColor(Color(preset.strokeUIColor))
                    .blur(radius: preset.strokeWidth * 0.5)
            )
    }
}

// MARK: - Word Highlight View (Instagram Bold Stacked / Karaoke)

struct WordHighlightView: View {
    let text: String
    let preset: CaptionStylePreset

    var words: [String] { text.components(separatedBy: .whitespaces).filter { !$0.isEmpty } }

    var body: some View {
        // Wrap words — each on a new line if they don't fit (simple vertical stack)
        VStack(spacing: 4) {
            // Group into lines of ~3-4 words (CapCut stacked style)
            let lines = groupedLines(words: words, maxPerLine: 3)
            ForEach(lines.indices, id: \.self) { lineIdx in
                HStack(spacing: 4) {
                    ForEach(lines[lineIdx], id: \.self) { word in
                        Text(word)
                            .font(preset.swiftUIFont)
                            .foregroundColor(preset.textSwiftUIColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(preset.bgSwiftUIColor)
                            )
                    }
                }
            }
        }
    }

    private func groupedLines(words: [String], maxPerLine: Int) -> [[String]] {
        var lines: [[String]] = []
        var current: [String] = []
        for word in words {
            current.append(word)
            if current.count >= maxPerLine {
                lines.append(current)
                current = []
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - Legacy Caption Text (fallback)

struct LegacyCaptionText: View {
    let caption: VideoCaption

    var body: some View {
        Text(caption.text)
            .font(.system(size: caption.style.fontSize,
                          weight: caption.style.fontWeight == "bold" ? .bold : .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
    }
}

// MARK: - Styled Caption Text (legacy alias kept for compatibility)

typealias StyledCaptionText = LegacyCaptionText
