//
//  ThumbnailPickerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Thumbnail Selector
//  Dependencies: AVFoundation
//  Features: Filmstrip frame extraction, tap-to-select cover image, scrub preview
//
//  FIX: videoDuration race condition — ThreadComposer loads duration async so it
//  arrives as 0 on first render. Two changes:
//  1. extractFrames() reads duration from the asset directly if videoDuration == 0
//  2. .onChange(of: videoDuration) retries if duration arrives after first render
//
//  CACHING: Extracts frames ONCE, stored in @State [CGImage].
//  Cleared on disappear to free memory.
//

import SwiftUI
import AVFoundation

struct ThumbnailPickerView: View {

    let videoURL: URL
    let videoDuration: TimeInterval
    @Binding var selectedThumbnailTime: TimeInterval?

    @State private var frames: [(time: TimeInterval, image: CGImage)] = []
    @State private var isExtracting = false
    @State private var selectedIndex: Int? = nil

    private let frameCount  = 15
    private let frameHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack {
                Image(systemName: "photo.on.rectangle")
                    .foregroundColor(.cyan)
                Text("Cover Image")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if selectedThumbnailTime != nil {
                    Button {
                        selectedThumbnailTime = nil
                        selectedIndex = nil
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Content
            if isExtracting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    Text("Loading frames...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(height: frameHeight)
                .frame(maxWidth: .infinity)

            } else if frames.isEmpty {
                // Show spinner if still waiting for duration, error text only if we truly failed
                if videoDuration == 0 {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        Text("Preparing video...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(height: frameHeight)
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Could not load video frames")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(height: frameHeight)
                        .frame(maxWidth: .infinity)
                }

            } else {
                // Filmstrip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                            Image(decorative: frame.image, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: frameHeight)
                                .clipped()
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            selectedIndex == index ? Color.cyan : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .overlay(
                                    selectedIndex == index ?
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.cyan)
                                            .shadow(color: .black, radius: 2)
                                        : nil
                                )
                                .onTapGesture {
                                    selectedIndex = index
                                    selectedThumbnailTime = frame.time
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Timestamp label
                if let idx = selectedIndex, idx < frames.count {
                    Text("Cover at \(formatTime(frames[idx].time))")
                        .font(.caption)
                        .foregroundColor(.cyan)
                } else {
                    Text("Tap a frame to set as cover (default: first frame)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            extractFrames()
        }
        // FIX: retry when duration arrives from ThreadComposer's async detectVideoProperties()
        .onChange(of: videoDuration) { _, newDuration in
            guard newDuration > 0, frames.isEmpty, !isExtracting else { return }
            extractFrames()
        }
        .onDisappear {
            frames.removeAll()
        }
    }

    // MARK: - Frame Extraction

    private func extractFrames() {
        guard frames.isEmpty, !isExtracting else { return }
        isExtracting = true

        Task.detached(priority: .userInitiated) {
            let asset    = AVAsset(url: videoURL)
            let duration: TimeInterval

            // FIX: if videoDuration is 0 (race condition), load it directly from the asset
            // This way the picker works even if ThreadComposer hasn't finished detecting yet
            if videoDuration > 0 {
                duration = videoDuration
            } else {
                let cmDuration = try? await asset.load(.duration)
                duration = cmDuration.map { CMTimeGetSeconds($0) } ?? 0
            }

            guard duration > 0 else {
                await MainActor.run { isExtracting = false }
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 356)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

            let interval = duration / Double(frameCount)
            var extracted: [(time: TimeInterval, image: CGImage)] = []

            for i in 0..<frameCount {
                let t = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
                if let (image, _) = try? await generator.image(at: t) {
                    extracted.append((time: interval * Double(i), image: image))
                }
            }

            await MainActor.run {
                frames         = extracted
                isExtracting   = false

                // Auto-select first frame so there's always a default cover
                if !extracted.isEmpty, selectedIndex == nil {
                    selectedIndex        = 0
                    selectedThumbnailTime = extracted[0].time
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
