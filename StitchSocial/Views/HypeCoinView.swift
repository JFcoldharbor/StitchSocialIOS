//
//  HypeCoinView.swift
//  StitchSocial
//
//  Native SwiftUI HypeCoin — shiny gold coin with live flame animation.
//  Uses TimelineView for per-frame flame updates (no Canvas static redraw issue).
//  Pure computed view, zero Firestore reads. No caching needed here.
//  Balance display pulls from HypeCoinCoordinator (already cached there).
//

import SwiftUI

// MARK: - HypeCoinView

struct HypeCoinView: View {
    var size: CGFloat = 80
    var onTap: (() -> Void)? = nil

    @State private var pressed = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            coinBody(t: t)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 1.18 : 1.0)
        .brightness(pressed ? 0.25 : 0)
        .shadow(
            color: Color(red: 1, green: 0.42, blue: 0).opacity(pressed ? 0.85 : 0.35),
            radius: pressed ? size * 0.28 : size * 0.14
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: pressed)
        .onTapGesture {
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pressed = false }
            onTap?()
        }
    }

    @ViewBuilder
    private func coinBody(t: Double) -> some View {
        let outerScale = 1.0 + sin(t * 3.3) * 0.055 + sin(t * 5.1) * 0.02
        let coreScale  = 1.0 + sin(t * 4.1 + 1.0) * 0.045 + sin(t * 6.7) * 0.015
        let coreOp     = 0.68 + sin(t * 8.5) * 0.28
        let flickerX   = sin(t * 7.3) * size * 0.025
        let flickerX2  = sin(t * 5.9 + 0.8) * size * 0.02

        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: size * 0.62, height: size * 0.09)
                .offset(y: size * 0.48)

            // Edge ring
            Circle()
                .fill(AngularGradient(colors: [
                    Color(hex: "#FFF0A0"), Color(hex: "#FFB800"),
                    Color(hex: "#7A4400"), Color(hex: "#FFD060"),
                    Color(hex: "#FFF0A0")
                ], center: .center))
                .frame(width: size, height: size)

            // Coin base
            Circle()
                .fill(RadialGradient(colors: [
                    Color(hex: "#FFF5A0"),
                    Color(hex: "#FFD700"),
                    Color(hex: "#CC8800"),
                    Color(hex: "#6B3A00")
                ], center: UnitPoint(x: 0.38, y: 0.32),
                   startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 0.935, height: size * 0.935)
                .shadow(color: Color(hex: "#AA5500").opacity(0.6),
                        radius: size * 0.1, x: 0, y: size * 0.04)

            // Emboss ring
            Circle()
                .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1)
                .frame(width: size * 0.84, height: size * 0.84)

            // Outer flame
            FlameOuter(size: size, scale: outerScale, offsetX: flickerX)
                .blur(radius: size * 0.035)
                .clipShape(Circle().scale(0.935))

            // Core flame
            FlameCore(size: size, scale: coreScale, offsetX: flickerX2)
                .clipShape(Circle().scale(0.935))

            // White-hot center
            Ellipse()
                .fill(Color.white.opacity(coreOp))
                .frame(width: size * 0.08, height: size * 0.13)
                .offset(x: flickerX * 0.5, y: size * 0.12)
                .clipShape(Circle().scale(0.935))

            // Specular highlight — bottom-left edge, clear of flame
            Ellipse()
                .fill(RadialGradient(colors: [
                    Color.white.opacity(0.5),
                    Color.white.opacity(0)
                ], center: .center, startRadius: 0, endRadius: size * 0.16))
                .frame(width: size * 0.28, height: size * 0.16)
                .rotationEffect(.degrees(30))
                .offset(x: -size * 0.22, y: size * 0.26)
                .clipShape(Circle().scale(0.935))

            Ellipse()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.09, height: size * 0.05)
                .rotationEffect(.degrees(30))
                .offset(x: -size * 0.24, y: size * 0.28)
                .clipShape(Circle().scale(0.935))
        }
    }
}

// MARK: - Flame Views (SwiftUI Path — react to parent state)

private struct FlameOuter: View {
    let size: CGFloat
    let scale: Double
    let offsetX: Double

    var body: some View {
        let s = size
        Path { p in
            p.move(to:     CGPoint(x: s*0.50 + offsetX, y: s*0.76))
            p.addCurve(to: CGPoint(x: s*0.29, y: s*0.49),
                       control1: CGPoint(x: s*0.37, y: s*0.72),
                       control2: CGPoint(x: s*0.27, y: s*0.61))
            p.addCurve(to: CGPoint(x: s*0.35, y: s*0.24),
                       control1: CGPoint(x: s*0.31, y: s*0.39),
                       control2: CGPoint(x: s*0.38, y: s*0.35))
            p.addCurve(to: CGPoint(x: s*0.42, y: s*0.43),
                       control1: CGPoint(x: s*0.37, y: s*0.31),
                       control2: CGPoint(x: s*0.38, y: s*0.38))
            p.addCurve(to: CGPoint(x: s*0.50 + offsetX, y: s*0.18),
                       control1: CGPoint(x: s*0.43, y: s*0.35),
                       control2: CGPoint(x: s*0.46, y: s*0.27))
            p.addCurve(to: CGPoint(x: s*0.58, y: s*0.43),
                       control1: CGPoint(x: s*0.54, y: s*0.27),
                       control2: CGPoint(x: s*0.57, y: s*0.35))
            p.addCurve(to: CGPoint(x: s*0.65, y: s*0.23),
                       control1: CGPoint(x: s*0.62, y: s*0.32),
                       control2: CGPoint(x: s*0.60, y: s*0.30))
            p.addCurve(to: CGPoint(x: s*0.71, y: s*0.51),
                       control1: CGPoint(x: s*0.68, y: s*0.36),
                       control2: CGPoint(x: s*0.63, y: s*0.43))
            p.addCurve(to: CGPoint(x: s*0.50 + offsetX, y: s*0.76),
                       control1: CGPoint(x: s*0.73, y: s*0.63),
                       control2: CGPoint(x: s*0.63, y: s*0.72))
        }
        .fill(LinearGradient(colors: [
            Color(hex: "#FF9500").opacity(0.92),
            Color(hex: "#FF4500").opacity(0.6),
            Color(hex: "#CC2200").opacity(0.05)
        ], startPoint: .bottom, endPoint: .top))
        .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 0.76))
        .frame(width: size, height: size)
    }
}

private struct FlameCore: View {
    let size: CGFloat
    let scale: Double
    let offsetX: Double

    var body: some View {
        let s = size
        Path { p in
            p.move(to:     CGPoint(x: s*0.50 + offsetX, y: s*0.73))
            p.addCurve(to: CGPoint(x: s*0.36, y: s*0.51),
                       control1: CGPoint(x: s*0.41, y: s*0.70),
                       control2: CGPoint(x: s*0.34, y: s*0.61))
            p.addCurve(to: CGPoint(x: s*0.41, y: s*0.32),
                       control1: CGPoint(x: s*0.38, y: s*0.43),
                       control2: CGPoint(x: s*0.43, y: s*0.40))
            p.addCurve(to: CGPoint(x: s*0.47, y: s*0.47),
                       control1: CGPoint(x: s*0.43, y: s*0.38),
                       control2: CGPoint(x: s*0.43, y: s*0.44))
            p.addCurve(to: CGPoint(x: s*0.50 + offsetX, y: s*0.26),
                       control1: CGPoint(x: s*0.475, y: s*0.40),
                       control2: CGPoint(x: s*0.49,  y: s*0.33))
            p.addCurve(to: CGPoint(x: s*0.53, y: s*0.47),
                       control1: CGPoint(x: s*0.51,  y: s*0.33),
                       control2: CGPoint(x: s*0.525, y: s*0.40))
            p.addCurve(to: CGPoint(x: s*0.59, y: s*0.32),
                       control1: CGPoint(x: s*0.57, y: s*0.44),
                       control2: CGPoint(x: s*0.57, y: s*0.38))
            p.addCurve(to: CGPoint(x: s*0.64, y: s*0.51),
                       control1: CGPoint(x: s*0.57, y: s*0.40),
                       control2: CGPoint(x: s*0.62, y: s*0.43))
            p.addCurve(to: CGPoint(x: s*0.50 + offsetX, y: s*0.73),
                       control1: CGPoint(x: s*0.66, y: s*0.61),
                       control2: CGPoint(x: s*0.59, y: s*0.70))
        }
        .fill(LinearGradient(colors: [
            Color.white,
            Color(hex: "#FFFDE0"),
            Color(hex: "#FFD700"),
            Color(hex: "#FF6B00"),
            Color(hex: "#FF2200")
        ], startPoint: .bottom, endPoint: .top))
        .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 0.73))
        .frame(width: size, height: size)
    }
}

// MARK: - Balance Badge

struct HypeCoinBadge: View {
    let balance: Int
    var body: some View {
        HStack(spacing: 6) {
            HypeCoinView(size: 28)
            Text("\(balance.formatted())")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "#FFF5A0"), Color(hex: "#FFB800")],
                    startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "#1A0800").opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "#FF8800").opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 32) {
            HypeCoinView(size: 160)
            HypeCoinBadge(balance: 1_250)
            HStack(spacing: 20) {
                HypeCoinView(size: 40)
                HypeCoinView(size: 56)
                HypeCoinView(size: 72)
            }
        }
    }
}
