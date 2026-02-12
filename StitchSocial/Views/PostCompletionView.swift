//
//  PostCompletionView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/11/26.
//


//
//  PostCompletionView.swift
//  StitchSocial
//
//  Layer 8: Views - Upload Progress & Completion Screen
//  Extracted from ThreadComposer
//  Dependencies: PostCompletionEffects, VideoCoordinator
//  Features: Heat-phase progress ring, ember/confetti effects, announcement styling
//

import SwiftUI

struct PostCompletionView: View {
    
    @ObservedObject var videoCoordinator: VideoCoordinator
    let isAnnouncement: Bool
    
    // MARK: - Phase Calculation
    
    private var progressPhase: Int {
        let p = videoCoordinator.overallProgress
        if p >= 1.0 { return 4 }
        if p >= 0.7 { return 3 }
        if p >= 0.3 { return 2 }
        return 1
    }
    
    private var phaseColors: [Color] {
        switch progressPhase {
        case 1: return isAnnouncement ? [.orange, .yellow] : [.cyan, .blue]
        case 2: return [.orange, Color(red: 1.0, green: 0.4, blue: 0)]
        case 3: return [Color(red: 1.0, green: 0.27, blue: 0), .orange]
        case 4: return [.green, .cyan]
        default: return [.cyan, .blue]
        }
    }
    
    private var phaseStatusText: String {
        if isAnnouncement {
            switch progressPhase {
            case 1: return "Preparing announcement..."
            case 2: return "🔥 Heating up..."
            case 3: return "🔥🔥 Almost there!"
            case 4: return "Announcement live!"
            default: return "Creating..."
            }
        }
        switch progressPhase {
        case 1: return "Creating your thread..."
        case 2: return "🔥 Heating up..."
        case 3: return "🔥🔥 Almost there!"
        case 4: return "Thread live!"
        default: return "Creating..."
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            // Heat glow from bottom
            if progressPhase >= 2 {
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, phaseColors[0].opacity(progressPhase == 3 ? 0.25 : 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                    .opacity(progressPhase >= 2 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: progressPhase)
                }
                .ignoresSafeArea()
            }
            
            // Ember particles during phase 2-3
            if progressPhase >= 2 && progressPhase < 4 {
                EmberParticlesView(intensity: progressPhase == 3 ? 1.0 : 0.5)
            }
            
            // Confetti on complete
            if progressPhase == 4 {
                ConfettiView()
            }
            
            // Main progress card
            progressCard
        }
        .animation(.easeInOut(duration: 0.5), value: progressPhase)
    }
    
    // MARK: - Progress Card
    
    private var progressCard: some View {
        VStack(spacing: 20) {
            if progressPhase == 4 {
                completedContent
            } else {
                inProgressContent
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(phaseColors[0].opacity(progressPhase >= 2 ? 0.2 : 0.05), lineWidth: 1)
                )
                .shadow(color: phaseColors[0].opacity(progressPhase == 3 ? 0.3 : 0.1), radius: progressPhase == 3 ? 30 : 10)
        )
    }
    
    // MARK: - Completed State
    
    private var completedContent: some View {
        Group {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .green.opacity(0.4), radius: 20)
                )
                .transition(.scale.combined(with: .opacity))
            
            Text(phaseStatusText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.green)
            
            Text("Your content is now visible")
                .font(.subheadline)
                .foregroundColor(.green.opacity(0.7))
        }
    }
    
    // MARK: - In Progress State
    
    private var inProgressContent: some View {
        Group {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 110, height: 110)
                
                Circle()
                    .trim(from: 0, to: CGFloat(videoCoordinator.overallProgress))
                    .stroke(
                        LinearGradient(colors: phaseColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phaseColors[0].opacity(progressPhase == 3 ? 0.6 : 0.3), radius: progressPhase == 3 ? 16 : 8)
                    .animation(.easeInOut(duration: 0.3), value: videoCoordinator.overallProgress)
                
                Text("\(Int(videoCoordinator.overallProgress * 100))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(progressPhase == 3 ? phaseColors[0] : .white)
                    .shadow(color: progressPhase == 3 ? phaseColors[0].opacity(0.5) : .clear, radius: 8)
                    .scaleEffect(progressPhase == 3 ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: progressPhase == 3)
            }
            
            // Status text
            Text(phaseStatusText)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(progressPhase >= 2 ? phaseColors[0] : .white.opacity(0.9))
                .shadow(color: progressPhase == 3 ? phaseColors[0].opacity(0.4) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.5), value: progressPhase)
            
            // Task pill
            Text(videoCoordinator.currentTask)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(phaseColors[0].opacity(0.15), lineWidth: 1))
                )
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    
                    Capsule()
                        .fill(LinearGradient(colors: phaseColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(videoCoordinator.overallProgress)))
                        .shadow(color: phaseColors[0].opacity(progressPhase >= 2 ? 0.5 : 0.2), radius: progressPhase == 3 ? 10 : 4)
                        .animation(.easeInOut(duration: 0.3), value: videoCoordinator.overallProgress)
                }
            }
            .frame(width: 240, height: 12)
            .clipShape(Capsule())
        }
    }
}