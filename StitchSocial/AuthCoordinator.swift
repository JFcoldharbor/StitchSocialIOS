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
import FirebaseFirestore

/// Orchestrates complete authentication workflow with special user detection and setup
/// Coordinates between authentication, user profile creation, and badge initialization
@MainActor
class AuthCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let authService: AuthService
    private let userService: UserService
    private let NotificationService: NotificationService
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
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
        NotificationService: NotificationService
    ) {
        self.authService = authService
        self.userService = userService
        self.NotificationService = NotificationService
        
        #if DEBUG
        print("🔐 AUTH COORDINATOR: Initialized - Ready for authentication workflow")
        #endif
        
        // Handle existing users migration on startup
        Task {
            await handleExistingUsersOnStartup()
        }
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
        
        #if DEBUG
        print("🔐 AUTH: Starting authentication workflow")
        #endif
        #if DEBUG
        print("🔐 AUTH: Email: \(email), Sign Up: \(isSignUp)")
        #endif
        
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
            
            #if DEBUG
            print("✅ AUTH: Complete workflow finished successfully")
            #endif
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
            
            #if DEBUG
            print("🔐 AUTH: Starting \(isSignUp ? "signup" : "login") process")
            #endif
            
            do {
                let user: StitchUser
                
                if isSignUp {
                    // FIXED: Use correct AuthService method name
                    let basicUser = try await authService.signUp(email: email, password: password)
                    currentTask = "Account created successfully"
                    
                    user = StitchUser(
                        id: basicUser.id,
                        email: email,
                        displayName: basicUser.displayName
                    )
                    
                } else {
                    // FIXED: Use correct AuthService method name
                    let basicUser = try await authService.signIn(email: email, password: password)
                    currentTask = "Signed in successfully"
                    
                    user = StitchUser(
                        id: basicUser.id,
                        email: email,
                        displayName: basicUser.displayName
                    )
                }
                
                await updateProgress(0.3)
                
                // Store authenticated user
                authenticatedUser = user
                
                #if DEBUG
                print("🔐 AUTH: Authentication successful - User ID: \(user.id)")
                #endif
                #if DEBUG
                print("🔐 AUTH: Email: \(user.email), Display Name: \(user.displayName)")
                #endif
                
                return user
                
            } catch {
                #if DEBUG
                print("❌ AUTH: Authentication failed - \(error.localizedDescription)")
                #endif
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
        
        #if DEBUG
        print("🌟 SPECIAL USER: Checking status for \(email)")
        #endif
        
        guard enableSpecialUserDetection else {
            #if DEBUG
            print("🌟 SPECIAL USER: Detection disabled")
            #endif
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
            
            #if DEBUG
            print("🌟 SPECIAL USER: Found special user - \(specialEntry.role.displayName)")
            #endif
            #if DEBUG
            print("🌟 SPECIAL USER: Starting clout: \(specialEntry.startingClout)")
            #endif
            #if DEBUG
            print("🌟 SPECIAL USER: Custom title: \(specialEntry.customTitle)")
            #endif
            
            return specialInfo
            
        } else {
            currentTask = "Regular user account"
            await updateProgress(0.5)
            
            #if DEBUG
            print("👤 REGULAR USER: No special configuration found")
            #endif
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
        
        #if DEBUG
        print("👤 PROFILE: Setting up profile for \(user.id)")
        #endif
        
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
            
            #if DEBUG
            print("👤 PROFILE: Setup complete")
            #endif
            #if DEBUG
            print("👤 PROFILE: Starting clout: \(startingClout)")
            #endif
            #if DEBUG
            print("👤 PROFILE: Special user: \(specialUserInfo != nil)")
            #endif
            
            return profile
            
        } catch {
            #if DEBUG
            print("❌ PROFILE: Setup failed - \(error.localizedDescription)")
            #endif
            throw AuthError.profileSetupFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Phase 4: Badge Initialization & Auto-Follow
    
    /// Initialize badges for new users with auto-follow
    private func performBadgeInitialization(
        userID: String,
        specialUserInfo: SpecialUserInfo?,
        isNewUser: Bool
    ) async throws {
        
        currentPhase = .initializingBadges
        currentTask = "Initializing badges..."
        await updateProgress(0.85)
        
        #if DEBUG
        print("🏆 BADGES: Starting initialization for \(userID)")
        #endif
        
        guard enableBadgeInitialization else {
            #if DEBUG
            print("🏆 BADGES: Initialization disabled")
            #endif
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
        
        // AUTO-FOLLOW JAMES FORTUNE FOR NEW USERS ONLY
        if isNewUser && enableAutoFollow {
            currentTask = "Following official accounts..."
            await updateProgress(0.92)
            
            #if DEBUG
            print("🔗 AUTO-FOLLOW: Starting auto-follow process for new user")
            #endif
            
            // Get James Fortune's entry from special users config
            if let jamesFortune = SpecialUsersConfig.getJamesFortune() {
                do {
                    #if DEBUG
                    print("🔍 AUTO-FOLLOW: Looking up James Fortune user ID...")
                    #endif
                    
                    // Find James Fortune's user ID by email
                    if let jamesUserID = try await findUserIDByEmail(email: jamesFortune.email) {
                        #if DEBUG
                        print("✅ AUTO-FOLLOW: Found James Fortune user ID: \(jamesUserID)")
                        #endif
                        
                        // Auto-follow James Fortune
                        try await userService.followUser(followerID: userID, followingID: jamesUserID)
                        
                        #if DEBUG
                        print("✅ AUTO-FOLLOW: New user \(userID) automatically following James Fortune \(jamesUserID)")
                        #endif
                        
                        currentTask = "Following official account complete"
                        
                    } else {
                        #if DEBUG
                        print("⚠️ AUTO-FOLLOW: James Fortune user ID not found")
                        #endif
                        currentTask = "Official account not found"
                    }
                    
                } catch {
                    #if DEBUG
                    print("⚠️ AUTO-FOLLOW: Failed to follow James Fortune: \(error)")
                    #endif
                    currentTask = "Auto-follow error - continuing signup"
                    // Don't fail signup for auto-follow errors
                }
            }
            
            await updateProgress(0.95)
        }
        
        currentTask = "Badge initialization complete"
        await updateProgress(1.0)
        
        #if DEBUG
        print("🏆 BADGES: Initialization complete - \(badgesToAward.count) badges awarded")
        #endif
    }
    
    /// Award individual badge to user
    private func awardBadge(userID: String, badgeRawValue: String) async {
        
        // TODO: Implement badge awarding when BadgeService is available
        #if DEBUG
        print("🏆 BADGE: Would award '\(badgeRawValue)' to \(userID)")
        #endif
        
        // TODO: Send badge unlock notification
        // await NotificationService.sendBadgeUnlockNotification(...)
    }
    
    // MARK: - Auto-Follow Helper Methods
    
    /// Find user ID by email address
    private func findUserIDByEmail(email: String) async throws -> String? {
        #if DEBUG
        print("🔍 AUTH: Looking up user ID for email: \(email)")
        #endif
        
        let snapshot = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.email, isEqualTo: email)
            .limit(to: 1)
            .getDocuments()
        
        let userID = snapshot.documents.first?.documentID
        
        if let userID = userID {
            #if DEBUG
            print("✅ AUTH: Found user ID \(userID) for email \(email)")
            #endif
        } else {
            #if DEBUG
            print("❌ AUTH: No user found for email \(email)")
            #endif
        }
        
        return userID
    }
    
    /// Call this method in your app startup to handle existing users
    func handleExistingUsersOnStartup() async {
        await migrateExistingUsersToAutoFollow()
    }
    
    /// Migrate existing users to auto-follow James Fortune (call this in init or app startup)
    func migrateExistingUsersToAutoFollow() async {
        #if DEBUG
        print("📦 MIGRATION: Starting existing users auto-follow migration")
        #endif
        
        guard let jamesFortune = SpecialUsersConfig.getJamesFortune() else {
            #if DEBUG
            print("❌ MIGRATION: James Fortune not found in config")
            #endif
            return
        }
        
        // Check if migration already completed
        if await hasAutoFollowMigrationBeenRun() {
            #if DEBUG
            print("✅ MIGRATION: Already completed, skipping")
            #endif
            return
        }
        
        do {
            // Find James Fortune's user ID
            guard let jamesUserID = try await findUserIDByEmail(email: jamesFortune.email) else {
                #if DEBUG
                print("❌ MIGRATION: James Fortune account not found")
                #endif
                return
            }
            
            #if DEBUG
            print("✅ MIGRATION: Found James Fortune account: \(jamesUserID)")
            #endif
            
            // Get all users who should follow James
            let allUsersSnapshot = try await db.collection(FirebaseSchema.Collections.users)
                .getDocuments()
            
            var successCount = 0
            var errorCount = 0
            
            for userDoc in allUsersSnapshot.documents {
                let userID = userDoc.documentID
                
                // Skip James himself
                if userID == jamesUserID {
                    continue
                }
                
                // Skip if already following
                let isAlreadyFollowing = try await userService.isFollowing(followerID: userID, followingID: jamesUserID)
                if isAlreadyFollowing {
                    continue
                }
                
                // Check if user should be excluded (only founders/co-founders)
                let userData = userDoc.data()
                let userEmail = userData[FirebaseSchema.UserDocument.email] as? String ?? ""
                
                if let specialUser = SpecialUsersConfig.getSpecialUser(for: userEmail) {
                    if specialUser.role == .founder || specialUser.role == .coFounder {
                        #if DEBUG
                        print("⏭️ MIGRATION: Skipping founder/co-founder \(userEmail)")
                        #endif
                        continue
                    } else {
                        #if DEBUG
                        print("✅ MIGRATION: Including special user \(userEmail) (\(specialUser.role.displayName))")
                        #endif
                    }
                }
                
                // Follow James Fortune
                do {
                    try await userService.followUser(followerID: userID, followingID: jamesUserID)
                    successCount += 1
                    #if DEBUG
                    print("✅ MIGRATION: User \(userID) now follows James Fortune")
                    #endif
                } catch {
                    errorCount += 1
                    #if DEBUG
                    print("❌ MIGRATION: Failed to migrate user \(userID): \(error)")
                    #endif
                }
                
                // Small delay to avoid overwhelming system
                if (successCount + errorCount) % 10 == 0 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
            }
            
            #if DEBUG
            print("🎉 MIGRATION COMPLETE:")
            #endif
            #if DEBUG
            print("   ✅ Successfully migrated: \(successCount) users")
            #endif
            #if DEBUG
            print("   ❌ Errors encountered: \(errorCount) users")
            #endif
            
            // Mark migration complete
            try await markMigrationComplete()
            
        } catch {
            #if DEBUG
            print("❌ MIGRATION FAILED: \(error)")
            #endif
        }
    }
    
    /// Check if migration has been completed
    private func hasAutoFollowMigrationBeenRun() async -> Bool {
        do {
            let doc = try await db.collection("system")
                .document("migrations")
                .getDocument()
            
            return doc.data()?["autoFollowMigrationComplete"] as? Bool ?? false
            
        } catch {
            #if DEBUG
            print("⚠️ MIGRATION: Could not check status: \(error)")
            #endif
            return false
        }
    }
    
    /// Mark migration as complete
    private func markMigrationComplete() async throws {
        try await db.collection("system")
            .document("migrations")
            .setData([
                "autoFollowMigrationComplete": true,
                "autoFollowMigrationDate": Timestamp(),
                "autoFollowMigrationVersion": "1.0"
            ], merge: true)
        
        #if DEBUG
        print("✅ MIGRATION: Marked as complete")
        #endif
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
        
        #if DEBUG
        print("🎉 AUTH: Authentication workflow completed successfully!")
        #endif
        #if DEBUG
        print("📊 ANALYTICS: Session established for \(profile.isSpecialUser ? "special" : "regular") user")
        #endif
        #if DEBUG
        print("📊 ANALYTICS: Total logins: \(authMetrics.totalLogins)")
        #endif
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
        
        #if DEBUG
        print("❌ AUTH: Error encountered - \(error.localizedDescription)")
        #endif
        #if DEBUG
        print("🔄 RETRY: Can retry: \(canRetry)")
        #endif
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
        
        #if DEBUG
        print("📊 AUTH METRICS: Duration: \(String(format: "%.2f", duration))s, Success: \(success)")
        #endif
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
        
        #if DEBUG
        print("🔐 AUTH: Signing out user")
        #endif
        
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
        
        #if DEBUG
        print("🔐 AUTH: Sign out complete")
        #endif
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
        
        #if DEBUG
        print("🔄 AUTH COORDINATOR: State reset")
        #endif
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
        #if DEBUG
        print("🔐 AUTH COORDINATOR: Hello World - Ready for complete authentication workflow!")
        #endif
        #if DEBUG
        print("🔐 Features: Login/Signup, Special user detection, Profile setup, Badge initialization, Auto-follow")
        #endif
        #if DEBUG
        print("🔐 Status: AuthService integration, Special user configuration, Auto-follow system ready")
        #endif
    }
}
