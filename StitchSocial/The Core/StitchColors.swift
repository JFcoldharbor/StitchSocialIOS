//
//  StitchColors.swift
//  CleanBeta
//
//  Created by James Garmon on 7/11/25.
//


//
//  StitchColors.swift
//  CleanBeta
//
//  Foundation layer - Zero dependencies
//  All color constants and theme definitions used throughout the app
//

import Foundation
import SwiftUI

/// Centralized color system for CleanBeta app
struct StitchColors {
    
    // MARK: - Brand Colors
    
    /// Primary brand color - Main accent color
    static let primary = Color(red: 0.2, green: 0.6, blue: 1.0) // Bright blue
    
    /// Secondary brand color - Supporting accent
    static let secondary = Color(red: 0.8, green: 0.2, blue: 0.6) // Hot pink
    
    /// Tertiary brand color - Subtle accent
    static let tertiary = Color(red: 0.4, green: 0.8, blue: 0.6) // Mint green
    
    /// Brand gradient colors
    static let gradientStart = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let gradientEnd = Color(red: 0.6, green: 0.2, blue: 1.0)
    
    // MARK: - Background Colors
    
    /// Primary background (dark mode friendly)
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
    
    /// Secondary background (cards, overlays)
    static let backgroundSecondary = Color(red: 0.1, green: 0.1, blue: 0.15)
    
    /// Tertiary background (subtle sections)
    static let backgroundTertiary = Color(red: 0.15, green: 0.15, blue: 0.2)
    
    /// Surface color (elevated elements)
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.18)
    
    /// Card background
    static let cardBackground = Color(red: 0.08, green: 0.08, blue: 0.12)
    
    // MARK: - Text Colors
    
    /// Primary text color
    static let textPrimary = Color.white
    
    /// Secondary text color (dimmed)
    static let textSecondary = Color(red: 0.7, green: 0.7, blue: 0.75)
    
    /// Tertiary text color (very dimmed)
    static let textTertiary = Color(red: 0.5, green: 0.5, blue: 0.55)
    
    /// Placeholder text
    static let textPlaceholder = Color(red: 0.4, green: 0.4, blue: 0.45)
    
    /// Disabled text
    static let textDisabled = Color(red: 0.3, green: 0.3, blue: 0.35)
    
    // MARK: - Interaction Colors
    
    /// Hype interaction color (like/upvote)
    static let hype = Color(red: 1.0, green: 0.3, blue: 0.3) // Red
    
    /// Cool interaction color (dislike/downvote)
    static let cool = Color(red: 0.3, green: 0.5, blue: 1.0) // Blue
    
    /// Reply interaction color
    static let reply = Color(red: 0.4, green: 0.8, blue: 0.4) // Green
    
    /// Share interaction color
    static let share = Color(red: 1.0, green: 0.7, blue: 0.2) // Orange
    
    /// View/play interaction color
    static let view = Color(red: 0.6, green: 0.6, blue: 0.6) // Gray
    
    // MARK: - User Tier Colors
    
    /// Rookie tier color
    static let tierRookie = Color(red: 0.6, green: 0.6, blue: 0.6) // Gray
    
    /// Rising tier color
    static let tierRising = Color(red: 0.4, green: 0.8, blue: 0.4) // Green
    
    /// Influencer tier color
    static let tierInfluencer = Color(red: 0.2, green: 0.6, blue: 1.0) // Blue
    
    /// Partner tier color
    static let tierPartner = Color(red: 0.8, green: 0.2, blue: 0.8) // Purple
    
    /// Top Creator tier color
    static let tierTopCreator = Color(red: 1.0, green: 0.6, blue: 0.2) // Orange
    
    /// Founder tier color
    static let tierFounder = Color(red: 1.0, green: 0.8, blue: 0.2) // Gold
    
    /// Co-Founder tier color
    static let tierCoFounder = Color(red: 0.9, green: 0.7, blue: 0.3) // Light Gold
    
    // MARK: - Temperature Colors
    
    /// Frozen temperature
    static let temperatureFrozen = Color(red: 0.4, green: 0.7, blue: 1.0) // Ice blue
    
    /// Cold temperature
    static let temperatureCold = Color(red: 0.5, green: 0.8, blue: 0.9) // Light blue
    
    /// Cool temperature
    static let temperatureCool = Color(red: 0.3, green: 0.8, blue: 0.6) // Teal
    
    /// Warm temperature
    static let temperatureWarm = Color(red: 1.0, green: 0.8, blue: 0.2) // Yellow
    
    /// Hot temperature
    static let temperatureHot = Color(red: 1.0, green: 0.5, blue: 0.2) // Orange
    
    /// Blazing temperature
    static let temperatureBlazing = Color(red: 1.0, green: 0.2, blue: 0.2) // Red
    
    // MARK: - Status Colors
    
    /// Success color
    static let success = Color(red: 0.2, green: 0.8, blue: 0.4) // Green
    
    /// Warning color
    static let warning = Color(red: 1.0, green: 0.7, blue: 0.2) // Orange
    
    /// Error color
    static let error = Color(red: 1.0, green: 0.3, blue: 0.3) // Red
    
    /// Info color
    static let info = Color(red: 0.3, green: 0.6, blue: 1.0) // Blue
    
    // MARK: - UI Element Colors
    
    /// Border color (subtle)
    static let border = Color(red: 0.2, green: 0.2, blue: 0.25)
    
    /// Separator color
    static let separator = Color(red: 0.15, green: 0.15, blue: 0.2)
    
    /// Shadow color
    static let shadow = Color.black.opacity(0.3)
    
    /// Overlay color (for modals, alerts)
    static let overlay = Color.black.opacity(0.6)
    
    /// Selection color
    static let selection = primary.opacity(0.2)
    
    /// Hover color
    static let hover = Color.white.opacity(0.1)
    
    // MARK: - Recording Colors
    
    /// Recording active color
    static let recordingActive = Color(red: 1.0, green: 0.2, blue: 0.2) // Red
    
    /// Recording paused color
    static let recordingPaused = Color(red: 1.0, green: 0.7, blue: 0.2) // Orange
    
    /// Recording processing color
    static let recordingProcessing = Color(red: 0.2, green: 0.6, blue: 1.0) // Blue
    
    /// Recording complete color
    static let recordingComplete = Color(red: 0.2, green: 0.8, blue: 0.4) // Green
    
    // MARK: - Tab Bar Colors
    
    /// Tab bar background
    static let tabBarBackground = Color(red: 0.05, green: 0.05, blue: 0.08).opacity(0.9)
    
    /// Tab bar selected color
    static let tabBarSelected = primary
    
    /// Tab bar unselected color
    static let tabBarUnselected = Color(red: 0.5, green: 0.5, blue: 0.55)
    
    // MARK: - Badge Colors
    
    /// Crown badge color
    static let badgeCrown = Color(red: 1.0, green: 0.8, blue: 0.2) // Gold
    
    /// Achievement badge color
    static let badgeAchievement = Color(red: 0.6, green: 0.4, blue: 1.0) // Purple
    
    /// Verified badge color
    static let badgeVerified = Color(red: 0.2, green: 0.6, blue: 1.0) // Blue
    
    /// Early adopter badge color
    static let badgeEarlyAdopter = Color(red: 0.8, green: 0.2, blue: 0.6) // Pink
}

// MARK: - Color Extensions

extension StitchColors {
    
    /// Returns appropriate tier color for given user tier
    static func colorForTier(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "rookie": return tierRookie
        case "rising": return tierRising
        case "influencer": return tierInfluencer
        case "partner": return tierPartner
        case "top_creator", "topcreator": return tierTopCreator
        case "founder": return tierFounder
        case "co_founder", "cofounder": return tierCoFounder
        default: return tierRookie
        }
    }
    
    /// Returns appropriate temperature color
    static func colorForTemperature(_ temperature: String) -> Color {
        switch temperature.lowercased() {
        case "frozen": return temperatureFrozen
        case "cold": return temperatureCold
        case "cool": return temperatureCool
        case "warm": return temperatureWarm
        case "hot": return temperatureHot
        case "blazing", "fire": return temperatureBlazing
        default: return temperatureWarm
        }
    }
    
    /// Returns appropriate interaction color
    static func colorForInteraction(_ interaction: String) -> Color {
        switch interaction.lowercased() {
        case "hype": return hype
        case "cool": return cool
        case "reply": return reply
        case "share": return share
        case "view": return view
        default: return textSecondary
        }
    }
    
    /// Returns appropriate recording state color
    static func colorForRecordingState(_ state: String) -> Color {
        switch state.lowercased() {
        case "recording": return recordingActive
        case "paused": return recordingPaused
        case "processing": return recordingProcessing
        case "complete": return recordingComplete
        case "error": return error
        default: return textSecondary
        }
    }
}

// MARK: - Gradients

extension StitchColors {
    
    /// Primary brand gradient
    static let primaryGradient = LinearGradient(
        colors: [gradientStart, gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Background gradient
    static let backgroundGradient = LinearGradient(
        colors: [background, backgroundSecondary],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Card gradient
    static let cardGradient = LinearGradient(
        colors: [cardBackground, surface],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Hype gradient
    static let hypeGradient = LinearGradient(
        colors: [hype, hype.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Cool gradient
    static let coolGradient = LinearGradient(
        colors: [cool, cool.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Temperature gradient (cold to hot)
    static let temperatureGradient = LinearGradient(
        colors: [temperatureFrozen, temperatureCool, temperatureWarm, temperatureHot, temperatureBlazing],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Dark/Light Mode Support

extension StitchColors {
    
    /// Adaptive background color that responds to color scheme
    static func adaptiveBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return background
        case .light:
            return Color(red: 0.95, green: 0.95, blue: 0.97)
        @unknown default:
            return background
        }
    }
    
    /// Adaptive text color that responds to color scheme
    static func adaptiveTextPrimary(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return textPrimary
        case .light:
            return Color(red: 0.1, green: 0.1, blue: 0.15)
        @unknown default:
            return textPrimary
        }
    }
    
    /// Adaptive surface color that responds to color scheme
    static func adaptiveSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return surface
        case .light:
            return Color.white
        @unknown default:
            return surface
        }
    }
}

// MARK: - Accessibility Support

extension StitchColors {
    
    /// High contrast version of primary color for accessibility
    static let primaryHighContrast = Color(red: 0.0, green: 0.4, blue: 0.8)
    
    /// High contrast version of secondary color for accessibility
    static let secondaryHighContrast = Color(red: 0.6, green: 0.0, blue: 0.4)
    
    /// Returns appropriate color with increased contrast if needed
    static func accessibleColor(_ baseColor: Color, highContrast: Bool = false) -> Color {
        if highContrast {
            // Return higher contrast version
            if baseColor == primary { return primaryHighContrast }
            if baseColor == secondary { return secondaryHighContrast }
        }
        return baseColor
    }
}