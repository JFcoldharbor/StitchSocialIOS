//
//  OrbitalLayoutCalculator.swift
//  StitchSocial
//
//  Layer 5: Business Logic - Orbital Positioning for Spatial Thread Interface
//  Dependencies: Foundation, CoreGraphics (Layer 1)
//  Features: 3-ring orbital layout, dynamic positioning, smooth animations
//  ARCHITECTURE COMPLIANT: Pure functions only, no UI dependencies
//

import Foundation
import CoreGraphics

/// Pure function calculator for orbital positioning in spatial thread interface
struct OrbitalLayoutCalculator {
    
    // MARK: - Layout Constants
    
    /// Ring configuration for 50 children maximum
    private static let ringConfiguration = RingConfiguration(
        innerRing: RingSpec(radius: 100, childrenCount: 12),
        middleRing: RingSpec(radius: 150, childrenCount: 18),
        outerRing: RingSpec(radius: 200, childrenCount: 20)
    )
    
    /// Maximum children per page to maintain 60fps performance
    static let maxChildrenPerPage = 50
    
    // MARK: - Public Interface
    
    /// Calculate positions for all children in orbital layout
    static func calculateOrbitalPositions(
        for children: [ChildThreadData],
        containerSize: CGSize,
        currentPage: Int = 0
    ) -> [OrbitalPosition] {
        
        let pageChildren = getChildrenForPage(children, page: currentPage)
        let centerPoint = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        
        var positions: [OrbitalPosition] = []
        var childIndex = 0
        
        // Inner Ring (12 children)
        for i in 0..<min(pageChildren.count, ringConfiguration.innerRing.childrenCount) {
            let position = calculateRingPosition(
                index: i,
                ringSpec: ringConfiguration.innerRing,
                centerPoint: centerPoint,
                childData: pageChildren[childIndex]
            )
            positions.append(position)
            childIndex += 1
        }
        
        // Middle Ring (18 children)
        if childIndex < pageChildren.count {
            for i in 0..<min(pageChildren.count - childIndex, ringConfiguration.middleRing.childrenCount) {
                let position = calculateRingPosition(
                    index: i,
                    ringSpec: ringConfiguration.middleRing,
                    centerPoint: centerPoint,
                    childData: pageChildren[childIndex]
                )
                positions.append(position)
                childIndex += 1
            }
        }
        
        // Outer Ring (20 children)
        if childIndex < pageChildren.count {
            for i in 0..<min(pageChildren.count - childIndex, ringConfiguration.outerRing.childrenCount) {
                let position = calculateRingPosition(
                    index: i,
                    ringSpec: ringConfiguration.outerRing,
                    centerPoint: centerPoint,
                    childData: pageChildren[childIndex]
                )
                positions.append(position)
                childIndex += 1
            }
        }
        
        return positions
    }
    
    /// Calculate total pages needed for thread children
    static func calculateTotalPages(for childrenCount: Int) -> Int {
        return max(1, Int(ceil(Double(childrenCount) / Double(maxChildrenPerPage))))
    }
    
    /// Check if page navigation is needed
    static func needsPagination(for childrenCount: Int) -> Bool {
        return childrenCount > maxChildrenPerPage
    }
    
    /// Get center position for parent thread
    static func getCenterPosition(containerSize: CGSize) -> CGPoint {
        return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
    }
    
    // MARK: - Ring Position Calculation
    
    private static func calculateRingPosition(
        index: Int,
        ringSpec: RingSpec,
        centerPoint: CGPoint,
        childData: ChildThreadData
    ) -> OrbitalPosition {
        
        // Calculate angle for even distribution
        let angleStep = (2 * Double.pi) / Double(ringSpec.childrenCount)
        let angle = angleStep * Double(index)
        
        // Calculate position using trigonometry
        let x = centerPoint.x + CGFloat(cos(angle)) * ringSpec.radius
        let y = centerPoint.y + CGFloat(sin(angle)) * ringSpec.radius
        
        // Determine visual state based on engagement and interaction limits
        let visualState = determineVisualState(for: childData)
        
        return OrbitalPosition(
            childID: childData.id,
            position: CGPoint(x: x, y: y),
            radius: ringSpec.radius,
            angle: angle,
            ringType: getRingType(for: ringSpec.radius),
            visualState: visualState,
            stepchildCount: childData.stepchildCount,
            interactionCount: childData.interactionCount
        )
    }
    
    // MARK: - Visual State Determination
    
    private static func determineVisualState(for child: ChildThreadData) -> OrbitalVisualState {
        let interactionLimit = 20 // Child interaction limit
        let interactionRatio = Double(child.interactionCount) / Double(interactionLimit)
        
        // Check for max interactions reached
        if child.interactionCount >= interactionLimit {
            return .maxInteractions
        }
        
        // Check for high engagement
        if interactionRatio >= 0.7 {
            return .highEngagement
        }
        
        // Check stepchild count for visual indicators
        if child.stepchildCount >= 6 {
            return .highActivity
        }
        
        return .normal
    }
    
    // MARK: - Utility Functions
    
    private static func getChildrenForPage(_ children: [ChildThreadData], page: Int) -> [ChildThreadData] {
        let startIndex = page * maxChildrenPerPage
        let endIndex = min(startIndex + maxChildrenPerPage, children.count)
        
        guard startIndex < children.count else { return [] }
        
        return Array(children[startIndex..<endIndex])
    }
    
    private static func getRingType(for radius: CGFloat) -> RingType {
        switch radius {
        case ringConfiguration.innerRing.radius:
            return .inner
        case ringConfiguration.middleRing.radius:
            return .middle
        case ringConfiguration.outerRing.radius:
            return .outer
        default:
            return .middle
        }
    }
}

// MARK: - Supporting Types

/// Configuration for the three orbital rings
private struct RingConfiguration {
    let innerRing: RingSpec
    let middleRing: RingSpec
    let outerRing: RingSpec
}

/// Specification for individual ring properties
private struct RingSpec {
    let radius: CGFloat
    let childrenCount: Int
}

/// Calculated position for a child in orbital layout
struct OrbitalPosition {
    let childID: String
    let position: CGPoint
    let radius: CGFloat
    let angle: Double
    let ringType: RingType
    let visualState: OrbitalVisualState
    let stepchildCount: Int
    let interactionCount: Int
}

/// Ring type for orbital positioning
enum RingType {
    case inner
    case middle
    case outer
    
    var maxChildren: Int {
        switch self {
        case .inner: return 12
        case .middle: return 18
        case .outer: return 20
        }
    }
}

/// Visual state for orbital child circles
enum OrbitalVisualState {
    case normal
    case highEngagement
    case highActivity
    case maxInteractions
    
    var circleSize: CGFloat {
        switch self {
        case .normal, .maxInteractions: return 16
        case .highEngagement: return 18
        case .highActivity: return 17
        }
    }
    
    var borderColor: String {
        switch self {
        case .normal: return "cyan"
        case .highEngagement: return "yellow"
        case .highActivity: return "orange"
        case .maxInteractions: return "red"
        }
    }
    
    var showsBadge: Bool {
        return self == .maxInteractions
    }
}

/// Data structure for child thread information
struct ChildThreadData {
    let id: String
    let creatorName: String
    let stepchildCount: Int
    let interactionCount: Int
    let engagementScore: Double
    let thumbnailURL: String?
    
    init(from video: CoreVideoMetadata) {
        self.id = video.id
        self.creatorName = video.creatorName
        self.stepchildCount = video.replyCount // Use replyCount for stepchildren count
        self.interactionCount = video.hypeCount + video.coolCount
        self.engagementScore = Double(video.hypeCount) / max(1.0, Double(video.viewCount))
        self.thumbnailURL = video.thumbnailURL
    }
}

// MARK: - Animation Support

extension OrbitalLayoutCalculator {
    
    /// Calculate smooth transition between orbital positions
    static func calculateTransition(
        from oldPositions: [OrbitalPosition],
        to newPositions: [OrbitalPosition],
        progress: Double
    ) -> [OrbitalPosition] {
        
        var transitionPositions: [OrbitalPosition] = []
        
        for newPos in newPositions {
            if let oldPos = oldPositions.first(where: { $0.childID == newPos.childID }) {
                // Interpolate between old and new positions
                let interpolatedX = oldPos.position.x + (newPos.position.x - oldPos.position.x) * CGFloat(progress)
                let interpolatedY = oldPos.position.y + (newPos.position.y - oldPos.position.y) * CGFloat(progress)
                
                let transitionPos = OrbitalPosition(
                    childID: newPos.childID,
                    position: CGPoint(x: interpolatedX, y: interpolatedY),
                    radius: newPos.radius,
                    angle: newPos.angle,
                    ringType: newPos.ringType,
                    visualState: newPos.visualState,
                    stepchildCount: newPos.stepchildCount,
                    interactionCount: newPos.interactionCount
                )
                
                transitionPositions.append(transitionPos)
            } else {
                // New position - start from center and animate out
                let centerX = newPos.position.x + (0 - newPos.position.x) * CGFloat(1 - progress)
                let centerY = newPos.position.y + (0 - newPos.position.y) * CGFloat(1 - progress)
                
                let transitionPos = OrbitalPosition(
                    childID: newPos.childID,
                    position: CGPoint(x: centerX, y: centerY),
                    radius: newPos.radius,
                    angle: newPos.angle,
                    ringType: newPos.ringType,
                    visualState: newPos.visualState,
                    stepchildCount: newPos.stepchildCount,
                    interactionCount: newPos.interactionCount
                )
                
                transitionPositions.append(transitionPos)
            }
        }
        
        return transitionPositions
    }
}
