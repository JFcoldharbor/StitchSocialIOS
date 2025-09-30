//
//  AuthService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Firebase Authentication WITH FIXED NOTIFICATION INTEGRATION
//  Dependencies: Firebase, SpecialUserEntry, UserTier, AuthState, BasicUserInfo, NotificationService (INJECTED)
//  FIXED: Dependency injection for NotificationService, proper imports
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

/// Complete Firebase authentication service with notification integration via dependency injection
@MainActor
class AuthService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var authState: AuthState = .unauthenticated
    @Published var currentUser: BasicUserInfo?
    @Published var lastError: StitchError?
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private var notificationService: NotificationService? // FIXED: Optional injected dependency
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    // MARK: - Initialization
    
    init() {
        setupAuthListener()
        print("🔧 AUTH SERVICE: Enhanced auth using database: \(Config.Firebase.databaseName)")
        
        // Verify Firebase configuration on init
        verifyFirebaseConfiguration()
    }
    
    /// Set notification service after app startup (dependency injection)
    func setNotificationService(_ service: NotificationService) {
        self.notificationService = service
        print("🔔 AUTH SERVICE: Notification service injected")
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
        // FIXED: Remove notification cleanup from deinit to avoid @MainActor issues
        // Notification cleanup will happen in signOut() and auth state changes
    }
    
    // MARK: - Firebase Configuration Verification
    
    private func verifyFirebaseConfiguration() {
        print("🔍 FIREBASE CONFIG: Verifying setup...")
        
        if let app = Auth.auth().app {
            print("✅ FIREBASE: App configured - \(app.name)")
            print("✅ FIREBASE: Database name - \(Config.Firebase.databaseName)")
        } else {
            print("❌ FIREBASE: App not configured")
        }
        
        print("✅ FIRESTORE: Configuration ready")
    }
    
    // MARK: - Public Authentication Methods
    
    /// Initialize authentication and check current state
    func initialize() async throws {
        authState = .authenticating
        isLoading = true
        
        // Check if user is already signed in
        if let firebaseUser = auth.currentUser {
            await handleAuthStateChange(firebaseUser)
        } else {
            authState = .unauthenticated
        }
        
        isLoading = false
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> BasicUserInfo {
        authState = .signingIn
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("✅ AUTH: Email sign in successful: \(result.user.uid)")
            
            // Load user profile and return
            let userProfile = try await loadUserProfile(userID: result.user.uid)
            currentUser = userProfile
            authState = .authenticated
            
            // FIXED: Store FCM token with error handling
            await storeFCMTokenSafely(for: result.user.uid)
            
            return userProfile
            
        } catch {
            authState = .error
            lastError = .authenticationError("Sign in failed: \(error.localizedDescription)")
            print("❌ AUTH: Email sign in failed: \(error)")
            throw lastError!
        }
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String? = nil) async throws -> BasicUserInfo {
        authState = .signingIn
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            print("🔍 PRE-SIGNUP DEBUG:")
            print("   Database: \(Config.Firebase.databaseName)")
            print("   Auth state: \(auth.currentUser?.uid ?? "none")")
            
            let result = try await auth.createUser(withEmail: email, password: password)
            
            print("🔍 POST-SIGNUP DEBUG:")
            print("   Firebase User: \(result.user.uid)")
            print("   Email: \(result.user.email ?? "none")")
            print("   Auth current: \(auth.currentUser?.uid ?? "none")")
            
            // Update display name if provided
            if let displayName = displayName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            print("✅ AUTH: Email sign up successful: \(result.user.uid)")
            
            // Create user profile with special user detection
            let userProfile = try await createNewUserProfile(for: result.user, providedDisplayName: displayName)
            currentUser = userProfile
            authState = .authenticated
            
            // FIXED: Store FCM token with error handling
            await storeFCMTokenSafely(for: result.user.uid)
            
            return userProfile
            
        } catch {
            authState = .error
            lastError = .authenticationError("Sign up failed: \(error.localizedDescription)")
            print("❌ AUTH: Email sign up failed: \(error)")
            
            if let nsError = error as NSError? {
                print("🔍 DETAILED ERROR:")
                print("   Domain: \(nsError.domain)")
                print("   Code: \(nsError.code)")
                print("   Description: \(nsError.localizedDescription)")
                print("   UserInfo: \(nsError.userInfo)")
            }
            
            throw lastError!
        }
    }
    
    /// Legacy method names for compatibility
    func signInWithEmail(_ email: String, password: String) async throws {
        _ = try await signIn(email: email, password: password)
    }
    
    func signUpWithEmail(_ email: String, password: String, displayName: String? = nil) async throws {
        _ = try await signUp(email: email, password: password, displayName: displayName)
    }
    
    /// Sign out current user
    func signOut() async throws {
        authState = .signingOut
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            // FIXED: Stop notification listener before signing out
            notificationService?.stopNotificationListener()
            print("🔔 AUTH: Stopped notification listener before sign out")
            
            try auth.signOut()
            currentUser = nil
            authState = .unauthenticated
            print("✅ AUTH: Sign out successful")
        } catch {
            authState = .error
            lastError = .authenticationError("Sign out failed: \(error.localizedDescription)")
            print("❌ AUTH: Sign out failed: \(error)")
            throw lastError!
        }
    }
    
    /// Reset password for email
    func resetPassword(email: String) async throws {
        lastError = nil
        
        do {
            try await auth.sendPasswordReset(withEmail: email)
            print("✅ AUTH: Password reset email sent to \(email)")
        } catch {
            lastError = .authenticationError("Password reset failed: \(error.localizedDescription)")
            print("❌ AUTH: Password reset failed: \(error)")
            throw lastError!
        }
    }
    
    // MARK: - FCM Token Management (FIXED)
    
    /// Safely store FCM token with proper error handling
    private func storeFCMTokenSafely(for userID: String) async {
        guard let notificationService = notificationService else {
            print("⚠️ AUTH: NotificationService not injected yet")
            return
        }
        
        do {
            // Use the correct method signature that exists in NotificationService
            try await notificationService.storeFCMToken(for: userID)
            
            // Start notification listener
            notificationService.startNotificationListener(for: userID)
            print("🔔 AUTH: Started notification listener for user \(userID)")
            
        } catch {
            print("⚠️ AUTH: Failed to store FCM token or start listener: \(error)")
            // Don't fail auth for notification issues
        }
    }
    
    // MARK: - User Profile Management
    
    /// Load user profile from Firestore
    func loadUserProfile(userID: String) async throws -> BasicUserInfo {
        let userDoc = db.collection(FirebaseSchema.Collections.users).document(userID)
        let snapshot = try await userDoc.getDocument()
        
        guard snapshot.exists, let data = snapshot.data() else {
            throw StitchError.authenticationError("User profile not found")
        }
        
        return createBasicUserInfo(from: data, uid: userID)
    }
    
    /// Update user profile
    func updateUserProfile(displayName: String? = nil, bio: String? = nil) async throws {
        guard let userID = auth.currentUser?.uid else {
            throw StitchError.authenticationError("No authenticated user")
        }
        
        var updates: [String: Any] = [
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ]
        
        if let displayName = displayName {
            updates[FirebaseSchema.UserDocument.displayName] = displayName
        }
        
        if let bio = bio {
            updates["bio"] = bio
        }
        
        try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .updateData(updates)
        
        // Reload current user
        currentUser = try await loadUserProfile(userID: userID)
        
        print("✅ AUTH: User profile updated")
    }
    
    // MARK: - Private Authentication Flow
    
    private func setupAuthListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                await self?.handleAuthStateChange(user)
            }
        }
    }
    
    private func handleAuthStateChange(_ user: User?) async {
        guard let user = user else {
            // Stop notification listener when user signs out
            notificationService?.stopNotificationListener()
            print("🔔 AUTH: Stopped notification listener - user signed out")
            
            authState = .unauthenticated
            currentUser = nil
            return
        }
        
        // Only handle state change if we're not already processing authentication
        guard authState != .signingIn && authState != .authenticating else {
            print("🔄 AUTH STATE: Skipping state change during authentication process")
            return
        }
        
        // If we already have current user and are authenticated, don't reload
        if currentUser != nil && authState == .authenticated {
            print("✅ AUTH STATE: Already authenticated with current user")
            return
        }
        
        do {
            // Load existing user profile
            currentUser = try await loadUserProfile(userID: user.uid)
            authState = .authenticated
            
            // FIXED: Store FCM token and start listener with error handling
            await storeFCMTokenSafely(for: user.uid)
            
            print("✅ AUTH: User profile loaded from state change")
        } catch {
            print("⚠️ AUTH: Failed to load user profile in state change: \(error)")
            
            // Check if this might be a new user during signup
            if error.localizedDescription.contains("User profile not found") {
                print("🔍 AUTH: Profile not found - user might be in signup process")
                return
            }
            
            // For other errors, set unauthenticated state
            authState = .unauthenticated
            currentUser = nil
            notificationService?.stopNotificationListener()
        }
    }
    
    // MARK: - User Profile Creation
    
    private func createNewUserProfile(for user: User, providedDisplayName: String? = nil) async throws -> BasicUserInfo {
        let email = user.email ?? ""
        
        print("🔍 CREATING USER PROFILE DEBUG:")
        print("   User UID: \(user.uid)")
        print("   Email: \(email)")
        print("   Database: \(Config.Firebase.databaseName)")
        print("   Current Auth User: \(auth.currentUser?.uid ?? "NONE")")
        print("   Document Path: users/\(user.uid)")
        
        // Check for special user configuration
        let specialConfig = SpecialUsersConfig.getSpecialUser(for: email)
        
        // Generate username and display name
        let username = generateUsername(from: email, id: user.uid)
        let displayName = providedDisplayName ??
                         user.displayName ??
                         specialConfig?.customTitle ??
                         "New User"
        
        // Determine tier and starting clout based on special user status
        let tier = specialConfig?.tierRawValue ?? UserTier.rookie.rawValue
        let startingClout = specialConfig?.startingClout ?? OptimizationConfig.User.defaultStartingClout
        
        // Create user document with special user detection
        var userData: [String: Any] = [
            FirebaseSchema.UserDocument.id: user.uid,
            FirebaseSchema.UserDocument.username: username,
            FirebaseSchema.UserDocument.displayName: displayName,
            FirebaseSchema.UserDocument.email: email,
            FirebaseSchema.UserDocument.tier: tier,
            FirebaseSchema.UserDocument.clout: startingClout,
            FirebaseSchema.UserDocument.isVerified: specialConfig?.badgeRawValues.contains("verified") ?? false,
            FirebaseSchema.UserDocument.profileImageURL: user.photoURL?.absoluteString ?? "",
            FirebaseSchema.UserDocument.createdAt: Timestamp(),
            FirebaseSchema.UserDocument.updatedAt: Timestamp(),
            
            // Stats
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.videoCount: 0,
            FirebaseSchema.UserDocument.threadCount: 0,
            FirebaseSchema.UserDocument.totalHypesReceived: 0,
            FirebaseSchema.UserDocument.totalCoolsReceived: 0,
            
            // Settings
            FirebaseSchema.UserDocument.isPrivate: false,
            FirebaseSchema.UserDocument.isBanned: false,
            
            // Special user metadata
            "isSpecialUser": specialConfig != nil,
            "specialRole": specialConfig?.role.rawValue ?? NSNull(),
            "specialPerks": specialConfig?.specialPerks ?? [],
            "priority": specialConfig?.priority ?? 0
        ]
        
        // Set bio if special user
        if let customBio = specialConfig?.customBio {
            userData["bio"] = customBio
        }
        
        print("🔍 USER DATA DEBUG:")
        print("   ID field: \(userData[FirebaseSchema.UserDocument.id] ?? "MISSING")")
        print("   Username: \(userData[FirebaseSchema.UserDocument.username] ?? "MISSING")")
        print("   Email: \(userData[FirebaseSchema.UserDocument.email] ?? "MISSING")")
        
        // Test auth token before write
        do {
            if let currentUser = auth.currentUser {
                var tokenReady = false
                var retryCount = 0
                let maxRetries = 3
                
                while !tokenReady && retryCount < maxRetries {
                    do {
                        let token = try await currentUser.getIDToken(forcingRefresh: retryCount > 0)
                        print("🔍 AUTH TOKEN: Successfully retrieved (\(token.prefix(20))...)")
                        tokenReady = true
                    } catch {
                        retryCount += 1
                        print("❌ AUTH TOKEN: Attempt \(retryCount) failed - \(error)")
                        if retryCount < maxRetries {
                            print("🔄 AUTH TOKEN: Retrying in 1 second...")
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                }
                
                if !tokenReady {
                    throw StitchError.authenticationError("Failed to get authentication token after \(maxRetries) attempts")
                }
                
            } else {
                print("❌ AUTH TOKEN: No current user!")
                throw StitchError.authenticationError("No authenticated user during profile creation")
            }
        } catch {
            print("❌ AUTH TOKEN: Failed to verify authentication - \(error)")
            throw StitchError.authenticationError("Failed to verify authentication token")
        }
        
        // Attempt to write user document
        do {
            print("🔍 ATTEMPTING FIRESTORE WRITE...")
            print("   Collection: \(FirebaseSchema.Collections.users)")
            print("   Document ID: \(user.uid)")
            print("   Data keys: \(userData.keys.sorted())")
            
            try await db.collection(FirebaseSchema.Collections.users)
                .document(user.uid)
                .setData(userData)
            
            print("✅ USER PROFILE: Successfully created for \(user.uid)")
            
            // Verify the document was actually written
            print("🔍 VERIFYING DOCUMENT CREATION...")
            let verifyDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(user.uid)
                .getDocument()
            
            if verifyDoc.exists {
                print("✅ VERIFICATION: Document exists in Firestore")
                if let data = verifyDoc.data() {
                    print("✅ VERIFICATION: Document has data (\(data.keys.count) fields)")
                }
            } else {
                print("❌ VERIFICATION: Document does not exist after creation!")
                throw StitchError.authenticationError("Profile creation verification failed")
            }
            
        } catch {
            print("❌ FIRESTORE WRITE FAILED:")
            print("   Error: \(error)")
            
            if let nsError = error as NSError? {
                print("   Domain: \(nsError.domain)")
                print("   Code: \(nsError.code)")
                print("   UserInfo: \(nsError.userInfo)")
            }
            
            throw StitchError.authenticationError("Failed to create user profile: \(error.localizedDescription)")
        }
        
        // Auto-follow special users for new regular accounts
        if specialConfig == nil {
            await autoFollowSpecialUsers(userID: user.uid)
        }
        
        let basicUserInfo = createBasicUserInfo(from: userData, uid: user.uid)
        
        // Log special user creation
        if let special = specialConfig {
            print("🎉 AUTH: Special user created - \(special.role.displayName): \(username)")
            print("👑 AUTH: Starting clout: \(startingClout), Tier: \(tier)")
        } else {
            print("✅ AUTH: Regular user created: \(username)")
        }
        
        return basicUserInfo
    }
    
    // MARK: - Helper Methods
    
    private func createBasicUserInfo(from data: [String: Any], uid: String) -> BasicUserInfo {
        return BasicUserInfo(
            id: uid,
            username: data[FirebaseSchema.UserDocument.username] as? String ?? "unknown",
            displayName: data[FirebaseSchema.UserDocument.displayName] as? String ?? "User",
            tier: UserTier(rawValue: data[FirebaseSchema.UserDocument.tier] as? String ?? "rookie") ?? .rookie,
            clout: data[FirebaseSchema.UserDocument.clout] as? Int ?? 0,
            isVerified: data[FirebaseSchema.UserDocument.isVerified] as? Bool ?? false,
            profileImageURL: data[FirebaseSchema.UserDocument.profileImageURL] as? String,
            createdAt: (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func generateUsername(from email: String, id: String) -> String {
        if !email.isEmpty {
            let emailPrefix = String(email.split(separator: "@").first ?? "user")
            return "\(emailPrefix)_\(String(id.prefix(6)))"
        } else {
            return "user_\(String(id.prefix(8)))"
        }
    }
    
    private func autoFollowSpecialUsers(userID: String) async {
        let autoFollowUsers = SpecialUsersConfig.getAutoFollowUsers()
        
        for specialUser in autoFollowUsers {
            print("ℹ️ AUTH: Would auto-follow \(specialUser.email)")
        }
    }
    
    // MARK: - User Status Helpers
    
    var isSpecialUser: Bool {
        guard let email = auth.currentUser?.email else { return false }
        return SpecialUsersConfig.isSpecialUser(email)
    }
    
    var specialUserConfig: SpecialUserEntry? {
        guard let email = auth.currentUser?.email else { return nil }
        return SpecialUsersConfig.getSpecialUser(for: email)
    }
    
    var specialPerks: [String] {
        guard let email = auth.currentUser?.email else { return [] }
        return SpecialUsersConfig.getSpecialPerks(for: email)
    }
    
    var currentUserEmail: String? {
        return auth.currentUser?.email
    }
    
    var currentUserID: String? {
        return auth.currentUser?.uid
    }
    
    var isAuthenticated: Bool {
        return auth.currentUser != nil && authState == .authenticated
    }
}

// MARK: - Validation Helpers

extension AuthService {
    
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    static func isValidPassword(_ password: String) -> Bool {
        return password.count >= 6
    }
    
    static var passwordRequirements: String {
        return "Password must be at least 6 characters long"
    }
    
    static func isValidDisplayName(_ displayName: String) -> Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 1 && trimmed.count <= 50
    }
}

// MARK: - Error Handling

extension AuthService {
    
    func clearError() {
        lastError = nil
    }
    
    func getUserFriendlyError(_ error: Error) -> String {
        if let authError = error as? AuthErrorCode {
            switch authError.code {
            case .userNotFound:
                return "No account found with this email address"
            case .wrongPassword:
                return "Incorrect password"
            case .invalidEmail:
                return "Please enter a valid email address"
            case .emailAlreadyInUse:
                return "An account with this email already exists"
            case .weakPassword:
                return "Password is too weak. Please choose a stronger password"
            case .networkError:
                return "Network error. Please check your connection"
            case .tooManyRequests:
                return "Too many attempts. Please try again later"
            default:
                return error.localizedDescription
            }
        }
        
        return error.localizedDescription
    }
}

// MARK: - Debug and Testing

extension AuthService {
    
    func debugCleanUserState() async {
        print("🧹 AUTH: Cleaning user state...")
        notificationService?.stopNotificationListener()
        try? auth.signOut()
        currentUser = nil
        authState = .unauthenticated
        lastError = nil
        isLoading = false
        print("🧹 AUTH: User state cleaned")
    }
    
    func helloWorldTest() {
        print("👋 AUTH SERVICE: Complete Hello World - Ready for authentication with notifications")
        print("📱 AUTH SERVICE: Current state: \(authState.displayName)")
        print("👤 AUTH SERVICE: Current user: \(currentUser?.username ?? "None")")
        print("🌟 AUTH SERVICE: Special user: \(isSpecialUser)")
        print("📧 AUTH SERVICE: Email: \(currentUserEmail ?? "None")")
        print("🔔 AUTH SERVICE: Notification service: \(notificationService != nil ? "Injected" : "Not injected")")
        print("✅ AUTH SERVICE: Features: Sign in/up, Special users, Profile creation, State management, Notification listeners")
    }
    
    func getAuthStatus() -> String {
        let user = currentUser?.username ?? "None"
        let email = currentUserEmail ?? "None"
        let special = isSpecialUser ? "Yes" : "No"
        
        return """
        AUTH STATUS:
        - State: \(authState.displayName)
        - User: \(user)
        - Email: \(email)
        - Special: \(special)
        - Authenticated: \(isAuthenticated)
        - Loading: \(isLoading)
        - Notifications: \(notificationService != nil ? "Active" : "Not injected")
        """
    }
}
