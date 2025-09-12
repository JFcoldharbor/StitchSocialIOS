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
    @State private var currentBio = ""
    @State private var currentPrivacy = false
    
    // MARK: - Validation
    
    private var hasUnsavedChanges: Bool {
        displayName != user.displayName ||
        bio != currentBio ||
        username != user.username ||
        isPrivate != currentPrivacy ||
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
        VStack(spacing: 16) {
            // Display Name
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Display Name")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(displayName.count)/30")
                        .font(.caption)
                        .foregroundColor(displayName.count > 30 ? .red : .gray)
                }
                
                TextField("Enter display name", text: $displayName)
                    .textFieldStyle(ProfileTextFieldStyle())
            }
            
            // Username
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Username")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if isCheckingUsername {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.cyan)
                    } else if let available = usernameAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(available ? .green : .red)
                    }
                }
                
                TextField("Enter username", text: $username)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .onChange(of: username) { _, newValue in
                        Task { await checkUsernameAvailability(newValue) }
                    }
            }
            
            // Bio
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bio")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(bio.count)/150")
                        .font(.caption)
                        .foregroundColor(bio.count > 150 ? .red : .gray)
                }
                
                TextField("Tell us about yourself", text: $bio, axis: .vertical)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .lineLimit(3...6)
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
    
    // MARK: - Helper Methods - FIXED IMPLEMENTATIONS
    
    private func loadCurrentProfileData() async {
        do {
            // Load extended profile data from Firebase
            if let profileData = try await userService.getExtendedProfile(id: user.id) {
                await MainActor.run {
                    self.currentBio = profileData.bio
                    self.currentPrivacy = profileData.isPrivate
                    self.bio = profileData.bio
                    self.isPrivate = profileData.isPrivate
                }
                print("EDIT PROFILE: Loaded current bio and privacy settings")
            }
        } catch {
            print("EDIT PROFILE ERROR: Failed to load profile data - \(error)")
            errorMessage = "Failed to load profile data"
        }
    }
    
    private func loadSelectedImage(_ photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }
        
        do {
            if let imageData = try await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: imageData) {
                
                await MainActor.run {
                    // Resize image for efficiency
                    let targetSize = CGSize(width: 400, height: 400)
                    self.profileImage = image.resized(to: targetSize)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load selected image"
            }
        }
    }
    
    private func checkUsernameAvailability(_ username: String) async {
        guard username.count >= 3, username != user.username else {
            usernameAvailable = true
            return
        }
        
        isCheckingUsername = true
        
        // Simulate check delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            isCheckingUsername = false
            // TODO: Implement real username availability check via UserService
            usernameAvailable = true // Placeholder
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
                
                // Update local user object with new image
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
            
            // Update profile text fields - FIXED WITH USERNAME SUPPORT
            try await userService.updateProfile(
                userID: user.id,
                displayName: displayName,
                bio: bio,
                isPrivate: isPrivate,
                username: username
            )
            
            // Update local user object with all changes
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
            
            print("EDIT PROFILE: Successfully saved profile changes")
            dismiss()
            
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            print("EDIT PROFILE ERROR: \(error)")
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
