//
//  SettingsView.swift - UPDATED WITH REFERRAL INTEGRATION
//  StitchSocial
//
//  Layer 8: Views - Settings Interface with Referral System
//  Dependencies: AuthService (Layer 4), ReferralButton (Layer 8), Config (Layer 1)
//  Features: Account management, referral system, sign-out, app info
//  FIXED: Improved sign-out flow - let auth state drive navigation instead of manual dismiss
//

import SwiftUI

struct SettingsView: View {
    
    // MARK: - Dependencies
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    @State private var showingSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                accountSection
                Divider().background(Color.gray.opacity(0.3))
                
                // 🆕 NEW: Social Section with Referral Button
                socialSection
                Divider().background(Color.gray.opacity(0.3))
                
                preferencesSection
                Divider().background(Color.gray.opacity(0.3))
                supportSection
                Divider().background(Color.gray.opacity(0.3))
                aboutSection
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        // FIXED: Listen for auth state changes to auto-dismiss on sign-out
        .onChange(of: authService.authState) { oldState, newState in
            if newState == .unauthenticated {
                // Auth state changed to unauthenticated, dismiss settings
                // ContentView will automatically show LoginView
                print("🔐 SETTINGS: Auth state changed to unauthenticated, dismissing")
                dismiss()
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task { await performSignOut() }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 12) {
                if let user = authService.currentUser {
                    accountInfoRow(title: "Display Name", value: user.displayName)
                    accountInfoRow(title: "Username", value: "@\(user.username)")
                    accountInfoRow(title: "Tier", value: user.tier.displayName)
                }
                
                signOutButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // 🆕 NEW: Social Section with Referral Integration
    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Social")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 12) {
                // 🎯 MAIN FEATURE: Referral Button Integration
                if let currentUser = authService.currentUser {
                    ReferralButton(userID: currentUser.id)
                        .padding(.horizontal, 4) // Small adjustment for visual alignment
                }
                
                // Additional social settings can go here
                settingsRow(
                    icon: "person.2.fill",
                    title: "Friend Suggestions",
                    subtitle: "Discover people you might know"
                ) {
                    // Future: Navigate to friend suggestions
                }
                
                settingsRow(
                    icon: "heart.fill",
                    title: "Engagement Settings",
                    subtitle: "Customize hype and interaction preferences"
                ) {
                    // Future: Navigate to engagement settings
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 12) {
                settingsRow(
                    icon: "bell",
                    title: "Notifications",
                    subtitle: "Push notifications and alerts"
                ) {
                    // Future: Navigate to notification settings
                }
                
                settingsRow(
                    icon: "eye",
                    title: "Privacy",
                    subtitle: "Account visibility and data"
                ) {
                    // Future: Navigate to privacy settings
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Support Section
    
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 12) {
                settingsRow(
                    icon: "questionmark.circle",
                    title: "Help & Support",
                    subtitle: "Get help with your account"
                ) {
                    // Future: Open support
                }
                
                settingsRow(
                    icon: "doc.text",
                    title: "Privacy Policy",
                    subtitle: "How we handle your data"
                ) {
                    // Future: Open privacy policy
                }
                
                settingsRow(
                    icon: "doc.text",
                    title: "Terms of Service",
                    subtitle: "Terms and conditions"
                ) {
                    // Future: Open terms
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Version")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text(appVersion)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("Build")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text(buildNumber)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Helper Views
    
    private func accountInfoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
    }
    
    private var signOutButton: some View {
        Button(action: { showingSignOutConfirmation = true }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                
                Text("Sign Out")
                    .font(.system(size: 16, weight: .medium))
                
                Spacer()
                
                if isSigningOut {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
            }
            .foregroundColor(isSigningOut ? .gray : .red)
            .padding(.vertical, 12)
        }
        .disabled(isSigningOut)
    }
    
    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Actions
    
    private func performSignOut() async {
        isSigningOut = true
        
        print("🔐 SETTINGS: Starting sign-out process")
        
        do {
            try await authService.signOut()
            
            // FIXED: Don't manually dismiss here
            // The .onChange(of: authService.authState) will handle dismissal
            // when authState changes to .unauthenticated
            // This ensures proper cleanup and state synchronization
            
            print("✅ SETTINGS: Sign-out successful, waiting for auth state change")
            
            // Note: isSigningOut doesn't need to be reset because the view will be dismissed
            // and deallocated once auth state changes
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to sign out: \(error.localizedDescription)"
                showingError = true
                isSigningOut = false
            }
            print("❌ SETTINGS: Sign-out failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - App Info
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthService())
}
