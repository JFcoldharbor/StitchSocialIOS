//
//  TextStickerView.swift
//  StitchSocial
//
//  Created by James Garmon on 4/11/26.
//


//
//  TextStickerView.swift
//  StitchSocial
//
//  Renders a single TextOverlay as a styled SwiftUI view.
//  Used both in the editor canvas and as preview in VideoReviewView.
//  CACHING: Pure view — no side effects, no reads. Re-renders only on overlay change.

import SwiftUI

struct TextStickerView: View {
    let overlay: TextOverlay
    var isSelected: Bool = false

    var body: some View {
        styledText
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
                .font(.system(size: overlay.fontSize,
                              weight: overlay.isBold ? .bold : .semibold,
                              design: .default))
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color(overlay.bgColor))
                )

        case .outline:
            Text(overlay.text)
                .font(.system(size: overlay.fontSize,
                              weight: overlay.isBold ? .bold : .semibold))
                .foregroundColor(Color(overlay.textColor))
                .shadow(color: Color(overlay.textColor).opacity(0.6), radius: 0, x: 1, y: 1)
                .shadow(color: Color(overlay.textColor).opacity(0.6), radius: 0, x: -1, y: -1)
                .overlay(
                    Text(overlay.text)
                        .font(.system(size: overlay.fontSize,
                                      weight: overlay.isBold ? .bold : .semibold))
                        .foregroundColor(.black.opacity(0.5))
                        .offset(x: 1.5, y: 1.5)
                )

        case .neon:
            Text(overlay.text)
                .font(.system(size: overlay.fontSize,
                              weight: overlay.isBold ? .bold : .semibold))
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
                .font(.system(size: overlay.fontSize,
                              weight: .regular, design: .monospaced))
                .foregroundColor(Color(overlay.textColor))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(overlay.bgColor))
                )

        case .gradient:
            Text(overlay.text)
                .font(.system(size: overlay.fontSize,
                              weight: overlay.isBold ? .bold : .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(overlay.textColor), Color(overlay.textColor).opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .padding(-6)
    }
}