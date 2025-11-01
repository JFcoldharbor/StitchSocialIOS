//
//  ProfileComponents.swift
//  CleanBeta
//
//  Layer 8: Views - Supporting UI Components for Instagram-Style Profile
//  Dependencies: SwiftUI, UIKit
//  Features: WaveShape, BlurView, Scroll tracking, Enhanced UI elements
//

import SwiftUI
import UIKit

// MARK: - Wave Shape for Liquid Effects

/// Custom shape for creating liquid wave animations in clout display
struct WaveShape: Shape {
    var waveHeight: CGFloat
    var waveLength: CGFloat
    var offset: CGFloat
    
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveWidth = rect.width
        let waveHeightValue = min(waveHeight, rect.height * 0.5)
        
        path.move(to: CGPoint(x: 0, y: rect.height))
        
        for x in stride(from: 0, through: waveWidth, by: 1) {
            let relativeX = x / waveLength
            let sine = sin(relativeX + offset * 0.01)
            let y = rect.height - (sine * waveHeightValue + waveHeightValue)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: waveWidth, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Blur View for Sticky Elements

/// UIKit blur effect wrapper for sticky tab bar backgrounds
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Scroll Tracking Components

/// Preference key for tracking scroll offset in profile view
struct MainScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Scroll direction tracking for sticky elements
enum ScrollDirection {
    case up, down, none
}

// MARK: - Enhanced Profile Image Component

/// Profile image with tier-colored border and liquid progress ring
struct EnhancedProfileImage: View {
    let imageURL: URL?
    let userInitials: String
    let tierColor: Color
    let liquidLevel: CGFloat
    let ringProgress: CGFloat
    let liquidWaveOffset: CGFloat
    let size: CGFloat
    
    init(
        imageURL: URL?,
        userInitials: String,
        tierColor: Color,
        liquidLevel: CGFloat = 0.5,
        ringProgress: CGFloat = 0.5,
        liquidWaveOffset: CGFloat = 0.0,
        size: CGFloat = 110
    ) {
        self.imageURL = imageURL
        self.userInitials = userInitials
        self.tierColor = tierColor
        self.liquidLevel = liquidLevel
        self.ringProgress = ringProgress
        self.liquidWaveOffset = liquidWaveOffset
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Main profile image
            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [tierColor.opacity(0.3), tierColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    
                    Text(userInitials)
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            
            // Liquid fill background (behind image)
            Circle()
                .fill(Color.black)
                .frame(width: size - 4, height: size - 4)
            
            // Animated liquid fill
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tierColor, .yellow, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size - 4, height: size - 4)
                .clipShape(
                    WaveShape(
                        waveHeight: 3,
                        waveLength: 20,
                        offset: liquidWaveOffset
                    )
                    .offset(y: (size - 4) * (1 - liquidLevel))
                )
            
            // Tier-colored border with progress ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [tierColor, .yellow, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: size, height: size)
                .shadow(color: tierColor.opacity(0.4), radius: 8, x: 0, y: 4)
            
            // Progress ring overlay
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    LinearGradient(
                        colors: [tierColor, .yellow, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size + 8, height: size + 8)
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Shimmer Effect Component

/// Shimmer overlay for progress bars and buttons
struct ShimmerOverlay: View {
    let shimmerOffset: CGFloat
    let cornerRadius: CGFloat
    
    init(shimmerOffset: CGFloat, cornerRadius: CGFloat = 4) {
        self.shimmerOffset = shimmerOffset
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.6), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .offset(x: shimmerOffset)
    }
}

// MARK: - Stacked Badge Component

/// Stacked badge display for achievements
struct StackedBadges: View {
    let badges: [BadgeInfo]
    let maxVisible: Int
    let onTap: () -> Void
    
    init(badges: [BadgeInfo] = [], maxVisible: Int = 3, onTap: @escaping () -> Void = {}) {
        self.badges = badges
        self.maxVisible = maxVisible
        self.onTap = onTap
    }
    
    var body: some View {
        ZStack {
            // Default badges if none provided
            if badges.isEmpty {
                defaultBadgeStack
            } else {
                userBadgeStack
            }
        }
        .onTapGesture {
            onTap()
        }
    }
    
    private var defaultBadgeStack: some View {
        ZStack {
            // Badge 3 (back)
            BadgeCircle(
                gradient: [.blue, .purple],
                icon: "star.fill",
                offset: CGSize(width: 16, height: 16)
            )
            
            // Badge 2 (middle)
            BadgeCircle(
                gradient: [.cyan, .blue],
                icon: "checkmark",
                offset: CGSize(width: 8, height: 8)
            )
            
            // Badge 1 (front)
            BadgeCircle(
                gradient: [.yellow, .orange],
                icon: "crown.fill",
                offset: .zero
            )
        }
    }
    
    private var userBadgeStack: some View {
        ZStack {
            ForEach(Array(badges.prefix(maxVisible).enumerated()), id: \.offset) { index, badge in
                BadgeCircle(
                    gradient: badge.colors,
                    icon: badge.iconName,
                    offset: CGSize(width: CGFloat(index * 8), height: CGFloat(index * 8))
                )
                .zIndex(Double(maxVisible - index))
            }
        }
    }
}

// MARK: - Individual Badge Circle

struct BadgeCircle: View {
    let gradient: [Color]
    let icon: String
    let offset: CGSize
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .bold))
            )
            .offset(offset)
            .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
    }
}

// MARK: - Glass Morphism Button

/// Sleek action button with glass morphism effect
struct GlassMorphismButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Enhanced Hype Rating Bar

/// Hype rating bar with gradient and shimmer effects
struct EnhancedHypeBar: View {
    let rating: Double
    let shimmerOffset: CGFloat
    let progress: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    
                    Text("Hype Rating")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(rating))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Enhanced progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: geometry.size.width, height: 6)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            ShimmerOverlay(shimmerOffset: shimmerOffset, cornerRadius: 4)
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Supporting Data Structures

/// Badge information for stacked display
struct BadgeInfo {
    let id: String
    let iconName: String
    let colors: [Color]
    let title: String
    
    static let sample = [
        BadgeInfo(id: "1", iconName: "crown.fill", colors: [.yellow, .orange], title: "Founder"),
        BadgeInfo(id: "2", iconName: "checkmark", colors: [.cyan, .blue], title: "Verified"),
        BadgeInfo(id: "3", iconName: "star.fill", colors: [.blue, .purple], title: "Rising Star")
    ]
}

// MARK: - Utility Extensions

extension Color {
    /// Gold color for special tiers
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
    
    /// Convert UserTier to display color
    static func tierColor(for tier: UserTier) -> Color {
        switch tier {
        case .rookie: return .green
        case .rising: return .blue
        case .veteran: return .gray
        case .influencer: return .purple
        case .ambassador: return .indigo      // Single color, not array
        case .elite: return .purple
        case .partner: return .orange
        case .legendary: return .red
        case .topCreator: return .yellow
        case .founder: return .gold
        case .coFounder: return .gold
        }
    }
}
