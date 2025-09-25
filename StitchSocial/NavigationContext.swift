//
//  ThreadNavigationCoordinator.swift
//  StitchSocial
//
//  Layer 6: Coordination - Reusable Thread Navigation System
//  Dependencies: VideoService (Layer 4), ThreadData (Layer 1), NavigationContext
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
        
        // Determine swipe direction with strict thresholds
        let isHorizontalSwipe = abs(adjustedTranslation.width) > GestureConfig.horizontalThreshold &&
                               abs(adjustedTranslation.width) > abs(adjustedTranslation.height) * GestureConfig.directionRatio
        let isVerticalSwipe = abs(adjustedTranslation.height) > GestureConfig.verticalThreshold &&
                             abs(adjustedTranslation.height) > abs(adjustedTranslation.width) * GestureConfig.directionRatio
        
        // Debounce rapid gestures
        gestureDebouncer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processGesture(
                    isHorizontal: isHorizontalSwipe,
                    isVertical: isVerticalSwipe,
                    translation: adjustedTranslation,
                    velocity: velocity
                )
            }
        }
    }
    
    // MARK: - Gesture Processing
    
    private func processGesture(
        isHorizontal: Bool,
        isVertical: Bool,
        translation: CGSize,
        velocity: CGSize
    ) {
        print("🎯 GESTURE: Horizontal=\(isHorizontal), Vertical=\(isVertical)")
        print("🎯 GESTURE: Translation=\(translation), Context=\(context)")
        print("🎯 GESTURE: Context allows horizontal=\(context.allowsHorizontalChildNavigation)")
        
        navigationState.isAnimating = true
        
        if isHorizontal && context.allowsHorizontalChildNavigation {
            print("✅ GESTURE: Processing horizontal swipe")
            handleHorizontalSwipe(translation: translation, velocity: velocity)
        } else if isVertical && context.allowsVerticalThreadNavigation {
            print("✅ GESTURE: Processing vertical swipe")
            handleVerticalSwipe(translation: translation, velocity: velocity)
        } else {
            print("❌ GESTURE: Ambiguous or blocked - snapping back")
            smoothSnapToCurrentPosition()
        }
        
        // Reset drag state with animation
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
            if navigationState.currentThreadIndex < threads.count - 1 {
                smoothMoveToThread(navigationState.currentThreadIndex + 1)
            } else {
                // Context-specific behavior at end
                handleEndOfFeed()
            }
        } else if isSwipeDown {
            if navigationState.currentThreadIndex > 0 {
                smoothMoveToThread(navigationState.currentThreadIndex - 1)
            } else {
                smoothSnapToCurrentPosition()
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    func smoothMoveToThread(_ threadIndex: Int) {
        guard threadIndex >= 0 && threadIndex < threads.count else {
            smoothSnapToCurrentPosition()
            return
        }
        
        navigationState.currentThreadIndex = threadIndex
        navigationState.currentStitchIndex = 0 // Reset to parent
        
        // Smooth spring animation
        withAnimation(.spring(response: GestureConfig.animationDuration, dampingFraction: 0.8)) {
            navigationState.verticalOffset = -CGFloat(threadIndex) * containerSize.height
            navigationState.horizontalOffset = 0 // Reset horizontal when changing threads
        }
        
        // Reset video play count for new thread
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
        
        // Preload adjacent content
        preloadAdjacentThreads()
    }
    
    func smoothMoveToStitch(_ stitchIndex: Int) {
        guard let currentThread = getCurrentThread() else {
            smoothSnapToCurrentPosition()
            return
        }
        
        let maxStitchIndex = currentThread.childVideos.count
        guard stitchIndex >= 0 && stitchIndex <= maxStitchIndex else {
            smoothSnapToCurrentPosition()
            return
        }
        
        navigationState.currentStitchIndex = stitchIndex
        
        // Smooth spring animation
        withAnimation(.spring(response: GestureConfig.animationDuration, dampingFraction: 0.8)) {
            navigationState.horizontalOffset = -CGFloat(stitchIndex) * containerSize.width
        }
        
        // Reset video play count for new video
        if let newVideo = getCurrentVideo() {
            resetVideoPlayCount(for: newVideo.id)
        }
    }
    
    private func smoothSnapToCurrentPosition() {
        // Smooth return to current position
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            // Offsets remain unchanged - just smooth animation
        }
    }
    
    // MARK: - Context-Specific Behavior
    
    private func handleEndOfFeed() {
        switch context {
        case .homeFeed:
            // Reshuffle feed
            reshuffleAndResetFeed()
        case .profile:
            // Snap back - no reshuffling in profile
            smoothSnapToCurrentPosition()
        case .discovery, .fullscreen:
            // Context-specific end behavior
            smoothSnapToCurrentPosition()
        }
    }
    
    private func reshuffleAndResetFeed() {
        guard !isReshuffling else { return }
        
        isReshuffling = true
        
        Task {
            // Simulate reshuffling delay
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                // Reset navigation state
                navigationState.reset()
                
                // Clear play counts
                videoPlayCounts.removeAll()
                
                isReshuffling = false
            }
        }
    }
    
    // MARK: - Auto-Progression
    
    func incrementVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID, default: 0] += 1
    }
    
    private func resetVideoPlayCount(for videoID: String) {
        videoPlayCounts[videoID] = 0
    }
    
    private func checkAutoProgression() {
        guard let currentVideo = getCurrentVideo() else { return }
        
        let videoID = currentVideo.id
        let playCount = videoPlayCounts[videoID] ?? 0
        
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
    
    func updateContext(_ newContext: NavigationContext) {
        // Context switching not implemented yet - would recreate coordinator
        print("Context switching to \(newContext) - requires coordinator recreation")
    }
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
