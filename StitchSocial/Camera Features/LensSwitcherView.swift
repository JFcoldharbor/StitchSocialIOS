//
//  LensSwitcherView.swift
//  StitchSocial
//
//  Lens picker pill shown in RecordingView when multiple lenses available.
//  Reads availableLenses from CinematicCameraManager (cached at session start).
//  No Firebase reads. No caching needed — purely reactive to published state.

import SwiftUI

struct LensSwitcherView: View {
    @ObservedObject var cameraManager: CinematicCameraManager

    var body: some View {
        // Only show if more than 1 lens available
        guard cameraManager.availableLenses.count > 1 else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 4) {
                ForEach(cameraManager.availableLenses, id: \.rawValue) { lens in
                    lensButton(lens)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            )
        )
    }

    private func lensButton(_ lens: CameraLens) -> some View {
        let isActive = cameraManager.activeLens == lens

        return Button {
            Task { await cameraManager.switchToLens(lens) }
        } label: {
            Text(lens.displayLabel)
                .font(.system(size: 13, weight: isActive ? .bold : .medium, design: .rounded))
                .foregroundColor(isActive ? .black : .white)
                .frame(minWidth: 36, minHeight: 28)
                .background(
                    Capsule()
                        .fill(isActive ? Color.white : Color.clear)
                )
                .padding(.horizontal, 2)
        }
        .disabled(cameraManager.isRecording)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}
