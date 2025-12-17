//
//  HomeFeedNavigationController.swift
//  StitchSocial
//
//  Layer 8: Views - Navigation Logic for HomeFeed
//  Dependencies: SwiftUI, ThreadData
//  Features: Thread/stitch navigation, offset management, smooth animations
//  OPTION A FIX: Removed onPlaybackShouldResume - VideoPlayerComponent is self-sufficient
//

import SwiftUI

// MARK: - Navigation Controller

class HomeFeedNavigationController: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentThreadIndex: Int = 0
    @Published var currentStitchIndex: Int = 0
    @Published var horizontalOffset: CGFloat = 0
    @Published var verticalOffset: CGFloat = 0
    
    // MARK: - Private Properties
    
    private var containerSize: CGSize = .zero
    private var threads: [ThreadData] = []
    
    // MARK: - Callbacks
    
    var onVideoChanged: ((CoreVideoMetadata) -> Void)?
    var onLoadMore: (() -> Void)?
    var onNavigationTracked: (() -> Void)?
    // REMOVED: onPlaybackShouldResume - VideoPlayerComponent handles its own playback
    
    // MARK: - Setup
    
    func setup(threads: [ThreadData], containerSize: CGSize) {
        self.threads = threads
        self.containerSize = containerSize
    }
    
    func updateThreads(_ threads: [ThreadData]) {
        self.threads = threads
    }
    
    // MARK: - Current Thread/Video
    
    func getCurrentThread() -> ThreadData? {
        guard currentThreadIndex >= 0 && currentThreadIndex < threads.count else {
            return nil
        }
        return threads[currentThreadIndex]
    }
    
    func getCurrentVideo() -> CoreVideoMetadata? {
        guard let thread = getCurrentThread() else { return nil }
        
        if currentStitchIndex == 0 {
            return thread.parentVideo
        } else {
            let childIndex = currentStitchIndex - 1
            guard childIndex >= 0 && childIndex < thread.childVideos.count else {
                return nil
            }
            return thread.childVideos[childIndex]
        }
    }
    
    // MARK: - Navigation Actions
    
    func moveVerticalUp() {
        if currentThreadIndex < threads.count - 1 {
            moveToThread(currentThreadIndex + 1)
        } else {
            onLoadMore?()
        }
    }
    
    func moveVerticalDown() {
        if currentThreadIndex > 0 {
            moveToThread(currentThreadIndex - 1)
        }
    }
    
    func moveHorizontalLeft() {
        guard let currentThread = getCurrentThread() else { return }
        guard !currentThread.childVideos.isEmpty else {
            print("🚫 No children to navigate to")
            return
        }
        
        if currentStitchIndex < currentThread.childVideos.count {
            moveToStitch(currentStitchIndex + 1)
        }
    }
    
    func moveHorizontalRight() {
        if currentStitchIndex > 0 {
            moveToStitch(currentStitchIndex - 1)
        }
    }
    
    func canSwipeHorizontal() -> Bool {
        guard let thread = getCurrentThread() else { return false }
        return !thread.childVideos.isEmpty
    }
    
    // MARK: - Private Navigation
    
    private func moveToThread(_ threadIndex: Int) {
        guard threadIndex >= 0 && threadIndex < threads.count else { return }
        
        currentThreadIndex = threadIndex
        currentStitchIndex = 0
        
        // Smooth animation to new position
        withAnimation(.easeOut(duration: 0.25)) {
            verticalOffset = -CGFloat(threadIndex) * containerSize.height
            horizontalOffset = 0
        }
        
        // Notify of video change
        if let newVideo = getCurrentVideo() {
            onVideoChanged?(newVideo)
        }
        
        // Track navigation
        onNavigationTracked?()
        
        // REMOVED: onPlaybackShouldResume delay
        // VideoPlayerComponent will automatically play when isActive becomes true
        
        print("🎬 MOVED TO THREAD: \(threadIndex)")
    }
    
    private func moveToStitch(_ stitchIndex: Int) {
        guard let currentThread = getCurrentThread() else { return }
        
        let maxStitchIndex = currentThread.childVideos.count
        guard stitchIndex >= 0 && stitchIndex <= maxStitchIndex else { return }
        
        currentStitchIndex = stitchIndex
        
        // Smooth animation to new position
        withAnimation(.easeOut(duration: 0.25)) {
            horizontalOffset = -CGFloat(stitchIndex) * containerSize.width
        }
        
        // Notify of video change
        if let newVideo = getCurrentVideo() {
            onVideoChanged?(newVideo)
        }
        
        // Track navigation
        onNavigationTracked?()
        
        // REMOVED: onPlaybackShouldResume delay
        // VideoPlayerComponent will automatically play when isActive becomes true
        
        print("🎯 MOVED TO STITCH: \(stitchIndex)")
    }
    
    // MARK: - Reset
    
    func reset() {
        currentThreadIndex = 0
        currentStitchIndex = 0
        horizontalOffset = 0
        verticalOffset = 0
    }
}
