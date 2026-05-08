//
//  CaptionOverlayView.swift
//  StitchSocial
//
//  Standard caption renderer. ONE hardcoded style (white text, black pill,
//  bold) so what's on screen always matches what gets exported. The only
//  per-video knob is the global vertical position (top / center / bottom).

import SwiftUI

struct CaptionOverlayView: View {
    let captions: [VideoCaption]
    let currentTime: TimeInterval
    var enabled: Bool = true
    var globalPosition: CaptionPosition = .bottom

    private var activeCaptions: [VideoCaption] {
        guard enabled else { return [] }
        return captions.filter { currentTime >= $0.startTime && currentTime <= $0.endTime }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(activeCaptions) { caption in
                    StandardCaptionText(text: caption.text)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * globalPosition.safeOffset
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Standard Caption Text
//
// Single hardcoded style. If we ever want to bring back style choice this is
// where to add it — but right now it intentionally has no inputs beyond the
// text itself so preview and export can never drift apart.

struct StandardCaptionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color.black.opacity(0.6))
            )
    }
}
