//
//  SettingsView.swift
//  StitchSocial
//
//  Full-page settings with wallet, subscriptions, ads, and account management
//

import SwiftUI

struct SettingsView: View {
    
    // MARK: - Dependencies
    
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coinService = HypeCoinService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var suggestionService = SuggestionService()
    
    // MARK: - State
    
    @State private var showingSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Navigation States
    @State private var showingManageAccount = false
    @State private var showingWallet = false
    @State private var showingMySubscriptions = false
    @State private var showingMySubscribers = false
    @State private var showingAdOpportunities = false
    @State private var showingCashOut = false
    @State private var showingSubscriptionSettings = false
    @State private var showingCommunitySettings = false
    @State private var showingPrivacySettings = false
    @State private var showingFriendSuggestions = false
    
    // Preferences
    @State private var isHapticEnabled = UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled")
    @State private var isNotificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    
    // MARK: - Computed Properties
    
    private var currentUser: BasicUserInfo? {
        authService.currentUser
    }
    
    private var isCreator: Bool {
        if SubscriptionService.shared.isDeveloper { return true }
        guard let user = currentUser else { return false }
        return AdRevenueShare.canAccessAds(tier: user.tier)
    }
    
    private var coinBalance: Int {
        coinService.balance?.availableCoins ?? 0
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader
                        .padding(.top, 8)
                    
                    // Wallet Section
                    walletSection
                    
                    // Creator Section (Influencer+)
                    if isCreator {
                        creatorSection
                    }
                    
                    // Subscriptions Section
                    subscriptionsSection
                    
                    // Social Section
                    socialSection
                    
                    // Preferences Section
                    preferencesSection
                    
                    // Support Section
                    supportSection
                    
                    // About Section
                    aboutSection
                    
                    // Sign Out
                    signOutButton
                        .padding(.top, 8)
                    
                    // Bottom Spacing
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(
                leading: Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                    }
                    .foregroundColor(.cyan)
                }
            )
        }
        .preferredColorScheme(.dark)
        .task {
            await loadData()
        }
        .onChange(of: authService.authState) { _, newState in
            if newState == .unauthenticated {
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
        // Full Screen Covers
        .fullScreenCover(isPresented: $showingManageAccount) {
            if let user = currentUser {
                AccountWebView.account(userID: user.id) {
                    Task { try? await HypeCoinService.shared.syncBalance(userID: user.id) }
                }
            }
        }
        .fullScreenCover(isPresented: $showingWallet) {
            if let user = currentUser {
                WalletView(userID: user.id, userTier: user.tier)
            }
        }
        .fullScreenCover(isPresented: $showingMySubscriptions) {
            if let user = currentUser {
                MySubscriptionsView(userID: user.id)
            }
        }
        .fullScreenCover(isPresented: $showingAdOpportunities) {
            if let user = currentUser {
                AdOpportunitiesView(user: user)
            }
        }
        .sheet(isPresented: $showingCashOut) {
            if let user = currentUser {
                CashOutSheet(
                    userID: user.id,
                    userTier: user.tier,
                    availableCoins: coinBalance
                )
            }
        }
        .sheet(isPresented: $showingCommunitySettings) {
            if let user = currentUser {
                CreatorCommunitySettingsView(
                    creatorID: user.id,
                    creatorUsername: user.username,
                    creatorDisplayName: user.displayName,
                    creatorTier: user.tier
                )
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            if let user = currentUser {
                // Avatar
                AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                
                // Name & Username
                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Tier Badge
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(user.tier.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Wallet Section
    
    private var walletSection: some View {
        SettingsSection(title: "WALLET", icon: "creditcard.fill", iconColor: .yellow) {
            // Coin Balance Card
            Button(action: { showingWallet = true }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        
                        Text("🔥")
                            .font(.system(size: 20))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hype Coins")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("\(coinBalance) coins")
                            .font(.subheadline)
                            .foregroundColor(.yellow)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Manage Account (Web)
            SettingsRow(
                icon: "globe",
                title: "Manage Account",
                subtitle: "Profile, billing & security",
                iconColor: .cyan
            ) {
                showingManageAccount = true
            }
            
            // Cash Out (Creators only)
            if isCreator {
                SettingsRow(
                    icon: "banknote",
                    title: "Cash Out",
                    subtitle: "Withdraw your earnings",
                    iconColor: .green
                ) {
                    showingCashOut = true
                }
            }
        }
    }
    
    // MARK: - Creator Section
    
    private var creatorSection: some View {
        SettingsSection(title: "CREATOR", icon: "star.circle.fill", iconColor: .purple) {
            // Ad Opportunities
            SettingsRow(
                icon: "dollarsign.circle.fill",
                title: "Ad Opportunities",
                subtitle: "Brand partnerships",
                iconColor: .green
            ) {
                showingAdOpportunities = true
            }
            
            // My Subscribers
            SettingsRow(
                icon: "person.2.fill",
                title: "My Subscribers",
                subtitle: "People subscribed to you",
                iconColor: .pink
            ) {
                showingMySubscribers = true
            }
            
            // Subscription Settings
            SettingsRow(
                icon: "gearshape.fill",
                title: "Subscription Settings",
                subtitle: "Set prices & tiers",
                iconColor: .orange
            ) {
                showingSubscriptionSettings = true
            }
            
            // Community Settings
            SettingsRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "My Community",
                subtitle: "Create & manage your community",
                iconColor: .cyan
            ) {
                showingCommunitySettings = true
            }
            
            // Revenue Share Info
            if let user = currentUser {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sub Revenue")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("\(Int(SubscriptionRevenueShare.creatorShare(for: user.tier) * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ad Revenue")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("\(Int(AdRevenueShare.creatorShare(for: user.tier) * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Subscriptions Section
    
    private var subscriptionsSection: some View {
        SettingsSection(title: "SUBSCRIPTIONS", icon: "heart.fill", iconColor: .pink) {
            SettingsRow(
                icon: "star.fill",
                title: "My Subscriptions",
                subtitle: "Creators you support",
                iconColor: .yellow
            ) {
                showingMySubscriptions = true
            }
        }
    }
    
    // MARK: - Social Section
    
    private var socialSection: some View {
        SettingsSection(title: "SOCIAL", icon: "person.2.fill", iconColor: .blue) {
            if let user = currentUser {
                ReferralButton(userID: user.id)
            }
            
            SettingsRow(
                icon: "person.badge.plus",
                title: "People You May Know",
                subtitle: "Based on mutual connections",
                iconColor: .cyan
            ) {
                showingFriendSuggestions = true
            }
            .sheet(isPresented: $showingFriendSuggestions) {
                if let user = currentUser {
                    PeopleYouMayKnowView(userID: user.id)
                        .environmentObject(authService)
                }
            }
            
            SettingsRow(
                icon: "link",
                title: "Connected Accounts",
                subtitle: "Link social media",
                iconColor: .purple
            ) {
                // Navigate to connected accounts
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        SettingsSection(title: "PREFERENCES", icon: "slider.horizontal.3", iconColor: .gray) {
            // Haptic Feedback Toggle
            SettingsToggleRow(
                icon: "iphone.radiowaves.left.and.right",
                title: "Haptic Feedback",
                subtitle: "Vibrations",
                iconColor: .cyan,
                isOn: $isHapticEnabled
            ) { newValue in
                UserDefaults.standard.set(newValue, forKey: "hapticFeedbackEnabled")
            }
            
            // Notifications Toggle
            SettingsToggleRow(
                icon: "bell.fill",
                title: "Notifications",
                subtitle: "Push alerts",
                iconColor: .red,
                isOn: $isNotificationsEnabled
            ) { newValue in
                UserDefaults.standard.set(newValue, forKey: "notificationsEnabled")
            }
            
            SettingsRow(
                icon: "eye.fill",
                title: "Privacy",
                subtitle: "Account visibility",
                iconColor: .blue
            ) {
                showingPrivacySettings = true
            }
            .sheet(isPresented: $showingPrivacySettings) {
                if let user = currentUser {
                    PrivacySettingsView(userID: user.id)
                }
            }
        }
    }
    
    // MARK: - Support Section
    
    private var supportSection: some View {
        SettingsSection(title: "SUPPORT", icon: "questionmark.circle.fill", iconColor: .blue) {
            SettingsRow(
                icon: "questionmark.circle",
                title: "Help & Support",
                subtitle: "Get help",
                iconColor: .blue
            ) {
                // Open support
            }
            
            SettingsRow(
                icon: "doc.text",
                title: "Privacy Policy",
                subtitle: "How we use data",
                iconColor: .gray
            ) {
                // Open privacy policy
            }
            
            SettingsRow(
                icon: "doc.text",
                title: "Terms of Service",
                subtitle: "Terms & conditions",
                iconColor: .gray
            ) {
                // Open terms
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        SettingsSection(title: "ABOUT", icon: "info.circle.fill", iconColor: .gray) {
            HStack {
                Text("Version")
                    .foregroundColor(.gray)
                Spacer()
                Text(appVersion)
                    .foregroundColor(.white)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            HStack {
                Text("Build")
                    .foregroundColor(.gray)
                Spacer()
                Text(buildNumber)
                    .foregroundColor(.white)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Sign Out Button
    
    private var signOutButton: some View {
        Button(action: { showingSignOutConfirmation = true }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18))
                
                Text("Sign Out")
                    .font(.system(size: 16, weight: .medium))
                
                Spacer()
                
                if isSigningOut {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
            }
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.15))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSigningOut)
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        guard let user = currentUser else { return }
        
        do {
            _ = try await HypeCoinService.shared.fetchBalance(userID: user.id)
            _ = try await SubscriptionService.shared.fetchMySubscriptions(userID: user.id)
        } catch {
            print("⚠️ SETTINGS: Failed to load data - \(error.localizedDescription)")
        }
    }
    
    private func performSignOut() async {
        isSigningOut = true
        
        do {
            PrivacyService.shared.clearSession()
            suggestionService.clearMutualCache()
            try await authService.signOut()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to sign out: \(error.localizedDescription)"
                showingError = true
                isSigningOut = false
            }
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

// MARK: - Settings Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
            .padding(.leading, 4)
            
            // Content
            VStack(spacing: 8) {
                content
            }
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.cyan)
                .onChange(of: isOn) { _, newValue in
                    onChange?(newValue)
                }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthService())
}
