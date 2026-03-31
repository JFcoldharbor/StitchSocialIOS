//
//  AutoSplitEngine.swift
//  StitchSocial
//
//  Layer 2: Logic - Segment Split Math Engine
//  Dependencies: Foundation, OptimizationConfig
//  Port of web SegmentEditor.jsx auto-split logic
//
//  Handles: interval-based splitting, manual lock/unlock, redistribute around locks,
//  delete + redistribute, split at playhead, ad slot management
//
//  CACHING: This is pure in-memory computation — no Firestore reads.
//  Segments are only written to Firestore on finalize.
//

import Foundation

// MARK: - Segment Split Interval

enum SplitInterval: TimeInterval, CaseIterable, Identifiable {
    case oneMin = 60
    case threeMin = 180
    case fiveMin = 300
    case nineMin = 540
    case twelveMin = 720
    case fifteenMin = 900
    
    var id: TimeInterval { rawValue }
    
    var label: String {
        switch self {
        case .oneMin: return "1 min"
        case .threeMin: return "3 min"
        case .fiveMin: return "5 min"
        case .nineMin: return "9 min"
        case .twelveMin: return "12 min"
        case .fifteenMin: return "15 min"
        }
    }
}

// MARK: - Editor Segment (in-memory only, not persisted until finalize)

struct EditorSegment: Identifiable, Equatable {
    let id: String
    var index: Int
    var title: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var locked: Bool            // true = manual (user-placed), false = auto
    
    var duration: TimeInterval { endTime - startTime }
    
    var formattedStartTime: String { Self.formatTime(startTime) }
    var formattedEndTime: String { Self.formatTime(endTime) }
    var formattedDuration: String { Self.formatTime(duration) }
    
    static func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Editor Ad Slot (in-memory)

struct EditorAdSlot: Identifiable, Equatable {
    let id: String
    var afterSegmentIndex: Int
    var type: String            // "pre-roll", "mid-roll", "post-roll"
    var durationSeconds: TimeInterval
    
    var insertAfterTime: TimeInterval? // Set on finalize from segment endTime
}

// MARK: - Split Mode

enum SplitMode: String, CaseIterable {
    case auto = "Auto"
    case manual = "Manual"
}

// MARK: - Auto Split Engine

@MainActor
class AutoSplitEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published var segments: [EditorSegment] = []
    @Published var adSlots: [EditorAdSlot] = []
    @Published var mode: SplitMode = .auto
    @Published var interval: SplitInterval = .threeMin
    @Published var selectedSegmentID: String?
    
    // MARK: - Configuration
    
    let duration: TimeInterval
    private let minSegmentDuration: TimeInterval = 2.0
    
    // MARK: - Init
    
    init(duration: TimeInterval) {
        self.duration = duration
        if duration > 0 {
            generateAutoSegments()
        }
    }
    
    // MARK: - Auto-Segment Generation
    
    /// Pure auto — split evenly by interval
    func generateAutoSegments() {
        guard duration > 0 else { return }
        
        let manualSegs = segments.filter { $0.locked }
        
        if manualSegs.isEmpty {
            // Pure auto split
            let count = max(1, Int(ceil(duration / interval.rawValue)))
            let segDur = duration / Double(count)
            var newSegs: [EditorSegment] = []
            for i in 0..<count {
                let start = Double(i) * segDur
                let end = min(Double(i + 1) * segDur, duration)
                newSegs.append(makeSegment(index: i, start: start, end: end, locked: false))
            }
            segments = newSegs
        } else {
            redistributeAroundManual(manualSegs)
        }
    }
    
    /// Mixed mode — auto-fill gaps around manually locked segments
    private func redistributeAroundManual(_ manualSegs: [EditorSegment]) {
        let sorted = manualSegs.sorted { $0.startTime < $1.startTime }
        var result: [EditorSegment] = []
        var cursor: TimeInterval = 0
        
        for manual in sorted {
            // Fill gap before this manual segment
            if manual.startTime > cursor + 0.5 {
                let gap = manual.startTime - cursor
                let autoCount = max(1, Int(round(gap / interval.rawValue)))
                let autoDur = gap / Double(autoCount)
                for i in 0..<autoCount {
                    let start = cursor + Double(i) * autoDur
                    let end = cursor + Double(i + 1) * autoDur
                    result.append(makeSegment(index: result.count, start: start, end: end, locked: false))
                }
            }
            // Add manual segment with updated index
            var m = manual
            m.index = result.count
            result.append(m)
            cursor = manual.endTime
        }
        
        // Fill gap after last manual segment
        if cursor < duration - 0.5 {
            let gap = duration - cursor
            let autoCount = max(1, Int(round(gap / interval.rawValue)))
            let autoDur = gap / Double(autoCount)
            for i in 0..<autoCount {
                let start = cursor + Double(i) * autoDur
                let end = min(cursor + Double(i + 1) * autoDur, duration)
                result.append(makeSegment(index: result.count, start: start, end: end, locked: false))
            }
        }
        
        segments = result
    }
    
    // MARK: - Segment Operations
    
    /// Delete a segment and redistribute
    func deleteSegment(_ segId: String) {
        guard let segIdx = segments.firstIndex(where: { $0.id == segId }) else { return }
        
        // Remove ad slots referencing this segment
        adSlots = adSlots.filter { $0.afterSegmentIndex != segIdx }
            .map { slot in
                var s = slot
                if s.afterSegmentIndex > segIdx { s.afterSegmentIndex -= 1 }
                return s
            }
        
        var newSegs = segments
        newSegs.remove(at: segIdx)
        
        if mode == .auto {
            let manualSegs = newSegs.filter { $0.locked }
            if manualSegs.isEmpty {
                // Regenerate evenly
                let count = max(1, newSegs.count)
                let segDur = duration / Double(count)
                segments = (0..<count).map { i in
                    makeSegment(index: i, start: Double(i) * segDur, end: min(Double(i + 1) * segDur, duration), locked: false)
                }
            } else {
                redistributeAroundManual(manualSegs)
            }
        } else {
            // Manual mode — just reindex
            segments = newSegs.enumerated().map { i, s in
                var seg = s; seg.index = i; return seg
            }
        }
    }
    
    /// Toggle lock (manual/auto) on a segment
    func toggleLock(_ segId: String) {
        guard let idx = segments.firstIndex(where: { $0.id == segId }) else { return }
        segments[idx].locked.toggle()
        
        if mode == .auto {
            let manualSegs = segments.filter { $0.locked }
            if manualSegs.isEmpty {
                generateAutoSegments()
            } else {
                redistributeAroundManual(manualSegs)
            }
        }
    }
    
    /// Rename a segment
    func renameSegment(_ segId: String, title: String) {
        guard let idx = segments.firstIndex(where: { $0.id == segId }) else { return }
        segments[idx].title = title
    }
    
    /// Split at playhead position (manual mode)
    func splitAtPlayhead(_ time: TimeInterval) {
        guard mode == .manual else { return }
        guard let segIdx = segments.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) else { return }
        
        let seg = segments[segIdx]
        guard time - seg.startTime >= minSegmentDuration,
              seg.endTime - time >= minSegmentDuration else { return }
        
        let left = makeSegment(index: segIdx, start: seg.startTime, end: time, locked: seg.locked)
        let right = makeSegment(index: segIdx + 1, start: time, end: seg.endTime, locked: seg.locked)
        
        segments.replaceSubrange(segIdx...segIdx, with: [left, right])
        reindex()
    }
    
    /// Drag a segment boundary handle
    func dragHandle(segIndex: Int, edge: String, toTime: TimeInterval) {
        guard segIndex >= 0 && segIndex < segments.count else { return }
        
        if edge == "start" && segIndex > 0 {
            let prevSeg = segments[segIndex - 1]
            guard !prevSeg.locked else { return }
            
            let newStart = max(prevSeg.startTime + minSegmentDuration,
                              min(toTime, segments[segIndex].endTime - minSegmentDuration))
            segments[segIndex].startTime = newStart
            segments[segIndex - 1].endTime = newStart
            
        } else if edge == "end" && segIndex < segments.count - 1 {
            let nextSeg = segments[segIndex + 1]
            guard !nextSeg.locked else { return }
            
            let newEnd = max(segments[segIndex].startTime + minSegmentDuration,
                            min(toTime, nextSeg.endTime - minSegmentDuration))
            segments[segIndex].endTime = newEnd
            segments[segIndex + 1].startTime = newEnd
        }
    }
    
    /// Change mode
    func setMode(_ newMode: SplitMode) {
        mode = newMode
        if newMode == .auto {
            generateAutoSegments()
        }
    }
    
    /// Change interval
    func setInterval(_ newInterval: SplitInterval) {
        interval = newInterval
        if mode == .auto {
            generateAutoSegments()
        }
    }
    
    // MARK: - Ad Slot Operations
    
    func addAdSlot(afterSegmentIndex: Int) {
        let slot = EditorAdSlot(
            id: "ad_\(UUID().uuidString.prefix(8))",
            afterSegmentIndex: afterSegmentIndex,
            type: "mid-roll",
            durationSeconds: 30
        )
        adSlots.append(slot)
    }
    
    func removeAdSlot(_ adId: String) {
        adSlots.removeAll { $0.id == adId }
    }
    
    func updateAdSlot(_ adId: String, type: String? = nil, duration: TimeInterval? = nil) {
        guard let idx = adSlots.firstIndex(where: { $0.id == adId }) else { return }
        if let type = type { adSlots[idx].type = type }
        if let duration = duration { adSlots[idx].durationSeconds = duration }
    }
    
    // MARK: - Finalize Output
    
    /// Convert editor state to finalize payload (matches web's handleFinalize output)
    func finalizeData() -> (segments: [EditorSegment], adSlots: [EditorAdSlot], totalDuration: TimeInterval) {
        let finalSegments = segments.enumerated().map { i, seg -> EditorSegment in
            var s = seg
            s.index = i
            if s.title.isEmpty { s.title = "Segment \(i + 1)" }
            return s
        }
        
        let finalAdSlots = adSlots.map { slot -> EditorAdSlot in
            var s = slot
            s.insertAfterTime = segments[safe: slot.afterSegmentIndex]?.endTime ?? 0
            return s
        }
        
        return (finalSegments, finalAdSlots, duration)
    }
    
    // MARK: - Stats
    
    var manualCount: Int { segments.filter { $0.locked }.count }
    var autoCount: Int { segments.filter { !$0.locked }.count }
    
    // MARK: - Private Helpers
    
    private func makeSegment(index: Int, start: TimeInterval, end: TimeInterval, locked: Bool) -> EditorSegment {
        EditorSegment(
            id: "seg_\(UUID().uuidString.prefix(8))",
            index: index,
            title: "Segment \(index + 1)",
            startTime: (start * 100).rounded() / 100,
            endTime: (end * 100).rounded() / 100,
            locked: locked
        )
    }
    
    private func reindex() {
        for i in segments.indices {
            segments[i].index = i
        }
    }
}
