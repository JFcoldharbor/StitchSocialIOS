//
//  OnboardingState.swift
//  StitchSocial
//
//  Layer 8: Views - Onboarding State + Spotlight View + Cutout Shape
//  Dependencies: SwiftUI, FirebaseFirestore, FirebaseAuth, OnboardingSeedService
//
//  FLOW:
//    1. swipeHint     — glow on card + hand animation. Advances on first swipe.
//    2. swipeToSeed   — dim/glow OFF. Floating badge counts down to seed video.
//                       Advances when currentSwipeIndex == seedIndex.
//    3. tapHint       — glow back on card + tap pulse. Advances when fullscreen opens.
//    4. threadButton  — inside FullscreenVideoView. Glow on thread button.
//                       Advances when thread button tapped.
//    5. threadExplore — inside ThreadView. Brief overlay "Swipe through the conversation."
//                       Auto-advances after 4 seconds OR first swipe.
//    6. stitchButton  — back in FullscreenVideoView. Glow on stitch button.
//                       Advances when stitch button tapped.
//    7. recordStitch  — camera opens. Onboarding completes when video is posted.
//
//  CACHING:
//  - OnboardingState.shared: UserDefaults key 'stitch_onboarding_complete'. 0 reads.
//  - seedIndex: set once by DiscoveryViewModel after seed injection. Memory only.
//  - currentStep: memory only — restart always begins at swipeHint.
//  Add to CachingOptimization.swift:
//  "OnboardingState.shared — singleton, UserDefaults-backed shouldShow.
//   seedIndex passed in-memory from DiscoveryViewModel. No Firestore reads.
//   Completes with 1 write to users/{uid}.hasCompletedOnboarding."
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - OnboardingState (Singleton)

@MainActor
final class OnboardingState: ObservableObject {

    static let shared = OnboardingState()

    @Published var shouldShow: Bool
    @Published var currentStep: OnboardingStep = .swipeHint

    /// Set by DiscoveryViewModel after seed injection so we know which index to wait for
    var seedIndex: Int = 2

    private let key = "stitch_onboarding_complete"

    private init() {
        shouldShow = !UserDefaults.standard.bool(forKey: "stitch_onboarding_complete")
    }

    // MARK: - Advance

    /// Call from real UI actions. Guards: must be active + on matching step.
    func advance(from step: OnboardingStep) {
        guard shouldShow else { return }
        guard currentStep == step else { return }
        let all = OnboardingStep.allCases
        guard let next = all.first(where: { $0.rawValue == step.rawValue + 1 }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentStep = next
        }
        print("🎓 ONBOARDING: → \(next.rawValue) (\(next.title))")
    }

    /// Called by DiscoveryView's onChange(currentSwipeIndex) to handle the seed-locking logic
    func handleSwipeIndexChanged(to index: Int) {
        guard shouldShow else { return }
        switch currentStep {
        case .swipeHint:
            // First swipe — move to free-swipe phase
            withAnimation(.easeInOut(duration: 0.3)) { currentStep = .swipeToSeed }
            print("🎓 ONBOARDING: → swipeToSeed (free swipe phase)")
        case .swipeToSeed:
            // Check if reached seed video
            if index == seedIndex {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    currentStep = .tapHint
                }
                print("🎓 ONBOARDING: → tapHint (seed video reached at index \(index))")
            }
        default:
            break
        }
    }

    // MARK: - Complete

    func complete(userID: String? = nil) {
        UserDefaults.standard.set(true, forKey: key)
        shouldShow = false
        Task { await OnboardingSeedService.shared.clearCache() }
        guard let uid = userID ?? Auth.auth().currentUser?.uid else { return }
        Task {
            try? await Firestore
                .firestore(database: Config.Firebase.databaseName)
                .collection("users").document(uid)
                .updateData(["hasCompletedOnboarding": true])
        }
        print("✅ ONBOARDING: Complete")
    }

    #if DEBUG
    func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
        Task { await OnboardingSeedService.shared.clearCache() }
        shouldShow = true
        currentStep = .swipeHint
        seedIndex = 2
        print("🔴 ONBOARDING: Reset for testing")
    }
    #endif
}

// MARK: - PreferenceKeys

struct OnboardingTabBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingSwipeCardFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingFullscreenBtnFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingThreadBtnFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingStitchBtnFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingCommunitiesPillFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingSearchIconFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct OnboardingThreadPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case swipeHint     = 0  // Glow + hand animation on card
    case swipeToSeed   = 1  // Free swipe — no dim, floating counter
    case tapHint       = 2  // Glow on seed card, tap pulse
    case threadButton  = 3  // Fullscreen: glow on thread button
    case threadExplore = 4  // ThreadView: brief overlay, auto-advance
    case stitchButton  = 5  // Fullscreen: glow on stitch button
    case recordStitch  = 6  // Camera open — completes on post

    var title: String {
        switch self {
        case .swipeHint:     return "Swipe to explore"
        case .swipeToSeed:   return ""
        case .tapHint:       return "Tap to watch"
        case .threadButton:  return "See the conversation"
        case .threadExplore: return "Swipe through"
        case .stitchButton:  return "Stitch in"
        case .recordStitch:  return "Your turn"
        }
    }

    var instruction: String {
        switch self {
        case .swipeHint:     return "Swipe left to see the next video"
        case .swipeToSeed:   return ""
        case .tapHint:       return "Tap the video to watch fullscreen"
        case .threadButton:  return "Tap the thread button to see everyone who stitched in"
        case .threadExplore: return "These are all the videos in this conversation. Swipe through them."
        case .stitchButton:  return "Tap the Stitch button to reply with your own video"
        case .recordStitch:  return "Record your first Stitch and add your voice to the conversation"
        }
    }

    /// Whether to show dim overlay + spotlight glow
    var showDim: Bool {
        switch self {
        case .swipeToSeed, .recordStitch: return false
        default: return true
        }
    }

    /// Whether to show the swipe hand animation
    var showHandSwipe: Bool { self == .swipeHint }

    /// Whether to show the tap pulse animation
    var showTapPulse: Bool {
        switch self {
        case .tapHint, .threadButton, .stitchButton: return true
        default: return false
        }
    }

    var showSkip: Bool {
        switch self {
        case .recordStitch: return false
        default: return true
        }
    }
}

// MARK: - SpotlightOnboardingView

struct SpotlightOnboardingView: View {

    let swipeCardFrame:        CGRect
    let fullscreenButtonFrame: CGRect
    let threadButtonFrame:     CGRect
    let stitchButtonFrame:     CGRect
    let communitiesPillFrame:  CGRect
    let searchIconFrame:       CGRect

    let onOpenCamera: () -> Void
    let onComplete:   () -> Void

    @ObservedObject private var onboarding = OnboardingState.shared
    @EnvironmentObject private var authService: AuthService

    @State private var handOffsetX:  CGFloat = 60
    @State private var handOpacity:  Double  = 0
    @State private var tapScale:     CGFloat = 1.0
    @State private var cardVisible:  Bool    = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1 — dim + spotlight. Pass-through so real taps reach UI.
                if onboarding.currentStep.showDim {
                    dimAndSpotlight(geometry: geometry)
                        .allowsHitTesting(false)
                }

                // Layer 2 — gesture hints. Pass-through.
                gestureHints(geometry: geometry)
                    .allowsHitTesting(false)

                // Layer 3 — free swipe counter badge. Pass-through.
                if onboarding.currentStep == .swipeToSeed {
                    swipeCounterBadge(geometry: geometry)
                        .allowsHitTesting(false)
                }

                // Layer 4 — instruction card. Pass-through.
                if onboarding.currentStep.showDim {
                    instructionCard(geometry: geometry)
                        .allowsHitTesting(false)
                        .opacity(cardVisible ? 1 : 0)
                        .animation(.easeIn(duration: 0.3), value: cardVisible)
                }

                // Layer 5 — skip button. Needs hit testing.
                skipOverlay

                // Layer 6 — recordStitch final card. Needs hit testing.
                if onboarding.currentStep == .recordStitch {
                    recordStitchCard
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    cardVisible = true
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Dim + Spotlight

    @ViewBuilder
    private func dimAndSpotlight(geometry: GeometryProxy) -> some View {
        let rect = spotlightRect(geometry: geometry)

        if rect == .zero {
            Color.black.opacity(0.60).ignoresSafeArea()
        } else {
            SpotlightCutoutShape(
                spotlightRect: rect.insetBy(dx: -20, dy: -20),
                cornerRadius: 18
            )
            .fill(Color.black.opacity(0.60))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: onboarding.currentStep.rawValue)

            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.cyan.opacity(0.9), lineWidth: 2.5)
                .frame(width: rect.width + 8, height: rect.height + 8)
                .position(x: rect.midX, y: rect.midY)
                .modifier(OnboardingPulseModifier())
                .animation(.easeInOut(duration: 0.35), value: onboarding.currentStep.rawValue)
        }
    }

    // MARK: - Gesture Hints

    @ViewBuilder
    private func gestureHints(geometry: GeometryProxy) -> some View {
        let step = onboarding.currentStep
        let rect = spotlightRect(geometry: geometry)

        if step.showHandSwipe && rect != .zero {
            Image(systemName: "hand.point.left.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.white.opacity(0.9))
                .offset(x: handOffsetX)
                .opacity(handOpacity)
                .position(x: rect.midX, y: rect.midY)
                .onAppear { animateHand(width: rect.width) }
                .onChange(of: step.rawValue) { _, _ in animateHand(width: rect.width) }

        } else if step.showTapPulse && rect != .zero {
            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: 52, height: 52)
                .scaleEffect(tapScale)
                .position(x: rect.midX, y: rect.midY)
                .onAppear { animateTap() }
                .onChange(of: step.rawValue) { _, _ in animateTap() }
        }
    }

    // MARK: - Free Swipe Counter Badge

    @State private var swipeArrowOffset: CGFloat = 0

    private func swipeCounterBadge(geometry: GeometryProxy) -> some View {
        let remaining = max(0, onboarding.seedIndex - 1)
        return VStack {
            Spacer()

            VStack(spacing: 10) {
                // Animated arrow
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.cyan.opacity(Double(i + 1) * 0.35))
                            .offset(x: swipeArrowOffset * CGFloat(i + 1) * 0.4)
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        swipeArrowOffset = -12
                    }
                }

                Text(remaining <= 1 ? "One more swipe" : "\(remaining) more swipes")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Keep swiping to find the conversation")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.80))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 140)
        }
    }

    // MARK: - Instruction Card

    @ViewBuilder
    private func instructionCard(geometry: GeometryProxy) -> some View {
        let step = onboarding.currentStep
        if step == .recordStitch || step == .swipeToSeed {
            EmptyView()
        } else {
        let rect  = spotlightRect(geometry: geometry)
        let cardY = cardYPosition(rect: rect, geometry: geometry)
        let above = isCardAbove(rect: rect, geometry: geometry)

        VStack {
            Spacer().frame(height: max(56, cardY))

            VStack(spacing: 12) {
                if rect != .zero {
                    Image(systemName: above ? "arrowshape.down.fill" : "arrowshape.up.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.cyan)
                }

                stepDots(current: step)

                VStack(spacing: 5) {
                    Text(step.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(step.instruction)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.14), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        } // end else
    }

    // MARK: - Step Dots

    private func stepDots(current: OnboardingStep) -> some View {
        let visibleSteps = OnboardingStep.allCases.filter {
            $0 != .swipeToSeed && $0 != .recordStitch
        }
        return HStack(spacing: 5) {
            ForEach(visibleSteps, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= current.rawValue
                          ? Color.cyan : Color.white.opacity(0.2))
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: current.rawValue)
            }
        }
    }

    // MARK: - Skip Overlay

    private var skipOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if onboarding.currentStep.showSkip {
                    Button("Skip") { onComplete() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 58)
                        .padding(.trailing, 20)
                }
            }
            Spacer()
        }
    }

    // MARK: - Record Stitch Card

    private var recordStitchCard: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "video.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.cyan)
            }

            VStack(spacing: 8) {
                Text("Your turn")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Record your first Stitch and add your\nvoice to this conversation.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                Button {
                    onOpenCamera()
                } label: {
                    Text("Record my Stitch")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(OnboardingScaleStyle())

                Button("Not now") { onComplete() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Spotlight Rect

    private func spotlightRect(geometry: GeometryProxy) -> CGRect {
        let fallback = CGRect(
            x: 60, y: 150,
            width: geometry.size.width - 120,
            height: geometry.size.height - 370
        )
        switch onboarding.currentStep {
        case .swipeHint, .tapHint:
            // Use swipeCardFrame only for x/width — its minY is unreliable.
            // Card top always sits at ~37% down the screen (below status bar,
            // toolbar, category pills, and instruction bar).
            // Card bottom extends to ~92% (above tab bar) to include title + stats.
            let cardX      = swipeCardFrame != .zero ? swipeCardFrame.minX + 60 : 60
            let cardWidth  = swipeCardFrame != .zero ? swipeCardFrame.width - 120 : geometry.size.width - 120
            let cardTop    = geometry.size.height * 0.25
            let cardBottom = geometry.size.height * 0.88
            return CGRect(
                x: cardX,
                y: cardTop,
                width: cardWidth,
                height: cardBottom - cardTop
            )
        // thread/stitch handled inside FullscreenOnboardingOverlay (separate window)
        default: return .zero
        }
    }

    // MARK: - Card Positioning

    private func cardYPosition(rect: CGRect, geometry: GeometryProxy) -> CGFloat {
        guard rect != .zero else { return geometry.size.height * 0.25 }
        let h: CGFloat = 160; let gap: CGFloat = 18
        let below = rect.maxY + gap
        return below + h < geometry.size.height - 80 ? below : max(56, rect.minY - h - gap)
    }

    private func isCardAbove(rect: CGRect, geometry: GeometryProxy) -> Bool {
        let h: CGFloat = 160; let gap: CGFloat = 18
        return !(rect.maxY + gap + h < geometry.size.height - 80)
    }

    // MARK: - Animations

    private func animateHand(width: CGFloat) {
        handOffsetX = width * 0.25
        handOpacity = 0
        withAnimation(.easeIn(duration: 0.25)) { handOpacity = 1.0 }
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: false).delay(0.25)) {
            handOffsetX = -width * 0.25
        }
    }

    private func animateTap() {
        tapScale = 1.0
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            tapScale = 1.45
        }
    }
}

// MARK: - ThreadView Onboarding Overlay

/// 4-step mini-tutorial shown inside ThreadView during threadExplore.
/// Each sub-step has its own spotlight and auto-advances.
/// Dismisses ThreadView when complete so user returns to fullscreen for stitch step.
struct ThreadViewOnboardingOverlay: View {

    /// Panel frame passed from ThreadView via PreferenceKey
    let panelFrame: CGRect

    @ObservedObject private var onboarding = OnboardingState.shared
    @Environment(\.dismiss) private var dismiss

    // Local sub-steps within threadExplore
    enum SubStep: Int, CaseIterable {
        case originalVideo  = 0  // Spotlight cards area — "This is the original video"
        case stitchVideo    = 1  // After first swipe — "This is a Stitch"
        case infoPanel      = 2  // Spotlight the Thread3DInfoPanel — "This shows the full conversation"
        case done           = 3  // "Now let's add yours" — dismiss
    }

    @State private var subStep: SubStep = .originalVideo
    @State private var progress: CGFloat = 0
    @State private var timerFired = false

    var body: some View {
        if onboarding.shouldShow && onboarding.currentStep == .threadExplore {
            GeometryReader { geometry in
                ZStack {
                    // Dim overlay — pass-through on spotlight area
                    if subStep != .done {
                        subStepDim(geometry: geometry)
                            .allowsHitTesting(false)
                    }

                    // Instruction card
                    if subStep != .done {
                        subStepCard(geometry: geometry)
                            .allowsHitTesting(false)
                    }

                    // Done card — needs hit testing for dismiss button
                    if subStep == .done {
                        doneCard
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear { startSubStep(.originalVideo) }
            .onReceive(NotificationCenter.default.publisher(for: .onboardingThreadViewSwiped)) { _ in
                // Only advance from originalVideo on first swipe.
                // stitchVideo and infoPanel must run their full timers so user
                // has time to read — don't skip on swipe.
                guard !timerFired else { return }
                guard subStep == .originalVideo else { return }
                timerFired = true
                withAnimation(.easeInOut(duration: 0.25)) { advanceSubStep() }
            }
        }
    }

    // MARK: - Sub-step Dim

    @ViewBuilder
    private func subStepDim(geometry: GeometryProxy) -> some View {
        let rect = subStepSpotlightRect(geometry: geometry)

        if rect == .zero {
            Color.black.opacity(0.60).ignoresSafeArea()
        } else {
            SpotlightCutoutShape(
                spotlightRect: rect.insetBy(dx: -20, dy: -20),
                cornerRadius: 18
            )
            .fill(Color.black.opacity(0.60))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: subStep.rawValue)

            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.cyan.opacity(0.9), lineWidth: 2.5)
                .frame(width: rect.width + 8, height: rect.height + 8)
                .position(x: rect.midX, y: rect.midY)
                .modifier(OnboardingPulseModifier())
                .animation(.easeInOut(duration: 0.35), value: subStep.rawValue)
        }
    }

    // MARK: - Sub-step Card

    @ViewBuilder
    private func subStepCard(geometry: GeometryProxy) -> some View {
        let rect  = subStepSpotlightRect(geometry: geometry)
        let above = rect.midY > geometry.size.height * 0.5
        let cardY: CGFloat = above
            ? max(60, rect.minY - 175)
            : min(rect.maxY + 16, geometry.size.height - 175)

        VStack {
            Spacer().frame(height: cardY)

            VStack(spacing: 10) {
                // Arrow toward spotlight
                if rect != .zero {
                    Image(systemName: above ? "arrowshape.down.fill" : "arrowshape.up.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.cyan)
                }

                // Sub-step dots
                HStack(spacing: 4) {
                    ForEach(SubStep.allCases.filter { $0 != .done }, id: \.rawValue) { s in
                        Circle()
                            .fill(s.rawValue <= subStep.rawValue
                                  ? Color.cyan : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }

                VStack(spacing: 5) {
                    Text(subStepTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(subStepInstruction)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                // Progress bar — auto-advance timer
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.cyan)
                            .frame(width: geo.size.width * progress)
                            .animation(.linear(duration: subStepDuration), value: progress)
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    // MARK: - Done Card
    // Shown as sub-step .done — full dim, no spotlight.
    // Button dismisses ThreadView back to fullscreen where Stitch button spotlight waits.

    private var doneCard: some View {
        ZStack {
            // Full dim — no cutout
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.cyan)
                }

                VStack(spacing: 8) {
                    Text("Now let's add yours")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Tap \"Go back\" and then tap the Stitch button to reply with your own video.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    // Advance onboarding then dismiss — returns to fullscreen
                    // where stitchButton spotlight is already waiting
                    onboarding.advance(from: .threadExplore)
                    dismiss()
                } label: {
                    Text("Go back to Stitch")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(OnboardingScaleStyle())
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Spotlight Rects
    // Uses geometry math — no PreferenceKey coordinate-space issues.
    // Video card area = center of screen between top bar and panel.
    // Panel area = bottom ~260pt of screen.

    private func subStepSpotlightRect(geometry: GeometryProxy) -> CGRect {
        let w = geometry.size.width
        let h = geometry.size.height
        switch subStep {
        case .originalVideo, .stitchVideo:
            // Card centered with nav arrows + close button taking ~60pt each side
            // Header (X + "1 of 5") takes ~120pt at top
            return CGRect(x: 60, y: 120, width: w - 120, height: h * 0.44)
        case .infoPanel:
            // Thread3DInfoPanel — bottom 36% of screen, inset from edges
            return CGRect(x: 12, y: h * 0.62, width: w - 24, height: h * 0.36)
        case .done:
            return .zero
        }
    }

    // MARK: - Sub-step Content

    private var subStepTitle: String {
        switch subStep {
        case .originalVideo: return "The original video"
        case .stitchVideo:   return "A Stitch"
        case .infoPanel:     return "The conversation"
        case .done:          return ""
        }
    }

    private var subStepInstruction: String {
        switch subStep {
        case .originalVideo: return "This is where the conversation started. Swipe left to see who replied."
        case .stitchVideo:   return "Someone replied with their own video. That\'s a Stitch. Swipe to explore more."
        case .infoPanel:     return "This panel shows everyone in the conversation. Tap any video to jump to it."
        case .done:          return ""
        }
    }

    private var subStepDuration: Double {
        switch subStep {
        case .originalVideo: return 4.0
        case .stitchVideo:   return 5.0   // longer — user just swiped, needs time to read
        case .infoPanel:     return 5.5   // longer — panel has lots of info to absorb
        case .done:          return 0
        }
    }

    // MARK: - Sub-step Transitions

    private func startSubStep(_ step: SubStep) {
        subStep = step
        progress = 0
        timerFired = false

        guard step != .done else { return }

        // Start progress bar animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.linear(duration: subStepDuration)) {
                progress = 1.0
            }
        }

        // Auto-advance timer
        DispatchQueue.main.asyncAfter(deadline: .now() + subStepDuration) {
            guard !timerFired else { return }
            timerFired = true
            advanceSubStep()
        }
    }

    /// Called by swipe in ThreadView OR timer
    func advanceSubStep() {
        guard subStep != .done else { return }
        let all = SubStep.allCases
        guard let next = all.first(where: { $0.rawValue == subStep.rawValue + 1 }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            timerFired = true // cancel any pending timer
            startSubStep(next)
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let onboardingThreadViewSwiped = Notification.Name("onboardingThreadViewSwiped")
}

// MARK: - Supporting Types

struct OnboardingPulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.38 : 0.82)
            .scaleEffect(on ? 1.06 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

struct OnboardingScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Spotlight Cutout Shape

/// Full-screen shape that fills everywhere EXCEPT the spotlight rect.
struct SpotlightCutoutShape: Shape {
    var spotlightRect: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(spotlightRect.animatableData, cornerRadius) }
        set {
            spotlightRect = CGRect(animatableData: newValue.first)
            cornerRadius  = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: spotlightRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

// MARK: - CGRect Animatable

extension CGRect {
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(origin.x, origin.y),
                AnimatablePair(size.width, size.height)
            )
        }
        set {
            origin.x    = newValue.first.first
            origin.y    = newValue.first.second
            size.width  = newValue.second.first
            size.height = newValue.second.second
        }
    }

    init(animatableData d: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                          AnimatablePair<CGFloat, CGFloat>>) {
        self.init(x: d.first.first, y: d.first.second,
                  width: d.second.first, height: d.second.second)
    }
}
