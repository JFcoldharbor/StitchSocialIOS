//
//  ForceUpdateView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/21/26.
//


//
//  ForceUpdateView.swift
//  StitchSocial
//
//  Layer 8: Views - Blocking update screen for outdated TestFlight builds
//  Dependencies: VersionGateService
//
//  Shows when VersionGateService.needsUpdate == true.
//  Non-dismissable when forceUpdate == true.
//  Opens TestFlight link to install latest build.
//

import SwiftUI

struct ForceUpdateView: View {
    @ObservedObject var versionGate: VersionGateService
    @State private var pulseAnimation = false
    @State private var isCheckingAgain = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color.black,
                    Color.purple.opacity(0.4),
                    Color.pink.opacity(0.2),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .onAppear { pulseAnimation = true }
                
                // Title
                Text("Update Available")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                // Message
                Text(versionGate.updateMessage)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Build info
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        buildBadge(
                            label: "Your Build",
                            value: "\(versionGate.currentBuild)",
                            color: .red
                        )
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                        
                        buildBadge(
                            label: "Required",
                            value: "\(versionGate.minimumBuild)+",
                            color: .green
                        )
                    }
                    
                    Text("v\(versionGate.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Update button
                Button {
                    openTestFlight()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                        Text("Update via TestFlight")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .padding(.horizontal, 32)
                
                // Check again button
                Button {
                    Task {
                        isCheckingAgain = true
                        await versionGate.forceCheck()
                        isCheckingAgain = false
                    }
                } label: {
                    if isCheckingAgain {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("I've already updated — check again")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Build Badge
    
    private func buildBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(width: 90)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Open TestFlight
    
    private func openTestFlight() {
        // Try the custom TestFlight URL first
        if !versionGate.testflightURL.isEmpty,
           let url = URL(string: versionGate.testflightURL) {
            UIApplication.shared.open(url)
            return
        }
        
        // Fallback: open TestFlight app directly
        if let url = URL(string: "itms-beta://") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    let service = VersionGateService.shared
    ForceUpdateView(versionGate: service)
}