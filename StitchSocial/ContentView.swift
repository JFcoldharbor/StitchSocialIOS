//
//  ContentView.swift
//  StitchSocial
//
//  Main app entry point with tab navigation and authentication flow
//  UPDATED: Added memory debug overlay (DEBUG builds only)
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    
    // MARK: - State Management
    
    @StateObject private var authService = AuthService()
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
    
    // MARK: - Debug State (NEW)
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
                // App logo from Assets
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
            // Main content based on selected tab
            switch selectedTab {
            case .home:
                HomeFeedView()
                    .environmentObject(authService)
                
            case .discovery:
                // Real Firebase-integrated DiscoveryView
                DiscoveryView()
                    .environmentObject(authService)
                
            case .progression:
                // FIXED: Pass required services to ProfileView
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
            
            // Custom tab bar with modular create action
            CustomDippedTabBar(
                selectedTab: $selectedTab,
                onTabSelected: { tab in
                    handleTabSelection(tab)
                },
                onCreateTapped: {
                    handleCreateAction()
                }
            )
            
            // MARK: - Memory Debug Overlay (DEBUG only)
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
    
    // MARK: - Video Creation Callback
    
    private func handleVideoCreated(_ videoMetadata: CoreVideoMetadata) {
        print("VIDEO CREATED: \(videoMetadata.title)")
        
        // Store video title for success message
        createdVideoTitle = videoMetadata.title
        
        // Trigger feed refresh
        homeFeedRefreshTrigger.toggle()
        
        // Show success message
        showingSuccessMessage = true
        
        // Optional: Auto-navigate to home feed
        selectedTab = .home
        
        print("FEED REFRESH: Triggered")
    }
    
    // MARK: - Initialization
    
    private func initializeApp() {
        Task {
            do {
                // Initialize configuration
                let configValidation = Config.validateConfiguration()
                if !configValidation.isValid {
                    print("CONFIG WARNING: Configuration issues found:")
                    for issue in configValidation.issues {
                        print("   - \(issue)")
                    }
                }
                
                // Print configuration status
                Config.printConfigurationStatus()
                
                // Initialize Firebase and auth
                try await initializeFirebase()
                
                // Check authentication state
                try await checkAuthenticationState()
                
                // Check if user needs onboarding
                checkOnboardingStatus()
                
                await MainActor.run {
                    isLoading = false
                }
                
            } catch {
                await handleInitializationError(error)
            }
        }
    }
    
    private func initializeFirebase() async throws {
        // Firebase is already initialized in App delegate
        // Validate Firebase configuration
        guard Config.Firebase.validateConfiguration() else {
            throw StitchError.validationError("Firebase configuration invalid")
        }
        
        print("FIREBASE: Configuration validated")
    }
    
    private func checkAuthenticationState() async throws {
        do {
            // Wait for auth state to be determined
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second timeout
            
            if let currentUser = Auth.auth().currentUser {
                // User is signed in, load user data
                try await loadUserData(userID: currentUser.uid)
                
                // Update auth service with current user info
                await MainActor.run {
                    // AuthService will handle user state internally
                }
                print("AUTH: User authenticated - \(currentUser.uid)")
            } else {
                print("AUTH: No authenticated user")
            }
            
        } catch let error as StitchError {
            if case .networkError(let message) = error, message.contains("timeout") {
                print("AUTH WARNING: Auth check timeout - proceeding with current state")
            } else {
                throw error
            }
        } catch {
            throw StitchError.authenticationError("Failed to check auth state: \(error.localizedDescription)")
        }
    }
    
    private func loadUserData(userID: String) async throws {
        do {
            // Load user profile
            if let user = try await userService.getUser(id: userID) {
                // User data loaded successfully
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
        // Check if user has completed onboarding
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompletedOnboarding && authService.currentUser != nil {
            showingOnboarding = true
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showingOnboarding = false
    }
    
    // MARK: - Tab Management
    
    private func handleTabSelection(_ tab: MainAppTab) {
        selectedTab = tab
    }
    
    // MARK: - Create Action (Modular)
    
    private func handleCreateAction() {
        // This is modular - can be expanded to show action sheet, different recording modes, etc.
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
    
    // MARK: - Helper Methods
    
    private func retryInitialization() {
        isLoading = true
        errorMessage = nil
        showingError = false
        initializeApp()
    }
}

// MARK: - Memory Debug Overlay (NEW)

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

// Add this to your AppDelegate or create a UIWindow subclass
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
        .preferredColorScheme(.dark)
}
