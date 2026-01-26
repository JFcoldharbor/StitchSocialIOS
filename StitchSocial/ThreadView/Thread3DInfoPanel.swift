//
//  Thread3DInfoPanel.swift
//  StitchSocial
//
//  Layer 8: Views - Premium Info Panel for 3D Thread Visualization
//  Dependencies: CoreVideoMetadata
//  Features: Holographic glass design, animated borders, futuristic UI
//
//  DESIGN PHILOSOPHY: This panel should feel like a floating holographic HUD
//  that complements the 3D orbital thread visualization. Premium, sci-fi inspired,
//  but not overdone. Elegant futurism.
//

import SwiftUI

// MARK: - Main Info Panel

struct Thread3DInfoPanel: View {
    let parentVideo: CoreVideoMetadata
    let childVideos: [CoreVideoMetadata]
    let selectedVideo: CoreVideoMetadata?
    @Binding var isExpanded: Bool  // Change from @State to @Binding
    let onVideoTap: ((CoreVideoMetadata) -> Void)?
    let onClose: (() -> Void)?
    
    // Animation states
    @State private var borderRotation: Double = 0
    @State private var glowPulse: Double = 0.6
    @State private var selectedIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0  // Drag tracking
    @GestureState private var isDragging = false  // Active drag state
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            if isExpanded {
                // EXPANDED: Full holographic panel
                mainPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // COLLAPSED: Just the handle bar (minimal footprint)
                expandHandle
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Main Panel
    
    private var mainPanel: some View {
        let dragGesture = DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // Drag down = positive (collapse)
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 50  // Lowered from 100 for more sensitivity
                let velocity = value.predictedEndLocation.y - value.location.y
                
                // If dragged down enough or velocity suggests collapse
                if dragOffset > threshold || velocity > 300 {  // Lowered from 500
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded = false
                        dragOffset = 0
                    }
                } else {
                    // Snap back to expanded
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
        
        return VStack(spacing: 0) {
            // Handle - tap to collapse or drag to expand/collapse
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.cyan.opacity(0.4))
                    .frame(width: 24, height: 2)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.6), Color.purple.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 40, height: 4)
                
                Rectangle()
                    .fill(Color.purple.opacity(0.4))
                    .frame(width: 24, height: 2)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            }
            .gesture(dragGesture)
            
            // Content - FULL VERSION (only when expanded)
            VStack(spacing: 12) {
                // Header row
                headerRow
                
                // Selected video info (when a card is tapped in 3D view)
                if let selected = selectedVideo {
                    selectedVideoCard(selected)
                } else {
                    // Default: show creator card
                    creatorInfoCard
                }
                
                // Child video strip - only show if has children
                if childVideos.count > 0 {
                    childVideoStrip
                }
                
                // Stats row - compact
                statsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(panelBackground)
        .clipShape(PanelShape())
        .overlay(animatedBorder)
        .shadow(color: Color.cyan.opacity(0.2), radius: 40, y: -10)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Panel Background
    
    private var panelBackground: some View {
        ZStack {
            // Base blur
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Dark overlay for depth
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.05, blue: 0.12).opacity(0.9),
                    Color(red: 0.04, green: 0.02, blue: 0.08).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.overlay)
            
            // Subtle grid pattern
            gridPattern
                .opacity(0.03)
            
            // Top highlight
            VStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                Spacer()
            }
        }
    }
    
    private var gridPattern: some View {
        GeometryReader { geo in
            Path { path in
                let spacing: CGFloat = 20
                // Vertical lines
                for x in stride(from: 0, to: geo.size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                // Horizontal lines
                for y in stride(from: 0, to: geo.size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.cyan, lineWidth: 0.5)
        }
    }
    
    // MARK: - Animated Border
    
    private var animatedBorder: some View {
        PanelShape()
            .stroke(
                AngularGradient(
                    colors: [
                        Color.cyan.opacity(0.8),
                        Color.purple.opacity(0.6),
                        Color.pink.opacity(0.4),
                        Color.cyan.opacity(0.2),
                        Color.cyan.opacity(0.8)
                    ],
                    center: .center,
                    startAngle: .degrees(borderRotation),
                    endAngle: .degrees(borderRotation + 360)
                ),
                lineWidth: 1.5
            )
            .shadow(color: Color.cyan.opacity(glowPulse * 0.5), radius: 8)
    }
    
    // MARK: - Expand Handle (COMPACT)
    
    private var expandHandle: some View {
        let dragGesture = DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // Drag up = negative (expand), Drag down = positive (collapse)
                dragOffset = -value.translation.height
            }
            .onEnded { value in
                let threshold: CGFloat = 30  // Lowered from 50 for more sensitivity
                let velocity = -value.predictedEndLocation.y + value.location.y
                
                // If dragged up enough or velocity suggests expand
                if dragOffset > threshold || velocity < -300 {  // Lowered from -500
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded = true
                        dragOffset = 0
                    }
                } else {
                    // Snap back to collapsed
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded = false
                        dragOffset = 0
                    }
                }
            }
        
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.cyan.opacity(0.4))
                    .frame(width: 24, height: 2)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.6), Color.purple.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 40, height: 4)
                
                Rectangle()
                    .fill(Color.purple.opacity(0.4))
                    .frame(width: 24, height: 2)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            
            // Collapsed state: Show minimal stats
            if !isExpanded {
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                    
                    Text("\(childVideos.count) children")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("Tap to expand ↑")
                        .font(.caption2)
                        .foregroundStyle(Color.purple.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(panelBackground)
        .clipShape(PanelShape())
        .overlay(animatedBorder)
        .shadow(color: Color.cyan.opacity(0.2), radius: 40, y: -10)
        .padding(.horizontal, 12)
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .gesture(dragGesture)
    }
    
    // MARK: - Header Row (COMPACT)
    
    private var headerRow: some View {
        HStack {
            // 3D Badge - smaller
            HStack(spacing: 4) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("3D")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Spacer()
            
            // Stitch count - compact
            HStack(spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.cyan)
                
                Text("\(childVideos.count + 1)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Close button - smaller
            Button(action: { onClose?() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 30, height: 30)
                    
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.5), Color.purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .buttonStyle(HolographicButtonStyle())
        }
    }
    
    // MARK: - Creator Info Card (COMPACT)
    
    private var creatorInfoCard: some View {
        HStack(spacing: 12) {
            // Thumbnail with glow ring
            ZStack {
                // Glow ring
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [Color.cyan, Color.purple, Color.pink, Color.cyan],
                            center: .center,
                            startAngle: .degrees(borderRotation * 2),
                            endAngle: .degrees(borderRotation * 2 + 360)
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 56, height: 72)
                    .blur(radius: 2)
                
                // Real thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Simplified thumbnail loading
                    if !parentVideo.thumbnailURL.isEmpty, let url = URL(string: parentVideo.thumbnailURL) {
                        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(width: 50, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Info - tighter
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(parentVideo.creatorName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(parentVideo.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Thread indicator - smaller
            VStack(spacing: 2) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.8), Color.purple.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("ORIGIN")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.cyan.opacity(0.6))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Selected Video Card (COMPACT)
    
    private func selectedVideoCard(_ video: CoreVideoMetadata) -> some View {
        HStack(spacing: 12) {
            // Real video thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Simplified thumbnail loading
                if !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) {
                    AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 60, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.4), lineWidth: 1)
            )
            
            // Video info - tighter
            VStack(alignment: .leading, spacing: 4) {
                // Type badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(video.id == parentVideo.id ? Color.cyan : Color.purple)
                        .frame(width: 5, height: 5)
                    
                    Text(video.id == parentVideo.id ? "ORIGINAL" : "REPLY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(video.id == parentVideo.id ? Color.cyan : Color.purple)
                }
                
                Text(video.creatorName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Text(video.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                
                // Stats - inline
                HStack(spacing: 10) {
                    Label("\(video.hypeCount)", systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                    
                    Label("\(video.coolCount)", systemImage: "snowflake")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan)
                }
            }
            
            Spacer()
            
            // Watch button - smaller
            Button(action: { onVideoTap?(video) }) {
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("WATCH")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .buttonStyle(HolographicButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    // MARK: - Child Video Strip (COMPACT)
    
    private var childVideoStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header
            HStack {
                Text("REPLIES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(2)
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            
            // Horizontal scroll of child thumbnails - smaller
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(childVideos.enumerated()), id: \.element.id) { index, child in
                        ChildVideoThumbnail(
                            video: child,
                            index: index,
                            isSelected: selectedVideo?.id == child.id,
                            onTap: { onVideoTap?(child) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    // MARK: - Stats Row (COMPACT)
    
    private var statsRow: some View {
        HStack(spacing: 0) {
            StatItem(
                icon: "flame.fill",
                value: totalHype,
                label: "HYPE",
                color: Color.orange
            )
            
            Spacer()
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 24)
            
            Spacer()
            
            StatItem(
                icon: "snowflake",
                value: totalCool,
                label: "COOL",
                color: Color.cyan
            )
            
            Spacer()
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 24)
            
            Spacer()
            
            StatItem(
                icon: "eye.fill",
                value: totalViews,
                label: "VIEWS",
                color: Color.white.opacity(0.6)
            )
            
            Spacer()
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 24)
            
            Spacer()
            
            StatItem(
                icon: "person.2.fill",
                value: uniqueCreators,
                label: "CREATORS",
                color: Color.purple
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
    
    // MARK: - Computed Stats
    
    private var totalHype: Int {
        ([parentVideo] + childVideos).reduce(0) { $0 + $1.hypeCount }
    }
    
    private var totalCool: Int {
        ([parentVideo] + childVideos).reduce(0) { $0 + $1.coolCount }
    }
    
    private var totalViews: Int {
        ([parentVideo] + childVideos).reduce(0) { $0 + $1.viewCount }
    }
    
    private var uniqueCreators: Int {
        Set(([parentVideo] + childVideos).map { $0.creatorID }).count
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // PERFORMANCE: Slower animation (20 seconds instead of 8)
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            borderRotation = 360
        }
        
        // PERFORMANCE: Removed glow pulse animation - use static value
        // glowPulse stays at 0.6
    }
}

// MARK: - Child Video Thumbnail (COMPACT)

private struct ChildVideoThumbnail: View {
    let video: CoreVideoMetadata
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Real thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.2 + Double(index % 3) * 0.1),
                                    Color.cyan.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Simplified thumbnail loading
                    if !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) {
                        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // Index badge overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(index + 1)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(2)
                        }
                    }
                }
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.cyan : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(color: isSelected ? Color.cyan.opacity(0.5) : Color.clear, radius: 6)
                
                // Creator name
                Text(video.creatorName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .frame(width: 48)
            }
        }
        .buttonStyle(HolographicButtonStyle())
    }
}

// MARK: - Stat Item (COMPACT)

private struct StatItem: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                
                Text(formatNumber(value))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1000000 {
            return String(format: "%.1fM", Double(num) / 1000000)
        } else if num >= 1000 {
            return String(format: "%.1fK", Double(num) / 1000)
        }
        return "\(num)"
    }
}

// MARK: - Panel Shape

private struct PanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let cornerRadius: CGFloat = 32
        let notchWidth: CGFloat = 100
        let notchHeight: CGFloat = 6
        
        // Start from bottom left
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        
        // Left edge up to top left corner
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        
        // Top left corner
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        
        // Top edge to notch
        path.addLine(to: CGPoint(x: rect.midX - notchWidth/2, y: 0))
        
        // Notch (subtle dip)
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: -notchHeight),
            control: CGPoint(x: rect.midX - notchWidth/4, y: -notchHeight)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + notchWidth/2, y: 0),
            control: CGPoint(x: rect.midX + notchWidth/4, y: -notchHeight)
        )
        
        // Top edge continues
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: 0))
        
        // Top right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: cornerRadius),
            control: CGPoint(x: rect.maxX, y: 0)
        )
        
        // Right edge down
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        
        // Bottom edge
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        
        return path
    }
}

// MARK: - Holographic Button Style

private struct HolographicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
