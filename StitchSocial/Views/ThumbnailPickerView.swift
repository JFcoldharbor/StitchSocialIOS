//
//  ThumbnailPickerView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/11/26.
//


//
//  ThumbnailPickerView.swift
//  StitchSocial
//
//  Layer 8: Views - Video Thumbnail Selector
//  Dependencies: AVFoundation
//  Features: Filmstrip frame extraction, tap-to-select cover image, scrub preview
//
//  CACHING: Extracts frames ONCE on appear, stores [CGImage] in memory.
//  Cleanup: Clears frame cache on disappear. If VideoTrimmerView needs the same
//  frames, pass thumbnailFrames through VideoEditState to avoid double extraction.
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
    
    private let frameCount = 15
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
                Text("Could not load video frames")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(height: frameHeight)
                    .frame(maxWidth: .infinity)
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
        .onAppear { extractFrames() }
        .onDisappear { clearFrameCache() }
    }
    
    // MARK: - Frame Extraction (runs once, cached in @State)
    
    private func extractFrames() {
        guard frames.isEmpty && !isExtracting else { return }
        guard videoDuration > 0 else { return }
        
        isExtracting = true
        
        Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 356) // Downscaled for memory
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            let interval = videoDuration / Double(frameCount)
            var extracted: [(time: TimeInterval, image: CGImage)] = []
            
            for i in 0..<frameCount {
                let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
                do {
                    let (image, _) = try await generator.image(at: time)
                    extracted.append((time: interval * Double(i), image: image))
                } catch {
                    // Skip failed frames silently
                    continue
                }
            }
            
            await MainActor.run {
                frames = extracted
                isExtracting = false
            }
        }
    }
    
    private func clearFrameCache() {
        frames.removeAll()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}