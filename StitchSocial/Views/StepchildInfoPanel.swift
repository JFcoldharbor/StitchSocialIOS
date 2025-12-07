//
//  StepchildInfoPanel.swift
//  StitchSocial
//
//  Layer 8: Views - Side Panel for Selected Child Details
//  Dependencies: CoreVideoMetadata, EngagementService
//  Features: Stepchild count, engagement stats, interaction limits visualization
//  ARCHITECTURE COMPLIANT: Pure UI component with engagement integration
//

import SwiftUI

/// Side panel showing detailed information about a selected child response
struct StepchildInfoPanel: View {
    
    // MARK: - Properties
    
    let selectedChild: CoreVideoMetadata?
    let stepchildren: [CoreVideoMetadata]
    let isVisible: Bool
    let onStepchildSelected: ((CoreVideoMetadata) -> Void)?
    let onClose: (() -> Void)?
    let onEngagement: ((CoreVideoMetadata, InteractionType) -> Void)?
    
    // MARK: - State
    
    @State private var selectedStepchildID: String?
    @State private var showingStepchildLimit = false
    @State private var animationOffset: CGFloat = 300
    
    // MARK: - Constants
    
    private let childInteractionLimit = 20
    private let stepchildInteractionLimit = 10
    private let panelWidth: CGFloat = 280
    
    // MARK: - Computed Properties
    
    private var childInteractionCount: Int {
        guard let child = selectedChild else { return 0 }
        return child.hypeCount + child.coolCount
    }
    
    private var childInteractionProgress: Double {
        return Double(childInteractionCount) / Double(childInteractionLimit)
    }
    
    private var isChildAtLimit: Bool {
        return childInteractionCount >= childInteractionLimit
    }
    
    private var stepchildrenWithLimits: [(CoreVideoMetadata, Int, Bool)] {
        return stepchildren.map { stepchild in
            let interactionCount = stepchild.hypeCount + stepchild.coolCount
            let isAtLimit = interactionCount >= stepchildInteractionLimit
            return (stepchild, interactionCount, isAtLimit)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack {
            Spacer()
            
            if isVisible && selectedChild != nil {
                panelContent
                    .frame(width: panelWidth)
                    .background(panelBackground)
                    .offset(x: animationOffset)
                    .animation(.easeInOut(duration: 0.3), value: animationOffset)
                    .onAppear {
                        animationOffset = 0
                    }
                    .onDisappear {
                        animationOffset = 300
                    }
            }
        }
        .onChange(of: isVisible) { _, visible in
            animationOffset = visible ? 0 : 300
        }
    }
    
    // MARK: - Panel Background
    
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 15, x: -5, y: 0)
    }
    
    // MARK: - Panel Content
    
    private var panelContent: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader
            
            // Child Info Section
            childInfoSection
            
            // Interaction Limits Section
            interactionLimitsSection
            
            // Stepchildren List
            if !stepchildren.isEmpty {
                stepchildrenSection
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Panel Header
    
    private var panelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Response Details")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                if let child = selectedChild {
                    Text("by \(child.creatorName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
            
            Spacer()
            
            Button(action: { onClose?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Child Info Section
    
    private var childInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Response")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            if let child = selectedChild {
                VStack(spacing: 8) {
                    // Engagement stats
                    HStack(spacing: 16) {
                        statCard(
                            icon: "flame.fill",
                            value: "\(child.hypeCount)",
                            label: "Hypes",
                            color: .red
                        )
                        
                        statCard(
                            icon: "snowflake",
                            value: "\(child.coolCount)",
                            label: "Cools",
                            color: .blue
                        )
                        
                        statCard(
                            icon: "eye.fill",
                            value: "\(child.viewCount)",
                            label: "Views",
                            color: .gray
                        )
                    }
                    
                    // Total interactions
                    HStack {
                        Text("Total Interactions:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text("\(childInteractionCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isChildAtLimit ? .red : .white)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Stat Card Helper
    
    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - Interaction Limits Section
    
    private var interactionLimitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interaction Limits")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingStepchildLimit.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.cyan)
                }
            }
            
            // Child limit progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Response Limit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("\(childInteractionCount)/\(childInteractionLimit)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isChildAtLimit ? .red : .cyan)
                }
                
                ProgressView(value: childInteractionProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: isChildAtLimit ? .red : .cyan))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
            
            // Stepchild limit info
            HStack {
                Text("Stepchild Limit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text("\(stepchildren.count) responses")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Stepchildren Section
    
    private var stepchildrenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Responses (\(stepchildren.count))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if stepchildren.count >= stepchildInteractionLimit {
                    Text("LIMIT REACHED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red)
                        )
                }
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(stepchildrenWithLimits, id: \.0.id) { stepchild, interactionCount, isAtLimit in
                        stepchildRow(stepchild: stepchild, interactionCount: interactionCount, isAtLimit: isAtLimit)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Stepchild Row
    
    private func stepchildRow(stepchild: CoreVideoMetadata, interactionCount: Int, isAtLimit: Bool) -> some View {
        Button(action: {
            onStepchildSelected?(stepchild)
        }) {
            HStack(spacing: 12) {
                // Creator circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.3), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(stepchild.creatorName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(stepchild.creatorName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(stepchild.title)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Stats
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(interactionCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isAtLimit ? .red : .cyan)
                    
                    Text("interactions")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Status indicator
                Circle()
                    .fill(isAtLimit ? .red : .green)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedStepchildID == stepchild.id ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        StepchildInfoPanel(
            selectedChild: sampleChild,
            stepchildren: sampleStepchildren,
            isVisible: true,
            onStepchildSelected: { stepchild in
                print("Selected stepchild: \(stepchild.creatorName)")
            },
            onClose: {
                print("Panel closed")
            },
            onEngagement: { video, type in
                print("Engagement: \(type) on \(video.creatorName)")
            }
        )
    }
}

// MARK: - Sample Data

private let sampleChild = CoreVideoMetadata(
    id: "child-1",
    title: "Sample Child Response",
    videoURL: "",
    thumbnailURL: "",
    creatorID: "user-1",
    creatorName: "Alice",
    createdAt: Date(),
    threadID: "thread-1",
    replyToVideoID: nil,
    conversationDepth: 1,
    viewCount: 250,
    hypeCount: 15,
    coolCount: 3,
    replyCount: 5,
    shareCount: 2,
    temperature: "warm",
    qualityScore: 75,
    engagementRatio: 0.8,
    velocityScore: 5.0,
    trendingScore: 0.6,
    duration: 18.0,
    aspectRatio: 9.0/16.0,
    fileSize: 2048000,
    discoverabilityScore: 0.7,
    isPromoted: false,
    lastEngagementAt: Date()
)

private let sampleStepchildren = [
    CoreVideoMetadata(
        id: "stepchild-1",
        title: "First stepchild response",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-2",
        creatorName: "Bob",
        createdAt: Date(),
        threadID: "thread-1",
        replyToVideoID: "child-1",
        conversationDepth: 2,
        viewCount: 100,
        hypeCount: 8,
        coolCount: 1,
        replyCount: 0,
        shareCount: 0,
        temperature: "cool",
        qualityScore: 65,
        engagementRatio: 0.89,
        velocityScore: 3.0,
        trendingScore: 0.4,
        duration: 12.0,
        aspectRatio: 9.0/16.0,
        fileSize: 1024000,
        discoverabilityScore: 0.5,
        isPromoted: false,
        lastEngagementAt: Date()
    ),
    CoreVideoMetadata(
        id: "stepchild-2",
        title: "Second stepchild response",
        videoURL: "",
        thumbnailURL: "",
        creatorID: "user-3",
        creatorName: "Charlie",
        createdAt: Date(),
        threadID: "thread-1",
        replyToVideoID: "child-1",
        conversationDepth: 2,
        viewCount: 75,
        hypeCount: 12,
        coolCount: 2,
        replyCount: 0,
        shareCount: 1,
        temperature: "warm",
        qualityScore: 70,
        engagementRatio: 0.86,
        velocityScore: 4.5,
        trendingScore: 0.5,
        duration: 15.0,
        aspectRatio: 9.0/16.0,
        fileSize: 1536000,
        discoverabilityScore: 0.6,
        isPromoted: false,
        lastEngagementAt: Date()
    )
]
