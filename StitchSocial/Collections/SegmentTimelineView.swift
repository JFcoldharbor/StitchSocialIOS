//
//  SegmentTimelineView.swift
//  StitchSocial
//
//  Created by James Garmon on 3/31/26.
//


//
//  SegmentTimelineView.swift
//  StitchSocial
//
//  Layer 6: Views - Visual Segment Timeline
//  Dependencies: AutoSplitEngine, SwiftUI
//  Port of web SegmentEditor.jsx timeline div
//
//  Features: colored segment blocks, drag handles, playhead indicator,
//  ad slot markers, tap to seek, segment selection
//

import SwiftUI

// MARK: - Segment Colors

private let segmentColors: [Color] = [
    .pink, .purple, .cyan, .orange,
    .green, .blue, .yellow, .red,
    .indigo, .teal, .mint, .brown,
]

// MARK: - Segment Timeline View

struct SegmentTimelineView: View {
    
    @ObservedObject var engine: AutoSplitEngine
    @Binding var currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragSegIndex: Int?
    @State private var dragEdge: String?
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 56
            
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.08))
                    .frame(height: height)
                
                // Segment blocks
                ForEach(Array(engine.segments.enumerated()), id: \.element.id) { i, seg in
                    segmentBlock(seg: seg, index: i, totalWidth: width, height: height)
                }
                
                // Ad slot markers
                ForEach(engine.adSlots) { ad in
                    adMarker(ad: ad, totalWidth: width, height: height)
                }
                
                // Playhead
                playhead(totalWidth: width, height: height)
                
                // Time markers
                timeMarkers(totalWidth: width, height: height)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard !isDragging else { return }
                let ratio = max(0, min(1, location.x / width))
                onSeek(ratio * engine.duration)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let segIdx = dragSegIndex, let edge = dragEdge {
                            let ratio = max(0, min(1, value.location.x / width))
                            let time = ratio * engine.duration
                            engine.dragHandle(segIndex: segIdx, edge: edge, toTime: time)
                        }
                    }
                    .onEnded { _ in
                        dragSegIndex = nil
                        dragEdge = nil
                        isDragging = false
                    }
            )
        }
        .frame(height: 56)
    }
    
    // MARK: - Segment Block
    
    @ViewBuilder
    private func segmentBlock(seg: EditorSegment, index: Int, totalWidth: CGFloat, height: CGFloat) -> some View {
        let left = (seg.startTime / engine.duration) * totalWidth
        let blockWidth = ((seg.endTime - seg.startTime) / engine.duration) * totalWidth
        let color = segmentColors[index % segmentColors.count]
        let isSelected = engine.selectedSegmentID == seg.id
        
        ZStack(alignment: .topLeading) {
            // Colored block
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(seg.locked ? 0.7 : 0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
            
            // Index label
            if blockWidth > 24 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        if seg.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Text("\(index + 1)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 3)
                    .padding(.leading, 3)
                    
                    Spacer()
                    
                    if blockWidth > 40 {
                        Text(seg.formattedDuration)
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.bottom, 3)
                            .padding(.leading, 3)
                    }
                }
            }
            
            // Left drag handle
            if index > 0 {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                isDragging = true
                                dragSegIndex = index
                                dragEdge = "start"
                                let ratio = max(0, min(1, value.location.x / totalWidth))
                                engine.dragHandle(segIndex: index, edge: "start", toTime: ratio * engine.duration)
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragSegIndex = nil
                                dragEdge = nil
                            }
                    )
            }
            
            // Right drag handle
            if index < engine.segments.count - 1 {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 12)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    isDragging = true
                                    dragSegIndex = index
                                    dragEdge = "end"
                                    let globalX = left + value.location.x
                                    let ratio = max(0, min(1, globalX / totalWidth))
                                    engine.dragHandle(segIndex: index, edge: "end", toTime: ratio * engine.duration)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    dragSegIndex = nil
                                    dragEdge = nil
                                }
                        )
                }
            }
        }
        .frame(width: max(2, blockWidth), height: height)
        .offset(x: left)
        .onTapGesture {
            engine.selectedSegmentID = seg.id
        }
    }
    
    // MARK: - Ad Marker
    
    @ViewBuilder
    private func adMarker(ad: EditorAdSlot, totalWidth: CGFloat, height: CGFloat) -> some View {
        if ad.afterSegmentIndex < engine.segments.count {
            let seg = engine.segments[ad.afterSegmentIndex]
            let pos = (seg.endTime / engine.duration) * totalWidth
            
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 2, height: height)
                .offset(x: pos - 1)
                .overlay(
                    Image(systemName: "dollarsign")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.yellow)
                        .offset(x: pos - 1, y: -height / 2 - 4)
                    , alignment: .topLeading
                )
                .allowsHitTesting(false)
        }
    }
    
    // MARK: - Playhead
    
    private func playhead(totalWidth: CGFloat, height: CGFloat) -> some View {
        let pos = engine.duration > 0 ? (currentTime / engine.duration) * totalWidth : 0
        
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: height)
            
            // Top handle
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white)
                .frame(width: 8, height: 4)
                .offset(y: -2)
        }
        .offset(x: pos)
        .allowsHitTesting(false)
    }
    
    // MARK: - Time Markers
    
    private func timeMarkers(totalWidth: CGFloat, height: CGFloat) -> some View {
        let markerCount = min(20, Int(ceil(engine.duration / 60))) + 1
        
        return ForEach(0..<markerCount, id: \.self) { i in
            let t = TimeInterval(i * 60)
            if t <= engine.duration {
                let pos = (t / engine.duration) * totalWidth
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 0.5, height: height)
                    .offset(x: pos)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Segment List Row

struct SegmentListRow: View {
    let segment: EditorSegment
    let index: Int
    let hasAdAfter: Bool
    let onToggleLock: () -> Void
    let onRename: (String) -> Void
    let onPreview: () -> Void
    let onAddAd: () -> Void
    let onDelete: () -> Void
    
    @State private var editingTitle: String
    
    init(segment: EditorSegment, index: Int, hasAdAfter: Bool,
         onToggleLock: @escaping () -> Void, onRename: @escaping (String) -> Void,
         onPreview: @escaping () -> Void, onAddAd: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.segment = segment
        self.index = index
        self.hasAdAfter = hasAdAfter
        self.onToggleLock = onToggleLock
        self.onRename = onRename
        self.onPreview = onPreview
        self.onAddAd = onAddAd
        self.onDelete = onDelete
        self._editingTitle = State(initialValue: segment.title)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Color dot + index
            Circle()
                .fill(segmentColors[index % segmentColors.count])
                .frame(width: 8, height: 8)
            
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .frame(width: 16)
            
            // Lock toggle
            Button(action: onToggleLock) {
                Image(systemName: segment.locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10))
                    .foregroundColor(segment.locked ? .pink : .gray.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Title
            TextField("Segment title...", text: $editingTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .onChange(of: editingTitle) { _, newValue in
                    onRename(newValue)
                }
            
            // Time range
            Text("\(segment.formattedStartTime) → \(segment.formattedEndTime)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
            
            // Duration
            Text(segment.formattedDuration)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
            
            // Preview
            Button(action: onPreview) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            
            // Ad slot
            Button(action: onAddAd) {
                Image(systemName: "dollarsign")
                    .font(.system(size: 9))
                    .foregroundColor(hasAdAfter ? .yellow : .gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            engine_selectedID() ? Color.white.opacity(0.03) : Color.clear
        )
    }
    
    // Workaround — can't access engine directly from row
    private func engine_selectedID() -> Bool { false }
}

// MARK: - Ad Slot Row

struct AdSlotRow: View {
    let adSlot: EditorAdSlot
    let onUpdateType: (String) -> Void
    let onUpdateDuration: (TimeInterval) -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 28)
            
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
            
            Text("AD BREAK")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.yellow)
            
            // Type picker
            Menu {
                Button("pre-roll") { onUpdateType("pre-roll") }
                Button("mid-roll") { onUpdateType("mid-roll") }
                Button("post-roll") { onUpdateType("post-roll") }
            } label: {
                Text(adSlot.type)
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Duration picker
            Menu {
                Button("15s") { onUpdateDuration(15) }
                Button("30s") { onUpdateDuration(30) }
                Button("60s") { onUpdateDuration(60) }
            } label: {
                Text("\(Int(adSlot.durationSeconds))s")
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 8))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.03))
    }
}