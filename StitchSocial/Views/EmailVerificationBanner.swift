//
//  EmailVerificationBanner.swift
//  StitchSocial
//
//  Created by James Garmon on 2/16/26.
//


//
//  EmailVerificationBanner.swift
//  StitchSocial
//
//  Layer 8: Views - Non-blocking email verification prompt
//  Dependencies: AuthService (Layer 4)
//  Features: Dismissible banner, resend button, auto-dismiss on verification
//
//  CACHING: Reads AuthService.isEmailVerified (UserDefaults-backed)
//           Only calls checkEmailVerification() (network) on explicit "Check" tap
//           No polling — user-initiated refresh only to minimize reads
//

import SwiftUI

struct EmailVerificationBanner: View {
    
    @EnvironmentObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var isDismissed = false
    @State private var isChecking = false
    @State private var isResending = false
    @State private var statusMessage: String?
    @State private var pollTimer: Timer?
    
    // Don't show if verified or dismissed
    var shouldShow: Bool {
        !authService.isEmailVerified && !isDismissed && authService.isAuthenticated
    }
    
    var body: some View {
        if shouldShow {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.orange)
                    
                    // Message
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verify your email")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if let status = statusMessage {
                            Text(status)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        } else {
                            Text("Check your inbox for a verification link")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        // Resend button
                        Button(action: resendEmail) {
                            if isResending {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Resend")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.3))
                        )
                        .disabled(isResending)
                        
                        // Check button — triggers one network call
                        Button(action: checkVerification) {
                            if isChecking {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Check")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(StitchColors.primary.opacity(0.3))
                        )
                        .disabled(isChecking)
                        
                        // Dismiss button
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDismissed = true
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // User returned from email app — check immediately
                    Task { await silentCheck() }
                }
            }
        }
    }
    
    // MARK: - Auto-Polling (every 5s while banner visible)
    //
    // COST: One Auth.currentUser.reload() per poll — no Firestore reads.
    // Firebase Auth reload is lightweight (checks auth token server-side).
    // Stops automatically when verified or banner dismissed.
    
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await silentCheck() }
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    /// Check without UI feedback — auto-dismiss if verified
    private func silentCheck() async {
        let verified = await authService.checkEmailVerification()
        if verified {
            await MainActor.run {
                stopPolling()
                statusMessage = "✅ Verified!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isDismissed = true
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func resendEmail() {
        isResending = true
        statusMessage = nil
        
        Task {
            do {
                try await authService.resendVerificationEmail()
                await MainActor.run {
                    statusMessage = "Verification email sent!"
                    isResending = false
                }
                
                // Clear status after 3 seconds
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    statusMessage = nil
                }
            } catch {
                await MainActor.run {
                    statusMessage = nil
                    isResending = false
                }
            }
        }
    }
    
    private func checkVerification() {
        isChecking = true
        statusMessage = nil
        
        Task {
            let verified = await authService.checkEmailVerification()
            
            await MainActor.run {
                isChecking = false
                
                if verified {
                    statusMessage = "✅ Verified!"
                    // Auto-dismiss after confirmation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isDismissed = true
                        }
                    }
                } else {
                    statusMessage = "Not yet — check your inbox"
                    // Clear status after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        statusMessage = nil
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            EmailVerificationBanner()
                .environmentObject(AuthService())
            
            Spacer()
        }
    }
}
