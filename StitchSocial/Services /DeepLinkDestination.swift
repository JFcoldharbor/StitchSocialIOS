//
//  DeepLinkHandler.swift
//  StitchSocial
//
//  Layer 8: Views - Deep Link Processing for Referral System
//  Dependencies: ReferralService (Layer 4), SwiftUI
//  Features: URL scheme handling, referral code processing
//

import SwiftUI
import Foundation

// MARK: - Deep Link Destinations

enum DeepLinkDestination: Equatable {
    case referralInvite(code: String)
    case profile(userID: String)
    case video(videoID: String)
    case thread(threadID: String)
    case unknown
}

// MARK: - Deep Link Handler

@MainActor
class DeepLinkHandler: ObservableObject {
    
    // MARK: - Published State
    
    @Published var pendingReferralCode: String?
    @Published var showingReferralSignup = false
    @Published var processedLink: DeepLinkDestination?
    @Published var isProcessing = false
    
    // MARK: - URL Processing
    
    /// Process incoming deep link URL
    func handleURL(_ url: URL) {
        print("🔗 DEEP LINK: Processing URL - \(url.absoluteString)")
        
        isProcessing = true
        
        // Parse the URL and extract destination
        let destination = parseDeepLink(url)
        
        switch destination {
        case .referralInvite(let code):
            handleReferralInvite(code: code)
            
        case .profile(let userID):
            print("🔗 DEEP LINK: Navigate to profile \(userID)")
            
        case .video(let videoID):
            print("🔗 DEEP LINK: Navigate to video \(videoID)")
            
        case .thread(let threadID):
            print("🔗 DEEP LINK: Navigate to thread \(threadID)")
            
        case .unknown:
            print("❌ DEEP LINK: Unknown URL format")
        }
        
        processedLink = destination
        isProcessing = false
    }
    
    // MARK: - URL Parsing
    
    private func parseDeepLink(_ url: URL) -> DeepLinkDestination {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Check for referral invite
        if pathComponents.count >= 2 && pathComponents[0] == "invite" {
            let referralCode = pathComponents[1]
            return .referralInvite(code: referralCode)
        }
        
        // Check for profile link
        if pathComponents.count >= 2 && pathComponents[0] == "profile" {
            let userID = pathComponents[1]
            return .profile(userID: userID)
        }
        
        // Check for video link
        if pathComponents.count >= 2 && pathComponents[0] == "video" {
            let videoID = pathComponents[1]
            return .video(videoID: videoID)
        }
        
        // Check for thread link
        if pathComponents.count >= 2 && pathComponents[0] == "thread" {
            let threadID = pathComponents[1]
            return .thread(threadID: threadID)
        }
        
        return .unknown
    }
    
    // MARK: - Referral Handling
    
    private func handleReferralInvite(code: String) {
        print("🎯 DEEP LINK: Processing referral invite with code: \(code)")
        
        // Store the referral code and show signup prompt
        pendingReferralCode = code
        showingReferralSignup = true
        
        print("📝 DEEP LINK: Stored referral code for signup flow")
    }
    
    // MARK: - Helper Methods
    
    /// Get and clear pending referral code for signup flow
    func consumePendingReferralCode() -> String? {
        let code = pendingReferralCode
        pendingReferralCode = nil
        showingReferralSignup = false
        return code
    }
    
    /// Check if there's a pending referral
    var hasPendingReferral: Bool {
        pendingReferralCode != nil
    }
    
    /// Clear all pending state
    func clearPendingState() {
        pendingReferralCode = nil
        showingReferralSignup = false
        processedLink = nil
    }
}

// MARK: - Referral Signup Prompt

struct ReferralSignupPrompt: View {
    let referralCode: String
    let onSignup: (String) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                    
                    Text("You've Been Invited!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Join Stitch Social and get exclusive bonuses")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                // Benefits
                VStack(spacing: 12) {
                    benefitRow(icon: "star.fill", text: "Start with bonus clout", color: .purple)
                    benefitRow(icon: "flame.fill", text: "Enhanced hype ratings", color: .orange)
                    benefitRow(icon: "heart.fill", text: "Priority features access", color: .red)
                }
                .padding(.vertical)
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    Button(action: { onSignup(referralCode) }) {
                        Text("Sign Up with Invite")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    
                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("✕") { onDismiss() }
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func benefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}
