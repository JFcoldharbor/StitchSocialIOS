//
//  BadgeArtwork.swift
//  StitchSocial
//
//  SwiftUI artwork for every badge, translated from BadgeMockup.jsx SVGs.
//  Usage: BadgeArtwork.art(id: def.id, size: 48)
//
//  CACHING: All shapes are pure SwiftUI — zero reads, zero network calls.
//  No caching needed here; SwiftUI reuses view descriptions automatically.
//

import SwiftUI

// MARK: - Public entry point

struct BadgeArtwork: View {
    let id: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            switch id {
            // ── Seasonal ──────────────────────────────────────
            case "halloween_pumpkin":  PumpkinKingArt(size: size)
            case "halloween_ghost":    GhostModeArt(size: size)
            case "christmas_elf":      HypeElfArt(size: size)
            case "christmas_legend":   SantaFavoriteArt(size: size)
            case "summer_vibe":        SummerVibeArt(size: size)
            case "new_year_blast":     NewYearBlastArt(size: size)
            // ── Hype Master ───────────────────────────────────
            case "hype_initiate":      HypeInitiateArt(size: size)
            case "hype_master":        HypeMasterArt(size: size)
            case "hype_overlord":      HypeOverlordArt(size: size)
            // ── Cool Villain ──────────────────────────────────
            case "cool_villain_rookie": PettyVillainArt(size: size)
            case "cool_villain_mid":    CooldownCommanderArt(size: size)
            case "cool_villain_legend": VillainEraArt(size: size)
            // ── Creator ───────────────────────────────────────
            case "first_post":         FirstDropArt(size: size)
            case "content_grinder":    ContentGrinderArt(size: size)
            case "prolific_creator":   ProlificCreatorArt(size: size)
            // ── Engagement ────────────────────────────────────
            case "xp_climber":         XPClimberArt(size: size)
            case "clout_earner":       CloutEarnerArt(size: size)
            case "clout_champion":     CloutChampionArt(size: size)
            // ── Tipper ────────────────────────────────────────
            case "tipper":             TipperArt(size: size)
            case "big_tipper":         BigTipperArt(size: size)
            case "whale":              WhaleArt(size: size)
            // ── Social ────────────────────────────────────────
            case "networker":          NetworkerArt(size: size)
            case "popular":            PopularArt(size: size)
            case "influencer_badge":   InfluencerArt(size: size)
            // ── Subscription (given) ──────────────────────────
            case "first_sub":          FirstSubArt(size: size)
            case "loyal_supporter":    LoyalSupporterArt(size: size)
            case "super_fan":          SuperFanArt(size: size)
            // ── Subscription (earned) ─────────────────────────
            case "first_subscriber":   FirstSubscriberArt(size: size)
            case "growing_community":  GrowingCommunityArt(size: size)
            case "subscriber_king":    SubscriberKingArt(size: size)
            // ── Tier ──────────────────────────────────────────
            case "tier_rookie":        TierArt(label: "R",  color: Color(hex: "9ca3af"), size: size)
            case "tier_rising":        TierArt(label: "RS", color: Color(hex: "4ade80"), size: size)
            case "tier_veteran":       VeteranArt(size: size)
            case "tier_influencer":    TierArt(label: "IN", color: Color(hex: "60a5fa"), size: size)
            case "tier_ambassador":    TierArt(label: "AM", color: Color(hex: "a78bfa"), size: size)
            case "tier_elite":         EliteArt(size: size)
            case "tier_partner":       TierArt(label: "PT", color: Color(hex: "f59e0b"), size: size)
            case "tier_legendary":     LegendaryStatusArt(size: size)
            case "tier_top_creator":   TierArt(label: "TC", color: Color(hex: "fbbf24"), size: size)
            case "tier_founder_crest": FounderCrestArt(size: size)
            // ── Special ───────────────────────────────────────
            case "founder_badge":      FounderBadgeArt(size: size)
            case "beta_tester":        BetaTesterArt(size: size)
            case "early_adopter":      EarlyAdopterArt(size: size)
            // ── Signal badges (pattern: signal_<kind>_<grade>) ─
            default:                   signalOrFallback(id: id, size: size)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func signalOrFallback(id: String, size: CGFloat) -> some View {
        if id.hasPrefix("signal_") {
            let parts = id.split(separator: "_")
            // signal_<kind>_<grade>  e.g. signal_partner_hypes_bronze
            let gradeStr = parts.last.map(String.init) ?? ""
            let grade = SignalGrade(rawString: gradeStr)
            let isFounder = id.contains("founder")
            let isMulti   = id.contains("multi_tier")
            let isSingle  = id.contains("single_post")
            if isFounder {
                SignalArt(kind: .founder,  grade: grade, size: size)
            } else if isMulti {
                SignalArt(kind: .multiTier, grade: grade, size: size)
            } else if isSingle {
                SignalArt(kind: .singlePost, grade: grade, size: size)
            } else {
                SignalArt(kind: .partnerHypes, grade: grade, size: size)
            }
        } else {
            FallbackArt(size: size)
        }
    }
}

// MARK: - Helpers

private enum SignalKind { case partnerHypes, singlePost, multiTier, founder }

private struct SignalGrade {
    let color1: Color; let color2: Color; let color3: Color; let bg: Color
    init(rawString: String) {
        switch rawString.lowercased() {
        case "silver":   color1=Color(hex:"c0c0c0"); color2=Color(hex:"606060"); color3=Color(hex:"e8e8e8"); bg=Color(hex:"111118")
        case "gold":     color1=Color(hex:"fbbf24"); color2=Color(hex:"92400e"); color3=Color(hex:"fde68a"); bg=Color(hex:"150e00")
        case "platinum": color1=Color(hex:"67e8f9"); color2=Color(hex:"0c4a6e"); color3=Color(hex:"e0f2fe"); bg=Color(hex:"00121a")
        default:         color1=Color(hex:"e07b30"); color2=Color(hex:"7c3510"); color3=Color(hex:"f0a060"); bg=Color(hex:"1a0a00")
        }
    }
}
// MARK: - SEASONAL

private struct PumpkinKingArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Body
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex:"fb923c"), Color(hex:"ea580c"), Color(hex:"7c2d12")],
                                     center: .init(x:0.5,y:0.55), startRadius: 0, endRadius: size*0.55))
                .frame(width: size*0.72, height: size*0.58)
                .offset(y: size*0.08)
            // Stem
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex:"15803d"))
                .frame(width: size*0.08, height: size*0.18)
                .offset(y: -size*0.28)
            // Crown
            Path { p in
                let w = size; let h = size
                p.move(to: .init(x:w*0.28,y:h*0.36))
                p.addLine(to: .init(x:w*0.34,y:h*0.23))
                p.addLine(to: .init(x:w*0.41,y:h*0.32))
                p.addLine(to: .init(x:w*0.50,y:h*0.20))
                p.addLine(to: .init(x:w*0.59,y:h*0.32))
                p.addLine(to: .init(x:w*0.66,y:h*0.23))
                p.addLine(to: .init(x:w*0.72,y:h*0.36))
            }
            .stroke(Color(hex:"fbbf24"), lineWidth: size*0.04)
            // Triangle eyes
            Path { p in
                p.move(to: .init(x:size*0.34,y:size*0.54))
                p.addLine(to: .init(x:size*0.41,y:size*0.43))
                p.addLine(to: .init(x:size*0.48,y:size*0.54))
                p.closeSubpath()
            }.fill(Color(hex:"fef08a"))
            Path { p in
                p.move(to: .init(x:size*0.52,y:size*0.54))
                p.addLine(to: .init(x:size*0.59,y:size*0.43))
                p.addLine(to: .init(x:size*0.66,y:size*0.54))
                p.closeSubpath()
            }.fill(Color(hex:"fef08a"))
            // Jagged mouth
            Path { p in
                let y = size*0.70
                p.move(to: .init(x:size*0.32,y:y))
                for i in 0..<5 {
                    let x = size*(0.32 + Double(i)*0.09)
                    p.addLine(to: .init(x:x + size*0.045, y: i%2==0 ? y+size*0.07 : y))
                }
                p.addLine(to: .init(x:size*0.68,y:y))
            }.stroke(Color(hex:"fef08a"), lineWidth: size*0.035)
        }
    }
}

private struct GhostModeArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Aura
            Ellipse()
                .fill(Color(hex:"a78bfa").opacity(0.18))
                .frame(width: size*0.72, height: size*0.80)
                .blur(radius: size*0.08)
                .offset(y: size*0.06)
            // Ghost body
            Path { p in
                let w = size; let h = size
                p.move(to: .init(x:w*0.18,y:h*0.82))
                p.addQuadCurve(to: .init(x:w*0.18,y:h*0.28), control: .init(x:w*0.18,y:h*0.20))
                p.addQuadCurve(to: .init(x:w*0.82,y:h*0.28), control: .init(x:w*0.50,y:h*0.10))
                p.addQuadCurve(to: .init(x:w*0.82,y:h*0.82), control: .init(x:w*0.82,y:h*0.20))
                p.addLine(to: .init(x:w*0.72,y:h*0.74))
                p.addLine(to: .init(x:w*0.61,y:h*0.82))
                p.addLine(to: .init(x:w*0.50,y:h*0.74))
                p.addLine(to: .init(x:w*0.39,y:h*0.82))
                p.addLine(to: .init(x:w*0.28,y:h*0.74))
                p.closeSubpath()
            }
            .fill(RadialGradient(colors: [Color(hex:"e2e8f0").opacity(0.95), Color(hex:"94a3b8").opacity(0.75)],
                                 center: .init(x:0.5,y:0.35), startRadius: 0, endRadius: size*0.5))
            // Eyes
            Ellipse().fill(Color(hex:"1e293b")).frame(width:size*0.18,height:size*0.22).offset(x:-size*0.14,y:-size*0.06)
            Ellipse().fill(Color(hex:"1e293b")).frame(width:size*0.18,height:size*0.22).offset(x:size*0.14,y:-size*0.06)
            Ellipse().fill(Color(hex:"818cf8").opacity(0.85)).frame(width:size*0.09,height:size*0.11).offset(x:-size*0.12,y:-size*0.07)
            Ellipse().fill(Color(hex:"818cf8").opacity(0.85)).frame(width:size*0.09,height:size*0.11).offset(x:size*0.16,y:-size*0.07)
        }
    }
}

private struct HypeElfArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Tree
            Path { p in
                let cx = size/2
                p.move(to: .init(x:cx,y:size*0.06))
                p.addLine(to: .init(x:size*0.72,y:size*0.42))
                p.addLine(to: .init(x:size*0.61,y:size*0.42))
                p.addLine(to: .init(x:size*0.78,y:size*0.66))
                p.addLine(to: .init(x:size*0.64,y:size*0.66))
                p.addLine(to: .init(x:size*0.72,y:size*0.88))
                p.addLine(to: .init(x:size*0.28,y:size*0.88))
                p.addLine(to: .init(x:size*0.36,y:size*0.66))
                p.addLine(to: .init(x:size*0.22,y:size*0.66))
                p.addLine(to: .init(x:size*0.39,y:size*0.42))
                p.addLine(to: .init(x:size*0.28,y:size*0.42))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"4ade80"),Color(hex:"15803d")], startPoint:.top, endPoint:.bottom))
            // Star
            StarShape(points:5)
                .fill(LinearGradient(colors:[Color(hex:"fef08a"),Color(hex:"f59e0b")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.18,height:size*0.18)
                .offset(y:-size*0.40)
            // Ornaments
            Circle().fill(Color(hex:"ef4444")).frame(width:size*0.12,height:size*0.12).offset(x:-size*0.12,y:size*0.14)
            Circle().fill(Color(hex:"fbbf24")).frame(width:size*0.12,height:size*0.12).offset(x:size*0.12,y:size*0.14)
            Circle().fill(Color(hex:"60a5fa")).frame(width:size*0.12,height:size*0.12).offset(x:-size*0.18,y:size*0.32)
            Circle().fill(Color(hex:"ef4444")).frame(width:size*0.14,height:size*0.14).offset(y:size*0.32)
        }
    }
}

private struct SantaFavoriteArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Crown
            Path { p in
                let w=size; let h=size
                p.move(to: .init(x:w*0.15,y:h*0.42))
                p.addLine(to: .init(x:w*0.25,y:h*0.22))
                p.addLine(to: .init(x:w*0.38,y:h*0.34))
                p.addLine(to: .init(x:w*0.50,y:h*0.14))
                p.addLine(to: .init(x:w*0.62,y:h*0.34))
                p.addLine(to: .init(x:w*0.75,y:h*0.22))
                p.addLine(to: .init(x:w*0.85,y:h*0.42))
                p.addLine(to: .init(x:w*0.78,y:h*0.50))
                p.addLine(to: .init(x:w*0.22,y:h*0.50))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"fef08a"),Color(hex:"b45309")], startPoint:.top, endPoint:.bottom))
            // Base band
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex:"b45309"))
                .frame(width:size*0.72,height:size*0.14)
                .offset(y:size*0.20)
            // Gems
            Circle().fill(Color(hex:"c084fc")).frame(width:size*0.14).offset(x:-size*0.22,y:size*0.20)
            Circle().fill(Color.white.opacity(0.9)).frame(width:size*0.18).offset(y:size*0.20)
            Circle().fill(Color(hex:"60a5fa")).frame(width:size*0.14).offset(x:size*0.22,y:size*0.20)
            // Sack
            Ellipse()
                .fill(LinearGradient(colors:[Color(hex:"dc2626"),Color(hex:"7f1d1d")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.60,height:size*0.46)
                .offset(y:size*0.26)
        }
    }
}

private struct SummerVibeArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Sun
            Circle()
                .fill(RadialGradient(colors:[Color(hex:"fef08a"),Color(hex:"f59e0b")], center:.center, startRadius:0, endRadius:size*0.22))
                .frame(width:size*0.44,height:size*0.44)
                .offset(y:-size*0.20)
            // Sun rays
            ForEach(0..<8) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex:"fde68a"))
                    .frame(width: size*0.05, height: size*0.14)
                    .offset(y: -size*0.38)
                    .rotationEffect(.degrees(Double(i)*45))
            }
            // Ocean
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors:[Color(hex:"0ea5e9"),Color(hex:"0369a1")], startPoint:.top, endPoint:.bottom))
                .frame(width:size,height:size*0.44)
                .offset(y:size*0.28)
            // Wave
            Path { p in
                p.move(to: .init(x:0,y:size*0.28))
                for i in stride(from: 0.0, through: 1.0, by: 0.125) {
                    p.addQuadCurve(
                        to: .init(x:size*(i+0.125),y:size*0.28),
                        control: .init(x:size*(i+0.0625), y: i.truncatingRemainder(dividingBy: 0.25)==0 ? size*0.20 : size*0.36)
                    )
                }
            }.stroke(Color(hex:"38bdf8"), lineWidth: size*0.06)
            // Board
            Ellipse()
                .fill(LinearGradient(colors:[Color(hex:"f97316"),Color(hex:"dc2626")], startPoint:.leading, endPoint:.trailing))
                .frame(width:size*0.58,height:size*0.14)
                .rotationEffect(.degrees(-10))
                .offset(y:size*0.24)
        }
    }
}

private struct NewYearBlastArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size*0.22)
                .fill(LinearGradient(colors:[Color(hex:"1e1b4b"),Color(hex:"07070b")], startPoint:.topLeading, endPoint:.bottomTrailing))
            // Firework bursts
            let bursts: [(CGFloat,CGFloat,String,Int)] = [
                (0.28,0.25,"f97316",8),(0.72,0.32,"60a5fa",7),(0.50,0.18,"fbbf24",10),
                (0.18,0.58,"f472b6",6),(0.82,0.64,"4ade80",7),(0.58,0.72,"c084fc",6)
            ]
            ForEach(0..<bursts.count, id:\.self) { i in
                let b = bursts[i]
                FireworkBurst(cx:b.0*size, cy:b.1*size, color:Color(hex:b.2), count:b.3, radius:size*0.16)
            }
            // Year label
            Text("2025")
                .font(.system(size: size*0.18, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex:"fbbf24"))
                .offset(y: size*0.30)
        }
        .frame(width:size,height:size)
        .clipShape(RoundedRectangle(cornerRadius:size*0.22))
    }
}

private struct FireworkBurst: View {
    let cx,cy: CGFloat; let color: Color; let count: Int; let radius: CGFloat
    var body: some View {
        Canvas { ctx, _ in
            for i in 0..<count {
                let angle = Double(i)/Double(count) * .pi * 2
                let path = Path { p in
                    p.move(to: .init(x:cx,y:cy))
                    p.addLine(to: .init(x:cx+CGFloat(cos(angle))*radius, y:cy+CGFloat(sin(angle))*radius))
                }
                ctx.stroke(path, with: .color(color), lineWidth: 1.8)
            }
            ctx.fill(Path(ellipseIn: .init(x:cx-3,y:cy-3,width:6,height:6)), with: .color(color))
        }
    }
}

// MARK: - HYPE MASTER

private struct HypeInitiateArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Path { p in
                let cx = size/2
                p.move(to: .init(x:cx, y:size*0.92))
                p.addQuadCurve(to:.init(x:size*0.24,y:size*0.50), control:.init(x:size*0.18,y:size*0.64))
                p.addQuadCurve(to:.init(x:size*0.38,y:size*0.24), control:.init(x:size*0.26,y:size*0.32))
                p.addQuadCurve(to:.init(x:cx,y:size*0.10), control:.init(x:size*0.32,y:size*0.46))
                p.addQuadCurve(to:.init(x:size*0.62,y:size*0.24), control:.init(x:size*0.68,y:size*0.46))
                p.addQuadCurve(to:.init(x:size*0.76,y:size*0.50), control:.init(x:size*0.74,y:size*0.32))
                p.addQuadCurve(to:.init(x:cx,y:size*0.92), control:.init(x:size*0.82,y:size*0.64))
            }
            .fill(RadialGradient(colors:[Color(hex:"f97316"),Color(hex:"dc2626"),Color(hex:"7f1d1d")],
                                 center:.init(x:0.5,y:0.7), startRadius:0, endRadius:size*0.55))
            // Core flame
            Path { p in
                let cx = size/2
                p.move(to: .init(x:cx,y:size*0.88))
                p.addQuadCurve(to:.init(x:size*0.34,y:size*0.52), control:.init(x:size*0.28,y:size*0.62))
                p.addQuadCurve(to:.init(x:cx,y:size*0.30), control:.init(x:size*0.38,y:size*0.34))
                p.addQuadCurve(to:.init(x:size*0.62,y:size*0.44), control:.init(x:size*0.62,y:size*0.34))
                p.addQuadCurve(to:.init(x:cx,y:size*0.88), control:.init(x:size*0.68,y:size*0.62))
            }
            .fill(RadialGradient(colors:[Color(hex:"fef08a"),Color(hex:"fb923c")], center:.init(x:0.5,y:0.55), startRadius:0, endRadius:size*0.38))
        }
    }
}

private struct HypeMasterArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Rings
            Ellipse().stroke(Color(hex:"fbbf24").opacity(0.28), lineWidth:1.5)
                .frame(width:size*0.92,height:size*0.32).rotationEffect(.degrees(-20))
            Ellipse().stroke(Color(hex:"f59e0b").opacity(0.32), lineWidth:1)
                .frame(width:size*0.72,height:size*0.24).rotationEffect(.degrees(20))
            // Bolt
            Path { p in
                p.move(to: .init(x:size*0.62,y:size*0.06))
                p.addLine(to: .init(x:size*0.32,y:size*0.54))
                p.addLine(to: .init(x:size*0.52,y:size*0.54))
                p.addLine(to: .init(x:size*0.40,y:size*0.94))
                p.addLine(to: .init(x:size*0.76,y:size*0.44))
                p.addLine(to: .init(x:size*0.54,y:size*0.44))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors:[Color(hex:"fef08a"),Color(hex:"f59e0b"),Color(hex:"78350f")],
                                 startPoint:.top, endPoint:.bottom))
            .shadow(color:Color(hex:"fbbf24").opacity(0.6), radius:6)
        }
    }
}

private struct HypeOverlordArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Crown body
            Path { p in
                p.move(to: .init(x:size*0.14,y:size*0.75))
                p.addLine(to: .init(x:size*0.22,y:size*0.32))
                p.addLine(to: .init(x:size*0.38,y:size*0.54))
                p.addLine(to: .init(x:size*0.50,y:size*0.18))
                p.addLine(to: .init(x:size*0.62,y:size*0.54))
                p.addLine(to: .init(x:size*0.78,y:size*0.32))
                p.addLine(to: .init(x:size*0.86,y:size*0.75))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"fef08a"),Color(hex:"f59e0b"),Color(hex:"92400e")], startPoint:.top, endPoint:.bottom))
            // Base
            RoundedRectangle(cornerRadius:4)
                .fill(Color(hex:"92400e"))
                .frame(width:size*0.80,height:size*0.16)
                .offset(y:size*0.30)
            // Gems
            Circle().fill(Color(hex:"c084fc")).frame(width:size*0.16).offset(x:-size*0.22,y:size*0.30)
            Circle().fill(LinearGradient(colors:[Color.white.opacity(0.55),Color(hex:"fbbf24")], startPoint:.topLeading, endPoint:.bottomTrailing)).frame(width:size*0.20).offset(y:size*0.30)
            Circle().fill(Color(hex:"60a5fa")).frame(width:size*0.16).offset(x:size*0.22,y:size*0.30)
        }
    }
}

// MARK: - COOL VILLAIN

private struct PettyVillainArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Horns
            Path { p in
                p.move(to: .init(x:size*0.30,y:size*0.32))
                p.addQuadCurve(to:.init(x:size*0.22,y:size*0.10), control:.init(x:size*0.16,y:size*0.16))
                p.addLine(to: .init(x:size*0.36,y:size*0.24))
            }.stroke(Color(hex:"6d28d9"), lineWidth:size*0.09)
            Path { p in
                p.move(to: .init(x:size*0.70,y:size*0.32))
                p.addQuadCurve(to:.init(x:size*0.78,y:size*0.10), control:.init(x:size*0.84,y:size*0.16))
                p.addLine(to: .init(x:size*0.64,y:size*0.24))
            }.stroke(Color(hex:"6d28d9"), lineWidth:size*0.09)
            // Face
            Ellipse()
                .fill(RadialGradient(colors:[Color(hex:"7c3aed"),Color(hex:"3b0764")], center:.init(x:0.5,y:0.45), startRadius:0, endRadius:size*0.44))
                .frame(width:size*0.80,height:size*0.72)
                .offset(y:size*0.14)
            // Brow lines
            Path { p in
                p.move(to:.init(x:size*0.28,y:size*0.42)); p.addQuadCurve(to:.init(x:size*0.44,y:size*0.46), control:.init(x:size*0.36,y:size*0.36))
            }.stroke(Color(hex:"c084fc"), lineWidth:size*0.05)
            Path { p in
                p.move(to:.init(x:size*0.56,y:size*0.46)); p.addQuadCurve(to:.init(x:size*0.72,y:size*0.42), control:.init(x:size*0.64,y:size*0.36))
            }.stroke(Color(hex:"c084fc"), lineWidth:size*0.05)
            // Eyes
            Ellipse().fill(Color(hex:"c084fc")).frame(width:size*0.22,height:size*0.20).offset(x:-size*0.14,y:size*0.18)
            Ellipse().fill(Color(hex:"c084fc")).frame(width:size*0.22,height:size*0.20).offset(x:size*0.14,y:size*0.18)
            Ellipse().fill(Color(hex:"0f0028")).frame(width:size*0.12,height:size*0.14).offset(x:-size*0.14,y:size*0.18)
            Ellipse().fill(Color(hex:"0f0028")).frame(width:size*0.12,height:size*0.14).offset(x:size*0.14,y:size*0.18)
            // Grin
            Path { p in
                p.move(to:.init(x:size*0.32,y:size*0.75))
                p.addQuadCurve(to:.init(x:size*0.68,y:size*0.75), control:.init(x:size*0.50,y:size*0.90))
            }.stroke(Color(hex:"c084fc"), lineWidth:size*0.05)
        }
    }
}

private struct CooldownCommanderArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Cape
            Path { p in
                p.move(to:.init(x:size*0.25,y:size*0.32))
                p.addQuadCurve(to:.init(x:size*0.14,y:size*0.96), control:.init(x:size*0.06,y:size*0.64))
                p.addLine(to:.init(x:size*0.86,y:size*0.96))
                p.addQuadCurve(to:.init(x:size*0.75,y:size*0.32), control:.init(x:size*0.94,y:size*0.64))
            }.fill(Color(hex:"1e1b4b").opacity(0.9))
            // Helmet
            Path { p in
                p.move(to:.init(x:size*0.26,y:size*0.54))
                p.addQuadCurve(to:.init(x:size*0.26,y:size*0.30), control:.init(x:size*0.22,y:size*0.14))
                p.addQuadCurve(to:.init(x:size*0.74,y:size*0.30), control:.init(x:size*0.50,y:size*0.12))
                p.addQuadCurve(to:.init(x:size*0.74,y:size*0.54), control:.init(x:size*0.78,y:size*0.14))
                p.closeSubpath()
            }.fill(Color(hex:"3b0764"))
            // Visor
            Path { p in
                p.move(to:.init(x:size*0.28,y:size*0.40))
                p.addQuadCurve(to:.init(x:size*0.72,y:size*0.40), control:.init(x:size*0.50,y:size*0.52))
            }
            .fill(LinearGradient(colors:[Color(hex:"a78bfa"),Color(hex:"4c1d95")], startPoint:.top, endPoint:.bottom))
            .opacity(0.85)
            // Body
            Ellipse()
                .fill(LinearGradient(colors:[Color(hex:"7c3aed"),Color(hex:"3b0764")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.52,height:size*0.50)
                .offset(y:size*0.24)
            // Snowflake on chest
            ForEach(0..<3) { i in
                Rectangle().fill(Color.white.opacity(0.8))
                    .frame(width:size*0.04,height:size*0.22)
                    .offset(y:size*0.24)
                    .rotationEffect(.degrees(Double(i)*60))
            }
        }
    }
}

private struct VillainEraArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Thorn crown
            Path { p in
                let pts: [(CGFloat,CGFloat)] = [(0.18,0.32),(0.25,0.18),(0.32,0.28),(0.38,0.12),(0.44,0.25),(0.50,0.10),(0.56,0.25),(0.62,0.12),(0.68,0.28),(0.75,0.18),(0.82,0.32)]
                p.move(to:.init(x:size*pts[0].0,y:size*pts[0].1))
                for pt in pts.dropFirst() { p.addLine(to:.init(x:size*pt.0,y:size*pt.1)) }
            }.stroke(Color(hex:"f59e0b").opacity(0.8), lineWidth:size*0.04)
            // Skull
            Ellipse()
                .fill(RadialGradient(colors:[Color(hex:"4c1d95"),Color(hex:"0a0014")], center:.init(x:0.5,y:0.4), startRadius:0, endRadius:size*0.42))
                .frame(width:size*0.72,height:size*0.68)
                .offset(y:size*0.10)
            // Eye sockets
            Ellipse().fill(Color(hex:"0a0014")).frame(width:size*0.24,height:size*0.28).offset(x:-size*0.16,y:size*0.04)
            Ellipse().fill(Color(hex:"0a0014")).frame(width:size*0.24,height:size*0.28).offset(x:size*0.16,y:size*0.04)
            Ellipse().fill(Color(hex:"7c3aed").opacity(0.9)).frame(width:size*0.12,height:size*0.14).offset(x:-size*0.16,y:size*0.04)
            Ellipse().fill(Color(hex:"7c3aed").opacity(0.9)).frame(width:size*0.12,height:size*0.14).offset(x:size*0.16,y:size*0.04)
            // Teeth row
            RoundedRectangle(cornerRadius:4).fill(Color(hex:"1e0040")).frame(width:size*0.50,height:size*0.18).offset(y:size*0.36)
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius:2)
                    .fill(Color(hex:"e2e8f0").opacity(0.9))
                    .frame(width:size*0.07,height:size*0.14)
                    .offset(x:size*(CGFloat(i)*0.10 - 0.20),y:size*0.36)
            }
        }
    }
}

// MARK: - CREATOR

private struct FirstDropArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Clapper body
            RoundedRectangle(cornerRadius:6)
                .fill(LinearGradient(colors:[Color(hex:"3b82f6"),Color(hex:"1d4ed8")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.80,height:size*0.56)
                .offset(y:size*0.14)
            // Clapper top
            RoundedRectangle(cornerRadius:4)
                .fill(Color(hex:"1e3a8a"))
                .frame(width:size*0.80,height:size*0.22)
                .offset(y:-size*0.18)
            // Stripes
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius:1)
                    .fill(i%2==0 ? Color(hex:"f1f5f9") : Color(hex:"1e3a8a"))
                    .frame(width:size*0.14,height:size*0.22)
                    .offset(x:size*(CGFloat(i)*0.16 - 0.24),y:-size*0.18)
                    .rotationEffect(.degrees(-15))
            }
            // Play button
            Path { p in
                p.move(to:.init(x:size*0.34,y:size*0.30))
                p.addLine(to:.init(x:size*0.34,y:size*0.60))
                p.addLine(to:.init(x:size*0.68,y:size*0.45))
                p.closeSubpath()
            }.fill(Color.white.opacity(0.92))
            // "1st" badge
            Circle().fill(Color(hex:"f59e0b")).frame(width:size*0.28).offset(x:size*0.28,y:-size*0.28)
            Text("1st").font(.system(size:size*0.11,weight:.black)).foregroundColor(.black).offset(x:size*0.28,y:-size*0.28)
        }
    }
}

private struct ContentGrinderArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(hex:"0f172a")).frame(width:size*0.88)
            Circle().stroke(LinearGradient(colors:[Color(hex:"60a5fa"),Color(hex:"1d4ed8")], startPoint:.topLeading, endPoint:.bottomTrailing), lineWidth:size*0.06).frame(width:size*0.88)
            ForEach(0..<6) { i in
                let angle = Double(i)*60 * .pi/180
                Circle().fill(Color(hex:"0f172a")).frame(width:size*0.18)
                    .offset(x:CGFloat(cos(angle))*size*0.30,y:CGFloat(sin(angle))*size*0.30)
                Rectangle().fill(Color(hex:"60a5fa")).frame(width:size*0.04,height:size*0.22)
                    .offset(x:CGFloat(cos(angle))*size*0.22,y:CGFloat(sin(angle))*size*0.22)
                    .rotationEffect(.degrees(Double(i)*60+90))
            }
            Circle().fill(Color(hex:"1e40af")).frame(width:size*0.30)
            Text("50").font(.system(size:size*0.14,weight:.black)).foregroundColor(.white)
        }
    }
}

private struct ProlificCreatorArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:10)
                .fill(LinearGradient(colors:[Color(hex:"93c5fd"),Color(hex:"1d4ed8")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.88,height:size*0.72)
                .offset(y:size*0.10)
            // Viewfinder bump
            RoundedRectangle(cornerRadius:6)
                .fill(Color(hex:"1d4ed8"))
                .frame(width:size*0.34,height:size*0.22)
                .offset(y:-size*0.24)
            // Lens
            Circle().fill(Color(hex:"0f172a")).frame(width:size*0.50).offset(y:size*0.12)
            Circle().fill(Color(hex:"0c1a50")).frame(width:size*0.38).offset(y:size*0.12)
            Circle()
                .fill(RadialGradient(colors:[Color(hex:"bfdbfe"),Color(hex:"1d4ed8"),Color(hex:"0c1a50")], center:.init(x:0.35,y:0.35), startRadius:0, endRadius:size*0.22))
                .frame(width:size*0.26).offset(y:size*0.12)
            // Flash
            RoundedRectangle(cornerRadius:2).fill(Color(hex:"fef08a")).frame(width:size*0.12,height:size*0.10).offset(x:size*0.30,y:-size*0.12)
            // 100 badge
            Circle().fill(Color(hex:"f59e0b")).frame(width:size*0.30).offset(x:size*0.32,y:-size*0.30)
            Text("100").font(.system(size:size*0.09,weight:.black)).foregroundColor(.black).offset(x:size*0.32,y:-size*0.30)
        }
    }
}

// MARK: - ENGAGEMENT

private struct XPClimberArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:6).fill(Color(hex:"052e16").opacity(0.9)).frame(width:size*0.88,height:size*0.80)
            // Bars
            let heights: [CGFloat] = [0.20,0.32,0.48,0.68]
            let colors: [Color] = [.init(hex:"22c55e").opacity(0.55),.init(hex:"22c55e").opacity(0.7),.init(hex:"22c55e").opacity(0.85),.init(hex:"4ade80")]
            ForEach(0..<4) { i in
                let h = heights[i]*size
                RoundedRectangle(cornerRadius:2)
                    .fill(i==3 ? LinearGradient(colors:[Color(hex:"166534"),Color(hex:"4ade80")], startPoint:.bottom, endPoint:.top) : LinearGradient(colors:[colors[i],colors[i]], startPoint:.bottom, endPoint:.top))
                    .frame(width:size*0.12,height:h)
                    .offset(x:size*(CGFloat(i)*0.18 - 0.26),y:size*(0.40-heights[i]*0.50))
            }
            // Trend arrow
            Path { p in
                p.move(to:.init(x:size*0.14,y:size*0.60))
                p.addLine(to:.init(x:size*0.34,y:size*0.44))
                p.addLine(to:.init(x:size*0.54,y:size*0.30))
                p.addLine(to:.init(x:size*0.76,y:size*0.14))
            }.stroke(Color(hex:"4ade80"), lineWidth:size*0.05)
            // XP chip
            Capsule().fill(Color(hex:"4ade80")).frame(width:size*0.34,height:size*0.18).offset(x:-size*0.22,y:-size*0.32)
            Text("XP 1K").font(.system(size:size*0.09,weight:.black)).foregroundColor(.black).offset(x:-size*0.22,y:-size*0.32)
        }
    }
}

private struct CloutEarnerArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Hexagon gem
            RegularPolygon(sides:6)
                .fill(RadialGradient(colors:[Color(hex:"bae6fd"),Color(hex:"0ea5e9"),Color(hex:"0c4a6e")], center:.init(x:0.5,y:0.35), startRadius:0, endRadius:size*0.50))
                .frame(width:size*0.90,height:size*0.90)
            // Facets
            Path { p in
                p.move(to:.init(x:size*0.50,y:size*0.05))
                p.addLine(to:.init(x:size*0.90,y:size*0.28))
                p.addLine(to:.init(x:size*0.50,y:size*0.50))
            }.fill(Color.white.opacity(0.14))
            // Shine
            RegularPolygon(sides:4)
                .fill(LinearGradient(colors:[Color.white.opacity(0.45),Color.white.opacity(0)], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.52,height:size*0.52)
            Circle().fill(Color.white.opacity(0.5)).frame(width:size*0.20)
        }
    }
}

private struct CloutChampionArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Trophy body
            Path { p in
                p.move(to:.init(x:size*0.32,y:size*0.14))
                p.addLine(to:.init(x:size*0.68,y:size*0.14))
                p.addLine(to:.init(x:size*0.64,y:size*0.62))
                p.addQuadCurve(to:.init(x:size*0.36,y:size*0.62), control:.init(x:size*0.50,y:size*0.78))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"fef08a"),Color(hex:"f59e0b"),Color(hex:"78350f")], startPoint:.top, endPoint:.bottom))
            // Handles
            Path { p in
                p.move(to:.init(x:size*0.32,y:size*0.22))
                p.addQuadCurve(to:.init(x:size*0.32,y:size*0.56), control:.init(x:size*0.10,y:size*0.40))
            }.stroke(Color(hex:"f59e0b"), lineWidth:size*0.08)
            Path { p in
                p.move(to:.init(x:size*0.68,y:size*0.22))
                p.addQuadCurve(to:.init(x:size*0.68,y:size*0.56), control:.init(x:size*0.90,y:size*0.40))
            }.stroke(Color(hex:"f59e0b"), lineWidth:size*0.08)
            // Stem + base
            Rectangle().fill(Color(hex:"92400e")).frame(width:size*0.14,height:size*0.12).offset(y:size*0.38)
            RoundedRectangle(cornerRadius:3).fill(Color(hex:"78350f")).frame(width:size*0.60,height:size*0.12).offset(y:size*0.44)
            // Star
            StarShape(points:5).fill(Color.white.opacity(0.75)).frame(width:size*0.32,height:size*0.32).offset(y:size*0.10)
        }
    }
}

// MARK: - TIPPER

private struct TipperArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors:[Color(hex:"fbbf24"),Color(hex:"92400e")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.80)
            Text("🪙").font(.system(size:size*0.46))
        }
    }
}
private struct BigTipperArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"fbbf24"),Color(hex:"f59e0b")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.82)
            ForEach(0..<3) { i in
                Text("🪙").font(.system(size:size*0.28)).offset(x:size*CGFloat(i-1)*0.22,y:size*CGFloat(i%2==0 ? -0.06 : 0.08))
            }
        }
    }
}
private struct WhaleArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"0ea5e9"),Color(hex:"0c4a6e")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.86)
            Text("🐳").font(.system(size:size*0.50))
        }
    }
}

// MARK: - SOCIAL

private struct NetworkerArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            let positions: [(CGFloat,CGFloat,CGFloat)] = [(0.50,0.30,0.20),(0.22,0.68,0.16),(0.78,0.68,0.16),(0.50,0.86,0.14)]
            // Lines
            Path { p in
                p.move(to:.init(x:size*0.50,y:size*0.30)); p.addLine(to:.init(x:size*0.22,y:size*0.68))
                p.move(to:.init(x:size*0.50,y:size*0.30)); p.addLine(to:.init(x:size*0.78,y:size*0.68))
                p.move(to:.init(x:size*0.22,y:size*0.68)); p.addLine(to:.init(x:size*0.50,y:size*0.86))
                p.move(to:.init(x:size*0.78,y:size*0.68)); p.addLine(to:.init(x:size*0.50,y:size*0.86))
                p.move(to:.init(x:size*0.22,y:size*0.68)); p.addLine(to:.init(x:size*0.78,y:size*0.68))
            }.stroke(Color(hex:"22d3ee").opacity(0.45), lineWidth:size*0.04)
            // Nodes
            ForEach(0..<positions.count, id:\.self) { i in
                let pos = positions[i]
                Circle()
                    .fill(RadialGradient(colors:[Color(hex:"67e8f9"),Color(hex:"0e7490")], center:.center, startRadius:0, endRadius:size*pos.2))
                    .frame(width:size*pos.2*2,height:size*pos.2*2)
                    .offset(x:size*(pos.0-0.50),y:size*(pos.1-0.50))
                    .opacity(1.0 - Double(i)*0.08)
            }
        }
    }
}

private struct PopularArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<12) { i in
                let angle = Double(i)*30 * .pi/180
                RoundedRectangle(cornerRadius:2)
                    .fill(i%2==0 ? Color(hex:"06b6d4") : Color(hex:"fde68a"))
                    .frame(width:size*0.06,height:size*0.16)
                    .offset(y:-size*0.42)
                    .rotationEffect(.degrees(Double(i)*30))
            }
            Circle()
                .fill(RadialGradient(colors:[Color(hex:"fef08a"),Color(hex:"06b6d4"),Color(hex:"0e7490")], center:.init(x:0.5,y:0.45), startRadius:0, endRadius:size*0.38))
                .frame(width:size*0.68)
            VStack(spacing:0) {
                Text("FOLLOWERS").font(.system(size:size*0.09,weight:.heavy)).foregroundColor(.white.opacity(0.65))
                Text("1K").font(.system(size:size*0.22,weight:.black)).foregroundColor(.white)
            }
        }
    }
}

private struct InfluencerArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Ellipse().stroke(Color(hex:"0284c7").opacity(0.5-Double(i)*0.1), lineWidth:1.5)
                    .frame(width:size*0.92,height:size*0.36)
                    .rotationEffect(.degrees(Double(i)*30 - 30))
            }
            Circle().fill(Color(hex:"fbbf24")).frame(width:size*0.16).offset(x:size*0.46)
            Circle().fill(Color(hex:"f472b6")).frame(width:size*0.14).offset(y:-size*0.44)
            Circle()
                .fill(RadialGradient(colors:[Color(hex:"e0f2fe"),Color(hex:"0284c7"),Color(hex:"0c4a6e")], center:.init(x:0.5,y:0.4), startRadius:0, endRadius:size*0.26))
                .frame(width:size*0.46)
            StarShape(points:5).fill(Color.white.opacity(0.88)).frame(width:size*0.30,height:size*0.30)
        }
    }
}

// MARK: - SUBSCRIPTION

private struct FirstSubArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:8)
                .fill(LinearGradient(colors:[Color(hex:"7c3aed"),Color(hex:"3b0764")], startPoint:.topLeading, endPoint:.bottomTrailing))
                .frame(width:size*0.82,height:size*0.72)
            Text("⭐").font(.system(size:size*0.30)).offset(y:-size*0.10)
            Text("SUB").font(.system(size:size*0.14,weight:.black)).foregroundColor(Color(hex:"c084fc")).offset(y:size*0.20)
        }
    }
}
private struct LoyalSupporterArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"a855f7"),Color(hex:"3b0764")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.82)
            Text("💜").font(.system(size:size*0.46))
        }
    }
}
private struct SuperFanArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"c084fc"),Color(hex:"7c3aed")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.82)
            Text("🌟").font(.system(size:size*0.46))
        }
    }
}
private struct FirstSubscriberArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:8).fill(Color(hex:"0f172a")).frame(width:size*0.82,height:size*0.72)
            RoundedRectangle(cornerRadius:8).stroke(Color(hex:"06b6d4").opacity(0.5), lineWidth:1.5).frame(width:size*0.82,height:size*0.72)
            Text("1").font(.system(size:size*0.40,weight:.black)).foregroundColor(Color(hex:"06b6d4"))
            Text("subscriber").font(.system(size:size*0.10,weight:.bold)).foregroundColor(Color(hex:"06b6d4").opacity(0.5)).offset(y:size*0.22)
        }
    }
}
private struct GrowingCommunityArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"0ea5e9"),Color(hex:"0369a1")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.82)
            Text("📈").font(.system(size:size*0.44))
        }
    }
}
private struct SubscriberKingArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"fbbf24"),Color(hex:"0ea5e9")], startPoint:.topLeading, endPoint:.bottomTrailing)).frame(width:size*0.82)
            Text("👑").font(.system(size:size*0.46))
        }
    }
}

// MARK: - TIER / REPUTATION

private struct TierArt: View {
    let label: String; let color: Color; let size: CGFloat
    var body: some View {
        ZStack {
            ShieldShape()
                .fill(LinearGradient(colors:[color.opacity(0.3),color.opacity(0.08)], startPoint:.top, endPoint:.bottom))
                .frame(width:size*0.80,height:size*0.88)
            ShieldShape()
                .stroke(color.opacity(0.55), lineWidth:size*0.04)
                .frame(width:size*0.80,height:size*0.88)
            Text(label)
                .font(.system(size:size*(label.count > 1 ? 0.20 : 0.28),weight:.black))
                .foregroundColor(color)
        }
    }
}

private struct VeteranArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Ribbon
            Path { p in
                p.move(to:.init(x:size*0.36,y:size*0.14))
                p.addLine(to:.init(x:size*0.42,y:size*0.40))
                p.addLine(to:.init(x:size*0.50,y:size*0.32))
                p.addLine(to:.init(x:size*0.58,y:size*0.40))
                p.addLine(to:.init(x:size*0.64,y:size*0.14))
                p.closeSubpath()
            }.fill(Color(hex:"4ade80"))
            // Medal disc
            Circle().fill(Color(hex:"052e16")).frame(width:size*0.72)
            Circle().stroke(LinearGradient(colors:[Color(hex:"86efac"),Color(hex:"15803d")], startPoint:.topLeading, endPoint:.bottomTrailing), lineWidth:size*0.06).frame(width:size*0.72)
            Circle().fill(LinearGradient(colors:[Color(hex:"86efac"),Color(hex:"15803d")], startPoint:.topLeading, endPoint:.bottomTrailing)).frame(width:size*0.50).offset(y:size*0.10)
            // Star
            StarShape(points:5).fill(Color.white.opacity(0.9)).frame(width:size*0.30,height:size*0.30).offset(y:size*0.10)
        }
    }
}

private struct EliteArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Shield
            RegularPolygon(sides:6)
                .fill(Color(hex:"0f0028"))
                .frame(width:size*0.88,height:size*0.88)
            RegularPolygon(sides:6)
                .stroke(RadialGradient(colors:[Color(hex:"e9d5ff"),Color(hex:"a855f7"),Color(hex:"3b0764")], center:.init(x:0.5,y:0.4), startRadius:0, endRadius:size*0.44), lineWidth:size*0.05)
                .frame(width:size*0.88,height:size*0.88)
            // Trident
            Rectangle().fill(Color(hex:"c084fc")).frame(width:size*0.06,height:size*0.50).offset(y:size*0.06)
            Rectangle().fill(Color(hex:"c084fc")).frame(width:size*0.06,height:size*0.24).offset(x:-size*0.20,y:-size*0.06)
            Rectangle().fill(Color(hex:"c084fc")).frame(width:size*0.06,height:size*0.24).offset(x:size*0.20,y:-size*0.06)
            Path { p in
                p.move(to:.init(x:size*0.30,y:size*0.16)); p.addLine(to:.init(x:size*0.30,y:size*0.26))
                p.move(to:.init(x:size*0.30,y:size*0.16)); p.addLine(to:.init(x:size*0.42,y:size*0.22))
                p.move(to:.init(x:size*0.70,y:size*0.16)); p.addLine(to:.init(x:size*0.70,y:size*0.26))
                p.move(to:.init(x:size*0.70,y:size*0.16)); p.addLine(to:.init(x:size*0.58,y:size*0.22))
                p.move(to:.init(x:size*0.50,y:size*0.10)); p.addLine(to:.init(x:size*0.44,y:size*0.22))
                p.move(to:.init(x:size*0.50,y:size*0.10)); p.addLine(to:.init(x:size*0.56,y:size*0.22))
            }.stroke(Color(hex:"c084fc"), lineWidth:size*0.04)
            // Gem
            Circle().fill(RadialGradient(colors:[Color(hex:"e9d5ff"),Color(hex:"a855f7"),Color(hex:"3b0764")], center:.init(x:0.35,y:0.35), startRadius:0, endRadius:size*0.14)).frame(width:size*0.22).offset(y:size*0.20)
        }
    }
}

private struct LegendaryStatusArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Pentagon glow
            RegularPolygon(sides:5)
                .fill(Color(hex:"fbbf24").opacity(0.12))
                .frame(width:size*0.92,height:size*0.92)
                .blur(radius:size*0.08)
            RegularPolygon(sides:5)
                .fill(Color(hex:"1c0a00"))
                .frame(width:size*0.88,height:size*0.88)
            RegularPolygon(sides:5)
                .stroke(LinearGradient(colors:[Color(hex:"fef3c7"),Color(hex:"f59e0b"),Color(hex:"78350f")], startPoint:.top, endPoint:.bottom), lineWidth:size*0.04)
                .frame(width:size*0.88,height:size*0.88)
            // Crown detail
            Path { p in
                p.move(to:.init(x:size*0.32,y:size*0.36))
                p.addLine(to:.init(x:size*0.38,y:size*0.24))
                p.addLine(to:.init(x:size*0.50,y:size*0.34))
                p.addLine(to:.init(x:size*0.62,y:size*0.24))
                p.addLine(to:.init(x:size*0.68,y:size*0.36))
            }.stroke(Color(hex:"fde68a"), lineWidth:size*0.05)
            // Inner flame
            Path { p in
                p.move(to:.init(x:size*0.50,y:size*0.18))
                p.addQuadCurve(to:.init(x:size*0.60,y:size*0.50), control:.init(x:size*0.66,y:size*0.32))
                p.addQuadCurve(to:.init(x:size*0.50,y:size*0.68), control:.init(x:size*0.58,y:size*0.65))
                p.addQuadCurve(to:.init(x:size*0.40,y:size*0.50), control:.init(x:size*0.42,y:size*0.65))
                p.addQuadCurve(to:.init(x:size*0.50,y:size*0.18), control:.init(x:size*0.34,y:size*0.32))
            }.fill(LinearGradient(colors:[Color(hex:"fef3c7"),Color(hex:"f59e0b"),Color(hex:"92400e")], startPoint:.top, endPoint:.bottom).opacity(0.9))
            // Jewels
            ForEach([-0.22,0.0,0.22], id:\.self) { x in
                Circle().fill(Color(hex:"f59e0b")).frame(width:size*0.16).offset(x:size*x,y:size*0.30)
            }
        }
    }
}

private struct FounderCrestArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            ShieldShape()
                .fill(LinearGradient(colors:[Color(hex:"fbbf24").opacity(0.22),Color(hex:"92400e").opacity(0.10)], startPoint:.top, endPoint:.bottom))
                .frame(width:size*0.82,height:size*0.90)
            ShieldShape()
                .stroke(LinearGradient(colors:[Color(hex:"fef3c7"),Color(hex:"f59e0b"),Color(hex:"78350f")], startPoint:.top, endPoint:.bottom), lineWidth:size*0.05)
                .frame(width:size*0.82,height:size*0.90)
            Text("FC").font(.system(size:size*0.22,weight:.black)).foregroundColor(Color(hex:"fbbf24"))
        }
    }
}

// MARK: - SPECIAL

private struct FounderBadgeArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(hex:"fbbf24").opacity(0.10)).frame(width:size*0.96).blur(radius:size*0.10)
            // Shield
            Path { p in
                let w=size; let h=size
                p.move(to:.init(x:w*0.50,y:h*0.04))
                p.addLine(to:.init(x:w*0.90,y:h*0.22))
                p.addLine(to:.init(x:w*0.90,y:h*0.56))
                p.addQuadCurve(to:.init(x:w*0.50,y:h*0.98), control:.init(x:w*0.90,y:h*0.82))
                p.addQuadCurve(to:.init(x:w*0.10,y:h*0.56), control:.init(x:w*0.10,y:h*0.82))
                p.addLine(to:.init(x:w*0.10,y:h*0.22))
                p.closeSubpath()
            }
            .fill(Color(hex:"1c0a00"))
            Path { p in
                let w=size; let h=size
                p.move(to:.init(x:w*0.50,y:h*0.04))
                p.addLine(to:.init(x:w*0.90,y:h*0.22))
                p.addLine(to:.init(x:w*0.90,y:h*0.56))
                p.addQuadCurve(to:.init(x:w*0.50,y:h*0.98), control:.init(x:w*0.90,y:h*0.82))
                p.addQuadCurve(to:.init(x:w*0.10,y:h*0.56), control:.init(x:w*0.10,y:h*0.82))
                p.addLine(to:.init(x:w*0.10,y:h*0.22))
                p.closeSubpath()
            }
            .stroke(LinearGradient(colors:[Color(hex:"fef3c7"),Color(hex:"fbbf24"),Color(hex:"78350f")], startPoint:.top, endPoint:.bottom), lineWidth:size*0.05)
            // "S" wordmark
            Path { p in
                p.move(to:.init(x:size*0.36,y:size*0.38))
                p.addQuadCurve(to:.init(x:size*0.36,y:size*0.29), control:.init(x:size*0.36,y:size*0.26))
                p.addQuadCurve(to:.init(x:size*0.64,y:size*0.29), control:.init(x:size*0.64,y:size*0.26))
                p.addQuadCurve(to:.init(x:size*0.64,y:size*0.44), control:.init(x:size*0.64,y:size*0.38))
                p.addQuadCurve(to:.init(x:size*0.36,y:size*0.58), control:.init(x:size*0.36,y:size*0.50))
                p.addQuadCurve(to:.init(x:size*0.36,y:size*0.68), control:.init(x:size*0.36,y:size*0.63))
                p.addQuadCurve(to:.init(x:size*0.64,y:size*0.68), control:.init(x:size*0.64,y:size*0.63))
                p.addQuadCurve(to:.init(x:size*0.64,y:size*0.60), control:.init(x:size*0.64,y:size*0.66))
            }.stroke(LinearGradient(colors:[Color(hex:"fef3c7"),Color(hex:"fbbf24"),Color(hex:"92400e")], startPoint:.top, endPoint:.bottom), lineWidth:size*0.07)
        }
    }
}

private struct BetaTesterArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Flask
            Path { p in
                p.move(to:.init(x:size*0.38,y:size*0.14))
                p.addLine(to:.init(x:size*0.38,y:size*0.50))
                p.addLine(to:.init(x:size*0.18,y:size*0.86))
                p.addQuadCurve(to:.init(x:size*0.82,y:size*0.86), control:.init(x:size*0.14,y:size*0.96))
                p.addLine(to:.init(x:size*0.62,y:size*0.50))
                p.addLine(to:.init(x:size*0.62,y:size*0.14))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"a78bfa"),Color(hex:"4c1d95")], startPoint:.topLeading, endPoint:.bottomTrailing))
            // Liquid
            Path { p in
                p.move(to:.init(x:size*0.20,y:size*0.84))
                p.addQuadCurve(to:.init(x:size*0.50,y:size*0.72), control:.init(x:size*0.35,y:size*0.68))
                p.addQuadCurve(to:.init(x:size*0.80,y:size*0.84), control:.init(x:size*0.65,y:size*0.68))
                p.addLine(to:.init(x:size*0.82,y:size*0.86))
                p.addQuadCurve(to:.init(x:size*0.18,y:size*0.86), control:.init(x:size*0.14,y:size*0.96))
                p.closeSubpath()
            }.fill(LinearGradient(colors:[Color(hex:"7c3aed"),Color(hex:"4c1d95")], startPoint:.leading, endPoint:.trailing).opacity(0.9))
            // Neck
            RoundedRectangle(cornerRadius:4).fill(Color(hex:"5b21b6")).frame(width:size*0.36,height:size*0.12).offset(y:-size*0.38)
            // Beta symbol
            Text("β").font(.system(size:size*0.24,weight:.black,design:.serif)).foregroundColor(Color(hex:"e9d5ff")).offset(y:size*0.14)
            // Sparkle
            StarShape(points:8).fill(Color(hex:"fbbf24").opacity(0.9)).frame(width:size*0.18,height:size*0.18).offset(x:size*0.28,y:-size*0.32)
        }
    }
}

private struct EarlyAdopterArt: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Color(hex:"818cf8"),Color(hex:"3730a3")], startPoint:.top, endPoint:.bottom)).frame(width:size*0.82)
            Text("🚀").font(.system(size:size*0.44))
        }
    }
}

// MARK: - SIGNAL

private struct SignalArt: View {
    let kind: SignalKind; let grade: SignalGrade; let size: CGFloat
    var body: some View {
        ZStack {
            // Hex background
            RegularPolygon(sides:6)
                .fill(grade.bg)
                .frame(width:size*0.94,height:size*0.94)
            RegularPolygon(sides:6)
                .stroke(LinearGradient(colors:[grade.color3,grade.color1,grade.color2], startPoint:.topLeading, endPoint:.bottomTrailing), lineWidth:size*0.05)
                .frame(width:size*0.94,height:size*0.94)
            // Kind artwork
            Group {
                switch kind {
                case .partnerHypes:
                    // Satellite dish
                    Path { p in
                        p.move(to:.init(x:size*0.50,y:size*0.54))
                        p.addQuadCurve(to:.init(x:size*0.26,y:size*0.22), control:.init(x:size*0.22,y:size*0.38))
                        p.move(to:.init(x:size*0.50,y:size*0.54))
                        p.addQuadCurve(to:.init(x:size*0.50,y:size*0.18), control:.init(x:size*0.40,y:size*0.28))
                        p.move(to:.init(x:size*0.50,y:size*0.54))
                        p.addQuadCurve(to:.init(x:size*0.72,y:size*0.24), control:.init(x:size*0.70,y:size*0.32))
                    }.stroke(grade.color1, lineWidth:size*0.04)
                    Rectangle().fill(grade.color1).frame(width:size*0.05,height:size*0.22).offset(y:size*0.20)
                    Rectangle().fill(grade.color1).frame(width:size*0.32,height:size*0.05).offset(y:size*0.32)
                case .singlePost:
                    Path { p in
                        p.move(to:.init(x:size*0.64,y:size*0.14))
                        p.addLine(to:.init(x:size*0.36,y:size*0.54))
                        p.addLine(to:.init(x:size*0.54,y:size*0.54))
                        p.addLine(to:.init(x:size*0.44,y:size*0.90))
                        p.addLine(to:.init(x:size*0.80,y:size*0.44))
                        p.addLine(to:.init(x:size*0.60,y:size*0.44))
                        p.closeSubpath()
                    }.fill(grade.color1)
                case .multiTier:
                    Circle().stroke(grade.color1, lineWidth:size*0.04).frame(width:size*0.72)
                    Ellipse().stroke(grade.color1.opacity(0.6), lineWidth:size*0.03).frame(width:size*0.40,height:size*0.72)
                    Rectangle().fill(grade.color1.opacity(0.5)).frame(width:size*0.72,height:size*0.03)
                case .founder:
                    ShieldShape()
                        .fill(grade.color2.opacity(0.4))
                        .frame(width:size*0.56,height:size*0.62)
                    ShieldShape()
                        .stroke(grade.color1, lineWidth:size*0.04)
                        .frame(width:size*0.56,height:size*0.62)
                    Text("S").font(.system(size:size*0.20,weight:.black)).foregroundColor(grade.color3)
                }
            }
            // Grade band
            Capsule()
                .fill(grade.color2.opacity(0.55))
                .frame(width:size*0.56,height:size*0.14)
                .offset(y:size*0.34)
            Text(gradeLabel).font(.system(size:size*0.09,weight:.heavy)).foregroundColor(grade.color3).tracking(0.5).offset(y:size*0.34)
        }
    }
    private var gradeLabel: String {
        if grade.color1 == Color(hex:"c0c0c0") { return "SILVER" }
        if grade.color1 == Color(hex:"fbbf24") { return "GOLD" }
        if grade.color1 == Color(hex:"67e8f9") { return "PLATINUM" }
        return "BRONZE"
    }
}

// MARK: - Fallback

private struct FallbackArt: View {
    let size: CGFloat
    var body: some View {
        Circle().fill(Color.white.opacity(0.08)).frame(width:size*0.80)
    }
}

// MARK: - Shape helpers

private struct StarShape: Shape {
    var points: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * 0.40
        var path = Path()
        for i in 0..<points*2 {
            let angle = (Double(i) * .pi / Double(points)) - .pi/2
            let r = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(x: center.x + CGFloat(cos(angle))*r, y: center.y + CGFloat(sin(angle))*r)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

private struct RegularPolygon: Shape {
    var sides: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<sides {
            let angle = (Double(i) * 2 * .pi / Double(sides)) - .pi/2
            let pt = CGPoint(x: center.x + CGFloat(cos(angle))*r, y: center.y + CGFloat(sin(angle))*r)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width; let h = rect.height
        p.move(to: .init(x: w*0.50, y: 0))
        p.addLine(to: .init(x: w, y: h*0.18))
        p.addLine(to: .init(x: w, y: h*0.56))
        p.addQuadCurve(to: .init(x: w*0.50, y: h), control: .init(x: w, y: h*0.84))
        p.addQuadCurve(to: .init(x: 0, y: h*0.56), control: .init(x: 0, y: h*0.84))
        p.addLine(to: .init(x: 0, y: h*0.18))
        p.closeSubpath()
        return p
    }
}

private struct RegularPolygon4: Shape {
    func path(in rect: CGRect) -> Path {
        RegularPolygon(sides: 4).path(in: rect)
    }
}
