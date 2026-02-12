//
//  EmberParticlesView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/11/26.
//


//
//  PostCompletionEffects.swift
//  StitchSocial
//
//  Layer 8: Views - Post Completion Particle Effects
//  Extracted from ThreadComposer for reusability
//  Features: Ember rising particles, confetti fall animation
//

import SwiftUI

// MARK: - Ember Particles View

struct EmberParticlesView: View {
    let intensity: Double
    
    @State private var embers: [EmberData] = []
    @State private var timer: Timer?
    
    struct EmberData: Identifiable {
        let id = UUID()
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
        let color: Color
    }
    
    var body: some View {
        ZStack {
            ForEach(embers) { ember in
                Circle()
                    .fill(ember.color)
                    .frame(width: ember.size, height: ember.size)
                    .position(x: ember.x, y: UIScreen.main.bounds.height)
                    .modifier(EmberRiseModifier(duration: ember.duration, delay: ember.delay))
            }
        }
        .ignoresSafeArea()
        .onAppear { startEmbers() }
        .onDisappear { stopEmbers() }
    }
    
    private func startEmbers() {
        spawnBatch()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            spawnBatch()
        }
    }
    
    private func stopEmbers() {
        timer?.invalidate()
        timer = nil
        embers.removeAll()
    }
    
    private func spawnBatch() {
        let count = intensity > 0.7 ? 6 : 3
        let colors: [Color] = [
            Color(red: 1.0, green: 0.4, blue: 0),
            Color(red: 1.0, green: 0.53, blue: 0),
            Color(red: 1.0, green: 0.67, blue: 0),
            Color(red: 1.0, green: 0.8, blue: 0),
            Color(red: 1.0, green: 0.27, blue: 0)
        ]
        let screenW = UIScreen.main.bounds.width
        
        for _ in 0..<count {
            let ember = EmberData(
                x: CGFloat.random(in: 20...(screenW - 20)),
                size: CGFloat.random(in: 3...7),
                duration: Double.random(in: 2.0...3.5),
                delay: Double.random(in: 0...0.8),
                color: colors.randomElement() ?? .orange
            )
            embers.append(ember)
        }
        
        // Cleanup old embers to prevent unbounded growth
        if embers.count > 30 {
            embers.removeFirst(count)
        }
    }
}

// MARK: - Ember Rise Modifier

struct EmberRiseModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var risen = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: risen ? -(UIScreen.main.bounds.height * 1.1) : 0)
            .opacity(risen ? 0 : 0.8)
            .scaleEffect(risen ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    risen = true
                }
            }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece] = []
    
    struct ConfettiPiece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let size: CGFloat
        let duration: Double
        let rotation: Double
    }
    
    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 0.6)
                    .position(x: piece.x, y: -10)
                    .modifier(ConfettiFallModifier(duration: piece.duration, rotation: piece.rotation))
            }
        }
        .ignoresSafeArea()
        .onAppear { spawnConfetti() }
    }
    
    private func spawnConfetti() {
        let colors: [Color] = [.cyan, .orange, .purple, .yellow, .green, .pink, .blue]
        let screenW = UIScreen.main.bounds.width
        
        for _ in 0..<20 {
            let piece = ConfettiPiece(
                x: CGFloat.random(in: 10...(screenW - 10)),
                color: colors.randomElement() ?? .cyan,
                size: CGFloat.random(in: 6...10),
                duration: Double.random(in: 2.0...3.5),
                rotation: Double.random(in: 360...1080)
            )
            pieces.append(piece)
        }
    }
}

// MARK: - Confetti Fall Modifier

struct ConfettiFallModifier: ViewModifier {
    let duration: Double
    let rotation: Double
    @State private var fallen = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: fallen ? UIScreen.main.bounds.height + 40 : 0)
            .rotationEffect(.degrees(fallen ? rotation : 0))
            .opacity(fallen ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeIn(duration: duration)) {
                    fallen = true
                }
            }
    }
}