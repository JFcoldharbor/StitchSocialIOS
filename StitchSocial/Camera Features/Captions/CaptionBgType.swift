//
//  CaptionBgType.swift
//  StitchSocial
//
//  Created by James Garmon on 4/11/26.
//


//
//  CaptionStylePreset.swift
//  StitchSocial
//
//  CapCut-style caption style presets.
//  Each preset is a one-tap combination of font, color, background, stroke.
//  Used by CaptionOverlayView (live preview) and buildCaptionLayer (export burn-in).
//
//  CACHING: Presets are value types, computed once per render — no caching needed.

import SwiftUI
import UIKit

// MARK: - Background Type

enum CaptionBgType: String, Codable {
    case none
    case pill           // rounded pill behind text
    case fullBar        // full-width bar edge-to-edge
    case highlightWord  // word-by-word fill (karaoke)
    case outline        // stroke around text, no fill
    case blur           // blurred bg under text
}

// MARK: - Caption Safe Zone
// Keeps captions from overlapping ContextualVideoOverlay metadata.
// Bottom metadata sits ~28% from bottom. Top status bar ~10%.

struct CaptionSafeZone {
    static let topMin: CGFloat    = 0.12   // below status bar
    static let topPreferred: CGFloat  = 0.15
    static let centerPreferred: CGFloat = 0.50
    static let bottomPreferred: CGFloat = 0.68   // above metadata overlay
    static let bottomMax: CGFloat = 0.72   // hard limit
}

extension CaptionPosition {
    /// Safe Y offset — won't overlap UI chrome or metadata overlay
    var safeOffset: CGFloat {
        switch self {
        case .top:    return CaptionSafeZone.topPreferred
        case .center: return CaptionSafeZone.centerPreferred
        case .bottom: return CaptionSafeZone.bottomPreferred
        }
    }
}

// MARK: - Caption Style Preset

struct CaptionStylePreset: Identifiable, Codable, Equatable {
    var id: String          // matches name, used for Codable persistence
    var name: String

    // Typography
    var fontName: String    // UIFont name
    var fontSize: CGFloat
    var isBold: Bool
    var isItalic: Bool

    // Text
    var textColorR: Double; var textColorG: Double
    var textColorB: Double; var textColorA: Double

    // Background
    var bgType: CaptionBgType
    var bgColorR: Double;  var bgColorG: Double
    var bgColorB: Double;  var bgColorA: Double

    // Stroke
    var strokeWidth: CGFloat
    var strokeColorR: Double; var strokeColorG: Double
    var strokeColorB: Double; var strokeColorA: Double

    // Computed helpers
    var textUIColor: UIColor {
        UIColor(red: textColorR, green: textColorG, blue: textColorB, alpha: textColorA)
    }
    var bgUIColor: UIColor {
        UIColor(red: bgColorR, green: bgColorG, blue: bgColorB, alpha: bgColorA)
    }
    var strokeUIColor: UIColor {
        UIColor(red: strokeColorR, green: strokeColorG, blue: strokeColorB, alpha: strokeColorA)
    }
    var textSwiftUIColor: Color { Color(textUIColor) }
    var bgSwiftUIColor: Color   { Color(bgUIColor) }

    var uiFont: UIFont {
        UIFont(name: fontName, size: fontSize) ??
        UIFont.systemFont(ofSize: fontSize, weight: isBold ? .bold : .regular)
    }
    var swiftUIFont: Font {
        Font.custom(fontName, size: fontSize).weight(isBold ? .bold : .regular)
    }
}

// MARK: - Preset Library

extension CaptionStylePreset {

    static let all: [CaptionStylePreset] = [
        classic, subtitle, boldWhite, instaBoldStacked,
        neonCyan, neonPink, fire, ice,
        typewriter, outlined, cinema, retro,
        minimal, gradient, pop, karaoke
    ]

    // ── Classic ─────────────────────────────────────────────────────────────
    static let classic = CaptionStylePreset(
        id: "classic", name: "Classic",
        fontName: "HelveticaNeue-Bold", fontSize: 22, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .pill,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0.6,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Subtitle ─────────────────────────────────────────────────────────────
    static let subtitle = CaptionStylePreset(
        id: "subtitle", name: "Subtitle",
        fontName: "HelveticaNeue", fontSize: 20, isBold: false, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .none,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 2,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0.9
    )

    // ── Bold White ───────────────────────────────────────────────────────────
    static let boldWhite = CaptionStylePreset(
        id: "boldwhite", name: "Bold",
        fontName: "Futura-Bold", fontSize: 26, isBold: true, isItalic: false,
        textColorR: 0, textColorG: 0, textColorB: 0, textColorA: 1,
        bgType: .pill,
        bgColorR: 1, bgColorG: 1, bgColorB: 1, bgColorA: 1,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Instagram Bold Stacked ───────────────────────────────────────────────
    // Bold uppercase, word-highlighted yellow background, white text
    static let instaBoldStacked = CaptionStylePreset(
        id: "instabold", name: "Insta Bold",
        fontName: "Futura-CondensedExtraBold", fontSize: 30, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .highlightWord,
        bgColorR: 1, bgColorG: 0.85, bgColorB: 0, bgColorA: 1,    // yellow
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Neon Cyan ───────────────────────────────────────────────────────────
    static let neonCyan = CaptionStylePreset(
        id: "neoncyan", name: "Neon",
        fontName: "AvenirNext-Bold", fontSize: 24, isBold: true, isItalic: false,
        textColorR: 0, textColorG: 1, textColorB: 0.9, textColorA: 1,
        bgType: .pill,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0.55,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 1, strokeColorB: 0.9, strokeColorA: 0.7
    )

    // ── Neon Pink ───────────────────────────────────────────────────────────
    static let neonPink = CaptionStylePreset(
        id: "neonpink", name: "Neon Pink",
        fontName: "AvenirNext-Bold", fontSize: 24, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 0.2, textColorB: 0.6, textColorA: 1,
        bgType: .pill,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0.55,
        strokeWidth: 0,
        strokeColorR: 1, strokeColorG: 0.2, strokeColorB: 0.6, strokeColorA: 0.7
    )

    // ── Fire ────────────────────────────────────────────────────────────────
    static let fire = CaptionStylePreset(
        id: "fire", name: "Fire",
        fontName: "Futura-Bold", fontSize: 26, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 0.4, textColorB: 0, textColorA: 1,
        bgType: .none,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 2.5,
        strokeColorR: 1, strokeColorG: 0.8, strokeColorB: 0, strokeColorA: 1
    )

    // ── Ice ─────────────────────────────────────────────────────────────────
    static let ice = CaptionStylePreset(
        id: "ice", name: "Ice",
        fontName: "AvenirNext-UltraLight", fontSize: 24, isBold: false, isItalic: false,
        textColorR: 0.7, textColorG: 0.95, textColorB: 1, textColorA: 1,
        bgType: .blur,
        bgColorR: 0.6, bgColorG: 0.9, bgColorB: 1, bgColorA: 0.15,
        strokeWidth: 0,
        strokeColorR: 1, strokeColorG: 1, strokeColorB: 1, strokeColorA: 0.3
    )

    // ── Typewriter ──────────────────────────────────────────────────────────
    static let typewriter = CaptionStylePreset(
        id: "typewriter", name: "Type",
        fontName: "Courier-Bold", fontSize: 20, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .fullBar,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0.8,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Outlined ────────────────────────────────────────────────────────────
    static let outlined = CaptionStylePreset(
        id: "outlined", name: "Outline",
        fontName: "HelveticaNeue-Bold", fontSize: 26, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .outline,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 3,
        strokeColorR: 1, strokeColorG: 1, strokeColorB: 1, strokeColorA: 1
    )

    // ── Cinema ──────────────────────────────────────────────────────────────
    static let cinema = CaptionStylePreset(
        id: "cinema", name: "Cinema",
        fontName: "HelveticaNeue", fontSize: 18, isBold: false, isItalic: true,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .fullBar,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0.85,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Retro ───────────────────────────────────────────────────────────────
    static let retro = CaptionStylePreset(
        id: "retro", name: "Retro",
        fontName: "AmericanTypewriter-Bold", fontSize: 22, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 0.9, textColorB: 0, textColorA: 1,
        bgType: .none,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 3,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 1
    )

    // ── Minimal ─────────────────────────────────────────────────────────────
    static let minimal = CaptionStylePreset(
        id: "minimal", name: "Minimal",
        fontName: "HelveticaNeue-Light", fontSize: 17, isBold: false, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 0.75,
        bgType: .none,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Gradient ────────────────────────────────────────────────────────────
    static let gradient = CaptionStylePreset(
        id: "gradient", name: "Gradient",
        fontName: "Didot-Bold", fontSize: 26, isBold: true, isItalic: false,
        textColorR: 0.4, textColorG: 0.8, textColorB: 1, textColorA: 1,
        bgType: .none,
        bgColorR: 0, bgColorG: 0, bgColorB: 0, bgColorA: 0,
        strokeWidth: 0,
        strokeColorR: 0.2, strokeColorG: 0.4, strokeColorB: 1, strokeColorA: 0.5
    )

    // ── Pop ─────────────────────────────────────────────────────────────────
    static let pop = CaptionStylePreset(
        id: "pop", name: "Pop",
        fontName: "Futura-CondensedExtraBold", fontSize: 28, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .pill,
        bgColorR: 0.95, bgColorG: 0.2, bgColorB: 0.4, bgColorA: 1,
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )

    // ── Karaoke ─────────────────────────────────────────────────────────────
    static let karaoke = CaptionStylePreset(
        id: "karaoke", name: "Karaoke",
        fontName: "AvenirNext-Bold", fontSize: 24, isBold: true, isItalic: false,
        textColorR: 1, textColorG: 1, textColorB: 1, textColorA: 1,
        bgType: .highlightWord,
        bgColorR: 0.3, bgColorG: 0.7, bgColorB: 1, bgColorA: 1,   // cyan highlight
        strokeWidth: 0,
        strokeColorR: 0, strokeColorG: 0, strokeColorB: 0, strokeColorA: 0
    )
}