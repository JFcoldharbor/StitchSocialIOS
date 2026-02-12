//
//  VideoNavigationPeeks.swift
//  StitchSocial
//
//  Layer 8: Views - Edge Peek Navigation Indicators
//  Shows previous/next video thumbnails on screen edges with floating icon styling
//  Dependencies: SwiftUI, CoreVideoMetadata

import SwiftUI
import CoreHaptics

struct VideoNavigationPeeks: View {
    
    // MARK: - Properties
    
    let allVideos: [CoreVideoMetadata]
    let currentVideoIndex: Int
    
    @State private var pulseIntensity: Double = 1.0
    @State private var hapticEngine: CHHapticEngine?
    @State private var hapticPlayedForVideoID: String = ""
    @State private var isHapticActive = false
    @State private var prevThumbnail: UIImage? = nil
    @State private var nextThumbnail: UIImage? = nil
    
    // MARK: - Computed Properties
    
    private var previousVideo: CoreVideoMetadata? {
        guard currentVideoIndex > 0 else { return nil }
        return allVideos[currentVideoIndex - 1]
    }
    
    private var nextVideo: CoreVideoMetadata? {
        guard currentVideoIndex < allVideos.count - 1 else { return nil }
        return allVideos[currentVideoIndex + 1]
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // Left peek - Previous video (on LEFT edge)
                if let prev = previousVideo {
                    HStack(spacing: 0) {
                        navigationPeekCard(
                            video: prev,
                            position: .left,
                            geometry: geometry
                        )
                        .frame(width: 45, height: 80)
                        
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                }
                
                // Right peek - Next video (on RIGHT edge)
                if let next = nextVideo {
                    HStack(spacing: 0) {
                        Spacer()
                        
                        navigationPeekCard(
                            video: next,
                            position: .right,
                            geometry: geometry
                        )
                        .frame(width: 45, height: 80)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            startHeartbeatAnimation()
            setupHapticEngine()
            loadPeekThumbnails()
        }
        .onChange(of: currentVideoIndex) { _, _ in
            stopHeartbeatHaptic()
            loadPeekThumbnails()
        }
        .onDisappear {
            stopHeartbeatHaptic()
        }
    }
    
    // MARK: - Thumbnail Loading (NSCache, no AsyncImage)
    
    private func loadPeekThumbnails() {
        prevThumbnail = nil
        nextThumbnail = nil
        
        if let prev = previousVideo {
            loadThumbnail(for: prev) { image in
                prevThumbnail = image
            }
        }
        if let next = nextVideo {
            loadThumbnail(for: next) { image in
                nextThumbnail = image
            }
        }
    }
    
    private func loadThumbnail(for video: CoreVideoMetadata, completion: @escaping (UIImage) -> Void) {
        // NSCache hit — instant
        if let cached = ThumbnailCache.shared.get(video.id) {
            completion(cached)
            return
        }
        guard !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) else { return }
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            ThumbnailCache.shared.set(image, for: video.id)
            await MainActor.run { completion(image) }
        }
    }
    
    // MARK: - Heartbeat Animation
    
    private func startHeartbeatAnimation() {
        func performHeartbeat() {
            withAnimation(.easeInOut(duration: 0.1)) {
                pulseIntensity = 1.5
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    pulseIntensity = 0.6
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    pulseIntensity = 1.5
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    pulseIntensity = 0.6
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                performHeartbeat()
            }
        }
        
        performHeartbeat()
    }
    
    // MARK: - Haptic Feedback
    
    private func setupHapticEngine() {
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            
            let hapticEnabled = UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled") || true
            
            let currentVideo = allVideos[safe: currentVideoIndex] ?? allVideos.first
            if hapticEnabled,
               allVideos.count > 1,
               let currentVideo = currentVideo,
               currentVideo.id != hapticPlayedForVideoID {
                
                hapticPlayedForVideoID = currentVideo.id
                startHeartbeatHaptic()
            }
        } catch {
            print("Haptic setup failed: \(error)")
        }
    }
    
    private func startHeartbeatHaptic() {
        isHapticActive = true
        
        func performHeartbeatHaptic() {
            guard isHapticActive else { return }
            
            playHeartbeatHapticPattern()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if self.isHapticActive {
                    performHeartbeatHaptic()
                }
            }
        }
        
        performHeartbeatHaptic()
    }
    
    private func stopHeartbeatHaptic() {
        isHapticActive = false
        try? hapticEngine?.stop(completionHandler: nil)
    }
    
    private func playHeartbeatHapticPattern() {
        guard let engine = hapticEngine else { return }
        
        do {
            var events = [CHHapticEvent]()
            
            let firstBeat = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: 0.1
            )
            events.append(firstBeat)
            
            let secondBeat = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0.2,
                duration: 0.1
            )
            events.append(secondBeat)
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play heartbeat haptic: \(error)")
        }
    }
    
    // MARK: - Navigation Peek Card
    
    @ViewBuilder
    private func navigationPeekCard(
        video: CoreVideoMetadata,
        position: PeekPosition,
        geometry: GeometryProxy
    ) -> some View {
        let thumbnail = position == .left ? prevThumbnail : nextThumbnail
        
        ZStack {
            // Cached thumbnail — no AsyncImage, no re-downloads per swipe
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 45, height: 80)
            .clipped()
            .cornerRadius(8)
            
            // Overlay gradient for depth
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.1),
                            Color.clear,
                            Color.black.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Direction indicator
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    if position == .left {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("prev")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    } else {
                        Text("next")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(6)
            }
        }
        .frame(width: 45, height: 80)  // ⭐ DOUBLE LOCK at ZStack level too
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.7),
                            Color.purple.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: position == .left ?
                            [.cyan.opacity(0.6), .blue.opacity(0.4)] :
                            [.orange.opacity(0.6), .pink.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .id(video.thumbnailURL)  // ⭐ NEW: Force view reload on thumbnail change
        .padding(
            position == .left ? .leading : .trailing,
            8
        )
    }
}

// MARK: - Supporting Types

enum PeekPosition {
    case left
    case right
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        Text("VideoNavigationPeeks Component")
            .foregroundColor(.white)
    }
}
