//
//  EditProfileView.swift
//  StitchSocial
//
//  Created by James Garmon on 8/25/25.
//


//
//  EditProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Instagram-Style Profile Editor
//  Dependencies: UserService (Layer 4), BasicUserInfo (Layer 1)
//  Features: Image upload, form validation, real-time character counting
//  ARCHITECTURE COMPLIANT: No business logic, service calls via binding
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    
    // MARK: - Dependencies & Bindings
    
    @ObservedObject var userService: UserService
    @Binding var user: BasicUserInfo
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Form State
    
    @State private var displayName: String
    @State private var bio: String
    @State private var username: String
    @State private var isPrivate: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    
    // MARK: - UI State
    
    @State private var isLoading = false
    @State private var showingUnsavedAlert = false
    @State private var errorMessage: String?
    @State private var usernameAvailable: Bool?
    @State private var isCheckingUsername = false
    
    // MARK: - Validation
    
    private var hasUnsavedChanges: Bool {
        displayName != user.displayName ||
        bio != getCurrentBio() ||
        username != user.username ||
        isPrivate != getCurrentPrivacy() ||
        profileImage != nil
    }
    
    private var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        displayName.count <= 30 &&
        bio.count <= 150 &&
        username.count >= 3 &&
        (usernameAvailable ?? true)
    }
    
    // MARK: - Initialization
    
    init(userService: UserService, user: Binding<BasicUserInfo>) {
        self.userService = userService
        self._user = user
        self._displayName = State(initialValue: user.wrappedValue.displayName)
        self._bio = State(initialValue: "")
        self._username = State(initialValue: user.wrappedValue.username)
        self._isPrivate = State(initialValue: false)
    }
    
    // MARK: - Main Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        profileImageSection
                        formFieldsSection
                        privacySection
                        
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showingUnsavedAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .foregroundColor(isFormValid ? .cyan : .gray)
                    .disabled(!isFormValid || isLoading)
                }
            }
        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .task {
            await loadCurrentProfileData()
        }
    }
    
    // MARK: - Profile Image Section
    
    private var profileImageSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Current/Updated Image
                Group {
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let imageURL = user.profileImageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            defaultAvatarView
                        }
                    } else {
                        defaultAvatarView
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.cyan, lineWidth: 2)
                )
                
                // Edit Overlay
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: 35, y: 35)
            }
            
            Text("Tap to change photo")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task { await loadSelectedImage(newPhoto) }
        }
    }
    
    // MARK: - Form Fields Section
    
    private var formFieldsSection: some View {
        VStack(spacing: 20) {
            // Display Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name")
                    .font(.headline)
                    .foregroundColor(.white)
                
                TextField("Enter display name", text: $displayName)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .onChange(of: displayName) { _, newValue in
                        if newValue.count > 30 {
                            displayName = String(newValue.prefix(30))
                        }
                    }
                
                HStack {
                    Spacer()
                    Text("\(displayName.count)/30")
                        .font(.caption)
                        .foregroundColor(displayName.count > 25 ? .orange : .gray)
                }
            }
            
            // Username Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack {
                    TextField("Enter username", text: $username)
                        .textFieldStyle(ProfileTextFieldStyle())
                        .autocapitalization(.none)
                        .onChange(of: username) { _, newValue in
                            checkUsernameAvailability(newValue)
                        }
                    
                    if isCheckingUsername {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let available = usernameAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(available ? .green : .red)
                    }
                }
                
                if let available = usernameAvailable, !available {
                    Text("Username not available")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Bio Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .font(.headline)
                    .foregroundColor(.white)
                
                TextEditor(text: $bio)
                    .frame(minHeight: 80)
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .onChange(of: bio) { _, newValue in
                        if newValue.count > 150 {
                            bio = String(newValue.prefix(150))
                        }
                    }
                
                HStack {
                    Spacer()
                    Text("\(bio.count)/150")
                        .font(.caption)
                        .foregroundColor(bio.count > 140 ? .orange : .gray)
                }
            }
        }
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy")
                .font(.headline)
                .foregroundColor(.white)
            
            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Account")
                        .foregroundColor(.white)
                    
                    Text("Only followers can see your content")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .tint(.cyan)
        }
    }
    
    // MARK: - Supporting Views
    
    private var defaultAvatarView: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
            )
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentBio() -> String {
        // TODO: Load from current user profile
        return ""
    }
    
    private func getCurrentPrivacy() -> Bool {
        // TODO: Load from current user profile  
        return false
    }
    
    private func loadCurrentProfileData() async {
        // TODO: Load extended profile data including bio and privacy settings
    }
    
    private func loadSelectedImage(_ photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }
        
        do {
            if let data = try await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                
                // Resize image to 512x512
                let resizedImage = image.resized(to: CGSize(width: 512, height: 512))
                await MainActor.run {
                    self.profileImage = resizedImage
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
            }
        }
    }
    
    private func checkUsernameAvailability(_ newUsername: String) {
        guard newUsername != user.username && newUsername.count >= 3 else {
            usernameAvailable = true
            return
        }
        
        isCheckingUsername = true
        usernameAvailable = nil
        
        Task {
            // Simulate username check delay
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                isCheckingUsername = false
                // TODO: Implement real username availability check via UserService
                usernameAvailable = true // Placeholder
            }
        }
    }
    
    private func saveProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Upload new profile image if selected
            if let image = profileImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                let imageURL = try await userService.uploadProfileImage(
                    userID: user.id,
                    imageData: imageData
                )
                
                // Update local user object
                user = BasicUserInfo(
                    id: user.id,
                    username: username,
                    displayName: displayName,
                    tier: user.tier,
                    clout: user.clout,
                    isVerified: user.isVerified,
                    profileImageURL: imageURL,
                    createdAt: user.createdAt
                )
            }
            
            // Update profile text fields
            try await userService.updateProfile(
                userID: user.id,
                displayName: displayName,
                bio: bio,
                isPrivate: isPrivate
            )
            
            // Update local user object
            user = BasicUserInfo(
                id: user.id,
                username: username,
                displayName: displayName,
                tier: user.tier,
                clout: user.clout,
                isVerified: user.isVerified,
                profileImageURL: user.profileImageURL,
                createdAt: user.createdAt
            )
            
            dismiss()
            
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Custom Text Field Style

struct ProfileTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .foregroundColor(.white)
            .autocorrectionDisabled()
    }
}

// MARK: - UIImage Resize Extension

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}