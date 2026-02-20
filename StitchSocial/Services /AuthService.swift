//
//  AuthService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Firebase Authentication
//  UPDATED: Email verification + referral code pass-through at signup
//  UPDATED: Removed deprecated notification methods, FCM now handled by FCMPushManager
//
//  CACHING: isEmailVerified cached in UserDefaults to avoid reload() on every launch
//  BATCHING: Email verification send is fire-and-forget (no await needed)
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import FirebaseFunctions

/// Complete Firebase authentication service
@MainActor
class AuthService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var authState: AuthState = .unauthenticated
    @Published var currentUser: BasicUserInfo?
    @Published var lastError: StitchError?
    @Published var isLoading: Bool = false
    @Published var isEmailVerified: Bool = false
    
    // MARK: - Private Properties
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let functions = Functions.functions(region: "us-central1")
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    // MARK: - Cache Keys (avoids redundant reload() calls)
    
    private enum CacheKeys {
        static let emailVerified = "stitch_email_verified"
    }
    
    // MARK: - Initialization
    
    init() {
        setupAuthListener()
        print("🔧 AUTH SERVICE: Enhanced auth using database: \(Config.Firebase.databaseName)")
        verifyFirebaseConfiguration()
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
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
        print("✅ FUNCTIONS: Region configured - us-central1")
    }
    
    // MARK: - Authenticated Cloud Functions
    
    /// Call authenticated Firebase function with proper token handling
    func callAuthenticatedFunction(name: String, data: [String: Any] = [:]) async throws -> Any? {
        guard let user = auth.currentUser else {
            throw StitchError.authenticationError("User not authenticated for function call")
        }
        
        print("🔐 AUTH: Calling authenticated function: \(name)")
        
        do {
            let token = try await user.getIDToken(forcingRefresh: true)
            print("✅ AUTH: Fresh token retrieved for function call")
            
            let result = try await functions.httpsCallable(name).call(data)
            
            print("✅ AUTH: Function \(name) called successfully")
            return result.data
            
        } catch {
            print("❌ AUTH: Function \(name) failed: \(error)")
            
            if error.localizedDescription.contains("UNAUTHENTICATED") {
                print("🔄 AUTH: Retrying with force token refresh...")
                let _ = try await user.getIDToken(forcingRefresh: true)
                let retryResult = try await functions.httpsCallable(name).call(data)
                return retryResult.data
            }
            
            throw error
        }
    }
    
    // MARK: - Public Authentication Methods
    
    /// Initialize authentication and check current state
    func initialize() async throws {
        authState = .authenticating
        isLoading = true
        
        if let firebaseUser = auth.currentUser {
            // Load cached verification status first (avoids network call)
            isEmailVerified = UserDefaults.standard.bool(forKey: CacheKeys.emailVerified)
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
            
            // Check email verification status and cache it
            isEmailVerified = result.user.isEmailVerified
            UserDefaults.standard.set(isEmailVerified, forKey: CacheKeys.emailVerified)
            
            let userProfile = try await loadUserProfile(userID: result.user.uid)
            currentUser = userProfile
            authState = .authenticated
            
            // FCM token registration is now automatic via FCMPushManager
            print("📱 AUTH: FCM token registration handled by FCMPushManager")
            print("📧 AUTH: Email verified: \(isEmailVerified)")
            
            return userProfile
            
        } catch {
            authState = .error
            lastError = .authenticationError("Sign in failed: \(error.localizedDescription)")
            print("❌ AUTH: Email sign in failed: \(error)")
            throw lastError!
        }
    }
    
    /// Sign up with email and password
    /// Returns (BasicUserInfo, isNewUser: true) — caller handles referral + verification prompt
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
            
            if let displayName = displayName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            // Send email verification — fire and forget, don't block signup
            Task {
                do {
                    try await result.user.sendEmailVerification()
                    print("📧 AUTH: Verification email sent to \(email)")
                } catch {
                    print("⚠️ AUTH: Failed to send verification email: \(error) — non-blocking")
                }
            }
            
            isEmailVerified = false
            UserDefaults.standard.set(false, forKey: CacheKeys.emailVerified)
            
            print("✅ AUTH: Email sign up successful: \(result.user.uid)")
            
            let userProfile = try await createNewUserProfile(for: result.user, providedDisplayName: displayName)
            currentUser = userProfile
            authState = .authenticated
            
            // FCM token registration is now automatic via FCMPushManager
            print("📱 AUTH: FCM token registration handled by FCMPushManager")
            
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
    
    // MARK: - Email Verification
    
    /// Check if current user's email is verified (calls reload to get fresh status)
    /// CACHING: Only calls reload() if cached value is false — once verified, never re-checks
    func checkEmailVerification() async -> Bool {
        // If already verified and cached, skip the network call
        if UserDefaults.standard.bool(forKey: CacheKeys.emailVerified) {
            isEmailVerified = true
            return true
        }
        
        guard let user = auth.currentUser else { return false }
        
        do {
            try await user.reload()
            let verified = user.isEmailVerified
            isEmailVerified = verified
            
            if verified {
                // Cache it permanently — email can't become un-verified
                UserDefaults.standard.set(true, forKey: CacheKeys.emailVerified)
                print("✅ AUTH: Email verification confirmed and cached")
            }
            
            return verified
        } catch {
            print("⚠️ AUTH: Failed to check email verification: \(error)")
            return false
        }
    }
    
    /// Resend verification email to current user
    func resendVerificationEmail() async throws {
        guard let user = auth.currentUser else {
            throw StitchError.authenticationError("No authenticated user")
        }
        
        guard !user.isEmailVerified else {
            print("✅ AUTH: Email already verified, no resend needed")
            isEmailVerified = true
            UserDefaults.standard.set(true, forKey: CacheKeys.emailVerified)
            return
        }
        
        try await user.sendEmailVerification()
        print("📧 AUTH: Verification email resent to \(user.email ?? "unknown")")
    }
    
    /// Sign out current user
    func signOut() async throws {
        authState = .signingOut
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            // No need to stop notification listener - handled by NotificationViewModel
            print("🔓 AUTH: Signing out user")
            
            try auth.signOut()
            currentUser = nil
            authState = .unauthenticated
            isEmailVerified = false
            
            // Clear cached verification on sign out
            UserDefaults.standard.removeObject(forKey: CacheKeys.emailVerified)
            
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
            // No need to stop listener - handled by NotificationViewModel
            authState = .unauthenticated
            currentUser = nil
            return
        }
        
        guard authState != .signingIn && authState != .authenticating else {
            print("🔄 AUTH STATE: Skipping state change during authentication process")
            return
        }
        
        if currentUser != nil && authState == .authenticated {
            print("✅ AUTH STATE: Already authenticated with current user")
            return
        }
        
        do {
            currentUser = try await loadUserProfile(userID: user.uid)
            authState = .authenticated
            
            // Update verification status from cached value (no network call)
            isEmailVerified = UserDefaults.standard.bool(forKey: CacheKeys.emailVerified)
            
            // FCM token registration is automatic via FCMPushManager
            print("✅ AUTH: User profile loaded from state change")
        } catch {
            print("⚠️ AUTH: Failed to load user profile in state change: \(error)")
            
            if error.localizedDescription.contains("User profile not found") {
                print("🔍 AUTH: Profile not found - user might be in signup process")
                return
            }
            
            authState = .unauthenticated
            currentUser = nil
        }
    }
    
    // MARK: - User Profile Creation
    
    private func createNewUserProfile(for user: User, providedDisplayName: String? = nil) async throws -> BasicUserInfo {
        let email = user.email ?? ""
        
        print("🔍 CREATING USER PROFILE DEBUG:")
        print("   User UID: \(user.uid)")
        print("   Email: \(email)")
        print("   Database: \(Config.Firebase.databaseName)")
        
        let specialConfig = SpecialUsersConfig.getSpecialUser(for: email)
        
        let username = generateUsername(from: email, id: user.uid)
        let displayName = providedDisplayName ??
                         user.displayName ??
                         specialConfig?.customTitle ??
                         "New User"
        
        let tier = specialConfig?.tierRawValue ?? UserTier.rookie.rawValue
        let startingClout = specialConfig?.startingClout ?? OptimizationConfig.User.defaultStartingClout
        
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
            
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.videoCount: 0,
            FirebaseSchema.UserDocument.threadCount: 0,
            FirebaseSchema.UserDocument.totalHypesReceived: 0,
            FirebaseSchema.UserDocument.totalCoolsReceived: 0,
            
            FirebaseSchema.UserDocument.isPrivate: false,
            FirebaseSchema.UserDocument.isBanned: false,
            
            // Email verification tracking
            "isEmailVerified": false,
            
            "isSpecialUser": specialConfig != nil,
            "specialRole": specialConfig?.role.rawValue ?? NSNull(),
            "specialPerks": specialConfig?.specialPerks ?? [],
            "priority": specialConfig?.priority ?? 0
        ]
        
        if let customBio = specialConfig?.customBio {
            userData["bio"] = customBio
        }
        
        do {
            print("🔍 ATTEMPTING FIRESTORE WRITE...")
            
            try await db.collection(FirebaseSchema.Collections.users)
                .document(user.uid)
                .setData(userData)
            
            print("✅ USER PROFILE: Successfully created for \(user.uid)")
            
            let verifyDoc = try await db.collection(FirebaseSchema.Collections.users)
                .document(user.uid)
                .getDocument()
            
            if verifyDoc.exists {
                print("✅ VERIFICATION: Document exists in Firestore")
            } else {
                print("❌ VERIFICATION: Document does not exist after creation!")
                throw StitchError.authenticationError("Profile creation verification failed")
            }
            
        } catch {
            print("❌ FIRESTORE WRITE FAILED:")
            print("   Error: \(error)")
            throw StitchError.authenticationError("Failed to create user profile: \(error.localizedDescription)")
        }
        
        await autoFollowDefaultAccounts(userID: user.uid)
        
        let basicUserInfo = createBasicUserInfo(from: userData, uid: user.uid)
        
        if let special = specialConfig {
            print("🎉 AUTH: Special user created - \(special.role.displayName): \(username)")
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
        try? auth.signOut()
        currentUser = nil
        authState = .unauthenticated
        lastError = nil
        isLoading = false
        isEmailVerified = false
        UserDefaults.standard.removeObject(forKey: CacheKeys.emailVerified)
        print("🧹 AUTH: User state cleaned")
    }
    
    func helloWorldTest() {
        print("👋 AUTH SERVICE: Complete Hello World - Ready for authentication")
        print("📱 AUTH SERVICE: Current state: \(authState.displayName)")
        print("👤 AUTH SERVICE: Current user: \(currentUser?.username ?? "None")")
        print("🌟 AUTH SERVICE: Special user: \(isSpecialUser)")
        print("📧 AUTH SERVICE: Email verified: \(isEmailVerified)")
        print("✅ AUTH SERVICE: FCM handled by FCMPushManager automatically")
    }
    
    
    // MARK: - Auto-Follow Default Accounts
    
    /// Auto-follow James Fortune and StitchSocial for new users
    /// Sends follow notification via Cloud Function for each account
    private func autoFollowDefaultAccounts(userID: String) async {
        let userService = UserService()
        
        let defaultAccounts = [
            "4ifwg1CxDGbZ9amfPOvl0lMR6982",  // James Fortune
            "L9cfRdqpDMWA9tq12YBh3IkhnGh1"   // StitchSocial
        ]
        
        for accountID in defaultAccounts {
            do {
                try await userService.followUser(followerID: userID, followingID: accountID)
                print("✅ AUTO-FOLLOW: User \(userID) followed \(accountID)")
                
                // Send follow notification — fire and forget
                Task {
                    do {
                        let _ = try await functions.httpsCallable("stitchnoti_sendFollow").call([
                            "recipientID": accountID
                        ])
                        print("🔔 AUTO-FOLLOW: Notification sent to \(accountID)")
                    } catch {
                        print("⚠️ AUTO-FOLLOW: Notification failed for \(accountID): \(error)")
                    }
                }
            } catch {
                print("⚠️ AUTO-FOLLOW: Failed to follow \(accountID): \(error)")
            }
        }
    }
}
