//
//  LoginView.swift
//  StitchSocial
//
//  Layer 8: Views - Authentication Interface
//  Dependencies: AuthService, ReferralService, StitchColors
//  UPDATED: Referral code field at signup + email verification trigger
//  UPDATED: Organic signup tracking for no-referral users
//  FIXED: Proper keyboard handling and text field visibility
//

import SwiftUI

struct LoginView: View {
    
    // MARK: - Authentication Service
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - Form State
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var confirmPassword: String = ""
    @State private var referralCode: String = ""
    @State private var currentMode: AuthMode = .signIn
    
    // MARK: - UI State
    @State private var isLoading: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var animateWelcome: Bool = false
    @State private var referralMessage: String?
    
    // MARK: - Focus State for Keyboard Management
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case email
        case username
        case displayName
        case password
        case confirmPassword
        case referralCode
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
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with logo
                        headerView
                            .padding(.top, 60)
                        
                        // Welcome section
                        welcomeSection
                            .padding(.top, 40)
                        
                        // Authentication form
                        authenticationForm
                            .padding(.horizontal, 24)
                        
                        // Action buttons
                        actionButtons
                            .padding(.horizontal, 24)
                            .id("actionButtons")
                        
                        // Mode switcher
                        modeSwitcher
                            .padding(.bottom, 40)
                        
                        // Extra padding so bottom fields can scroll above keyboard
                        Spacer()
                            .frame(height: 200)
                            .id("bottomSpacer")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { newField in
                    guard let field = newField else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
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
            .id(Field.email)
            
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
                .id(Field.username)
                
                CustomTextField(
                    title: "Display Name",
                    text: $displayName,
                    placeholder: "Your display name",
                    keyboardType: .default,
                    isSecure: false,
                    focusState: $focusedField,
                    field: .displayName
                )
                .id(Field.displayName)
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
            .id(Field.password)
            
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
                .id(Field.confirmPassword)
                
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
                
                // MARK: - Referral Code Field (signup only)
                referralCodeSection
                    .id(Field.referralCode)
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
    
    // MARK: - Referral Code Section
    private var referralCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 4)
            
            Text("Referral Code")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(StitchColors.textSecondary)
            
            HStack(spacing: 12) {
                TextField("Have a code? (optional)", text: $referralCode)
                    .textFieldStyle(StitchTextFieldStyle())
                    .keyboardType(.default)
                    .autocapitalization(.allCharacters)
                    .focused($focusedField, equals: .referralCode)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }
            }
            
            // Referral result message
            if let message = referralMessage {
                HStack(spacing: 4) {
                    Image(systemName: message.contains("✅") ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(message.contains("✅") ? .green : .gray)
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(message.contains("✅") ? .green : .gray)
                    Spacer()
                }
            } else {
                Text("Skip if you don't have one")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(StitchColors.textSecondary.opacity(0.6))
            }
        }
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
            
            // Forgot password (sign in only)
            if currentMode == .signIn {
                Button(action: {
                    // Handle forgot password
                    Task {
                        guard isValidEmail(email) else { return }
                        try? await authService.resetPassword(email: email)
                    }
                }) {
                    Text("Forgot Password?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(StitchColors.primary)
                }
            }
        }
    }
    
    // MARK: - Mode Switcher
    private var modeSwitcher: some View {
        HStack {
            Text(currentMode == .signIn ? "Don't have an account?" : "Already have an account?")
                .font(.system(size: 14))
                .foregroundColor(StitchColors.textSecondary)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentMode = currentMode == .signIn ? .signUp : .signIn
                    clearForm()
                }
            }) {
                Text(currentMode == .signIn ? "Sign Up" : "Sign In")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(StitchColors.primary)
            }
        }
        .opacity(animateWelcome ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.8).delay(1.0), value: animateWelcome)
    }
    
    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(StitchColors.success)
                    .scaleEffect(showingSuccess ? 1.0 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showingSuccess)
                
                Text("Welcome!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Your account is ready to go")
                    .font(.system(size: 16))
                    .foregroundColor(StitchColors.textSecondary)
                
                // Show referral result if applicable
                if let message = referralMessage, message.contains("✅") {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.top, 4)
                }
            }
            .opacity(showingSuccess ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(0.3), value: showingSuccess)
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
    
    // MARK: - Form Validation
    private var isFormValid: Bool {
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
                    // Step 1: Create account (sends verification email automatically)
                    try await authService.signUp(
                        email: email,
                        password: password,
                        displayName: displayName
                    )
                    
                    // Step 2: Process referral or track organic signup
                    if let firebaseUser = authService.currentUser {
                        await processReferralAtSignup(newUserID: firebaseUser.id)
                    }
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
    
    // MARK: - Referral Processing at Signup
    
    /// Process referral code or track organic signup
    /// Called after successful account creation
    private func processReferralAtSignup(newUserID: String) async {
        print("🔥 LOGIN: processReferralAtSignup called for \(newUserID)")
        print("🔥 LOGIN: referralCode field value: '\(referralCode)'")
        
        let referralService = ReferralService()
        let trimmedCode = referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedCode.isEmpty {
            // No referral code — track as organic signup
            await referralService.processOrganicSignup(newUserID: newUserID)
            print("📊 LOGIN: Organic signup tracked for \(newUserID)")
        } else {
            // Has referral code — validate and process with auto-follow
            do {
                let result = try await referralService.processReferralSignup(
                    referralCode: trimmedCode,
                    newUserID: newUserID,
                    platform: "ios",
                    sourceType: .manual
                )
                
                await MainActor.run {
                    if result.success {
                        referralMessage = "✅ \(result.message)"
                        if let referrerID = result.referrerID {
                            print("✅ LOGIN: Referral processed — now following \(referrerID)")
                        }
                    } else {
                        referralMessage = result.message
                        // Still track as organic if code failed
                        Task {
                            await referralService.processOrganicSignup(newUserID: newUserID)
                        }
                    }
                }
            } catch {
                print("⚠️ LOGIN: Referral processing failed: \(error) — tracking as organic")
                await referralService.processOrganicSignup(newUserID: newUserID)
                await MainActor.run {
                    referralMessage = "Code not found — signed up without referral"
                }
            }
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        username = ""
        displayName = ""
        confirmPassword = ""
        referralCode = ""
        referralMessage = nil
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
            focusState.wrappedValue = .referralCode
        case .referralCode:
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
