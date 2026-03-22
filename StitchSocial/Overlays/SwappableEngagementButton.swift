//
//  SwappableEngagementButton.swift
//  StitchSocial
//
//  Wraps the Hype button slot in ContextualVideoOverlay.
//  Swipe UP   → slide to Tip button (Hype exits top, Tip enters from bottom)
//  Swipe DOWN → slide back to Hype (Tip exits bottom, Hype enters from top)
//
//  State resets to .hype when videoID changes (new video scrolled to).
//  No Firestore reads. No caching needed here — delegates to TipService/EngagementManager.
//

import SwiftUI

struct SwappableEngagementButton: View {

    // MARK: - Props
    let videoID: String
    let creatorID: String
    let currentHypeCount: Int
    let currentUserID: String
    let userTier: UserTier
    let currentTipCount: Int
    @ObservedObject var engagementManager: EngagementManager
    @ObservedObject var iconManager: FloatingIconManager

    // MARK: - State
    @State private var mode: EngagementButtonMode = .hype
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false

    private let swipeThreshold: CGFloat = 30

    // MARK: - Body

    var body: some View {
        ZStack {
            // Hype button layer
            hypeLayer

            // Tip button layer
            tipLayer

            // Swipe hint indicator
            swipeHint
        }
        .frame(width: 60, height: 100)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .onChange(of: videoID) { _ in
            // Reset to hype on new video — no animation needed
            mode = .hype
            dragOffset = 0
        }
    }

    // MARK: - Layers

    private var hypeLayer: some View {
        ProgressiveHypeButton(
            videoID: videoID,
            creatorID: creatorID,
            currentHypeCount: currentHypeCount,
            currentUserID: currentUserID,
            userTier: userTier,
            engagementManager: engagementManager,
            iconManager: iconManager
        )
        .offset(y: hypeOffset)
        .opacity(hypeOpacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: mode)
    }

    private var tipLayer: some View {
        TipButton(
            videoID: videoID,
            creatorID: creatorID,
            currentUserID: currentUserID,
            currentTipCount: currentTipCount,
            iconManager: iconManager
        )
        .offset(y: tipOffset)
        .opacity(tipOpacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: mode)
    }

    // MARK: - Swipe Hint (small chevron indicator)

    private var swipeHint: some View {
        VStack(spacing: 1) {
            Image(systemName: mode == .hype ? "chevron.up" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
        }
        .offset(y: 48)
    }

    // MARK: - Offsets & Opacity

    private var hypeOffset: CGFloat {
        switch mode {
        case .hype: return 0 + dragOffset * 0.3
        case .tip:  return -80
        }
    }

    private var hypeOpacity: Double {
        switch mode {
        case .hype: return 1.0
        case .tip:  return 0.0
        }
    }

    private var tipOffset: CGFloat {
        switch mode {
        case .hype: return 80
        case .tip:  return 0 + dragOffset * 0.3
        }
    }

    private var tipOpacity: Double {
        switch mode {
        case .hype: return 0.0
        case .tip:  return 1.0
        }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Only track vertical drag, small rubber-band feel
                dragOffset = value.translation.height * 0.4
            }
            .onEnded { value in
                let dy = value.translation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    dragOffset = 0

                    if dy < -swipeThreshold && mode == .hype {
                        // Swipe up → show Tip
                        mode = .tip
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if dy > swipeThreshold && mode == .tip {
                        // Swipe down → show Hype
                        mode = .hype
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
    }
}
