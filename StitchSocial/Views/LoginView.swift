//
//  LoginView.swift
//  CleanBeta
//
//  Layer 8: Views - Authentication Interface
//  Uses existing AuthService.swift (Layer 4) - Zero new dependencies
//  Clean integration with existing architecture
//

import SwiftUI
import FirebaseAuth

/// Clean login interface using existing AuthService
struct LoginView: View {
    
    // MARK: - Dependencies (Existing Architecture)
    @EnvironmentObject private var authService: AuthService
    
    // MARK: - Authentication State
    @State private var currentMode: AuthMode = .signIn
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // MARK: - Form Fields
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    
    // MARK: - UI State
    @State private var animateWelcome = false
    @State private var showingSuccess = false
    
    // MARK: - Authentication Modes
    enum AuthMode: CaseIterable {
        case signIn
        case signUp
        case anonymous
        
        var title: String {
            switch self {
            case .signIn: return "Welcome Back"
            case .signUp: return "Join CleanBeta"
            case .anonymous: return "Try CleanBeta"
            }
        }
        
        var subtitle: String {
            switch self {
            case .signIn: return "Sign in to continue your journey"
            case .signUp: return "Create your video conversation account"
            case .anonymous: return "Explore without signing up"
            }
        }
        
        var buttonText: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            case .anonymous: return "Continue as Guest"
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            // Main content
            VStack(spacing: 0) {
                // Header with logo
                headerView
                    .padding(.top, 50)
                
                // Form content
                ScrollView {
                    VStack(spacing: 24) {
                        // Welcome section
                        welcomeSection
                            .padding(.top, 40)
                        
                        // Authentication form
                        if currentMode != .anonymous {
                            authenticationForm
                                .padding(.horizontal, 24)
                        }
                        
                        // Action buttons
                        actionButtons
                            .padding(.horizontal, 24)
                        
                        // Mode switcher
                        modeSwitcher
                            .padding(.bottom, 40)
                    }
                }
                .keyboardAdaptive()
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
        .onAppear {
            startWelcomeAnimation()
        }
        .onChange(of: authService.authState) { state in
            handleAuthStateChange(state)
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Background View
    private var backgroundView: some View {
        ZStack {
            // Base background
            StitchColors.background
                .ignoresSafeArea()
            
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    StitchColors.primary.opacity(0.3),
                    StitchColors.secondary.opacity(0.2),
                    StitchColors.background
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated particles
            if animateWelcome {
                ForEach(0..<15, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 2...6))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
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
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // CleanBeta logo
            HStack(spacing: 12) {
                // Logo Image - Replace with your actual logo
                Group {
                    if let logoImage = UIImage(named: "cleanBetaLogo") {
                        Image(uiImage: logoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    } else if let logoImage = UIImage(named: "AppIcon") {
                        Image(uiImage: logoImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // Fallback logo design
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(StitchColors.primary)
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "video.and.waveform")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Text("CleanBeta")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(StitchColors.textPrimary)
            }
            .opacity(animateWelcome ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 1.0).delay(0.3), value: animateWelcome)
            
            Spacer()
            
            // Beta badge
            Text("BETA")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(StitchColors.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(StitchColors.primary.opacity(0.2))
                .cornerRadius(6)
                .opacity(animateWelcome ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateWelcome)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Welcome Section
    private var welcomeSection: some View {
        VStack(spacing: 16) {
            // Main title
            Text(currentMode.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(StitchColors.textPrimary)
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
                isSecure: false
            )
            
            // Username field (sign up only)
            if currentMode == .signUp {
                CustomTextField(
                    title: "Username",
                    text: $username,
                    placeholder: "Choose a username",
                    keyboardType: .default,
                    isSecure: false
                )
                
                CustomTextField(
                    title: "Display Name",
                    text: $displayName,
                    placeholder: "Your display name",
                    keyboardType: .default,
                    isSecure: false
                )
            }
            
            // Password field
            CustomTextField(
                title: "Password",
                text: $password,
                placeholder: "Enter your password",
                keyboardType: .default,
                isSecure: true
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
                    isSecure: true
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
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .opacity(animateWelcome ? 1.0 : 0.0)
        .offset(y: animateWelcome ? 0 : 30)
        .animation(.easeInOut(duration: 0.8).delay(0.6), value: animateWelcome)
    }
    
    // MARK: - Password Requirements View
    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Password Requirements:")
                .font(.caption)
                .foregroundColor(StitchColors.textSecondary)
            
            PasswordRequirement(text: "At least 8 characters", isMet: password.count >= 8)
            PasswordRequirement(text: "Contains uppercase letter", isMet: password.contains { $0.isUppercase })
            PasswordRequirement(text: "Contains lowercase letter", isMet: password.contains { $0.isLowercase })
            PasswordRequirement(text: "Contains number", isMet: password.contains { $0.isNumber })
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
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFormValid ? StitchColors.primary : StitchColors.border)
                )
            }
            .disabled(!isFormValid || isLoading)
            .opacity(animateWelcome ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.8).delay(0.8), value: animateWelcome)
        }
    }
    
    // MARK: - Mode Switcher
    private var modeSwitcher: some View {
        VStack(spacing: 12) {
            // Divider
            HStack {
                Rectangle()
                    .fill(StitchColors.border)
                    .frame(height: 1)
                
                Text("or")
                    .font(.system(size: 14))
                    .foregroundColor(StitchColors.textSecondary)
                    .padding(.horizontal, 16)
                
                Rectangle()
                    .fill(StitchColors.border)
                    .frame(height: 1)
            }
            
            // Mode switch buttons
            HStack(spacing: 16) {
                if currentMode != .signUp {
                    Button("Sign Up") {
                        switchToMode(.signUp)
                    }
                    .foregroundColor(StitchColors.primary)
                }
                
                if currentMode != .signIn {
                    Button("Sign In") {
                        switchToMode(.signIn)
                    }
                    .foregroundColor(StitchColors.primary)
                }
                
                if currentMode != .anonymous {
                    Button("Guest Mode") {
                        switchToMode(.anonymous)
                    }
                    .foregroundColor(StitchColors.secondary)
                }
            }
            .font(.system(size: 16, weight: .medium))
        }
        .opacity(animateWelcome ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.8).delay(1.0), value: animateWelcome)
    }
    
    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Success icon
                Circle()
                    .fill(StitchColors.success)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(showingSuccess ? 1.0 : 0.1)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showingSuccess)
                
                // Success message
                VStack(spacing: 8) {
                    Text("Welcome to CleanBeta!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(StitchColors.textPrimary)
                    
                    Text("Ready to start creating video conversations")
                        .font(.system(size: 16))
                        .foregroundColor(StitchColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showingSuccess ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(0.3), value: showingSuccess)
            }
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Authenticating...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(StitchColors.textPrimary)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        switch currentMode {
        case .signIn:
            return !email.isEmpty && !password.isEmpty && isValidEmail(email)
        case .signUp:
            return !email.isEmpty && !username.isEmpty && !password.isEmpty &&
                   !displayName.isEmpty && password == confirmPassword &&
                   isValidEmail(email) && isValidPassword(password)
        case .anonymous:
            return true
        }
    }
    
    // MARK: - Actions
    
    private func performPrimaryAction() {
        guard isFormValid && !isLoading else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                switch currentMode {
                case .signIn:
                    // Use Firebase Auth directly for sign in
                    let _ = try await Auth.auth().signIn(withEmail: email, password: password)
                    
                case .signUp:
                    // Use Firebase Auth directly for sign up
                    let result = try await Auth.auth().createUser(withEmail: email, password: password)
                    
                    // Create user profile using UserService
                    // This would be handled by AuthService listener
                    
                case .anonymous:
                    // Use existing AuthService method
                    try await authService.signInAnonymously()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func handleAuthStateChange(_ state: AuthState) {
        switch state {
        case .authenticated:
            isLoading = false
            showSuccessAndTransition()
        case .error:
            isLoading = false
            errorMessage = "Authentication failed"
            showingError = true
        case .authenticating:
            isLoading = true
        default:
            isLoading = false
        }
    }
    
    private func showSuccessAndTransition() {
        showingSuccess = true
        
        // Transition to main app after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showingSuccess = false
            }
        }
    }
    
    private func switchToMode(_ mode: AuthMode) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentMode = mode
            clearForm()
        }
    }
    
    private func startWelcomeAnimation() {
        withAnimation(.easeInOut(duration: 0.8)) {
            animateWelcome = true
        }
    }
    
    private func clearForm() {
        email = ""
        username = ""
        password = ""
        confirmPassword = ""
        displayName = ""
        errorMessage = ""
        showingError = false
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.contains { $0.isUppercase } &&
               password.contains { $0.isLowercase } &&
               password.contains { $0.isNumber }
    }
}

// MARK: - Custom TextField Component

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    
    @State private var isSecureVisible = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            HStack {
                if isSecure && !isSecureVisible {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(AuthTextFieldStyle())
                        .keyboardType(keyboardType)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(AuthTextFieldStyle())
                        .keyboardType(keyboardType)
                        .focused($isFocused)
                }
                
                if isSecure {
                    Button(action: { isSecureVisible.toggle() }) {
                        Image(systemName: isSecureVisible ? "eye.slash" : "eye")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 16))
                    }
                    .padding(.trailing, 12)
                }
            }
        }
    }
}

// MARK: - Auth Text Field Style

struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

// MARK: - Password Requirement Component

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? StitchColors.success : StitchColors.textTertiary)
                .font(.system(size: 12))
            
            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? StitchColors.success : StitchColors.textSecondary)
            
            Spacer()
        }
    }
}

// MARK: - Keyboard Adaptive Modifier (Simplified)

struct KeyboardAdaptive: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Keyboard will show - content automatically adjusts with ScrollView
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                // Keyboard will hide - content automatically adjusts
            }
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        modifier(KeyboardAdaptive())
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
