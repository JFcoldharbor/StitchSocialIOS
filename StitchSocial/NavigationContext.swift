//
//  ThreadNavigationCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - Reusable Thread Navigation System
//  Dependencies: VideoService (Layer 4), ThreadData (Layer 1)
//  Features: Stabilized gesture handling, context-aware navigation, smooth animations
//  Purpose: Single source of truth for thread navigation logic (HomeFeed + Profile)
//

import SwiftUI
import Combine

// MARK: - Thread Navigation Context

enum ThreadNavigationContext: String, CaseIterable {
    case homeFeed = "homeFeed"
    case profile = "profile"
    case discovery = "discovery"
    case fullscreen = "fullscreen"
    
    var allowsVerticalThreadNavigation: Bool {
        switch self {
        case .homeFeed, .discovery: return true
        case .profile, .fullscreen: return false
        }
    }
    
    var allowsHorizontalChildNavigation: Bool {
        switch self {
        case .homeFeed, .profile, .fullscreen: return true
        case .discovery: return false
        }
    }
    
    var autoProgressionEnabled: Bool {
        switch self {
        case .homeFeed, .discovery: return true
        case .profile, .fullscreen: return false
        }
    }
}

// MARK: - Navigation State

struct NavigationState {
    var currentThreadIndex: Int = 0
    var currentStitchIndex: Int = 0
    var verticalOffset: CGFloat = 0
    var horizontalOffset: CGFloat = 0
    var isAnimating: Bool = false
    var dragOffset: CGSize = .zero
    
    mutating func reset() {
        currentThreadIndex = 0
        currentStitchIndex = 0
        verticalOffset = 0
        horizontalOffset = 0
        isAnimating = false
        dragOffset = .zero
    }
}

// MARK: - ThreadNavigationCoordinator

@MainActor
class ThreadNavigationCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var navigationState = NavigationState()
    @Published var threads: [ThreadData] = []
    @Published var isReshuffling: Bool = false
    
    // MARK: - Dependencies
    
    private let videoService: VideoService
    private let context: ThreadNavigationContext
    
    // MARK: - Gesture Configuration
    
    private struct GestureConfig {
        static let minimumDistance: CGFloat = 20
        static let horizontalThreshold: CGFloat = 80
        static let verticalThreshold: CGFloat = 100
        static let directionRatio: CGFloat = 2.0
        static let animationDuration: TimeInterval = 0.4
        static let dragDamping: CGFloat = 0.8
        static let verticalDamping: CGFloat = 0.9
    }
    
    // MARK: - Auto-Progression
    
    private var videoPlayCounts: [String: Int] = [:]
    private var autoProgressTimer: Timer?
    private let maxPlaysPerVideo = 2
    
    // MARK: - Gesture State
    
    private var gestureDebouncer: Timer?
    private var containerSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init(videoService: VideoService, context: ThreadNavigationContext) {
        self.videoService = videoService
        self.context = context
    }
    
    deinit {
        Task { @MainActor in
            stopAutoProgression()
        }
        gestureDebouncer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    func setThreads(_ threads: [ThreadData]) {
        self.threads = threads
        navigationState.reset()
        
        print("🎯 COORDINATOR: Set \(threads.count) threads")
        for (index, thread) in threads.enumerated() {
            print("  Thread \(index): \(thread.id) with \(thread.childVideos.count) children")
            print("    Parent: \(thread.parentVideo.title)")
            for (childIndex, child) in thread.childVideos.enumerated() {
                print("    Child \(childIndex + 1): \(child.title)")
            }
        }
    }
    
    func setContainerSize(_ size: CGSize) {
        containerSize = size
    }
    
    func startAutoProgression() {
        guard context.autoProgressionEnabled else { return }
        
        autoProgressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAutoProgression()
            }
        }
    }
    
    func stopAutoProgression() {
        autoProgressTimer?.invalidate()
        autoProgressTimer = nil
    }
    
    func getCurrentThread() -> ThreadData? {
        guard navigationState.currentThreadIndex >= 0 &&
              navigationState.currentThreadIndex < threads.count else {
            return nil
        }
        return threads[navigationState.currentThreadIndex]
    }
    
    func getCurrentVideo() -> CoreVideoMetadata? {
        guard let thread = getCurrentThread() else { return nil }
        
        if navigationState.currentStitchIndex == 0 {
            return thread.parentVideo
        } else if navigationState.currentStitchIndex <= thread.childVideos.count {
            return thread.childVideos[navigationState.currentStitchIndex - 1]
        }
        
        return nil
    }
    
    // MARK: - Gesture Handling
    
    func handleDragChanged(_ value: DragGesture.Value) {
        // Cancel any pending debouncer
        gestureDebouncer?.invalidate()
        
        // Block during animation or reshuffling
        guard !navigationState.isAnimating && !isReshuffling else { return }
        
        let translation = value.translation
        let isHorizontalDrag = abs(translation.width) > abs(translation.height)
        
        if isHorizontalDrag && context.allowsHorizontalChildNavigation {
            // Check if horizontal movement is allowed
            if let thread = getCurrentThread(), !thread.childVideos.isEmpty {
                let dampedWidth = translation.width * GestureConfig.dragDamping
                navigationState.dragOffset = CGSize(width: dampedWidth, height: 0)
            } else {
                // Block horizontal but allow vertical
                let dampedHeight = translation.height * GestureConfig.verticalDamping
                navigationState.dragOffset = CGSize(width: 0, height: dampedHeight)
            }
        } else if context.allowsVerticalThreadNavigation {
            // Vertical drag with damping
            let dampedHeight = translation.height * GestureConfig.verticalDamping
            navigationState.dragOffset = CGSize(width: 0, height: dampedHeight)
        } else {
            // Context doesn't allow this direction
            navigationState.dragOffset = .zero
        }
    }
    
    func handleDragEnded(_ value: DragGesture.Value) {
        let translation = value.translation
        let velocity = value.velocity
        
        // Apply velocity boost for more responsive detection
        let adjustedTranslation = CGSize(
            width: translation.width + (velocity.width * 0.1),
            height: translation.height + (velocity.height * 0.1)
        )
        
        // Reset drag offset with animation
        withAnimation(.easeOut(duration: 0.2)) {
            navigationState.dragOffset = .zero
        }
        
        // Determine dominant direction
        let isHorizontal = abs(adjustedTranslation.width) > abs(adjustedTranslation.height)
        
        if isHorizontal && context.allowsHorizontalChildNavigation {
            handleHorizontalSwipe(translation: adjustedTranslation, velocity: velocity)
        } else if !isHorizontal && context.allowsVerticalThreadNavigation {
            handleVerticalSwipe(translation: adjustedTranslation, velocity: velocity)
        } else {
            print("🚫 SWIPE: Direction not allowed in context \(context)")
            smoothSnapToCurrentPosition()
        }
    }
    
    // MARK: - Navigation Methods
    
    func smoothMoveToThread(_ index: Int) {
        guard index >= 0 && index < threads.count else {
            print("❌ THREAD: Invalid index \(index)")
            return
        }
        
        print("🎯 THREAD: Moving to thread \(index)")
        
        navigationState.isAnimating = true
        navigationState.currentThreadIndex = index
        navigationState.currentStitchIndex = 0
        
        // Calculate new offsets
        let targetVerticalOffset = -CGFloat(index) * containerSize.height
        
        withAnimation(animationSpring) {
            navigationState.verticalOffset = targetVerticalOffset
            navigationState.horizontalOffset = 0
        }
        
        // End animation state
        DispatchQueue.main.asyncAfter(deadline: .now() + GestureConfig.animationDuration) {
            self.navigationState.isAnimating = false
        }
        
        // Preload adjacent content
        preloadAdjacentThreads()
    }
    
    func smoothMoveToStitch(_ index: Int) {
        guard let currentThread = getCurrentThread() else {
            print("❌ STITCH: No current thread")
            return
        }
        
        let maxIndex = currentThread.childVideos.count
        guard index >= 0 && index <= maxIndex else {
            print("❌ STITCH: Invalid index \(index) for thread with \(maxIndex) children")
            return
        }
        
        print("🎯 STITCH: Moving to stitch \(index)")
        
        navigationState.isAnimating = true
        navigationState.currentStitchIndex = index
        
        // Calculate horizontal offset
        let targetHorizontalOffset = -CGFloat(index) * containerSize.width
        
        withAnimation(animationSpring) {
            navigationState.horizontalOffset = targetHorizontalOffset
        }
        
        // End animation state
        DispatchQueue.main.asyncAfter(deadline: .now() + GestureConfig.animationDuration) {
            self.navigationState.isAnimating = false
        }
    }
    
    private func smoothSnapToCurrentPosition() {
        navigationState.isAnimating = true
        
        withAnimation(animationSpring) {
            navigationState.verticalOffset = -CGFloat(navigationState.currentThreadIndex) * containerSize.height
            navigationState.horizontalOffset = -CGFloat(navigationState.currentStitchIndex) * containerSize.width
        }
        
        withAnimation(.easeOut(duration: 0.2)) {
            navigationState.dragOffset = .zero
        }
        
        // End animation state
        DispatchQueue.main.asyncAfter(deadline: .now() + GestureConfig.animationDuration) {
            self.navigationState.isAnimating = false
        }
    }
    
    // MARK: - Swipe Handling
    
    private func handleHorizontalSwipe(translation: CGSize, velocity: CGSize) {
        guard let currentThread = getCurrentThread() else {
            print("❌ HORIZONTAL: No current thread")
            smoothSnapToCurrentPosition()
            return
        }
        
        print("🔍 HORIZONTAL: Current thread has \(currentThread.childVideos.count) children")
        print("🔍 HORIZONTAL: Current stitch index: \(navigationState.currentStitchIndex)")
        
        guard !currentThread.childVideos.isEmpty else {
            print("❌ HORIZONTAL: No children in thread \(currentThread.id)")
            smoothSnapToCurrentPosition()
            return
        }
        
        let isSwipeLeft = translation.width < 0  // Next child
        let isSwipeRight = translation.width > 0 // Previous child
        
        if isSwipeLeft {
            // Move to next child
            if navigationState.currentStitchIndex < currentThread.childVideos.count {
                let nextStitchIndex = navigationState.currentStitchIndex + 1
                print("➡️ HORIZONTAL: Moving to child \(nextStitchIndex) of \(currentThread.childVideos.count)")
                smoothMoveToStitch(nextStitchIndex)
            } else {
                print("🔚 HORIZONTAL: At end of children")
                smoothSnapToCurrentPosition()
            }
        } else if isSwipeRight {
            // Move to previous child
            if navigationState.currentStitchIndex > 0 {
                let prevStitchIndex = navigationState.currentStitchIndex - 1
                print("⬅️ HORIZONTAL: Moving to child \(prevStitchIndex)")
                smoothMoveToStitch(prevStitchIndex)
            } else {
                print("🏠 HORIZONTAL: At parent")
                smoothSnapToCurrentPosition()
            }
        }
    }
    
    private func handleVerticalSwipe(translation: CGSize, velocity: CGSize) {
        let isSwipeUp = translation.height < 0    // Next thread
        let isSwipeDown = translation.height > 0  // Previous thread
        
        if isSwipeUp {
            // Move to next thread
            if navigationState.currentThreadIndex < threads.count - 1 {
                let nextThreadIndex = navigationState.currentThreadIndex + 1
                print("⬇️ VERTICAL: Moving to thread \(nextThreadIndex)")
                smoothMoveToThread(nextThreadIndex)
            } else {
                print("🔚 VERTICAL: At end of threads")
                handleEndOfFeed()
            }
        } else if isSwipeDown {
            // Move to previous thread
            if navigationState.currentThreadIndex > 0 {
                let prevThreadIndex = navigationState.currentThreadIndex - 1
                print("⬆️ VERTICAL: Moving to thread \(prevThreadIndex)")
                smoothMoveToThread(prevThreadIndex)
            } else {
                print("🔝 VERTICAL: At top of feed")
                smoothSnapToCurrentPosition()
            }
        }
    }
    
    // MARK: - End of Feed Handling
    
    private func handleEndOfFeed() {
        print("🔄 END: Reached end of feed in context \(context)")
        
        switch context {
        case .homeFeed:
            triggerFeedReshuffling()
        case .discovery:
            smoothSnapToCurrentPosition() // Stay at current position
        case .profile, .fullscreen:
            smoothSnapToCurrentPosition() // Limited navigation context
        }
    }
    
    private func triggerFeedReshuffling() {
        print("🔄 RESHUFFLE: Starting feed reshuffling")
        isReshuffling = true
        
        // Simulate reshuffling delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Reset to beginning
            self.navigationState.reset()
            self.isReshuffling = false
            
            print("✅ RESHUFFLE: Feed reshuffling complete")
        }
    }
    
    // MARK: - Auto-Progression Logic
    
    private func checkAutoProgression() {
        guard let currentVideo = getCurrentVideo() else { return }
        
        let playCount = videoPlayCounts[currentVideo.id, default: 0] + 1
        videoPlayCounts[currentVideo.id] = playCount
        
        print("📺 AUTO: Video \(currentVideo.id) played \(playCount) times")
        
        // Only auto-advance for contexts that support it
        guard context.autoProgressionEnabled && playCount >= maxPlaysPerVideo else { return }
        
        // Reset count to prevent immediate re-triggering
        videoPlayCounts[currentVideo.id] = 0
        
        if playCount >= maxPlaysPerVideo {
            autoAdvanceToNext()
        }
    }
    
    private func autoAdvanceToNext() {
        // Try to advance to next child first, then next thread
        guard let currentThread = getCurrentThread() else { return }
        
        if navigationState.currentStitchIndex < currentThread.childVideos.count {
            // Move to next child
            smoothMoveToStitch(navigationState.currentStitchIndex + 1)
        } else if navigationState.currentThreadIndex < threads.count - 1 {
            // Move to next thread
            smoothMoveToThread(navigationState.currentThreadIndex + 1)
        } else {
            // Reached end - context-specific behavior
            handleEndOfFeed()
        }
    }
    
    // MARK: - Performance
    
    private func preloadAdjacentThreads() {
        Task {
            await videoService.preloadThreadsForNavigation(
                threads: threads,
                currentIndex: navigationState.currentThreadIndex,
                direction: .horizontal
            )
        }
    }
    
    // MARK: - Public Utilities
    
    func reset() {
        navigationState.reset()
        videoPlayCounts.removeAll()
        isReshuffling = false
    }
    
    // FIXED: Removed problematic updateContext method that referenced non-existent NavigationContext
    // Context switching not implemented - would require coordinator recreation
}

// MARK: - Gesture Configuration Extension

extension ThreadNavigationCoordinator {
    
    /// Get minimum drag distance for current context
    var minimumDragDistance: CGFloat {
        return GestureConfig.minimumDistance
    }
    
    /// Get animation spring configuration
    var animationSpring: Animation {
        return .spring(response: GestureConfig.animationDuration, dampingFraction: 0.8)
    }
    
    /// Check if navigation is currently blocked
    var isNavigationBlocked: Bool {
        return navigationState.isAnimating || isReshuffling
    }
}
