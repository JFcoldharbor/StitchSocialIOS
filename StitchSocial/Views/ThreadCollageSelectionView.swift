//
//  ThreadCollageSelectionView.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Collage Clip Selection & Build UI
//  Dependencies: ThreadCollageService (Layer 4), CollageConfiguration (Layer 3), VideoService
//  Features: Select main + 3-5 responses, preview time allocation, build & export collage
//
//  CACHING: Uses pre-loaded ThreadData — zero additional Firestore reads for selection.
//  Thumbnails should come from existing ThumbnailCacheManager (no re-generation).
//  AVAssets only loaded when user taps "Build Collage" via batched TaskGroup in service.
//

import SwiftUI
import AVKit

// MARK: - Main Selection View

struct ThreadCollageSelectionView: View {
    
    // MARK: - Properties
    
    /// Pre-loaded thread data — NO extra Firebase reads needed
    let threadData: ThreadData
    
    @StateObject private var collageService = ThreadCollageService()
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var showingBuildConfirmation = false
    @State private var showingSettings = false
    @State private var showingShareSheet = false
    @State private var exportedVideoURL: URL?
    @State private var buildError: String?
    @State private var trimEditingClipID: String?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerBar
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        mainVideoSection
                        responsesSection
                        
                        if collageService.canBuildCollage {
                            allocationPreview
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                
                bottomBar
            }
            
            // Build progress overlay
            if case .idle = collageService.state {} else {
                if case .selectingClips = collageService.state {} else {
                    if case .completed = collageService.state {} else {
                        buildProgressOverlay
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            CollageSettingsSheet(configuration: $collageService.configuration)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: .init(
            get: { trimEditingClipID != nil },
            set: { if !$0 { trimEditingClipID = nil } }
        )) {
            if let clipID = trimEditingClipID,
               let clipIndex = collageService.selectedClips.firstIndex(where: { $0.id == clipID }) {
                ClipTrimView(
                    clip: $collageService.selectedClips[clipIndex],
                    onDone: {
                        trimEditingClipID = nil
                    },
                    onRemove: collageService.selectedClips[clipIndex].isMainClip ? nil : {
                        let video = collageService.selectedClips[clipIndex].videoMetadata
                        _ = collageService.toggleResponseVideo(video)
                        trimEditingClipID = nil
                    }
                )
            }
        }
        .onChange(of: collageService.state) { newState in
            if case .completed(let url) = newState {
                exportedVideoURL = url
                showingShareSheet = true
            } else if case .failed(let error) = newState {
                buildError = error
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedVideoURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Build Failed", isPresented: .init(
            get: { buildError != nil },
            set: { if !$0 { buildError = nil } }
        )) {
            Button("OK") { buildError = nil }
        } message: {
            Text(buildError ?? "Unknown error")
        }
        .onAppear {
            // Kill all background playback — prevents audio overlap
            BackgroundActivityManager.shared.killAllBackgroundActivity(reason: "Collage selection")
            VideoPreloadingService.shared.pauseAllPlayback()
            
            // Set main video from thread parent — no Firebase call
            collageService.setMainVideo(threadData.parentVideo)
        }
        .onDisappear {
            collageService.cleanup()
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            Button {
                collageService.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Thread Collage")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Main Video Section
    
    private var mainVideoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                Text("MAIN VIDEO")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.2)
            }
            
            mainVideoCard(threadData.parentVideo)
        }
    }
    
    private func mainVideoCard(_ video: CoreVideoMetadata) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView(for: video, size: CGSize(width: 80, height: 120))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow, lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title.isEmpty ? "Main Stitch" : video.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text("@\(video.creatorName)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(spacing: 12) {
                    Label(formatDuration(video.duration), systemImage: "clock")
                    Label("\(video.hypeCount)", systemImage: "flame")
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Responses Section
    
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)
                Text("SELECT RESPONSES (\(collageService.responseClipCount)/\(ThreadCollageService.maxResponseClips))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.2)
                
                Spacer()
                
                if collageService.responseClipCount < ThreadCollageService.minResponseClips {
                    Text("min \(ThreadCollageService.minResponseClips)")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            
            if threadData.childVideos.isEmpty {
                emptyResponsesView
            } else {
                // Horizontal scroll of response cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(threadData.childVideos, id: \.id) { video in
                            responseCard(video)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func responseCard(_ video: CoreVideoMetadata) -> some View {
        let isSelected = collageService.isSelected(video.id)
        
        return Button {
            if isSelected {
                // Already selected — open trim editor
                trimEditingClipID = video.id
            } else {
                withAnimation(.spring(response: 0.3)) {
                    _ = collageService.toggleResponseVideo(video)
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    thumbnailView(for: video, size: CGSize(width: 100, height: 150))
                    
                    // Selection indicator
                    if isSelected {
                        // Checkmark top-right
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.cyan)
                            .background(Circle().fill(Color.black.opacity(0.5)).padding(-2))
                            .offset(x: -6, y: 6)
                    }
                    
                    // Trim hint on selected clips
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 9))
                                Text("Trim")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(4)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
                )
                
                VStack(spacing: 2) {
                    Text("@\(video.creatorName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    
                    Text(formatDuration(video.duration))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: 100)
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                // Long press to deselect
                if isSelected {
                    withAnimation(.spring(response: 0.3)) {
                        _ = collageService.toggleResponseVideo(video)
                    }
                }
            }
        )
    }
    
    private var emptyResponsesView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.3))
                Text("No responses in this thread yet")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 30)
            Spacer()
        }
    }
    
    // MARK: - Allocation Preview
    
    private var allocationPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                Text("TIME ALLOCATION")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.2)
                
                Spacer()
                
                Text("\(Int(collageService.configuration.totalDuration))s total")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Visual bar showing time distribution
            timeDistributionBar
            
            // Per-clip breakdown
            VStack(spacing: 6) {
                ForEach(collageService.selectedClips) { clip in
                    allocationRow(clip: clip)
                }
                
                // Watermark end card
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                    Text("Creator Watermark")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("\(Int(collageService.configuration.watermarkDuration))s")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
    
    private var timeDistributionBar: some View {
        GeometryReader { geo in
            let total = collageService.configuration.totalDuration
            HStack(spacing: 1) {
                ForEach(collageService.selectedClips) { clip in
                    let fraction = clip.allocatedDuration / total
                    RoundedRectangle(cornerRadius: 3)
                        .fill(clip.isMainClip ? Color.yellow : Color.cyan)
                        .frame(width: max(4, geo.size.width * fraction))
                }
                
                // Watermark segment
                let wmFraction = collageService.configuration.watermarkDuration / total
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: max(4, geo.size.width * wmFraction))
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private func allocationRow(clip: CollageClip) -> some View {
        HStack {
            Circle()
                .fill(clip.isMainClip ? Color.yellow : Color.cyan)
                .frame(width: 8, height: 8)
            
            Text(clip.isMainClip ? "Main" : "@\(clip.videoMetadata.creatorName)")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            
            Spacer()
            
            Text("\(Int(clip.allocatedDuration))s of \(Int(clip.originalDuration))s")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(clip.isMainClip ? .yellow : .cyan)
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))
            
            HStack(spacing: 16) {
                // Clip count indicator
                HStack(spacing: 4) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 14))
                    Text("\(collageService.selectedClips.count) clips")
                        .font(.system(size: 14))
                }
                .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                // Build button
                Button {
                    Task {
                        // Recalculate allocations before build
                        do {
                            let url = try await collageService.buildCollage()
                            exportedVideoURL = url
                        } catch {
                            if !Task.isCancelled {
                                buildError = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Build Collage")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: collageService.canBuildCollage
                                ? [Color.cyan, Color.blue]
                                : [Color.gray.opacity(0.4), Color.gray.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                }
                .disabled(!collageService.canBuildCollage)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.95))
        }
    }
    
    // MARK: - Build Progress Overlay
    
    private var buildProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Phase indicator
                phaseIcon
                
                Text(phaseLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: collageService.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                        .scaleEffect(y: 2)
                    
                    Text("\(Int(collageService.progress * 100))%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 200)
                
                Button {
                    collageService.cancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                }
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
    }
    
    private var phaseIcon: some View {
        Group {
            switch collageService.state {
            case .loadingAssets:
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 36))
                    .foregroundColor(.cyan)
            case .composing:
                Image(systemName: "film.stack")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
            case .addingWatermark:
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)
            case .exporting:
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
            default:
                Image(systemName: "gear")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var phaseLabel: String {
        switch collageService.state {
        case .loadingAssets: return "Loading clips..."
        case .composing: return "Building collage..."
        case .addingWatermark: return "Adding watermark..."
        case .exporting(let p): return "Exporting \(Int(p * 100))%..."
        case .failed(let e): return "Failed: \(e)"
        default: return "Processing..."
        }
    }
    
    // MARK: - Shared Components
    
    /// Thumbnail view — uses thumbnailURL from CoreVideoMetadata
    /// CACHING: Should pull from ThumbnailCacheManager, not re-download
    private func thumbnailView(for video: CoreVideoMetadata, size: CGSize) -> some View {
        AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            case .failure:
                placeholderThumbnail(size: size)
            case .empty:
                placeholderThumbnail(size: size)
                    .overlay(ProgressView().tint(.white))
            @unknown default:
                placeholderThumbnail(size: size)
            }
        }
        .cornerRadius(8)
    }
    
    private func placeholderThumbnail(size: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: size.width, height: size.height)
            .overlay(
                Image(systemName: "play.fill")
                    .foregroundColor(.white.opacity(0.3))
            )
            .cornerRadius(8)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return mins > 0 ? "\(mins):\(String(format: "%02d", secs))" : "\(secs)s"
    }
}

// MARK: - Settings Sheet

struct CollageSettingsSheet: View {
    @Binding var configuration: CollageConfiguration
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Time strategy
                        settingsSection(title: "Time Distribution") {
                            Picker("Strategy", selection: $configuration.timeStrategy) {
                                ForEach(TimeStrategy.allCases, id: \.self) { strategy in
                                    Text(strategy.displayName).tag(strategy)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Transition
                        settingsSection(title: "Transition") {
                            Picker("Transition", selection: $configuration.transitionType) {
                                ForEach(CollageTransition.allCases, id: \.self) { transition in
                                    Text(transition.displayName).tag(transition)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Resolution
                        settingsSection(title: "Quality") {
                            Picker("Resolution", selection: $configuration.outputResolution) {
                                ForEach(OutputResolution.allCases, id: \.self) { res in
                                    Text(res.displayName).tag(res)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Watermark duration
                        settingsSection(title: "Watermark End Card") {
                            HStack {
                                Text("\(Int(configuration.watermarkDuration))s")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                Slider(
                                    value: $configuration.watermarkDuration,
                                    in: 2...5,
                                    step: 1
                                )
                                .tint(.cyan)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Collage Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.0)
            
            content()
        }
    }
}
