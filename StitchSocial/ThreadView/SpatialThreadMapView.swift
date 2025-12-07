//
//  SpatialThreadMapView.swift
//  StitchSocial
//
//  Layer 8: Views - Main Orbital Interface Container (FIXED: Touch passthrough)
//  Dependencies: OrbitalLayoutCalculator (Layer 5), VideoService (Layer 4)
//  Features: Central thread display, orbital child positioning, page navigation
//  ARCHITECTURE COMPLIANT: No business logic, uses calculated positions
//  CRITICAL: Only child orbs and pagination buttons block touches - everything else passes through
//

import SwiftUI

/// Main spatial thread map showing orbital interface with central thread and orbiting children
struct SpatialThreadMapView: View {
    
    // MARK: - Properties
    
    let parentThread: CoreVideoMetadata
    let children: [CoreVideoMetadata]
    let onChildSelected: ((CoreVideoMetadata) -> Void)?
    let onEngagement: ((CoreVideoMetadata, InteractionType) -> Void)?
    let onParentTapped: (() -> Void)?
    
    // MARK: - State
    
    @State private var currentPage: Int = 0
    @State private var selectedChildID: String?
    @State private var orbitalPositions: [OrbitalPosition] = []
    @State private var animationProgress: Double = 0.0
    
    // MARK: - Computed Properties
    
    private var childrenData: [ChildThreadData] {
        children.map { ChildThreadData(from: $0) }
    }
    
    private var totalPages: Int {
        OrbitalLayoutCalculator.calculateTotalPages(for: children.count)
    }
    
    private var needsPagination: Bool {
        OrbitalLayoutCalculator.needsPagination(for: children.count)
    }
    
    private var currentPageChildren: [ChildThreadData] {
        let startIndex = currentPage * OrbitalLayoutCalculator.maxChildrenPerPage
        let endIndex = min(startIndex + OrbitalLayoutCalculator.maxChildrenPerPage, childrenData.count)
        
        guard startIndex < childrenData.count else { return [] }
        return Array(childrenData[startIndex..<endIndex])
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            // NO BLOCKING BACKGROUND - Use transparent overlays only
            Color.clear
                .overlay(
                    // Layer 1: Orbital rings (visual only)
                    orbitalRingsView(geometry: geometry)
                        .allowsHitTesting(false) // Pass touches through
                )
                .overlay(
                    // Layer 2: Central parent video (TAPPABLE)
                    centralThreadView(geometry: geometry)
                )
                .overlay(
                    // Layer 3: Child orbs (ONLY interactive elements)
                    orbitalInterfaceView(geometry: geometry)
                )
                .overlay(
                    // Layer 4: Page navigation (only buttons interactive)
                    Group {
                        if needsPagination {
                            pageNavigationView
                        }
                    }
                )
        }
        .onAppear {
            setupOrbitalInterface()
        }
        .onChange(of: currentPage) { _ in
            updateOrbitalPositions()
        }
        .onChange(of: children) { _ in
            updateOrbitalPositions()
        }
    }
    
    // MARK: - Orbital Interface View (ONLY child orbs are tappable)
    
    private func orbitalInterfaceView(geometry: GeometryProxy) -> some View {
        // NO ZStack wrapper - just the child orbs
        ForEach(orbitalPositions, id: \.childID) { position in
            OrbitalChildView(
                childData: getChildData(for: position.childID),
                position: position,
                isSelected: selectedChildID == position.childID,
                onTap: { childData in
                    handleChildSelection(childData)
                }
            )
            .position(position.position)
            .scaleEffect(animationProgress)
            .opacity(animationProgress)
            .animation(
                .easeInOut(duration: 0.6)
                .delay(Double.random(in: 0...0.3)),
                value: animationProgress
            )
        }
    }
    
    // MARK: - Central Thread View (Large tappable parent video card)
    
    private func centralThreadView(geometry: GeometryProxy) -> some View {
        let centerPosition = OrbitalLayoutCalculator.getCenterPosition(containerSize: geometry.size)
        
        return Button(action: {
            print("🎬 ORBITAL: Parent video tapped")
            onParentTapped?()
        }) {
            VStack(spacing: 12) {
                // Large parent video card with actual thumbnail
                ZStack {
                    // Thumbnail background
                    AsyncThumbnailView(
                        url: parentThread.thumbnailURL,
                        aspectRatio: 3.0/4.0,
                        contentMode: .fill
                    )
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Dark overlay for better text contrast
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 120, height: 160)
                    
                    // Play button and info overlay
                    VStack(spacing: 12) {
                        Spacer()
                        
                        // Play button
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        
                        // Reply count badge
                        Text("\(children.count) replies")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                            )
                            .padding(.bottom, 8)
                    }
                    .frame(width: 120, height: 160)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: .purple.opacity(0.4), radius: 15, x: 0, y: 8)
                
                // Creator info
                VStack(spacing: 4) {
                    Text(parentThread.creatorName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Original Thread")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.8))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .position(centerPosition)
        .scaleEffect(1.0 + sin(Date().timeIntervalSince1970 * 0.5) * 0.03)
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: UUID())
    }
    
    // MARK: - Orbital Rings View (Visual guides only)
    
    private func orbitalRingsView(geometry: GeometryProxy) -> some View {
        let centerPosition = OrbitalLayoutCalculator.getCenterPosition(containerSize: geometry.size)
        
        return ZStack {
            // Inner ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .frame(width: 200, height: 200)
                .position(centerPosition)
            
            // Middle ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 300, height: 300)
                .position(centerPosition)
            
            // Outer ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: 400, height: 400)
                .position(centerPosition)
        }
    }
    
    // MARK: - Page Navigation View (Buttons only)
    
    private var pageNavigationView: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                // Previous page button
                Button(action: previousPage) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                        
                        Text("Previous")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(currentPage > 0 ? .white : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(currentPage > 0 ? 0.2 : 0.1))
                    )
                }
                .disabled(currentPage <= 0)
                
                // Page indicator (not tappable)
                Text("\(currentPage + 1) of \(totalPages)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.purple.opacity(0.3))
                    )
                    .allowsHitTesting(false) // Not tappable
                
                // Next page button
                Button(action: nextPage) {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.system(size: 14, weight: .bold))
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(currentPage < totalPages - 1 ? .white : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(currentPage < totalPages - 1 ? 0.2 : 0.1))
                    )
                }
                .disabled(currentPage >= totalPages - 1)
            }
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupOrbitalInterface() {
        updateOrbitalPositions()
        
        // Animate in the interface
        withAnimation(.easeInOut(duration: 0.8)) {
            animationProgress = 1.0
        }
    }
    
    private func updateOrbitalPositions() {
        // Use the calculator to get new positions
        let containerSize = UIScreen.main.bounds.size
        let newPositions = OrbitalLayoutCalculator.calculateOrbitalPositions(
            for: childrenData,
            containerSize: containerSize,
            currentPage: currentPage
        )
        
        // Animate position changes
        withAnimation(.easeInOut(duration: 0.5)) {
            orbitalPositions = newPositions
        }
    }
    
    private func getChildData(for childID: String) -> ChildThreadData? {
        return currentPageChildren.first { $0.id == childID }
    }
    
    private func handleChildSelection(_ childData: ChildThreadData) {
        selectedChildID = childData.id
        
        // Find the corresponding CoreVideoMetadata
        if let selectedVideo = children.first(where: { $0.id == childData.id }) {
            onChildSelected?(selectedVideo)
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("🔵 ORBITAL: Child selected - \(childData.creatorName)")
    }
    
    private func previousPage() {
        guard currentPage > 0 else { return }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            currentPage -= 1
            animationProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                animationProgress = 1.0
            }
        }
        
        print("◀️ ORBITAL: Previous page - \(currentPage + 1)")
    }
    
    private func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            currentPage += 1
            animationProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                animationProgress = 1.0
            }
        }
        
        print("▶️ ORBITAL: Next page - \(currentPage + 1)")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SpatialThreadMapView(
            parentThread: CoreVideoMetadata.sampleThread,
            children: CoreVideoMetadata.sampleChildren,
            onChildSelected: { child in
                print("Selected child: \(child.creatorName)")
            },
            onEngagement: { video, type in
                print("Engagement: \(type) on \(video.creatorName)")
            },
            onParentTapped: {
                print("Parent video tapped!")
            }
        )
    }
}

// MARK: - Sample Data Extension

extension CoreVideoMetadata {
    static let sampleThread = CoreVideoMetadata(
        id: "thread-1",
        title: "Original Thread",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-1",
        creatorName: "ThreadCreator",
        createdAt: Date(),
        threadID: "thread-1",
        replyToVideoID: nil,
        conversationDepth: 0,
        viewCount: 1000,
        hypeCount: 150,
        coolCount: 25,
        replyCount: 42,
        shareCount: 10,
        temperature: "Hot",
        qualityScore: 85,
        engagementRatio: 0.85,
        velocityScore: 50.0,
        trendingScore: 0.8,
        duration: 30.0,
        aspectRatio: 16.0/9.0,
        fileSize: 5000000,
        discoverabilityScore: 0.9,
        isPromoted: false,
        lastEngagementAt: Date()
    )
    
    static let sampleChildren: [CoreVideoMetadata] = (1...42).map { index in
        CoreVideoMetadata(
            id: "child-\(index)",
            title: "Response \(index)",
            videoURL: "",
            thumbnailURL: "",
            creatorID: "user-\(index)",
            creatorName: "User\(index)",
            createdAt: Date(),
            threadID: "thread-1",
            replyToVideoID: nil,
            conversationDepth: 1,
            viewCount: Int.random(in: 10...500),
            hypeCount: Int.random(in: 1...50),
            coolCount: Int.random(in: 0...10),
            replyCount: Int.random(in: 0...10),
            shareCount: Int.random(in: 0...5),
            temperature: ["Cool", "Warm", "Hot"].randomElement() ?? "Cool",
            qualityScore: Int.random(in: 40...90),
            engagementRatio: Double.random(in: 0.3...0.9),
            velocityScore: Double.random(in: 0.1...10.0),
            trendingScore: Double.random(in: 0.1...0.8),
            duration: 15.0,
            aspectRatio: 16.0/9.0,
            fileSize: Int64.random(in: 1000000...3000000),
            discoverabilityScore: Double.random(in: 0.3...0.8),
            isPromoted: false,
            lastEngagementAt: Date()
        )
    }
}
