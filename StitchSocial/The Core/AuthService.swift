//
//  AuthService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Firebase Authentication
//  Dependencies: Firebase, SpecialUserEntry, UserTier, AuthState, BasicUserInfo
//  Features: Email auth, special user detection, enhanced user creation, state management
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Complete Firebase authentication service with special user detection and state management
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
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    // MARK: - Initialization
    
    init() {
        setupAuthListener()
        print("🔧 AUTH SERVICE: Enhanced auth using database: \(Config.Firebase.databaseName)")
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
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
    
    /// Sign in with email and password - Returns BasicUserInfo for compatibility
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
            
            return userProfile
            
        } catch {
            authState = .error
            lastError = .authenticationError("Sign in failed: \(error.localizedDescription)")
            print("❌ AUTH: Email sign in failed: \(error)")
            throw lastError!
        }
    }
    
    /// Sign up with email and password - Returns BasicUserInfo for compatibility
    func signUp(email: String, password: String, displayName: String? = nil) async throws -> BasicUserInfo {
        authState = .signingIn
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            
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
            
            return userProfile
            
        } catch {
            authState = .error
            lastError = .authenticationError("Sign up failed: \(error.localizedDescription)")
            print("❌ AUTH: Email sign up failed: \(error)")
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
    
    /// Sign in anonymously for testing
    func signInAnonymously() async throws {
        authState = .authenticating
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await auth.signInAnonymously()
            print("✅ AUTH: Anonymous sign in successful: \(result.user.uid)")
            
            // Create anonymous user profile
            let userProfile = try await createAnonymousUserProfile(for: result.user)
            currentUser = userProfile
            authState = .authenticated
            
        } catch {
            authState = .error
            lastError = .authenticationError("Anonymous sign in failed: \(error.localizedDescription)")
            print("❌ AUTH: Anonymous sign in failed: \(error)")
            throw lastError!
        }
    }
    
    /// Sign out current user
    func signOut() async throws {
        authState = .signingOut
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
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
            authState = .unauthenticated
            currentUser = nil
            return
        }
        
        // Only handle state change if we're not already processing authentication
        guard authState != .signingIn && authState != .authenticating else {
            return
        }
        
        do {
            // Load existing user profile
            currentUser = try await loadUserProfile(userID: user.uid)
            authState = .authenticated
            print("✅ AUTH: User profile loaded from state change")
        } catch {
            print("⚠️ AUTH: Failed to load user profile in state change: \(error)")
            // Don't set error state here as user might be signing up
        }
    }
    
    // MARK: - User Profile Creation
    
    private func createNewUserProfile(for user: User, providedDisplayName: String? = nil) async throws -> BasicUserInfo {
        let email = user.email ?? ""
        
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
        
        try await db.collection(FirebaseSchema.Collections.users)
            .document(user.uid)
            .setData(userData)
        
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
    
    private func createAnonymousUserProfile(for user: User) async throws -> BasicUserInfo {
        let username = "anon_\(String(user.uid.prefix(8)))"
        let displayName = "Anonymous User"
        
        let userData: [String: Any] = [
            FirebaseSchema.UserDocument.id: user.uid,
            FirebaseSchema.UserDocument.username: username,
            FirebaseSchema.UserDocument.displayName: displayName,
            FirebaseSchema.UserDocument.email: "",
            FirebaseSchema.UserDocument.tier: UserTier.rookie.rawValue,
            FirebaseSchema.UserDocument.clout: 0,
            FirebaseSchema.UserDocument.isVerified: false,
            FirebaseSchema.UserDocument.profileImageURL: "",
            FirebaseSchema.UserDocument.createdAt: Timestamp(),
            FirebaseSchema.UserDocument.updatedAt: Timestamp(),
            
            // Stats
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.videoCount: 0,
            
            // Settings
            FirebaseSchema.UserDocument.isPrivate: false,
            FirebaseSchema.UserDocument.isBanned: false,
            
            // Anonymous flag
            "isAnonymous": true
        ]
        
        try await db.collection(FirebaseSchema.Collections.users)
            .document(user.uid)
            .setData(userData)
        
        return createBasicUserInfo(from: userData, uid: user.uid)
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
            // In a real implementation, you'd search for users by email and follow them
            // For now, just log the intent
            print("ℹ️ AUTH: Would auto-follow \(specialUser.email)")
        }
    }
    
    // MARK: - User Status Helpers
    
    /// Check if current user is special user
    var isSpecialUser: Bool {
        guard let email = auth.currentUser?.email else { return false }
        return SpecialUsersConfig.isSpecialUser(email)
    }
    
    /// Get special user config for current user
    var specialUserConfig: SpecialUserEntry? {
        guard let email = auth.currentUser?.email else { return nil }
        return SpecialUsersConfig.getSpecialUser(for: email)
    }
    
    /// Get special perks for current user
    var specialPerks: [String] {
        guard let email = auth.currentUser?.email else { return [] }
        return SpecialUsersConfig.getSpecialPerks(for: email)
    }
    
    /// Get current user email
    var currentUserEmail: String? {
        return auth.currentUser?.email
    }
    
    /// Get current Firebase user ID
    var currentUserID: String? {
        return auth.currentUser?.uid
    }
    
    /// Check if user is authenticated
    var isAuthenticated: Bool {
        return auth.currentUser != nil && authState == .authenticated
    }
}

// MARK: - Validation Helpers

extension AuthService {
    
    /// Validate email format
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// Validate password strength
    static func isValidPassword(_ password: String) -> Bool {
        return password.count >= 6
    }
    
    /// Get password requirements
    static var passwordRequirements: String {
        return "Password must be at least 6 characters long"
    }
    
    /// Validate display name
    static func isValidDisplayName(_ displayName: String) -> Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 1 && trimmed.count <= 50
    }
}

// MARK: - Error Handling

extension AuthService {
    
    /// Clear last error
    func clearError() {
        lastError = nil
    }
    
    /// Get user-friendly error message
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
    
    /// Hello World test function
    func helloWorldTest() {
        print("👋 AUTH SERVICE: Complete Hello World - Ready for authentication")
        print("📱 AUTH SERVICE: Current state: \(authState.displayName)")
        print("👤 AUTH SERVICE: Current user: \(currentUser?.username ?? "None")")
        print("🌟 AUTH SERVICE: Special user: \(isSpecialUser)")
        print("📧 AUTH SERVICE: Email: \(currentUserEmail ?? "None")")
        print("✅ AUTH SERVICE: Features: Sign in/up, Special users, Profile creation, State management")
    }
    
    /// Get authentication status for debugging
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
        """
    }
}
