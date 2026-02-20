//
//  ReferralButton.swift
//  StitchSocial
//
//  Layer 8: Views - Ambassador Referral Dashboard
//  Dependencies: ReferralService (Layer 4), Native iOS Share Sheet
//  Features: Full analytics dashboard, recent referrals, copy code, share sheet
//
//  CACHING: Stats loaded once on appear, cached in @State for session.
//  getUserReferralStats = 1 user doc read + 1 referrals query (max 10 docs).
//  No polling, no listeners. Refreshes only on manual pull or share action.
//

import SwiftUI

struct ReferralButton: View {
    
    // MARK: - Dependencies
    
    @StateObject private var referralService = ReferralService()
    @EnvironmentObject var authService: AuthService
    let userID: String
    
    // MARK: - State
    
    @State private var showingDashboard = false
    @State private var showingShareSheet = false
    @State private var referralLink: ReferralLink?
    @State private var isGeneratingLink = false
    
    /// Influencer+ tiers get ambassador dashboard
    private var isAmbassador: Bool {
        guard let user = authService.currentUser else { return false }
        let ambassadorTiers: Set<UserTier> = [
            .influencer, .ambassador, .elite, .partner,
            .legendary, .topCreator, .founder, .coFounder
        ]
        return ambassadorTiers.contains(user.tier)
    }
    
    var body: some View {
        if isAmbassador {
            // Full ambassador dashboard
            Button(action: { showingDashboard = true }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.4), Color.cyan.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ambassador Program")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Track referrals & earn rewards")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .fullScreenCover(isPresented: $showingDashboard) {
                ReferralDashboardView(userID: userID)
                    .environmentObject(authService)
            }
        } else {
            // Simple invite button for everyone else
            Button(action: handleSimpleShare) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        if isGeneratingLink {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        } else {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite Friends")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Share Stitch Social with friends")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isGeneratingLink)
            .sheet(isPresented: $showingShareSheet) {
                if let link = referralLink {
                    ShareSheet(items: [link.shareText])
                }
            }
        }
    }
    
    private func handleSimpleShare() {
        Task {
            isGeneratingLink = true
            do {
                let link = try await referralService.generateReferralLink(for: userID)
                await MainActor.run {
                    referralLink = link
                    isGeneratingLink = false
                    showingShareSheet = true
                }
            } catch {
                print("⚠️ REFERRAL: Failed to generate link: \(error)")
                isGeneratingLink = false
            }
        }
    }
}

// MARK: - Referral Dashboard (Full Screen)

struct ReferralDashboardView: View {
    
    let userID: String
    
    @StateObject private var referralService = ReferralService()
    @Environment(\.dismiss) private var dismiss
    
    @State private var stats: ReferralStats?
    @State private var referralLink: ReferralLink?
    @State private var isLoading = true
    @State private var isGeneratingLink = false
    @State private var showingShareSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var codeCopied = false
    @State private var animateIn = false
    
    // Cached — no re-reads unless user pulls to refresh
    @State private var hasFetchedOnce = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Gradient accent
            VStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.25), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 250)
                    .offset(y: -60)
                
                Spacer()
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Nav bar
                navBar
                
                if isLoading && !hasFetchedOnce {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Referral code card
                            codeCard
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 20)
                            
                            // Stats grid
                            statsGrid
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 20)
                            
                            // Rewards progress
                            rewardsProgress
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 20)
                            
                            // How it works
                            howItWorks
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 20)
                            
                            // Recent referrals
                            if let stats = stats, !stats.recentReferrals.isEmpty {
                                recentReferralsSection(stats.recentReferrals)
                                    .opacity(animateIn ? 1 : 0)
                                    .offset(y: animateIn ? 0 : 20)
                            }
                            
                            // Share CTA
                            shareCTA
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 20)
                            
                            Spacer().frame(height: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let link = referralLink {
                ShareSheet(items: [link.shareText])
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            guard !hasFetchedOnce else { return }
            await loadStats()
            hasFetchedOnce = true
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
    }
    
    // MARK: - Nav Bar
    
    private var navBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            
            Spacer()
            
            Text("Ambassador")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Balance spacer
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Code Card
    
    private var codeCard: some View {
        VStack(spacing: 16) {
            Text("YOUR INVITE CODE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .tracking(2)
            
            HStack(spacing: 12) {
                Text(stats?.referralCode ?? "—")
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                
                Button(action: copyCode) {
                    Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(codeCopied ? .green : .purple)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(codeCopied ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
                        )
                }
            }
            
            if stats?.referralCode.isEmpty == false {
                Text("Friends enter this code when signing up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.4), Color.cyan.opacity(0.2), Color.purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard(
                value: "\(stats?.totalReferrals ?? 0)",
                label: "Total Invites",
                icon: "person.2.fill",
                color: .cyan
            )
            
            statCard(
                value: "\(stats?.monthlyReferrals ?? 0)",
                label: "This Month",
                icon: "calendar",
                color: .green
            )
            
            statCard(
                value: "+\(stats?.cloutEarned ?? 0)",
                label: "Clout Earned",
                icon: "bolt.fill",
                color: .purple
            )
        }
    }
    
    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Rewards Progress
    
    private var rewardsProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reward Progress")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if stats?.rewardsMaxed == true {
                    Label("Maxed!", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            // Clout bar
            rewardRow(
                icon: "bolt.fill",
                label: "Clout",
                current: stats?.cloutEarned ?? 0,
                total: 1000,
                color: .purple,
                suffix: ""
            )
            
            // Hype bonus bar
            let hypePct = (stats?.hypeRatingBonus ?? 0) * 100
            rewardRow(
                icon: "flame.fill",
                label: "Hype Bonus",
                current: Int(hypePct * 10),
                total: 100,
                color: .orange,
                suffix: String(format: "+%.1f%%", hypePct)
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func rewardRow(icon: String, label: String, current: Int, total: Int, color: Color, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if suffix.isEmpty {
                    Text("\(current)/\(total)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(current >= total ? .green : color)
                } else {
                    Text(suffix)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
            }
            
            GeometryReader { geo in
                let fraction = total > 0 ? CGFloat(current) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(1.0, fraction), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    // MARK: - How It Works
    
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How It Works")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            
            howItWorksStep(number: "1", text: "Share your code with friends")
            howItWorksStep(number: "2", text: "They enter it when signing up")
            howItWorksStep(number: "3", text: "You both get rewards — they auto-follow you")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func howItWorksStep(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.purple)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.purple.opacity(0.15)))
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Recent Referrals
    
    private func recentReferralsSection(_ referrals: [ReferralInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Referrals")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(referrals.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
            }
            
            ForEach(referrals.prefix(5), id: \.id) { referral in
                referralRow(referral)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func referralRow(_ referral: ReferralInfo) -> some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(referral.status == .completed ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: referral.status == .completed ? "checkmark" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(referral.status == .completed ? .green : .yellow)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(referral.refereeUsername ?? referral.refereeID?.prefix(8).description ?? "User")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(referral.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if referral.cloutAwarded > 0 {
                Text("+\(referral.cloutAwarded)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            Text(referral.status.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(referral.status == .completed ? .green : .yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(referral.status == .completed ? Color.green.opacity(0.12) : Color.yellow.opacity(0.12))
                )
        }
    }
    
    // MARK: - Share CTA
    
    private var shareCTA: some View {
        Button(action: handleShare) {
            HStack(spacing: 10) {
                if isGeneratingLink {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                }
                
                Text("Share Your Invite Code")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.purple.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .disabled(isGeneratingLink)
        .opacity(isGeneratingLink ? 0.7 : 1)
    }
    
    // MARK: - Actions
    
    private func loadStats() async {
        isLoading = true
        do {
            let loaded = try await referralService.getUserReferralStats(userID: userID)
            await MainActor.run {
                stats = loaded
                isLoading = false
            }
        } catch {
            print("⚠️ REFERRAL DASHBOARD: Failed to load stats: \(error)")
            isLoading = false
        }
    }
    
    private func copyCode() {
        guard let code = stats?.referralCode, !code.isEmpty else { return }
        UIPasteboard.general.string = code
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            codeCopied = true
        }
        
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { codeCopied = false }
        }
    }
    
    private func handleShare() {
        Task {
            isGeneratingLink = true
            do {
                let link = try await referralService.generateReferralLink(for: userID)
                await MainActor.run {
                    referralLink = link
                    isGeneratingLink = false
                    showingShareSheet = true
                }
                
                // Refresh stats after generating link (may have created code)
                // Reuses cached user doc if code already existed — 0 extra reads
                let refreshed = try await referralService.getUserReferralStats(userID: userID)
                await MainActor.run { stats = refreshed }
                
            } catch {
                await MainActor.run {
                    isGeneratingLink = false
                    errorMessage = "Failed to generate link: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Share Sheet

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
