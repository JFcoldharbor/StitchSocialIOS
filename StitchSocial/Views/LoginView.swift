//
//  LoginView.swift
//  StitchSocial
//
//  Layer 8: Views - Authentication Interface
//  Dependencies: AuthService, StitchColors
//  FIXED: Proper keyboard handling and text field visibility
//  UPDATED: Added Terms & Conditions + Safety Policy acceptance checkbox
//           Saves acceptedTermsAt / acceptedTermsVersion to Firestore user doc on auth
//
//  CACHING NOTE: acceptedTermsAt is a one-time write per login session.
//  If you add a "force re-accept on policy update" flow later, cache the
//  accepted version string in UserDefaults to avoid a Firestore read on every
//  cold launch. Add that to your caching optimization file when implemented.
//

import SwiftUI
import FirebaseFirestore

struct LoginView: View {
    
    // MARK: - Authentication Service
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - Form State
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var confirmPassword: String = ""
    @State private var currentMode: AuthMode = .signIn
    @State private var acceptedTerms: Bool = false
    
    // MARK: - UI State
    @State private var isLoading: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var animateWelcome: Bool = false
    
    // MARK: - Focus State for Keyboard Management
    @FocusState private var focusedField: Field?
    
    // MARK: - Legal URLs
    private let termsURL = URL(string: "https://stitchsocial.me/privacy")!
    private let safetyURL = URL(string: "https://stitchsocial.me/privacy")!
    private let privacyURL = URL(string: "https://stitchsocial.me/privacy")!
    
    // MARK: - Terms Version (bump when policies change to force re-acceptance)
    private let currentTermsVersion = "1.0"
    
    enum Field: Hashable {
        case email
        case username
        case displayName
        case password
        case confirmPassword
    }
    
    enum AuthMode: CaseIterable {
        case signIn
        case signUp
        
        var title: String {
            switch self {
            case .signIn: return "Welcome Back"
            case .signUp: return "Join Stitch Social"
            }
        }
        
        var subtitle: String {
            switch self {
            case .signIn: return "Sign in to continue your creative journey"
            case .signUp: return "Create your conversation account"
            }
        }
        
        var buttonText: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            // Main content with proper keyboard handling
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with logo
                        headerView
                            .padding(.top, max(50, geometry.safeAreaInsets.top + 20))
                        
                        // Welcome section
                        welcomeSection
                            .padding(.top, 40)
                        
                        // Authentication form
                        authenticationForm
                            .padding(.horizontal, 24)
                        
                        // Terms acceptance checkbox + legal links
                        termsAcceptanceView
                            .padding(.horizontal, 24)
                        
                        // Action buttons
                        actionButtons
                            .padding(.horizontal, 24)
                        
                        // Mode switcher
                        modeSwitcher
                            .padding(.bottom, 40)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            
            // Success overlay
            if showingSuccess {
                successOverlay
            }
            
            // Loading overlay
            if isLoading {
                loadingOverlay
            }
        }
        .onTapGesture {
            focusedField = nil // Dismiss keyboard when tapping outside
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animateWelcome = true
            }
        }
    }
    
    // MARK: - Background View
    private var backgroundView: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating particles
            ForEach(0..<20, id: \.self) { index in
                Circle()
                    .fill(StitchColors.primary.opacity(0.1))
                    .frame(width: CGFloat.random(in: 2...8))
                    .position(
                        x: animateWelcome ?
                           CGFloat.random(in: 0...UIScreen.main.bounds.width) :
                           CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: animateWelcome ?
                           CGFloat.random(in: 0...UIScreen.main.bounds.height) :
                           CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 3...6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: animateWelcome
                    )
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            // App logo from Assets
            Image("StitchSocialLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .scaleEffect(animateWelcome ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 0.8), value: animateWelcome)
            
            // App name
            Text("Stitch Social")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .opacity(animateWelcome ? 1.0 : 0.0)
                .offset(y: animateWelcome ? 0 : 20)
                .animation(.easeInOut(duration: 0.8).delay(0.2), value: animateWelcome)
        }
    }
    
    // MARK: - Welcome Section
    private var welcomeSection: some View {
        VStack(spacing: 16) {
            // Title
            Text(currentMode.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .opacity(animateWelcome ? 1.0 : 0.0)
                .offset(y: animateWelcome ? 0 : 20)
                .animation(.easeInOut(duration: 0.8).delay(0.2), value: animateWelcome)
            
            // Subtitle
            Text(currentMode.subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(StitchColors.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(animateWelcome ? 1.0 : 0.0)
                .offset(y: animateWelcome ? 0 : 20)
                .animation(.easeInOut(duration: 0.8).delay(0.4), value: animateWelcome)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Authentication Form
    private var authenticationForm: some View {
        VStack(spacing: 20) {
            // Email field
            CustomTextField(
                title: "Email",
                text: $email,
                placeholder: "Enter your email",
                keyboardType: .emailAddress,
                isSecure: false,
                focusState: $focusedField,
                field: .email
            )
            
            // Username field (sign up only)
            if currentMode == .signUp {
                CustomTextField(
                    title: "Username",
                    text: $username,
                    placeholder: "Choose a username",
                    keyboardType: .default,
                    isSecure: false,
                    focusState: $focusedField,
                    field: .username
                )
                
                CustomTextField(
                    title: "Display Name",
                    text: $displayName,
                    placeholder: "Your display name",
                    keyboardType: .default,
                    isSecure: false,
                    focusState: $focusedField,
                    field: .displayName
                )
            }
            
            // Password field
            CustomTextField(
                title: "Password",
                text: $password,
                placeholder: "Enter your password",
                keyboardType: .default,
                isSecure: true,
                focusState: $focusedField,
                field: .password
            )
            
            // Password requirements (sign up only)
            if currentMode == .signUp && !password.isEmpty {
                passwordRequirementsView
            }
            
            // Confirm password (sign up only)
            if currentMode == .signUp {
                CustomTextField(
                    title: "Confirm Password",
                    text: $confirmPassword,
                    placeholder: "Confirm your password",
                    keyboardType: .default,
                    isSecure: true,
                    focusState: $focusedField,
                    field: .confirmPassword
                )
                
                if !confirmPassword.isEmpty && password != confirmPassword {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(StitchColors.error)
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundColor(StitchColors.error)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
        )
        .opacity(animateWelcome ? 1.0 : 0.0)
        .offset(y: animateWelcome ? 0 : 20)
        .animation(.easeInOut(duration: 0.8).delay(0.6), value: animateWelcome)
    }
    
    // MARK: - Terms Acceptance View
    private var termsAcceptanceView: some View {
        VStack(spacing: 12) {
            // Checkbox row
            Button(action: { acceptedTerms.toggle() }) {
                HStack(alignment: .top, spacing: 12) {
                    // Checkbox
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(acceptedTerms ? StitchColors.primary : StitchColors.textSecondary)
                    
                    // Agreement text with tappable links
                    agreementText
                }
            }
            .buttonStyle(.plain)
            
            // Legal links row
            HStack(spacing: 16) {
                Link(destination: termsURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text("Terms")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(StitchColors.primary)
                }
                
                Link(destination: safetyURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 10))
                        Text("Safety")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(StitchColors.primary)
                }
                
                Link(destination: privacyURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text("Privacy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(StitchColors.primary)
                }
            }
        }
        .opacity(animateWelcome ? 1.0 : 0.0)
        .offset(y: animateWelcome ? 0 : 20)
        .animation(.easeInOut(duration: 0.8).delay(0.7), value: animateWelcome)
    }
    
    // MARK: - Agreement Text
    private var agreementText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("I agree to the ")
                .font(.system(size: 13))
                .foregroundColor(StitchColors.textSecondary)
            +
            Text("Terms & Conditions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(StitchColors.primary)
            +
            Text(", ")
                .font(.system(size: 13))
                .foregroundColor(StitchColors.textSecondary)
            +
            Text("Safety Policy")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(StitchColors.primary)
            +
            Text(", and ")
                .font(.system(size: 13))
                .foregroundColor(StitchColors.textSecondary)
            +
            Text("Privacy Policy")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(StitchColors.primary)
        }
        .multilineTextAlignment(.leading)
    }
    
    // MARK: - Password Requirements View
    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: password.count >= 6 ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(password.count >= 6 ? StitchColors.success : StitchColors.textSecondary)
                Text("At least 6 characters")
                    .font(.caption)
                    .foregroundColor(password.count >= 6 ? StitchColors.success : StitchColors.textSecondary)
                Spacer()
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary action button
            Button(action: performPrimaryAction) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(currentMode.buttonText)
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isFormValid && !isLoading ? StitchColors.primary : StitchColors.border)
                )
            }
            .disabled(!isFormValid || isLoading)
            .opacity(animateWelcome ? 1.0 : 0.0)
            .offset(y: animateWelcome ? 0 : 20)
            .animation(.easeInOut(duration: 0.8).delay(0.8), value: animateWelcome)
            
            // Terms reminder if not accepted
            if !acceptedTerms {
                Text("Please accept the Terms & Conditions to continue")
                    .font(.system(size: 11))
                    .foregroundColor(StitchColors.textSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Mode Switcher
    private var modeSwitcher: some View {
        VStack(spacing: 12) {
            HStack {
                Text(currentMode == .signIn ? "Don't have an account?" : "Already have an account?")
                    .font(.system(size: 14))
                    .foregroundColor(StitchColors.textSecondary)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentMode = currentMode == .signIn ? .signUp : .signIn
                        // Clear form when switching modes
                        clearForm()
                    }
                }) {
                    Text(currentMode == .signIn ? "Sign Up" : "Sign In")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(StitchColors.primary)
                }
            }
            .opacity(animateWelcome ? 1.0 : 0.0)
            .offset(y: animateWelcome ? 0 : 20)
            .animation(.easeInOut(duration: 0.8).delay(1.0), value: animateWelcome)
        }
    }
    
    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Use real logo with checkmark overlay
                ZStack {
                    Image("StitchSocialLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                    
                    // Success checkmark badge
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(StitchColors.success)
                        .background(Circle().fill(Color.black).frame(width: 28, height: 28))
                        .offset(x: 35, y: 35)
                }
                
                VStack(spacing: 8) {
                    Text("Welcome to Stitch!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Your account is ready to go")
                        .font(.system(size: 16))
                        .foregroundColor(StitchColors.textSecondary)
                }
                .opacity(showingSuccess ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.3), value: showingSuccess)
            }
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: StitchColors.primary))
                    .scaleEffect(1.5)
                
                Text("Authenticating...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Form Validation (now requires acceptedTerms)
    private var isFormValid: Bool {
        guard acceptedTerms else { return false }
        
        switch currentMode {
        case .signIn:
            return isValidEmail(email) && password.count >= 6
        case .signUp:
            return isValidEmail(email) &&
                   !username.isEmpty &&
                   !displayName.isEmpty &&
                   password.count >= 6 &&
                   password == confirmPassword
        }
    }
    
    // MARK: - Actions
    private func performPrimaryAction() {
        focusedField = nil // Dismiss keyboard
        isLoading = true
        
        Task {
            do {
                switch currentMode {
                case .signIn:
                    try await authService.signIn(email: email, password: password)
                case .signUp:
                    try await authService.signUp(
                        email: email,
                        password: password,
                        displayName: displayName
                    )
                }
                
                // Show success state
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showingSuccess = true
                    }
                }
                
                // Post-login setup: developer bypass + auto-join official community
                if let firebaseUser = authService.currentUser {
                    // Set developer email for subscription bypass
                    SubscriptionService.shared.setCurrentUserEmail(email)
                    
                    // Save terms acceptance to Firestore (single batched write)
                    await saveTermsAcceptance(userID: firebaseUser.id)
                    
                    // Auto-join Stitch Social official community
                    await CommunityService.shared.autoJoinOfficialCommunity(
                        userID: firebaseUser.id,
                        username: firebaseUser.username,
                        displayName: firebaseUser.displayName
                    )
                }
                
                // Auto-dismiss success after 2 seconds
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    showingSuccess = false
                }
                
            } catch {
                print("Authentication error: \(error)")
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - Save Terms Acceptance to Firestore
    /// Writes acceptedTermsAt + version to user doc in a single merge write.
    /// No caching needed here — this is a one-time write per auth session.
    /// If you later need to CHECK acceptance on app launch, cache the version
    /// in UserDefaults to avoid a Firestore read every cold start.
    private func saveTermsAcceptance(userID: String) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userID)
        
        let termsData: [String: Any] = [
            "acceptedTermsAt": FieldValue.serverTimestamp(),
            "acceptedTermsVersion": currentTermsVersion,
            "acceptedSafetyPolicy": true,
            "acceptedPrivacyPolicy": true
        ]
        
        do {
            try await userRef.setData(termsData, merge: true)
            print("✅ Terms acceptance saved for user: \(userID)")
        } catch {
            print("❌ Failed to save terms acceptance: \(error.localizedDescription)")
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        username = ""
        displayName = ""
        confirmPassword = ""
        acceptedTerms = false
        focusedField = nil
    }
    
    // MARK: - Email Validation
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    var focusState: FocusState<LoginView.Field?>.Binding
    let field: LoginView.Field
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(StitchColors.textSecondary)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(StitchTextFieldStyle())
                    .keyboardType(keyboardType)
                    .focused(focusState, equals: field)
                    .submitLabel(.next)
                    .onSubmit {
                        advanceToNextField()
                    }
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(StitchTextFieldStyle())
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                    .focused(focusState, equals: field)
                    .submitLabel(.next)
                    .onSubmit {
                        advanceToNextField()
                    }
            }
        }
    }
    
    private func advanceToNextField() {
        switch field {
        case .email:
            focusState.wrappedValue = .username
        case .username:
            focusState.wrappedValue = .displayName
        case .displayName:
            focusState.wrappedValue = .password
        case .password:
            focusState.wrappedValue = .confirmPassword
        case .confirmPassword:
            focusState.wrappedValue = nil
        }
    }
}

// MARK: - Enhanced Text Field Style
struct StitchTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .font(.system(size: 16))
            .accentColor(StitchColors.primary)
    }
}

// MARK: - Preview
#Preview {
    LoginView()
        .environmentObject(AuthService())
        .preferredColorScheme(.dark)
}
