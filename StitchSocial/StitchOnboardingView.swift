//
//  StitchOnboardingView.swift
//  CleanBeta
//
//  Welcome onboarding experience for new Stitch users
//  Explains app purpose, gestures, and content types
//

import SwiftUI

struct StitchOnboardingView: View {
    @State private var currentStep = 0
    @State private var selectedContentTypes: Set<OnboardingContentType> = []
    @State private var showGestureDemo = false
    @State private var animationOffset: CGFloat = 0
    @State private var pulseAnimation = false
    
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    private let totalSteps = 5
    
    var body: some View {
        ZStack {
            // Background with animated gradient
            LinearGradient(
                colors: [
                    Color.black,
                    Color.purple.opacity(0.3),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                // Animated particles
                ForEach(0..<15, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 2...6))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                        .animation(
                            Animation.linear(duration: Double.random(in: 8...12))
                                .repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }
            )
            
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Main content
                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    purposeStep.tag(1)
                    gesturesStep.tag(2)
                    contentSelectionStep.tag(3)
                    tierSystemStep.tag(4)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
                
                // Navigation buttons
                navigationButtons
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 4)
                    .fill(step <= currentStep ? Color.white : Color.white.opacity(0.3))
                    .frame(height: 4)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentStep)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Step 1: Welcome
    
    private var welcomeStep: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App logo/icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                
                Image(systemName: "video.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 16) {
                Text("Welcome to")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Stitch")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .overlay(
                        LinearGradient(
                            colors: [Color.purple, Color.pink, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(
                            Text("Stitch")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                        )
                    )
                
                Text("Where every video starts a conversation")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Step 2: App Purpose
    
    private var purposeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Text("How Stitch Works")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 24) {
                purposeCard(
                    icon: "video.circle.fill",
                    title: "Create a Thread",
                    description: "Start with your video - ask questions, share thoughts, or showcase skills",
                    color: .purple
                )
                
                purposeCard(
                    icon: "arrow.branch",
                    title: "Others Reply",
                    description: "People respond with their own videos, creating rich conversations",
                    color: .blue
                )
                
                purposeCard(
                    icon: "flame.fill",
                    title: "Build Community",
                    description: "Gain Hype, earn badges, and climb tiers as you contribute amazing content",
                    color: .orange
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private func purposeCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Step 3: Gestures
    
    private var gesturesStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Text("Master the Gestures")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Navigate conversations like a pro")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 16) {
                gestureCard(
                    gesture: "Swipe Up",
                    action: "Next video in thread",
                    icon: "arrow.up",
                    color: .green
                )
                
                gestureCard(
                    gesture: "Swipe Down",
                    action: "Previous video",
                    icon: "arrow.down",
                    color: .blue
                )
                
                gestureCard(
                    gesture: "Swipe Left/Right",
                    action: "Switch between threads",
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
                
                gestureCard(
                    gesture: "Double Tap",
                    action: "Hype (like) the video",
                    icon: "flame.fill",
                    color: .orange
                )
                
                gestureCard(
                    gesture: "Long Press",
                    action: "Cool (dislike) or options",
                    icon: "snowflake",
                    color: .cyan
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private func gestureCard(gesture: String, action: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(action)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Step 4: Content Selection
    
    private var contentSelectionStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Text("What interests you?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Select topics you'd like to see and create")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(OnboardingContentType.allCases, id: \.self) { contentType in
                    contentTypeCard(contentType)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    private func contentTypeCard(_ contentType: OnboardingContentType) -> some View {
        let isSelected = selectedContentTypes.contains(contentType)
        
        return VStack(spacing: 12) {
            Image(systemName: contentType.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(isSelected ? .white : contentType.color)
            
            Text(contentType.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(contentType.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? contentType.color.opacity(0.3) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ? contentType.color : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            withAnimation {
                if isSelected {
                    selectedContentTypes.remove(contentType)
                } else {
                    selectedContentTypes.insert(contentType)
                }
            }
        }
    }
    
    // MARK: - Step 5: Tier System
    
    private var tierSystemStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Text("Climb the Ranks")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Earn Clout through great content and engagement")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                ForEach(UserTierInfo.allTiers, id: \.tier) { tierInfo in
                    tierCard(tierInfo)
                }
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Earn Clout by creating engaging content")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.orange)
                    Text("Unlock exclusive badges and privileges")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func tierCard(_ tierInfo: UserTierInfo) -> some View {
        HStack(spacing: 16) {
            // Tier icon
            ZStack {
                Circle()
                    .fill(tierInfo.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Text(tierInfo.emoji)
                    .font(.title2)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tierInfo.tier.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("\(tierInfo.range) Clout")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if tierInfo.tier == .rookie {
                Text("You are here!")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.2))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tierInfo.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            // Skip button
            if currentStep < totalSteps - 1 {
                Button("Skip") {
                    onSkip()
                }
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Next/Complete button
            Button(action: {
                if currentStep < totalSteps - 1 {
                    withAnimation {
                        currentStep += 1
                    }
                } else {
                    onComplete()
                }
            }) {
                HStack(spacing: 8) {
                    Text(currentStep < totalSteps - 1 ? "Next" : "Start Creating!")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if currentStep < totalSteps - 1 {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                    } else {
                        Image(systemName: "video.fill")
                            .font(.headline)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

// MARK: - Supporting Types

enum OnboardingContentType: String, CaseIterable {
    case trending = "trending"
    case educational = "educational"
    case entertainment = "entertainment"
    case creative = "creative"
    case lifestyle = "lifestyle"
    case debate = "debate"
    
    var title: String {
        switch self {
        case .trending: return "Trending"
        case .educational: return "Learning"
        case .entertainment: return "Comedy"
        case .creative: return "Creative"
        case .lifestyle: return "Lifestyle"
        case .debate: return "Hot Takes"
        }
    }
    
    var description: String {
        switch self {
        case .trending: return "Hot topics"
        case .educational: return "Teach & learn"
        case .entertainment: return "Fun content"
        case .creative: return "Art & music"
        case .lifestyle: return "Daily life"
        case .debate: return "Discussions"
        }
    }
    
    var icon: String {
        switch self {
        case .trending: return "flame.fill"
        case .educational: return "book.fill"
        case .entertainment: return "theatermasks.fill"
        case .creative: return "paintbrush.fill"
        case .lifestyle: return "house.fill"
        case .debate: return "bubble.left.and.bubble.right.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .trending: return .orange
        case .educational: return .blue
        case .entertainment: return .yellow
        case .creative: return .purple
        case .lifestyle: return .green
        case .debate: return .red
        }
    }
}

struct UserTierInfo {
    let tier: UserTier
    let range: String
    let color: Color
    let emoji: String
    
    static let allTiers = [
        UserTierInfo(tier: .rookie, range: "0-999", color: .gray, emoji: "🆕"),
        UserTierInfo(tier: .rising, range: "1K-5K", color: .blue, emoji: "⬆️"),
        UserTierInfo(tier: .influencer, range: "5K-20K", color: .purple, emoji: "⭐"),
        UserTierInfo(tier: .partner, range: "20K-100K", color: .orange, emoji: "👑"),
        UserTierInfo(tier: .topCreator, range: "100K+", color: .red, emoji: "🔥")
    ]
}

// MARK: - Preview

struct StitchOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        StitchOnboardingView(
            onComplete: { print("Onboarding completed") },
            onSkip: { print("Onboarding skipped") }
        )
        .preferredColorScheme(.dark)
    }
}
