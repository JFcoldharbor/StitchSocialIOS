//
//  CinematicRecordingButton.swift
//  StitchSocial
//
//  UPDATED: Tap to start, tap to stop. No hold required.
//  onPressStart fires on first tap, onPressEnd fires on second tap.
//

import SwiftUI

struct CinematicRecordingButton: View {
    @Binding var isRecording: Bool
    let totalDuration: TimeInterval
    let tierLimit: TimeInterval
    let onPressStart: () -> Void
    let onPressEnd: () -> Void
    var compactMode: Bool = false

    @State private var pulseAnimation = false
    @State private var scaleAnimation = false

    private var buttonSize: CGFloat { compactMode ? 66 : 80 }
    private var ringWidth: CGFloat { compactMode ? 5 : 6 }

    private var progress: Double {
        guard tierLimit > 0 else { return 0 }
        return min(totalDuration / tierLimit, 1.0)
    }

    private var progressColor: Color {
        if progress >= 0.9 { return .red }
        else if progress >= 0.8 { return .yellow }
        else { return .white }
    }

    var body: some View {
        ZStack {
            // Outer track ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: ringWidth)
                .frame(width: buttonSize + 12, height: buttonSize + 12)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, lineWidth: ringWidth)
                .frame(width: buttonSize + 12, height: buttonSize + 12)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            isRecording ? StitchColors.recordingActive.opacity(0.8) : StitchColors.primary.opacity(0.7),
                            isRecording ? StitchColors.recordingActive.opacity(0.6) : StitchColors.secondary.opacity(1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.1),
                                    StitchColors.primary.opacity(0.4),
                                    StitchColors.secondary.opacity(1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 0.8)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .frame(width: buttonSize, height: buttonSize)
                .scaleEffect(scaleAnimation ? 0.94 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: scaleAnimation)

            // Center icon
            if isRecording {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: compactMode ? 20 : 24, height: compactMode ? 20 : 24)
                    .opacity(pulseAnimation ? 0.7 : 1.0)
                    .shadow(color: .white.opacity(0.8), radius: 2.8)
                    .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
            } else if progress >= 1.0 {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: compactMode ? 24 : 28))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Circle()
                    .stroke(Color.white, lineWidth: compactMode ? 2.5 : 3)
                    .frame(width: compactMode ? 23 : 28, height: compactMode ? 23 : 28)
                    .overlay(
                        Circle()
                            .fill(StitchColors.recordingActive.opacity(0.8))
                            .frame(width: compactMode ? 14 : 18, height: compactMode ? 14 : 18)
                    )
                    .shadow(color: .white.opacity(0.8), radius: 2.8)
                    .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
            }
        }
        .shadow(
            color: isRecording ? StitchColors.recordingActive.opacity(0.6) : StitchColors.primary.opacity(0.6),
            radius: 16, x: 0, y: 6
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 25)
        // TAP to toggle start/stop
        .onTapGesture {
            guard progress < 1.0 else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scaleAnimation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scaleAnimation = false
            }
            if isRecording {
                onPressEnd()
            } else {
                onPressStart()
            }
        }
        .disabled(progress >= 1.0)
        .onAppear { if isRecording { startAnimations() } }
        .onChange(of: isRecording) { _, newValue in
            newValue ? startAnimations() : stopAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }

    private func stopAnimations() {
        pulseAnimation = false
    }
}
