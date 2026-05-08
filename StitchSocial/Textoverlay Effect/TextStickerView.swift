//
//  TextStickerView.swift
//  StitchSocial
//
//  Renders a single TextOverlay as a styled SwiftUI view.
//  Used both in the editor canvas and as preview in VideoReviewView.
//
//  WYSIWYG: this file and VideoExportService+TextOverlays.buildTextLayer
//  are the two sides of the same render. They MUST stay in sync — same
//  font (via overlay.font), same scale model (transform applied after
//  text + padding render), same per-style chrome.
//
//  CACHING: Pure view — no side effects, no reads. Re-renders only on overlay change.

import SwiftUI

struct TextStickerView: View {
    let overlay: TextOverlay
    var isSelected: Bool = false

    /// Resolves to a SwiftUI Font using overlay.font and overlay.fontSize.
    /// Centralized so we can't accidentally drift back to .system everywhere.
    private var resolvedFont: Font {
        overlay.font.swiftUIFont(size: overlay.fontSize, bold: overlay.isBold)
    }

    var body: some View {
        styledText
            // Apply scale + rotation as transforms AFTER the styled view is
            // rendered, so padding and chrome scale uniformly. Export does
            // the same on its container CALayer for parity.
            .scaleEffect(overlay.scale)
            .rotationEffect(.degrees(overlay.rotation))
            .overlay(
                isSelected ? selectionBorder : nil
            )
    }

    @ViewBuilder
    private var styledText: some View {
        switch overlay.style {
        case .boldPill:
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color(overlay.bgColor))
                )

        case .outline:
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .shadow(color: Color(overlay.textColor).opacity(0.6), radius: 0, x: 1, y: 1)
                .shadow(color: Color(overlay.textColor).opacity(0.6), radius: 0, x: -1, y: -1)
                .overlay(
                    Text(overlay.text)
                        .font(resolvedFont)
                        .foregroundColor(.black.opacity(0.5))
                        .offset(x: 1.5, y: 1.5)
                )

        case .neon:
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .shadow(color: Color(overlay.textColor).opacity(0.9), radius: 8)
                .shadow(color: Color(overlay.textColor).opacity(0.5), radius: 16)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(overlay.bgColor))
                )

        case .typewriter:
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(overlay.bgColor))
                )

        case .gradient:
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(overlay.textColor), Color(overlay.textColor).opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 4)

        // ── Phase 4 styles ─────────────────────────────────────────────

        case .ribbon:
            // Banner-style: text on a flat colored bar with notched ends.
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(
                    RibbonShape().fill(Color(overlay.bgColor))
                )

        case .shadow:
            // Heavy drop shadow, no background.
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .shadow(color: .black.opacity(0.85), radius: 0, x: 4, y: 4)
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

        case .glitch:
            // Stacked RGB-split layers for a chromatic aberration look.
            ZStack {
                Text(overlay.text)
                    .font(resolvedFont)
                    .foregroundColor(.cyan)
                    .offset(x: -2, y: 0)
                Text(overlay.text)
                    .font(resolvedFont)
                    .foregroundColor(.red)
                    .offset(x: 2, y: 0)
                Text(overlay.text)
                    .font(resolvedFont)
                    .foregroundColor(Color(overlay.textColor))
            }

        case .handwritten:
            // Snell Roundhand or similar script fallback.
            Text(overlay.text)
                .font(.custom("SnellRoundhand-Bold", size: overlay.fontSize))
                .foregroundColor(Color(overlay.textColor))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)

        case .sticker:
            // IG story sticker: thick white border around colored fill.
            Text(overlay.text)
                .font(resolvedFont)
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(overlay.bgColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white, lineWidth: 4)
                        )
                )
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .padding(-6)
    }
}

// MARK: - Ribbon Shape

private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch: CGFloat = min(10, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - notch, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: notch, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
