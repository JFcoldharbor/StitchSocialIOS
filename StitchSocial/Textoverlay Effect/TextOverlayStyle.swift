//
//  TextOverlayModel.swift
//  StitchSocial
//
//  CACHING: No network reads. All state in-memory during review.
//  Export renders CALayers once per export.

import Foundation
import UIKit
import SwiftUI

// MARK: - System Font Catalogue

enum OverlayFont: String, CaseIterable, Codable {
    case defaultSans   = "Default"
    case futura        = "Futura"
    case georgia       = "Georgia"
    case helvetica     = "Helvetica"
    case avenir        = "Avenir"
    case didot         = "Didot"
    case typewriter    = "Typewriter"
    case chalkduster   = "Chalkduster"
    case gillSans      = "Gill Sans"
    case rockwell      = "Rockwell"
    case baskerville   = "Baskerville"

    /// Actual PostScript font name passed to UIFont/CTFont
    var postScriptName: String {
        switch self {
        case .defaultSans:  return "HelveticaNeue"
        case .futura:       return "Futura-Bold"
        case .georgia:      return "Georgia"
        case .helvetica:    return "Helvetica Neue"
        case .avenir:       return "AvenirNext-Bold"
        case .didot:        return "Didot"
        case .typewriter:   return "AmericanTypewriter"
        case .chalkduster:  return "Chalkduster"
        case .gillSans:     return "GillSans-Bold"
        case .rockwell:     return "Rockwell"
        case .baskerville:  return "Baskerville-Bold"
        }
    }

    /// Short label shown in picker
    var label: String { rawValue }

    /// SwiftUI Font for live preview
    func swiftUIFont(size: CGFloat, bold: Bool) -> Font {
        switch self {
        case .defaultSans:
            return .system(size: size, weight: bold ? .bold : .semibold, design: .default)
        case .typewriter:
            return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
        default:
            return .custom(postScriptName, size: size)
        }
    }
}

// MARK: - Typography Style

enum TextOverlayStyle: String, CaseIterable, Codable {
    case boldPill   = "Bold Pill"
    case outline    = "Outline"
    case neon       = "Neon"
    case typewriter = "Typewriter"
    case gradient   = "Gradient"

    var defaultBgColor: UIColor {
        switch self {
        case .boldPill:   return .white
        case .outline:    return .clear
        case .neon:       return UIColor.black.withAlphaComponent(0.5)
        case .typewriter: return UIColor.black.withAlphaComponent(0.75)
        case .gradient:   return .clear
        }
    }

    var defaultTextColor: UIColor {
        switch self {
        case .boldPill:   return .black
        case .outline:    return .white
        case .neon:       return .cyan
        case .typewriter: return .white
        case .gradient:   return .white
        }
    }

    /// Suggested font per style
    var defaultFont: OverlayFont {
        switch self {
        case .boldPill:   return .futura
        case .outline:    return .defaultSans
        case .neon:       return .avenir
        case .typewriter: return .typewriter
        case .gradient:   return .didot
        }
    }
}

// MARK: - Preset Palettes

struct TextOverlayPalette {
    static let bgColors: [Color] = [
        .white, .black, .red, .orange, .yellow,
        .green, .cyan, .blue, .purple, .pink,
        Color(white: 0, opacity: 0.6)
    ]
    static let textColors: [Color] = [
        .white, .black, .red, .orange, .yellow,
        .green, .cyan, .blue, .purple, .pink
    ]
}

// MARK: - Text Overlay Model

struct TextOverlay: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var style: TextOverlayStyle
    var font: OverlayFont = .defaultSans
    var fontSize: CGFloat = 28
    var isBold: Bool = true

    // RGBA components for Codable
    var textColorRed: Double = 1; var textColorGreen: Double = 1
    var textColorBlue: Double = 1; var textColorAlpha: Double = 1
    var bgColorRed: Double = 1;   var bgColorGreen: Double = 1
    var bgColorBlue: Double = 1;  var bgColorAlpha: Double = 1

    // Position as fraction of video (0…1)
    var normalizedX: CGFloat = 0.5
    var normalizedY: CGFloat = 0.5
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0

    // Time range (nil = full duration)
    var startTime: TimeInterval? = nil
    var endTime: TimeInterval?   = nil

    var textColor: UIColor {
        UIColor(red: textColorRed, green: textColorGreen,
                blue: textColorBlue, alpha: textColorAlpha)
    }
    var bgColor: UIColor {
        UIColor(red: bgColorRed, green: bgColorGreen,
                blue: bgColorBlue, alpha: bgColorAlpha)
    }

    mutating func setTextColor(_ c: Color) {
        let ui = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        textColorRed = r; textColorGreen = g; textColorBlue = b; textColorAlpha = a
    }
    mutating func setBgColor(_ c: Color) {
        let ui = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        bgColorRed = r; bgColorGreen = g; bgColorBlue = b; bgColorAlpha = a
    }

    /// Apply a style and reset font/colors to that style's defaults
    mutating func applyStyle(_ s: TextOverlayStyle) {
        style = s
        font = s.defaultFont
        setTextColor(Color(s.defaultTextColor))
        setBgColor(Color(s.defaultBgColor))
    }
}
