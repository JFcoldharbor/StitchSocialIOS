//
//  HomeFeedDebugger.swift
//  StitchSocial
//
//  Created by James Garmon on 12/17/25.
//


//
//  HomeFeedDebugger.swift
//  StitchSocial
//
//  COMPREHENSIVE DEBUGGER - Trace every step of HomeFeed lifecycle
//  Add this file to your project and call HomeFeedDebugger.shared methods
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

// MARK: - HomeFeed Debugger

@MainActor
class HomeFeedDebugger: ObservableObject {
    
    static let shared = HomeFeedDebugger()
    
    // MARK: - State Tracking
    
    @Published var isEnabled = true
    @Published var eventLog: [DebugEvent] = []
    
    private var startTime: Date = Date()
    private var swipeCount = 0
    private var playerCreateCount = 0
    private var playerFailCount = 0
    private var poolHitCount = 0
    private var poolMissCount = 0
    
    // MARK: - Event Types
    
    enum EventType: String {
        case lifecycle = "🔄 LIFECYCLE"
        case feed = "📋 FEED"
        case navigation = "👆 NAV"
        case gesture = "✋ GESTURE"
        case player = "🎬 PLAYER"
        case playback = "▶️ PLAYBACK"
        case error = "❌ ERROR"
        case warning = "⚠️ WARNING"
        case pool = "🏊 POOL"
        case state = "📊 STATE"
    }
    
    struct DebugEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let elapsed: TimeInterval
        let type: EventType
        let message: String
        let details: String?
        
        var formatted: String {
            let elapsedStr = String(format: "%.2fs", elapsed)
            if let details = details {
                return "[\(elapsedStr)] \(type.rawValue): \(message)\n    → \(details)"
            }
            return "[\(elapsedStr)] \(type.rawValue): \(message)"
        }
    }
    
    private init() {
        startTime = Date()
        log(.lifecycle, "Debugger initialized")
    }
    
    // MARK: - Logging
    
    func log(_ type: EventType, _ message: String, details: String? = nil) {
        guard isEnabled else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let event = DebugEvent(
            timestamp: Date(),
            elapsed: elapsed,
            type: type,
            message: message,
            details: details
        )
        
        eventLog.append(event)
        print(event.formatted)
        
        // Keep log manageable
        if eventLog.count > 500 {
            eventLog.removeFirst(100)
        }
    }
    
    func error(_ message: String, error: Error? = nil) {
        let details = error?.localizedDescription
        log(.error, message, details: details)
        playerFailCount += 1
    }
    
    func warning(_ message: String, details: String? = nil) {
        log(.warning, message, details: details)
    }
    
    // MARK: - Lifecycle Events
    
    func feedViewAppeared() {
        startTime = Date() // Reset timer
        swipeCount = 0
        log(.lifecycle, "HomeFeedView.onAppear")
    }
    
    func feedViewDisappeared() {
        log(.lifecycle, "HomeFeedView.onDisappear", details: "Total swipes: \(swipeCount)")
    }
    
    func gridAppeared(threadCount: Int) {
        log(.lifecycle, "HomeFeedVideoGrid appeared", details: "\(threadCount) threads")
    }
    
    func containerAppeared(videoID: String, isActive: Bool) {
        log(.lifecycle, "Container appeared: \(videoID.prefix(8))", details: "isActive: \(isActive)")
    }
    
    func playerComponentAppeared(videoID: String, isActive: Bool) {
        log(.player, "PlayerComponent appeared: \(videoID.prefix(8))", details: "isActive: \(isActive)")
    }
    
    // MARK: - Feed Events
    
    func feedLoadStarted(source: String) {
        log(.feed, "Load started", details: "source: \(source)")
    }
    
    func feedLoadCompleted(threadCount: Int, source: String) {
        log(.feed, "Load completed", details: "\(threadCount) threads from \(source)")
    }
    
    func feedLoadFailed(error: Error) {
        self.error("Feed load failed", error: error)
    }
    
    func feedEmpty() {
        warning("Feed is empty")
    }
    
    // MARK: - Navigation Events
    
    func navigationSetup(threadCount: Int, containerSize: CGSize) {
        log(.navigation, "Navigation setup", details: "threads: \(threadCount), size: \(containerSize)")
    }
    
    func currentPosition(threadIndex: Int, stitchIndex: Int, threadCount: Int) {
        log(.state, "Position: thread \(threadIndex)/\(threadCount), stitch \(stitchIndex)")
    }
    
    // MARK: - Gesture Events
    
    func gestureDragStarted() {
        log(.gesture, "Drag started")
    }
    
    func gestureDragChanged(translation: CGSize, direction: String) {
        // Only log significant movements to reduce spam
        if abs(translation.width) > 50 || abs(translation.height) > 50 {
            log(.gesture, "Dragging", details: "translation: \(translation), direction: \(direction)")
        }
    }
    
    func gestureDragEnded(result: String) {
        swipeCount += 1
        log(.gesture, "Drag ended (#\(swipeCount))", details: "result: \(result)")
    }
    
    func swipeCommitted(direction: String, fromThread: Int, fromStitch: Int) {
        log(.navigation, "Swipe committed: \(direction)", details: "from thread:\(fromThread) stitch:\(fromStitch)")
    }
    
    func navigationCompleted(toThread: Int, toStitch: Int, videoID: String) {
        log(.navigation, "Navigation completed", details: "to thread:\(toThread) stitch:\(toStitch) video:\(videoID.prefix(8))")
    }
    
    // MARK: - Player Events
    
    func playerSetupStarted(videoID: String, isActive: Bool) {
        log(.player, "Setup started: \(videoID.prefix(8))", details: "isActive: \(isActive)")
    }
    
    func playerPoolHit(videoID: String) {
        poolHitCount += 1
        log(.pool, "Pool HIT: \(videoID.prefix(8))", details: "hits: \(poolHitCount), misses: \(poolMissCount)")
    }
    
    func playerPoolMiss(videoID: String) {
        poolMissCount += 1
        log(.pool, "Pool MISS: \(videoID.prefix(8))", details: "hits: \(poolHitCount), misses: \(poolMissCount)")
    }
    
    func playerCreating(videoID: String, url: String) {
        playerCreateCount += 1
        log(.player, "Creating player #\(playerCreateCount): \(videoID.prefix(8))", details: "url: \(url.prefix(50))...")
    }
    
    func playerCreated(videoID: String) {
        log(.player, "Player created: \(videoID.prefix(8))")
    }
    
    func playerReady(videoID: String, isActive: Bool) {
        log(.player, "Player READY: \(videoID.prefix(8))", details: "isActive: \(isActive)")
    }
    
    func playerFailed(videoID: String, error: Error?) {
        self.error("Player FAILED: \(videoID.prefix(8))", error: error)
    }
    
    func playerInvalidURL(videoID: String, url: String) {
        error("Invalid URL for \(videoID.prefix(8))", error: nil)
        log(.error, "URL was: \(url)")
    }
    
    // MARK: - Playback Events
    
    func playbackStarted(videoID: String, source: String) {
        log(.playback, "▶️ PLAY: \(videoID.prefix(8))", details: "source: \(source)")
    }
    
    func playbackPaused(videoID: String, reason: String) {
        log(.playback, "⏸️ PAUSE: \(videoID.prefix(8))", details: "reason: \(reason)")
    }
    
    func playbackReset(videoID: String) {
        log(.playback, "⏮️ RESET: \(videoID.prefix(8))")
    }
    
    func playbackLooped(videoID: String) {
        log(.playback, "🔄 LOOP: \(videoID.prefix(8))")
    }
    
    func playbackKilled(videoID: String) {
        log(.playback, "🛑 KILLED: \(videoID.prefix(8))")
    }
    
    // MARK: - Active State Events
    
    func activeStateChanged(videoID: String, from: Bool, to: Bool) {
        let emoji = to ? "✅" : "⬜"
        log(.state, "\(emoji) Active: \(from) → \(to) for \(videoID.prefix(8))")
    }
    
    func activeVideoMismatch(expected: String, actual: String?) {
        warning("Active video mismatch", details: "expected: \(expected.prefix(8)), actual: \(actual?.prefix(8) ?? "nil")")
    }
    
    // MARK: - Pool Events
    
    func poolStatus(size: Int, maxSize: Int, activeVideo: String?) {
        log(.pool, "Pool: \(size)/\(maxSize)", details: "active: \(activeVideo?.prefix(8) ?? "none")")
    }
    
    func poolEviction(videoID: String) {
        warning("Pool evicted: \(videoID.prefix(8))")
    }
    
    func poolCleared() {
        log(.pool, "Pool CLEARED")
    }
    
    // MARK: - Summary
    
    func printSummary() {
        let summary = """
        
        ═══════════════════════════════════════════════
        📊 HOMEFEED DEBUG SUMMARY
        ═══════════════════════════════════════════════
        Total events: \(eventLog.count)
        Duration: \(String(format: "%.1fs", Date().timeIntervalSince(startTime)))
        
        📈 STATS:
        • Swipes: \(swipeCount)
        • Players created: \(playerCreateCount)
        • Player failures: \(playerFailCount)
        • Pool hits: \(poolHitCount)
        • Pool misses: \(poolMissCount)
        • Hit rate: \(poolHitCount + poolMissCount > 0 ? String(format: "%.1f%%", Double(poolHitCount) / Double(poolHitCount + poolMissCount) * 100) : "N/A")
        
        ❌ ERRORS (\(eventLog.filter { $0.type == .error }.count)):
        \(eventLog.filter { $0.type == .error }.map { "  • \($0.message)" }.joined(separator: "\n"))
        
        ⚠️ WARNINGS (\(eventLog.filter { $0.type == .warning }.count)):
        \(eventLog.filter { $0.type == .warning }.map { "  • \($0.message)" }.joined(separator: "\n"))
        ═══════════════════════════════════════════════
        
        """
        print(summary)
    }
    
    func reset() {
        eventLog.removeAll()
        startTime = Date()
        swipeCount = 0
        playerCreateCount = 0
        playerFailCount = 0
        poolHitCount = 0
        poolMissCount = 0
        log(.lifecycle, "Debugger reset")
    }
    
    // MARK: - Export
    
    func exportLog() -> String {
        return eventLog.map { $0.formatted }.joined(separator: "\n")
    }
}

// MARK: - Debug View Overlay (Add to HomeFeedView for visual debugging)

struct HomeFeedDebugOverlay: View {
    @ObservedObject var debugger = HomeFeedDebugger.shared
    @State private var isExpanded = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Toggle button
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "ant.fill")
                            Text("DEBUG")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                    }
                    
                    if isExpanded {
                        // Quick stats
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Swipes: \(debugger.eventLog.filter { $0.type == .gesture && $0.message.contains("ended") }.count)")
                            Text("Errors: \(debugger.eventLog.filter { $0.type == .error }.count)")
                            Text("Events: \(debugger.eventLog.count)")
                        }
                        .font(.caption2.monospaced())
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        
                        // Actions
                        HStack(spacing: 8) {
                            Button("Summary") {
                                debugger.printSummary()
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                            
                            Button("Reset") {
                                debugger.reset()
                            }
                            .font(.caption2)
                            .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        
                        // Recent events
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(debugger.eventLog.suffix(10).reversed()) { event in
                                    Text(event.formatted)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(colorFor(event.type))
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(width: 280, height: 150)
                        .padding(8)
                        .background(Color.black.opacity(0.9))
                        .cornerRadius(8)
                    }
                }
                .padding(.trailing, 8)
            }
            
            Spacer()
        }
        .padding(.top, 60)
    }
    
    private func colorFor(_ type: HomeFeedDebugger.EventType) -> Color {
        switch type {
        case .error: return .red
        case .warning: return .orange
        case .playback: return .green
        case .gesture: return .cyan
        case .navigation: return .yellow
        case .player: return .purple
        case .pool: return .blue
        default: return .white
        }
    }
}

// MARK: - Quick Debug Extension for Strings

extension String {
    var debugID: String {
        return String(self.prefix(8))
    }
}