//
//  CinematicRecordingButton.swift
//  StitchSocial
//
//  REDESIGNED: Matches CustomDippedTabBar create button style
//  Glassmorphism design with gradient backgrounds and shadows
//

import SwiftUI

struct CinematicRecordingButton: View {
    @Binding var isRecording: Bool
    @Binding var videoCoordinator: VideoCoordinator?
    let onRecordingComplete: () -> Void
    
    // Animation states
    @State private var pulseAnimation = false
    @State private var scaleAnimation = false
    
    // Button size (same as create button)
    private let buttonSize: CGFloat = 68
    
    var body: some View {
        Button(action: toggleRecording) {
            ZStack {
                // Main glassmorphism background (matching create button)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                isRecording ? StitchColors.recordingActive.opacity(0.8) : StitchColors.primary.opacity(0.7),
                                isRecording ? StitchColors.recordingActive.opacity(0.6) : StitchColors.secondary.opacity(1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.1),
                                        StitchColors.primary.opacity(0.4),
                                        StitchColors.secondary.opacity(1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blur(radius: 0.8)
                    )
                    .overlay(
                        // Glass border (matching create button)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.3),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .frame(width: buttonSize, height: buttonSize)
                
                // Processing ring overlay (when active)
                if let coordinator = videoCoordinator, coordinator.isProcessing {
                    Circle()
                        .trim(from: 0, to: coordinator.overallProgress)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: buttonSize + 8, height: buttonSize + 8)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: coordinator.overallProgress)
                }
                
                // Center icon
                if isRecording {
                    // Recording state: white square with rounded corners
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .opacity(pulseAnimation ? 0.7 : 1.0)
                        .shadow(color: .white.opacity(0.8), radius: 2.8)
                        .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
                } else {
                    // Idle state: record circle (matching create button plus icon style)
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .fill(StitchColors.recordingActive.opacity(0.8))
                                .frame(width: 18, height: 18)
                        )
                        .shadow(color: .white.opacity(0.8), radius: 2.8)
                        .shadow(color: StitchColors.primary.opacity(0.6), radius: 5.5)
                }
            }
        }
        .scaleEffect(scaleAnimation ? 0.85 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: scaleAnimation)
        .shadow(
            color: isRecording ? StitchColors.recordingActive.opacity(0.6) : StitchColors.primary.opacity(0.6),
            radius: 16,
            x: 0,
            y: 6
        )
        .shadow(
            color: Color.black.opacity(0.4),
            radius: 12,
            x: 0,
            y: 25
        )
        .disabled(videoCoordinator?.isProcessing == true)
        .onAppear {
            if isRecording {
                startAnimations()
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startAnimations()
            } else {
                stopAnimations()
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleRecording() {
        // Haptic feedback (matching create button)
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Button animation (matching create button)
        withAnimation(.easeInOut(duration: 0.1)) {
            scaleAnimation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scaleAnimation = false
            }
        }
        
        // Toggle recording state
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        startAnimations()
    }
    
    private func stopRecording() {
        isRecording = false
        stopAnimations()
        onRecordingComplete()
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        pulseAnimation = true
        
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
    
    private func stopAnimations() {
        pulseAnimation = false
    }
}
