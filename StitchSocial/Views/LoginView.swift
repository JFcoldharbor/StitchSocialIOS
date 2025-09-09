//
//  LoginView.swift
//  StitchSocial
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
        
        var title: String {
            switch self {
            case .signIn: return "Welcome Back"
            case .signUp: return "Join Stitch Social"
            }
        }
        
        var subtitle: String {
            switch self {
            case .signIn: return "Sign in to continue your journey"
            case .signUp: return "Create your video conversation account"
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
                        authenticationForm
                            .padding(.horizontal, 24)
                        
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
        VStack(spacing: 16) {
            // App logo - Use your actual logo here
            ZStack {
                // Background circle for logo
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [StitchColors.primary, StitchColors.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                // Replace this with your actual logo image
                // Image("stitch_logo") // Uncomment and use your logo asset
                // For now, using system icon as placeholder
                Image(systemName: "video.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
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
        .offset(y: animateWelcome ? 0 : 20)
        .animation(.easeInOut(duration: 0.8).delay(0.6), value: animateWelcome)
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
            
            // Mode switch buttons - Only Sign In/Sign Up
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
                    Text("Welcome to Stitch Social!")
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
        guard isFormValid && !isLoading else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                switch currentMode {
                case .signIn:
                    // Use AuthService directly for sign in
                    _ = try await authService.signIn(email: email, password: password)
                    
                case .signUp:
                    // Use AuthService directly for sign up
                    _ = try await authService.signUp(email: email, password: password, displayName: displayName)
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
    
    private func sendPasswordReset() {
        guard !email.isEmpty && isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            showingError = true
            return
        }
        
        Task {
            do {
                try await authService.resetPassword(email: email)
                await MainActor.run {
                    errorMessage = "Password reset email sent to \(email)"
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to send password reset email: \(error.localizedDescription)"
                    showingError = true
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
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(StitchColors.textSecondary)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(StitchTextFieldStyle())
                    .keyboardType(keyboardType)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(StitchTextFieldStyle())
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
            }
        }
    }
}

// MARK: - Text Field Style
struct StitchTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .font(.system(size: 16))
    }
}

// MARK: - Keyboard Adaptive Modifier
extension View {
    func keyboardAdaptive() -> some View {
        self.modifier(KeyboardAdaptive())
    }
}

struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    keyboardHeight = keyboardFrame.cgRectValue.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
    }
}

// MARK: - Preview
#Preview {
    LoginView()
        .environmentObject(AuthService())
        .preferredColorScheme(.dark)
}
