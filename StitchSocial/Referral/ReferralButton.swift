//
//  ReferralButton.swift
//  StitchSocial
//
//  Layer 8: Views - Referral Button for Settings Integration
//  Dependencies: ReferralService (Layer 4), Native iOS Share Sheet
//  Features: Glassmorphism styling, native sharing, loading states
//

import SwiftUI

struct ReferralButton: View {
    
    // MARK: - Dependencies
    
    @StateObject private var referralService = ReferralService()
    let userID: String
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var isLoading = false
    @State private var showingShareSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var referralLink: ReferralLink?
    @State private var referralStats: ReferralStats?
    
    // MARK: - Animation State
    
    @State private var isPressed = false
    @State private var showingSuccess = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Main Invite Button
            Button(action: handleInviteButtonTap) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: isLoading ? "arrow.2.circlepath" : "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.purple)
                            .rotationEffect(.degrees(isLoading ? 360 : 0))
                            .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite Friends")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Get 100 clout per friend + 0.10% hype bonus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Arrow or Loading
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isPressed ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                )
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .opacity(isLoading ? 0.7 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLoading)
            .onLongPressGesture(minimumDuration: 0) {
                // Handle press completed
            } onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
            
            // Stats Display (if available)
            if let stats = referralStats {
                referralStatsView(stats)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = referralLink {
                ShareSheet(items: [link.shareText, URL(string: link.universalLink)!])
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadInitialData()
        }
    }
    
    // MARK: - Referral Stats View
    
    @ViewBuilder
    private func referralStatsView(_ stats: ReferralStats) -> some View {
        VStack(spacing: 8) {
            // Progress Bar to 1000 Clout
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Referral Rewards")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(stats.cloutEarned)/1000 clout")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(stats.rewardsMaxed ? .green : .purple)
                }
                
                ProgressView(value: Double(stats.cloutEarned), total: 1000.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: stats.rewardsMaxed ? .green : .purple))
                    .frame(height: 4)
            }
            
            // Stats Grid
            HStack(spacing: 16) {
                statItem(
                    icon: "person.2.fill",
                    value: "\(stats.completedReferrals)",
                    label: "Friends",
                    color: .green
                )
                
                statItem(
                    icon: "flame.fill",
                    value: "+\(String(format: "%.1f", stats.hypeRatingBonus * 100))%",
                    label: "Hype Bonus",
                    color: .orange
                )
                
                statItem(
                    icon: "star.fill",
                    value: "+\(stats.cloutEarned)",
                    label: "Clout Earned",
                    color: .purple
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
    
    // MARK: - Stat Item Component
    
    @ViewBuilder
    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Actions
    
    private func handleInviteButtonTap() {
        Task {
            await generateAndShareReferralLink()
        }
    }
    
    @MainActor
    private func generateAndShareReferralLink() async {
        guard !isLoading else { return }
        
        isLoading = true
        
        do {
            // Generate referral link
            let link = try await referralService.generateReferralLink(for: userID)
            referralLink = link
            
            // Load updated stats
            let stats = try await referralService.getUserReferralStats(userID: userID)
            referralStats = stats
            
            // Show share sheet
            showingShareSheet = true
            
            // Success animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingSuccess = true
            }
            
            // Reset success animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingSuccess = false
                }
            }
            
        } catch {
            errorMessage = "Failed to generate referral link: \(error.localizedDescription)"
            showingError = true
        }
        
        isLoading = false
    }
    
    private func loadInitialData() async {
        do {
            let stats = try await referralService.getUserReferralStats(userID: userID)
            await MainActor.run {
                referralStats = stats
            }
        } catch {
            print("Failed to load referral stats: \(error)")
        }
    }
}

// MARK: - FIXED: Simple ShareSheet Implementation

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [
            .assignToContact,
            .saveToCameraRoll,
            .addToReadingList,
            .print
        ]
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
            ReferralButton(userID: "preview_user_id")
            
            Spacer()
        }
        .padding()
    }
}
