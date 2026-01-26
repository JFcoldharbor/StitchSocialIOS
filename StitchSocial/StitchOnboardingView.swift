//
//  StitchOnboardingView.swift
//  CleanBeta
//
//  Interactive step-by-step navigation tutorial for new Stitch users
//  Guides users through Discovery → Swiping → Fullscreen → Thread View → Stitching → Search
//

import SwiftUI

struct StitchOnboardingView: View {
    @State private var currentStep = 0
    @State private var pulseAnimation = false
    @State private var showSwipeHint = false
    @State private var showTapHint = false
    @State private var mockSwipeOffset: CGFloat = 0
    @State private var hasCompletedInteraction = false
    
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    private let totalSteps = 7
    
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            VStack(spacing: 0) {
                // Top bar with progress
                topBar
                
                // Main content
                TabView(selection: $currentStep) {
                    welcomeStep.tag(0)
                    discoveryStep.tag(1)
                    swipingStep.tag(2)
                    fullscreenStep.tag(3)
                    threadViewStep.tag(4)
                    stitchStep.tag(5)
                    searchStep.tag(6)
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
        .onChange(of: currentStep) { _ in
            // Reset interaction state when changing steps
            hasCompletedInteraction = false
            showSwipeHint = false
            showTapHint = false
            mockSwipeOffset = 0
            
            // Start hint animations after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    showSwipeHint = true
                    showTapHint = true
                }
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color.purple.opacity(0.2),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            // Subtle animated particles
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: CGFloat.random(in: 3...8))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
            }
        )
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        VStack(spacing: 16) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? Color.white : (step < currentStep ? Color.purple : Color.white.opacity(0.3)))
                        .frame(width: step == currentStep ? 10 : 6, height: step == currentStep ? 10 : 6)
                        .animation(.spring(response: 0.4), value: currentStep)
                }
            }
            
            // Step counter
            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Step 0: Welcome
    
    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseAnimation ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Welcome to Stitch")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Let's show you around")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Quick overview cards
            VStack(spacing: 12) {
                quickInfoCard(icon: "play.rectangle.fill", text: "Watch video conversations", color: .blue)
                quickInfoCard(icon: "arrow.triangle.branch", text: "Reply with your own videos", color: .purple)
                quickInfoCard(icon: "person.2.fill", text: "Connect with creators", color: .pink)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Text("We'll guide you through each feature")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 20)
        }
    }
    
    private func quickInfoCard(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Step 1: Discovery
    
    private var discoveryStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text("Discovery")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Find amazing content even with no followers")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            // Mock phone showing tabs
            mockPhoneFrame {
                VStack(spacing: 0) {
                    // Mock video area
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("Video Content")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        )
                    
                    Spacer().frame(height: 8)
                    
                    // Mock bottom tabs with highlight on Discover
                    HStack(spacing: 0) {
                        mockTab(icon: "house.fill", label: "Home", isHighlighted: false)
                        mockTab(icon: "sparkles", label: "Discover", isHighlighted: true)
                        mockTab(icon: "plus.circle.fill", label: "", isHighlighted: false, isCenter: true)
                        mockTab(icon: "bell.fill", label: "Alerts", isHighlighted: false)
                        mockTab(icon: "person.fill", label: "Profile", isHighlighted: false)
                    }
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                }
            }
            
            // Explanation cards
            VStack(spacing: 12) {
                explanationCard(
                    icon: "flame.fill",
                    title: "Trending",
                    description: "Popular videos getting lots of engagement",
                    color: .orange
                )
                
                explanationCard(
                    icon: "number",
                    title: "Hashtags",
                    description: "Browse topics that interest you",
                    color: .blue
                )
                
                explanationCard(
                    icon: "sparkle.magnifyingglass",
                    title: "For You",
                    description: "Personalized recommendations",
                    color: .purple
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Step 2: Swiping
    
    private var swipingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .foregroundColor(.green)
                    Text("Navigate Videos")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Swipe to browse content")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Interactive mock phone
            mockPhoneFrame {
                ZStack {
                    // Mock video cards
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.3))
                        .overlay(
                            VStack {
                                Text("Video 1")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        )
                        .offset(y: mockSwipeOffset)
                    
                    // Swipe hint arrows
                    VStack {
                        // Up arrow
                        Image(systemName: "chevron.up")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(showSwipeHint ? 1 : 0.3)
                            .offset(y: showSwipeHint ? -5 : 0)
                        
                        Spacer()
                        
                        // Down arrow
                        Image(systemName: "chevron.down")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(showSwipeHint ? 1 : 0.3)
                            .offset(y: showSwipeHint ? 5 : 0)
                    }
                    .padding(.vertical, 20)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        mockSwipeOffset = value.translation.height * 0.3
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            mockSwipeOffset = 0
                            hasCompletedInteraction = true
                        }
                    }
            )
            
            // Gesture cards
            VStack(spacing: 10) {
                gestureRow(icon: "arrow.up", gesture: "Swipe Up", action: "Next video", color: .green)
                gestureRow(icon: "arrow.down", gesture: "Swipe Down", action: "Previous video", color: .blue)
                gestureRow(icon: "arrow.left.arrow.right", gesture: "Swipe Left/Right", action: "Switch threads", color: .purple)
            }
            .padding(.horizontal, 24)
            
            if hasCompletedInteraction {
                Text("Nice! You've got it! ✓")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("Try swiping on the phone above!")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Step 3: Fullscreen
    
    private var fullscreenStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.cyan)
                    Text("Fullscreen Mode")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Tap any video to expand it")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Mock phone showing grid → fullscreen
            HStack(spacing: 20) {
                // Grid view
                VStack(spacing: 4) {
                    mockMiniPhone {
                        VStack(spacing: 2) {
                            HStack(spacing: 2) {
                                mockMiniVideo()
                                mockMiniVideo()
                            }
                            HStack(spacing: 2) {
                                mockMiniVideo(highlighted: true)
                                mockMiniVideo()
                            }
                        }
                        .padding(4)
                    }
                    Text("Grid View")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Arrow
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.cyan)
                    .overlay(
                        Circle()
                            .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                            .scaleEffect(showTapHint ? 1.5 : 1)
                            .opacity(showTapHint ? 0 : 1)
                    )
                
                // Fullscreen view
                VStack(spacing: 4) {
                    mockMiniPhone {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple.opacity(0.4))
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16))
                                    Text("Full Video")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.white.opacity(0.7))
                            )
                    }
                    Text("Fullscreen")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Info cards
            VStack(spacing: 10) {
                infoRow(icon: "hand.tap", text: "Tap video thumbnail to go fullscreen")
                infoRow(icon: "xmark.circle", text: "Tap X or swipe down to exit")
                infoRow(icon: "speaker.wave.2", text: "Audio plays automatically in fullscreen")
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Step 4: Thread View
    
    private var threadViewStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(.purple)
                    Text("Thread View")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("See the full video conversation")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Mock thread visualization
            mockPhoneFrame {
                VStack(spacing: 8) {
                    // Original video
                    threadVideoMock(label: "Original", isOriginal: true)
                    
                    // Thread line
                    Rectangle()
                        .fill(Color.purple.opacity(0.5))
                        .frame(width: 2, height: 15)
                    
                    // Replies
                    HStack(alignment: .top, spacing: 8) {
                        threadVideoMock(label: "Reply 1", isOriginal: false)
                        threadVideoMock(label: "Reply 2", isOriginal: false)
                    }
                    
                    // More indicator
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                        Text("3 more replies")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                .padding(8)
            }
            
            // Thread explanation
            VStack(spacing: 10) {
                threadFeatureRow(icon: "arrow.branch", text: "Videos branch into conversations")
                threadFeatureRow(icon: "figure.walk", text: "Navigate up/down through replies")
                threadFeatureRow(icon: "infinity", text: "Conversations can go 20 levels deep!")
            }
            .padding(.horizontal, 24)
            
            // How to access
            VStack(spacing: 8) {
                Text("How to access Thread View")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 16) {
                    accessMethodBadge(icon: "bubble.right", label: "Tap replies")
                    accessMethodBadge(icon: "arrow.up.square", label: "Swipe up")
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Step 5: Stitch (Reply)
    
    private var stitchStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "video.badge.plus")
                        .foregroundColor(.pink)
                    Text("Create a Stitch")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Reply to videos with your own")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Mock showing stitch flow
            mockPhoneFrame {
                VStack(spacing: 12) {
                    // Video being watched
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 80)
                        .overlay(
                            Text("Someone's Video")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        )
                    
                    // Stitch button highlighted
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(Color.pink.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                    .scaleEffect(showTapHint ? 1.2 : 1)
                                    .opacity(showTapHint ? 0.5 : 1)
                                
                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(.pink)
                            }
                            
                            Text("Stitch")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 8)
                    
                    // Arrow down
                    Image(systemName: "arrow.down")
                        .foregroundColor(.pink.opacity(0.7))
                    
                    // Recording preview
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.pink.opacity(0.2))
                        .frame(height: 50)
                        .overlay(
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                Text("Record your reply")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        )
                }
                .padding(8)
            }
            
            // Steps
            VStack(alignment: .leading, spacing: 12) {
                stitchStepRow(number: 1, text: "Find a video you want to reply to")
                stitchStepRow(number: 2, text: "Tap the Stitch button on the right")
                stitchStepRow(number: 3, text: "Record your video response")
                stitchStepRow(number: 4, text: "Add captions & post!")
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Step 6: Search
    
    private var searchStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                    Text("Find People")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Search for creators to follow")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Mock search interface
            mockPhoneFrame {
                VStack(spacing: 8) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        Text("Search users, hashtags...")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                    
                    // Mock search results
                    VStack(spacing: 6) {
                        searchResultMock(name: "CoolCreator", followers: "12.5K")
                        searchResultMock(name: "FunnyPerson", followers: "8.2K")
                        searchResultMock(name: "TechGuru", followers: "45K")
                    }
                }
                .padding(10)
            }
            
            // Search tips
            VStack(spacing: 10) {
                searchTipRow(icon: "person.fill", text: "Search by username")
                searchTipRow(icon: "number", text: "Find hashtags to explore")
                searchTipRow(icon: "star.fill", text: "Discover suggested creators")
            }
            .padding(.horizontal, 24)
            
            // Where to find search
            VStack(spacing: 8) {
                Text("Access search from")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 16) {
                    accessMethodBadge(icon: "sparkles", label: "Discover tab")
                    accessMethodBadge(icon: "magnifyingglass", label: "Search icon")
                }
            }
            
            Spacer()
            
            // Ready message
            VStack(spacing: 8) {
                Text("🎉 You're all set!")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Start exploring and creating")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 10)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            // Skip/Back button
            if currentStep == 0 {
                Button("Skip Tutorial") {
                    onSkip()
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            } else {
                Button(action: {
                    withAnimation {
                        currentStep -= 1
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                }
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
                HStack(spacing: 6) {
                    Text(currentStep < totalSteps - 1 ? "Next" : "Let's Go!")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Image(systemName: currentStep < totalSteps - 1 ? "chevron.right" : "arrow.right")
                        .font(.subheadline)
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
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    // MARK: - Reusable Components
    
    private func mockPhoneFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            // Notch
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
                .frame(width: 80, height: 20)
            
            // Screen content
            content()
                .frame(width: 180, height: 280)
                .background(Color.black.opacity(0.6))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                )
        )
    }
    
    private func mockMiniPhone<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 70, height: 120)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private func mockMiniVideo(highlighted: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(highlighted ? Color.cyan.opacity(0.4) : Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(highlighted ? Color.cyan : Color.clear, lineWidth: 2)
            )
    }
    
    private func mockTab(icon: String, label: String, isHighlighted: Bool, isCenter: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: isCenter ? 24 : 16))
                .foregroundColor(isHighlighted ? .yellow : (isCenter ? .white : .white.opacity(0.5)))
            
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(isHighlighted ? .yellow : .white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            isHighlighted ?
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.2))
                .padding(.horizontal, 4)
            : nil
        )
    }
    
    private func explanationCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func gestureRow(icon: String, gesture: String, action: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(gesture)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)
            
            Text("→")
                .foregroundColor(.white.opacity(0.3))
            
            Text(action)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.cyan)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
    
    private func threadVideoMock(label: String, isOriginal: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isOriginal ? Color.purple.opacity(0.4) : Color.blue.opacity(0.3))
            .frame(width: isOriginal ? 80 : 60, height: isOriginal ? 60 : 45)
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text(label)
                        .font(.system(size: 7))
                }
                .foregroundColor(.white.opacity(0.6))
            )
    }
    
    private func threadFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.purple)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private func accessMethodBadge(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.caption)
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private func stitchStepRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
    
    private func searchResultMock(name: String, followers: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                )
            
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                Text("\(followers) followers")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text("Follow")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func searchTipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Supporting Types (preserved from original)

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
