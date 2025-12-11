//
//  CollectionAccessibilityManager.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionAccessibility.swift
//  StitchSocial
//
//  Layer 6: Views - Accessibility Support
//  Dependencies: SwiftUI, Foundation
//  Features: VoiceOver labels, Dynamic Type, reduced motion, accessibility actions, traits
//  CREATED: Phase 7 - Collections feature Polish
//

import SwiftUI
import Combine

// MARK: - Accessibility Manager

/// Manages accessibility settings and provides helpers for Collections feature
@MainActor
class CollectionAccessibilityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CollectionAccessibilityManager()
    
    // MARK: - Published State
    
    /// Whether VoiceOver is running
    @Published private(set) var isVoiceOverRunning: Bool = false
    
    /// Whether reduce motion is enabled
    @Published private(set) var reduceMotionEnabled: Bool = false
    
    /// Whether reduce transparency is enabled
    @Published private(set) var reduceTransparencyEnabled: Bool = false
    
    /// Current Dynamic Type size
    @Published private(set) var dynamicTypeSize: DynamicTypeSize = .medium
    
    /// Whether bold text is enabled
    @Published private(set) var boldTextEnabled: Bool = false
    
    /// Whether differentiate without color is enabled
    @Published private(set) var differentiateWithoutColor: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
        updateCurrentSettings()
        
        print("♿️ ACCESSIBILITY: Initialized")
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        // VoiceOver changes
        NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
            }
            .store(in: &cancellables)
        
        // Reduce motion changes
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
            }
            .store(in: &cancellables)
        
        // Reduce transparency changes
        NotificationCenter.default.publisher(for: UIAccessibility.reduceTransparencyStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
            }
            .store(in: &cancellables)
        
        // Bold text changes
        NotificationCenter.default.publisher(for: UIAccessibility.boldTextStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.boldTextEnabled = UIAccessibility.isBoldTextEnabled
            }
            .store(in: &cancellables)
        
        // Differentiate without color changes
        NotificationCenter.default.publisher(for: NSNotification.Name(rawValue: "UIAccessibilityDifferentiateWithoutColorDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.differentiateWithoutColor = UIAccessibility.shouldDifferentiateWithoutColor
            }
            .store(in: &cancellables)
    }
    
    private func updateCurrentSettings() {
        isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        reduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
        boldTextEnabled = UIAccessibility.isBoldTextEnabled
        differentiateWithoutColor = UIAccessibility.shouldDifferentiateWithoutColor
    }
    
    // MARK: - Announcements
    
    /// Announce a message to VoiceOver users
    func announce(_ message: String, delay: TimeInterval = 0.1) {
        guard isVoiceOverRunning else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
    
    /// Announce screen change
    func announceScreenChange(_ message: String) {
        guard isVoiceOverRunning else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .screenChanged, argument: message)
        }
    }
    
    /// Announce layout change
    func announceLayoutChange(_ element: Any? = nil) {
        guard isVoiceOverRunning else { return }
        
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }
}

// MARK: - Accessibility Labels

/// Centralized accessibility labels for Collections feature
enum CollectionAccessibilityLabel {
    
    // MARK: - Collection Row
    
    static func collectionRow(
        title: String,
        creatorName: String,
        segmentCount: Int,
        duration: String,
        viewCount: Int,
        hypeCount: Int
    ) -> String {
        let segmentText = segmentCount == 1 ? "1 part" : "\(segmentCount) parts"
        return "\(title), by \(creatorName). \(segmentText), \(duration) total. \(formatCount(viewCount)) views, \(formatCount(hypeCount)) hypes."
    }
    
    static func collectionRowHint(isPublished: Bool) -> String {
        if isPublished {
            return "Double tap to play collection"
        } else {
            return "Double tap to edit draft"
        }
    }
    
    // MARK: - Segment Row
    
    static func segmentRow(
        partNumber: Int,
        title: String,
        duration: String,
        uploadStatus: SegmentUploadStatus?
    ) -> String {
        var label = "Part \(partNumber), \(title), \(duration)"
        
        if let status = uploadStatus {
            switch status {
            case .pending:
                label += ", pending upload"
            case .uploading:
                label += ", uploading"
            case .processing:
                label += ", processing"
            case .complete:
                label += ", uploaded"
            case .failed:
                label += ", upload failed"
            case .cancelled:
                label += ", cancelled"
            }
        }
        
        return label
    }
    
    // MARK: - Player Controls
    
    static func playPauseButton(isPlaying: Bool) -> String {
        isPlaying ? "Pause" : "Play"
    }
    
    static func playPauseHint(isPlaying: Bool) -> String {
        isPlaying ? "Double tap to pause video" : "Double tap to play video"
    }
    
    static func skipButton(direction: String, seconds: Int) -> String {
        "Skip \(direction) \(seconds) seconds"
    }
    
    static func previousSegmentButton(hasPrevious: Bool) -> String {
        hasPrevious ? "Go to previous segment" : "At first segment"
    }
    
    static func nextSegmentButton(hasNext: Bool) -> String {
        hasNext ? "Go to next segment" : "At last segment"
    }
    
    static func progressScrubber(currentTime: String, duration: String, progress: Double) -> String {
        let percent = Int(progress * 100)
        return "Progress: \(currentTime) of \(duration), \(percent) percent complete"
    }
    
    static func segmentIndicator(current: Int, total: Int) -> String {
        "Part \(current) of \(total)"
    }
    
    // MARK: - Upload Status
    
    static func uploadProgress(segmentNumber: Int, progress: Double) -> String {
        let percent = Int(progress * 100)
        return "Part \(segmentNumber) upload: \(percent) percent"
    }
    
    static func overallUploadProgress(uploaded: Int, total: Int, progress: Double) -> String {
        let percent = Int(progress * 100)
        return "\(uploaded) of \(total) segments uploaded, \(percent) percent complete"
    }
    
    // MARK: - Engagement
    
    static func engagementStats(views: Int, hypes: Int, cools: Int, replies: Int) -> String {
        return "\(formatCount(views)) views, \(formatCount(hypes)) hypes, \(formatCount(cools)) cools, \(formatCount(replies)) replies"
    }
    
    static func hypeButton(count: Int, hasHyped: Bool) -> String {
        if hasHyped {
            return "Hyped, \(formatCount(count)) total hypes"
        } else {
            return "Hype, \(formatCount(count)) hypes"
        }
    }
    
    static func coolButton(count: Int, hasCooled: Bool) -> String {
        if hasCooled {
            return "Cooled, \(formatCount(count)) total cools"
        } else {
            return "Cool, \(formatCount(count)) cools"
        }
    }
    
    // MARK: - Composer
    
    static func titleField(characterCount: Int, maxLength: Int) -> String {
        "Title, \(characterCount) of \(maxLength) characters"
    }
    
    static func descriptionField(characterCount: Int, maxLength: Int) -> String {
        "Description, \(characterCount) of \(maxLength) characters"
    }
    
    static func addSegmentButton(currentCount: Int, maxCount: Int) -> String {
        "Add segment, \(currentCount) of \(maxCount) added"
    }
    
    static func publishButton(canPublish: Bool, issues: [String]) -> String {
        if canPublish {
            return "Publish collection"
        } else {
            let issueText = issues.isEmpty ? "Requirements not met" : issues.first!
            return "Cannot publish: \(issueText)"
        }
    }
    
    // MARK: - Helpers
    
    private static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1f million", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1f thousand", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Accessibility View Modifiers

/// Collection row accessibility modifier
struct CollectionRowAccessibility: ViewModifier {
    let title: String
    let creatorName: String
    let segmentCount: Int
    let duration: String
    let viewCount: Int
    let hypeCount: Int
    let isPublished: Bool
    let onPlay: () -> Void
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CollectionAccessibilityLabel.collectionRow(
                title: title,
                creatorName: creatorName,
                segmentCount: segmentCount,
                duration: duration,
                viewCount: viewCount,
                hypeCount: hypeCount
            ))
            .accessibilityHint(CollectionAccessibilityLabel.collectionRowHint(isPublished: isPublished))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onPlay()
            }
    }
}

extension View {
    func collectionRowAccessibility(
        title: String,
        creatorName: String,
        segmentCount: Int,
        duration: String,
        viewCount: Int,
        hypeCount: Int,
        isPublished: Bool = true,
        onPlay: @escaping () -> Void
    ) -> some View {
        modifier(CollectionRowAccessibility(
            title: title,
            creatorName: creatorName,
            segmentCount: segmentCount,
            duration: duration,
            viewCount: viewCount,
            hypeCount: hypeCount,
            isPublished: isPublished,
            onPlay: onPlay
        ))
    }
}

/// Segment row accessibility modifier
struct SegmentRowAccessibility: ViewModifier {
    let partNumber: Int
    let title: String
    let duration: String
    let uploadStatus: SegmentUploadStatus?
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CollectionAccessibilityLabel.segmentRow(
                partNumber: partNumber,
                title: title,
                duration: duration,
                uploadStatus: uploadStatus
            ))
            .accessibilityHint("Double tap to select")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onSelect()
            }
            .accessibilityAction(named: "Delete") {
                onDelete?()
            }
    }
}

extension View {
    func segmentRowAccessibility(
        partNumber: Int,
        title: String,
        duration: String,
        uploadStatus: SegmentUploadStatus? = nil,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(SegmentRowAccessibility(
            partNumber: partNumber,
            title: title,
            duration: duration,
            uploadStatus: uploadStatus,
            onSelect: onSelect,
            onDelete: onDelete
        ))
    }
}

/// Player controls accessibility modifier
struct PlayerControlsAccessibility: ViewModifier {
    let isPlaying: Bool
    let currentTime: String
    let duration: String
    let progress: Double
    let currentSegment: Int
    let totalSegments: Int
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video player controls")
            .accessibilityValue(CollectionAccessibilityLabel.segmentIndicator(
                current: currentSegment,
                total: totalSegments
            ))
    }
}

extension View {
    func playerControlsAccessibility(
        isPlaying: Bool,
        currentTime: String,
        duration: String,
        progress: Double,
        currentSegment: Int,
        totalSegments: Int
    ) -> some View {
        modifier(PlayerControlsAccessibility(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            currentSegment: currentSegment,
            totalSegments: totalSegments
        ))
    }
}

// MARK: - Accessible Progress View

/// Progress indicator with proper accessibility
struct AccessibleProgressView: View {
    let progress: Double
    let label: String
    
    var body: some View {
        ProgressView(value: progress)
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Accessible Scrubber

/// Video scrubber with accessibility support
struct AccessibleScrubber: View {
    @Binding var progress: Double
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    
    private var currentTimeString: String {
        formatTime(progress * duration)
    }
    
    private var durationString: String {
        formatTime(duration)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                
                // Progress track
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress, height: 4)
                
                // Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 16 : 12, height: isDragging ? 16 : 12)
                    .offset(x: geometry.size.width * progress - 6)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newProgress = min(1, max(0, value.location.x / geometry.size.width))
                        progress = newProgress
                    }
                    .onEnded { value in
                        isDragging = false
                        let finalProgress = min(1, max(0, value.location.x / geometry.size.width))
                        onSeek(finalProgress * duration)
                    }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Video progress")
        .accessibilityValue(CollectionAccessibilityLabel.progressScrubber(
            currentTime: currentTimeString,
            duration: durationString,
            progress: progress
        ))
        .accessibilityAdjustableAction { direction in
            let step: Double = 0.05 // 5% increments
            switch direction {
            case .increment:
                let newProgress = min(1, progress + step)
                progress = newProgress
                onSeek(newProgress * duration)
            case .decrement:
                let newProgress = max(0, progress - step)
                progress = newProgress
                onSeek(newProgress * duration)
            @unknown default:
                break
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Reduced Motion Helpers

extension View {
    /// Apply animation only if reduce motion is disabled
    func animationIfAllowed<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReducedMotionAnimationModifier(animation: animation, value: value))
    }
    
    /// Apply transition only if reduce motion is disabled
    func transitionIfAllowed(_ transition: AnyTransition) -> some View {
        modifier(ReducedMotionTransitionModifier(transition: transition))
    }
}

struct ReducedMotionAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: value)
    }
}

struct ReducedMotionTransitionModifier: ViewModifier {
    let transition: AnyTransition
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .transition(reduceMotion ? .opacity : transition)
    }
}

// MARK: - Dynamic Type Support

extension View {
    /// Scale padding based on Dynamic Type
    func scaledPadding(_ edges: Edge.Set = .all, _ length: CGFloat = 16) -> some View {
        modifier(ScaledPaddingModifier(edges: edges, length: length))
    }
    
    /// Scale frame based on Dynamic Type
    func scaledFrame(minHeight: CGFloat) -> some View {
        modifier(ScaledFrameModifier(minHeight: minHeight))
    }
}

struct ScaledPaddingModifier: ViewModifier {
    let edges: Edge.Set
    let length: CGFloat
    
    @ScaledMetric var scaledLength: CGFloat
    
    init(edges: Edge.Set, length: CGFloat) {
        self.edges = edges
        self.length = length
        _scaledLength = ScaledMetric(wrappedValue: length)
    }
    
    func body(content: Content) -> some View {
        content.padding(edges, scaledLength)
    }
}

struct ScaledFrameModifier: ViewModifier {
    let minHeight: CGFloat
    
    @ScaledMetric var scaledHeight: CGFloat
    
    init(minHeight: CGFloat) {
        self.minHeight = minHeight
        _scaledHeight = ScaledMetric(wrappedValue: minHeight)
    }
    
    func body(content: Content) -> some View {
        content.frame(minHeight: scaledHeight)
    }
}

// MARK: - High Contrast Support

extension View {
    /// Adjust colors for high contrast mode
    func highContrastAware(normalColor: Color, highContrastColor: Color) -> some View {
        modifier(HighContrastColorModifier(normalColor: normalColor, highContrastColor: highContrastColor))
    }
}

struct HighContrastColorModifier: ViewModifier {
    let normalColor: Color
    let highContrastColor: Color
    
    @Environment(\.colorSchemeContrast) var contrast
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(contrast == .increased ? highContrastColor : normalColor)
    }
}

// MARK: - Focus Management

/// Manages focus for accessibility
class AccessibilityFocusManager: ObservableObject {
    @Published var focusedElement: AccessibilityFocusElement?
    
    enum AccessibilityFocusElement: Hashable {
        case playButton
        case scrubber
        case segmentList
        case titleField
        case publishButton
        case errorMessage
    }
    
    @MainActor func focusOn(_ element: AccessibilityFocusElement) {
        focusedElement = element
        
        // Announce focus change
        CollectionAccessibilityManager.shared.announceLayoutChange(nil)
    }
}
