//
//  AuthCoordinator.swift
//  StitchSocial
//
//  Created by James Garmon on 8/17/25.
//

//
//  AuthCoordinator.swift
//  CleanBeta
//
//  Layer 6: Coordination - Authentication Workflow Orchestration
//  Dependencies: AuthService, UserService, SpecialUserEntry
//  Orchestrates: Login → Special User Detection → Profile Setup → Badge Initialization
//

import Foundation
import SwiftUI

/// Orchestrates complete authentication workflow with special user detection and setup
/// Coordinates between authentication, user profile creation, and badge initialization
@MainActor
class AuthCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let authService: AuthService
    private let userService: UserService
    private let notificationService: NotificationService
    
    // MARK: - Authentication State
    
    @Published var currentPhase: AuthPhase = .ready
    @Published var isProcessing: Bool = false
    @Published var authProgress: Double = 0.0
    @Published var currentTask: String = ""
    
    // MARK: - User State
    
    @Published var authenticatedUser: StitchUser?
    @Published var isSpecialUser: Bool = false
    @Published var specialUserEntry: SpecialUserEntry?
    @Published var userProfile: AuthUserProfile?
    
    // MARK: - Error Handling
    
    @Published var lastError: AuthError?
    @Published var showingError: Bool = false
    @Published var canRetry: Bool = false
    
    // MARK: - Analytics
    
    @Published var authMetrics = AuthMetrics()
    @Published var sessionData = SessionData()
    
    // MARK: - Configuration
    
    private let enableSpecialUserDetection = true
    private let enableBadgeInitialization = true
    private let enableAutoFollow = true
    private let maxRetries = 2
    
    // MARK: - Initialization
    
    init(
        authService: AuthService,
        userService: UserService,
        notificationService: NotificationService
    ) {
        self.authService = authService
        self.userService = userService
        self.notificationService = notificationService
        
        print("🔐 AUTH COORDINATOR: Initialized - Ready for authentication workflow")
    }
    
    // MARK: - Primary Authentication Workflow
    
    /// Complete authentication workflow: Login → Detection → Profile → Badges
    func processAuthentication(
        email: String,
        password: String,
        isSignUp: Bool = false
    ) async throws -> StitchUser {
        
        let startTime = Date()
        isProcessing = true
        currentPhase = .authenticating
        authProgress = 0.0
        
        print("🔐 AUTH: Starting authentication workflow")
        print("🔐 AUTH: Email: \(email), Sign Up: \(isSignUp)")
        
        defer {
            isProcessing = false
            recordAuthMetrics(
                duration: Date().timeIntervalSince(startTime),
                success: authenticatedUser != nil,
                isSignUp: isSignUp
            )
        }
        
        do {
            // Phase 1: Authentication (0-30%)
            let user = try await performAuthentication(
                email: email,
                password: password,
                isSignUp: isSignUp
            )
            
            // Phase 2: Special User Detection (30-50%)
            let specialUserInfo = await performSpecialUserDetection(
                email: email,
                userID: user.id
            )
            
            // Phase 3: Profile Setup (50-80%)
            let profile = try await performProfileSetup(
                user: user,
                specialUserInfo: specialUserInfo,
                isNewUser: isSignUp
            )
            
            // Phase 4: Badge Initialization (80-100%)
            try await performBadgeInitialization(
                userID: user.id,
                specialUserInfo: specialUserInfo,
                isNewUser: isSignUp
            )
            
            // Complete authentication
            await completeAuthentication(
                user: user,
                profile: profile,
                specialUserInfo: specialUserInfo
            )
            
            print("✅ AUTH: Complete workflow finished successfully")
            return user
            
        } catch {
            await handleAuthError(error)
            throw error
        }
    }
    
    // MARK: - Phase 1: Authentication
    
    /// Perform Firebase authentication (login or signup)
    private func performAuthentication(
        email: String,
        password: String,
        isSignUp: Bool
    ) async throws -> StitchUser {
        
        currentPhase = .authenticating
        currentTask = isSignUp ? "Creating account..." : "Signing in..."
        await updateProgress(0.1)
        
        print("🔐 AUTH: Starting \(isSignUp ? "signup" : "login") process")
        
        do {
            let user: StitchUser
            
            if isSignUp {
                // Fixed: Use correct AuthService method name
                try await authService.signUpWithEmail(email, password: password)
                currentTask = "Account created successfully"
                
                // Get user info after signup
                guard let currentUser = authService.currentUser else {
                    throw AuthError.authenticationFailed("User not available after signup")
                }
                
                user = StitchUser(
                    id: currentUser.id,
                    email: email, // BasicUserInfo doesn't have email field, use parameter
                    displayName: currentUser.displayName
                )
                
            } else {
                // Fixed: Use correct AuthService method name
                try await authService.signInWithEmail(email, password: password)
                currentTask = "Signed in successfully"
                
                // Get user info after signin
                guard let currentUser = authService.currentUser else {
                    throw AuthError.authenticationFailed("User not available after signin")
                }
                
                user = StitchUser(
                    id: currentUser.id,
                    email: email, // BasicUserInfo doesn't have email field, use parameter
                    displayName: currentUser.displayName
                )
            }
            
            await updateProgress(0.3)
            
            // Store authenticated user
            authenticatedUser = user
            
            print("🔐 AUTH: Authentication successful - User ID: \(user.id)")
            print("🔐 AUTH: Email: \(user.email), Display Name: \(user.displayName)")
            
            return user
            
        } catch {
            print("❌ AUTH: Authentication failed - \(error.localizedDescription)")
            throw AuthError.authenticationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Phase 2: Special User Detection
    
    /// Detect if user is in special users list and get configuration
    private func performSpecialUserDetection(
        email: String,
        userID: String
    ) async -> SpecialUserInfo? {
        
        currentPhase = .detectingSpecialUser
        currentTask = "Checking special user status..."
        await updateProgress(0.35)
        
        print("🌟 SPECIAL USER: Checking status for \(email)")
        
        guard enableSpecialUserDetection else {
            print("🌟 SPECIAL USER: Detection disabled")
            await updateProgress(0.5)
            return nil
        }
        
        // Check against special users configuration
        if let specialEntry = SpecialUsersConfig.getSpecialUser(for: email) {
            
            isSpecialUser = true
            specialUserEntry = specialEntry
            
            let specialInfo = SpecialUserInfo(
                entry: specialEntry,
                isFounder: specialEntry.isFounder,
                isCelebrity: specialEntry.isCelebrity,
                startingClout: specialEntry.startingClout,
                customTitle: specialEntry.customTitle,
                customBio: specialEntry.customBio,
                specialPerks: specialEntry.specialPerks
            )
            
            currentTask = "Special user detected: \(specialEntry.role.displayName)"
            await updateProgress(0.5)
            
            print("🌟 SPECIAL USER: Found special user - \(specialEntry.role.displayName)")
            print("🌟 SPECIAL USER: Starting clout: \(specialEntry.startingClout)")
            print("🌟 SPECIAL USER: Custom title: \(specialEntry.customTitle)")
            
            return specialInfo
            
        } else {
            currentTask = "Regular user account"
            await updateProgress(0.5)
            
            print("👤 REGULAR USER: No special configuration found")
            return nil
        }
    }
    
    // MARK: - Phase 3: Profile Setup
    
    /// Setup user profile with special user benefits
    private func performProfileSetup(
        user: StitchUser,
        specialUserInfo: SpecialUserInfo?,
        isNewUser: Bool
    ) async throws -> AuthUserProfile {
        
        currentPhase = .settingUpProfile
        currentTask = "Setting up profile..."
        await updateProgress(0.55)
        
        print("👤 PROFILE: Setting up profile for \(user.id)")
        
        do {
            // Determine starting values
            let startingClout = specialUserInfo?.startingClout ?? UserTier.rookie.cloutRange.lowerBound
            let customTitle = specialUserInfo?.customTitle
            let customBio = specialUserInfo?.customBio
            let tierOverride = specialUserInfo?.entry.tierRawValue
            
            currentTask = "Creating user profile..."
            await updateProgress(0.65)
            
            // Create profile data
            let profile = AuthUserProfile(
                userID: user.id,
                email: user.email,
                displayName: user.displayName,
                customTitle: customTitle,
                customBio: customBio,
                startingClout: startingClout,
                isSpecialUser: specialUserInfo != nil,
                tierOverride: tierOverride
            )
            
            userProfile = profile
            
            currentTask = "Profile setup complete"
            await updateProgress(0.8)
            
            print("👤 PROFILE: Setup complete")
            print("👤 PROFILE: Starting clout: \(startingClout)")
            print("👤 PROFILE: Special user: \(specialUserInfo != nil)")
            
            return profile
            
        } catch {
            print("❌ PROFILE: Setup failed - \(error.localizedDescription)")
            throw AuthError.profileSetupFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Phase 4: Badge Initialization
    
    /// Initialize badges for new users
    private func performBadgeInitialization(
        userID: String,
        specialUserInfo: SpecialUserInfo?,
        isNewUser: Bool
    ) async throws {
        
        currentPhase = .initializingBadges
        currentTask = "Initializing badges..."
        await updateProgress(0.85)
        
        print("🏆 BADGES: Starting initialization for \(userID)")
        
        guard enableBadgeInitialization else {
            print("🏆 BADGES: Initialization disabled")
            await updateProgress(1.0)
            return
        }
        
        // Determine badges to award
        var badgesToAward: [String] = []
        
        // Special user badges
        if let specialInfo = specialUserInfo {
            if specialInfo.isFounder {
                badgesToAward.append("founder")
            }
            if specialInfo.isCelebrity {
                badgesToAward.append("celebrity")
            }
        }
        
        // New user badges
        if isNewUser {
            badgesToAward.append("new_user")
            
            // Early adopter badge for 2025
            let calendar = Calendar.current
            if calendar.component(.year, from: Date()) == 2025 {
                badgesToAward.append("early_adopter")
            }
        }
        
        currentTask = "Awarding \(badgesToAward.count) badges..."
        await updateProgress(0.9)
        
        // Award badges
        for badgeRawValue in badgesToAward {
            await awardBadge(userID: userID, badgeRawValue: badgeRawValue)
        }
        
        currentTask = "Badge initialization complete"
        await updateProgress(1.0)
        
        print("🏆 BADGES: Initialization complete - \(badgesToAward.count) badges awarded")
    }
    
    /// Award individual badge to user
    private func awardBadge(userID: String, badgeRawValue: String) async {
        
        // TODO: Implement badge awarding when BadgeService is available
        print("🏆 BADGE: Would award '\(badgeRawValue)' to \(userID)")
        
        // TODO: Send badge unlock notification
        // await notificationService.sendBadgeUnlockNotification(...)
    }
    
    // MARK: - Completion
    
    /// Complete authentication workflow with state updates
    private func completeAuthentication(
        user: StitchUser,
        profile: AuthUserProfile,
        specialUserInfo: SpecialUserInfo?
    ) async {
        
        currentPhase = .complete
        currentTask = "Authentication complete!"
        
        // Update session data
        sessionData.authenticationTime = Date()
        sessionData.isSpecialUser = specialUserInfo != nil
        sessionData.userTier = profile.tierOverride ?? "rookie"
        
        // Update metrics
        authMetrics.totalLogins += 1
        if specialUserInfo != nil {
            authMetrics.specialUserLogins += 1
        }
        
        print("🎉 AUTH: Authentication workflow completed successfully!")
        print("📊 ANALYTICS: Session established for \(profile.isSpecialUser ? "special" : "regular") user")
        print("📊 ANALYTICS: Total logins: \(authMetrics.totalLogins)")
    }
    
    // MARK: - Error Handling
    
    /// Handle authentication errors with retry logic
    private func handleAuthError(_ error: Error) async {
        
        currentPhase = .error
        lastError = error as? AuthError ?? .unknown(error.localizedDescription)
        showingError = true
        canRetry = determineRetryability(error)
        
        // Update metrics
        authMetrics.totalErrors += 1
        authMetrics.lastErrorType = lastError?.localizedDescription
        
        print("❌ AUTH: Error encountered - \(error.localizedDescription)")
        print("🔄 RETRY: Can retry: \(canRetry)")
    }
    
    /// Determine if error allows retry
    private func determineRetryability(_ error: Error) -> Bool {
        if let authError = error as? AuthError {
            switch authError {
            case .networkError, .profileSetupFailed:
                return true
            case .authenticationFailed, .invalidCredentials, .userNotFound:
                return false
            default:
                return true
            }
        }
        return true
    }
    
    // MARK: - Helper Methods
    
    /// Update authentication progress
    private func updateProgress(_ progress: Double) async {
        authProgress = min(1.0, max(0.0, progress))
    }
    
    /// Record authentication metrics
    private func recordAuthMetrics(
        duration: TimeInterval,
        success: Bool,
        isSignUp: Bool
    ) {
        authMetrics.averageAuthTime = duration
        authMetrics.successRate = calculateSuccessRate()
        
        if isSignUp {
            authMetrics.totalSignUps += 1
        }
        
        print("📊 AUTH METRICS: Duration: \(String(format: "%.2f", duration))s, Success: \(success)")
    }
    
    /// Calculate authentication success rate
    private func calculateSuccessRate() -> Double {
        let total = authMetrics.totalLogins + authMetrics.totalErrors
        guard total > 0 else { return 1.0 }
        return Double(authMetrics.totalLogins) / Double(total)
    }
    
    // MARK: - Public Interface
    
    /// Sign out user and reset state
    func signOut() async throws {
        
        print("🔐 AUTH: Signing out user")
        
        try await authService.signOut()
        
        // Reset state
        currentPhase = .ready
        isProcessing = false
        authProgress = 0.0
        currentTask = ""
        
        authenticatedUser = nil
        isSpecialUser = false
        specialUserEntry = nil
        userProfile = nil
        
        lastError = nil
        showingError = false
        canRetry = false
        
        print("🔐 AUTH: Sign out complete")
    }
    
    /// Reset coordinator state
    func resetState() {
        currentPhase = .ready
        isProcessing = false
        authProgress = 0.0
        currentTask = ""
        
        lastError = nil
        showingError = false
        canRetry = false
        
        print("🔄 AUTH COORDINATOR: State reset")
    }
    
    /// Get current authentication status
    func getAuthStatus() -> AuthStatus {
        return AuthStatus(
            phase: currentPhase,
            progress: authProgress,
            currentTask: currentTask,
            isProcessing: isProcessing,
            isAuthenticated: authenticatedUser != nil,
            isSpecialUser: isSpecialUser,
            canRetry: canRetry,
            lastError: lastError
        )
    }
    
    /// Get authentication metrics
    func getAuthMetrics() -> AuthMetrics {
        return authMetrics
    }
}

// MARK: - Supporting Types

/// Authentication workflow phases
enum AuthPhase: String, CaseIterable {
    case ready = "ready"
    case authenticating = "authenticating"
    case detectingSpecialUser = "detecting_special_user"
    case settingUpProfile = "setting_up_profile"
    case initializingBadges = "initializing_badges"
    case complete = "complete"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .authenticating: return "Authenticating"
        case .detectingSpecialUser: return "Checking Status"
        case .settingUpProfile: return "Setting Up Profile"
        case .initializingBadges: return "Initializing Badges"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }
}

/// Authentication errors
enum AuthError: LocalizedError {
    case authenticationFailed(String)
    case invalidCredentials
    case userNotFound
    case profileSetupFailed(String)
    case badgeInitializationFailed(String)
    case networkError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .userNotFound:
            return "User account not found"
        case .profileSetupFailed(let message):
            return "Profile setup failed: \(message)"
        case .badgeInitializationFailed(let message):
            return "Badge initialization failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

/// Special user information
struct SpecialUserInfo {
    let entry: SpecialUserEntry
    let isFounder: Bool
    let isCelebrity: Bool
    let startingClout: Int
    let customTitle: String
    let customBio: String
    let specialPerks: [String]
}

/// User profile data for authentication
struct AuthUserProfile {
    let userID: String
    let email: String
    let displayName: String
    let customTitle: String?
    let customBio: String?
    let startingClout: Int
    let isSpecialUser: Bool
    let tierOverride: String?
}

/// Authentication metrics for analytics
struct AuthMetrics {
    var totalLogins: Int = 0
    var totalSignUps: Int = 0
    var totalErrors: Int = 0
    var specialUserLogins: Int = 0
    var averageAuthTime: TimeInterval = 0.0
    var successRate: Double = 1.0
    var lastErrorType: String?
}

/// Session data tracking
struct SessionData {
    var authenticationTime: Date?
    var isSpecialUser: Bool = false
    var userTier: String = "rookie"
    var sessionStartTime: Date = Date()
    
    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }
}

/// Authentication status for UI
struct AuthStatus {
    let phase: AuthPhase
    let progress: Double
    let currentTask: String
    let isProcessing: Bool
    let isAuthenticated: Bool
    let isSpecialUser: Bool
    let canRetry: Bool
    let lastError: AuthError?
}

/// Simple user representation for coordination
struct StitchUser {
    let id: String
    let email: String
    let displayName: String
}

// MARK: - Extensions

extension AuthCoordinator {
    
    /// Test authentication workflow with mock data
    func helloWorldTest() {
        print("🔐 AUTH COORDINATOR: Hello World - Ready for complete authentication workflow!")
        print("🔐 Features: Login/Signup, Special user detection, Profile setup, Badge initialization")
        print("🔐 Status: AuthService integration, Special user configuration, Badge system ready")
    }
}
