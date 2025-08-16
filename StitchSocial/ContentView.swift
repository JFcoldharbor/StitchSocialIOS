//
//  ContentView.swift
//  CleanBeta
//
//  Main app entry point with tab navigation and authentication flow
//  FIXED: Removed placeholder components, using real DiscoveryView
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    
    // MARK: - State Management
    
    @StateObject private var authService = AuthService()
    @StateObject private var videoService = VideoService()
    @StateObject private var userService = UserService()
    @State private var selectedTab: MainAppTab = .home
    @State private var showingOnboarding = false
    @State private var showingRecording = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // MARK: - Feed Refresh State
    @State private var homeFeedRefreshTrigger = false
    @State private var showingSuccessMessage = false
    @State private var createdVideoTitle = ""
    
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
                // App logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [StitchColors.primary, StitchColors.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "video.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Stitch")
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
    
    // MARK: - Main App View (FIXED)
    
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
                        videoService: videoService  // Add this parameter
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
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

// MARK: - Authentication View

struct AuthenticationView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    StitchColors.primary.opacity(0.3),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App branding
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [StitchColors.primary, StitchColors.secondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "video.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Stitch")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Where every video starts a conversation")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Sign in options
                VStack(spacing: 16) {
                    Button(action: signInWithApple) {
                        HStack {
                            Image(systemName: "applelogo")
                                .font(.system(size: 18, weight: .medium))
                            Text("Continue with Apple")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    
                    Button(action: signInWithGoogle) {
                        HStack {
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .medium))
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                    
                    // Loading indicator
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func signInWithApple() {
        Task {
            await performSignIn {
                // TODO: Implement Apple Sign In
                throw StitchError.authenticationError("Apple Sign In not yet implemented")
            }
        }
    }
    
    private func signInWithGoogle() {
        Task {
            await performSignIn {
                // TODO: Implement Google Sign In
                throw StitchError.authenticationError("Google Sign In not yet implemented")
            }
        }
    }
    
    private func performSignIn(_ signInAction: @escaping () async throws -> Void) async {
        await MainActor.run {
            isSigningIn = true
            errorMessage = nil
        }
        
        do {
            try await signInAction()
            print("AUTH: Sign in successful")
            
        } catch {
            print("AUTH: Sign in failed - \(error)")
            
            await MainActor.run {
                if let stitchError = error as? StitchError {
                    errorMessage = stitchError.localizedDescription
                } else {
                    errorMessage = "Sign in failed: \(error.localizedDescription)"
                }
                showingError = true
            }
        }
        
        await MainActor.run {
            isSigningIn = false
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
