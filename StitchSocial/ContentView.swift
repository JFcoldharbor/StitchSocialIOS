//
//  ContentView.swift
//  StitchSocial
//
//  Main app entry point with tab navigation and authentication flow
//  UPDATED: Added announcement system for platform-wide mandatory content
//  UPDATED: Added memory debug overlay (DEBUG builds only)
//  FIXED: Use @EnvironmentObject for authService to share state with parent
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    
    // MARK: - State Management
    
    @EnvironmentObject var authService: AuthService
    
    @StateObject private var videoService = VideoService()
    @StateObject private var userService = UserService()
    @State private var selectedTab: MainAppTab = .discovery
    @State private var showingOnboarding = false
    @State private var showingRecording = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // MARK: - Feed Refresh State
    @State private var homeFeedRefreshTrigger = false
    @State private var showingSuccessMessage = false
    @State private var createdVideoTitle = ""
    
    // MARK: - Announcement State (NEW)
    @ObservedObject private var announcementService = AnnouncementService.shared
    @State private var currentUserInfo: BasicUserInfo?  // FIXED: Use BasicUserInfo
    
    // MARK: - Debug State
    #if DEBUG
    @State private var showMemoryDebug = false
    #endif
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if authService.currentUser == nil {
                authenticationView
            } else if showingOnboarding {
                onboardingView
            } else {
                mainAppView
            }
        }
        .onAppear {
            initializeApp()
        }
        .onChange(of: authService.authState) { oldState, newState in
            print("🔐 CONTENTVIEW: Auth state changed from \(oldState) to \(newState)")
            if newState == .unauthenticated {
                selectedTab = .discovery
                showingOnboarding = false
                showingRecording = false
                currentUserInfo = nil
            } else if newState == .authenticated, let currentUser = authService.currentUser {
                // NEW: Check for announcements when user becomes authenticated
                Task {
                    await checkForAnnouncements(userId: currentUser.id)
                }
            }
        }
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView(
                recordingContext: .newThread,
                onVideoCreated: { videoMetadata in
                    handleVideoCreated(videoMetadata)
                },
                onCancel: {
                    showingRecording = false
                }
            )
        }
        .alert("Video Created!", isPresented: $showingSuccessMessage) {
            Button("View Feed") {
                selectedTab = .home
            }
            Button("OK") { }
        } message: {
            Text("'\(createdVideoTitle)' has been posted successfully!")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image("StitchSocialLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                
                Text("Stitch Social")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                    .scaleEffect(1.2)
                
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    private var authenticationView: some View {
        LoginView()
            .environmentObject(authService)
    }
    
    private var onboardingView: some View {
        StitchOnboardingView(
            onComplete: {
                completeOnboarding()
            },
            onSkip: {
                completeOnboarding()
            }
        )
    }
    
    // MARK: - Main App View
    
    private var mainAppView: some View {
        ZStack(alignment: .bottom) {
            switch selectedTab {
            case .home:
                HomeFeedView()
                    .environmentObject(authService)
                
            case .discovery:
                DiscoveryView()
                    .environmentObject(authService)
                
            case .progression:
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService
                )
                .environmentObject(authService)
                
            case .notifications:
                NotificationView()
                    .environmentObject(authService)
            }
            
            CustomDippedTabBar(
                selectedTab: $selectedTab,
                onTabSelected: { tab in
                    handleTabSelection(tab)
                },
                onCreateTapped: {
                    handleCreateAction()
                }
            )
            
            // MARK: - Announcement Overlay (NEW - Highest Priority)
            announcementOverlay
            
            #if DEBUG
            if showMemoryDebug {
                VStack {
                    HStack {
                        Spacer()
                        MemoryDebugOverlay()
                            .padding(.trailing, 16)
                            .padding(.top, 60)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            #endif
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #if DEBUG
        .onShake {
            showMemoryDebug.toggle()
            print("🧠 DEBUG: Memory overlay \(showMemoryDebug ? "shown" : "hidden")")
        }
        #endif
    }
    
    // MARK: - Announcement Overlay (NEW)
    
    @ViewBuilder
    private var announcementOverlay: some View {
        if announcementService.isShowingAnnouncement,
           let announcement = announcementService.currentAnnouncement {
            
            AnnouncementOverlayView(
                announcement: announcement,
                onComplete: {
                    print("📢 ANNOUNCEMENT: User completed viewing")
                    Task {
                        guard let userId = authService.currentUser?.id else { return }
                        // Mark as completed so it won't show again
                        try? await announcementService.markAsCompleted(
                            userId: userId,
                            announcementId: announcement.id,
                            watchedSeconds: announcement.minimumWatchSeconds
                        )
                        print("📢 ANNOUNCEMENT: Marked as completed")
                    }
                },
                onDismiss: {
                    Task {
                        guard let userId = authService.currentUser?.id else { return }
                        try? await announcementService.dismissAnnouncement(
                            userId: userId,
                            announcementId: announcement.id
                        )
                        print("📢 ANNOUNCEMENT: User dismissed")
                    }
                }
            )
            .id(announcement.id)  // IMPORTANT: Force view refresh when announcement changes
            .environmentObject(videoService)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .zIndex(9999)
        }
    }
    
    // MARK: - Video Creation Callback
    
    private func handleVideoCreated(_ videoMetadata: CoreVideoMetadata) {
        print("VIDEO CREATED: \(videoMetadata.title)")
        createdVideoTitle = videoMetadata.title
        homeFeedRefreshTrigger.toggle()
        showingSuccessMessage = true
        selectedTab = .home
        print("FEED REFRESH: Triggered")
    }
    
    // MARK: - Initialization
    
    private func initializeApp() {
        Task {
            do {
                let configValidation = Config.validateConfiguration()
                if !configValidation.isValid {
                    print("CONFIG WARNING: Configuration issues found:")
                    for issue in configValidation.issues {
                        print("   - \(issue)")
                    }
                }
                
                Config.printConfigurationStatus()
                
                try await initializeFirebase()
                try await checkAuthenticationState()
                checkOnboardingStatus()
                
                // NEW: Check for announcements after auth is confirmed
                if let currentUser = authService.currentUser {
                    await checkForAnnouncements(userId: currentUser.id)
                }
                
                await MainActor.run {
                    isLoading = false
                }
                
            } catch {
                await handleInitializationError(error)
            }
        }
    }
    
    // MARK: - Announcement Check (NEW)
    
    private func checkForAnnouncements(userId: String) async {
        do {
            // FIXED: Use getUser which returns BasicUserInfo
            guard let userInfo = try await userService.getUser(id: userId) else {
                print("⚠️ ANNOUNCEMENTS: Could not load user info")
                return
            }
            currentUserInfo = userInfo
            
            let accountAge = Calendar.current.dateComponents(
                [.day],
                from: userInfo.createdAt ?? Date(),
                to: Date()
            ).day ?? 0
            
            await AnnouncementService.shared.checkForCriticalAnnouncements(
                userId: userId,
                userTier: userInfo.tier.rawValue,
                accountAge: accountAge
            )
            
            let pendingCount = AnnouncementService.shared.pendingAnnouncements.count
            print("📢 ANNOUNCEMENTS: Checked for user \(userId), \(pendingCount) pending")
            
        } catch {
            print("⚠️ ANNOUNCEMENTS: Failed to check - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Firebase Initialization
    
    private func initializeFirebase() async throws {
        print("FIREBASE: Verifying initialization...")
    }
    
    // MARK: - Authentication
    
    private func checkAuthenticationState() async throws {
        print("AUTH: Checking authentication state...")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        if let currentUser = authService.currentUser {
            print("AUTH: User authenticated - \(currentUser.id)")
            try await loadUserData(userID: currentUser.id)
        } else {
            print("AUTH: No authenticated user")
        }
    }
    
    private func loadUserData(userID: String) async throws {
        do {
            if let user = try await userService.getUser(id: userID) {
                print("USER DATA: Loaded - \(user.username)")
            } else {
                print("USER DATA WARNING: User profile not found in database")
            }
        } catch let error as StitchError {
            if case .networkError(let message) = error, message.contains("timeout") {
                print("USER DATA WARNING: Load timeout - proceeding")
            } else {
                throw error
            }
        } catch {
            throw StitchError.processingError("Failed to load user data: \(error.localizedDescription)")
        }
    }
    
    private func checkOnboardingStatus() {
        // BYPASSED: Onboarding disabled for now - will replace with spotlight tutorial
        // let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        // if !hasCompletedOnboarding && authService.currentUser != nil {
        //     showingOnboarding = true
        // }
        showingOnboarding = false
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showingOnboarding = false
    }
    
    // MARK: - Tab Management
    
    private func handleTabSelection(_ tab: MainAppTab) {
        selectedTab = tab
    }
    
    // MARK: - Create Action
    
    private func handleCreateAction() {
        showingRecording = true
    }
    
    // MARK: - Error Handling
    
    private func handleInitializationError(_ error: Error) async {
        print("INIT ERROR: \(error)")
        
        let errorDescription: String
        if let stitchError = error as? StitchError {
            errorDescription = stitchError.localizedDescription
        } else {
            errorDescription = "Failed to initialize app: \(error.localizedDescription)"
        }
        
        await MainActor.run {
            self.errorMessage = errorDescription
            self.showingError = true
            self.isLoading = false
        }
    }
    
    private func retryInitialization() {
        isLoading = true
        errorMessage = nil
        showingError = false
        initializeApp()
    }
}

// MARK: - Memory Debug Overlay

struct MemoryDebugOverlay: View {
    @ObservedObject private var preloadService = VideoPreloadingService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(pressureColor)
                    .frame(width: 8, height: 8)
                
                Text(pressureText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            
            Text("Pool: \(preloadService.poolStats.totalPlayers)/\(preloadService.getPoolStatus().maxPoolSize)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            
            if preloadService.isInReducedMode {
                Text("REDUCED MODE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            
            if let currentID = preloadService.currentlyPlayingVideoID {
                Text("▶ \(currentID.prefix(6))...")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }
    
    private var pressureColor: Color {
        switch preloadService.memoryPressureLevel {
        case .normal: return .green
        case .elevated: return .yellow
        case .critical: return .orange
        case .emergency: return .red
        }
    }
    
    private var pressureText: String {
        switch preloadService.memoryPressureLevel {
        case .normal: return "MEM OK"
        case .elevated: return "MEM ⚠️"
        case .critical: return "MEM 🔶"
        case .emergency: return "MEM 🔴"
        }
    }
}

// MARK: - Shake Gesture (DEBUG only)

#if DEBUG
extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(action: action))
    }
}

struct ShakeDetector: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AuthService())
        .preferredColorScheme(.dark)
}
